import Foundation

/// One real, minimal call per connection, so "connected" means "answered just now".
/// Keys are read from Keychain and used only as request headers; results never contain them.
struct HealthResult {
    /// ok = a live call succeeded · failed = it did not · off = not configured · configured = set up but deliberately not called (it would start paid work)
    let id: String
    let name: String
    let status: String
    let detail: String
    let ms: Int
    var payload: [String: Any] { ["id": id, "name": name, "status": status, "detail": detail, "ms": ms] }
    var line: String { status.uppercased().padding(toLength: 11, withPad: " ", startingAt: 0) + name + " · " + detail + (ms > 0 ? " · \(ms) ms" : "") }
}

enum HealthCheck {
    static let order = ["luna", "voice", "claude", "grok", "projects", "cursor", "operations"]
    struct Settings {
        var claudeModel = ClaudeClient.defaultModel
        var grokModel = GrokClient.defaultModel
        var projectsModel: String?
        var managerModel: String?
        var cursorRepo = CursorClient.defaultRepo
        /// The same files the app saves from the board settings.
        static func load(support: URL) -> Settings {
            func read(_ name: String) -> String? { try? String(contentsOf: support.appendingPathComponent(name), encoding: .utf8) }
            var settings = Settings()
            if let model = read("claude-model.txt").flatMap(ClaudeClient.sanitize) { settings.claudeModel = model }
            if let model = read("grok-model.txt").flatMap(GrokClient.sanitize) { settings.grokModel = model }
            settings.projectsModel = read("projects-model.txt").flatMap(OllamaClient.sanitize)
            settings.managerModel = read("manager-model.txt").flatMap { OperationsManager.resolve(stored: $0, advertised: []) }
            if let repo = read("cursor-repo.txt").flatMap(CursorClient.sanitizeRepo) { settings.cursorRepo = repo }
            return settings
        }
    }
    static let probe = "Health check. Reply with exactly: OK"

