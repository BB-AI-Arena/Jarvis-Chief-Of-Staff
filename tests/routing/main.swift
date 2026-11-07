import Foundation
let plain = "{\"route\":\"task\",\"text\":\"Inspect the source without edits\"}"
assert(RouteDecision.decode(plain)?.route == "task")
assert(RouteDecision.decode("```json\n" + plain + "\n```")?.route == "task")
assert(RouteDecision.decode("```\n" + plain + "\n```")?.route == "task")
assert(RouteDecision.decode("text before " + plain) == nil)
assert(RouteDecision.decode("{\"route\":\"shell\",\"text\":\"bad route\"}") == nil)
assert(RouteDecision.decode("{\"route\":\"task\",\"text\":\"\"}") == nil)
print("PASS: plain and fenced routing accepted; malformed, unknown and empty instructions rejected")
