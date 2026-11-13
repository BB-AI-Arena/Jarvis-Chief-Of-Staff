import Foundation
assert(ClaudeClient.defaultModel == "claude-sonnet-5-5")
assert(ClaudeClient.sanitize("  claude-sonnet-5-5 \n") == "claude-sonnet-5-5")
assert(ClaudeClient.sanitize("claude-opus-5-5") == "claude-opus-5-5")
assert(ClaudeClient.sanitize("") == nil)
assert(ClaudeClient.sanitize("bad model") == nil)
assert(ClaudeClient.sanitize("claude/sonnet") == nil)
print("PASS: Claude model id defaults to the current Sonnet API id and rejects malformed ids")
let calls = ClaudeClient.toolCalls([["type": "text", "text": "Let me check."], ["type": "tool_use", "id": "toolu_1", "name": "lookup", "input": ["brief": "Neon boardroom"]]])
assert(calls.count == 1 && calls[0].id == "toolu_1" && calls[0].name == "lookup" && calls[0].brief == "Neon boardroom")
assert(ClaudeClient.toolCalls([["type": "text", "text": "No tools"]]).isEmpty)
print("PASS: Claude tool_use blocks are parsed into id, name and brief; text-only replies have no tool calls")
let uses = ClaudeClient.toolUses([["type": "text", "text": "Looking."], ["type": "tool_use", "id": "toolu_2", "name": "read_file", "input": ["path": "source/Package.swift", "start_line": 1]]])
assert(uses.count == 1 && uses[0].name == "read_file" && uses[0].input["path"] as? String == "source/Package.swift" && uses[0].input["start_line"] as? Int == 1)
assert(ClaudeClient.maxToolRounds == 8)
print("PASS: the CTO's tool calls carry their full input, with a bounded number of rounds")
let search = ClaudeClient.searchBody(model: "claude-sonnet-5-5", system: "SYS", messages: [["role": "user", "content": "Find competitors"]])
assert((search["tools"] as! [[String: Any]])[0]["type"] as? String == "web_search_20260209")
assert((search["tools"] as! [[String: Any]])[0]["max_uses"] as? Int == 5)
assert(search["fallbacks"] as? String == "default")
assert(ClaudeClient.searchBody(model: "claude-haiku-5-5", system: "S", messages: [])["fallbacks"] == nil)
let blocks: [[String: Any]] = [
    ["type": "server_tool_use", "id": "srv_1", "name": "web_search", "input": ["query": "handyman software"]],
    ["type": "web_search_tool_result", "tool_use_id": "srv_1", "content": []],
    ["type": "text", "text": "Jobber leads the market. ", "citations": [["type": "web_search_result_location", "url": "https://example.com/a", "title": "A", "cited_text": "Jobber"]]],
    ["type": "text", "text": "Housecall Pro is second.", "citations": [["type": "web_search_result_location", "url": "https://example.com/a"], ["type": "web_search_result_location", "url": "https://example.com/b"]]]
]
assert(ClaudeClient.searchReport(blocks) == "Jobber leads the market. Housecall Pro is second.\n\nSources:\n- https://example.com/a\n- https://example.com/b")
assert(ClaudeClient.searchReport([["type": "text", "text": "Plain answer."]]) == "Plain answer.")
let uncited: [[String: Any]] = [
    ["type": "web_search_tool_result", "tool_use_id": "srv_2", "content": [["type": "web_search_result", "url": "https://example.com/g2", "title": "G2"], ["type": "web_search_result", "url": "https://example.com/g2"], ["type": "web_search_result", "url": "https://example.com/capterra"]]],
    ["type": "text", "text": "Jobber and Housecall Pro."]]
assert(ClaudeClient.searchReport(uncited) == "Jobber and Housecall Pro.\n\nSources searched:\n- https://example.com/g2\n- https://example.com/capterra")
assert(ClaudeClient.searchReport([["type": "server_tool_use", "id": "x"]]) == nil)
print("PASS: Research can fall back to Claude with live web search, keeping the answer and its cited sources")

var answerPages = ClaudeClient.AnswerPages()
assert(answerPages.append("Part one",limited:true) == .more && answerPages.result == nil)
assert(answerPages.append("Part two",limited:false) == .complete)
assert(answerPages.result == "Part one\nPart two")
var exhaustedPages = ClaudeClient.AnswerPages()
for _ in 0..<3 { assert(exhaustedPages.append("partial",limited:true) == .more) }
assert(exhaustedPages.append("still partial",limited:true) == .exhausted && exhaustedPages.result == nil)
print("PASS: multi-prompt answers are assembled only on completion; exhausted partial work cannot pass as finished")

// Exercise the actual continuation requests without network access or real credentials.
final class PageProtocol: URLProtocol {
    static var errorResponse = false
    static var lastDiagnostic = ""
    static var limitedForever = false
    static var bodies: [[String:Any]] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.anthropic.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody
        if bytes == nil,let stream = request.httpBodyStream {
            stream.open();defer { stream.close() };var data = Data();var buffer = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer,maxLength:buffer.count);if count <= 0 { break };data.append(contentsOf:buffer.prefix(count)) };bytes = data
        }
        let body = bytes.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] } ?? [:]
        Self.bodies.append(body)
        if Self.errorResponse {
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:429,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data("{\"error\":{\"message\":\"Rate limit reached for not-a-real-key\"}}".utf8));client?.urlProtocolDidFinishLoading(self);return
        }
        let limited = Self.limitedForever || Self.bodies.count == 1
        let reply: [String:Any] = ["content":[["type":"text","text":limited ? "First page" : "Final page"]],"stop_reason":limited ? "max_tokens" : "end_turn"]
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:reply));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
URLProtocol.registerClass(PageProtocol.self)
func exercisePages(forever: Bool) -> String? {
    SpendBudget.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: SpendBudget.directory) }
    PageProtocol.limitedForever = forever;PageProtocol.bodies = []
    var finished = false;var answer: String?
    ClaudeClient.converse("Complete this assignment",model:"claude-sonnet-5-5",apiKey:"not-a-real-key",system:"S",tools:[],isCancelled:{false},tool:{_,_,done in done("unused")},diagnostic:{PageProtocol.lastDiagnostic = $0}) { text in answer = text;finished = true }
    let deadline = Date().addingTimeInterval(5)
    while !finished && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
    assert(finished,"continuation test did not complete")
    return answer
}
assert(exercisePages(forever:false) == "First page\nFinal page")
assert(PageProtocol.bodies.count == 2)
let continuationMessages = PageProtocol.bodies[1]["messages"] as! [[String:Any]]
assert(continuationMessages.count == 3)
assert(continuationMessages.last?["content"] as? String == ClaudeClient.continueAnswer)
assert(exercisePages(forever:true) == nil)
assert(PageProtocol.bodies.count == 4,"continuations must remain bounded")
PageProtocol.errorResponse = true
assert(exercisePages(forever:false) == nil)
assert(PageProtocol.lastDiagnostic.contains("HTTP 429"))
assert(PageProtocol.lastDiagnostic.contains("Rate limit reached"))
assert(!PageProtocol.lastDiagnostic.contains("not-a-real-key"))
PageProtocol.errorResponse = false
URLProtocol.unregisterClass(PageProtocol.self)
print("PASS: real client continues a limited response, retains its prior context, and refuses exhausted partial output")
