import Foundation
assert(Acceptance.cases.count == 15)
let research = Acceptance.cases[2], greeting = Acceptance.cases[4], debate = Acceptance.cases[3]
assert(Acceptance.problem(RouteDecision(route: "assign", text: "Research competitors", director: "research"), for: research) == nil)
assert(Acceptance.problem(RouteDecision(route: "assign", text: "Research competitors", director: "creative"), for: research)!.contains("expected research"))
assert(Acceptance.problem(RouteDecision(route: "reply", text: "I can't.", director: nil), for: research)!.contains("expected assign"))
assert(Acceptance.problem(nil, for: greeting) == "no decision returned")
assert(Acceptance.problem(RouteDecision(route: "reply", text: "Good morning.", director: nil), for: greeting) == nil)
assert(Acceptance.problem(RouteDecision(route: "debate", text: "ok", director: nil, task: "Ship this week?"), for: debate) == nil)
assert(Acceptance.line(0, greeting, nil, ms: 5).hasPrefix("FAIL  1"))
print("PASS: the acceptance run fails a request that is refused, lost, or sent to the wrong director")

let videoCheck = Acceptance.cases[0]
assert(Acceptance.problem(RouteDecision(route: "assign", text: "Verify artwork", director: "research"), for: videoCheck) != nil)
assert(Acceptance.problem(RouteDecision(route: "reply", text: "I cannot watch video.", director: nil), for: videoCheck) == nil)
print("PASS: video artwork verification cannot pass acceptance when assigned to Research")
