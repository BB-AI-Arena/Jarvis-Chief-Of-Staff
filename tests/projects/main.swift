import Foundation
let input: [String: Any] = ["subtask": "Summary", "instructions": "Summarize", "input_text": "All the notes"]
assert(ProjectsTool.payload(input)?.prompt.contains("All the notes") == true)
assert(ProjectsTool.payload(["subtask": "Empty"]) == nil)
assert(ProjectsTool.payload(["subtask": "Long", "instructions": "Summarize", "input_text": String(repeating: "x", count: 50001) + "TAIL"])?.prompt.hasSuffix("TAIL") == true)
assert(ProjectsTool.anthropic["name"] as? String == ProjectsTool.name)
assert(ProjectsTool.responsesFunction["name"] as? String == ProjectsTool.name)
assert((ProjectsTool.function["function"] as? [String: Any])?["name"] as? String == ProjectsTool.name)
let bounded = ProjectsTool(chat: { prompt, done in done("summary"); return {} })
var events = [String](), replies = [String]()
for _ in 0..<4 { bounded.run(input, isCancelled: { false }, event: { phase, _ in events.append(phase) }, completion: { replies.append($0) }) }
assert(bounded.count == 3 && replies.count == 4 && replies.last!.contains("limit"))
assert(events == ["handoff", "done", "handoff", "done", "handoff", "done"])
let cancelled = ProjectsTool(chat: { _, _ in fatalError("Cancelled work must never start") })
cancelled.run(input, isCancelled: { true }, event: { _, _ in assertionFailure() }, completion: { assert($0.contains("cancelled")) })
assert(cancelled.count == 0)
var late: ((String?) -> Void)?, stops = 0, completions = 0
let timed = ProjectsTool(timeout: 0.02, chat: { _, done in late = done; return { stops += 1 } })
timed.run(input, isCancelled: { false }, event: { _, _ in }, completion: { result in
    completions += 1
    assert(result.contains("timed out"))
    late?("late answer")
    assert(completions == 1 && stops == 1)
    print("PASS: Projects validates full input, supports three tool schemas, caps delegations and cancels timed-out work exactly once")
    exit(0)
})
DispatchQueue.main.asyncAfter(deadline: .now() + 2) { fatalError("Timeout watchdog failed") }
dispatchMain()
