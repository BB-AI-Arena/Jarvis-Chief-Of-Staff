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
    /// Model metadata checked locally: qwen35 262,144; gemma4 131,072 tokens.
    /// UTF-8 bytes are a conservative input allowance, not an exact token estimate.
    static func contextCapacity(_ model: String) -> Int {
        if model.hasPrefix("qwen3.5") { return 262144 }
        if model.hasPrefix("gemma4") { return 131072 }
        return 8192
    }
    static func inputBytes(_ messages: [[String:Any]], tools: [[String:Any]] = []) -> Int {
        (try? JSONSerialization.data(withJSONObject:["messages":messages,"tools":tools]).count) ?? Int.max / 2
    }
    static func inputContext(_ messages: [[String:Any]], tools: [[String:Any]] = [], model: String) -> Int {
        min(contextCapacity(model),max(8192,((inputBytes(messages,tools:tools)+8191)/4096)*4096))
    }
    static func fitsContext(_ messages: [[String:Any]], tools: [[String:Any]] = [], model: String) -> Bool {
        inputBytes(messages,tools:tools) + 4096 <= contextCapacity(model)
    }
    static func requestBody(_ prompt: String, model: String, system: String) -> [String: Any] {
        let messages: [[String:Any]] = [["role":"system","content":system],["role":"user","content":PromptDelivery.envelope(prompt)]]
        return ["model":model,"stream":false,"think":false,"keep_alive":"30m","options":["num_ctx":inputContext(messages,model:model),"num_predict":900],"messages":messages]
    }
    static func text(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["done_reason"] as? String != "length",let message = json["message"] as? [String: Any], let content = message["content"] as? String else { return nil }
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
        if fitsContext(requestBody(prompt,model:model,system:system)["messages"] as! [[String:Any]],model:model) { task.resume() }
        else { task.cancel();DispatchQueue.main.async { completion(nil) } }
        return task
    }
    static let maxToolRounds = 6
    /// Chat with tools (Ollama /api/chat "tools"). Tool calls run natively and go back as role "tool" messages.
    /// Completion gets nil when the model never answers; a model that does not support tools gets one plain chat instead.
    static func converse(_ prompt: String, model: String, system: String, host: String = base, tools: [[String: Any]], isCancelled: @escaping () -> Bool, tool: @escaping (String, [String: Any], @escaping (String) -> Void) -> Void, completion: @escaping (String?) -> Void) {
        let meterTag = TokenMeter.tag
        var messages: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": PromptDelivery.envelope(prompt)]]
        func round(_ remaining: Int) {
            if isCancelled() { return }
            var body = requestBody(prompt, model: model, system: system)
            body["messages"] = messages
            if remaining > 0 { body["tools"] = tools }
            body["options"] = ["num_ctx":inputContext(messages,tools:remaining > 0 ? tools : [],model:model),"num_predict":900]
            guard fitsContext(messages,tools:remaining > 0 ? tools : [],model:model) else { completion(nil);return }
            var request = URLRequest(url: URL(string: host + "/api/chat")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 240
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request) { data, response, _ in
                TokenMeter.record(meterTag, model: model, data: data)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = status == 200 ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
                DispatchQueue.main.async {
                    if isCancelled() { return }
                    guard let json, let message = json["message"] as? [String: Any] else {
                        // e.g. "does not support tools": answer without them once.
                        if remaining == maxToolRounds { TokenMeter.charge(meterTag ?? "jarvis") { chat(prompt, model: model, system: system, host: host, completion: completion) } }
                        else { completion(nil) }
                        return
                    }
                    guard json["done_reason"] as? String != "length" else { completion(nil);return }
                    let calls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { call -> (String, [String: Any])? in
                        guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
                        return (name, DarkTool.arguments(function["arguments"]))
                    }
                    if calls.isEmpty || remaining == 0 {
                        let text = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        completion(text.isEmpty ? nil : text); return
                    }
                    messages.append(message)
                    func next(_ index: Int) {
                        if index == calls.count { round(remaining - 1); return }
                        tool(calls[index].0, calls[index].1) { output in
                            messages.append(["role": "tool", "tool_name": calls[index].0, "content": output])
                            next(index + 1)
                        }
                    }
                    next(0)
                }
            }.resume()
        }
        round(maxToolRounds)
    }
}
