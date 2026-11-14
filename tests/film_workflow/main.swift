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

// A locked Mac can receive a writing-only revision without fabricating UI approval.
var rejected = app.loadFilmStory()!
rejected.phase = "production_needs_attention"
rejected.approvedHash = rejected.hash
rejected.approvedAt = "historical-approval-time"
app.saveFilmStory(rejected)
let inbox = app.support.appendingPathComponent("story-revision-inbox")
try! FileManager.default.createDirectory(at:inbox,withIntermediateDirectories:true)
let request = StoryRevisionRequest(storyID:rejected.id,expectedHash:rejected.hash,feedback:"Immediate hook, real app captures, coherent story.")
let requestFile = inbox.appendingPathComponent(request.id + ".json")
try! JSONEncoder().encode(request).write(to:requestFile)
app.consumeStoryRevisionRequests()
let revision = app.loadFilmStory()!
assert(revision.phase == "draft" && revision.approvedHash.isEmpty && revision.approvedAt.isEmpty)
assert(revision.ownerRevisionFeedback == request.feedback)
assert(revision.script == rejected.script && revision.brief == rejected.brief)
assert(revision.history.contains(where:{$0.contains("Historical production approval:")}))
assert(app.ledger.rows.first(where:{$0.id==revision.taskID})!.instructions.contains(request.feedback))
assert(app.dispatched.last == "creative")
let countAfterRevision = app.dispatched.count
app.consumeStoryRevisionRequests()
assert(app.dispatched.count == countAfterRevision)
let previous = app.support.appendingPathComponent("story-revision-history/" + request.id + "/previous-story.json")
assert(try! JSONDecoder().decode(FilmStory.self,from:Data(contentsOf:previous)).approvedHash == rejected.approvedHash)
let stale = StoryRevisionRequest(storyID:rejected.id,expectedHash:"outdated",feedback:"Stale request")
try! JSONEncoder().encode(stale).write(to:inbox.appendingPathComponent(stale.id + ".json"))
app.consumeStoryRevisionRequests()
assert(app.dispatched.count == countAfterRevision && app.loadFilmStory()!.taskID == revision.taskID)
print("PASS: local revision inbox archives historical approval, dispatches actual Creative once, rejects stale requests and never starts production")

var failedDraft = app.loadFilmStory()!
failedDraft.phase = "needs_attention"
app.saveFilmStory(failedDraft)
app.updateTask(failedDraft.taskID,state:"failed",summary:"No completed screenplay")
assert(app.canReviseFilmStory(failedDraft))
app.reviseFilmStory(failedDraft.id,feedback:"Retry the same complete rewrite after fixing delivery.")
assert(app.loadFilmStory()!.phase == "draft" && app.dispatched.last == "creative")
assert(app.loadFilmStory()!.approvedHash.isEmpty)
var failedReview = app.loadFilmStory()!
failedReview.phase = "needs_attention"
app.saveFilmStory(failedReview)
if let i = app.ledger.rows.firstIndex(where:{$0.id == failedReview.taskID}) { app.ledger.rows[i].owner = "research";app.ledger.rows[i].state = "failed" }
assert(!app.canReviseFilmStory(failedReview))
print("PASS: only failed Creative consultation can retry from needs_attention; no stale-script Research handoff")

var terminalStory = app.loadFilmStory()!
terminalStory.phase = "draft";app.saveFilmStory(terminalStory)
app.refreshFilmStory()
assert(app.loadFilmStory()!.phase == "needs_attention")
assert(app.ledger.rows.first(where:{$0.id == terminalStory.id})?.state == "failed")
print("PASS: failed consultation terminalizes aggregate story status")

