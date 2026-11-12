import Foundation

/// Eleven realistic requests that must route correctly before a push. `Jarvis --acceptance` sends each through the live router.
enum Acceptance {
    struct Case {
        let prompt: String
        let history: String
        /// Acceptable routes; "assign" also accepts "task".
        let routes: [String]
        /// Acceptable directors for an assignment (empty = any).
        let directors: [String]
    }
    static let cases: [Case] = [
        Case(prompt: "Add drafting the launch plan to the task list.", history: "", routes: ["assign"], directors: []),
        Case(prompt: "Research the top three competitors in handyman scheduling software.", history: "", routes: ["assign"], directors: ["research"]),
        Case(prompt: "Have the board debate whether we should ship the handyman app this week.", history: "", routes: ["debate"], directors: []),
        Case(prompt: "Good morning Jarvis, how are you today?", history: "", routes: ["reply"], directors: []),
        Case(prompt: "Do an engineering review of how the task ledger saves its records.", history: "", routes: ["assign"], directors: ["technology"]),
        Case(prompt: "Design a logo and a name for the handyman app.", history: "", routes: ["assign"], directors: ["creative"]),
        Case(prompt: "Build me a project plan with milestones and dates for the handyman MVP.", history: "", routes: ["assign"], directors: ["projects"]),
        Case(prompt: "Remember that our first target customer is solo handymen.", history: "", routes: ["remember"], directors: []),
        Case(prompt: "I've been going back and forth on pricing lately.", history: "", routes: ["reply", "suggest"], directors: []),
        Case(prompt: "Create a 30 second cinematic video about Drop Assassin in HD with heavy special effects.", history: "", routes: ["assign"], directors: ["creative"]),
        Case(prompt: "Fix your own UI so I can watch each director working when you hand off a task.", history: "", routes: ["assign", "task"], directors: ["operations"]),
        Case(prompt: "Yes, go ahead.", history: "assistant: Shall I add outlining a simple MVP for solo handymen to the task list for Projects?", routes: ["assign"], directors: [])
    ]
    /// Nil when the decision is acceptable, otherwise why it is not.
    static func problem(_ decision: RouteDecision?, for test: Case) -> String? {
        guard let decision else { return "no decision returned" }
        let route = decision.route == "task" ? "assign" : decision.route
        guard test.routes.contains(route) else { return "route \(decision.route), expected \(test.routes.joined(separator: " or "))" }
        if route == "assign" {
            guard let assignment = RouteDecision.assignment(for: decision) else { return "assignment has no usable director" }
            if !test.directors.isEmpty, !test.directors.contains(assignment.director) { return "director \(assignment.director), expected \(test.directors.joined(separator: " or "))" }
        }
        if route == "debate", RouteDecision.debateTopic(for: decision) == nil { return "debate has no question" }
        if route == "remember", RouteDecision.memory(for: decision) == nil { return "nothing to remember" }
        return nil
    }
    static func line(_ index: Int, _ test: Case, _ decision: RouteDecision?, ms: Int) -> String {
        let outcome = problem(decision, for: test)
        let where_ = decision.map { $0.route + ($0.director.map { " → " + $0 } ?? "") } ?? "nothing"
        return (outcome == nil ? "PASS " : "FAIL ") + String(format: "%2d", index + 1) + " “" + test.prompt.prefix(60) + "” · " + where_ + " · \(ms) ms" + (outcome.map { " · " + $0 } ?? "")
    }
    /// Runs the cases one after another through the fast router. Completion receives the number that failed.
    static func run(apiKey: String, persona: String, completion: @escaping (Int) -> Void) {
        var failed = 0
        func next(_ index: Int) {
            guard index < cases.count else { completion(failed); return }
            let test = cases[index], start = Date()
            JarvisRouter.route(test.prompt, history: test.history, apiKey: apiKey, persona: persona, memory: "") { decision in
                if problem(decision, for: test) != nil { failed += 1 }
                print(line(index, test, decision, ms: Int(Date().timeIntervalSince(start) * 1000)))
                next(index + 1)
            }
        }
        next(0)
    }
}
