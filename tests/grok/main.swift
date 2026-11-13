import Foundation
assert(GrokClient.defaultModel == "grok-4.7")
assert(GrokClient.sanitize("  grok-4.7 \n") == "grok-4.7")
assert(GrokClient.sanitize("grok-4.20-0309-reasoning") == "grok-4.20-0309-reasoning")
assert(GrokClient.sanitize("") == nil)
assert(GrokClient.sanitize("bad model") == nil)
assert(GrokClient.sanitize("grok/4") == nil)
let body = GrokClient.requestBody("Survey the market", model: "grok-4.7", system: "persona")
assert(body["model"] as? String == "grok-4.7")
let messages = body["messages"] as! [[String: String]]
assert(messages[0]["role"] == "system" && messages[0]["content"] == "persona")
assert(messages[1]["role"] == "user" && messages[1]["content"] == "Survey the market")
let reply = Data("{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\" Three findings. \"}}]}".utf8)
assert(GrokClient.text(from: reply) == "Three findings.")
assert(GrokClient.text(from: Data("{\"choices\":[]}".utf8)) == nil)
assert(GrokClient.text(from: Data("{\"error\":\"bad key\"}".utf8)) == nil)
print("PASS: Grok defaults to the documented xAI model id, rejects malformed ids, and reads only real completions")
let searchBody = GrokClient.searchBody("Find competitors", model: "grok-4.7", system: "SYS")
assert((searchBody["tools"] as! [[String: String]]) == [["type": "web_search"]])
assert((searchBody["input"] as! [[String: String]])[1] == ["role": "user", "content": "Find competitors"])
let searched = GrokClient.searchText(from: Data("{\"output\":[{\"type\":\"web_search_call\"},{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Jobber leads.\",\"annotations\":[{\"type\":\"url_citation\",\"url\":\"https://example.com/a\"},{\"type\":\"url_citation\",\"url\":\"https://example.com/a\"}]}]}]}".utf8))
assert(searched == "Jobber leads.\n\nSources:\n- https://example.com/a")
assert(GrokClient.searchText(from: Data("{\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Plain.\"}]}]}".utf8)) == "Plain.")
assert(GrokClient.searchText(from: Data("{\"error\":\"nope\"}".utf8)) == nil)
print("PASS: Research asks xAI for live web search and keeps the answer with its cited sources")
let calls = GrokClient.functionCalls(from: ["id": "r1", "output": [["type": "web_search_call"], ["type": "function_call", "call_id": "c1", "name": "run_on_dark", "arguments": "{\"command\":\"nvidia-smi\"}"]]])
assert(calls.count == 1 && calls[0].id == "c1" && calls[0].input["command"] as? String == "nvidia-smi")
assert(GrokClient.functionCalls(from: ["output": [["type": "message"]]]).isEmpty)
print("PASS: Grok's tool calls are read from the Responses API so Research can use DARK while searching the web")

assert(GrokClient.fastModel == "grok-4.20-0309-non-reasoning")
assert(GrokClient.wantsDepth("Give a thorough analysis"))
assert(!GrokClient.wantsDepth("Find three competitors"))
assert(GrokClient.maxToolRounds == 4)
assert(DarkTool.relevant("Inspect ComfyUI on DARK"))
assert(!DarkTool.relevant("Find competitor prices"))
TokenMeter.reset()
TokenMeter.add("projects", model: "test", input: 10, output: 5)
assert(TokenMeter.used("projects") == 15 && TokenMeter.used("research") == 0)
TokenMeter.reset()
TokenMeter.add("projects", model: "test", input: 10, output: 5, date: Date(timeIntervalSince1970: 0))
assert(TokenMeter.used("projects") == 0)
print("PASS: research depth, tool limits, DARK relevance and daily seat token usage")

let fullReview = String(repeating:"x",count:45000) + "END_OF_COMPLETE_SCREENPLAY"
assert((GrokClient.requestBody(fullReview,model:"m",system:"s")["messages"] as! [[String:String]])[1]["content"] == fullReview)
assert((GrokClient.searchBody(fullReview,model:"m",system:"s")["input"] as! [[String:String]])[1]["content"] == fullReview)
print("PASS: Research receives complete long screenplays on both request paths")

assert(GrokClient.text(from:Data("{\"choices\":[{\"finish_reason\":\"length\",\"message\":{\"content\":\"unfinished\"}}]}".utf8)) == nil)
assert(GrokClient.searchText(from:Data("{\"status\":\"incomplete\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"unfinished\"}]}]}".utf8)) == nil)

// Exercise the real transport without credentials, network access or a nine-minute wait.
final class ReviewTimeoutProtocol: URLProtocol {
    static var timeouts: [TimeInterval] = []
    static var shouldTimeout = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.x.ai" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.timeouts.append(request.timeoutInterval)
        if Self.shouldTimeout { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\"Complete review\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":3}}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let budgetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
SpendBudget.directory = budgetRoot
URLProtocol.registerClass(ReviewTimeoutProtocol.self)
defer { URLProtocol.unregisterClass(ReviewTimeoutProtocol.self); try? FileManager.default.removeItem(at: budgetRoot) }
func checkReviewTimeout(_ seconds: TimeInterval?, fails: Bool = false) {
    ReviewTimeoutProtocol.shouldTimeout = fails
    var complete = false, result: String?, diagnostic: String?
    let done: (String?) -> Void = { result = $0; complete = true }
    let task: URLSessionDataTask
    if let seconds {
        task = GrokClient.research(fullReview, model: "grok-4.7", apiKey: "fixture-not-a-key", maxTokens: 4096, timeout: seconds, diagnostic: { diagnostic = $0 }, completion: done)
    } else {
        task = GrokClient.research(fullReview, model: "grok-4.7", apiKey: "fixture-not-a-key", maxTokens: 4096, diagnostic: { diagnostic = $0 }, completion: done)
    }
    let request = task.originalRequest!
    assert(request.timeoutInterval == (seconds ?? 180))
    let payload = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    assert(payload["max_tokens"] as? Int == 4096)
    assert((payload["messages"] as! [[String: String]])[1]["content"] == fullReview)
    let deadline = Date().addingTimeInterval(5)
    while !complete && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    assert(complete)
    if fails { assert(result == nil && diagnostic?.contains("Grok request failed") == true) }
    else { assert(result == "Complete review" && diagnostic == nil) }
}
checkReviewTimeout(nil)
checkReviewTimeout(540)
checkReviewTimeout(540, fails: true)
assert(ReviewTimeoutProtocol.timeouts == [180, 540, 540])
print("PASS: ordinary requests retain 180s, full screenplay requests use 540s without truncation, and timeout cannot return a completed review")