// Reviewer feedback must not overwrite the latest owner direction between stages.
var contextStory = app.loadFilmStory()!
contextStory.phase = "draft"
contextStory.ownerRevisionFeedback = "CURRENT OWNER: coherent story, real app screens, immediate hook"
app.saveFilmStory(contextStory)
app.deliver("RUNTIME_SECONDS: 90\nFull revised screenplay\nEND")
let reviewTask = app.ledger.rows.first(where:{$0.id == app.loadFilmStory()!.taskID})!
assert(reviewTask.instructions.contains(contextStory.ownerRevisionFeedback!))
app.deliver(review("revise",["Fix scene motivation"]))
let writingTask = app.ledger.rows.first(where:{$0.id == app.loadFilmStory()!.taskID})!
assert(writingTask.instructions.contains(contextStory.ownerRevisionFeedback!))
assert(app.loadFilmStory()!.ownerRevisionFeedback == contextStory.ownerRevisionFeedback)
print("PASS: latest owner revision direction survives Research and Creative handoffs")

var workshopStory = app.loadFilmStory()!
workshopStory.phase = "needs_attention";app.saveFilmStory(workshopStory)
let beforeWorkshop = try! Data(contentsOf:app.filmStoryURL)
let workshop = StoryRevisionRequest(storyID:workshopStory.id,expectedHash:workshopStory.hash,feedback:"Return a one-page story spine only.",writingSeat:"creative")
try! JSONEncoder().encode(workshop).write(to:inbox.appendingPathComponent(workshop.id + ".json"))
app.consumeStoryRevisionRequests()
assert(try! Data(contentsOf:app.filmStoryURL) == beforeWorkshop)
let workshopTask = app.ledger.rows.first(where:{$0.instructions.contains(workshop.feedback)})!
assert(workshopTask.owner == "creative" && workshopTask.instructions.contains("not a screenplay"))
let afterWorkshopCount = app.dispatched.count
app.consumeStoryRevisionRequests();assert(app.dispatched.count == afterWorkshopCount)
print("PASS: separate writing workshop dispatches once without modifying screenplay state or approval")

// Only actual completed, full-version director records may become an owner-review proposal.
var oldStory = app.loadFilmStory()!
oldStory.phase = "needs_attention";oldStory.approvedHash = "historical";oldStory.approvedAt = "then"
app.saveFilmStory(oldStory)
for i in app.ledger.rows.indices where app.ledger.rows[i].state == "running" { app.ledger.rows[i].state = "failed" }
let finalScript = "RUNTIME_SECONDS: 160\nComplete sequence-by-sequence assembly\nEND"
let finalHash = FilmStory.digest(finalScript)
let researchID = app.storyTask("Review exact " + finalHash + "\n" + finalScript,seat:"research")
let creativeID = app.storyTask("Confirm exact " + finalHash + "\n" + finalScript,seat:"creative")
app.updateTask(researchID,state:"completed",summary:"Accepted")
app.updateTask(creativeID,state:"completed",summary:"Confirmed")
let acceptedJSON = String(data:try! JSONSerialization.data(withJSONObject:["script_sha256":finalHash,"decision":"accept","summary":"Complete story accepted","changes":[]]),encoding:.utf8)!
app.saveResult(researchID,title:"",director:"",text:acceptedJSON)
app.saveResult(creativeID,title:"",director:"",text:"CREATIVE_ACCEPTS_STORY\nSCREENPLAY_SHA256: " + finalHash)
let adoption = ReviewedStoryAdoption(storyID:oldStory.id,previousHash:oldStory.hash,script:finalScript,scriptHash:finalHash,researchTaskID:researchID,creativeTaskID:creativeID)
let untouched = try! Data(contentsOf:app.filmStoryURL)
var badAdoption = adoption
badAdoption = ReviewedStoryAdoption(storyID:oldStory.id,previousHash:oldStory.hash,script:finalScript+"changed",scriptHash:finalHash,researchTaskID:researchID,creativeTaskID:creativeID)
assert(!app.adoptReviewedStory(badAdoption))
app.updateTask(researchID,state:"running",summary:"Still reviewing")
assert(!app.adoptReviewedStory(adoption))
app.updateTask(researchID,state:"completed",summary:"Accepted")
app.saveResult(creativeID,title:"",director:"",text:"CREATIVE_ACCEPTS_STORY\nSCREENPLAY_SHA256: wrong")
assert(!app.adoptReviewedStory(adoption))
app.saveResult(creativeID,title:"",director:"",text:"CREATIVE_ACCEPTS_STORY\nSCREENPLAY_SHA256: " + finalHash)
app.saveResult(researchID,title:"",director:"",text:acceptedJSON.replacingOccurrences(of:finalHash,with:"stale"))
assert(!app.adoptReviewedStory(adoption))
assert(try! Data(contentsOf:app.filmStoryURL) == untouched)
app.saveResult(researchID,title:"",director:"",text:acceptedJSON)
app.saveResult(creativeID,title:"",director:"",text:"CREATIVE_ACCEPTS_STORY\nSCREENPLAY_SHA256: " + finalHash + "\nBut I do not accept the ending.")
assert(!app.adoptReviewedStory(adoption))
app.saveResult(creativeID,title:"",director:"",text:"# Creative result\n\nCreative Director · timestamp\n\n---\n\nCREATIVE_ACCEPTS_STORY\nSCREENPLAY_SHA256: " + finalHash + "\n")
let dispatchedBeforeAdoption = app.dispatched.count
assert(app.adoptReviewedStory(adoption))
let proposed = app.loadFilmStory()!
assert(proposed.phase == "awaiting_approval" && proposed.script == finalScript && proposed.hash == finalHash)
assert(proposed.viewedHash.isEmpty && proposed.approvedHash.isEmpty && proposed.approvedAt.isEmpty)
assert(!proposed.canApprove(finalHash))
assert(proposed.brief == oldStory.brief && proposed.ownerRevisionFeedback == oldStory.ownerRevisionFeedback)
assert(app.dispatched.count == dispatchedBeforeAdoption)
assert(!app.adoptReviewedStory(adoption))
assert(FileManager.default.fileExists(atPath:app.support.appendingPathComponent("reviewed-story-history/" + adoption.id + "/previous-story.json").path))
print("PASS: reviewed adoption rejects stale/incomplete/unbound evidence, archives history, awaits unread owner approval and never renders")

