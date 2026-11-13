import Foundation

/// Transcript turns, independent of whether the voice model emits a delegation event.
/// Timeline matching keeps a late delegation from claiming a newer user request.
struct VoiceHandoff {
    struct Turn {
        let id: Int
        var text: String
        let start: Int?
        var claimed = false
        var closed = false
    }
    private(set) var turns: [Turn] = []
    private var sequence = 0
    mutating func append(_ text: String, start: Int?) -> Int {
        if turns.last == nil || turns.last!.closed {
            sequence += 1
            turns.append(Turn(id: sequence, text: "", start: start))
            if turns.count > 32 { turns.removeFirst() }
        }
        turns[turns.count - 1].text += text
        return turns.last!.id
    }
    mutating func close() -> Int? {
        guard !turns.isEmpty else { return nil }
        turns[turns.count - 1].closed = true
        return turns.last!.id
    }
    func turn(at offset: Int?) -> Int? {
        guard let offset else { return turns.last?.id }
        return turns.last(where: { ($0.start ?? 0) <= offset })?.id
    }
    mutating func claim(_ id: Int) -> String? {
        guard let i = turns.firstIndex(where: { $0.id == id }), !turns[i].claimed else { return nil }
        let text = turns[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        turns[i].claimed = true
        return text
    }
}
