import Foundation

/// Native calls to Cursor's Cloud Agents API (v1, public beta) for the Creative Director.
/// Docs: https://cursor.com/docs/cloud-agent/api/endpoints. The API key is a request header only.
enum CursorClient {
    static let base = "https://api.cursor.com"
    static let defaultRepo = "https://github.com/BB-AI-Arena/Jarvis-Chief-Of-Staff"
    static let terminal = ["FINISHED", "ERROR", "CANCELLED", "EXPIRED"]
    /// Empty means Cursor's configured default model; otherwise an id from GET /v1/models.
    static func sanitizeModel(_ raw: String) -> String? {
        let model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty { return "" }
        guard model.range(of: "^[A-Za-z0-9._:-]{2,80}$", options: .regularExpression) != nil else { return nil }
        return model
    }
    /// An https repository URL without credentials.
    static func sanitizeRepo(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 300, let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.path.split(separator: "/").count >= 2 else { return nil }
        return text
    }
    static func agentLink(_ id: String) -> String { "https://cursor.com/agents/" + id }
    /// The brief sent to the cloud agent: the Creative Director persona first, then Jarvis's assignment.
    static func prompt(persona: String, brief: String) -> String {
        persona + "\n\n---\nASSIGNMENT FROM JARVIS (Creative Director brief):\n" + PromptDelivery.envelope(brief)
            + "\n\n---\nReport what you changed or produced, what you verified, and anything left open. Do not claim checks you did not run."
    }
    static func launchBody(prompt: String, repo: String, model: String, name: String) -> [String: Any] {
        var body: [String: Any] = ["prompt": ["text": prompt], "repos": [["url": repo]], "name": String(name.prefix(100))]
        if !model.isEmpty { body["model"] = ["id": model] }
        return body
    }
    /// (agentID, runID) from a Create An Agent response.
    static func parseLaunch(_ data: Data) -> (agent: String, run: String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agent = (json["agent"] as? [String: Any])?["id"] as? String, !agent.isEmpty,
              let run = (json["run"] as? [String: Any])?["id"] as? String ?? (json["agent"] as? [String: Any])?["latestRunId"] as? String, !run.isEmpty else { return nil }
        return (agent, run)
    }
    /// (status, result, prURL) from a Get A Run response.
    static func parseRun(_ data: Data) -> (status: String, result: String?, pr: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let status = json["status"] as? String else { return nil }
        let result = (json["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let branches = (json["git"] as? [String: Any])?["branches"] as? [[String: Any]] ?? []
        let pr = branches.compactMap { $0["prUrl"] as? String }.first
        return (status, (result?.isEmpty ?? true) ? nil : result, pr)
    }
    private static func request(_ path: String, method: String, apiKey: String, body: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }
    /// Connected only when API Key Info (GET /v1/me) returns 200.
    static func check(_ apiKey: String, completion: @escaping (Bool) -> Void) {
        URLSession.shared.dataTask(with: request("/v1/me", method: "GET", apiKey: apiKey)) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
    static func launch(prompt: String, repo: String, model: String, name: String, apiKey: String, completion: @escaping ((agent: String, run: String)?, Int) -> Void) {
        DispatchQueue.main.async { completion(nil, 402) } // No provider-enforced per-run cost ceiling.
    }

    static func run(agent: String, run: String, apiKey: String, completion: @escaping ((status: String, result: String?, pr: String?)?) -> Void) {
        let path = "/v1/agents/\(agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")/runs/\(run.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
        URLSession.shared.dataTask(with: request(path, method: "GET", apiKey: apiKey)) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let parsed = ok ? data.flatMap { parseRun($0) } : nil
            DispatchQueue.main.async { completion(parsed) }
        }.resume()
    }
    static func cancel(agent: String, run: String, apiKey: String) {
        let path = "/v1/agents/\(agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")/runs/\(run.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")/cancel"
        URLSession.shared.dataTask(with: request(path, method: "POST", apiKey: apiKey)).resume()
    }
}