let beforeExternalApproval = try! Data(contentsOf:app.filmStoryURL)
let noApproval = ExternalStoryApproval(scriptHash:finalHash,sourceChatID:UUID().uuidString,ownerText:"If I approve this, will you render?")
assert(!app.recordExternalStoryApproval(noApproval))
let staleApproval = ExternalStoryApproval(scriptHash:"wrong",sourceChatID:UUID().uuidString,ownerText:"Approved")
assert(!app.recordExternalStoryApproval(staleApproval))
assert(try! Data(contentsOf:app.filmStoryURL) == beforeExternalApproval)
let external = ExternalStoryApproval(scriptHash:finalHash,sourceChatID:UUID().uuidString,ownerText:"Approved")
let dispatchBeforeExternal = app.dispatched.count
assert(app.recordExternalStoryApproval(external))
let externallyApproved = app.loadFilmStory()!
assert(externallyApproved.phase == "approved" && externallyApproved.approvedHash == finalHash)
assert(externallyApproved.viewedHash.isEmpty && !externallyApproved.approvedAt.isEmpty)
assert(app.dispatched.count == dispatchBeforeExternal && !externallyApproved.canRender(task:externallyApproved.taskID))
assert(!app.recordExternalStoryApproval(external))
assert(externallyApproved.history.contains(where:{$0.contains(external.sourceChatID) && $0.contains("No UI view was asserted")}))
print("PASS: exact owner-chat approval records provenance without faking a UI read or launching rendering")

