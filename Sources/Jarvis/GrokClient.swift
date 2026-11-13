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
        ["model": model, "max_tokens": 1200, "messages": [["role": "system", "content": system], ["role": "user", "content": PromptDelivery.envelope(prompt)]]]
    }
    static func text(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = json["choices"] as? [[String: Any]],
              choices.first?["finish_reason"] as? String != "length",
              let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String else { return nil }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    /// Live web search through xAI's Responses API (docs.x.ai/docs/guides/tools/search-tools, checked 2026-11-10).
    static func searchBody(_ prompt: String, model: String, system: String) -> [String: Any] {
        ["model": model, "tools": [["type": "web_search"]],
         "input": [["role": "system", "content": system], ["role": "user", "content": PromptDelivery.envelope(prompt)]]]
    }
    /// Final text of a Responses API reply, followed by the cited URLs when the reply carries them.
    static func searchText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["status"] as? String != "incomplete", functionCalls(from:json).isEmpty,let output = json["output"] as? [[String: Any]] else { return nil }
        var parts: [String] = [], sources: [String] = []
        for item in output where item["type"] as? String == "message" && item["phase"] as? String != "commentary" && item["channel"] as? String != "commentary" {
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
        let meterTag = TokenMeter.tag
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, apiKey)
        request.httpBody = try? JSONSerialization.data(withJSONObject: searchBody(prompt, model: model, system: system))
        BudgetHTTP.dataTask(with: request, seat: meterTag) { data, response, _ in
            TokenMeter.record(meterTag, model: model, data: data)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = status == 200 ? data.flatMap { GrokClient.searchText(from: $0) } : nil
            DispatchQueue.main.async {
                if isCancelled() { return }
                if let text { completion(text, true); return }
                TokenMeter.charge(meterTag ?? "jarvis") { research(prompt, model: model, apiKey: apiKey, system: system + "\n\nLive web search was not available on this call, so say when your information may be out of date.") { completion($0, false) } }
            }
        }.resume()
    }
    /// Function calls in a Responses API reply: (call id, name, arguments).
    static func functionCalls(from json: [String: Any]) -> [(id: String, name: String, input: [String: Any])] {
        (json["output"] as? [[String: Any]] ?? []).compactMap { item in
            guard item["type"] as? String == "function_call", let id = item["call_id"] as? String, let name = item["name"] as? String else { return nil }
            return (id, name, DarkTool.arguments(item["arguments"]))
        }
    }
    static let maxToolRounds = 4
    /// Quick research model (no extended thinking). Measured 2026-11-12: about 10 s for a web-search task against about 35 s on grok-4.7.
    static let fastModel = "grok-4.20-0309-non-reasoning"
    /// True when the task asks for depth, so the configured reasoning model is worth its time and cost.
    static func wantsDepth(_ task: String) -> Bool {
        let lower = task.lowercased()
        return ["deep", "in depth", "in-depth", "thorough", "careful", "comprehensive", "detailed analysis", "rigorous", "exhaustive"].contains { lower.contains($0) }
    }
    /// Research with live web search plus Jarvis's own tools (run_on_dark). Tool calls run natively and are fed back with
    /// previous_response_id. If xAI refuses the first call, it falls back to researchLive without the tools.
    static func researchWithTools(_ prompt: String, model: String, apiKey: String, system: String, tools: [[String: Any]], isCancelled: @escaping () -> Bool, tool: @escaping (String, [String: Any], @escaping (String) -> Void) -> Void, completion: @escaping (String?, Bool) -> Void) {
        let meterTag = TokenMeter.tag
        func send(_ body: [String: Any], remaining: Int, first: Bool) {
            if isCancelled() { return }
            var request = URLRequest(url: URL(string: "https://api.x.ai/v1/responses")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 240
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            authorize(&request, apiKey)
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            BudgetHTTP.dataTask(with: request, seat: meterTag) { data, response, _ in
                TokenMeter.record(meterTag, model: model, data: data)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = status == 200 ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
                DispatchQueue.main.async {
                    if isCancelled() { return }
                    guard let json else {
                        if first { TokenMeter.charge(meterTag ?? "jarvis") { researchLive(prompt, model: model, apiKey: apiKey, system: system, isCancelled: isCancelled, completion: completion) } }
                        else { completion(nil, true) }
                        return
                    }
                    let calls = functionCalls(from: json)
                    guard !calls.isEmpty, remaining > 0, let id = json["id"] as? String else {
                        completion(data.flatMap(searchText), true); return
                    }
                    var outputs: [[String: Any]] = []
                    func next(_ index: Int) {
                        if index == calls.count {
                            var body: [String: Any] = ["model": model, "previous_response_id": id, "input": outputs]
                            // Follow-up rounds get Jarvis's tools only: re-running web search each round cost hundreds of thousands of tokens.
                            if remaining > 1 { body["tools"] = tools }
                            send(body, remaining: remaining - 1, first: false)
                            return
                        }
                        tool(calls[index].name, calls[index].input) { output in
                            outputs.append(["type": "function_call_output", "call_id": calls[index].id, "output": (output.count > 24000 ? String(output.prefix(24000)) + "\n[TOOL RESULT INCOMPLETE: only the first 24,000 characters were returned. Retrieve the remaining source with a narrower or paged tool call before claiming a full review.]" : output)])
                            next(index + 1)
                        }
                    }
                    next(0)
                }
            }.resume()
        }
        var body = searchBody(prompt, model: model, system: system)
        body["tools"] = [["type": "web_search"]] + tools
        send(body, remaining: maxToolRounds, first: true)
    }
    @discardableResult
    static func research(_ prompt: String, model: String, apiKey: String, system: String = GrokClient.researchFallback, maxTokens: Int = 1200, diagnostic: ((String) -> Void)? = nil, completion: @escaping (String?) -> Void) -> URLSessionDataTask {
        let meterTag = TokenMeter.tag
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, apiKey)
        var body = requestBody(prompt, model: model, system: system)
        body["max_tokens"] = maxTokens
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = BudgetHTTP.dataTask(with: request, seat: meterTag) { data, response, error in
            TokenMeter.record(meterTag, model: model, data: data)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = status == 200 ? data.flatMap { GrokClient.text(from: $0) } : nil
            DispatchQueue.main.async {
                if text == nil {
                    let value = data.flatMap { (try? JSONSerialization.jsonObject(with:$0)) as? [String:Any] }
                    let message = (value?["error"] as? [String:Any])?["message"] as? String ?? error?.localizedDescription ?? "No complete final answer (possibly response limit)."
                    diagnostic?("Grok request failed (HTTP \(status)): " + String(message.replacingOccurrences(of:apiKey,with:"[redacted]").prefix(800)))
                }
                completion(text)
            }
        }
        task.resume()
        return task
    }
    private static func authorize(_ request: inout URLRequest, _ apiKey: String) {
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
    }
}
