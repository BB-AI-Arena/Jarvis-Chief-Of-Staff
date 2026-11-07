import Foundation

func check(_ value: @autoclosure () -> Bool, _ description: String) {
    guard value() else { fatalError("FAIL: " + description) }
    print("PASS: " + description)
}
var turn = VoiceTurn()
turn.begin(at: 0)
check(turn.finish(at: 20) == nil, "silence alone never sends an empty model request")
turn.hear("Help me plan an app", at: 21)
check(turn.finish(at: 22) == nil, "a short thinking pause does not submit early")
turn.audioActivity(at: 22.1)
check(turn.finish(at: 23) == nil, "ongoing speech postpones turn completion even without new recognition text")
check(turn.finish(at: 23.6) == "Help me plan an app", "a completed spoken turn submits automatically after silence")
check(turn.finish(at: 30, final: true) == nil, "final callback cannot submit the same turn a second time")
turn.hear("speaker echo", at: 31)
check(turn.transcript == "Help me plan an app", "recognizer callbacks outside the listening phase cannot become a new turn")
turn.begin(at: 40)
turn.hear("Cancel this", at: 41)
turn.cancel()
check(turn.finish(at: 50, final: true) == nil, "ending the conversation discards pending microphone text")
turn.begin(at: 60)
turn.hear("Another question", at: 61)
check(turn.finish(at: 61.1, final: true) == "Another question", "a recognizer final result can end a turn without an extra delay")
turn.begin(at: 70)
turn.hear("   ", at: 71)
check(turn.finish(at: 80) == nil, "whitespace transcripts do not send requests")