// A targeted post-delivery edit consultation does not rewrite an approved screenplay.
let approvedBytes = try! Data(contentsOf:app.filmStoryURL)
let editRequest = StoryRevisionRequest(storyID:externallyApproved.id,expectedHash:externallyApproved.hash,feedback:"Targeted edit consultation: reveal the actual app sooner; preserve accepted story.",writingSeat:"creative")
try! JSONEncoder().encode(editRequest).write(to:inbox.appendingPathComponent(editRequest.id + ".json"))
app.consumeStoryRevisionRequests()
assert(try! Data(contentsOf:app.filmStoryURL) == approvedBytes)
assert(app.ledger.rows.contains(where:{$0.owner == "creative" && $0.instructions.contains(editRequest.feedback)}))
assert(!app.canReviseFilmStory(app.loadFilmStory()!))
assert(!app.loadFilmStory()!.canRender(task:app.loadFilmStory()!.taskID))
print("PASS: approved-script targeted consultation preserves exact approval and cannot start wholesale rewrite or rendering")

// Replacing an approved, externally delivered rejected film requires real owner evidence.
let previousApproved = app.loadFilmStory()!
let nextScript = "RUNTIME_SECONDS: 60\nActual app first, brief planned-feature preview\nEND"
let nextHash = FilmStory.digest(nextScript)
let rr = app.storyTask("Full " + nextHash + "\n" + nextScript,seat:"research")
let cc = app.storyTask("Full " + nextHash + "\n" + nextScript,seat:"creative")
app.updateTask(rr,state:"completed",summary:"Accept")
app.updateTask(cc,state:"completed",summary:"Accept")
app.saveResult(rr,title:"",director:"",text:acceptedJSON.replacingOccurrences(of:finalHash,with:nextHash))
app.saveResult(cc,title:"",director:"",text:"CREATIVE_ACCEPTS_STORY\nSCREENPLAY_SHA256: " + nextHash)
let missingEvidence = ReviewedStoryAdoption(storyID:previousApproved.id,previousHash:previousApproved.hash,script:nextScript,scriptHash:nextHash,researchTaskID:rr,creativeTaskID:cc)
assert(!app.adoptReviewedStory(missingEvidence))
let filmRoot = app.support.appendingPathComponent("completed-external-film")
try! FileManager.default.createDirectory(at:filmRoot.appendingPathComponent("app-first-revision"),withIntermediateDirectories:true)
func evidence(_ name:String,_ value:[String:Any]) { try! JSONSerialization.data(withJSONObject:value).write(to:filmRoot.appendingPathComponent(name)) }
let deliveredID = UUID().uuidString
app.ledger.rows.append(TaskRecord(id:deliveredID,state:"completed",verified:false,owner:"creative",createdAt:"then",updatedAt:"then",resultSummary:"Delivered",title:"Completed external film"))
evidence("external-task.json",["id":deliveredID,"kind":"film"])
evidence("job.json",["approved_sha256":"wrong"])
let ownerChat = UUID().uuidString
evidence("owner-film-review.json",["decision":"rejected_needs_revision","owner_feedback_verbatim":"Too slow; show the actual app.","source_chat":ownerChat])
evidence("app-first-revision/owner-direction.json",["owner_answer_verbatim":"Actual app first; roughly 60 seconds.","source_chat":ownerChat,"exact_replacement_script_approval":"not_yet_given"])
let replacement = ReviewedStoryAdoption(storyID:previousApproved.id,previousHash:previousApproved.hash,script:nextScript,scriptHash:nextHash,researchTaskID:rr,creativeTaskID:cc,rejectedFilmRoot:filmRoot.path)
assert(!app.adoptReviewedStory(replacement))
evidence("job.json",["approved_sha256":previousApproved.hash])
let dispatchBeforeReplacement = app.dispatched.count
assert(app.adoptReviewedStory(replacement))
let replacementStory = app.loadFilmStory()!
assert(replacementStory.phase == "awaiting_approval" && replacementStory.hash == nextHash)
assert(replacementStory.approvedHash.isEmpty && replacementStory.viewedHash.isEmpty && replacementStory.approvedAt.isEmpty)
assert(replacementStory.ownerRevisionFeedback!.contains("Actual app first"))
assert(replacementStory.history.contains(where:{$0.contains(previousApproved.approvedHash)}))
assert(app.dispatched.count == dispatchBeforeReplacement)
print("PASS: completed rejected-film evidence enables a reviewed replacement only, preserving historical approval and requiring fresh owner approval")
