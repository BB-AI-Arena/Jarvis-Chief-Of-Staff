import Foundation

/// A prompt part is bounded; the full assignment is never sliced away.
/// These parts still share one model context. They do not create extra context capacity.
enum PromptDelivery {
    static let partCharacters = 50_000
    static func parts(_ text: String) -> [String] {
        guard !text.isEmpty else { return [""] }
        var result: [String] = [],start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start,offsetBy:partCharacters,limitedBy:text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]));start = end
        }
        return result
    }
    static func envelope(_ text: String) -> String {
        let pieces = parts(text)
        guard pieces.count > 1 else { return text }
        return "Complete assignment in \(pieces.count) numbered parts. Read every part before acting. Preserve all requirements and integrate the whole result.\n" + pieces.enumerated().map { index,part in
            "\n--- BEGIN PART \(index+1)/\(pieces.count) ---\n" + part + "\n--- END PART \(index+1)/\(pieces.count) ---"
        }.joined() + "\nEND OF COMPLETE ASSIGNMENT. All \(pieces.count) parts supplied."
    }
}
