import Foundation

/// Counts the tokens each director actually used, read from the providers' own replies (Claude and Grok "usage",
/// Ollama eval counts, the Operations worker's "tokens used" line). Nothing is estimated. Calls are charged to the
/// director whose work started them; anything else (routing, next-step offers) is charged to Jarvis.
/// Kept in ~/Library/Application Support/Jarvis/usage.json as today's numbers and all-time totals.
enum TokenMeter {
    struct Line: Equatable { var calls = 0, input = 0, output = 0; var total: Int { input + output } }
    /// The director to charge for calls started synchronously right now (main thread only). Use `charge`.
    static var tag: String?
    static var file: URL?
    static var onChange: (() -> Void)?
    private static var today: [String: [String: Line]] = [:]     // seat → model → line
    private static var allTime: [String: [String: Line]] = [:]
    private static var day = ""
    private static var loaded = false
    private static let lock = NSLock()

    /// Runs `work` with every client call it starts synchronously charged to `seat`.
    @discardableResult static func charge<T>(_ seat: String, _ work: () -> T) -> T {
        let previous = tag; tag = seat
        defer { tag = previous }
        return work()
    }
    /// (input, output) from any provider's reply body, or nil when it carries no usage.
    static func usage(from data: Data?) -> (input: Int, output: Int)? {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let usage = json["usage"] as? [String: Any] {
            let int: (String) -> Int = { (usage[$0] as? Int) ?? 0 }
            let input = int("input_tokens") + int("cache_read_input_tokens") + int("cache_creation_input_tokens") + int("prompt_tokens")
            let output = int("output_tokens") + int("completion_tokens")
            return input + output > 0 ? (input, output) : nil
        }
        let input = (json["prompt_eval_count"] as? Int) ?? 0, output = (json["eval_count"] as? Int) ?? 0
        return input + output > 0 ? (input, output) : nil
    }
    /// The total from the Operations worker's log ("tokens used: 12,345" or "tokens used\n12,345").
    static func workerTokens(_ log: String) -> Int? {
        guard let range = log.range(of: "tokens used[^0-9]{0,6}([0-9][0-9,]*)", options: [.regularExpression, .caseInsensitive, .backwards]) else { return nil }
        return Int(log[range].filter(\.isNumber))
    }
    static func record(_ seat: String?, model: String, data: Data?) {
        guard let usage = usage(from: data) else { return }
        add(seat ?? "jarvis", model: model, input: usage.input, output: usage.output)
    }
    static func add(_ seat: String, model: String, input: Int, output: Int, date: Date = Date()) {
        lock.lock()
        loadIfNeeded()
        let stamp = dayString(date)
        if stamp != day { day = stamp; today = [:] }
        for keyPath in [0, 1] {
            var table = keyPath == 0 ? today : allTime
            var line = table[seat, default: [:]][model, default: Line()]
            line.calls += 1; line.input += max(input, 0); line.output += max(output, 0)
            table[seat, default: [:]][model] = line
            if keyPath == 0 { today = table } else { allTime = table }
        }
        save()
        lock.unlock()
        DispatchQueue.main.async { onChange?() }
    }
    /// Tokens a seat has used today (input + output), for per-task budgets.
    static func used(_ seat: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        if dayString(Date()) != day { day = dayString(Date()); today = [:] }
        return (today[seat] ?? [:]).values.reduce(0) { $0 + $1.total }
    }
    /// Per-seat summary for the page: today and all time, with a per-model breakdown.
    static func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        if dayString(Date()) != day { day = dayString(Date()); today = [:] }
        func encode(_ table: [String: [String: Line]]) -> [String: Any] {
            table.mapValues { models -> [String: Any] in
                let sum = models.values.reduce(Line()) { Line(calls: $0.calls + $1.calls, input: $0.input + $1.input, output: $0.output + $1.output) }
                return ["calls": sum.calls, "input": sum.input, "output": sum.output, "total": sum.total,
                        "models": models.mapValues { ["calls": $0.calls, "input": $0.input, "output": $0.output] }]
            }
        }
        return ["day": day, "today": encode(today), "allTime": encode(allTime)]
    }
    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
    private static func decode(_ any: Any?) -> [String: [String: Line]] {
        guard let seats = any as? [String: [String: [String: Int]]] else { return [:] }
        return seats.mapValues { $0.mapValues { Line(calls: $0["calls"] ?? 0, input: $0["input"] ?? 0, output: $0["output"] ?? 0) } }
    }
    private static func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let file, let data = try? Data(contentsOf: file), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        day = json["day"] as? String ?? ""
        today = decode(json["today"]); allTime = decode(json["allTime"])
    }
    private static func save() {
        guard let file else { return }
        let encode: ([String: [String: Line]]) -> [String: Any] = { $0.mapValues { $0.mapValues { ["calls": $0.calls, "input": $0.input, "output": $0.output] } } }
        if let data = try? JSONSerialization.data(withJSONObject: ["day": day, "today": encode(today), "allTime": encode(allTime)], options: [.sortedKeys]) {
            try? data.write(to: file, options: .atomic)
        }
    }
    /// Test hook: forget everything in memory.
    static func reset() { lock.lock(); today = [:]; allTime = [:]; day = ""; loaded = true; lock.unlock() }
}
