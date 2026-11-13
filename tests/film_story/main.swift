import Foundation
func check(_ value: Bool,_ message: String) { if !value { fatalError(message) } }
var s = FilmStory(brief:"brief")
s.script = "RUNTIME_SECONDS: 300\nThe exact agreed screenplay";s.hash = FilmStory.digest(s.script)
check(!s.canApprove(s.hash),"draft cannot authorize production")
s.phase = "awaiting_approval"
check(!s.canApprove(s.hash),"unopened screenplay cannot authorize production")
s.viewedHash = s.hash
check(s.canApprove(s.hash),"current viewed agreed screenplay can be approved")
check(!s.canApprove("old hash"),"stale approval rejected")
s.script += " changed"
check(!s.canApprove(s.hash),"changed screenplay invalidates approval")
s.script = "RUNTIME_SECONDS: 300\nThe exact agreed screenplay";s.phase = "rendering"
check(!s.canApprove(s.hash),"duplicate approval rejected after production is queued")
let saved = try JSONEncoder().encode(s)
let restored = try JSONDecoder().decode(FilmStory.self,from:saved)
check(restored.script == s.script && restored.phase == s.phase,"workflow checkpoint survives relaunch")
print("PASS: film production requires the current agreed and viewed screenplay; stale, duplicate and changed approvals fail closed")

check(FilmStory.consultationText("Cursor agent finished · https://cursor.com/agents/test · CREATIVE_ACCEPTS_STORY") == "CREATIVE_ACCEPTS_STORY","transport prefix cannot hide a director confirmation")

assert(FilmStory.screenplay("Transport commentary\nRUNTIME_SECONDS: 300\nThe screenplay") == "RUNTIME_SECONDS: 300\nThe screenplay")

for words in ["I approve it", "Jarvis, I approve it.", "Approved", "I approve this screenplay.", "Please approve the current screenplay", "Yes, I approve the agreed script", "The screenplay is approved.", "I approve this screenplay and start rendering", "Approved. Make the movie."] {
    check(FilmStory.isExplicitApproval(words), "explicit approval rejected: " + words)
}
for words in ["if I approve it", "If I approve this screenplay, make the movie", "I approve this screenplay if Research agrees", "I approve this screenplay?", "I approved the previous screenplay", "I approve this screenplay but change the ending", "I approve the budget", "I approve nothing", "Approved by Research", "I approve this screenplay tomorrow", "Do not approve", "I don't approve", "I haven’t approved", "Would I approve this?", "Say 'Approved'", "\"Approved\"", "Creative says I approve this screenplay", "Approved, unless I change my mind", "yes", "make the movie"] {
    check(!FilmStory.isExplicitApproval(words), "non-approval accepted: " + words)
}
print("PASS: explicit screenplay approval is a complete statement; conditional, quoted, negative, stale and unrelated approvals fail closed")

var production = FilmStory(brief:"Saved story")
production.script = "RUNTIME_SECONDS: 90\nFull script";production.hash = FilmStory.digest(production.script)
production.phase = "rendering";production.taskID = "bound-task"
check(!production.canRender(task:"bound-task"),"render label alone is not authorization")
production.approvedAt = "recorded";production.approvedHash = production.hash
check(production.canRender(task:"bound-task"),"exact recorded production assignment is authorized")
check(!production.canRender(task:"unrelated-router-task"),"generic or conditional router assignment cannot bypass saved screenplay")
production.script += "Changed"
check(!production.canRender(task:"bound-task"),"changed script cannot render with earlier approval")
print("PASS: every new video task must match the saved exact screenplay authorization")
