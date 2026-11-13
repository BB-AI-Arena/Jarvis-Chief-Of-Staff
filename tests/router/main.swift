import Foundation
let system = JarvisRouter.system(persona: "PERSONA", memory: "- 2026-11-09 · Brandon · target is solo handymen")
assert(system.contains("PERSONA") && system.contains("route=assign") && system.contains("route=debate") && system.contains("route=remember") && system.contains("solo handymen"))
assert(!JarvisRouter.system(persona: "", memory: "").contains("Board memory"))
let body = JarvisRouter.body(prompt: "Add the launch plan", history: "user: hi", system: system)
assert(body["model"] as? String == "claude-sonnet-5-5")
assert((body["tool_choice"] as! [String: String]) == ["type": "auto"])
assert(((body["messages"] as! [[String: String]])[0]["content"]!).contains("Current user request:\nAdd the launch plan"))
let enumRoutes = (((JarvisRouter.tool["input_schema"] as! [String: Any])["properties"] as! [String: Any])["route"] as! [String: Any])["enum"] as! [String]
assert(enumRoutes == RouteDecision.routes)
print("PASS: the fast router sends the shared rules, memory and a validated route tool to Claude Sonnet")
func reply(_ input: String) -> Data { Data("{\"content\":[{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"route\",\"input\":\(input)}],\"stop_reason\":\"tool_use\"}".utf8) }
let assign = JarvisRouter.decision(from: reply("{\"route\":\"assign\",\"text\":\"Draft the launch plan\",\"director\":\"projects\"}"))!
assert(RouteDecision.assignment(for: assign)?.director == "projects")
assert(JarvisRouter.decision(from: reply("{\"route\":\"assign\",\"text\":\"Do it\",\"director\":\"jarvis\"}")) == nil)
assert(JarvisRouter.decision(from: reply("{\"route\":\"shell\",\"text\":\"rm\"}")) == nil)
assert(JarvisRouter.decision(from: Data("{\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}".utf8)) == nil)
let noted = JarvisRouter.decision(from: reply("{\"route\":\"remember\",\"text\":\"Noted.\",\"task\":\"First customers are solo handymen.\"}"))!
assert(RouteDecision.memory(for: noted) == "First customers are solo handymen.")
assert(RouteDecision.memory(for: assign) == nil)
print("PASS: router replies are validated like every other brain; Jarvis is never a director and unknown routes are dropped")
extension RouteDecision: Equatable { public static func == (a: RouteDecision, b: RouteDecision) -> Bool { a.route == b.route && a.text == b.text && a.director == b.director && a.task == b.task } }

let next = JarvisRouter.nextStepPrompt(task: "task", director: "research", result: "done")
assert(next.contains("Usually no follow-up") && next.contains("Never suggest verifying"))
let taskReply = JarvisRouter.decision(from: reply("{\"route\":\"assign\",\"text\":\"On it\",\"task\":\"Summarize the supplied notes\",\"director\":\"projects\"}"))!
assert(taskReply.task == "Summarize the supplied notes")
print("PASS: router keeps task separate from speech and defaults to no follow-up")

let completePrompt = String(repeating:"x",count:49000) + "TAIL_REQUIREMENT"
let longBody = JarvisRouter.body(prompt:completePrompt,history:"earlier",system:"system")
assert(((longBody["messages"] as! [[String:String]])[0]["content"]!).contains(completePrompt))
assert(RouteDecision.limitsRule.contains("50,000"))

assert(ClaudeStream.textField(#"{"route":"reply","text":"Hello, \"Brandon\". Next"#) == "Hello, \"Brandon\". Next")
assert(ClaudeStream.textField(#"{"text":"A \u00"#) == "A ")
print("PASS: partial streaming JSON preserves quoted speech and withholds incomplete escapes")

// Real URLSession SSE transport with an isolated ledger and no provider/network access.
final class StreamFixtureProtocol: URLProtocol {
    static var events: [[String: Any]] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.anthropic.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"text/event-stream"])!
        client?.urlProtocol(self, didReceive:response, cacheStoragePolicy:.notAllowed)
        for event in Self.events {
            let json = try! JSONSerialization.data(withJSONObject:event)
            var data = Data("data: ".utf8); data.append(json); data.append(Data("\n\n".utf8))
            client?.urlProtocol(self, didLoad:data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
URLProtocol.registerClass(StreamFixtureProtocol.self)
defer { URLProtocol.unregisterClass(StreamFixtureProtocol.self) }
func streamFixture(tool:String = "route", stopped:Bool = true, error:Bool = false, wrongIndex:Bool = false, duplicate:Bool = false) -> (RouteDecision?, [String]) {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    SpendBudget.directory = temporary
    defer { try? FileManager.default.removeItem(at:temporary) }
    let fragments = [#"{"route":"reply","text":"Hello, "#, #"Brandon. A quoted \"word\" is safe."}"#]
    var events: [[String:Any]] = [
        ["type":"message_start","message":["usage":["input_tokens":10]]],
        ["type":"content_block_start","index":0,"content_block":["type":"tool_use","id":"fixture","name":tool,"input":[:]]]
    ]
    for fragment in fragments { events.append(["type":"content_block_delta","index":wrongIndex ? 1 : 0,"delta":["type":"input_json_delta","partial_json":fragment]]) }
    events.append(["type":"content_block_stop","index":0])
    if duplicate { events.append(["type":"content_block_start","index":1,"content_block":["type":"tool_use","id":"second","name":"route","input":[:]]]) }
    if error { events.append(["type":"error","error":["type":"overloaded_error"]]) }
    events.append(["type":"message_delta","delta":["stop_reason":"tool_use"],"usage":["output_tokens":12]])
    if stopped { events.append(["type":"message_stop"]) }
    StreamFixtureProtocol.events = events
    var request = URLRequest(url:URL(string:"https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.httpBody = try! JSONSerialization.data(withJSONObject:["model":JarvisRouter.model,"max_tokens":600,"stream":true,"messages":[["role":"user","content":"fixture"]]])
    var done = false, result:RouteDecision?, sentences:[String] = []
    ClaudeStream.route(request,sentence:{sentences.append($0)},completion:{result = $0;done = true})
    let deadline = Date().addingTimeInterval(8)
    while !done && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
    assert(done,"SSE fixture never completed")
    let state = try! JSONDecoder().decode(SpendBudget.State.self, from:Data(contentsOf:temporary.appendingPathComponent("daily.json")))
    if result != nil { assert(state.reserved["jarvis"] == 140 && state.holds?.isEmpty == true) }
    else { assert(state.reserved["jarvis"] == SpendBudget.maximum(request) && state.holds?.count == 1) }
    return (result,sentences)
}
let completedStream = streamFixture()
assert(completedStream.0?.text == "Hello, Brandon. A quoted \"word\" is safe.")
assert(completedStream.1.joined() == completedStream.0?.text)
assert(streamFixture(stopped:false).0 == nil)
assert(streamFixture(error:true).0 == nil)
let unknownTool = streamFixture(tool:"unknown")
assert(unknownTool.0 == nil && unknownTool.1.isEmpty)
assert(streamFixture(duplicate:true).0 == nil)
let mismatchedBlock = streamFixture(wrongIndex:true)
assert(mismatchedBlock.0 == nil && mismatchedBlock.1.isEmpty)
print("PASS: real SSE transport preserves exact speech and rejects incomplete/error/unknown-tool/mismatched-block streams")
