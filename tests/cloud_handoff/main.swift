import Foundation
let live = CloudVoice()
var routed: [String] = []
let receive: (String, String, @escaping (String) -> Void) -> Void = { prompt, _, done in routed.append(prompt); done("") }
live.onTurn = receive; live.onDelegate = receive
func event(_ type: String, _ extra: [String: Any]) { var e = extra; e["type"] = type; live.handle(e, greeting: false) }
event("session.input_transcript.delta", ["delta": "Create a ten second video based on Drop Assassin artwork", "start_ms": 100, "end_ms": 1000])
event("session.output_transcript.delta", ["delta": "Passing this to Creative", "start_ms": 1100, "end_ms": 1500])
DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
    assert(routed.count == 1 && routed[0].contains("ten second"), "Spoken hand-off without delegation event must reach the backend")
    event("session.delegation.created", ["delegation": ["id": "late", "target": "client"], "offset_ms": 1200])
    event("session.input_transcript.delta", ["delta": "Create another video", "start_ms": 2000, "end_ms": 2500])
    event("session.delegation.created", ["delegation": ["id": "next", "target": "client"], "offset_ms": 2600])
    event("session.output_transcript.delta", ["delta": "I heard the request", "start_ms": 2700, "end_ms": 3000])
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
    assert(routed == ["Create a ten second video based on Drop Assassin artwork", "Create another video"], "Normal and fallback hand-offs must dispatch exactly once")
    live.sendText("Create a typed artwork video")
}
DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
    assert(routed.count == 3 && routed.last == "Create a typed artwork video")
    live.stop()
    print("PASS: real CloudVoice event handling dispatches missing, explicit, delayed and typed hand-offs exactly once without microphone or network")
    exit(0)
}
dispatchMain()
