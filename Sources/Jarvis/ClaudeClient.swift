import Foundation

/// Native Anthropic calls. The API key is a request header only and is never returned.
enum ClaudeClient {
    /// Current Sonnet id from the Claude API model list (coding and agents).
    static let defaultModel = "claude-sonnet-5-5"
    static func sanitize(_ raw: String) -> String? {
        let model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.range(of: "^[A-Za-z0-9._:-]{3,80}$", options: .regularExpression) != nil else { return nil }
        return model
    }
    static func check(_ apiKey: String, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        authorize(&request, apiKey)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
    @discardableResult
    static func review(_ prompt: String, model: String, apiKey: String, completion: @escaping (String?) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        authorize(&request, apiKey)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1200,
            "system": "You are Jarvis's Chief Technology Officer. Answer the engineering request. You cannot edit files from this call. Be concise and do not invent results.",
            "messages": [["role": "user", "content": String(prompt.prefix(12000))]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var text: String?
            if status == 200, let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let blocks = json["content"] as? [[String: Any]] {
                let joined = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { text = joined }
            }
            DispatchQueue.main.async { completion(text) }
        }
        task.resume()
        return task
    }
    private static func authorize(_ request: inout URLRequest, _ apiKey: String) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }
}
