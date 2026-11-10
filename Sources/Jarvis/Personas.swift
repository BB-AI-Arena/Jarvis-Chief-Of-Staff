import Foundation

/// Board persona files bundled from Resources/board/personas. Plain text only; no secrets live here.
enum Personas {
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
        guard let persona = text(seat) else { return fallback }
        let charter = text("board-charter") ?? ""
        return persona + (charter.isEmpty ? "" : "\n\n" + charter)
    }
}
