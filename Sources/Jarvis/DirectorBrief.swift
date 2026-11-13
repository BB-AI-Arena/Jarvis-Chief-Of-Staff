import Foundation

/// The execution contract supplements, but never replaces, the owner's complete instructions.
enum DirectorBrief {
    static func make(role: String, instructions: String) -> String {
        let access: String
        switch role {
        case "technology": access = "Workspace file tools read the configured Mac workspace. run_on_dark executes on the separate Linux DARK machine: it cannot read this Mac's ~/Library/Application Support/Jarvis or macOS logs. Use the supplied live board evidence for ledger state, and Mac file tools only where permitted; report an unavailable path rather than searching the wrong machine."
        case "research": access = "Use the source packet and actual configured research tools. The owner's requirements and supplied product records are authoritative inputs to a concept review. Distinguish observed facts from future requirements. Do not replace an actual requested review with an intention to research."
        case "creative": access = "Your Cursor workspace is a cloud checkout; it is not Brandon's Mac or DARK. Use the complete supplied brief, script and Research packet. Do not claim to have read Mac-only files unless they were supplied or an actual tool retrieved them."
        case "projects": access = "Your configured model has finite local context and no implied web or Mac file access. Use supplied evidence and configured tools. Split work into scoped parts when needed."
        default: access = "Operate only in the explicitly authorized workspace and tool scope. Source edits, a successful build and an installed/loaded change are different completion states. Do not claim the running app changed unless installation/application was verified."
        }
        return """
        ASSIGNMENT CONTRACT — \(role)
        Objective: satisfy the complete owner instructions below. Preserve every requirement, approved decision and supplied source; a short title is only a label.
        \(access)
        Plan dependent work in numbered scoped passes as needed. Consult the other director when this workflow requires it, carry concrete findings forward and integrate the final result. Do not invent consensus, missing facts or verification. Existing budgets and approval gates still apply.
        Deliver a completed answer or artifact with concrete findings, supporting evidence, what was actually checked and any remaining blocker. A progress update is not the final deliverable. Follow any explicit output schema in the instructions exactly. If blocked, identify the specific missing tool, source or provider error rather than reporting a vague success or guessing.

        COMPLETE OWNER/WORKFLOW INSTRUCTIONS:
        \(PromptDelivery.envelope(instructions))
        """
    }
}
