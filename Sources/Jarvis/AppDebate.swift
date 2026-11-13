import AppKit
import WebKit
import AVFoundation
import Speech

extension JarvisApp {
    func debateSpeakers() -> [(seat: String, model: String, ask: (String, String, @escaping (String?) -> Void) -> URLSessionDataTask)] {
        var speakers: [(seat: String, model: String, ask: (String, String, @escaping (String?) -> Void) -> URLSessionDataTask)] = []
        if claudeConnected, let key = ClaudeCredential.read() {
            let model = claudeModel
            speakers.append(("cto", model, { prompt, system, done in TokenMeter.charge("technology") { ClaudeClient.review(prompt, model: model, apiKey: key, system: system, completion: done) } }))
        }
        if grokConnected, let key = GrokCredential.read() {
            let model = grokModel
            speakers.append(("research", model, { prompt, system, done in TokenMeter.charge("research") { GrokClient.research(prompt, model: model, apiKey: key, system: system, completion: done) } }))
        }
        if let model = projectsModel {
            speakers.append(("projects", model, { prompt, system, done in TokenMeter.charge("projects") { OllamaClient.chat(prompt, model: model, system: system, completion: done) } }))
        }
        return speakers
    }
    /// A live debate: each connected director answers in parallel per round, then a chair call checks for consensus. At most three rounds.
    /// Starts a debate and returns what Jarvis should say. `liveUpdate` receives the verdict when a voice delegation asked for it.
    @discardableResult
    func startDebate(_ raw: String, liveUpdate: ((String) -> Void)? = nil) -> (started: Bool, message: String) {
        guard debateTaskID == nil else { return (false, "The board is already debating another question. I'll report that verdict first.") }
        guard let topic = BoardDebate.clean(topic: raw) else { return (false, "Give the board a question to debate.") }
        let speakers = debateSpeakers()
        guard speakers.count >= 2 else {
            let connected = speakers.map { BoardDebate.title($0.seat) }
            return (false, "A real debate needs at least two connected directors: Claude for the CTO, Grok for Research, or a local model for Projects. Connected now: " + (connected.isEmpty ? "none" : connected.joined(separator: ", ")) + ". Nothing was started.")
        }
        let now = TaskLedger.timestamp(), taskID = UUID().uuidString
        var records = ledger.load()
        records.insert(TaskRecord(id: taskID, state: "running", verified: false, owner: "board", parentID: nil, createdAt: now, updatedAt: now, resultSummary: "Round 1 of up to \(BoardDebate.maxRounds)", title: String(("Board debate: " + topic).prefix(500))), at: 0)
        publishTasks(records)
        debateTaskID = taskID
        debateLiveUpdate = liveUpdate
        debateVoice = liveUpdate == nil ? nil : liveVoice
        send("debateStarted", ["id": taskID, "topic": topic, "seats": speakers.map { $0.seat }])
        debateRound(1, topic: topic, turns: [], speakers: speakers, taskID: taskID)
        return (true, BoardDebate.acknowledgement(seats: speakers.map { $0.seat }))
    }
    /// Says the verdict through the live voice when one is running ("voice"); otherwise the page speaks it ("page").
    func announceDebate(_ line: String) -> String {
        if let update = debateLiveUpdate, let live = liveVoice, live === debateVoice { update(line); return "voice" }
        if let live = liveVoice { live.announce(line); return "voice" }
        return "page"
    }
    func debateRound(_ round: Int, topic: String, turns: [BoardDebate.Turn], speakers: [(seat: String, model: String, ask: (String, String, @escaping (String?) -> Void) -> URLSessionDataTask)], taskID: String) {
        guard debateTaskID == taskID, !quitting else { return }
        var replies = [String?](repeating: nil, count: speakers.count)
        var pending = speakers.count
        for (index, speaker) in speakers.enumerated() {
            let system = BoardDebate.turnSystem(persona: Personas.system(speaker.seat, fallback: "You are Jarvis's " + BoardDebate.title(speaker.seat) + ".")) + memory.context() + "\n\n" + DirectorResultsContext(workspace: workspace, records: ledger.load()).context(for: topic)
            let prompt = BoardDebate.turnPrompt(topic: topic, round: round, seat: speaker.seat, turns: turns)
            debateRequests.append(speaker.ask(prompt, system) { [weak self] text in
                guard let self = self, self.debateTaskID == taskID else { return }
                replies[index] = text.map { BoardDebate.spoken($0) }.flatMap { $0.isEmpty ? nil : $0 }
                pending -= 1
                guard pending == 0 else { return }
                self.debateRequests = []
                let said = speakers.indices.compactMap { i in replies[i].map { BoardDebate.Turn(seat: speakers[i].seat, round: round, text: $0) } }
                let silent = speakers.indices.filter { replies[$0] == nil }.map { speakers[$0].seat }
                guard !said.isEmpty else { self.failDebate(taskID, "No director answered in round \(round). Nothing was decided."); return }
                self.send("debateRound", ["id": taskID, "round": round, "turns": said.map { ["seat": $0.seat, "text": $0.text] }, "silent": silent])
                self.noteTask(taskID, summary: "Round \(round) of up to \(BoardDebate.maxRounds) · " + said.map { BoardDebate.title($0.seat) }.joined(separator: ", ") + " spoke")
                self.judgeDebate(round, topic: topic, turns: turns + said, speakers: speakers, taskID: taskID)
            })
        }
    }
    func judgeDebate(_ round: Int, topic: String, turns: [BoardDebate.Turn], speakers: [(seat: String, model: String, ask: (String, String, @escaping (String?) -> Void) -> URLSessionDataTask)], taskID: String) {
        guard debateTaskID == taskID, let chair = speakers.first else { return }
        let final = round >= BoardDebate.maxRounds
        debateRequests.append(chair.ask(BoardDebate.judgePrompt(topic: topic, turns: turns, finalRound: final), BoardDebate.judgeSystem) { [weak self] raw in
            guard let self = self, self.debateTaskID == taskID else { return }
            self.debateRequests = []
            let verdict = raw.flatMap { BoardDebate.verdict(from: $0) }
            if verdict?.agreed == true || final {
                let summary = BoardDebate.summary(topic: topic, turns: turns, verdict: verdict, rounds: round, chair: chair.model)
                self.updateTask(taskID, state: "completed", summary: String(summary.prefix(4000)))
                let line = BoardDebate.announcement(verdict: verdict, rounds: round)
                self.memory.append(kind: "Board debate", text: topic + " → " + (verdict.map { ($0.agreed ? "agreed: " : "no consensus: ") + $0.decision } ?? "no verdict"))
                self.send("debateResult", ["id": taskID, "announcement": line, "announce": self.announceDebate(line), "agreed": verdict?.agreed == true, "topic": topic, "decision": verdict?.decision ?? "The chair could not summarise the outcome.", "rounds": round, "chair": chair.model, "transcript": BoardDebate.transcript(turns)])
                self.endDebate()
            } else {
                self.debateRound(round + 1, topic: topic, turns: turns, speakers: speakers, taskID: taskID)
            }
        })
    }
    func failDebate(_ taskID: String, _ message: String) {
        updateTask(taskID, state: "failed", summary: message)
        send("debateResult", ["id": taskID, "failed": true, "agreed": false, "decision": message, "announcement": message, "announce": announceDebate(message)])
        endDebate()
    }
    func endDebate() {
        debateRequests.forEach { $0.cancel() }
        debateRequests = []
        debateTaskID = nil
        debateLiveUpdate = nil
        debateVoice = nil
    }
}
