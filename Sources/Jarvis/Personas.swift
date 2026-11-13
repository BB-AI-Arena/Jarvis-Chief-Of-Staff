import Foundation

/// Board persona files bundled from Resources/board/personas. Plain text only; no secrets live here.
enum Personas {
    static let deliveryPolicy = "Delivery and capability policy: Prompt content is delivered in parts of up to 50,000 characters. Longer assignments retain every part; use additional scoped prompts within the authorized budget when needed. This is a part size, not an overall job ceiling. You have finite input context, response length, tool-round, timeout and token budgets, and only the configured tools. Preserve every original requirement. For a large assignment, plan numbered dependent parts and use additional prompts/tool calls when needed within the existing budget. Keep a checklist of parts, pass the necessary source and prior results to each, then integrate and review the complete result. Do not claim to have read unavailable source or visually watched a film without the corresponding tool evidence. Short task labels and summaries are not substitutes for the full saved brief. Splitting a prompt does not bypass the model context limit; if context cannot hold the source, use scoped passes with a final synthesis and disclose what each pass actually saw. Do not silently clip source, accept an output cut off by a token limit, or call a partial answer complete. Preserve partial work and explicitly identify any remaining blocker; never silently raise a budget or bypass required owner approval."
    static let seats = ["jarvis", "cto", "research", "operations", "creative", "projects", "board-charter"]
    static func text(_ name: String) -> String? {
        guard seats.contains(name) else { return nil }
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("board/personas/\(name).md")) }
        if let root = Bundle.main.object(forInfoDictionaryKey: "JarvisProjectRoot") as? String {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent("Resources/board/personas/\(name).md"))
        }
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty { return text }
        }
        return nil
    }
    /// The seat persona followed by the board charter, or the fallback when the files are missing.
    static func system(_ seat: String, fallback: String) -> String {
        guard let persona = text(seat) else { return fallback + "\n\n" + deliveryPolicy }
        let charter = text("board-charter") ?? ""
        return persona + (charter.isEmpty ? "" : "\n\n" + charter) + "\n\n" + deliveryPolicy
    }
}
