import Foundation

/// Hold the speaking pose through short pauses; silent transport packets are not speech.
struct VoiceActivity {
    private var lastAudible = -Double.infinity
    mutating func update(rms: Double, at time: TimeInterval) -> Bool {
        if rms > 0.003 { lastAudible = time }
        return time - lastAudible < 0.45
    }
}
