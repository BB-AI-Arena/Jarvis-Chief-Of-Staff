import AppKit
import WebKit
import AVFoundation
import Speech

extension JarvisApp {
    // MARK: Task core. Every request is recorded first, queued per director, and started when that seat is free.
    func acknowledge(_ message: String, _ liveUpdate: ((String) -> Void)?) {
        if let update = liveUpdate { update(message) } else { send("reply", ["text": message, "model": "Jarvis", "streamed":streamSpoke && message == streamText]); if !streamPlayback { streamVoice = nil };streamSpoke = false; send("state", "idle") }
    }
    /// Tells Brandon something through whatever is live: the voice delegation that asked, the live voice session, or page speech.
    func say(_ line: String, for parentID: String? = nil) {
        if let id = parentID, let reply = liveReplies[id], let live = liveVoice, live === reply.voice { reply.update(line); return }
        if let live = liveVoice { live.announce(line); return }
        send("announce", ["text": line])
    }
    func seatReady(_ director: String) -> (connected: Bool, busy: Bool) {
        switch director {
        case "technology": return (claudeConnected, seatRuns[director] != nil)
        case "research": return (grokConnected || claudeConnected, seatRuns[director] != nil)
        case "creative": return (cursorConnected || grokConnected || claudeConnected || comfyWorkflow() != nil, seatRuns[director] != nil)
        case "projects": return (projectsModel != nil, seatRuns[director] != nil)
        case "operations": return (AgentRuntime.executable != nil, tasks["work"] != nil)
        default: return (false, false)
        }
    }
    /// Records the task, then starts it if its director is free. Otherwise it waits in that director's queue and starts on its own.
    func delegateWork(_ task: String, director: String, liveUpdate: ((String) -> Void)? = nil) {
        if director == "creative",isApprovedFilmRequest(task) { acknowledge(createApprovedFilm(),liveUpdate);return }
        if ["creative","projects"].contains(director),isSavedStoryRequest(task) {
            acknowledge(resumeSavedFilmStory(),liveUpdate);return
        }
        let now = TaskLedger.timestamp(), parentID = UUID().uuidString, title = directorTitle(director)
        var records = ledger.load()
        records.insert(TaskRecord(id: parentID, state: "proposed", verified: false, owner: director, parentID: nil, createdAt: now, updatedAt: now, resultSummary: TaskLedger.queued, title: String(task.prefix(500)), brief: task), at: 0)
        publishTasks(records)
        if let liveUpdate { liveReplies[parentID] = LiveReply(update: liveUpdate, voice: liveVoice) }
        dispatch(director)
        records = ledger.load()
        guard let index = records.firstIndex(where: { $0.id == parentID }) else { return }
        let message: String
        if records[index].state == "running" || records[index].state == "completed" {
            message = "I've added that to the task list and assigned it to the \(title). I'll report what comes back."
        } else if records[index].state == "failed" {
            message = "I've added that to the task list, but the \(title) could not start it. \(records[index].resultSummary)"
        } else if !seatReady(director).connected {
            records[index].resultSummary = TaskLedger.queued + ": seat not connected"
            publishTasks(records)
            message = "I've added that to the task list for the \(title). That seat isn't connected yet, so it will start as soon as it is."
        } else {
            let ahead = TaskLedger.queuedAhead(records, of: parentID)
            records[index].resultSummary = TaskLedger.queued + ": behind the current assignment"
            publishTasks(records)
            message = "I've added that to the task list for the \(title). It's queued behind " + (ahead == 0 ? "the current assignment" : "\(ahead + 1) other assignments") + " and will start automatically."
        }
        acknowledge(message, liveUpdate)
    }
    func dispatch(_ director: String) {
        let ready = seatReady(director)
        guard ready.connected, !ready.busy, !quitting, let next = TaskLedger.nextQueued(ledger.load(), director: director) else { return }
        if director == "research",next.instructions.contains("STORY_REVIEW_CONTRACT"),!grokConnected { return }
        switch director {
        case "technology": startClaude(next)
        case "research": startGrok(next)
        case "creative": startCreative(next)
        case "projects": startProjects(next)
        default: startOperations(next)
        }
    }
    func dispatchAll() { RouteDecision.directors.forEach { dispatch($0) } }
    /// Shared bookkeeping for a model-backed seat: marks the parent running, adds the director's row, and finishes through `finishAssignment`.
    func runSeat(_ seat: String, parent: TaskRecord, owner: String, start: (String, @escaping (String?, String?) -> Void) -> URLSessionDataTask?) {
        let now = TaskLedger.timestamp(), taskID = UUID().uuidString
        var records = ledger.load()
        guard let index = records.firstIndex(where: { $0.id == parent.id }) else { return }
        seatRuns[seat] = taskID
        records[index].state = "running"; records[index].updatedAt = now; records[index].resultSummary = ""
        records.insert(TaskRecord(id: taskID, state: "running", verified: false, owner: owner, parentID: parent.id, createdAt: now, updatedAt: now, resultSummary: "", title: parent.title), at: index + 1)
        publishTasks(records)
        sendWork(seat: seat, taskID: taskID, phase: "handoff", title: parent.title, text: "On it")
        let request = TokenMeter.charge(seat) { start(taskID) { [weak self] text, failure in
            guard let self = self else { return }
            if self.quitting || self.seatRuns[seat] != taskID { return }
            self.seatRequests[seat] = nil
            self.seatRuns[seat] = nil
            if self.ledger.load().first(where: { $0.id == taskID })?.state == "cancelled" { self.dispatch(seat); return }
            self.finishAssignment(seat: seat, taskID: taskID, parent: parent, text: text, failure: failure)
        } }
        if let request { seatRequests[seat] = request }
        // A director cannot sit on one assignment forever: past its limit the run is stopped and the seat takes the next task.
        if let normalLimit = Self.seatTimeLimit[seat], !(seat == "creative") {
            let limit: TimeInterval = seat == "research" && parent.instructions.contains("STORY_REVIEW_CONTRACT") ? 600 : normalLimit
            DispatchQueue.main.asyncAfter(deadline: .now() + limit) { [weak self] in
                guard let self, !self.quitting, self.seatRuns[seat] == taskID else { return }
                self.seatRequests[seat]?.cancel(); self.seatRequests[seat] = nil
                self.seatRuns[seat] = nil
                self.finishAssignment(seat: seat, taskID: taskID, parent: parent, text: nil, failure: "Stopped after \(Int(limit / 60)) minutes without a result. The task may be too broad for this director, or need a different one.")
            }
        }
    }
    /// Longest one assignment may run, in seconds. Creative (Cursor agents, renders) and Operations manage their own limits.
    static let seatTimeLimit: [String: TimeInterval] = ["research": 300, "technology": 480, "projects": 360]
    /// Most tokens one assignment may use before its tools are withdrawn and it must answer.
    static let seatTokenBudget: [String: Int] = ["research": 600_000, "technology": 400_000, "projects": 200_000]
    /// Closes the loop: saves the full result, records it in memory, tells Brandon in a sentence with an optional next step, and starts the next queued task.
    func finishAssignment(seat: String, taskID: String, parent: TaskRecord, text: String?, failure: String?) {
        let title = directorTitle(seat), name = TaskLedger.headline(parent.title, limit: 90)
        sendWork(seat: seat, taskID: taskID, phase: text == nil ? "failed" : "done", title: parent.title, text: text == nil ? "Couldn't finish" : "Done")
        if let text {
            saveResult(parent.id, title: parent.title, director: title, text: text)
            if let file = resultFile(parent.id), let item = resultItem(file.deletingPathExtension().lastPathComponent, full: false) { send("resultReady", item) }
            if seat == "operations" { afterWorker() }
            updateTask(taskID, state: "completed", summary: String(text.prefix(2000)))
            send("taskResult", ["text": text, "success": true])
            memory.append(kind: title, text: name + " → " + TaskLedger.headline(text))
            let line = "The \(title) finished: \(name) " + TaskLedger.headline(text) + (seat == "creative" && text.contains("final.mp4") ? " It's ready to play in Results." : " The full result is in Results.")
            if parent.title.hasPrefix("[Story consultation]") {
                send("notice", "The \(title) returned its story consultation; Jarvis is coordinating the next step.")
                liveReplies[parent.id] = nil
                dispatch(seat)
                return
            }
            offerNextStep(task: parent.title, seat: seat, result: text) { [weak self] offer in
                self?.say(line + (offer.map { " " + $0 } ?? ""), for: parent.id)
                self?.liveReplies[parent.id] = nil
            }
        } else {
            let summary = failure ?? "The \(title) did not return a result."
            updateTask(taskID, state: "failed", summary: summary)
            send("taskResult", ["text": summary, "success": false])
            say("The \(title) could not finish: \(name) " + TaskLedger.headline(summary), for: parent.id)
            liveReplies[parent.id] = nil
        }
        dispatch(seat)
    }
    /// One optional follow-up for approval, from the fast router. Never added to the task list without Brandon's yes.
    func offerNextStep(task: String, seat: String, result: String, completion: @escaping (String?) -> Void) {
        // One follow-up per request: never chain suggestions, and never suggest more of the same after a blocked attempt.
        if approvedSuggestions.remove(task) != nil || RouteDecision.looksBlocked(result) { completion(nil); return }
        guard claudeConnected, let apiKey = ClaudeCredential.read() else { completion(nil); return }
        JarvisRouter.route(JarvisRouter.nextStepPrompt(task: task, director: seat, result: result), history: "", apiKey: apiKey, persona: "", memory: "") { [weak self] decision in
            guard let self = self, let decision, let suggestion = RouteDecision.suggestion(for: decision) else { completion(nil); return }
            self.suggestTask(suggestion.title, director: suggestion.director)
            completion(decision.text)
        }
    }
    /// Tool handler for a director's model: run_on_dark runs on DARK (and shows on the board); anything else goes to `other`.
    func directorTool(_ taskID: String, seat: String, other: ((String, [String: Any], @escaping (String) -> Void) -> Void)? = nil) -> (String, [String: Any], @escaping (String) -> Void) -> Void {
        let dark = DarkServer.load(support: support)
        let projects = ProjectsTool()
        let start = TokenMeter.used(seat), budget = Self.seatTokenBudget[seat] ?? 400_000
        return { [weak self] name, input, reply in
            guard let self, self.seatRuns[seat] == taskID else { reply("Assignment cancelled."); return }
            let spent = TokenMeter.used(seat) - start
            if spent > budget {
                self.noteTask(taskID, summary: "Token budget reached (\(spent / 1000)k); wrapping up")
                reply("This task's token budget is used up (\(spent / 1000)k of \(budget / 1000)k). No more tool calls will run. Answer now with what you have and say plainly what is unfinished.")
                return
            }
            if name == ProjectsTool.name, seat != "projects" {
                let delegationID = taskID + "-projects-" + UUID().uuidString
                projects.run(input, isCancelled: { [weak self] in self?.seatRuns[seat] != taskID }, event: { [weak self] phase, title in
                    guard let self else { return }
                    let label = self.directorTitle(seat) + " → Projects: " + title
                    self.noteTask(taskID, summary: label + (phase == "handoff" ? "" : " · " + phase))
                    self.sendWork(seat: "projects", taskID: delegationID, phase: phase, title: label, text: label)
                }, completion: reply)
                return
            }
            guard name == DarkTool.name else { if let other { other(name, input, reply) } else { reply("Unknown tool \(name).") }; return }
            let command = ((input["command"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.noteTask(taskID, summary: "On DARK: " + String(command.prefix(90)))
            DarkTool.run(input, dark: dark) { output in
                if output.hasPrefix("Refused") { self.noteTask(taskID, summary: "DARK refused: " + String(command.prefix(70))) }
                reply(output)
            }
        }
    }
    /// The CTO reads the Jarvis Workspace folder and the Jarvis source with read-only tools. The folder mapped in Knowledge map is never sent to a model.
    func startClaude(_ parent: TaskRecord) {
        guard let apiKey = ClaudeCredential.read() else { return }
        let model = claudeModel, workspace = WorkspaceTools(roots: ["workspace": workspace, "source": project]), memoryContext = memory.context() + "\n\n" + DirectorResultsContext(workspace: self.workspace, records: ledger.load()).context(for: parent.instructions)
        let darkReady = DarkServer.load(support: support).hasKey
        runSeat("technology", parent: parent, owner: model) { [weak self] taskID, done in
            let system = Personas.system("cto", fallback: ClaudeClient.ctoFallback) + "\n\nThis call is an assignment from Jarvis. You have read-only tools (list_files, read_file, search_code) over two areas: workspace/ is Brandon's Jarvis Workspace folder with saved results and memory, and source/ is the Jarvis app source. Check the real files before you answer questions about them. You cannot edit files here. Answer as the CTO and say what you did not check." + (darkReady ? " " + DarkTool.promptNote : "") + " " + ProjectsTool.promptNote + memoryContext
            let workspaceTool: (String, [String: Any], @escaping (String) -> Void) -> Void = { name, input, reply in
                DispatchQueue.global(qos: .userInitiated).async {
                    let output = workspace.run(name, input)
                    DispatchQueue.main.async {
                        let target = (input["path"] as? String) ?? (input["query"] as? String) ?? ""
                        self?.noteTask(taskID, summary: "Reading files · \(name) \(String(target.prefix(60)))")
                        reply(output)
                    }
                }
            }
            let tools = WorkspaceTools.definitions + [ProjectsTool.anthropic] + (darkReady ? [DarkTool.anthropic] : [])
            var providerFailure: String?
            ClaudeClient.converse(DirectorBrief.make(role:"technology",instructions:parent.instructions), model: model, apiKey: apiKey, system: system, tools: tools, isCancelled: { [weak self] in self?.seatRuns["technology"] != taskID }, tool: self?.directorTool(taskID, seat: "technology", other: workspaceTool) ?? workspaceTool, diagnostic:{ [weak self] reason in
                providerFailure = reason
                self?.noteTask(taskID,summary:reason)
                guard let self,let data = try? JSONSerialization.data(withJSONObject:["at":TaskLedger.timestamp(),"taskID":taskID,"provider":"Claude","model":model,"error":reason]) else { return }
                let url = self.support.appendingPathComponent("provider-errors.jsonl")
                if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600]) }
                if let file = try? FileHandle(forWritingTo:url) { defer { try? file.close() };_ = try? file.seekToEnd();try? file.write(contentsOf:data + Data([10])) }
            }) { text in done(text, text == nil ? (providerFailure ?? "Claude did not return a complete result; no detailed provider error was available.") : nil) }
            return nil
        }
    }
    func refreshClaude(announce: Bool) {
        guard let apiKey = ClaudeCredential.read() else {
            claudeConnected = false
            send("claudeStatus", ["connected": false, "model": claudeModel])
            return
        }
        ClaudeClient.check(apiKey) { [weak self] ok in
            guard let self = self else { return }
            self.claudeConnected = ok
            self.send("claudeStatus", ["connected": ok, "model": self.claudeModel])
            self.sendSeatStatus()
            if announce { self.send("notice", ok ? "Claude is connected for the Chief Technology Officer." : "Claude did not accept that key. The seat stays not connected.") }
        }
    }
    /// Shows a suggested task for approval. It is not written to the ledger until Brandon approves it.
    func suggestTask(_ title: String, director: String) {
        send("taskSuggestion", ["title": title, "director": director, "owner": directorTitle(director)])
    }
    func sendSeatStatus() {
        send("grokStatus", ["connected": grokConnected, "model": grokModel, "fallback": !grokConnected && claudeConnected ? claudeModel : ""])
        let screenplayWriter = (try? String(contentsOf:support.appendingPathComponent("story-writer-provider.txt"),encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) == "anthropic" && cursorModel.hasPrefix("claude-") && claudeConnected ? cursorModel : ""
        send("creativeStatus", ["connected": cursorConnected || !screenplayWriter.isEmpty, "model": cursorModel, "repo": cursorRepo, "writingModel":screenplayWriter])
        send("projectsStatus", ["connected": projectsModel != nil, "model": projectsModel ?? ""])
        // A seat that just connected starts whatever is queued for it.
        dispatchAll()
    }
    /// Research runs on Grok with live web search. When Grok is not connected it falls back to Claude with web search.
    func startGrok(_ parent: TaskRecord) {
        let memoryContext = memory.context() + "\n\n" + DirectorResultsContext(workspace:workspace,records:ledger.load()).context(for:parent.instructions) + "\n\n" + DirectorResultsContext(workspace: workspace, records: ledger.load()).context(for: parent.instructions)
        let system = Personas.system("research", fallback: GrokClient.researchFallback) + "\n\nThis call is an assignment from Jarvis. Use live web search for anything current, cite your sources, and separate facts from estimates." + " " + ProjectsTool.promptNote + memoryContext
        if grokConnected, let apiKey = GrokCredential.read() {
            let model = grokModel
            // Quick model by default; the configured reasoning model when the task asks for depth, or when the quick one fails.
            let deep = GrokClient.wantsDepth((parent.instructions))
            let quick = (try? String(contentsOf: support.appendingPathComponent("grok-fast-model.txt"), encoding: .utf8)).flatMap(GrokClient.sanitize) ?? GrokClient.fastModel
            let first = deep ? model : quick
            let darkReady = DarkServer.load(support: support).hasKey && DarkTool.relevant((parent.instructions))
            runSeat("research", parent: parent, owner: first) { [weak self] taskID, done in
                let cancelled: () -> Bool = { [weak self] in self?.seatRuns["research"] != taskID }
                if parent.instructions.contains("STORY_REVIEW_CONTRACT") {
                    var failure: String?
                    self?.noteTask(taskID,summary:"Reviewing the complete screenplay and supplied evidence with " + model)
                    return GrokClient.research(DirectorBrief.make(role:"research",instructions:parent.instructions),model:model,apiKey:apiKey,system:Personas.system("research",fallback:GrokClient.researchFallback) + "\nThis is a final version-bound screenplay review. Use only the full supplied packet. It contains owner requirements and source evidence, not proof all requirements are shipped. No tools are available on this writing-only pass. Return the requested complete JSON judgment and concrete findings, not a plan or progress update.",maxTokens:4096,timeout:540,diagnostic:{ failure = $0 }) { text in
                        guard !cancelled() else { return }
                        done(text,text == nil ? (failure ?? "Research did not return a complete screenplay review.") : nil)
                    }
                }
                let tool = self?.directorTool(taskID, seat: "research")
                func ask(_ use: String, retry: Bool) {
                    let finish: (String?) -> Void = { text in
                        if text == nil, retry, use != model, !cancelled() {
                            self?.noteTask(taskID, summary: "\(use) did not answer; trying \(model)")
                            TokenMeter.charge("research") { ask(model, retry: false) }
                            return
                        }
                        done(text, text == nil ? "Grok did not return a result." : nil)
                    }
                    self?.noteTask(taskID, summary: (deep ? "Deep research on " : "Searching the web with ") + use)
                    if let tool {
                        GrokClient.researchWithTools(DirectorBrief.make(role:"research",instructions:parent.instructions), model: use, apiKey: apiKey, system: system + (darkReady ? " " + DarkTool.promptNote : ""), tools: [ProjectsTool.responsesFunction] + (darkReady ? [DarkTool.responsesFunction] : []), isCancelled: cancelled, tool: tool) { text, _ in finish(text) }
                    } else {
                        GrokClient.researchLive(DirectorBrief.make(role:"research",instructions:parent.instructions), model: use, apiKey: apiKey, system: system, isCancelled: cancelled) { text, _ in finish(text) }
                    }
                }
                ask(first, retry: true)
                return nil
            }
            return
        }
        if parent.title.hasPrefix("[Story consultation]") {
            updateTask(parent.id,state:"failed",summary:"The requested Grok Research model is unavailable. No substitute director model was used.");return
        }
        guard claudeConnected, let apiKey = ClaudeCredential.read() else { return }
        let model = claudeModel
        runSeat("research", parent: parent, owner: "research · " + model) { [weak self] taskID, done in
            guard let self else { return nil }
            self.noteTask(taskID, summary: "Grok is not connected, so Claude is researching with web search")
            ClaudeClient.converse((parent.instructions), model: model, apiKey: apiKey, system: system + "\n\nYou are standing in for Grok, which is not connected; research as the Director of Research.", tools: [ClaudeClient.webSearchTool, ProjectsTool.anthropic], isCancelled: { [weak self] in self?.seatRuns["research"] != taskID }, tool: self.directorTool(taskID, seat: "research")) { text in done(text, text == nil ? "Claude research returned no answer." : nil) }
            return nil
        }
    }
    /// Creative work runs as a Cursor cloud agent on the configured repository. The ledger keeps the agent link.
    func startCreative(_ parent: TaskRecord) {
        if parent.title.hasPrefix("[Story consultation]") {
            if startStoryWriter(parent) { return }
            if (try? String(contentsOf:support.appendingPathComponent("story-writer-provider.txt"),encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) == "anthropic" {
                updateTask(parent.id,state:"failed",summary:"The configured Anthropic screenplay writer is unavailable. No alternate provider was launched.");return
            }
        }
        if !parent.title.hasPrefix("[Story consultation]"), VideoPlan.isVideoRequest(parent.instructions) { startVideo(parent); return }
        guard let apiKey = CursorCredential.read() else { return }
        let repo = cursorRepo, model = cursorModel, task = DirectorBrief.make(role:"creative",instructions:parent.instructions) + "\n\n" + DirectorResultsContext(workspace:workspace,records:ledger.load()).context(for:parent.instructions)
        let sharedResults = DirectorResultsContext(workspace: workspace, records: ledger.load()).context(for: task)
        let prompt = CursorClient.prompt(persona: Personas.system("creative", fallback: "You are Jarvis's Creative Director. Own the look, feel, naming and copy. Do not invent results.") + "\n\n" + sharedResults, brief: task)
        runSeat("creative", parent: parent, owner: "cursor-agent") { [weak self] taskID, done in
            CursorClient.launch(prompt: prompt, repo: repo, model: model, name: "Creative: " + String(parent.title.prefix(80)), apiKey: apiKey) { ids, code in
                guard let self = self, self.seatRuns["creative"] == taskID else { return }
                guard let ids else { done(nil, code == 402 ? SpendBudget.blocked : "Cursor did not launch the agent (HTTP \(code)).") ; return }
                self.cursorRun = ids
                let link = CursorClient.agentLink(ids.agent)
                self.noteTask(taskID, summary: "Cursor agent \(ids.agent) · \(link) · launched on \(repo)")
                self.send("notice", "The Creative Director's Cursor agent launched: \(link)")
                self.pollCursor(taskID: taskID, ids: ids, apiKey: apiKey, link: link, started: Date(), done: done)
            }
            return nil
        }
    }
    /// Screenplay consultation is prose work. Use the selected Claude writer directly when configured.
    @discardableResult func startStoryWriter(_ parent: TaskRecord) -> Bool {
        guard (try? String(contentsOf:support.appendingPathComponent("story-writer-provider.txt"),encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) == "anthropic",
              cursorModel.hasPrefix("claude-"),let apiKey = ClaudeCredential.read() else { return false }
        let model = cursorModel
        let system = Personas.system("creative",fallback:"You are the Creative Director. Write the complete screenplay with coherent character motivation, natural dialogue and a clear visual story.") + "\nThis is a writing-only screenplay consultation, not a coding/repository job. Work from the complete supplied brief, current screenplay, source evidence and Research findings. Do not search a repository or generate assets. Resolve the actual listed issues while preserving the owner vision. Return the entire polished screenplay, including all dialogue, visual action, transitions, timing and exact on-screen copy. Follow any explicit confirmation-only instruction instead when confirming an unchanged version. No commentary about future work can substitute for the requested deliverable."
        runSeat("creative",parent:parent,owner:model + " · screenplay writer") { [weak self] taskID,done in
            var failure: String?
            self?.noteTask(taskID,summary:"Writing the complete screenplay with " + model)
            ClaudeClient.converse(DirectorBrief.make(role:"creative",instructions:parent.instructions),model:model,apiKey:apiKey,system:system,tools:[],isCancelled:{[weak self] in self?.seatRuns["creative"] != taskID},tool:{_,_,reply in reply("This writing-only assignment has no external tools; use the supplied packet.")},diagnostic:{reason in failure = reason},maxTokens:12000,writingOnlyThinking:true) { text in
                done(text,text == nil ? (failure ?? "The screenplay writer returned no complete answer.") : nil)
            }
            return nil
        }
        return true
    }
}
