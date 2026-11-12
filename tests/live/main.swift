import Foundation
let fm = FileManager.default
let base = fm.temporaryDirectory.appendingPathComponent("jarvis-live-\(UUID().uuidString)")
let bundle = base.appendingPathComponent("bundle"), source = base.appendingPathComponent("source"), live = base.appendingPathComponent("support/ui-live")
for dir in [bundle, source, base.appendingPathComponent("support")] { try! fm.createDirectory(at: dir, withIntermediateDirectories: true) }
func page(_ dir: URL, _ js: String) {
    try! "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    try! js.write(to: dir.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)
    try! "body{}".write(to: dir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
    try! "window.x=1;".write(to: dir.appendingPathComponent("live.js"), atomically: true, encoding: .utf8)
}
page(bundle, "var a=1;"); page(source, "var a=1;")
assert(LiveUI.root(bundle: bundle, live: live) == bundle)
assert(LiveUI.apply(source: source, bundle: bundle, live: live, node: nil) == .unchanged)
page(source, "var a=2;")
assert(LiveUI.apply(source: source, bundle: bundle, live: live, node: nil) == .applied)
assert(LiveUI.root(bundle: bundle, live: live) == live && fm.fileExists(atPath: live.appendingPathComponent("live.js").path))
assert(LiveUI.apply(source: source, bundle: bundle, live: live, node: nil) == .unchanged)
if let node = LiveUI.nodePath {
    page(source, "var a = ;")
    if case .failed(let why) = LiveUI.apply(source: source, bundle: bundle, live: live, node: node) { assert(why.contains("app.js")) } else { assert(false) }
    assert(try! String(contentsOf: live.appendingPathComponent("app.js"), encoding: .utf8) == "var a=2;")
}
page(bundle, "var a=3;")   // a newer installed build makes the old live copy stale
assert(LiveUI.root(bundle: bundle, live: live) == bundle)
LiveUI.rollBack(live: live)
assert(!fm.fileExists(atPath: live.path))
print("PASS: UI updates apply in place from the source page, skip broken scripts, and never outlive a newer installed build")
let results = base.appendingPathComponent("Results")
try! fm.createDirectory(at: results.appendingPathComponent("2026 video abc"), withIntermediateDirectories: true)
try! Data("12345".utf8).write(to: results.appendingPathComponent("2026 video abc/final.mp4"))
let good = URL(string: ResultMedia.url(for: "2026 video abc/final.mp4"))!
assert(ResultMedia.resolve(good, root: results)?.lastPathComponent == "final.mp4")
for bad in ["jarvis-media://results/../secret.mp4", "jarvis-media://results/2026%20video%20abc/../../x.mp4", "jarvis-media://results/.hidden/a.mp4", "jarvis-media://other/a.mp4", "jarvis-media://results/2026%20video%20abc/notes.md"] {
    assert(ResultMedia.resolve(URL(string: bad)!, root: results) == nil, bad)
}
assert(ResultMedia.range("bytes=0-1", length: 5) == 0...1 && ResultMedia.range("bytes=2-", length: 5) == 2...4 && ResultMedia.range("bytes=-2", length: 5) == 3...4)
assert(ResultMedia.range("bytes=9-", length: 5) == nil && ResultMedia.range(nil, length: 5) == nil && ResultMedia.range("bytes=1-99", length: 5) == 1...4)
print("PASS: results play inside Jarvis from the Results folder only, with seeking")
TokenMeter.file = base.appendingPathComponent("usage.json"); TokenMeter.reset()
assert(TokenMeter.usage(from: Data("{\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"cache_read_input_tokens\":2}}".utf8))! == (12, 5))
assert(TokenMeter.usage(from: Data("{\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":3}}".utf8))! == (7, 3))
assert(TokenMeter.usage(from: Data("{\"prompt_eval_count\":4,\"eval_count\":6}".utf8))! == (4, 6))
assert(TokenMeter.usage(from: Data("{\"text\":\"hi\"}".utf8)) == nil)
assert(TokenMeter.workerTokens("done\ntokens used\n12,345\n") == 12345 && TokenMeter.workerTokens("tokens used: 99") == 99 && TokenMeter.workerTokens("nothing") == nil)
TokenMeter.charge("technology") { TokenMeter.record(TokenMeter.tag, model: "claude-sonnet-5-5", data: Data("{\"usage\":{\"input_tokens\":100,\"output_tokens\":20}}".utf8)) }
TokenMeter.record(nil, model: "claude-haiku-5-5", data: Data("{\"usage\":{\"input_tokens\":30,\"output_tokens\":4}}".utf8))
assert(TokenMeter.tag == nil)
let snap = TokenMeter.snapshot(), today = snap["today"] as! [String: [String: Any]]
assert(today["technology"]?["total"] as? Int == 120 && today["jarvis"]?["calls"] as? Int == 1)
let saved = try! JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("usage.json"))) as! [String: Any]
assert(((saved["allTime"] as! [String: Any])["technology"] as? [String: Any]) != nil)
print("PASS: tokens are read from each provider's reply and charged to the director whose work made the call")
try? fm.removeItem(at: base)
