import Foundation

/// Native xAI calls for the Director of Research. The API key is a request header only and is never returned.
enum GrokClient {
    /// xAI's recommended model for chat and code (docs.x.ai/docs/models, checked 2026-11-09).
    static let defaultModel = "grok-4.7"
    static let researchFallback = "You are Jarvis's Director of Research. Answer the research request concisely. Separate facts from estimates, cite sources when you have them, say when information may be out of date, and do not invent results."
    static func sanitize(_ raw: String) -> String? {
        let model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.range(of: "^[A-Za-z0-9._:-]{3,80}$", options: .regularExpression) != nil else { return nil }
        return model
    }
    static func check(_ apiKey: String, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/models")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        authorize(&request, apiKey)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
    static func requestBody(_ prompt: String, model: String, system: String) -> [String: Any] {
        ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": String(prompt.prefix(12000))]]]
    }
    static func text(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String else { return nil }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    /// Live web search through xAI's Responses API (docs.x.ai/docs/guides/tools/search-tools, checked 2026-11-10).
    static func searchBody(_ prompt: String, model: String, system: String) -> [String: Any] {
        ["model": model, "tools": [["type": "web_search"]],
         "input": [["role": "system", "content": system], ["role": "user", "content": String(prompt.prefix(12000))]]]
    }
    /// Final text of a Responses API reply, followed by the cited URLs when the reply carries them.
    static func searchText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let output = json["output"] as? [[String: Any]] else { return nil }
        var parts: [String] = [], sources: [String] = []
        for item in output where item["type"] as? String == "message" {
            for block in item["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "output_text" {
                if let text = block["text"] as? String { parts.append(text) }
                for note in block["annotations"] as? [[String: Any]] ?? [] {
                    if let url = note["url"] as? String, url.hasPrefix("http"), !sources.contains(url) { sources.append(url) }
                }
            }
        }
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return sources.isEmpty ? text : text + "\n\nSources:\n" + sources.prefix(12).map { "- " + $0 }.joined(separator: "\n")
    }
    /// Research with live web search. If xAI refuses the search call, falls back to the plain model and says so.
    static func researchLive(_ prompt: String, model: String, apiKey: String, system: String, isCancelled: @escaping () -> Bool, completion: @escaping (String?, Bool) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, apiKey)
        request.httpBody = try? JSONSerialization.data(withJSONObject: searchBody(prompt, model: model, system: system))
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = status == 200 ? data.flatMap { GrokClient.searchText(from: $0) } : nil
            DispatchQueue.main.async {
                if isCancelled() { return }
                if let text { completion(text, true); return }
                research(prompt, model: model, apiKey: apiKey, system: system + "\n\nLive web search was not available on this call, so say when your information may be out of date.") { completion($0, false) }
            }
        }.resume()
    }
    @discardableResult
    static func research(_ prompt: String, model: String, apiKey: String, system: String = GrokClient.researchFallback, completion: @escaping (String?) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, apiKey)
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody(prompt, model: model, system: system))
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = status == 200 ? data.flatMap { GrokClient.text(from: $0) } : nil
            DispatchQueue.main.async { completion(text) }
        }
        task.resume()
        return task
    }
    private static func authorize(_ request: inout URLRequest, _ apiKey: String) {
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
    }
}
