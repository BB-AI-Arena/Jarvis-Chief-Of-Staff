import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-director-results-\(UUID().uuidString)")
let folder = root.appendingPathComponent("Results")
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let id = UUID().uuidString
let name = "2026-11-12 Nebula screenplay " + id.prefix(8).lowercased() + ".md"
let finalLine = "FINAL LINE: The astronaut returns the silver compass to her sister."
let text = "# Nebula screenplay\n\nCreative Director\n\nA complete scene with details absent from the task summary.\n" + finalLine
try! text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
var creative = TaskRecord(id: id, state: "completed", verified: true, owner: "creative", createdAt: "now", updatedAt: "now", resultSummary: "A screenplay was written.", title: "Nebula screenplay")
let saved = try! TaskLedger.decode(TaskLedger.encode([creative]))
let context = DirectorResultsContext(workspace: root, records: saved)
let jarvis = context.context(for: "What was the final line of the Nebula screenplay?")
let research = context.context(for: "Review the Nebula screenplay from Creative")
assert(jarvis.contains(finalLine) && research.contains(finalLine))
assert(jarvis.contains("done but unverified") && research.contains("done but unverified"))
assert(jarvis.contains("Jarvis Workspace/Results/" + name))
assert(creative.payload["verified"] as? Bool == false)
creative.verificationEvidence = "Owner reviewed the saved screenplay, hash abc123."
assert(creative.verificationStatus == "done and verified")
assert(DirectorResultsContext(workspace: root, records: [creative]).context(for: "Nebula screenplay").contains("evidence: Owner reviewed"))
for (state, expected) in [("proposed", "recorded"), ("running", "running"), ("failed", "failed")] {
    creative.state = state
    assert(creative.verificationStatus == expected)
}
print("PASS: Creative's complete saved result and unverified status are retrievable by Jarvis and Research; verified requires evidence")
