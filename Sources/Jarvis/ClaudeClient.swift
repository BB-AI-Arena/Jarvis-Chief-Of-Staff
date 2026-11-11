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
    static let ctoFallback = "You are Jarvis's Chief Technology Officer. Answer the engineering request. You can read the workspace with your tools but cannot edit files or run commands. Be concise and do not invent results."
    @discardableResult
    static func review(_ prompt: String, model: String, apiKey: String, system: String = ClaudeClient.ctoFallback, completion: @escaping (String?) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        authorize(&request, apiKey)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1200,
            "system": system,
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
    /// Tool calls requested in a Messages API response, as (id, name, brief). `brief` is the tool input's "brief" string, if any.
    static func toolCalls(_ blocks: [[String: Any]]) -> [(id: String, name: String, brief: String)] {
        blocks.compactMap { block in
            guard block["type"] as? String == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
            let brief = (block["input"] as? [String: Any])?["brief"] as? String ?? ""
            return (id, name, brief)
        }
    }
    /// Tool calls with their full input, as (id, name, input).
    static func toolUses(_ blocks: [[String: Any]]) -> [(id: String, name: String, input: [String: Any])] {
        blocks.compactMap { block in
            guard block["type"] as? String == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
            return (id, name, block["input"] as? [String: Any] ?? [:])
        }
    }
    static let maxToolRounds = 8
    /// Claude with tools. The tool handler runs natively and returns text. After `maxToolRounds` the tools are withdrawn so Claude must answer.
    static func converse(_ prompt: String, model: String, apiKey: String, system: String, tools: [[String: Any]], isCancelled: @escaping () -> Bool, tool: @escaping (String, [String: Any], @escaping (String) -> Void) -> Void, completion: @escaping (String?) -> Void) {
        var messages: [[String: Any]] = [["role": "user", "content": String(prompt.prefix(12000))]]
        func round(_ remaining: Int) {
            if isCancelled() { return }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            authorize(&request, apiKey)
            var body: [String: Any] = ["model": model, "max_tokens": 4000, "system": system, "messages": messages]
            if remaining > 0 { body["tools"] = tools }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request) { data, response, _ in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = status == 200 ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
                DispatchQueue.main.async {
                    if isCancelled() { return }
                    guard let json, let blocks = json["content"] as? [[String: Any]] else { completion(nil); return }
                    let calls = toolUses(blocks)
                    if json["stop_reason"] as? String == "tool_use", !calls.isEmpty, remaining > 0 {
                        messages.append(["role": "assistant", "content": blocks])
                        var results: [[String: Any]] = []
                        func next(_ index: Int) {
                            if index == calls.count {
                                if remaining == 1 { results.append(["type": "text", "text": "That was the last tool call available. Answer now with what you have, and say what you could not check."]) }
                                messages.append(["role": "user", "content": results])
                                round(remaining - 1)
                                return
                            }
                            let call = calls[index]
                            tool(call.name, call.input) { output in
                                results.append(["type": "tool_result", "tool_use_id": call.id, "content": String(output.prefix(24000))])
                                next(index + 1)
                            }
                        }
                        next(0)
                        return
                    }
                    let joined = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(joined.isEmpty ? nil : joined)
                }
            }.resume()
        }
        round(maxToolRounds)
    }
    private static func authorize(_ request: inout URLRequest, _ apiKey: String) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }
}
