import Foundation

extension JarvisApp {
    var filmStoryURL: URL { support.appendingPathComponent("film-story.json") }
    func loadFilmStory() -> FilmStory? {
        guard let data = try? Data(contentsOf:filmStoryURL) else { return nil }
        return try? JSONDecoder().decode(FilmStory.self,from:data)
    }
    @discardableResult func saveFilmStory(_ story: FilmStory) -> Bool {
        do { try JSONEncoder().encode(story).write(to:filmStoryURL,options:.atomic);return true }
        catch { send("notice","Could not save story workflow: " + error.localizedDescription);return false }
    }
    func storyTask(_ prompt: String, seat: String) -> String {
        let id = UUID().uuidString,now = TaskLedger.timestamp()
        var records = ledger.load()
        records.insert(TaskRecord(id:id,state:"proposed",verified:false,owner:seat,createdAt:now,updatedAt:now,resultSummary:TaskLedger.queued,title:"[Story consultation] " + directorTitle(seat),brief:prompt),at:0)
        // Dispatch only after the workflow checkpoint has recorded this task id.
        publishTasks(records)
        return id
    }
    func refreshFilmStory() {
        guard var story = loadFilmStory() else { return }
        if story.phase == "rendering",let task = ledger.load().first(where:{$0.id == story.taskID}) {
            if ["failed","cancelled","completed"].contains(task.state) {
                story.phase = task.state == "completed" ? "completed" : "production_needs_attention"
                story.feedback = task.resultSummary
                _ = saveFilmStory(story)
            }
            return
        }
        guard !["awaiting_approval","approved","rendering","needs_attention","production_needs_attention","completed","cancelled"].contains(story.phase) else { return }
        func assign(_ phase: String, seat: String, prompt: String) {
            story.phase = phase
            story.taskID = storyTask(prompt,seat:seat)
            if saveFilmStory(story) { dispatch(seat) }
        }
        let rules = (story.ownerRevisionFeedback.map { "LATEST OWNER REVISION DIRECTION (apply alongside the original brief; resolve older conflicts in favor of the latest owner instruction):\n" + $0 + "\n" } ?? "") + (story.sourceEvidence.map { "CURRENT LOCAL SOURCE EVIDENCE (requirements are not automatically shipped):\n" + $0 + "\n" } ?? "") + """
        Handoff integrity: you are receiving the complete saved deliverable, not the task-list summary. Review it through its final line. Prior research critiques are advisory and may contain mistakes; verify them against the OWNER BRIEF rather than adopting them as new requirements. The member-owned target, offer, acceptance and reciprocal contact-sharing sequence is already required; do not ask Brandon whether to include it. Do not invent a latency threshold for the earlier failed alert. A collector scans an item he already owns; it can be a different item from the chase he is hunting. Never require him to already own the missing target. Do not invent collectible names, edition sizes, MSRP, market values or coverage percentages as verified facts. Use verified references or explicitly labeled production placeholders.
        This is a writing-only consultation between Jarvis's Creative Director and Director of Research. Do not render, generate assets, launch production, modify code or publish anything. Brandon must approve the exact final screenplay first. Return the complete deliverable in your final reply, not only a link or a summary. Keep it below 24,000 characters. The user brief is authoritative product direction; separate upcoming concepts from released and measured claims. Never invent delivery latency measurements or general accusations about competitors. A fictional character may experience a late alert. Preserve the user's intended value proposition. Any readable screens/signs must later use captured or explicitly typeset text, never generated gibberish. Maintain one young ADULT protagonist, coherent causal scenes, exact collectible identity, natural anatomy and consistent ownership. No budgets or APIs may be changed.\n
        """
        if story.phase == "new" {
            assign("research",seat:"research",prompt:rules + "Research the product and advise Creative on factual boundaries and story opportunities. Identify evidence versus owner-supplied future requirements. Consult the connected project information when available; label missing evidence. Do not research unrelated market news.\nOWNER BRIEF:\n" + story.brief)
            return
        }
        guard let task = ledger.load().first(where:{$0.id == story.taskID}) else { return }
        if ["failed","cancelled"].contains(task.state) {
            story.phase = "needs_attention";story.feedback = task.resultSummary;_ = saveFilmStory(story)
            updateTask(story.id,state:task.state,summary:"Story consultation needs attention. " + task.resultSummary)
            say("The story consultation needs attention. " + TaskLedger.headline(task.resultSummary));return
        }
        guard task.state == "completed",let file = resultFile(task.id),let raw = try? String(contentsOf:file,encoding:.utf8) else { return }
        let text = FilmStory.consultationText(raw)
        story.history.append(story.phase + "\n" + text)
        switch story.phase {
        case "research":
            story.research = text;story.round = 1
            assign("draft",seat:"creative",prompt:rules + "Consult Research's findings below and write a complete screenplay, not a feature list. Choose a suitable runtime (up to ten minutes supported by renderer); state the runtime explicitly. Begin with a standalone plain-text line RUNTIME_SECONDS: N (N is the full runtime in seconds, 15 through 600). Include character bible, scene transitions, visual action, dialogue/narration, exact UI copy, and how the next scene follows. End with any specific questions for Research.\nOWNER BRIEF:\n" + story.brief + "\nRESEARCH CONSULTATION:\n" + text)
        case "draft":
            story.script = FilmStory.screenplay(text);story.hash = FilmStory.digest(story.script)
            guard story.runtime != nil else {
                story.phase = "needs_attention";story.feedback = "Creative omitted a valid RUNTIME_SECONDS line. The story remains unapproved.";_ = saveFilmStory(story)
                say(story.feedback);return
            }
            assign("review",seat:"research",prompt:rules + StoryReview.contract + "\nSCREENPLAY SHA256: " + story.hash + "\nCreative has responded to your consultation with the screenplay below. Critique its product claims, continuity and causal story. Follow the final JSON review contract above. Accept only this unchanged version, or list concrete required corrections with evidence.\nOWNER BRIEF:\n" + story.brief + "\nYOUR PRIOR FINDINGS:\n" + story.research + "\nCREATIVE SCREENPLAY:\n" + story.script)
        case "review":
            guard let review = StoryReview.parse(text,hash:story.hash) else {
                story.reviewDeliveryFailures = (story.reviewDeliveryFailures ?? 0) + 1
                if (story.reviewDeliveryFailures ?? 0) <= 2 {
                    assign("review",seat:"research",prompt:rules + StoryReview.contract + "\nThe last return was not a complete version-bound judgment. Finish the actual review; do not send a progress note.\nSCREENPLAY SHA256: " + story.hash + "\nOWNER BRIEF:\n" + story.brief + "\nSOURCE EVIDENCE:\n" + story.research + "\nCOMPLETE SCREENPLAY:\n" + story.script)
                } else {
                    story.phase = "needs_attention";story.feedback = "Research did not return a complete review of the current script. This is a review-delivery failure, not director disagreement.";_ = saveFilmStory(story);say(story.feedback)
                }
                return
            }
            story.reviewDeliveryFailures = 0
            story.feedback = review.report
            if review.decision == "accept" {
                assign("confirm",seat:"creative",prompt:rules + "Research has accepted your exact screenplay. Read its response and confirm you also accept that screenplay unchanged by returning a standalone line CREATIVE_ACCEPTS_STORY. If you disagree, state why and do not emit that line. Do not rewrite the script during confirmation.\nSCREENPLAY:\n" + story.script + "\nRESEARCH RESPONSE:\n" + review.report)
            } else if story.round < 6 {
                story.round += 1
                assign("draft",seat:"creative",prompt:rules + "Consult Research's concrete findings and revise the same complete screenplay. Close each listed correction explicitly; preserve resolved decisions and the owner vision. Return the full polished screenplay, not patches or another plan. Include a short correction-to-resolution record after the screenplay.\nOWNER BRIEF:\n" + story.brief + "\nPREVIOUS SCREENPLAY:\n" + story.script + "\nRESEARCH CRITIQUE:\n" + review.report)
            } else {
                story.phase = "needs_attention";_ = saveFilmStory(story)
                say("The directors still have specific unresolved changes after six completed reviews. " + TaskLedger.headline(review.report) + " The detailed findings are saved; no film production has started.")
            }
        case "confirm":
            guard text.components(separatedBy:.newlines).contains("CREATIVE_ACCEPTS_STORY") else {
                if story.round < 6 {
                    story.round += 1
                    assign("draft",seat:"creative",prompt:rules + "Research accepted the previous screenplay, but your confirmation raised a concern. Resolve it by returning the entire revised screenplay, with a short list of exactly what changed and why. Research will review this version. Do not restart or change resolved owner requirements.\nOWNER BRIEF:\n" + story.brief + "\nCURRENT SCREENPLAY:\n" + story.script + "\nRESEARCH FINDINGS:\n" + story.feedback + "\nYOUR CONCERN:\n" + text)
                } else {
                    story.phase = "needs_attention";story.feedback = text;_ = saveFilmStory(story)
                    say("Creative still has a concrete concern after six completed review rounds. " + TaskLedger.headline(text) + " The full screenplay and findings are saved; no production has started.")
                }
                return
            }
            story.phase = "awaiting_approval";story.taskID = story.id
            guard saveFilmStory(story) else { return }
            presentReviewedStory(story,open:true)
        default: break
        }
    }
    func presentReviewedStory(_ story: FilmStory, open: Bool) {
        saveResult(story.id,title:"Film storyline for your approval",director:"Jarvis · Creative and Research",text:story.script + "\n\nCONSULTATION RECORD\n\n" + story.history.joined(separator:"\n\n"))
        var records = ledger.load();let now = TaskLedger.timestamp()
        let approval = TaskRecord(id:story.id,state:"proposed",verified:false,owner:"creative",createdAt:now,updatedAt:now,resultSummary:"Creative and Research agree. Open the screenplay, then approve this exact story or request revisions. Approval starts film production from that exact screenplay.",title:"Film storyline — awaiting your approval")
        if let i = records.firstIndex(where:{$0.id == story.id}) { records[i] = approval } else { records.insert(approval,at:0) }
        publishTasks(records)
        if open { showWorkspace();openResult(story.id) }
        say("Creative and Research have agreed on a storyline. I've put the full screenplay in Results. Please review it; I will start production only if you approve it.")
    }
    /// Adopt completed, exact-version director reviews; this never authorizes production.
    @discardableResult func adoptReviewedStory(_ request: ReviewedStoryAdoption) -> Bool {
        guard UUID(uuidString:request.id) != nil,var story = loadFilmStory(), story.id == request.storyID,story.hash == request.previousHash,
              ["needs_attention","production_needs_attention","completed","awaiting_approval"].contains(story.phase),
              FilmStory.digest(request.script) == request.scriptHash else { return false }
        var candidate = story;candidate.script = request.script
        guard candidate.runtime != nil else { return false }
        let records = ledger.load()
        guard !records.contains(where:{$0.state == "running"}),
              let research = records.first(where:{$0.id == request.researchTaskID && $0.owner == "research" && $0.state == "completed"}),
              let creative = records.first(where:{$0.id == request.creativeTaskID && $0.owner == "creative" && $0.state == "completed"}),
              research.instructions.contains(request.script),research.instructions.contains(request.scriptHash),
              creative.instructions.contains(request.script),creative.instructions.contains(request.scriptHash),
              let researchFile = resultFile(research.id),let creativeFile = resultFile(creative.id),
              let researchRaw = try? String(contentsOf:researchFile,encoding:.utf8),
              let creativeRaw = try? String(contentsOf:creativeFile,encoding:.utf8),
              let review = StoryReview.parse(FilmStory.consultationText(researchRaw),hash:request.scriptHash),review.decision == "accept" else { return false }
        let creativeBody = creativeRaw.range(of:"\n---\n\n").map { String(creativeRaw[$0.upperBound...]) } ?? creativeRaw
        let lines = FilmStory.consultationText(creativeBody).components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty}
        guard lines == ["CREATIVE_ACCEPTS_STORY","SCREENPLAY_SHA256: " + request.scriptHash] else { return false }
        let archive = support.appendingPathComponent("reviewed-story-history/" + request.id)
        do {
            try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true)
            try JSONEncoder().encode(story).write(to:archive.appendingPathComponent("previous-story.json"),options:.atomic)
            try JSONEncoder().encode(request).write(to:archive.appendingPathComponent("request.json"),options:.atomic)
            try Data(researchRaw.utf8).write(to:archive.appendingPathComponent("research-result.md"),options:.atomic)
            try Data(creativeRaw.utf8).write(to:archive.appendingPathComponent("creative-result.md"),options:.atomic)
        } catch { return false }
        if !story.approvedHash.isEmpty { story.history.append("Historical approval: " + story.approvedHash + " at " + story.approvedAt) }
        story.history.append("Completed full-version Research " + research.id + "\n" + researchRaw)
        story.history.append("Completed full-version Creative " + creative.id + "\n" + creativeRaw)
        story.script = request.script;story.hash = request.scriptHash;story.phase = "awaiting_approval";story.taskID = story.id
        story.viewedHash = "";story.approvedHash = "";story.approvedAt = "";story.feedback = review.report
        guard saveFilmStory(story) else { return false }
        presentReviewedStory(story,open:false)
        return true
    }
    /// Resume one durable consultation instead of spawning disconnected rewrites on every repeated request.
    func resumeSavedFilmStory() -> String {
        guard var story = loadFilmStory() else { return "There is no saved film consultation yet." }
        if story.phase == "awaiting_approval" { openResult(story.id);return "The directors' agreed screenplay is saved in Results and awaiting your approval. Production has not started." }
        if story.phase == "production_needs_attention" { return "Your exact screenplay approval is retained. Production needs attention: " + story.feedback }
        if story.phase == "completed" { return "The approved film task has completed. Its saved result is in Results; completion alone does not certify creative quality." }
        if ["approved","rendering"].contains(story.phase) { return "The approved screenplay is already assigned for production. I will report its recorded status." }
        if ["research","draft","review","confirm"].contains(story.phase),let current = ledger.load().first(where:{$0.id == story.taskID}),["running","proposed"].contains(current.state) {
            return "I have your complete saved brief and latest screenplay. The existing consultation is still " + story.phase + "; I have not started a duplicate writing job."
        }
        guard story.approvedHash.isEmpty,!story.script.isEmpty else { return "The saved consultation needs its original draft or approval state resolved before it can resume." }
        story.script = FilmStory.screenplay(story.script);story.hash = FilmStory.digest(story.script)
        story.history.append("Owner resumed the saved consultation. Previous progress-only returns do not establish a completed review or a disagreement. Full original brief and current screenplay retained.")
        story.round = 1;story.reviewDeliveryFailures = 0;story.viewedHash = ""
        story.taskID = storyTask(StoryReview.contract + "\nReview the complete saved screenplay now. Research progress notes from earlier failed deliveries are not findings. Use the supplied owner brief and evidence, preserve the full concept vision and identify only concrete unresolved issues. Do not generate film assets.\nSCREENPLAY SHA256: " + story.hash + "\nOWNER BRIEF:\n" + story.brief + "\nSOURCE EVIDENCE:\n" + story.research + "\nCURRENT LOCAL SOURCE DOCUMENTS:\n" + (story.sourceEvidence ?? "No added local source packet.") + "\nCOMPLETE CURRENT SCREENPLAY:\n" + story.script,seat:"research")
        story.phase = "review";story.feedback = "A complete version-bound Research review is pending; no director disagreement has been established by the earlier progress notes."
        guard saveFilmStory(story) else { return "The consultation could not be saved; no duplicate job was started." }
        dispatch("research")
        return "I still have your complete original brief and current screenplay. I have resumed Research's full review with Grok 4.7; Creative will address its concrete findings before I bring the agreed version to you."
    }
    func isApprovedFilmRequest(_ text: String) -> Bool {
        guard let story = loadFilmStory(),["approved","production_needs_attention"].contains(story.phase) else { return false }
        let lower = text.lowercased()
        return ["make the movie","make the film","render the film","produce the film","film from the approved","video from the approved"].contains { lower.contains($0) }
    }
    func isSavedStoryRequest(_ text: String) -> Bool {
        guard loadFilmStory() != nil else { return false }
        let lower = text.lowercased()
        let specific = ["my script","the script","my screenplay","the screenplay","story consultation","my storyline"].contains { lower.contains($0) }
        let action = ["generate","finish","resume","continue","write","send","approval"].contains { lower.contains($0) }
        return specific && action && !["another unrelated","separate new film"].contains { lower.contains($0) }
    }
    /// Record a direct owner-chat approval without claiming a UI view or launching production.
    @discardableResult func recordExternalStoryApproval(_ request: ExternalStoryApproval) -> Bool {
        guard UUID(uuidString:request.id) != nil,UUID(uuidString:request.sourceChatID) != nil,
              FilmStory.isExplicitApproval(request.ownerText),var story = loadFilmStory(),story.phase == "awaiting_approval",
              story.runtime != nil,story.hash == request.scriptHash,FilmStory.digest(story.script) == request.scriptHash else { return false }
        let archive = support.appendingPathComponent("external-story-approvals/" + request.id)
        do {
            try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true)
            try JSONEncoder().encode(story).write(to:archive.appendingPathComponent("previous-story.json"),options:.atomic)
            try JSONEncoder().encode(request).write(to:archive.appendingPathComponent("owner-chat-attestation.json"),options:.atomic)
        } catch { return false }
        story.phase = "approved";story.approvedHash = request.scriptHash;story.approvedAt = TaskLedger.timestamp()
        story.history.append("Owner chat approval recorded at " + story.approvedAt + " from chat " + request.sourceChatID + ": " + request.ownerText + "\nExact screenplay: " + request.scriptHash + "\nNo UI view was asserted. Complete animatic and quality checks precede full rendering.")
        guard saveFilmStory(story) else { return false }
        updateTask(story.id,state:"completed",summary:"Owner approved the exact screenplay through chat; complete animatic and quality checks are required before full rendering.")
        return true
    }
    @discardableResult func approveFilmStory(_ id: String, hash: String, announce: Bool = true) -> String {
        guard var story = loadFilmStory(),story.id == id,story.canApprove(hash) else {
            let message = "Open and review the current screenplay before approving it. Approval must match its saved version."
            if announce { send("notice",message) };return message
        }
        // Persist authorization before queuing any rendering work. Repeated clicks cannot launch duplicates.
        story.phase = "approved";story.approvedHash = hash;story.approvedAt = TaskLedger.timestamp()
        guard saveFilmStory(story) else { return "The screenplay approval could not be saved. No rendering was started." }
        let outcome = createApprovedFilm()
        if announce { say(outcome) };return outcome
    }
    func createApprovedFilm() -> String {
        guard var story = loadFilmStory(),["approved","production_needs_attention"].contains(story.phase),!story.approvedHash.isEmpty,story.approvedHash == story.hash,story.hash == FilmStory.digest(story.script) else { return "Film production requires your approval of the exact agreed screenplay first." }
        guard SpendBudget.allowsBudgetedFilm else {
            story.feedback = "Your approval is saved for this exact screenplay. " + SpendBudget.blocked
            _ = saveFilmStory(story)
            updateTask(story.id,state:"proposed",summary:story.feedback)
            return story.feedback
        }
        let hash = story.hash,id = story.id
        let brief = "Create a \(story.runtime!) second film from Brandon's APPROVED SCREENPLAY below. Follow its plot, dialogue, narration, cast, collectible ownership, claims and scene order exactly. Do not invent another story or alter these commitments. Source clips may be subdivided for rendering while preserving the approved actions. Use approved Drop Assassin artwork and exact character references. Render video only with local models on DARK RTX 4090; never call a frontier/cloud video generator or use a cloud video fallback. Stop and report if DARK is unavailable. Use captured or typeset readable UI/text; never synthesize lettering. Do not silently simplify approved essential actions. If the approved screenplay cannot be produced faithfully, report the blocker before substituting scenes.\nAPPROVED SHA256: " + hash + "\n\n" + story.script
        let task = storyTask(brief,seat:"creative")
        // Rendering intentionally uses a different title from writing-only consultations.
        var records = ledger.load()
        if let i = records.firstIndex(where:{$0.id == task}) { records[i].title = "Create the approved Drop Assassin film" }
        if let i = records.firstIndex(where:{$0.id == id}) { records[i].state = "completed";records[i].resultSummary = "Owner approved screenplay " + hash }
        publishTasks(records)
        story.phase = "rendering";story.taskID = task
        guard saveFilmStory(story) else { return "The production assignment could not be saved; no render was dispatched." }
        dispatch("creative")
        return "I have assigned the approved screenplay to Creative for film production."
    }
    func canReviseFilmStory(_ story: FilmStory) -> Bool {
        if ["awaiting_approval","production_needs_attention","completed"].contains(story.phase) { return true }
        guard story.phase == "needs_attention", let task = ledger.load().first(where:{$0.id == story.taskID}) else { return false }
        return task.state == "failed" && task.owner == "creative" && task.title.hasPrefix("[Story consultation]")
    }
    func reviseFilmStory(_ id: String, feedback: String) {
        guard var story = loadFilmStory(),story.id == id,canReviseFilmStory(story),!feedback.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        if !story.approvedHash.isEmpty {
            story.history.append("Historical production approval: " + story.approvedHash + " at " + story.approvedAt + ". Owner requested a new revision; this authorization does not apply to the replacement.")
        }
        story.ownerRevisionFeedback = feedback
        story.feedback = feedback;story.round = 1;story.viewedHash = "";story.approvedHash = "";story.approvedAt = ""
        story.history.append("Owner requested revisions: " + feedback)
        story.taskID = storyTask("Writing only: revise the complete screenplay below in consultation with Research. Do not generate assets, render, publish, modify code, or start production. Return the full revised screenplay under 24,000 characters. Begin with a standalone plain-text line RUNTIME_SECONDS: N (full runtime in seconds, 15 through 600). Preserve the owner brief and apply the requested changes. Research will review your revision before it returns to Brandon.\nOWNER BRIEF:\n" + story.brief + "\nOWNER FEEDBACK:\n" + feedback + "\nCURRENT SCREENPLAY:\n" + story.script,seat:"creative")
        story.phase = "draft"
        guard saveFilmStory(story) else { return }
        updateTask(id,state:"running",summary:"Owner requested revisions; Creative and Research are consulting again.")
        dispatch("creative")
    }

    /// Poll a user-owned local inbox, independent of WebKit readiness or screen lock.
    func consumeStoryRevisionRequests() {
        let approvalInbox = support.appendingPathComponent("external-story-approval-inbox")
        for file in (try? FileManager.default.contentsOfDirectory(at:approvalInbox,includingPropertiesForKeys:nil)) ?? [] {
            guard file.pathExtension == "json",let data = try? Data(contentsOf:file),let request = try? JSONDecoder().decode(ExternalStoryApproval.self,from:data) else { continue }
            if recordExternalStoryApproval(request) { try? FileManager.default.removeItem(at:file) }
        }
        let adoptionInbox = support.appendingPathComponent("reviewed-story-inbox")
        for file in (try? FileManager.default.contentsOfDirectory(at:adoptionInbox,includingPropertiesForKeys:nil)) ?? [] {
            guard file.pathExtension == "json",let data = try? Data(contentsOf:file),let request = try? JSONDecoder().decode(ReviewedStoryAdoption.self,from:data) else { continue }
            if adoptReviewedStory(request) { try? FileManager.default.removeItem(at:file) }
        }
        let inbox = support.appendingPathComponent("story-revision-inbox")
        let files = (try? FileManager.default.contentsOfDirectory(at:inbox,includingPropertiesForKeys:nil)) ?? []
        for file in files.filter({$0.pathExtension == "json"}).sorted(by:{$0.lastPathComponent < $1.lastPathComponent}) {
            guard let data = try? Data(contentsOf:file),let request = try? JSONDecoder().decode(StoryRevisionRequest.self,from:data),
                  UUID(uuidString:request.id) != nil,let story = loadFilmStory(),story.id == request.storyID,story.hash == request.expectedHash,
                  (request.writingSeat == nil ? canReviseFilmStory(story) : (["creative","research"].contains(request.writingSeat!) && ["needs_attention","awaiting_approval","completed","production_needs_attention"].contains(story.phase))),
                  !request.feedback.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { continue }
            let archive = support.appendingPathComponent("story-revision-history/" + request.id)
            do {
                try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true)
                try JSONEncoder().encode(story).write(to:archive.appendingPathComponent("previous-story.json"),options:.atomic)
                try FileManager.default.moveItem(at:file,to:archive.appendingPathComponent("request.json"))
            } catch { continue }
            if let seat = request.writingSeat {
                let taskID = storyTask("[STORY SPINE WORKSHOP] Writing-only independent consultation. Return ONLY the requested story architecture or critique, not a screenplay. No assets, code changes, rendering, publishing, or owner approval. Do not call this screenplay consensus.\n" + request.feedback,seat:seat)
                try? Data(taskID.utf8).write(to:archive.appendingPathComponent("task-id.txt"),options:.atomic)
                dispatch(seat)
                continue
            }
            reviseFilmStory(story.id,feedback:request.feedback)
            let accepted = loadFilmStory()?.phase == "draft"
            try? Data((accepted ? "Writing-only revision queued" : "Revision not queued; inspect saved workflow").utf8).write(to:archive.appendingPathComponent("status.txt"),options:.atomic)
        }
    }

}
