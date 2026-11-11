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
    /// Marker on a parent task that is waiting for its director. Only tasks carrying it start automatically.
    static let queued = "queued"
    static let unassigned = "unassigned"
    static func isQueued(_ record: TaskRecord) -> Bool {
        record.parentID == nil && record.state == "proposed" && record.resultSummary.hasPrefix(queued)
    }
    /// The oldest queued task for a director. Records are stored newest first.
    static func nextQueued(_ records: [TaskRecord], director: String) -> TaskRecord? {
        records.last { isQueued($0) && $0.owner == director }
    }
    /// How many queued tasks are ahead of this one for the same director.
    static func queuedAhead(_ records: [TaskRecord], of id: String) -> Int {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return 0 }
        return records[(index + 1)...].filter { isQueued($0) && $0.owner == records[index].owner }.count
    }
    /// One spoken sentence from a result: no markdown, clipped at a sentence boundary.
    static func headline(_ text: String, limit: Int = 220) -> String {
        var line = text.replacingOccurrences(of: "[*_#`>|]+", with: "", options: .regularExpression)
        line = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let stop = line.range(of: "[.!?](\\s|$)", options: .regularExpression), line.distance(from: line.startIndex, to: stop.lowerBound) >= 20, line.distance(from: line.startIndex, to: stop.lowerBound) < limit {
            return String(line[..<stop.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        guard line.count > limit else { return line }
        return line.prefix(limit).split(separator: " ").dropLast().joined(separator: " ") + "…"
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
