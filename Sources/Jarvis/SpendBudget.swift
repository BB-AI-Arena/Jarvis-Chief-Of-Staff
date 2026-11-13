import Foundation
import Darwin

/// Conservative prepaid allowance, separate from measured token usage. Reservations settle only after verified usage; ambiguous failures and process exits
/// retain their full reservation.
/// This covers new native director requests, not other apps or already-running workers.
enum SpendBudget {
    static var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis/Budgets")
    static let dailyMicroUSD = 10_000_000
    static var allowsUnboundedJobs: Bool { false }
    static var allowsBudgetedFilm: Bool { true }
    static let blocked = "Daily $10 director budget: this job has no enforceable maximum charge, so it was not started."
    struct Hold: Codable { var seat: String; var microUSD: Int }
    struct State: Codable { var day: String; var reserved: [String: Int]; var holds: [String: Hold]? = [:] }
    struct Ticket { let id: String; let day: String }

    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Chicago"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    /// File lock covers concurrent app/probe processes. Invalid state and failed writes fail closed.
    static func reserve(seat: String, microUSD: Int, now: Date = Date()) -> Bool {
        reserveTicket(seat: seat, microUSD: microUSD, now: now) != nil
    }
    static func reserveTicket(seat: String, microUSD: Int, now: Date = Date()) -> Ticket? {
        guard microUSD > 0, microUSD <= dailyMicroUSD else { return nil }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return nil }
        let fd = open(directory.appendingPathComponent("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return nil }; defer { flock(fd, LOCK_UN) }
        let file = directory.appendingPathComponent("daily.json"), stamp = day(now)
        var state = State(day: stamp, reserved: [:])
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
                guard state.reserved.values.allSatisfy({ $0 >= 0 && $0 <= dailyMicroUSD }), state.day <= stamp else { return nil }
                if state.day != stamp { state = State(day: stamp, reserved: [:]) }
            }
            let used = state.reserved[seat, default: 0]
            guard microUSD <= dailyMicroUSD - used else { return nil }
            let ticket = Ticket(id: UUID().uuidString, day: stamp)
            state.reserved[seat] = used + microUSD
            if state.holds == nil { state.holds = [:] }
            state.holds?[ticket.id] = Hold(seat: seat, microUSD: microUSD)
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
            return ticket
        } catch { return nil }
    }
    /// Reserve the entire supported context at the highest standard rate, plus bounded output.
    /// Server-side search, implicit history, caching options and unknown models are refused.
    /// Rates verified Nov 12 2026; expire rather than silently trust stale prices.
    static func maximum(_ request: URLRequest, now: Date = Date()) -> Int? {
        guard day(now) <= "2026-11-30", let data = request.httpBody,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = body["model"] as? String,
              body["previous_response_id"] == nil, body["fallbacks"] == nil, body["service_tier"] == nil else { return nil }
        let tools = body["tools"] as? [[String: Any]] ?? []
        guard tools.allSatisfy({ $0["type"] == nil || ($0["type"] as? String) == "function" }),
              !String(decoding: data, as: UTF8.self).contains("cache_control") else { return nil }
        // xAI official model pricing, verified 2026-11-12: medium 2K output $0.08,
        // plus $0.01 per reference image. Reserve the full fixed charge, never refund it.
        if request.url?.absoluteString == "https://api.x.ai/v1/images/edits", model == "grok-imagine-image-2.0" {
            guard body["n"] as? Int == 1,body["quality"] as? String == "medium",body["resolution"] as? String == "2k",
                  let images = body["images"] as? [[String:Any]],(1...5).contains(images.count),
                  images.allSatisfy({ ($0["type"] as? String) == "image_url" && ($0["url"] as? String)?.hasPrefix("data:image/") == true }) else { return nil }
            return 80_000 + images.count * 10_000
        }
        let output = (body["max_tokens"] as? Int) ?? (body["max_output_tokens"] as? Int)
        guard let output, output > 0, output <= 32000 else { return nil }
        switch (request.url?.host, model) {
        case ("api.anthropic.com", "claude-haiku-5-5"): return 500_000 + (output * 5 + 1) / 2
        case ("api.anthropic.com", "claude-sonnet-5-5"): return 2_000_000 + output * 10
        case ("api.anthropic.com", "claude-opus-5-5"): return 4_000_000 + output * 20
        case ("api.x.ai", "grok-4.7"): return 2_000_000 + output * 12
        case ("api.x.ai", "grok-4.20-0309-non-reasoning"): return 2_500_000 + output * 5
        default: return nil
        }
    }
    static func authorize(_ request: URLRequest, seat: String?) -> Ticket? {
        guard let cost = maximum(request) else { return nil }
        return reserveTicket(seat: seat ?? "jarvis", microUSD: cost)
    }
    /// Exact response usage at conservative uncached/high-context rates. Unknown usage
    /// cannot release funds. Missing/replayed tickets and late prior-day responses are inert.
    static func responseCost(_ request: URLRequest, data: Data?) -> Int? {
        guard let bodyData = request.httpBody,
              let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let model = body["model"] as? String,
              let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any] else { return nil }
        let inputKey = request.url?.host == "api.anthropic.com" ? "input_tokens" : "prompt_tokens"
        let outputKey = request.url?.host == "api.anthropic.com" ? "output_tokens" : "completion_tokens"
        guard let input = usage[inputKey] as? Int, let output = usage[outputKey] as? Int,
              input >= 0, output >= 0, input <= 2_000_000, output <= 32000 else { return nil }
        // Explicit caching and server tools are refused; do not settle unexpected billing categories.
        for key in ["cache_creation_input_tokens", "cache_read_input_tokens"] {
            if let count = usage[key] as? Int, count != 0 { return nil }
        }
        switch (request.url?.host, model) {
        case ("api.anthropic.com", "claude-haiku-5-5"): return (input + output * 5 + 1) / 2
        case ("api.anthropic.com", "claude-sonnet-5-5"): return input * 2 + output * 10
        case ("api.anthropic.com", "claude-opus-5-5"): return input * 4 + output * 20
        case ("api.x.ai", "grok-4.7"): return input * 4 + output * 12
        case ("api.x.ai", "grok-4.20-0309-non-reasoning"): return (input * 5 + 1) / 2 + output * 5
        default: return nil
        }
    }
    static func settle(_ ticket: Ticket, actualMicroUSD: Int) {
        guard actualMicroUSD >= 0 else { return }
        let fd = open(directory.appendingPathComponent("lock").path, O_RDWR)
        guard fd >= 0 else { return }; defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return }; defer { flock(fd, LOCK_UN) }
        let file = directory.appendingPathComponent("daily.json")
        guard var state = try? JSONDecoder().decode(State.self, from: Data(contentsOf: file)),
              state.day == ticket.day, let hold = state.holds?[ticket.id],
              actualMicroUSD <= hold.microUSD,
              let used = state.reserved[hold.seat], used >= hold.microUSD else { return }
        state.reserved[hold.seat] = used - hold.microUSD + actualMicroUSD
        state.holds?[ticket.id] = nil
        // Failed persistence keeps the original reservation on disk.
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: file, options: .atomic) }
    }
}

/// Denials still complete exactly once, without sending the authenticated request.
enum BudgetHTTP {
    static func dataTask(with request: URLRequest, seat: String?, session: URLSession = .shared, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        guard let ticket = SpendBudget.authorize(request, seat: seat) else {
            let task = URLSession.shared.dataTask(with: URL(string: "about:blank")!)
            task.cancel()
            DispatchQueue.global().async {
                let reason = SpendBudget.maximum(request) == nil ? SpendBudget.blocked : "Daily $10 director budget: insufficient remaining allowance or unreadable budget state. No request was sent."
                completionHandler(nil, nil, NSError(domain: "JarvisBudget", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
            }
            return task
        }
        return session.dataTask(with: request) { data, response, error in
            if error == nil, let status = (response as? HTTPURLResponse)?.statusCode,
               (200..<300).contains(status), let actual = SpendBudget.responseCost(request, data: data) {
                SpendBudget.settle(ticket, actualMicroUSD: actual)
            }
            completionHandler(data, response, error)
        }
    }
}
