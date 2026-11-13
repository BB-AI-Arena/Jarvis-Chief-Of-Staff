import AppKit
import WebKit
import AVFoundation
import Speech

extension JarvisApp {
    // MARK: Video. Creative directs the shots; DARK renders the motion.
    var comfyServer: String { (try? String(contentsOf: support.appendingPathComponent("comfy-url.txt"), encoding: .utf8)).flatMap(OllamaClient.sanitizeHost) ?? ComfyVideo.defaultServer }
    var comfyWorkflowFile: URL { workspace.appendingPathComponent("Video/comfyui-workflow-api.json") }
    /// The exported ComfyUI workflow, when it exists and has a "{{prompt}}" slot.
    func comfyWorkflow() -> [String: Any]? {
        guard let data = try? Data(contentsOf: comfyWorkflowFile), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], VideoPlan.hasPromptSlot(json) else { return nil }
        return json
    }
    func startVideo(_ parent: TaskRecord) {
        guard SpendBudget.allowsBudgetedFilm else {
            updateTask(parent.id, state: "failed", summary: SpendBudget.blocked)
            send("notice", SpendBudget.blocked)
            return
        }

        if let story = loadFilmStory() {
            guard story.canRender(task:parent.id) else {
                updateTask(parent.id,state:"proposed",summary:"Production is waiting for owner approval of the exact agreed screenplay; no rendering started.")
                say("That screenplay has not been approved for production. I will bring the agreed story to you first.");return
            }
        }
        let brief = parent.instructions, total = VideoPlan.requestedSeconds(parent.instructions)
        let workflow = comfyWorkflow(), server = comfyServer, dark = DarkServer.load(support: support)
        let folder = resultsDirectory.appendingPathComponent(resultBase(parent.id, title: parent.title))
        let artworkDirectory = VideoArtwork.directory(for: brief, sources: VideoArtwork.loadSources(support: support))
        let artworkRequired = artworkDirectory != nil || VideoArtwork.needsReference(brief)
        runSeat("creative", parent: parent, owner: "creative · video") { [weak self] taskID, done in
            guard let self else { return nil }
            let cancelled: () -> Bool = { [weak self] in self?.seatRuns["creative"] != taskID }
            // The Studio card: every change below is a real event (renderer choice, plan, ComfyUI message, download, join).
            var job = VideoPlan.Progress(taskID: taskID)
            job.title = TaskLedger.headline(brief, limit: 70)
            self.videoJobs[taskID] = job
            let finishedJobs = self.videoJobs.values.filter { $0.ended != nil }.sorted { ($0.ended ?? .distantPast) > ($1.ended ?? .distantPast) }
            for old in finishedJobs.dropFirst(5) { self.videoJobs[old.taskID] = nil }
            self.publishVideo(taskID)
            let update: ((inout VideoPlan.Progress) -> Void) -> Void = { [weak self] change in
                guard let self, var current = self.videoJobs[taskID] else { return }
                change(&current); self.videoJobs[taskID] = current; self.publishVideo(taskID)
            }
            var promptShots: [String: Int] = [:]
            var scenePrompts = Set<String>()
            var monitor: ComfyMonitor?
            var renderer: VideoPlan.Renderer?
            let finish: (String?, String?) -> Void = { text, failure in
                monitor?.stop(); monitor = nil
                update { $0.stage = text == nil ? .failed : .finished; $0.ended = Date(); $0.note = failure.map { String($0.prefix(160)) } ?? (text == nil ? "Stopped" : "Completed — video ready") }
                done(text, failure)
            }
            // Watches for Stop (cancels Jarvis's jobs on DARK) and reads the 4090's load every 10 s while rendering there.
            var ticks = 0
            func watch() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, let current = self.videoJobs[taskID], current.ended == nil else { return }
                    if cancelled() {
                        monitor?.stop(); monitor = nil
                        let open = promptShots.filter { current.shots.indices.contains($0.value) && !["done", "failed"].contains(current.shots[$0.value].state) }.map(\.key)
                        ComfyVideo.cancel(server: server, promptIDs: open)
                        update { $0.stage = .failed; $0.note = "stopped"; $0.ended = Date() }
                        return
                    }
                    ticks += 1
                    if renderer == .comfy, ticks % 2 == 0, dark.hasKey {
                        dark.run(DarkServer.gpuQuery, timeout: 15) { code, output in
                            if code == 0, let gpu = DarkServer.describeGPU(output) { update { $0.gpu = gpu } }
                        }
                    }
                    watch()
                }
            }
            watch()
            // 1. Use DARK for every video render; cloud still repair is bounded inside the film worker.
            typealias Choice = (VideoPlan.Renderer, ShotRenderer)?
            let pick: (@escaping (Choice) -> Void) -> Void = { choose in
                guard let workflow else { choose(nil); return }
                update { $0.note = "Checking the 4090 on DARK" }
                dark.ensureComfy(server: server) { ok, note in
                    update { $0.note = note }
                    choose(ok ? (.comfy, ComfyVideo(server: server, workflow: workflow, clientID: "jarvis-" + taskID.prefix(8).lowercased())) : nil)
                }
            }
            let pickWithArtwork: (@escaping (Choice) -> Void) -> Void = { choose in
                guard artworkRequired else { pick(choose); return }
                guard let directory = artworkDirectory else {
                    finish(nil, "No artwork source is configured for this video. Provide the artwork directory on DARK; the Knowledge map alone does not attach images to video jobs."); return
                }
                guard let workflow, VideoArtwork.conditioned(workflow, image: "check.png") != nil else {
                    finish(nil, "The configured ComfyUI workflow cannot accept reference artwork. No text-only video was generated."); return
                }
                dark.ensureComfy(server: server) { ok, note in
                    guard !cancelled() else { return }
                    guard ok else { finish(nil, "Artwork rendering needs ComfyUI on DARK: " + note); return }
                    self.noteTask(taskID, summary: "Loading source artwork from DARK")
                    VideoArtwork.prepare(directory: directory, brief: brief, server: server, workflow: workflow, dark: dark) { refs, error in
                        guard !cancelled() else { return }
                        guard var refs else { finish(nil, error); return }
                        if let look = VideoArtwork.approvedLook(for: brief, support: self.support) { refs.append(look) }
                        choose((.comfy, ComfyVideo(server: server, workflow: workflow, clientID: "jarvis-" + taskID.prefix(8).lowercased(), artwork: refs)))
                    }
                }
            }
            pickWithArtwork { [weak self] chosen in
                guard let self, !cancelled() else { return }
                guard let (chosenRenderer, engine) = chosen else { finish(nil, "DARK's local video renderer is unavailable at \(server). No cloud video generation was started."); return }
                renderer = chosenRenderer
                update { $0.renderer = chosenRenderer.rawValue; $0.stage = .planning }
                self.noteTask(taskID, summary: "Planning \(total) s of shots for \(chosenRenderer.rawValue)")
                // Live ComfyUI events for this job's shots.
                if let comfy = engine as? ComfyVideo {
                    let nodes = comfy.workflow
                    monitor = ComfyMonitor(server: server, clientID: comfy.clientID)
                    monitor?.onEvent = { event in
                        guard let index = promptShots[event.promptID] else { return }
                        update { job in
                            guard job.shots.indices.contains(index), !["done", "failed"].contains(job.shots[index].state) else { return }
                            switch event.type {
                            case "execution_start":
                                job.shots[index].state = "rendering"; job.shots[index].started = job.shots[index].started ?? Date()
                            case "executing":
                                if let node = event.node {
                                    job.shots[index].state = "rendering"; job.shots[index].started = job.shots[index].started ?? Date()
                                    let kind = ((nodes[node] as? [String: Any])?["class_type"] as? String) ?? ""
                                    let activity = scenePrompts.contains(event.promptID) ? "building scene on DARK" : VideoPlan.Progress.activity(kind)
                                    if !activity.isEmpty, activity != job.shots[index].activity { job.shots[index].activity = activity; job.shots[index].step = 0; job.shots[index].steps = 0 }
                                } else { job.shots[index].state = "downloading" }
                            case "progress":
                                job.shots[index].step = event.value ?? 0; job.shots[index].steps = event.max ?? 0
                            case "execution_error":
                                job.shots[index].note = "ComfyUI reported an error"
                            default: break
                            }
                        }
                    }
                    monitor?.start()
                }
                if let comfy=engine as? ComfyVideo {
                    guard let script=Bundle.main.url(forResource:"film_supervisor",withExtension:"py") else { finish(nil,"The local film engine is missing from this build.");return }
                    let spec=LocalFilmWorker.spec(brief:brief,seconds:total,artwork:comfy.artwork,workflow:comfy.workflow,server:server,dark:dark,project:self.project,model:self.cursorModel.hasPrefix("claude-") ? self.cursorModel : self.claudeModel,clientID:comfy.clientID)
                    var ended=false
                    self.filmWorkers[taskID]=LocalFilmWorker.start(spec:spec,folder:folder,project:self.project,script:script,event:{ event in
                        guard !cancelled() else { return }
                        switch event["type"] as? String {
                        case "plan":
                            if let object=event["plan"],let data=try? JSONSerialization.data(withJSONObject:object),let raw=String(data:data,encoding:.utf8),let plan=VideoPlan.parse(raw,renderer:.comfy,total:total) { update { $0.loadDirected(plan,total:total);$0.renderer="4090 · FLUX.2 → LTX-2.3" } }
                        case "queued":
                            if let id=event["prompt_id"] as? String,let index=event["index"] as? Int { promptShots[id]=index;if event["scene"] as? Bool == true { scenePrompts.insert(id) };update { if $0.shots.indices.contains(index) { $0.shots[index].pipelinePhase=event["scene"] as? Bool == true ? "scene" : "film_video" } } }
                        case "progress":
                            let message=event["message"] as? String ?? "Working on the local film"
                            self.noteTask(taskID,summary:message)
                            update { job in
                                job.note=message
                                if event["phase"] as? String == "joining",job.shots.allSatisfy({$0.state=="done"}) { job.stage = .joining }
                                else if event["index"] is Int { job.stage = .rendering }
                                if let i=event["index"] as? Int,job.shots.indices.contains(i) {
                                    let rawPhase=event["phase"] as? String ?? "video"
                                    let phase=rawPhase == "video" ? "film_video" : rawPhase
                                    if phase != job.shots[i].pipelinePhase { job.shots[i].step=0;job.shots[i].steps=0 }
                                    job.shots[i].pipelinePhase=phase
                                    job.shots[i].state=event["state"] as? String ?? "rendering";job.shots[i].activity=message
                                    job.shots[i].started=job.shots[i].started ?? Date()
                                    if job.shots[i].state=="done" { job.shots[i].ended=Date() }
                                }
                            }
                        case "usage":
                            if let usage=event["usage"],let data=try? JSONSerialization.data(withJSONObject:["usage":usage]) { TokenMeter.record(event["seat"] as? String,model:event["model"] as? String ?? "film director",data:data) }
                        case "pilot_ready":self.send("notice","Local film pilot ready: " + (event["path"] as? String ?? ""))
                        case "notice":self.send("notice",event["message"] as? String ?? "")
                        case "failed":ended=true;finish(nil,event["message"] as? String ?? "The local film needs attention. Checkpoints have been retained.")
                        case "done":
                            ended=true
                            let path=event["path"] as? String ?? ""
                            finish("Finished the directed local film.\n\nVideo: " + path + "\n\n" + (event["report"] as? String ?? ""),nil)
                        default:break
                        }
                    },completion:{ status in
                        self.filmWorkers[taskID]=nil
                        if !ended,!cancelled() { finish(nil,"The local film worker stopped (exit \(status)). The job and checkpoints are saved in " + folder.path) }
                    })
                    return
                }
                // 2. Plan the shots with the Creative persona (Claude, then Grok, then a plain split of the brief).
                let artwork = (engine as? ComfyVideo)?.artwork ?? []
                self.planVideo(taskID: taskID, brief: brief, total: total, renderer: chosenRenderer, artwork: artwork) { [weak self] plan in
                    guard let self, !cancelled() else { return }
                    guard let plan else { finish(nil, "Creative could not produce a complete storyboard from the artwork. No generic slideshow was rendered."); return }
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let storyboard = VideoPlan.document(plan, brief: brief, renderer: chosenRenderer, results: []) + (artwork.isEmpty ? "" : VideoArtwork.manifest(artwork, indices: plan.shots.enumerated().map { $0.element.referenceIndex ?? $0.offset }))
                    try? storyboard.write(to: folder.appendingPathComponent("storyboard.md"), atomically: true, encoding: .utf8)
                    let cost = VideoPlan.cost(plan, renderer: chosenRenderer)
                    update { $0.load(plan); $0.note = plan.concept ?? (cost > 0 ? String(format: "about $%.2f", cost) : "free on the 4090") }
                    self.noteTask(taskID, summary: "Rendering \(plan.shots.count) shots (\(plan.seconds) s) on \(chosenRenderer.rawValue)" + (cost > 0 ? String(format: ", about $%.2f", cost) : ", free"))
                    // Text-only jobs also stay on DARK. Artwork jobs use the local scene pipeline above.
                    var results = [String](repeating: "not rendered", count: plan.shots.count)
                    var clips = [URL?](repeating: nil, count: plan.shots.count)
                    var pending = plan.shots.count, finished = 0
                    for (index, shot) in plan.shots.enumerated() {
                        var shotEngine = engine
                        if var comfy = engine as? ComfyVideo { comfy.artworkIndex = shot.referenceIndex ?? index; comfy.onQueued = { promptShots[$0] = index }; shotEngine = comfy }
                        else { update { $0.shots[index].state = "rendering"; $0.shots[index].started = Date(); $0.shots[index].activity = "rendering on xAI" } }
                        shotEngine.render(shot, to: folder.appendingPathComponent("shot-\(index + 1).mp4"), isCancelled: cancelled) { [weak self] file, failure in
                            guard let self, !cancelled() else { return }
                            clips[index] = file
                            results[index] = file != nil ? "shot-\(index + 1).mp4" : "failed: " + (failure ?? "unknown")
                            pending -= 1
                            if file != nil { finished += 1 }
                            update { job in
                                guard job.shots.indices.contains(index) else { return }
                                job.shots[index].state = file != nil ? "done" : "failed"; job.shots[index].ended = Date()
                                job.shots[index].started = job.shots[index].started ?? Date()
                                if let failure { job.shots[index].note = String(failure.prefix(140)) }
                            }
                            if let file { VideoStitcher.thumbnail(file) { thumb in update { job in if job.shots.indices.contains(index) { job.shots[index].thumb = thumb } } } }
                            self.noteTask(taskID, summary: "Rendered \(finished) of \(plan.shots.count) shots on \(chosenRenderer.rawValue)")
                            guard pending == 0 else { return }
                            try? (VideoPlan.document(plan, brief: brief, renderer: chosenRenderer, results: results) + (artwork.isEmpty ? "" : VideoArtwork.manifest(artwork, indices: plan.shots.enumerated().map { $0.element.referenceIndex ?? $0.offset }))).write(to: folder.appendingPathComponent("shot-list.md"), atomically: true, encoding: .utf8)
                            let made = clips.compactMap { $0 }
                            guard !made.isEmpty else { finish(nil, "No shot rendered. First problem: " + (results.first { $0.hasPrefix("failed") } ?? "unknown")); return }
                            // 4. Join the shots into one file.
                            update { $0.stage = .joining }
                            self.noteTask(taskID, summary: "Joining \(made.count) shots")
                            VideoStitcher.join(made, to: folder.appendingPathComponent("final.mp4")) { joined in
                                let failed = results.filter { $0.hasPrefix("failed") }.count
                                let where_ = folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
                                let headline = (joined ? "Finished \"\(plan.title)\": \(made.count) shots, \(plan.seconds) seconds, rendered on \(chosenRenderer.rawValue)." : "Rendered \(made.count) shots of \"\(plan.title)\" on \(chosenRenderer.rawValue), but they could not be joined into one file.")
                                    + (failed > 0 ? " \(failed) shot\(failed == 1 ? "" : "s") failed." : "")
                                finish(headline + "\n\nVideo: " + (joined ? where_ + "/final.mp4" : where_ + " (separate shots)") + "\n\n" + VideoPlan.document(plan, brief: brief, renderer: chosenRenderer, results: results) + (artwork.isEmpty ? "" : VideoArtwork.manifest(artwork, indices: plan.shots.enumerated().map { $0.element.referenceIndex ?? $0.offset })), nil)
                            }
                        }
                    }
                }
            }
            return nil
        }
    }
    func planVideo(taskID: String, brief: String, total: Int, renderer: VideoPlan.Renderer, artwork: [VideoArtwork.Reference] = [], completion: @escaping (VideoPlan.Plan?) -> Void) {
        // DARK films are planned exclusively by the local worker; never fall through to paid providers.
        if renderer == .comfy { completion(nil); return }
        if !artwork.isEmpty {
            guard claudeConnected, let key = ClaudeCredential.read() else { completion(nil); return }
            noteTask(taskID, summary: "Creative is inspecting artwork and writing a story")
            let tool = directorTool(taskID, seat: "creative")
            VideoArtwork.previews(artwork, server: comfyServer) { [weak self] images in
                guard let self, self.seatRuns["creative"] == taskID else { return }
                guard let images else { completion(nil); return }
                let prompt = "Direct the complete story assignment below as a \(total)-second film with a beginning, development and ending. Preserve the requested events. Maximum five seconds per shot. Design a NEW opening scene and motion for each shot; provide continuity, image_prompt and reference_indices. Labelled reference images follow."
                TokenMeter.charge("creative") {
                    let shared = DirectorResultsContext(workspace: self.workspace, records: self.ledger.load()).context(for: brief)
                    ClaudeClient.converse(prompt, model: self.claudeModel, apiKey: key, system: VideoArtwork.storyboardSystem + " " + ProjectsTool.promptNote + "\n\n" + shared, images: [["type":"text","text":"Complete story assignment:\n" + brief]] + images, tools: [ProjectsTool.anthropic], isCancelled: { [weak self] in self?.seatRuns["creative"] != taskID }, tool: tool) { raw in
                        completion(raw.flatMap { VideoArtwork.storyboard($0, references: artwork.count, total: total) })
                    }
                }
            }
            return
        }
        let system = VideoPlan.plannerSystem(persona: Personas.system("creative", fallback: "You are Jarvis's Creative Director, a film director with a strong visual style.")) + " " + ProjectsTool.promptNote + "\n\n" + DirectorResultsContext(workspace: workspace, records: ledger.load()).context(for: brief)
        let tool = directorTool(taskID, seat: "creative")
        let cancelled: () -> Bool = { [weak self] in self?.seatRuns["creative"] != taskID }
        let prompt = VideoPlan.plannerPrompt(brief: brief, seconds: total, renderer: renderer)
        let finish: (String?) -> Bool = { raw in
            guard let raw, let plan = VideoPlan.parse(raw, renderer: renderer, total: total) else { return false }
            completion(plan); return true
        }
        let grok = { [weak self] in
            guard let self, self.grokConnected, let key = GrokCredential.read() else { completion(VideoPlan.fallback(brief: brief, total: total, renderer: renderer)); return }
            TokenMeter.charge("creative") { GrokClient.researchWithTools(prompt, model: self.grokModel, apiKey: key, system: system, tools: [ProjectsTool.responsesFunction], isCancelled: cancelled, tool: tool) { raw, _ in
                if !finish(raw) { completion(VideoPlan.fallback(brief: brief, total: total, renderer: renderer)) }
            } }
        }
        guard claudeConnected, let key = ClaudeCredential.read() else { grok(); return }
        TokenMeter.charge("creative") { ClaudeClient.converse(prompt, model: claudeModel, apiKey: key, system: system, tools: [ProjectsTool.anthropic], isCancelled: cancelled, tool: tool) { raw in if !finish(raw) { grok() } } }
    }
    /// Polls Get A Run until it reaches a terminal status. Completed tasks stay unverified: the API reports a result, not a check.
}
