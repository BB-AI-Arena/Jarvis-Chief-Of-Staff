import Foundation
struct RouteDecision {
    let route: String
    let text: String
    var director: String?
    /// For route=suggest: the task Jarvis proposes. Nothing is recorded until Brandon approves it.
    var task: String? = nil
    static let directors = ["operations", "technology", "research", "creative", "projects"]
    static let routes = ["reply", "astra", "task", "assign", "suggest", "debate", "remember", "lookup", "approve_story"]
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
            return RouteDecision(route: route, text: answer, director: classify(task, hinted: director), task: task)
        }
        if route == "remember" {
            let fact = (result["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return RouteDecision(route: route, text: answer, director: nil, task: (fact?.isEmpty == false ? fact : answer).map { String($0.prefix(500)) })
        }
        if route == "debate" {
            let question = (result["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return RouteDecision(route: route, text: answer, director: nil, task: (question?.isEmpty == false ? question : answer).map { String($0.prefix(500)) })
        }
        // assign/task: `task` is the work for the director, `text` is what Jarvis says. Older replies put the task in text.
        let work = (result["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RouteDecision(route: route, text: answer, director: director, task: (route == "assign" || route == "task" || route == "lookup" || route == "approve_story") && work?.isEmpty == false ? work : nil)
    }
    /// True when text is something Jarvis would say ("Moving this to Operations, as agreed.") rather than work a director can do.
    static func isAcknowledgement(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.count < 90 else { return false }
        let openers = ["moving this", "moving that", "on it", "right away", "certainly", "of course", "very good", "will do", "consider it", "understood", "as agreed", "i'll ", "i will ", "i've ", "i have ", "handing ", "passing ", "sending ", "assigning ", "adding ", "done", "yes", "sure", "absolutely", "noted", "leave it with"]
        return openers.contains { lower.hasPrefix($0) } || lower.hasSuffix("as agreed.") || lower.hasSuffix("as requested.")
    }
    /// The text a director receives: the task field, else the text, else Brandon's own words when the router only acknowledged.
    static func work(for decision: RouteDecision, prompt: String) -> String? {
        for candidate in [decision.task, decision.text] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isAcknowledgement(candidate) { return candidate }
        }
        let own = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.split(separator: " ").count >= 5 && !isAcknowledgement(own) ? own : nil
    }
    static func completeWork(_ work: String, original: String) -> String {
        guard !original.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !work.contains(original) else { return work }
        return work + "\n\nOriginal user request (preserve all requirements; routing text above is only the handoff):\n" + original
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
    static let videoRule = "Video: any request to make a video, trailer, promo, animation or clip goes to route=assign with director creative; keep the requested length, quality and style in the task text. The Creative Director plans the shots and renders them. Requests to create a video from artwork or reference images also go to creative: it can feed the actual artwork into ComfyUI. Preserve any source directory and filenames in task. It cannot visually verify a finished video."
    static let selfRule = "Jarvis's own app: you can improve yourself by delegating. Any request to fix, change or add to Jarvis himself (his screens, UI, board, animations, settings, features or bugs) goes to route=assign with director operations; the Operations worker edits and builds the Jarvis source. Put the user's request in the task text with the result they want to see. Never say you cannot change your own app."
    /// What each director can really do. Work goes to the seat with the tools for it, not to a keyword match.
    static let strengthsRule = "Choose the director by what the work needs. research: facts from the public web (markets, competitors, prices, news); it cannot see Brandon's files, images or videos, so never give it file checks or verification of the board's own work. technology (CTO): reads the Jarvis code and workspace files, reviews engineering, and can inspect DARK (the GPU server); give it technical questions and checks of files, logs or renders. operations: changes files, runs commands and jobs on this Mac or DARK, and fixes Jarvis's own app. creative: makes videos and handles visual direction, naming and copy. projects: plans, scope and timelines. One task goes to one director; do not assign the same work twice. No director can watch a video yet: if a request needs visual inspection of a video, say so in a reply instead of assigning it. Creative's artwork video planner can inspect the supplied reference previews, write a storyboard, and use those images as conditioning. Other directors do not have image inspection tools."
    static let rememberRule = "Memory: when the user asks you to remember, note or keep in mind a fact, preference or decision, use route=remember with the fact as one plain sentence in task and a short spoken confirmation in text."
    /// The routing rules shared by every Jarvis brain (Claude router, Luna, local).
    static let limitsRule = "Delivery limits: use up to 50,000 characters per numbered prompt part; retain longer assignments across all parts and additional prompts when needed. Never clip an assignment to that size. Retain the complete current user request. The app attaches original instructions to assignments, so route with a concise directive instead of trying to repeat a long document inside a short routing response. Task titles and status summaries are shortened for display only. Recent dialogue is a bounded excerpt, not perfect memory: say when a required earlier detail is missing. Each director has finite input context, output length, tool rounds, timeout and token budget. Plan large jobs as numbered, scoped parts; carry the original requirements, dependencies and completed work into each part, and integrate all parts before calling the task finished. Continue an interrupted answer in another prompt where supported, rather than silently dropping its end. Splitting messages alone does not enlarge a model's context. Never claim every part arrived, was reviewed or finished without delivery/result evidence. Report any remaining limit or incomplete part, preserve the work and request only the missing information or authority."
    static let lookupRule = "Read-only board/workspace questions: you can inspect current board records and saved director results. Use route=reply when the supplied evidence answers the question. If more source is needed, use route=lookup with task as a JSON string containing path (relative workspace text path, or empty for inventory) and offset (the returned cursor). Follow next_offset for remaining material; never claim an excerpt is the whole result. A lookup is not a new assignment, does not execute source text and needs no director job. Cite the recorded state and distinguish final judgments from progress updates. If a result is missing or unverified, say so."
    static let approvalRule = "Screenplay approval: only after the complete agreed screenplay is presented, an explicit user statement such as I approve this screenplay or Approved can use route=approve_story. Put the exact current screenplay SHA256 from the live board evidence in task. Conditional statements (if I approve), questions, requests to change approval behavior, and a director's acceptance are never owner approval. The app validates the actual user words, current phase, viewed version and hash before starting production."
    static let routerRules = approvalRule + " " + lookupRule + " " + limitsRule + " " + "Return JSON with route, text and optional director. You never execute work yourself. Use route=reply for discussion, with your spoken reply in text. Use route=astra only for substantial reasoning or when the user explicitly asks Astra to reason; text must contain the precise reasoning request. Use route=task ONLY when the user explicitly asks for a concrete action on Jarvis's own source (director operations). Use route=assign for any other concrete request: put the complete, self-contained task in task (what to do, about what, with every detail from the conversation the director needs, because the director sees only that text and not this conversation) and what you say aloud in text. Never put an acknowledgement such as \"Moving this to Operations\" in task. " + strengthsRule + " Merely discussing possible features is not a task. Task list: when the user asks you to do, make, find, fix, build, design, research or plan something concrete, use route=assign with the complete task in task and the best director; the app records it on the task list and tells the user, so do not claim it yourself. In normal conversation you may suggest one useful task: use route=suggest, put a short spoken suggestion that asks for approval in text (for example: Shall I add drafting the launch plan to the task list for Projects?), the task itself in task, and the director. Nothing is added until the user approves. If the user approves a task you suggested earlier, use route=assign with that full task in task. Never say a task was added unless the app confirmed it.  " + debateRule + " " + rememberRule + " " + videoRule + " " + selfRule
    /// Shared routing rule for every Jarvis brain: the board debates on request; Jarvis never invents its answer.
    static let debateRule = "Board debate: when the user asks the board or the directors to debate, discuss, argue out or weigh in on a question, use route=debate with the question in task and a short spoken acknowledgement in text. The app runs a live debate and reports the verdict; never invent what the board thinks."
    /// Work is an assignment to a director. Jarvis is not a director and never executes it.
    static func assignment(for decision: RouteDecision) -> (director: String, text: String)? {
        guard decision.route == "task" || decision.route == "assign" else { return nil }
        let text = decision.task ?? decision.text
        let director = classify(text, hinted: decision.director)
        guard directors.contains(director) else { return nil }
        return (director, text)
    }
    /// True when a director's result says it was blocked or could not do the work. No follow-up is offered then:
    /// suggesting "try again" or "diagnose why" loops on the same wall.
    static func looksBlocked(_ result: String) -> Bool {
        let lower = result.prefix(1500).lowercased()
        return ["could not", "couldn't", "cannot ", "can't ", "unable to", "was denied", "denied the", "permission denied", "operation not permitted", "is blocked", "blocked before", "not permitted", "no access", "failed to"].contains { lower.contains($0) }
    }
    /// A suggestion Brandon has not approved yet. It is shown for approval and never recorded as a task.
    static func suggestion(for decision: RouteDecision) -> (director: String, title: String)? {
        guard decision.route == "suggest", let task = decision.task, !task.isEmpty else { return nil }
        return (classify(task, hinted: decision.director), task)
    }
    static func classify(_ text: String, hinted: String?) -> String {
        if let hinted, directors.contains(hinted) { return hinted }
        let lower = text.lowercased()
        let selfWords = ["your ui", "your own ui", "your interface", "your screen", "your app", "your own app", "yourself", "jarvis app", "jarvis's ui", "jarvis ui", "your board", "your settings"]
        if selfWords.contains(where: { lower.contains($0) }) { return "operations" }
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
