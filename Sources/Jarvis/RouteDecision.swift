import Foundation
struct RouteDecision {
    let route: String
    let text: String
    var director: String?
    static let directors = ["operations", "technology", "research", "creative", "projects"]
    static func decode(_ raw: String) -> RouteDecision? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json\n"), text.hasSuffix("```") { text = String(text.dropFirst(8).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        else if text.hasPrefix("```\n"), text.hasSuffix("```") { text = String(text.dropFirst(4).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let data = text.data(using: .utf8), let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let route = result["route"] as? String, ["reply", "astra", "task", "assign"].contains(route), let answer = result["text"] as? String, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let hinted = result["director"] as? String
        if route == "assign" {
            guard let hinted, directors.contains(hinted) else { return nil }
        }
        let director = hinted.flatMap { directors.contains($0) ? $0 : nil }
        return RouteDecision(route: route, text: answer, director: director)
    }
    /// Work is an assignment to a director. Jarvis is not a director and never executes it.
    static func assignment(for decision: RouteDecision) -> (director: String, text: String)? {
        guard decision.route == "task" || decision.route == "assign" else { return nil }
        let director = classify(decision.text, hinted: decision.director)
        guard directors.contains(director) else { return nil }
        return (director, decision.text)
    }
    static func classify(_ text: String, hinted: String?) -> String {
        if let hinted, directors.contains(hinted) { return hinted }
        let lower = text.lowercased()
        if lower.contains("grok") || lower.contains("research") { return "research" }
        if lower.contains("design") || lower.contains("creative") || lower.contains("visual") { return "creative" }
        if lower.contains("project plan") || lower.contains("roadmap") || lower.contains("planning") { return "projects" }
        if lower.contains("claude") || lower.contains("engineering review") || lower.contains("code review") { return "technology" }
        return "operations"
    }
}

enum OperationsManager {
    /// Identifiers this build actually passes to the agent runtime. Nothing else is assumed.
    static let runtimeModels = ["gpt-6-astra", "gpt-6-luna"]
    /// Spellings the owner uses for the Operations manager. Returned only when a live model list contains that exact id.
    static let managerCandidates = ["GPT Sol 6.1", "gpt-sol-6.1", "gpt-sol-6.1:latest"]
    static func resolve(stored: String?, advertised: [String]) -> String? {
        let known = Set(runtimeModels + advertised)
        if let stored = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return known.contains(stored) ? stored : nil
        }
        return managerCandidates.first { advertised.contains($0) }
    }
}
