import Foundation

/// Turn detection is independent of the recognizer so silence/cancellation can be tested.
struct VoiceTurn {
    private(set) var listening = false
    private(set) var transcript = ""
    private(set) var beganAt: TimeInterval = 0
    private var lastActivity: TimeInterval = 0
    var silenceSeconds: TimeInterval = 1.4

    mutating func begin(at time: TimeInterval) {
        listening = true; transcript = ""; beganAt = time; lastActivity = time
    }
    mutating func hear(_ text: String, at time: TimeInterval) {
        guard listening else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text != transcript { transcript = text; lastActivity = time }
    }
    mutating func audioActivity(at time: TimeInterval) {
        if listening { lastActivity = time }
    }
    mutating func finish(at time: TimeInterval, final: Bool = false) -> String? {
        guard listening, !transcript.isEmpty, final || time - lastActivity >= silenceSeconds else { return nil }
        listening = false
        return transcript
    }
    mutating func cancel() { listening = false; transcript = "" }
}
