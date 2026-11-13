import Foundation

/// Only a complete, version-bound judgment is a review. A progress message is not dissent.
struct StoryReview {
    let hash: String
    let decision: String
    let summary: String
    let changes: [String]
    static let contract = """
    STORY_REVIEW_CONTRACT: This is a final review of supplied screenplay and evidence, not a progress update. Return only JSON with script_sha256, decision, summary, changes. decision is accept, revise, or needs_evidence. Echo the supplied screenplay SHA-256 exactly. summary states your concluded judgment. changes is an array of numbered concrete issue/scene/evidence/correction strings; check prior corrections and do not reopen resolved issues without new evidence or a new regression; revise or needs_evidence requires at least one real blocker. Accept requires no unresolved changes. Do not count your intention to read documents as a review. Judge the screenplay as a complete collector story, not merely an implementation checklist. Show the requested benefits, including per-item and total collection value. Clearly labeled illustrative/demo UI or production placeholders may represent upcoming functionality; never describe fictional examples as actual observed market values. Do not erase the owner's concept benefits merely because a feature is planned. Do not invent requirements, stock, edition names or performance measurements. Distinguish the owner's upcoming-feature vision from shipped claims; don't reject an explicitly framed concept merely because it is upcoming. The member offer and mutual contact-sharing sequence is already required. Use the supplied records; identify any precise missing evidence instead of making another general research plan.
    """
    static func parse(_ raw: String, hash: String) -> StoryReview? {
        guard let first = raw.firstIndex(of:"{"),let last = raw.lastIndex(of:"}"),first < last,
              let data = String(raw[first...last]).data(using:.utf8),let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              value["script_sha256"] as? String == hash,let decision = value["decision"] as? String,["accept","revise","needs_evidence"].contains(decision),
              let summary = value["summary"] as? String,!summary.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              let changes = value["changes"] as? [String],changes.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}),
              (decision == "accept" ? changes.isEmpty : !changes.isEmpty) else { return nil }
        return StoryReview(hash:hash,decision:decision,summary:summary,changes:changes)
    }
    var report: String { "Research verdict: " + decision + "\n" + summary + (changes.isEmpty ? "" : "\n" + changes.map{"• " + $0}.joined(separator:"\n")) }
}
