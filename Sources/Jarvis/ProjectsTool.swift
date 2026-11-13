import Foundation

/// One instance per director assignment; reused across model retries. Main-queue only.
final class ProjectsTool {
    static let name = "delegate_to_projects"
    static let promptNote = "Use delegate_to_projects for cheap bulk work (drafting, summarising, formatting, extraction, checklists and rewriting), saving your own model for judgment. Supply explicit instructions and all input text; Projects has no access to this conversation, files or web. Review its returned text before using it. At most three delegations per assignment, 120 seconds each."
    static let schema: [String: Any] = ["type": "object", "properties": [
        "subtask": ["type": "string", "description": "Short title for the board"],
        "instructions": ["type": "string", "description": "Explicit task and required output format"],
        "input_text": ["type": "string", "description": "All source text needed to do the task"]
    ], "required": ["subtask", "instructions", "input_text"], "additionalProperties": false]
    static var anthropic: [String: Any] { ["name": name, "description": promptNote, "input_schema": schema] }
    static var function: [String: Any] { ["type": "function", "function": ["name": name, "description": promptNote, "parameters": schema]] }
    static var responsesFunction: [String: Any] { ["type": "function", "name": name, "description": promptNote, "parameters": schema] }
    private(set) var count = 0
    typealias Chat = (String, @escaping (String?) -> Void) -> (() -> Void)
    private let chat: Chat
    private let timeout: TimeInterval
    init(timeout: TimeInterval = 120, chat: Chat? = nil) {
        self.timeout = timeout
        self.chat = chat ?? { prompt, done in
            let task = TokenMeter.charge("projects") {
                OllamaClient.chat(prompt, model: "qwen3.5:latest", system: "You are the Director of Projects helping another director. Follow the explicit instructions using only the supplied input. Return the requested work, not a project plan unless asked. Do not invent facts or claim external actions.", host: OllamaClient.defaultServer, completion: done)
            }
            return { task.cancel() }
        }
    }
    static func payload(_ input: [String: Any]) -> (title: String, prompt: String)? {
        guard let title = input["subtask"] as? String, let instructions = input["instructions"] as? String,
              let source = input["input_text"] as? String,
              [title, instructions, source].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), title.count <= 160 else { return nil }
        let prompt = "Instructions:\n" + instructions + "\n\nInput text:\n" + source
        return (title, prompt)
    }
    func run(_ input: [String: Any], isCancelled: @escaping () -> Bool, event: @escaping (String, String) -> Void, completion: @escaping (String) -> Void) {
        guard !isCancelled() else { completion("Projects delegation cancelled."); return }
        guard let payload = Self.payload(input) else { completion("Projects requires a subtask title (up to 160 characters), explicit instructions and nonempty input_text, Use numbered prompt parts of up to 50,000 characters. Longer work is retained; use scoped passes and integrate results within the model context and tool-call budget."); return }
        guard count < 3 else { completion("Projects delegation limit reached (3 per assignment). Finish with the results already returned."); return }
        count += 1
        event("handoff", payload.title)
        var finished = false
        var cancel: (() -> Void)?
        var timer: DispatchSourceTimer?
        func finish(_ text: String?, failure: String) {
            guard !finished else { return }
            finished = true
            timer?.cancel(); timer = nil
            event(text == nil ? "failed" : "done", payload.title)
            completion(text ?? failure)
        }
        cancel = chat(payload.prompt) { text in
            if isCancelled() { finish(nil, failure: "Projects delegation cancelled.") }
            else { finish(text, failure: "Projects returned no answer from qwen3.5 on DARK.") }
        }
        guard !finished else { return }
        let deadline = Date().addingTimeInterval(timeout)
        let watchdog = DispatchSource.makeTimerSource(queue: .main)
        timer = watchdog
        watchdog.schedule(deadline: .now(), repeating: 0.1)
        watchdog.setEventHandler {
            if isCancelled() || Date() >= deadline {
                cancel?()
                finish(nil, failure: isCancelled() ? "Projects delegation cancelled." : "Projects delegation timed out after 120 seconds.")
            }
        }
        watchdog.resume()
    }
}
