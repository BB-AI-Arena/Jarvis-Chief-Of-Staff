import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
SpendBudget.directory = root
defer { try? FileManager.default.removeItem(at: root) }
let now = ISO8601DateFormatter().date(from: "2026-11-12T18:00:00Z")!
assert(SpendBudget.reserve(seat: "technology", microUSD: 6_000_000, now: now))
assert(!SpendBudget.reserve(seat: "technology", microUSD: 5_000_000, now: now))
assert(SpendBudget.reserve(seat: "research", microUSD: 10_000_000, now: now))
assert(!SpendBudget.reserve(seat: "research", microUSD: 1, now: now))
assert(!SpendBudget.reserve(seat: "technology", microUSD: -1, now: now))
assert(SpendBudget.reserve(seat: "technology", microUSD: 4_000_000, now: now))
assert(SpendBudget.reserve(seat: "technology", microUSD: 10_000_000, now: now.addingTimeInterval(86400)))
assert(!SpendBudget.reserve(seat: "technology", microUSD: 1, now: now))
try! Data("broken".utf8).write(to: root.appendingPathComponent("daily.json"))
assert(!SpendBudget.reserve(seat: "projects", microUSD: 1, now: now))
try! FileManager.default.removeItem(at: root.appendingPathComponent("daily.json"))
let lock = NSLock(); var allowed = 0
DispatchQueue.concurrentPerform(iterations: 20) { _ in
    if SpendBudget.reserve(seat: "creative", microUSD: 1_000_000, now: now) { lock.lock(); allowed += 1; lock.unlock() }
}
assert(allowed == 15)
var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
r.httpBody = try! JSONSerialization.data(withJSONObject: ["model":"claude-sonnet-5-5","max_tokens":1200])
assert(SpendBudget.maximum(r, now: now) == 2_012_000)
assert(SpendBudget.maximum(r, now: now.addingTimeInterval(30 * 86400)) == nil)
r.httpBody = try! JSONSerialization.data(withJSONObject: ["model":"claude-sonnet-5-5","max_tokens":1200,"tools":[["type":"web_search_20250305"]]])
assert(SpendBudget.maximum(r, now: now) == nil)
assert(!SpendBudget.allowsUnboundedJobs)
print("PASS: independent daily caps, exact boundary, rollover, rollback, corruption, concurrency, expiry and unbounded-job denial")
// Settlement releases only the unused portion of this exact ticket, once.
SpendBudget.directory = root.appendingPathComponent("settlement")
let ticket = SpendBudget.reserveTicket(seat: "creative", microUSD: 4_240_000, now: now)!
SpendBudget.settle(ticket, actualMicroUSD: 200_000)
SpendBudget.settle(ticket, actualMicroUSD: 0)
assert(SpendBudget.reserve(seat: "creative", microUSD: 14_800_000, now: now))
assert(!SpendBudget.reserve(seat: "creative", microUSD: 1, now: now))
let nextDay = SpendBudget.reserveTicket(seat: "creative", microUSD: 15_000_000, now: now.addingTimeInterval(86400))!
SpendBudget.settle(ticket, actualMicroUSD: 0)
assert(!SpendBudget.reserve(seat: "creative", microUSD: 1, now: now.addingTimeInterval(86400)))
SpendBudget.settle(nextDay, actualMicroUSD: 16_000_000)
assert(!SpendBudget.reserve(seat: "creative", microUSD: 1, now: now.addingTimeInterval(86400)))
r.httpBody = try! JSONSerialization.data(withJSONObject: ["model":"claude-opus-5-5","max_tokens":12000])
assert(SpendBudget.maximum(r, now: now) == 4_240_000)
let usage = try! JSONSerialization.data(withJSONObject: ["usage":["input_tokens":1000,"output_tokens":100]])
assert(SpendBudget.responseCost(r, data:usage) == 6000)
assert(SpendBudget.responseCost(r, data:Data("{}".utf8)) == nil)
print("PASS: usage settlement, replay protection, cross-day completion, over-reservation rejection and long-output bounds")

// Raising Creative preserves old reservations and keeps every other seat at ten.
SpendBudget.directory = root.appendingPathComponent("raised-cap")
let old = SpendBudget.State(day: SpendBudget.day(now), reserved:["creative":10_000_000,"research":10_000_000], holds:["old":SpendBudget.Hold(seat:"creative",microUSD:4_240_000)])
try! FileManager.default.createDirectory(at:SpendBudget.directory,withIntermediateDirectories:true)
try! JSONEncoder().encode(old).write(to:SpendBudget.directory.appendingPathComponent("daily.json"))
assert(SpendBudget.reserve(seat:"creative",microUSD:5_000_000,now:now))
assert(!SpendBudget.reserve(seat:"creative",microUSD:1,now:now))
assert(!SpendBudget.reserve(seat:"research",microUSD:1,now:now))
let raised = try! JSONDecoder().decode(SpendBudget.State.self,from:Data(contentsOf:SpendBudget.directory.appendingPathComponent("daily.json")))
assert(raised.holds?["old"]?.microUSD == 4_240_000)
print("PASS: Creative15 cap preserves old spend/holds and other seats remain10")
