import AppKit
import WebKit
import AVFoundation
import Speech

extension JarvisApp {
    func resultFile(_ id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        let tag = " " + id.prefix(8).lowercased() + ".md"
        guard let name = (try? FileManager.default.contentsOfDirectory(atPath: resultsDirectory.path))?.first(where: { $0.hasSuffix(tag) }) else { return nil }
        return resultsDirectory.appendingPathComponent(name)
    }
    /// Attach explicitly registered, independently supervised films without starting another renderer.
    func filmJSON(_ url: URL) -> [String:Any]? {
        guard let data = try? Data(contentsOf:url) else { return nil }
        return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
    }
    func refreshExternalFilms() {
        let folders = (try? FileManager.default.contentsOfDirectory(at:workspace.appendingPathComponent("Video"),includingPropertiesForKeys:nil)) ?? []
        var records = ledger.load()
        for folder in folders {
            guard let registration = filmJSON(folder.appendingPathComponent("external-task.json")),
                  let id = registration["id"] as? String, UUID(uuidString:id) != nil,
                  let state = filmJSON(folder.appendingPathComponent("film-state.json")),
                  let supervisor = filmJSON(folder.appendingPathComponent("supervisor.json")),
                  let spec = filmJSON(folder.appendingPathComponent("job.json")),let total = spec["seconds"] as? Int,
                  let plan = filmJSON(folder.appendingPathComponent("plan.json")),
                  let data = try? JSONSerialization.data(withJSONObject:plan),let raw = String(data:data,encoding:.utf8),
                  let parsed = VideoPlan.parse(raw,renderer:.comfy,total:total) else { continue }
            externalFilms[id] = folder
            let delivery = filmJSON(folder.appendingPathComponent("delivery-status.json")) ?? [:]
            let upload = filmJSON(folder.appendingPathComponent("social-upload-status.json")) ?? [:]
            let status = supervisor["status"] as? String ?? "unknown"
            let heartbeat = supervisor["heartbeat"] as? Double ?? 0
            let stale = Date().timeIntervalSince1970 - heartbeat > 90
            let complete = delivery["stage"] as? String == "Completed — video ready"
            let failed = ["needs_attention","cancelled"].contains(status) || (stale && status != "completed") || delivery["stage"] as? String == "Needs attention"
            var job = videoJobs[id] ?? VideoPlan.Progress(taskID:id)
            job.loadDirected(parsed,total:parsed.seconds)
            job.renderer = "4090 · FLUX.2 → LTX-2.3"
            let clips = state["clips"] as? [String:Any] ?? [:]
            let scenes = state["scenes"] as? [String:Any] ?? [:]
            for i in job.shots.indices {
                job.shots[i].state = clips[String(i)] == nil ? "queued" : "done"
                job.shots[i].pipelinePhase = scenes[String(i)] == nil ? "scene" : "scene_ready"
            }
            job.note = stale && !complete && status != "completed" ? "Supervisor heartbeat missing; checkpoints retained" : (supervisor["reason"] as? String ?? state["status"] as? String ?? "Working")
            job.note = "\(clips.count)/\(job.shots.count) clips accepted · " + job.note
            job.stage = failed ? .failed : complete ? .finished : status == "completed" ? .joining : .rendering
            job.ended = failed || complete ? Date() : nil
            if complete { job.note = upload["stage"] as? String ?? "Completed — video ready" }
            videoJobs[id] = job;publishVideo(id)
            let taskState = status == "cancelled" ? "cancelled" : failed ? "failed" : complete ? "completed" : "running"
            if let i = records.firstIndex(where:{$0.id == id}) {
                records[i].state = taskState;records[i].resultSummary = job.note;records[i].updatedAt = TaskLedger.timestamp()
            } else {
                records.insert(TaskRecord(id:id,state:taskState,verified:false,owner:"creative",createdAt:TaskLedger.timestamp(),updatedAt:TaskLedger.timestamp(),resultSummary:job.note,title:parsed.title),at:0)
            }
        }
        if !externalFilms.isEmpty { publishTasks(records) }
    }
    func publishTasks(_ records: [TaskRecord], save: Bool = true) {
        // Older builds listed the Operations manager and model roster as "proposed" rows on every run; they never needed approval.
        let records = records.filter { $0.owner != "operations-manager" && $0.owner != "operations-workers" }
        if save { try? ledger.save(records) }
        let saved = Set((try? FileManager.default.contentsOfDirectory(atPath: resultsDirectory.path))?.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3).suffix(8)) } ?? [])
        send("taskUpdate", records.map { record -> [String: Any] in
            var item = record.payload
            if saved.contains(String(record.id.prefix(8)).lowercased()), let file = resultFile(record.id) {
                item["hasResult"] = true
                item["savedRecordPath"] = "Jarvis Workspace/Results/" + file.lastPathComponent
            }
            if let story = loadFilmStory(),story.id == record.id,story.phase == "awaiting_approval" {
                item["storyHash"] = story.hash
            }
            if TaskLedger.isQueued(record) { item["queued"] = true }
            return item
        })
    }
    /// The full result as a document Brandon can open. The ledger keeps only a summary.
    func saveResult(_ id: String, title: String, director: String, text: String) {
        guard UUID(uuidString: id) != nil else { return }
        try? FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
        let name = resultBase(id, title: title) + ".md"
        let document = "# \(title)\n\n\(director) · \(TaskLedger.timestamp())\n\n---\n\n\(text)\n"
        try? document.write(to: resultsDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    /// "<date> <title words> <first 8 of the id>": the result document's name, and the folder name for files a task produces.
    func resultBase(_ id: String, title: String) -> String {
        if let existing = resultFile(id) { return String(existing.deletingPathExtension().lastPathComponent) }
        let slug = title.replacingOccurrences(of: "[^A-Za-z0-9 ]+", with: " ", options: .regularExpression).split(separator: " ").prefix(8).joined(separator: " ")
        return "\(TaskLedger.timestamp().prefix(10)) \(slug.prefix(60)) \(id.prefix(8).lowercased())"
    }
    /// Opens the finished video when the task made one, otherwise the result document.
    /// Opens a task's result inside Jarvis (Results view): videos play there, documents read there.
    func openResult(_ id: String) {
        if var story = loadFilmStory(),story.id == id,story.phase == "awaiting_approval",resultFile(id) != nil {
            story.viewedHash = story.hash;_ = saveFilmStory(story)
        }
        guard let file = resultFile(id) else { send("notice", "There is no saved result for that task yet."); return }
        showResult(key: file.deletingPathExtension().lastPathComponent)
    }
    func resultKey(_ key: String) -> String? {
        key.isEmpty || key.contains("/") || key.hasPrefix(".") || key.contains("..") ? nil : key
    }
    /// One result: its document text and, when it has one, the playable video and shot clips.
    func resultItem(_ key: String, full: Bool) -> [String: Any]? {
        guard let key = resultKey(key) else { return nil }
        let fm = FileManager.default
        let doc = resultsDirectory.appendingPathComponent(key + ".md"), folder = resultsDirectory.appendingPathComponent(key)
        let video = folder.appendingPathComponent("final.mp4")
        let hasDoc = fm.fileExists(atPath: doc.path), hasVideo = fm.fileExists(atPath: video.path)
        guard hasDoc || hasVideo || fm.fileExists(atPath: folder.path) else { return nil }
        let text = (try? String(contentsOf: doc, encoding: .utf8)) ?? (try? String(contentsOf: folder.appendingPathComponent("shot-list.md"), encoding: .utf8)) ?? ""
        let title = text.split(separator: "\n").first(where: { $0.hasPrefix("# ") }).map { String($0.dropFirst(2)) } ?? String(key.dropFirst(11).dropLast(9))
        let shots = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("shot-") && $0.hasSuffix(".mp4") }
            .sorted { (Int($0.dropFirst(5).dropLast(4)) ?? 0) < (Int($1.dropFirst(5).dropLast(4)) ?? 0) }
        let modified = [doc, video, folder].compactMap { (try? fm.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }.max() ?? .distantPast
        var item: [String: Any] = ["key": key, "title": String(title.prefix(160)), "date": String(key.prefix(10)), "modified": Int(modified.timeIntervalSince1970 * 1000),
                                   "kind": hasVideo ? "video" : "document", "video": hasVideo ? ResultMedia.url(for: key + "/final.mp4") : NSNull()]
        if let record = ledger.load().first(where: { key.hasSuffix(" " + $0.id.prefix(8).lowercased()) }) {
            item["verificationStatus"] = record.verificationStatus
            item["verified"] = record.verificationStatus == "done and verified"
            item["savedRecordPath"] = "Jarvis Workspace/Results/" + key + ".md"
            if record.verificationStatus == "done and verified" { item["verificationEvidence"] = record.verificationEvidence }
        }
        if full {
            item["text"] = text
            item["shots"] = shots.map { ResultMedia.url(for: key + "/" + $0) }
        } else {
            let body = text.split(separator: "\n").first { !$0.hasPrefix("#") && !$0.hasPrefix("---") && !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.contains(" · 20") }
            item["summary"] = String((body ?? "").prefix(180))
        }
        return item
    }
    func listResults() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: resultsDirectory.path)) ?? []
        let keys = Set(names.filter { !$0.hasPrefix(".") }.map { $0.hasSuffix(".md") ? String($0.dropLast(3)) : $0 })
        let items = keys.compactMap { resultItem($0, full: false) }.sorted { ($0["modified"] as? Int ?? 0) > ($1["modified"] as? Int ?? 0) }
        send("results", Array(items.prefix(80)))
    }
    func showResult(key: String) {
        guard let item = resultItem(key, full: true) else { send("notice", "That result is no longer in Jarvis Workspace/Results."); return }
        send("showResult", item)
    }
    func revealResult(key: String) {
        guard let key = resultKey(key) else { return }
        let folder = resultsDirectory.appendingPathComponent(key), doc = resultsDirectory.appendingPathComponent(key + ".md")
        let target = FileManager.default.fileExists(atPath: folder.path) ? folder : doc
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    // MARK: Live board (hand-offs and directors at work)
    /// Tells the page what a director is doing, for the board's hand-off and working animations.
    func sendWork(seat: String, taskID: String, phase: String, title: String, text: String) {
        let payload: [String: Any] = ["seat": seat, "taskID": taskID, "phase": phase, "title": TaskLedger.headline(title, limit: 90),
                                      "text": String(text.prefix(180)), "at": Int(Date().timeIntervalSince1970 * 1000)]
        if phase == "done" || phase == "failed" { workBoard[seat] = nil }
        else {
            var kept = payload
            if phase == "update", let since = workBoard[seat]?["since"] { kept["since"] = since } else { kept["since"] = payload["at"] }
            workBoard[seat] = kept
        }
        send("work", workBoard[seat] ?? payload)
    }
    func publishVideo(_ taskID: String) {
        guard let job = videoJobs[taskID] else { return }
        send("videoProgress", job.payload())
    }

    // MARK: In-place UI updates
    /// Copies the page from the Jarvis source folder into the live UI folder and reloads the windows without quitting.
    /// If the new page does not report ready within 15 seconds it is rolled back to the previous page.
    func reloadUI(reason: String) {
        let outcome = LiveUI.apply(source: project.appendingPathComponent("Resources"), bundle: bundlePage, live: livePage)
        switch outcome {
        case .unchanged:
            if reason == "manual" { send("notice", "The UI is already up to date with the source.") }
        case .failed(let why):
            send("notice", "UI update not applied: " + why)
            if reason != "manual" { say("I didn't apply the UI change: " + why) }
        case .applied:
            uiAwaitingReady = true
            [web, orbWeb].compactMap { $0 }.forEach { loadPage($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.uiAwaitingReady else { return }
                self.uiAwaitingReady = false
                LiveUI.rollBack(live: self.livePage)
                [self.web, self.orbWeb].compactMap { $0 }.forEach { self.loadPage($0) }
                self.say("The new UI didn't start, so I rolled it back to the previous one.")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.send("notice", "UI updated in place. Nothing was restarted.") }
        }
    }
    func updateTask(_ id: String, state: String, summary: String) {
        var records = ledger.load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let now = TaskLedger.timestamp()
        records[index].state = state
        records[index].updatedAt = now
        records[index].resultSummary = summary
        if state != "completed" { records[index].verified = false; records[index].verificationEvidence = nil }
        if let parentID = records[index].parentID, let parent = records.firstIndex(where: { $0.id == parentID }), records[parent].state == "running" || records[parent].state == "proposed" {
            records[parent].state = state
            records[parent].updatedAt = now
            records[parent].resultSummary = summary
            records[parent].verified = false
            records[parent].verificationEvidence = nil
        }
        publishTasks(records)
    }
    func directorTitle(_ id: String) -> String {
        switch id {
        case "technology": return "Chief Technology Officer"
        case "research": return "Director of Research"
        case "creative": return "Creative Director"
        case "projects": return "Director of Projects"
        default: return "Director of Operations"
        }
    }
}
