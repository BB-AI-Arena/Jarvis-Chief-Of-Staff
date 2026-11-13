import Foundation
struct TestLedger { var rows: [TaskRecord] = []; func load() -> [TaskRecord] { rows } }
enum SpendBudget { static var allowsBudgetedFilm = true; static let blocked = "Budget blocked" }
final class JarvisApp {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var ledger = TestLedger(); var dispatched: [String] = []; var announcements: [String] = []
    init() { try! FileManager.default.createDirectory(at:support,withIntermediateDirectories:true) }
    func directorTitle(_ seat:String)->String { seat }
    func publishTasks(_ rows:[TaskRecord]) { ledger.rows = rows }
    func dispatch(_ seat:String) { dispatched.append(seat) }
    func say(_ text:String) { announcements.append(text) }
    func send(_ event:String,_ text:String) {}
    func showWorkspace() {}
    func openResult(_ id:String) { var s=loadFilmStory()!;s.viewedHash=s.hash;saveFilmStory(s) }
    func resultFile(_ id:String)->URL? { let f=support.appendingPathComponent(id+".md");return FileManager.default.fileExists(atPath:f.path) ? f:nil }
    func saveResult(_ id:String,title:String,director:String,text:String) { try! text.write(to:support.appendingPathComponent(id+".md"),atomically:true,encoding:.utf8) }
    func updateTask(_ id:String,state:String,summary:String) { if let i=ledger.rows.firstIndex(where:{$0.id==id}) { ledger.rows[i].state=state;ledger.rows[i].resultSummary=summary } }
    func deliver(_ text:String) { let id=loadFilmStory()!.taskID;saveResult(id,title:"",director:"",text:text);updateTask(id,state:"completed",summary:text);refreshFilmStory() }
}
let app=JarvisApp();defer { try? FileManager.default.removeItem(at:app.support) }
var story=FilmStory(brief:"Full owner brief preserved")
story.script="RUNTIME_SECONDS: 90\nComplete saved screenplay\nEND";story.hash=FilmStory.digest(story.script);story.phase="needs_attention";story.round=3
app.saveFilmStory(story);_ = app.resumeSavedFilmStory()
assert(app.loadFilmStory()!.id==story.id && app.loadFilmStory()!.script==story.script)
let reviewID=app.loadFilmStory()!.taskID;let dispatchCount=app.dispatched.count
_ = app.resumeSavedFilmStory();assert(app.dispatched.count==dispatchCount && app.loadFilmStory()!.taskID==reviewID)
app.deliver("I am checking the brand file.")
assert(app.loadFilmStory()!.phase=="review" && app.loadFilmStory()!.round==1 && app.loadFilmStory()!.reviewDeliveryFailures==1)
func review(_ decision:String,_ changes:[String])->String { String(data:try! JSONSerialization.data(withJSONObject:["script_sha256":app.loadFilmStory()!.hash,"decision":decision,"summary":"Actual test review","changes":changes]),encoding:.utf8)! }
app.deliver(review("revise",["Scene 1: label the upcoming concept."]))
assert(app.loadFilmStory()!.phase=="draft" && app.loadFilmStory()!.round==2)
app.deliver("RUNTIME_SECONDS: 90\nRevised full screenplay with upcoming concept\nEND")
let revised=app.loadFilmStory()!;assert(revised.hash != story.hash)
app.deliver(review("accept",[]));assert(app.loadFilmStory()!.phase=="confirm")
app.deliver("CREATIVE_ACCEPTS_STORY")
let agreed=app.loadFilmStory()!;assert(agreed.phase=="awaiting_approval" && agreed.approvedHash.isEmpty)
assert(app.resultFile(agreed.id) != nil)
_ = app.approveFilmStory(agreed.id,hash:story.hash);assert(app.loadFilmStory()!.phase=="awaiting_approval")
SpendBudget.allowsBudgetedFilm=false
_ = app.approveFilmStory(agreed.id,hash:agreed.hash)
assert(app.loadFilmStory()!.phase=="approved" && app.loadFilmStory()!.approvedHash==agreed.hash)
assert(!app.ledger.rows.contains(where:{$0.title=="Create the approved Drop Assassin film"}))
SpendBudget.allowsBudgetedFilm=true
_ = app.createApprovedFilm();assert(app.loadFilmStory()!.phase=="rendering")
let renders=app.ledger.rows.filter{$0.title=="Create the approved Drop Assassin film"}
assert(renders.count==1 && renders[0].instructions.contains(agreed.script) && renders[0].instructions.contains(agreed.hash))
_ = app.approveFilmStory(agreed.id,hash:agreed.hash);_ = app.createApprovedFilm()
assert(app.ledger.rows.filter{$0.title=="Create the approved Drop Assassin film"}.count==1)
print("PASS: real workflow resumes one saved story, retries progress without dissent, revises full script, obtains both acceptances, rejects stale approval, preserves authorization on budget block and dispatches exact approved script once")

let rendering=app.loadFilmStory()!
app.updateTask(rendering.taskID,state:"failed",summary:"DARK unavailable; no cloud fallback")
app.refreshFilmStory()
assert(app.loadFilmStory()!.phase=="production_needs_attention" && app.loadFilmStory()!.approvedHash==agreed.hash)
assert(app.isApprovedFilmRequest("resume and make the movie"))
_ = app.createApprovedFilm()
app.updateTask(app.loadFilmStory()!.taskID,state:"completed",summary:"Verified output file saved")
app.refreshFilmStory();assert(app.loadFilmStory()!.phase=="completed")
print("PASS: failed and finished production project actual task state while retaining exact owner authorization")
