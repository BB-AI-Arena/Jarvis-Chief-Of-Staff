import Foundation

let base = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-context-\(UUID().uuidString)")
let results = base.appendingPathComponent("Results")
try! FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: base) }
try! "# Story consultation, revision three\nCreative wants the ending to remain ambiguous.\nResearch says the audience needs a clear resolution.\nTheir disagreement is whether the final scene resolves the mystery.\n".write(to: results.appendingPathComponent("2026 Story Consultation.md"), atomically: true, encoding: .utf8)
for index in 0..<100 {
    try! "# Routine report \(index)\nNo relevant story detail.\n".write(to: results.appendingPathComponent("Report \(index).md"), atomically: true, encoding: .utf8)
}
try! FileManager.default.createDirectory(at: base.appendingPathComponent("Notes"), withIntermediateDirectories: true)
try! "The launch owner is Maya.\n".write(to: base.appendingPathComponent("Notes/launch.md"), atomically: true, encoding: .utf8)
try! "PASSWORD=do-not-read\n".write(to: base.appendingPathComponent("Notes/passwords.txt"), atomically: true, encoding: .utf8)
let outside = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-context-outside-\(UUID().uuidString).md")
try! "Research and Creative secret outside the workspace\n".write(to: outside, atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(at: outside) }
try! FileManager.default.createSymbolicLink(at: base.appendingPathComponent("Notes/linked.md"), withDestinationURL: outside)
let context = SharedWorkspaceContext(root: base)
let answer = context.context(for: "What do Creative and Research disagree on in the Story consultation?")
assert(answer.contains("Story Consultation.md"))
assert(answer.contains("final scene resolves the mystery"))
assert(!answer.contains("secret outside"))
assert(!answer.contains("do-not-read"))
let launch = context.context(for: "Who owns the launch?")
assert(launch.contains("Notes/launch.md") && launch.contains("Maya"))
let inventory = context.context(for: "What results are in the workspace?")
assert(inventory.contains("Results/2026 Story Consultation.md"))
print("PASS: Jarvis retrieves older director results and shared notes while excluding credentials and links outside the workspace")

let privateSupport = base.appendingPathComponent("SupportFixture")
try! FileManager.default.createDirectory(at:privateSupport.appendingPathComponent("tasks"),withIntermediateDirectories:true)
try! "{\"phase\":\"needs_attention\",\"taskID\":\"review-1\",\"feedback\":\"Research returned a progress note, not a judgment\",\"approvedHash\":\"\"}".write(to:privateSupport.appendingPathComponent("film-story.json"),atomically:true,encoding:.utf8)
try! "[{\"id\":\"review-1\",\"state\":\"completed\",\"owner\":\"research\",\"title\":\"Review the complete story\",\"resultSummary\":\"I am checking\"}]".write(to:privateSupport.appendingPathComponent("tasks/ledger.json"),atomically:true,encoding:.utf8)
let withBoard = SharedWorkspaceContext(root:base,support:privateSupport)
assert(withBoard.context(for:"What did Research decide?").contains("Research returned a progress note, not a judgment"))
let longDoc = String(repeating:"x",count:70000) + "FINAL_BOARD_ANSWER"
try! longDoc.write(to:results.appendingPathComponent("Long result.md"),atomically:true,encoding:.utf8)
let firstPart = withBoard.lookup("{\"path\":\"Results/Long result.md\",\"offset\":0}")
let finalPart = withBoard.lookup("{\"path\":\"Results/Long result.md\",\"offset\":50000}")
assert(!firstPart.contains("FINAL_BOARD_ANSWER") && finalPart.contains("FINAL_BOARD_ANSWER"))
assert(withBoard.lookup("{\"path\":\"../private.txt\"}").contains("denied"))
assert(withBoard.lookup("{\"path\":\"\"}").contains("Long result.md"))
print("PASS: current board evidence and paged full results are available without escaping the workspace")
