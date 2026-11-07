import Foundation
struct RouteDecision {
    let route: String
    let text: String
    static func decode(_ raw: String) -> RouteDecision? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json\n"), text.hasSuffix("```") { text = String(text.dropFirst(8).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        else if text.hasPrefix("```\n"), text.hasSuffix("```") { text = String(text.dropFirst(4).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let data = text.data(using: .utf8), let result = try? JSONSerialization.jsonObject(with: data) as? [String: String], let route = result["route"], ["reply", "astra", "task"].contains(route), let answer = result["text"], !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return RouteDecision(route: route, text: answer)
    }
}
