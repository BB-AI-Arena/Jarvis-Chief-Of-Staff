"""Compile the actual external-film refresh methods in an isolated native fixture.
Only UI publication is stubbed; all filesystem, ledger and video progress code is real.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root/'Sources/Jarvis/AppResults.swift').read_text()
methods = source[source.index('    func filmJSON('):source.index('    func publishTasks(')]
prefix = '''import Foundation
final class JarvisApp {
    let workspace:URL
    let ledger:TaskStore
    var externalFilms:[String:URL] = [:]
    var videoJobs:[String:VideoPlan.Progress] = [:]
    init(_ root:URL) { workspace=root;ledger=TaskStore(directory:root.appendingPathComponent("tasks")) }
    func publishVideo(_ id:String) {}
    func publishTasks(_ records:[TaskRecord]) { try! ledger.save(records) }
'''
suffix = '''}
let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at:root) }
let folder=root.appendingPathComponent("Video/fixture")
try! FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
func write(_ name:String,_ value:[String:Any]) { try! JSONSerialization.data(withJSONObject:value).write(to:folder.appendingPathComponent(name)) }
let id=UUID().uuidString
write("external-task.json",["id":id]);write("film-state.json",["status":"Planning screenplay"]);write("job.json",["seconds":418])
let app=JarvisApp(root)
func check(_ status:String,_ age:Double,_ expected:String) {
    write("supervisor.json",["status":status,"heartbeat":Date().timeIntervalSince1970-age])
    app.refreshExternalFilms()
    assert(app.externalFilms[id]?.standardizedFileURL.path == folder.standardizedFileURL.path)
    assert(app.ledger.load().count == 1)
    assert(app.ledger.load()[0].state == expected)
    assert(app.videoJobs[id]?.shots.isEmpty == true)
}
check("running",0,"running")
check("needs_attention",0,"failed")
check("running",120,"failed")
assert(app.videoJobs[id]!.note.contains("heartbeat missing"))
check("cancelled",0,"cancelled")
check("running",0,"running")
assert(!FileManager.default.fileExists(atPath:folder.appendingPathComponent("plan.json").path))
write("external-task.json",["id":id,"kind":"animatic"])
write("film-state.json",["status":"Repairing storyboard","boards_total":8,"boards":["0":["path":"actual-board.png"]]])
check("running",0,"running")
assert(app.videoJobs[id]!.renderer == "DARK · storyboard animatic")
assert(app.videoJobs[id]!.note.contains("1/8 storyboard boards ready"))
assert(!app.videoJobs[id]!.note.contains("clips accepted"))
write("delivery-status.json",["stage":"Completed — video ready"])
check("completed",0,"running")
write("delivery-status.json",["stage":"Completed — animatic ready"])
check("completed",0,"completed")
assert(app.videoJobs[id]!.note == "Animatic ready — full film not rendered")
print("PASS: animatic boards remain distinct from film clips and generic video completion cannot complete an animatic")
print("PASS: registered film attaches before plan, preserves one ledger task, and fails closed for failed/cancelled/stale supervision")
'''
with tempfile.TemporaryDirectory(prefix='jarvis-external-state-') as tmp:
    main = Path(tmp)/'main.swift'; main.write_text(prefix+methods+suffix)
    binary = Path(tmp)/'check'
    sources = ['SpendBudget','PromptDelivery','VideoPlan','VideoArtwork','VideoRender','DarkServer','TaskLedger']
    subprocess.run(['swiftc',*[str(root/'Sources/Jarvis'/f'{s}.swift') for s in sources],str(main),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
