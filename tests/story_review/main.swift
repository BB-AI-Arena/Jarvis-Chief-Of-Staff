import Foundation
let hash = "exact-version"
func verdict(_ decision: String,_ changes: [String],_ version: String = hash) -> String {
 String(data:try! JSONSerialization.data(withJSONObject:["script_sha256":version,"decision":decision,"summary":"Concluded review","changes":changes]),encoding:.utf8)!
}
assert(StoryReview.parse("I am checking the brand file before deciding.",hash:hash) == nil)
assert(StoryReview.parse(verdict("accept",[]),hash:hash)?.decision == "accept")
assert(StoryReview.parse(verdict("accept",["unresolved blocker"]),hash:hash) == nil)
assert(StoryReview.parse(verdict("revise",[]),hash:hash) == nil)
assert(StoryReview.parse(verdict("revise",["Scene 3: ownership changes without a transfer; preserve the existing owner."]),hash:hash)?.changes.count == 1)
assert(StoryReview.parse(verdict("accept",[],"old-version"),hash:hash) == nil)
print("PASS: progress notes, stale judgments and contradictory acceptance cannot become completed story reviews")
