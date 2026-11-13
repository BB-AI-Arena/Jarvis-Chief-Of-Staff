import Foundation

assert(LocalFilmWorker.tokenBudget(seconds:10)==150_000)
assert(LocalFilmWorker.tokenBudget(seconds:600)==4_000_000)
assert(LocalFilmWorker.tokenBudget(seconds:Int.max)==4_000_000)

let root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-film-bridge-" + UUID().uuidString)
let project = root.appendingPathComponent("project")
try! FileManager.default.createDirectory(at: project.appendingPathComponent(".voice/bin"), withIntermediateDirectories: true)
let interpreter = Process(), interpreterOutput = Pipe()
interpreter.executableURL = URL(fileURLWithPath:"/usr/bin/env")
interpreter.arguments = ["python3","-c","import sys; print(sys.executable)"]
interpreter.standardOutput = interpreterOutput
try! interpreter.run();interpreter.waitUntilExit()
let python = String(data:interpreterOutput.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)!.trimmingCharacters(in:.whitespacesAndNewlines)
assert(interpreter.terminationStatus == 0 && python.hasPrefix("/"))
try! FileManager.default.createSymbolicLink(at: project.appendingPathComponent(".voice/bin/python"), withDestinationURL: URL(fileURLWithPath:python).resolvingSymlinksInPath())
let script = root.appendingPathComponent("worker.py")
try! """
import json,time
print(json.dumps({'type':'progress','message':'Rendering a physical scene'}),flush=True)
time.sleep(1.5)
print(json.dumps({'type':'done','path':'/tmp/test-film.mp4'}),flush=True)
""".write(to:script,atomically:true,encoding:.utf8)
var worker: Process?, kinds = [String](), live = false, complete = false, exitCode: Int32 = -1
LocalFilmWorker.canStart = { false }
var denied = false
let blocked = LocalFilmWorker.start(spec:[:],folder:root.appendingPathComponent("blocked"),project:project,script:script,event:{ _ in },completion:{ denied = $0 != 0 })
assert(blocked == nil && denied)
assert(!FileManager.default.fileExists(atPath:root.appendingPathComponent("blocked").path))
// Only this synthetic script is authorized; it prints fixtures and has no provider calls.
LocalFilmWorker.canStart = { true }
defer { LocalFilmWorker.canStart = { SpendBudget.allowsBudgetedFilm } }
worker = LocalFilmWorker.start(spec:["brief":"A bridge check with no credentials"],folder:root.appendingPathComponent("job"),project:project,script:script,event:{ event in
    kinds.append(event["type"] as? String ?? "")
    if event["type"] as? String == "progress" { live = worker?.isRunning == true }
},completion:{ code in exitCode=code;complete=true })
let deadline = Date().addingTimeInterval(10)
while !complete && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
if worker?.isRunning == true { worker?.terminate() }
assert(complete && exitCode == 0 && kinds == ["progress","done"])
assert(live,"Worker progress must reach the app before the worker exits")
let events = try! String(contentsOf:root.appendingPathComponent("job/worker-events.jsonl"),encoding:.utf8)
assert(events.components(separatedBy:"\n").filter { !$0.isEmpty }.count == 2)
try? FileManager.default.removeItem(at:root)
print("PASS: native film progress arrives while the worker is running, structured events are logged, and completion follows the final event")
