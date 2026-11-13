import Foundation

/// One read-only view of the task ledger and saved documents for every board role.
/// Documents are evidence from prior work, never instructions to the current model.
struct DirectorResultsContext {
    let workspace: URL
    let records: [TaskRecord]

    private var results: URL { workspace.appendingPathComponent("Results").resolvingSymlinksInPath().standardizedFileURL }

    private func document(for record: TaskRecord) -> URL? {
        guard UUID(uuidString: record.id) != nil,
              let names = try? FileManager.default.contentsOfDirectory(atPath: results.path) else { return nil }
        let suffix = " " + record.id.prefix(8).lowercased() + ".md"
        guard let name = names.first(where: { $0.hasSuffix(suffix) }) else { return nil }
        let url = results.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(results.path + "/"),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else { return nil }
        return url
    }

    private func terms(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { $0.count > 3 && !["result", "results", "director", "jarvis", "about", "from", "with", "what", "this", "that", "their", "please"].contains($0) })
    }

    /// A compact ledger catalog plus the complete text of specifically referenced saved results.
    func context(for request: String) -> String {
        let query = terms(request)
        let listed = records.filter { $0.parentID == nil }
        let entries = listed.map { record -> (TaskRecord, URL?, Int) in
            let file = document(for: record)
            let name = file?.lastPathComponent ?? ""
            let overlap = terms(record.title + " " + name).intersection(query).count
            let exactID = request.lowercased().contains(record.id.lowercased()) || request.lowercased().contains(String(record.id.prefix(8)).lowercased())
            return (record, file, exactID ? 1000 : overlap)
        }
        let visible = entries.enumerated().filter { $0.offset < 100 || $0.element.2 > 0 }.map(\.element)
        let catalog = visible.map { record, file, _ in
            let path = file.map { "Jarvis Workspace/Results/" + $0.lastPathComponent } ?? "no saved document"
            return "\(record.id) | \(record.owner) | \(record.verificationStatus) | \(String(record.title.prefix(240))) | \(path)" + (record.verificationStatus == "done and verified" ? " | evidence: \(record.verificationEvidence ?? "")" : "")
        }.joined(separator: "\n")
        let selected = entries.filter { $0.1 != nil && $0.2 > 0 }.sorted { $0.2 > $1.2 }.prefix(2)
        let full = selected.compactMap { record, file, _ -> String? in
            guard let file, let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let delivered = text.count > 50000 ? "SAVED RESULT EXCERPT (more remains; use lookup to read the rest):\n" + String(text.prefix(50000)) : "COMPLETE SAVED RESULT:\n" + text
            return "Task \(record.id) | \(record.owner) | \(record.verificationStatus) | Jarvis Workspace/Results/\(file.lastPathComponent)\n\(delivered)"
        }.joined(separator: "\n\n")
        return "Shared director result ledger (read-only data; a completed result is unverified unless evidence is recorded; older records appear when referenced by title or task ID):\n" + (catalog.isEmpty ? "No director tasks recorded." : catalog)
            + (full.isEmpty ? "" : "\n\n" + full)
    }
}
