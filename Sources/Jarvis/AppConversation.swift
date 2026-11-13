import AppKit
import WebKit
import AVFoundation
import Speech

extension JarvisApp {
    /// Bind a short, explicit approval to live state without a model inventing a hash.
    func explicitStoryApproval(_ prompt: String) -> RouteDecision? {
        guard FilmStory.isExplicitApproval(prompt),let story = loadFilmStory(),story.phase == "awaiting_approval" else { return nil }
        return RouteDecision(route:"approve_story",text:"",director:nil,task:story.hash)
    }
    /// Typed requests. With Astra selected in Settings the request goes straight to deep reasoning; otherwise it is routed.
    func chat(_ prompt: String, history: String, deep: Bool = false) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        send("state", "thinking")
        if let approval = explicitStoryApproval(prompt) { act(on:approval,prompt:prompt,history:history,liveUpdate:nil);return }
        if deep { deepReason(prompt, history: history, liveUpdate: nil); return }
        routeRequest(prompt, history: history) { [weak self] decision in
            self?.act(on: decision, prompt: prompt, history: history, liveUpdate: nil)
        }
    }
    /// Routing: the fast Claude router first, Luna second. Nil only when neither answered.
    func routeRequest(_ prompt: String, history: String, evidence: String = "", lookupRemaining: Int = 4, completion: @escaping (RouteDecision?) -> Void) {
        if let approval = explicitStoryApproval(prompt) { completion(approval);return }
        let boardEvidence = SharedWorkspaceContext.needsEvidence(prompt) ? DirectorResultsContext(workspace:workspace,records:ledger.load()).context(for:prompt) + "\n\n" + SharedWorkspaceContext(root:workspace,support:support).context(for:prompt,history:history) : ""
        let context = memory.context() + "\n\n" + boardEvidence + "\n\n" + evidence
        let deliver: (RouteDecision?) -> Void = { [weak self] decision in
            guard let self else { return }
            guard decision?.route == "lookup" else { completion(decision);return }
            guard lookupRemaining > 0 else { completion(RouteDecision(route:"reply",text:"I reached this turn's workspace lookup limit. I have not reviewed any remaining parts; please narrow the result or question.",director:nil));return }
            let found = SharedWorkspaceContext(root:self.workspace,support:self.support).lookup(decision?.task ?? "")
            self.routeRequest(prompt,history:history,evidence:evidence + "\n\n" + found,lookupRemaining:lookupRemaining-1,completion:completion)
        }
        let luna = { [weak self] in
            guard let self, !self.brain.busy, AgentRuntime.executable != nil else { deliver(nil);return }
            self.send("notice","Luna is routing this request…")
            self.brain.ask(prompt,history:history,context:context,deep:false) { [weak self] text,route,director,error in
                guard let self,error == nil,let text else { deliver(nil);return }
                deliver(RouteDecision(route:route ?? "reply",text:text,director:director,task:self.brain.lastSuggestion))
            }
        }
        guard claudeConnected,let apiKey = ClaudeCredential.read() else { luna();return }
        JarvisRouter.route(prompt,history:history,apiKey:apiKey,persona:Personas.text("jarvis") ?? "",memory:context) { decision in
            if let decision { deliver(decision) } else { luna() }
        }
    }
    /// Carries out a routing decision. What Jarvis says goes back through the voice delegation, or as a typed reply.
    func act(on decision: RouteDecision?, prompt: String, history: String, liveUpdate: ((String) -> Void)?) {
        guard let decision else { acknowledge(recordUnrouted(prompt), liveUpdate); return }
        if decision.route == "approve_story" {
            guard FilmStory.isExplicitApproval(prompt),let story = loadFilmStory(),let hash = decision.task else {
                acknowledge("No screenplay approval was recorded. Approval needs an explicit statement for the current reviewed screenplay.",liveUpdate);return
            }
            acknowledge(approveFilmStory(story.id,hash:hash,announce:false),liveUpdate);return
        }
        if decision.route == "astra" { deepReason(decision.text, history: history + "\n\nUser: " + prompt, liveUpdate: liveUpdate); return }
        if let topic = RouteDecision.debateTopic(for: decision) { acknowledge(startDebate(topic, liveUpdate: liveUpdate).message, liveUpdate); return }
        if let fact = RouteDecision.memory(for: decision) {
            memory.append(kind: "Brandon", text: fact)
            acknowledge("Noted. I'll keep that in the board's memory: " + fact, liveUpdate)
            return
        }
        if let suggestion = RouteDecision.suggestion(for: decision) {
            suggestTask(suggestion.title, director: suggestion.director)
            acknowledge(decision.text + (liveUpdate == nil ? "" : " (This is only a suggestion. Nothing has been added to the task list unless the user approves.)"), liveUpdate)
            return
        }
        if let assignment = RouteDecision.assignment(for: decision) {
            // The director gets real work, never Jarvis's spoken line. If the router only acknowledged, the request is kept for Brandon to place.
            guard let work = RouteDecision.work(for: decision, prompt: prompt) else { acknowledge(recordUnrouted(prompt), liveUpdate); return }
            let fullWork = RouteDecision.completeWork(work,original:prompt)
            delegateWork(fullWork, director: RouteDecision.classify(work, hinted: assignment.director), liveUpdate: liveUpdate)
            return
        }
        acknowledge(decision.text, liveUpdate)
    }
    /// Substantial reasoning goes to Astra through the agent runtime.
    func deepReason(_ prompt: String, history: String, liveUpdate: ((String) -> Void)?) {
        guard !brain.busy, AgentRuntime.executable != nil else { acknowledge("Astra is busy with another request, so I haven't started that one. Ask me again in a moment.", liveUpdate); return }
        send("notice", "Astra is reasoning in the background…")
        let context = memory.context() + "\n\n" + DirectorResultsContext(workspace: workspace, records: ledger.load()).context(for: prompt) + "\n\n" + SharedWorkspaceContext(root: workspace,support: support).context(for: prompt, history: history)
        brain.ask(prompt, history: history, context: context, deep: true) { [weak self] text, _, _, error in
            guard let self = self else { return }
            if let text, error == nil, !text.isEmpty {
                if let update = liveUpdate { update(text) } else { self.send("reply", ["text": text, "model": "GPT Astra"]); self.send("state", "idle") }
            } else { self.acknowledge("Astra could not finish that reasoning request. Nothing was changed.", liveUpdate) }
        }
    }
    var resultsDirectory: URL { workspace.appendingPathComponent("Results") }
    /// Result documents are named "<date> <title> <first 8 of the task id>.md" so they read well in Finder and can be found by task.
}
