import Foundation

/// Local Ollama calls for the Director of Projects. Nothing leaves this Mac.
enum OllamaClient {
    static let base = "http://127.0.0.1:11434"
    static let projectsFallback = "You are Jarvis's Director of Projects. Turn the request into a plan: milestones, owners by director, dates, what was cut, risks, and one next move. Be concise and do not invent results."
    /// Ollama tags look like `name:tag` or `namespace/name:tag`.
    static func sanitize(_ raw: String) -> String? {
        let model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.range(of: "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$", options: .regularExpression) != nil, !model.contains("..") else { return nil }
        return model
    }
    static func models(completion: @escaping ([String]?) -> Void) {
        var request = URLRequest(url: URL(string: base + "/api/tags")!)
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
    static func chat(_ prompt: String, model: String, system: String, completion: @escaping (String?) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: URL(string: base + "/api/chat")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody(prompt, model: model, system: system))
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = status == 200 ? data.flatMap { OllamaClient.text(from: $0) } : nil
            DispatchQueue.main.async { completion(text) }
        }
        task.resume()
        return task
    }
}
