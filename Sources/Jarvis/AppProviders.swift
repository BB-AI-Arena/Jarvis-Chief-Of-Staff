import AppKit
import WebKit
import AVFoundation
import Speech

extension JarvisApp {
    func pollCursor(taskID: String, ids: (agent: String, run: String), apiKey: String, link: String, started: Date, done: @escaping (String?, String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, !self.quitting, self.seatRuns["creative"] == taskID else { return }
            CursorClient.run(agent: ids.agent, run: ids.run, apiKey: apiKey) { [weak self] state in
                guard let self = self, self.seatRuns["creative"] == taskID else { return }
                guard let state else {
                    if Date().timeIntervalSince(started) > 4 * 3600 { self.cursorRun = nil; done(nil, "Stopped checking after 4 hours; status unknown. \(link)"); return }
                    self.pollCursor(taskID: taskID, ids: ids, apiKey: apiKey, link: link, started: started, done: done); return
                }
                if CursorClient.terminal.contains(state.status) {
                    self.cursorRun = nil
                    let pr = state.pr.map { " · PR \($0)" } ?? ""
                    let result = state.result.map { " · " + $0 } ?? ""
                    if state.status == "FINISHED" { done("Cursor agent finished · \(link)\(pr)\(result)", nil) }
                    else { done(nil, "Cursor agent \(state.status.lowercased()) · \(link)\(result)") }
                    return
                }
                self.noteTask(taskID, summary: "Cursor agent \(ids.agent) · \(link) · \(state.status.lowercased())")
                self.pollCursor(taskID: taskID, ids: ids, apiKey: apiKey, link: link, started: started, done: done)
            }
        }
    }
    func noteTask(_ id: String, summary: String) {
        var records = ledger.load()
        guard let index = records.firstIndex(where: { $0.id == id }), records[index].state == "running" else { return }
        records[index].resultSummary = summary
        records[index].updatedAt = TaskLedger.timestamp()
        publishTasks(records)
        if let seat = seatRuns.first(where: { $0.value == id })?.key ?? (workTaskID == id ? "operations" : nil) {
            sendWork(seat: seat, taskID: id, phase: "update", title: records[index].title, text: summary)
        }
    }
    /// After the Operations worker finishes: apply any change it made to the page in place, and say when native code changed too.
    func afterWorker() {
        reloadUI(reason: "worker")
        let now = LiveUI.fingerprint(project.appendingPathComponent("Sources"))
        if let before = workerSourcesFingerprint, before != now {
            send("notice", "The change also touches Jarvis's native code. That part takes effect after the next install.")
        }
        workerSourcesFingerprint = nil
    }
    func refreshCursor(announce: Bool) {
        guard let apiKey = CursorCredential.read() else { cursorConnected = false; sendSeatStatus(); return }
        CursorClient.check(apiKey) { [weak self] ok in
            guard let self = self else { return }
            self.cursorConnected = ok
            self.sendSeatStatus()
            if announce { self.send("notice", ok ? "Cursor is connected for the Creative Director." : "Cursor did not accept that key. The Creative seat stays not connected.") }
        }
    }
    func configureCursor() {
        let alert = NSAlert()
        alert.messageText = "Connect Cursor"
        alert.informativeText = "The Creative Director launches Cursor cloud agents with a Cursor API key (Cursor Dashboard → API Keys). It is stored in this Mac's Keychain and is not shown to the page."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 26))
        field.placeholderString = "Cursor API key"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save key")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { send("notice", "No key was entered."); return }
        if CursorCredential.save(key) { refreshCursor(announce: true) }
        else { send("notice", "The key could not be saved to Keychain.") }
    }
    func refreshGrok(announce: Bool) {
        guard let apiKey = GrokCredential.read() else { grokConnected = false; sendSeatStatus(); return }
        GrokClient.check(apiKey) { [weak self] ok in
            guard let self = self else { return }
            self.grokConnected = ok
            self.sendSeatStatus()
            if announce { self.send("notice", ok ? "Grok is connected for the Director of Research." : "xAI did not accept that key. The Research seat stays not connected.") }
        }
    }
    func configureGrok() {
        let alert = NSAlert()
        alert.messageText = "Connect Grok"
        alert.informativeText = "The Director of Research uses an xAI API key. It is stored in this Mac's Keychain and is not shown to the page."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 26))
        field.placeholderString = "xAI API key"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save key")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { send("notice", "No key was entered."); return }
        if GrokCredential.save(key) { refreshGrok(announce: true) }
        else { send("notice", "The key could not be saved to Keychain.") }
    }
    func storeGrokModel(_ raw: String) {
        guard let model = GrokClient.sanitize(raw) else { send("notice", "That Grok model id was not saved."); return }
        grokModel = model
        try? model.write(to: support.appendingPathComponent("grok-model.txt"), atomically: true, encoding: .utf8)
        sendSeatStatus()
        send("notice", "Director of Research model set to \(model).")
    }
    func storeCursorModel(_ raw: String) {
        guard let model = CursorClient.sanitizeModel(raw) else { send("notice", "That Cursor model id was not saved."); return }
        cursorModel = model
        try? model.write(to: support.appendingPathComponent("cursor-model.txt"), atomically: true, encoding: .utf8)
        sendSeatStatus()
        send("notice", model.isEmpty ? "Creative Director uses Cursor's default model." : "Creative Director model set to \(model).")
    }
    func storeCursorRepo(_ raw: String) {
        guard let repo = CursorClient.sanitizeRepo(raw) else { send("notice", "That repository URL was not saved. Use an https repository URL."); return }
        cursorRepo = repo
        try? repo.write(to: support.appendingPathComponent("cursor-repo.txt"), atomically: true, encoding: .utf8)
        sendSeatStatus()
        send("notice", "Creative Director repository set to \(repo).")
    }
    /// Projects runs on the 4090's Ollama. If the server does not answer, it falls back to the model saved for this Mac.
    func startProjects(_ parent: TaskRecord) {
        guard let model = projectsModel else { return }
        let memoryContext = memory.context() + "\n\n" + DirectorResultsContext(workspace:workspace,records:ledger.load()).context(for:parent.instructions) + "\n\n" + DirectorResultsContext(workspace: workspace, records: ledger.load()).context(for: parent.instructions)
        let fallback = (try? String(contentsOf: support.appendingPathComponent("projects-fallback-model.txt"), encoding: .utf8)).flatMap(OllamaClient.sanitize)
        runSeat("projects", parent: parent, owner: "projects · " + model) { [weak self] taskID, done in
            let darkReady = DarkTool.relevant(parent.instructions) && DarkServer.load(support: self?.support ?? URL(fileURLWithPath: "/")).hasKey
            let system = Personas.system("projects", fallback: OllamaClient.projectsFallback) + "\n\nThis call is an assignment from Jarvis. You run on a local model and cannot browse or edit files. Answer as the Director of Projects." + (darkReady ? " " + DarkTool.promptNote : "") + memoryContext
            let answered: (String?) -> Void = { [weak self] text in
                if let text { done(text, nil); return }
                guard let fallback, OllamaClient.base != OllamaClient.local, self?.seatRuns["projects"] == taskID else {
                    done(nil, "The model \(model) did not answer. Check that Ollama is running on \(OllamaClient.base).")
                    return
                }
                self?.noteTask(taskID, summary: "The 4090 did not answer; using \(fallback) on this Mac")
                self?.seatRequests["projects"] = OllamaClient.chat(DirectorBrief.make(role:"projects",instructions:parent.instructions), model: fallback, system: system, host: OllamaClient.local) { text in
                    done(text, text == nil ? "Neither the 4090 nor this Mac's \(fallback) answered." : nil)
                }
            }
            if darkReady, let tool = self?.directorTool(taskID, seat: "projects") {
                OllamaClient.converse(DirectorBrief.make(role:"projects",instructions:parent.instructions), model: model, system: system, tools: [DarkTool.function], isCancelled: { [weak self] in self?.seatRuns["projects"] != taskID }, tool: tool, completion: answered)
                return nil
            }
            return OllamaClient.chat(DirectorBrief.make(role:"projects",instructions:parent.instructions), model: model, system: system, completion: answered)
        }
    }
    /// Live check of every connection. Seat status follows the result, so a seat shows connected only after a real answer.
    /// At launch the check skips the Luna call (it would hold up the first request) and Jarvis says what is off.
    func runHealthCheck(startup: Bool) {
        guard !healthRunning else { return }
        healthRunning = true
        send("healthStarted", true)
        var settings = HealthCheck.Settings(claudeModel: claudeModel, grokModel: grokModel, projectsModel: projectsModel, managerModel: OperationsManager.resolve(stored: managerModel, advertised: knownLocalModels), cursorRepo: cursorRepo)
        settings.comfyServer = comfyServer
        settings.comfyWorkflowReady = comfyWorkflow() != nil
        settings.dark = DarkServer.load(support: support)
        HealthCheck.run(settings: settings, brain: brain, includeLuna: !startup) { [weak self] results in
            guard let self = self else { return }
            self.healthRunning = false
            for result in results where result.status != "off" {
                switch result.id {
                case "claude": self.claudeConnected = result.status == "ok"; self.send("claudeStatus", ["connected": self.claudeConnected, "model": self.claudeModel])
                case "grok": self.grokConnected = result.status == "ok"
                case "cursor": self.cursorConnected = result.status == "ok"
                default: break
                }
            }
            self.sendSeatStatus()
            self.send("health", ["checkedAt": TaskLedger.timestamp(), "results": results.map { $0.payload }])
            let failed = results.filter { $0.status == "failed" }.map { $0.name }
            self.send("notice", failed.isEmpty ? "Health check finished: nothing failed." : "Health check: " + failed.joined(separator: ", ") + " failed. Details are in Settings.")
            if startup, let line = HealthCheck.startupLine(results) { self.say(line) }
        }
    }
    /// One-time SSH setup for DARK: creates Jarvis's own key if needed, then opens Terminal so Brandon types the server password
    /// into ssh-copy-id himself. Jarvis never sees or stores the password.
    func configureDark() {
        let dark = DarkServer.load(support: support)
        if !dark.hasKey {
            let keygen = Process()
            keygen.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            keygen.arguments = ["-t", "ed25519", "-f", dark.key, "-N", "", "-C", "jarvis@mac"]
            keygen.standardOutput = FileHandle.nullDevice; keygen.standardError = FileHandle.nullDevice
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dark.key).deletingLastPathComponent(), withIntermediateDirectories: true)
            do { try keygen.run(); keygen.waitUntilExit() } catch { send("notice", "Could not create an SSH key for DARK."); return }
        }
        dark.save(support: support)
        let command = "ssh-copy-id -i '\(dark.publicKey)' \(dark.target)"
        // A .command file opens in Terminal through Launch Services, so Jarvis needs no Automation permission to show it.
        let script = support.appendingPathComponent("connect-dark.command")
        let body = "#!/bin/zsh\nclear\necho \"Jarvis is adding its SSH key to DARK. Type DARK's password when asked. It is not shown or saved.\"\necho\nif \(command); then echo; echo \"Done. Close this window, go back to Jarvis and run the health check.\"; else echo; echo \"That did not work. Close this window and try Connect DARK again.\"; fi\n"
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                DispatchQueue.main.async {
                    self.send("notice", error == nil ? "Terminal is open: type DARK's password there once. Then run the health check in Settings." : "Open Terminal and run: " + command)
                }
            }
        } catch { send("notice", "Open Terminal and run: " + command) }
    }
    func storeProjectsModel(_ raw: String) {
        let url = support.appendingPathComponent("projects-model.txt")
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? FileManager.default.removeItem(at: url)
            projectsModel = nil; sendSeatStatus()
            send("notice", "Director of Projects model cleared. The seat is not connected.")
            return
        }
        guard let model = OllamaClient.sanitize(raw) else { send("notice", "That local model name was not saved."); return }
        OllamaClient.models { [weak self] names in
            guard let self = self else { return }
            guard let names else { self.send("notice", "Ollama is not responding on this Mac, so the Projects model was not saved."); return }
            guard names.contains(model) else { self.send("notice", "\(model) is not installed in Ollama, so it was not saved. Installed: " + (names.isEmpty ? "none" : names.joined(separator: ", ")) + "."); return }
            self.projectsModel = model
            try? model.write(to: url, atomically: true, encoding: .utf8)
            self.sendSeatStatus()
            self.send("notice", "Director of Projects now runs locally on \(model).")
        }
    }
    /// Directors that can speak in a debate right now, with the call that asks each one. Order is chair preference.
}
