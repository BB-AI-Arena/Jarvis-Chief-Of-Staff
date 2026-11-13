import Foundation

/// Opt-in real API integration check. Uses isolated ledger/results, existing Keychain
/// credentials and the same persistent spending allowance as the app. Never renders.
enum CoreLiveCheck {
    static var app: JarvisApp?
    static func run() {
        let instance = JarvisApp(); app = instance
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/core-live-" + UUID().uuidString)
        instance.support = root.appendingPathComponent("support")
        instance.workspace = root.appendingPathComponent("workspace")
        try! FileManager.default.createDirectory(at: instance.support, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: instance.workspace.appendingPathComponent("Results"), withIntermediateDirectories: true)
        TokenMeter.file = instance.support.appendingPathComponent("usage.json")
        var delivered = 0, pending = 3
        instance.onEvent = { event, payload in
            if event == "resultReady" { delivered += 1 }
        }
        let seats = ["technology", "research", "creative"]
        func launch(_ seat: String, connected: Bool) {
            print("CONNECTION \(seat): \(connected ? "verified" : "failed/missing")")
            switch seat {
            case "technology": instance.claudeConnected = connected
            case "research": instance.grokConnected = connected
            default: instance.cursorConnected = connected
            }
            if connected {
                let task = "Return exactly JARVIS_LIVE_\(seat.uppercased()) followed by one sentence explaining why a failed task must not be reported as completed. Do not use tools, browse, edit files, create branches or open a PR."
                instance.approvedSuggestions.insert(task)
                instance.delegateWork(task, director: seat)
            }
            pending -= 1
        }
        if let key = ClaudeCredential.read() { ClaudeClient.check(key) { launch("technology", connected: $0) } } else { launch("technology", connected: false) }
        if let key = GrokCredential.read() { GrokClient.check(key) { launch("research", connected: $0) } } else { launch("research", connected: false) }
        if let key = CursorCredential.read() { CursorClient.check(key) { launch("creative", connected: $0) } } else { launch("creative", connected: false) }
        let started = Date()
        func finish() {
            let records = instance.ledger.load()
            let outcomes: [[String: Any]] = seats.map { seat in
                let parent = records.first { $0.owner == seat && $0.parentID == nil }
                let file = parent.flatMap { instance.resultFile($0.id) }
                let result = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
                let passed = parent?.state == "completed" && result.contains("JARVIS_LIVE_" + seat.uppercased())
                print("\(passed ? "PASS" : "NOT VERIFIED") \(seat): \(parent?.resultSummary ?? "connection failed")")
                return ["seat":seat,"passed":passed,"state":parent?.state ?? "not_started","summary":parent?.resultSummary ?? "connection failed","savedResult":file?.lastPathComponent ?? "","result":result]
            }
            let report: [String: Any] = ["started":ISO8601DateFormatter().string(from:started),"finished":ISO8601DateFormatter().string(from:Date()),"outcomes":outcomes,"resultReadyEvents":delivered,"usage":TokenMeter.snapshot(),"scope":"Real connection and delegateWork -> provider -> ledger -> saved Result. No microphone or visual playback assertion."]
            let file = root.appendingPathComponent("report.json")
            try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: file)
            print("REPORT " + file.path)
            exit(outcomes.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 2)
        }
        // dispatchMain drives provider callbacks; no NSApplication startup or production workers.
        func poll() {
            let records = instance.ledger.load()
            if pending == 0 && !records.contains(where: { ["running", "proposed"].contains($0.state) }) { finish(); return }
            if Date().timeIntervalSince(started) > 180 { finish(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: poll)
        }
        poll()
    }
}
