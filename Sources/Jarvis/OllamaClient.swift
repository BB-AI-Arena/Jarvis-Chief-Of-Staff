import Foundation

/// Ollama calls for the Director of Projects: on Brandon's 4090 server ("DARK") when it answers, otherwise on this Mac.
/// Nothing leaves the local network.
enum OllamaClient {
    static let local = "http://127.0.0.1:11434"
    static let defaultServer = "http://192.168.4.31:11434"
    /// The model server in use. Set by the app at launch; the 4090 by default.
    static var base = defaultServer
    /// A LAN or loopback http(s) URL without credentials, path or query.
    static func sanitizeHost(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.path.isEmpty || url.path == "/" else { return nil }
        let privateHost = host == "localhost" || host == "127.0.0.1" || host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasSuffix(".local")
            || host.range(of: "^172\\.(1[6-9]|2[0-9]|3[01])\\.", options: .regularExpression) != nil
        return privateHost ? text : nil
    }
    static let projectsFallback = "You are Jarvis's Director of Projects. Turn the request into a plan: milestones, owners by director, dates, what was cut, risks, and one next move. Be concise and do not invent results."
    /// Ollama tags look like `name:tag` or `namespace/name:tag`.
    static func sanitize(_ raw: String) -> String? {
        let model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.range(of: "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$", options: .regularExpression) != nil, !model.contains("..") else { return nil }
        return model
    }
    static func models(at host: String = base, completion: @escaping ([String]?) -> Void) {
        var request = URLRequest(url: URL(string: host + "/api/tags")!)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let names = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.flatMap { $0["models"] as? [[String: Any]] }?.compactMap { $0["name"] as? String }
            DispatchQueue.main.async { completion(names) }
        }.resume()
    }
    static func requestBody(_ prompt: String, model: String, system: String) -> [String: Any] {
        ["model": model, "stream": false, "think": false, "keep_alive": "30m", "options": ["num_ctx": 8192, "num_predict": 900],
         "messages": [["role": "system", "content": system], ["role": "user", "content": String(prompt.prefix(12000))]]]
    }
    static func text(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = json["message"] as? [String: Any], let content = message["content"] as? String else { return nil }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    @discardableResult
    static func chat(_ prompt: String, model: String, system: String, host: String = base, completion: @escaping (String?) -> Void) -> URLSessionDataTask {
        let meterTag = TokenMeter.tag
        var request = URLRequest(url: URL(string: host + "/api/chat")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody(prompt, model: model, system: system))
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            TokenMeter.record(meterTag, model: model, data: data)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = status == 200 ? data.flatMap { OllamaClient.text(from: $0) } : nil
            DispatchQueue.main.async { completion(text) }
        }
        task.resume()
        return task
    }
}
