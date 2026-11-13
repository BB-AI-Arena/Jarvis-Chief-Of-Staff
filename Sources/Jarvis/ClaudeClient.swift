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
        let meterTag = TokenMeter.tag
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        authorize(&request, apiKey)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1200,
            "system": system,
            "messages": [["role": "user", "content": PromptDelivery.envelope(prompt)]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = BudgetHTTP.dataTask(with: request, seat: meterTag) { data, response, _ in
            TokenMeter.record(meterTag, model: model, data: data)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var text: String?
            if status == 200, let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let blocks = json["content"] as? [[String: Any]], json["stop_reason"] as? String != "max_tokens" {
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
    /// Bounded multi-prompt answers. Partial pages cannot masquerade as a complete result.
    struct AnswerPages {
        enum Step: Equatable { case more, complete, exhausted }
        var remaining = 3
        var parts: [String] = []
        var complete = false
        mutating func append(_ text: String?, limited: Bool) -> Step {
            if let text { parts.append(text) }
            if !limited { complete = text != nil;return complete ? .complete : .exhausted }
            guard remaining > 0, text != nil else { return .exhausted }
            remaining -= 1;return .more
        }
        var result: String? { complete ? parts.joined(separator:"\n") : nil }
    }
    static let continueAnswer = "Your answer reached its response limit. Continue exactly where it ended; do not repeat earlier text or omit unfinished requirements. Return only the remaining numbered sections. If this is the final part, finish the deliverable completely."
    static let maxToolRounds = 8
    /// Claude with tools. The tool handler runs natively and returns text. After `maxToolRounds` the tools are withdrawn so Claude must answer.
    static func converse(_ prompt: String, model: String, apiKey: String, system: String, images: [[String: Any]] = [], tools: [[String: Any]], isCancelled: @escaping () -> Bool, tool: @escaping (String, [String: Any], @escaping (String) -> Void) -> Void, diagnostic: ((String) -> Void)? = nil, maxTokens: Int = 4000, completion: @escaping (String?) -> Void) {
        let meterTag = TokenMeter.tag
        var pages = AnswerPages()
        var messages: [[String: Any]] = [["role": "user", "content": [["type": "text", "text": PromptDelivery.envelope(prompt)]] + images]]
        func round(_ remaining: Int) {
            if isCancelled() { return }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            authorize(&request, apiKey)
            if supportsFallback(model) { request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
            var body: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system, "messages": messages]
            if remaining > 0 { body["tools"] = tools }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            BudgetHTTP.dataTask(with: request, seat: meterTag) { data, response, error in
                TokenMeter.record(meterTag, model: model, data: data)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = status == 200 ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
                DispatchQueue.main.async {
                    if isCancelled() { return }
                    guard let json, let blocks = json["content"] as? [[String: Any]] else {
                        let provider = data.flatMap { (try? JSONSerialization.jsonObject(with:$0)) as? [String:Any] }
                        let message = (provider?["error"] as? [String:Any])?["message"] as? String ?? error?.localizedDescription ?? "Response contained no usable content."
                        diagnostic?("Claude request failed (HTTP \(status)): " + String(message.replacingOccurrences(of:apiKey,with:"[redacted]").prefix(800)))
                        completion(nil);return
                    }
                    if json["stop_reason"] as? String == "max_tokens" {
                        guard toolUses(blocks).isEmpty, pages.append(searchReport(blocks),limited:true) == .more else { diagnostic?("Claude reached its response continuation limit or returned an incomplete tool request; no final result was accepted.");completion(nil);return }
                        messages.append(["role":"assistant","content":blocks])
                        messages.append(["role":"user","content":continueAnswer])
                        round(remaining);return
                    }
                    if json["stop_reason"] as? String == "pause_turn" {
                        guard remaining > 0 else { diagnostic?("Claude exhausted its tool/continuation budget before a final answer.");completion(nil);return }
                        messages.append(["role": "assistant", "content": blocks])
                        round(remaining - 1)
                        return
                    }
                    if json["stop_reason"] as? String == "refusal" { diagnostic?("Claude declined the request; no completed result was returned.");completion(nil);return }
                    let calls = toolUses(blocks)
                    if !calls.isEmpty && remaining == 0 { diagnostic?("Claude exhausted its tool-call budget with requests still pending; no completed result was returned.");completion(nil);return }
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
                                results.append(["type": "tool_result", "tool_use_id": call.id, "content": (output.count > 24000 ? String(output.prefix(24000)) + "\n[TOOL RESULT INCOMPLETE: only the first 24,000 characters were returned. Retrieve the remaining source with a narrower or paged tool call before claiming a full review.]" : output)])
                                next(index + 1)
                            }
                        }
                        next(0)
                        return
                    }
                    _ = pages.append(searchReport(blocks),limited:false)
                    if pages.result == nil { diagnostic?("Claude returned no final answer text.") }
                    completion(pages.result)
                }
            }.resume()
        }
        round(maxToolRounds)
    }
    // MARK: Research with Claude's server-side web search (used when Grok is unavailable).
    static let webSearchTool: [String: Any] = ["type": "web_search_20260209", "name": "web_search", "max_uses": 5]
    /// Models that accept the server-side refusal fallback (`fallbacks: "default"`).
    static func supportsFallback(_ model: String) -> Bool {
        ["claude-opus-5-5", "claude-sonnet-5-5", "claude-opus-5", "claude-fable-5-1", "claude-fable-5-2"].contains(model)
    }
    static func searchBody(model: String, system: String, messages: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = ["model": model, "max_tokens": 8000, "system": system, "tools": [webSearchTool], "messages": messages]
        if supportsFallback(model) { body["fallbacks"] = "default" }
        return body
    }
    /// The answer text followed by the web sources Claude cited (deduplicated, in order).
    static func searchReport(_ blocks: [[String: Any]]) -> String? {
        var parts: [String] = [], cited: [String] = [], searched: [String] = []
        /// Every "url" inside a search result block, however deeply the result list is nested.
        func urls(in value: Any) -> [String] {
            if let item = value as? [String: Any] { return ((item["url"] as? String).map { [$0] } ?? []) + item.values.flatMap { urls(in: $0) } }
            if let list = value as? [Any] { return list.flatMap { urls(in: $0) } }
            return []
        }
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String { parts.append(text) }
                for citation in block["citations"] as? [[String: Any]] ?? [] {
                    if let url = citation["url"] as? String, url.hasPrefix("http"), !cited.contains(url) { cited.append(url) }
                }
            case "web_search_tool_result":
                for url in urls(in: block["content"] ?? []) where url.hasPrefix("http") && !searched.contains(url) { searched.append(url) }
            default: break
            }
        }
        let text = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Prefer what Claude cited; otherwise list the pages its searches returned.
        if !cited.isEmpty { return text + "\n\nSources:\n" + cited.prefix(12).map { "- " + $0 }.joined(separator: "\n") }
        if !searched.isEmpty { return text + "\n\nSources searched:\n" + searched.prefix(8).map { "- " + $0 }.joined(separator: "\n") }
        return text
    }
    /// Claude answers with live web search. Resumes paused turns (the server's search loop has its own limit) up to 3 times.
    /// Completion gets the report, or nil plus a plain reason.
    static func research(_ prompt: String, model: String, apiKey: String, system: String, isCancelled: @escaping () -> Bool, completion: @escaping (String?, String?) -> Void) {
        let meterTag = TokenMeter.tag
        var pages = AnswerPages()
        var messages: [[String: Any]] = [["role": "user", "content": PromptDelivery.envelope(prompt)]]
        func send(_ continuations: Int) {
            if isCancelled() { return }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 300
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            authorize(&request, apiKey)
            if supportsFallback(model) { request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
            request.httpBody = try? JSONSerialization.data(withJSONObject: searchBody(model: model, system: system, messages: messages))
            BudgetHTTP.dataTask(with: request, seat: meterTag) { data, response, _ in
                TokenMeter.record(meterTag, model: model, data: data)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                DispatchQueue.main.async {
                    if isCancelled() { return }
                    guard status == 200, let json, let blocks = json["content"] as? [[String: Any]] else {
                        let message = ((json?["error"] as? [String: Any])?["message"] as? String).map { ": " + String($0.prefix(160)) } ?? ""
                        completion(nil, "Claude research failed (HTTP \(status))" + message); return
                    }
                    switch json["stop_reason"] as? String {
                    case "refusal": completion(nil, "Claude declined this research request.")
                    case "max_tokens" where continuations > 0:
                        guard pages.append(searchReport(blocks),limited:true) == .more else { completion(nil,"Claude research response remains incomplete after its continuation limit.");return }
                        messages.append(["role":"assistant","content":blocks]);messages.append(["role":"user","content":continueAnswer])
                        send(continuations - 1)
                    case "max_tokens" where continuations == 0, "pause_turn" where continuations == 0:
                        completion(nil,"Claude research reached its continuation limit; the response is incomplete.")
                    case "pause_turn" where continuations > 0:
                        // Resend the history with the paused assistant turn; the server resumes the search by itself.
                        messages.append(["role": "assistant", "content": blocks])
                        send(continuations - 1)
                    default:
                        _ = pages.append(searchReport(blocks),limited:false)
                        completion(pages.result, pages.result == nil ? "Claude returned no complete research report." : nil)
                    }
                }
            }.resume()
        }
        send(3)
    }
    private static func authorize(_ request: inout URLRequest, _ apiKey: String) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }
}
