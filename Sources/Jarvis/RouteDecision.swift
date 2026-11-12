import Foundation
struct RouteDecision {
    let route: String
    let text: String
    var director: String?
    /// For route=suggest: the task Jarvis proposes. Nothing is recorded until Brandon approves it.
    var task: String? = nil
    static let directors = ["operations", "technology", "research", "creative", "projects"]
    static let routes = ["reply", "astra", "task", "assign", "suggest", "debate", "remember"]
    /// Strict structured-output schema for Luna. The API rejects a schema unless every property is listed in `required`,
    /// so optional fields are required but nullable. (An earlier optional-field schema made every Luna call fail.)
    static var outputSchema: [String: Any] {
        ["type": "object",
         "properties": ["route": ["type": "string", "enum": routes], "text": ["type": "string"],
                        "director": ["type": ["string", "null"], "enum": directors + [NSNull()]], "task": ["type": ["string", "null"]]],
         "required": ["route", "text", "director", "task"], "additionalProperties": false]
    }
    static func decode(_ raw: String) -> RouteDecision? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json\n"), text.hasSuffix("```") { text = String(text.dropFirst(8).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        else if text.hasPrefix("```\n"), text.hasSuffix("```") { text = String(text.dropFirst(4).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let data = text.data(using: .utf8), let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let route = result["route"] as? String, routes.contains(route), let answer = result["text"] as? String, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let hinted = result["director"] as? String
        // A named director must be real ("jarvis" never is). A null director falls back to classify().
        if route == "assign", let hinted, !directors.contains(hinted) { return nil }
        let director = hinted.flatMap { directors.contains($0) ? $0 : nil }
        if route == "suggest" {
            guard let task = (result["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !task.isEmpty else { return nil }
            return RouteDecision(route: route, text: answer, director: classify(task, hinted: director), task: String(task.prefix(500)))
        }
        if route == "remember" {
            let fact = (result["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return RouteDecision(route: route, text: answer, director: nil, task: (fact?.isEmpty == false ? fact : answer).map { String($0.prefix(500)) })
        }
        if route == "debate" {
            let question = (result["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return RouteDecision(route: route, text: answer, director: nil, task: (question?.isEmpty == false ? question : answer).map { String($0.prefix(500)) })
        }
        return RouteDecision(route: route, text: answer, director: director)
    }
    /// For route=remember: the fact to keep in board memory.
    static func memory(for decision: RouteDecision) -> String? {
        guard decision.route == "remember" else { return nil }
        let fact = (decision.task ?? decision.text).trimmingCharacters(in: .whitespacesAndNewlines)
        return fact.isEmpty ? nil : String(fact.prefix(500))
    }
    /// For route=debate: the question to put to the board (the task field, or the text when task is empty).
    static func debateTopic(for decision: RouteDecision) -> String? {
        guard decision.route == "debate" else { return nil }
        let topic = (decision.task ?? decision.text).trimmingCharacters(in: .whitespacesAndNewlines)
        return topic.isEmpty ? nil : topic
    }
    static let videoRule = "Video: any request to make a video, trailer, promo, animation or clip goes to route=assign with director creative; keep the requested length, quality and style in the task text. The Creative Director plans the shots and renders them."
    static let rememberRule = "Memory: when the user asks you to remember, note or keep in mind a fact, preference or decision, use route=remember with the fact as one plain sentence in task and a short spoken confirmation in text."
    /// The routing rules shared by every Jarvis brain (Claude router, Luna, local).
    static let routerRules = "Return JSON with route, text and optional director. You never execute work yourself. Use route=reply for discussion, with your spoken reply in text. Use route=astra only for substantial reasoning or when the user explicitly asks Astra to reason; text must contain the precise reasoning request. Use route=task ONLY when the user explicitly asks for a concrete action on Jarvis's own source (director operations). Use route=assign for any other concrete request; text must contain the complete task. Set director to operations for workspace work or running jobs on this Mac, technology for engineering, research for facts and markets, creative for look, naming and copy, or projects for plans and scope. Merely discussing possible features is not a task. Task list: when the user asks you to do, make, find, fix, build, design, research or plan something concrete, use route=assign with the complete task in text and the best director; the app records it on the task list and tells the user, so do not claim it yourself. In normal conversation you may suggest one useful task: use route=suggest, put a short spoken suggestion that asks for approval in text (for example: Shall I add drafting the launch plan to the task list for Projects?), the task itself in task, and the director. Nothing is added until the user approves. If the user approves a task you suggested earlier, use route=assign with that task. Never say a task was added unless the app confirmed it.  " + debateRule + " " + rememberRule + " " + videoRule
    /// Shared routing rule for every Jarvis brain: the board debates on request; Jarvis never invents its answer.
    static let debateRule = "Board debate: when the user asks the board or the directors to debate, discuss, argue out or weigh in on a question, use route=debate with the question in task and a short spoken acknowledgement in text. The app runs a live debate and reports the verdict; never invent what the board thinks."
    /// Work is an assignment to a director. Jarvis is not a director and never executes it.
    static func assignment(for decision: RouteDecision) -> (director: String, text: String)? {
        guard decision.route == "task" || decision.route == "assign" else { return nil }
        let director = classify(decision.text, hinted: decision.director)
        guard directors.contains(director) else { return nil }
        return (director, decision.text)
    }
    /// A suggestion Brandon has not approved yet. It is shown for approval and never recorded as a task.
    static func suggestion(for decision: RouteDecision) -> (director: String, title: String)? {
        guard decision.route == "suggest", let task = decision.task, !task.isEmpty else { return nil }
        return (classify(task, hinted: decision.director), task)
    }
    static func classify(_ text: String, hinted: String?) -> String {
        if let hinted, directors.contains(hinted) { return hinted }
        let lower = text.lowercased()
        if lower.contains("grok") || lower.contains("research") { return "research" }
        if lower.contains("design") || lower.contains("creative") || lower.contains("visual") || lower.contains("video") || lower.contains("trailer") || lower.contains("animation") { return "creative" }
        if lower.contains("project plan") || lower.contains("roadmap") || lower.contains("planning") { return "projects" }
        if lower.contains("claude") || lower.contains("engineering review") || lower.contains("code review") { return "technology" }
        return "operations"
    }
}

enum OperationsManager {
    /// Identifiers this build actually passes to the agent runtime. Nothing else is assumed.
    /// gpt-6-sol was confirmed in the runtime's model/list on 2026-11-09 (default effort medium). It is the closest match to "GPT Sol 6.1".
    static let runtimeModels = ["gpt-6-astra", "gpt-6-luna", "gpt-6-sol"]
    static let fallbackWorker = "gpt-6-astra"
    static let effort = "medium"
    /// The model and runtime config the Operations worker runs with. Only runtime models can run it; a local Ollama manager cannot.
    static func worker(manager: String?) -> (model: String, config: [String]) {
        guard let manager, runtimeModels.contains(manager) else { return (fallbackWorker, []) }
        return (manager, ["-c", "model_reasoning_effort=\"\(effort)\""])
    }
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
