import AppKit
import WebKit
import AVFoundation
import Speech

extension JarvisApp {
    func chooseFolder() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.message = "Choose a folder for Jarvis to map locally. Code relationships use Graphify; file contents are not sent to a model."
        picker.begin { result in if result == .OK, let url = picker.url { self.root = url.resolvingSymlinksInPath(); self.index(self.root!) } }
    }
    func index(_ folder: URL) {
        guard tasks["graph"] == nil else { send("notice", "A map is already building. Please wait for it to finish."); return }
        send("indexing", ["name": folder.lastPathComponent, "path": folder.path])
        let cache = support.appendingPathComponent("Graphs/\(UUID().uuidString)")
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                let nodes = Self.folderNodes(folder)
                self.send("files", ["nodes": nodes, "root": folder.path, "name": folder.lastPathComponent, "limited": nodes.count >= 1500])
                DispatchQueue.main.async {
                    self.run(key: "graph", executable: self.project.appendingPathComponent(".graphify/bin/graphify"), arguments: ["extract", folder.path, "--code-only", "--no-cluster", "--max-workers", "2", "--out", cache.path], cwd: folder, timeout: 120) { code, output in
                        let graphFile = cache.appendingPathComponent("graphify-out/graph.json")
                        if code == 0, let data = try? Data(contentsOf: graphFile), let graph = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            self.send("graph", graph)
                        } else { self.send("graphError", "Folder map is ready. Graphify could not complete: " + String(output.suffix(700))) }
                    }
                }
            } catch { self.send("graphError", error.localizedDescription) }
        }
    }
    static func folderNodes(_ folder: URL) -> [[String: Any]] {
        var nodes: [[String: Any]] = [["id": folder.path, "label": folder.lastPathComponent, "kind": "folder", "parent": ""]]
        let excluded: Set<String> = ["node_modules", ".git", ".build", ".graphify", ".voice", "dist", "build", "__pycache__", "Pods", "DerivedData", "graphify-out", "venv", ".venv"]
        if let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            while let file = files.nextObject() as? URL {
                let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if excluded.contains(file.lastPathComponent) || values?.isSymbolicLink == true { files.skipDescendants(); continue }
                let relative = file.path.dropFirst(folder.path.count).split(separator: "/")
                if relative.count > 6 { files.skipDescendants(); continue }
                nodes.append(["id": file.path, "label": file.lastPathComponent, "kind": values?.isDirectory == true ? "folder" : "file", "parent": file.deletingLastPathComponent().path])
                if nodes.count >= 1500 { break }
            }
        }
        return nodes
    }
}
