import Foundation

/// A bounded Messages SSE request. Usage settles only after a complete message_stop.
enum ClaudeStream {
    static func route(_ request: URLRequest, session: URLSession = .shared, sentence: @escaping (String) -> Void, completion: @escaping (RouteDecision?) -> Void) {
        guard let ticket = SpendBudget.authorize(request,seat: "jarvis") else { completion(nil); return }
        Task {
            var partial = "", buffer = "", spoken = "", usage: [String:Any] = [:], stopped = false, reason = ""
            var toolIndex: Int?, invalidTool = false
            var decision: RouteDecision?
            do {
                let (bytes,response) = try await session.bytes(for:request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { await MainActor.run { completion(nil) };return }
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: "),let data = String(line.dropFirst(6)).data(using:.utf8),let event = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { continue }
                    switch event["type"] as? String {
                    case "message_start": usage = (event["message"] as? [String:Any])?["usage"] as? [String:Any] ?? [:]
                    case "content_block_start":
                        if let block = event["content_block"] as? [String:Any], block["type"] as? String == "tool_use" {
                            if toolIndex != nil || block["name"] as? String != "route" { invalidTool = true }
                            toolIndex = event["index"] as? Int
                        }
                    case "content_block_delta":
                        if let delta = event["delta"] as? [String:Any],let json = delta["partial_json"] as? String {
                            guard !invalidTool, let toolIndex, event["index"] as? Int == toolIndex else { invalidTool = true;continue }
                            partial += json
                            // Only an ordinary reply may be spoken before the routing decision completes.
                            if partial.contains("\"route\":\"reply\"") || partial.contains("\"route\": \"reply\"") {
                                if let text = textField(partial), text.hasPrefix(spoken) {
                                    buffer = String(text.dropFirst(spoken.count))
                                    while let boundary = buffer.range(of:"[.!?](?:\\s|$)",options:.regularExpression), buffer.distance(from:buffer.startIndex,to:boundary.upperBound) > 1 {
                                        let part = String(buffer[..<boundary.upperBound]);spoken += part;buffer = String(buffer[boundary.upperBound...])
                                        await MainActor.run { sentence(part) }
                                    }
                                }
                            }
                        }
                    case "message_delta":
                        if let delta = event["delta"] as? [String:Any] { reason = delta["stop_reason"] as? String ?? "" }
                        for (key,value) in event["usage"] as? [String:Any] ?? [:] { usage[key] = value }
                    case "error": throw NSError(domain:"ClaudeStream",code:1)
                    case "message_stop": stopped = true
                    default: break
                    }
                }
                if stopped && !invalidTool && toolIndex != nil && reason == "tool_use" {
                    decision = RouteDecision.decode(partial)
                    let data = try JSONSerialization.data(withJSONObject:["usage":usage])
                    if let cost = SpendBudget.responseCost(request,data:data) { SpendBudget.settle(ticket,actualMicroUSD:cost) }
                    TokenMeter.record("jarvis",model:"claude-sonnet-5-5",data:data)
                    if let decision,decision.route == "reply",decision.text.hasPrefix(spoken) {
                        let tail = String(decision.text.dropFirst(spoken.count));if !tail.isEmpty { await MainActor.run { sentence(tail) } }
                    }
                }
            } catch { }
            let result = decision
            await MainActor.run { completion(result) }
        }
    }
    /// Decode only complete JSON string characters, withholding split escape sequences.
    static func textField(_ input:String) -> String? {
        guard let range = input.range(of:"\"text\"\\s*:\\s*\"",options:.regularExpression) else { return nil }
        var raw = "",escaped = false
        for char in input[range.upperBound...] {
            if char == "\"" && !escaped { break }
            raw.append(char)
            if char == "\\" { escaped.toggle() } else { escaped = false }
        }
        while !raw.isEmpty {
            if let data = ("\"" + raw + "\"").data(using:.utf8),let value = try? JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed) as? String { return value }
            raw.removeLast()
        }
        return ""
    }
}
