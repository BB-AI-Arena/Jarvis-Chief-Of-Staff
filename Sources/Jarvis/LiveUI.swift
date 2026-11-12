import Foundation
import CryptoKit

/// In-place UI updates. The page (HTML, JS, CSS, board art) can be replaced from the Jarvis source folder while the app
/// runs, so a director's UI fix shows up without quitting — quitting would interrupt every running task.
/// The live copy sits in Application Support and is used only while the installed app's own page is the one it was
/// made from; installing a newer build makes the old live copy stale, and the bundle wins again.
enum LiveUI {
    /// Required page files; every other top-level .html, .js and .css file is carried along too.
    static let pageFiles = ["index.html", "app.js", "style.css"]
    static let pageFolders = ["board", "vendor"]
    static func pageNames(_ folder: URL) -> [String] {
        let tops = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let extra = tops.filter { !$0.hasPrefix(".") && ["html", "js", "css"].contains(($0 as NSString).pathExtension.lowercased()) }
        return Array(Set(pageFiles + extra)).sorted() + pageFolders
    }
    enum Outcome: Equatable { case applied, unchanged, failed(String) }

    /// SHA-256 over every file's relative path and contents, in path order. Nil when the folder has none of `names`.
    static func fingerprint(_ folder: URL, names: [String]? = nil) -> String? {
        let fm = FileManager.default
        var paths: [String] = []
        let tops = names ?? ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        for top in tops where !top.hasPrefix(".") {
            let url = folder.appendingPathComponent(top)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                for case let sub as String in fm.enumerator(atPath: url.path) ?? NSEnumerator() where !sub.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                    var subDir: ObjCBool = false
                    if fm.fileExists(atPath: url.appendingPathComponent(sub).path, isDirectory: &subDir), !subDir.boolValue { paths.append(top + "/" + sub) }
                }
            } else { paths.append(top) }
        }
        guard !paths.isEmpty else { return nil }
        var hash = SHA256()
        for path in paths.sorted() {
            hash.update(data: Data(path.utf8))
            hash.update(data: (try? Data(contentsOf: folder.appendingPathComponent(path))) ?? Data())
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func pageFingerprint(_ folder: URL) -> String? { fingerprint(folder, names: pageNames(folder)) }

    /// The folder the page loads from: the live copy when it was made on top of this build's page, otherwise the bundle.
    static func root(bundle: URL, live: URL) -> URL {
        guard FileManager.default.fileExists(atPath: live.appendingPathComponent("index.html").path),
              let base = try? String(contentsOf: live.appendingPathComponent(".base"), encoding: .utf8),
              base == pageFingerprint(bundle) else { return bundle }
        return live
    }

    /// Copies the source page into the live folder after checking it. Never touches the bundle or the source.
    static func apply(source: URL, bundle: URL, live: URL, node: String? = nodePath) -> Outcome {
        let fm = FileManager.default
        for file in pageFiles where !fm.fileExists(atPath: source.appendingPathComponent(file).path) { return .failed("the source page is missing \(file)") }
        guard let incoming = pageFingerprint(source), let base = pageFingerprint(bundle) else { return .failed("the page could not be read") }
        if incoming == pageFingerprint(root(bundle: bundle, live: live)) { return .unchanged }
        if let node {
            for script in pageNames(source) where script.hasSuffix(".js") {
                if let problem = syntaxProblem(source.appendingPathComponent(script), node: node) { return .failed("\(script) has a syntax error: " + problem) }
            }
        }
        let staging = live.deletingLastPathComponent().appendingPathComponent(".ui-staging")
        try? fm.removeItem(at: staging)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for name in pageNames(source) where fm.fileExists(atPath: source.appendingPathComponent(name).path) {
                try fm.copyItem(at: source.appendingPathComponent(name), to: staging.appendingPathComponent(name))
            }
            try base.write(to: staging.appendingPathComponent(".base"), atomically: true, encoding: .utf8)
            try? fm.removeItem(at: live)
            try fm.moveItem(at: staging, to: live)
        } catch { try? fm.removeItem(at: staging); return .failed("copying the page failed: " + error.localizedDescription) }
        return .applied
    }
    static func rollBack(live: URL) { try? FileManager.default.removeItem(at: live) }

    static var nodePath: String? { ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) } }
    /// `node --check`: nil when the script parses, otherwise the first error line.
    static func syntaxProblem(_ script: URL, node: String) -> String? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = ["--check", script.path]
        process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").first { $0.contains("Error") }.map { String($0.prefix(200)) } ?? "exit \(process.terminationStatus)"
    }
}
