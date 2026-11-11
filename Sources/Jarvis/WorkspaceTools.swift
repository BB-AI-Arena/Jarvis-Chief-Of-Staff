import Foundation

/// Read-only file tools for the CTO. Paths start with a named area ("workspace/…" or "source/…") and are resolved inside that area's folder;
/// nothing is written or run, and nothing outside those folders can be reached.
struct WorkspaceTools {
    let roots: [String: URL]
    init(roots: [String: URL]) { self.roots = roots }
    init(root: URL) { self.roots = ["workspace": root] }
    static let excluded: Set<String> = ["node_modules", ".git", ".build", ".graphify", ".voice", "dist", "build", "__pycache__", "Pods", "DerivedData", "graphify-out", "venv", ".venv", "models"]
    /// File names that may hold secrets are never listed, read or searched.
    static func sensitive(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix(".env") || lower.hasSuffix(".pem") || lower.hasSuffix(".key") || lower.hasSuffix(".p12") || lower.contains("credential") && !lower.hasSuffix(".swift") || lower.contains("secret") || lower == "id_rsa" || lower == "id_ed25519"
    }
    static let definitions: [[String: Any]] = [
        ["name": "list_files", "description": "List files and folders under a path. Paths start with an area name: use \"\" to see the areas, then for example \"workspace/Results\" or \"source/Sources\". Returns up to 200 entries.",
         "input_schema": ["type": "object", "properties": ["path": ["type": "string"]], "required": ["path"]]],
        ["name": "read_file", "description": "Read a text file by its area path (for example \"source/Package.swift\") with line numbers. Returns up to 400 lines starting at start_line (default 1).",
         "input_schema": ["type": "object", "properties": ["path": ["type": "string"], "start_line": ["type": "integer"]], "required": ["path"]]],
        ["name": "search_code", "description": "Search every area's text files for a case-insensitive substring. Returns up to 40 matches as area/path:line: text.",
         "input_schema": ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"]]]
    ]
    private func base(_ area: String) -> URL? { roots[area]?.resolvingSymlinksInPath().standardizedFileURL }
    /// A path inside its area, or nil when it names no area, escapes the area, is excluded, or looks like a secret.
    func resolve(_ path: String) -> URL? {
        let parts = path.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let area = parts.first, let base = base(area) else { return nil }
        let rest = parts.dropFirst().joined(separator: "/")
        let candidate = (rest.isEmpty ? base : base.appendingPathComponent(rest)).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else { return nil }
        let inside = candidate.path.dropFirst(base.path.count).split(separator: "/").map(String.init)
        guard !inside.contains(where: { WorkspaceTools.excluded.contains($0) || WorkspaceTools.sensitive($0) || $0.hasPrefix(".") }) else { return nil }
        return candidate
    }
    private func relative(_ url: URL, area: String) -> String {
        guard let base = base(area) else { return area }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == base.path ? area : area + "/" + String(path.dropFirst(base.path.count + 1))
    }
    func run(_ name: String, _ input: [String: Any]) -> String {
        switch name {
        case "list_files": return list(input["path"] as? String ?? "")
        case "read_file": return read(input["path"] as? String ?? "", start: input["start_line"] as? Int ?? 1)
        case "search_code": return search(input["query"] as? String ?? "")
        default: return "Unknown tool \(name)."
        }
    }
    func list(_ path: String) -> String {
        if path.trimmingCharacters(in: CharacterSet(charactersIn: " /.\n")).isEmpty { return roots.keys.sorted().map { $0 + "/" }.joined(separator: "\n") }
        guard let url = resolve(path) else { return "That path is outside the readable areas. Start it with one of: " + roots.keys.sorted().joined(separator: ", ") + "." }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return "Not a folder: \(path)" }
        let shown = names.filter { !$0.hasPrefix(".") && !WorkspaceTools.excluded.contains($0) && !WorkspaceTools.sensitive($0) }.sorted().prefix(200)
        let lines = shown.map { name -> String in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path, isDirectory: &isDirectory)
            return isDirectory.boolValue ? name + "/" : name
        }
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }
    func read(_ path: String, start: Int) -> String {
        guard let url = resolve(path) else { return "That path is outside the readable areas. Start it with one of: " + roots.keys.sorted().joined(separator: ", ") + "." }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else { return "No such file: \(path)" }
        guard size <= 1_000_000, let text = try? String(contentsOf: url, encoding: .utf8) else { return "Not a readable text file (binary or over 1 MB): \(path)" }
        let lines = text.components(separatedBy: "\n")
        let first = max(1, start)
        guard first <= lines.count else { return "The file has \(lines.count) lines." }
        let last = min(lines.count, first + 399)
        let body = (first...last).map { "\($0)\t" + String(lines[$0 - 1].prefix(400)) }.joined(separator: "\n")
        return String(body.prefix(24000)) + (last < lines.count ? "\n… \(lines.count - last) more lines; call read_file with start_line \(last + 1)." : "")
    }
    func search(_ query: String) -> String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 2 else { return "Give a search string of at least 2 characters." }
        var hits: [String] = []
        var scanned = 0
        for area in roots.keys.sorted() {
            guard let base = base(area), let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let file = files.nextObject() as? URL {
                let name = file.lastPathComponent
                let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDirectory = values?.isDirectory == true
                // skipDescendants() is only safe on a folder: on a file it can skip the rest of that folder.
                if WorkspaceTools.excluded.contains(name) || WorkspaceTools.sensitive(name) { if isDirectory { files.skipDescendants() }; continue }
                if isDirectory || (values?.fileSize ?? 0) > 400_000 { continue }
                scanned += 1
                if scanned > 4000 { break }
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for (index, line) in text.components(separatedBy: "\n").enumerated() where line.lowercased().contains(needle) {
                    hits.append("\(relative(file, area: area)):\(index + 1): " + String(line.trimmingCharacters(in: .whitespaces).prefix(200)))
                    if hits.count >= 40 { return hits.joined(separator: "\n") + "\n… more matches not shown." }
                }
            }
        }
        return hits.isEmpty ? "No matches for \"\(query)\"." : hits.joined(separator: "\n")
    }
}
