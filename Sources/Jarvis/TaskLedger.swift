import Foundation

struct TaskRecord: Codable, Equatable {
    var id: String
    var state: String
    var verified: Bool
    var owner: String
    var parentID: String?
    var createdAt: String
    var updatedAt: String
    var resultSummary: String
    var title: String

    static let states = ["proposed", "running", "completed", "failed", "cancelled"]

    var payload: [String: Any] {
        var item: [String: Any] = [
            "id": id, "state": state, "verified": verified, "owner": owner,
            "createdAt": createdAt, "updatedAt": updatedAt,
            "resultSummary": resultSummary, "title": title
        ]
        if let parentID { item["parentID"] = parentID }
        return item
    }
}

enum TaskLedger {
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
    static func encode(_ records: [TaskRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(records)
    }
    static func decode(_ data: Data) throws -> [TaskRecord] {
        guard let records = try? JSONDecoder().decode([TaskRecord].self, from: data) else { return [] }
        return records.filter { TaskRecord.states.contains($0.state) }
    }
    /// A task still marked running when the app quits or launches again did not finish.
    static func interruptRunning(_ records: [TaskRecord], at timestamp: String) -> [TaskRecord] {
        records.map { record in
            guard record.state == "running" else { return record }
            var copy = record
            copy.state = "failed"
            copy.verified = false
            copy.updatedAt = timestamp
            copy.resultSummary = record.resultSummary.isEmpty ? "interrupted" : record.resultSummary + " interrupted"
            return copy
        }
    }
}

final class TaskStore {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    private var file: URL { directory.appendingPathComponent("ledger.json") }
    func load() -> [TaskRecord] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? TaskLedger.decode(data)) ?? []
    }
    func save(_ records: [TaskRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TaskLedger.encode(records).write(to: file, options: .atomic)
    }
}