    /// Short, key-free description of an HTTP failure: the status and the provider's own error message if it sent one.
    static func failure(_ status: Int, _ data: Data?) -> String {
        guard status != 0 else { return "no response (network or timeout)" }
        var message = ""
        if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] { message = error["message"] as? String ?? "" }
            else if let error = json["error"] as? String { message = error }
            else if let text = json["message"] as? String { message = text }
        }
        message = message.replacingOccurrences(of: "(sk|xai|key|crsr)[-_][A-Za-z0-9_-]{8,}", with: "[redacted]", options: .regularExpression)
        return "HTTP \(status)" + (message.isEmpty ? "" : ": " + String(message.prefix(160)))
    }
    static func claudeText(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let blocks = json["content"] as? [[String: Any]] else { return nil }
        let text = blocks.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    /// One spoken sentence at launch naming what is not working, or nil when every connection answered.
    static func startupLine(_ results: [HealthResult]) -> String? {
        let down = results.filter { $0.status == "failed" || $0.status == "off" }.map { result -> String in
            let name = result.name.replacingOccurrences(of: " \\(.*\\)", with: "", options: .regularExpression)
            return result.status == "off" ? "\(name) isn't connected" : "\(name) isn't answering"
        }
        guard !down.isEmpty else { return nil }
        let list = down.count == 1 ? down[0] : down.dropLast().joined(separator: ", ") + " and " + down.last!
        return "A quick heads-up: \(list). Everything else is ready."
    }
    static func quote(_ text: String) -> String { "replied “" + String(text.prefix(40)) + "”" }

    private static func call(_ request: URLRequest, done: @escaping (Int, Data?, Int) -> Void) {
        let start = Date()
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            DispatchQueue.main.async { done(status, data, ms) }
        }.resume()
    }
    private static func request(_ url: String, method: String = "GET", headers: [String: String], body: [String: Any]? = nil, timeout: TimeInterval = 60) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.timeoutInterval = timeout
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// Runs every check in parallel. `brain` is the app's own Luna connection, so the check uses the real routing path.
    static func run(settings: Settings, brain: ConversationBrain, includeLuna: Bool = true, completion: @escaping ([HealthResult]) -> Void) {
        var results: [String: HealthResult] = [:]
        var pending = order.count
        func finish(_ result: HealthResult) {
            guard results[result.id] == nil else { return }
            results[result.id] = result
            pending -= 1
            if pending == 0 { completion(order.compactMap { results[$0] }) }
        }

        // OpenAI realtime voice: confirm the key. Opening a voice session would start paid audio, so it is not opened.
        if let key = VoiceCredential.read()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            call(request("https://api.openai.com/v1/models", headers: ["Authorization": "Bearer " + key], timeout: 20)) { status, data, ms in
                finish(HealthResult(id: "voice", name: "OpenAI realtime voice", status: status == 200 ? "ok" : "failed", detail: status == 200 ? "key accepted (voice session not opened)" : failure(status, data), ms: ms))
            }
        } else { finish(HealthResult(id: "voice", name: "OpenAI realtime voice", status: "off", detail: "no key in Keychain", ms: 0)) }

        // Claude (CTO): one tiny message on the configured model.
        if let key = ClaudeCredential.read() {
            let body: [String: Any] = ["model": settings.claudeModel, "max_tokens": 16, "messages": [["role": "user", "content": probe]]]
            call(request("https://api.anthropic.com/v1/messages", method: "POST", headers: ["x-api-key": key, "anthropic-version": "2023-06-01"], body: body)) { status, data, ms in
                let text = status == 200 ? data.flatMap(claudeText) : nil
                finish(HealthResult(id: "claude", name: "Claude (CTO)", status: text == nil ? "failed" : "ok", detail: settings.claudeModel + " · " + (text.map(quote) ?? failure(status, data)), ms: ms))
            }
        } else { finish(HealthResult(id: "claude", name: "Claude (CTO)", status: "off", detail: "no Anthropic key in Keychain", ms: 0)) }

        // Grok (Research): one tiny completion on the configured model.
        if let key = GrokCredential.read() {
            var body = GrokClient.requestBody(probe, model: settings.grokModel, system: "You are a health check. Reply with exactly: OK")
            body["max_tokens"] = 16
            call(request("https://api.x.ai/v1/chat/completions", method: "POST", headers: ["Authorization": "Bearer " + key], body: body)) { status, data, ms in
                let text = status == 200 ? data.flatMap(GrokClient.text) : nil
                finish(HealthResult(id: "grok", name: "Grok (Research)", status: text == nil ? "failed" : "ok", detail: settings.grokModel + " · " + (text.map(quote) ?? failure(status, data)), ms: ms))
            }
        } else { finish(HealthResult(id: "grok", name: "Grok (Research)", status: "off", detail: "no xAI key in Keychain", ms: 0)) }

        // Projects: one tiny local Ollama chat on the chosen model.
        if let model = settings.projectsModel {
            call(request(OllamaClient.base + "/api/chat", method: "POST", headers: [:], body: OllamaClient.requestBody(probe, model: model, system: "You are a health check. Reply with exactly: OK"), timeout: 120)) { status, data, ms in
                let text = status == 200 ? data.flatMap(OllamaClient.text) : nil
                finish(HealthResult(id: "projects", name: "Projects (local Ollama)", status: text == nil ? "failed" : "ok", detail: model + " · " + (text.map(quote) ?? (status == 0 ? "Ollama is not responding on this Mac" : failure(status, data))), ms: ms))
            }
        } else { finish(HealthResult(id: "projects", name: "Projects (local Ollama)", status: "off", detail: "no local model chosen", ms: 0)) }

        // Cursor (Creative): authentication only. Launching an agent starts paid cloud work on a repository.
        if let key = CursorCredential.read() {
            call(request(CursorClient.base + "/v1/me", headers: ["Authorization": "Bearer " + key], timeout: 20)) { status, data, ms in
                finish(HealthResult(id: "cursor", name: "Cursor (Creative)", status: status == 200 ? "ok" : "failed", detail: status == 200 ? "key accepted · repo " + settings.cursorRepo.replacingOccurrences(of: "https://", with: "") + " · no agent launched" : failure(status, data), ms: ms))
            }
        } else { finish(HealthResult(id: "cursor", name: "Cursor (Creative)", status: "off", detail: "no Cursor key in Keychain", ms: 0)) }

        // Operations: configuration only. Running the worker edits the source workspace.
        if AgentRuntime.executable == nil {
            finish(HealthResult(id: "operations", name: "Operations worker", status: "failed", detail: "agent runtime not configured", ms: 0))
        } else {
            let worker = OperationsManager.worker(manager: settings.managerModel)
            finish(HealthResult(id: "operations", name: "Operations worker", status: "configured", detail: worker.model + (worker.config.isEmpty ? " (no manager set)" : " · " + OperationsManager.effort) + " · not run (it edits the workspace)", ms: 0))
        }

        // Luna last: Keychain reads above can block on a macOS prompt, which must not eat into Luna's reply timeout.
        // Luna is the routing brain every voice hand-off and typed request goes through.
        let lunaStart = Date()
        if AgentRuntime.executable == nil {
            finish(HealthResult(id: "luna", name: "Luna (Jarvis routing)", status: "failed", detail: "agent runtime not configured", ms: 0))
        } else if !includeLuna {
            finish(HealthResult(id: "luna", name: "Luna (Jarvis routing)", status: "configured", detail: "fallback router · not called at launch; run the health check to test it", ms: 0))
        } else if brain.busy {
            finish(HealthResult(id: "luna", name: "Luna (Jarvis routing)", status: "failed", detail: "busy with another request; run the check again", ms: 0))
        } else {
            brain.ask("Health check: reply briefly that you are online.", history: "") { text, route, _, error in
                let ms = Int(Date().timeIntervalSince(lunaStart) * 1000)
                if let error { finish(HealthResult(id: "luna", name: "Luna (Jarvis routing)", status: "failed", detail: String(error.prefix(200)), ms: ms)) }
                else { finish(HealthResult(id: "luna", name: "Luna (Jarvis routing)", status: "ok", detail: "gpt-6-luna · route \(route ?? "?") · " + quote(text ?? ""), ms: ms)) }
            }
        }
    }
}
