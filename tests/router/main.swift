import Foundation
let system = JarvisRouter.system(persona: "PERSONA", memory: "- 2026-11-09 · Brandon · target is solo handymen")
assert(system.contains("PERSONA") && system.contains("route=assign") && system.contains("route=debate") && system.contains("route=remember") && system.contains("solo handymen"))
assert(!JarvisRouter.system(persona: "", memory: "").contains("Board memory"))
let body = JarvisRouter.body(prompt: "Add the launch plan", history: "user: hi", system: system)
assert(body["model"] as? String == "claude-haiku-5-5")
assert((body["tool_choice"] as! [String: String]) == ["type": "tool", "name": "route"])
assert(((body["messages"] as! [[String: String]])[0]["content"]!).contains("Current user request:\nAdd the launch plan"))
let enumRoutes = (((JarvisRouter.tool["input_schema"] as! [String: Any])["properties"] as! [String: Any])["route"] as! [String: Any])["enum"] as! [String]
assert(enumRoutes == RouteDecision.routes)
print("PASS: the fast router sends the shared rules, memory and a forced route tool to a small Claude model")
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
