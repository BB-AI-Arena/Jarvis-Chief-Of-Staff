import Foundation
import CryptoKit

struct FilmStory: Codable {
    var id = UUID().uuidString
    var brief: String
    var phase = "new"
    var taskID = ""
    var round = 0
    var reviewDeliveryFailures: Int? = nil
    var sourceEvidence: String? = nil
    var research = ""
    var script = ""
    var feedback = ""
    var ownerRevisionFeedback: String? = nil
    var hash = ""
    var viewedHash = ""
    var approvedHash = ""
    var approvedAt = ""
    var history: [String] = []
    static func consultationText(_ raw: String) -> String {
        // Cursor's transport prefix is metadata, not part of the director's screenplay or acceptance.
        guard let prefix = raw.range(of:"Cursor agent finished · "),let end = raw.range(of:" · ",range:prefix.upperBound..<raw.endIndex) else { return raw }
        var body = String(raw[end.upperBound...])
        if body.hasPrefix("PR "),let next = body.range(of:" · ") { body = String(body[next.upperBound...]) }
        return body
    }
    static func screenplay(_ raw: String) -> String {
        let lines = raw.components(separatedBy:.newlines)
        guard let start = lines.firstIndex(where:{$0.hasPrefix("RUNTIME_SECONDS:")}) else { return raw }
        return lines[start...].joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func isExplicitApproval(_ prompt: String) -> Bool {
        let text = prompt.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        // Match a complete owner statement, never an approval word embedded in instructions,
        // quoted dialogue, a question, a condition, or approval of some unrelated task.
        let subject = "(?:(?:this|the)(?: exact| agreed| current)? (?:screenplay|script|story|storyline)(?: version)?)"
        let approval = "(?:(?:i )?approve(?: (?:" + subject + "|it))?|approved|" + subject + " (?:is )?approved)"
        let production = "(?:[,;.!] ?| and )(?:please )?(?:make (?:the movie|the film)|start (?:rendering|production)|render the film)"
        return text.range(of:"^(?:jarvis[, ]+)?(?:yes[, ]+)?(?:please )?" + approval + "(?:" + production + ")?[.!]*$",options:.regularExpression) != nil
    }

    static func digest(_ text: String) -> String { SHA256.hash(data:Data(text.utf8)).map { String(format:"%02x",$0) }.joined() }
    var runtime: Int? {
        guard let line = script.components(separatedBy:.newlines).first(where:{$0.hasPrefix("RUNTIME_SECONDS:")}),
              let seconds = Int(line.dropFirst("RUNTIME_SECONDS:".count).trimmingCharacters(in:.whitespaces)),seconds >= 15,seconds <= 600 else { return nil }
        return seconds
    }
    func canRender(task assignmentID: String) -> Bool {
        phase == "rendering" && taskID == assignmentID && !approvedAt.isEmpty &&
        !approvedHash.isEmpty && approvedHash == hash && hash == Self.digest(script) && runtime != nil
    }
    func canApprove(_ submitted: String) -> Bool {
        phase == "awaiting_approval" && runtime != nil && !script.isEmpty && hash == Self.digest(script) && submitted == hash && viewedHash == hash
    }
}


/// Local writing-only request; stale screenplay versions cannot restart consultation.
struct StoryRevisionRequest: Codable {
    var id = UUID().uuidString
    let storyID: String
    let expectedHash: String
    let feedback: String
    var writingSeat: String? = nil
}

struct ReviewedStoryAdoption: Codable {
    var id = UUID().uuidString
    let storyID: String
    let previousHash: String
    let script: String
    let scriptHash: String
    let researchTaskID: String
    let creativeTaskID: String
}

struct ExternalStoryApproval: Codable {
    var id = UUID().uuidString
    let scriptHash: String
    let sourceChatID: String
    let ownerText: String
}
