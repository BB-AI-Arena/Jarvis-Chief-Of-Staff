# Film story consultation

Jarvis owns the durable consultation checkpoint in its private Application Support `film-story.json`. It dispatches writing-only jobs to the configured Research and Creative seats through the normal task ledger. Every handoff uses the full brief and saved result, rather than the ledger's truncated summary. Consultation jobs cannot enter the native video path.

Research advises; Creative writes; Research reviews; Creative explicitly confirms the unchanged screenplay. Up to six completed review rounds are allowed before an unresolved disagreement is reported. Research must return a complete StoryReview JSON judgment bound to the exact screenplay hash; Creative must return its actual acceptance confirmation. Progress notes, stale hashes and contradictory accept-with-blockers responses are not valid reviews. Invalid deliveries receive bounded re-prompts without consuming creative revision rounds. A missing runtime or failed seat blocks progress visibly. Review-delivery failures are reported separately from genuine concrete disagreement.

The agreed screenplay and consultation record appear in Results. Its task offers approval and revision controls. Approval requires opening the current result, the current screenplay SHA-256, a valid explicit runtime, and the awaiting-approval phase. The saved owner authorization precedes production queueing. Repeated clicks, changed scripts, and stale hashes are rejected. Revisions reset approval and return to consultation. The render receives the approved screenplay as its full brief and instructions to preserve its story commitments.

This gate authorizes production; it does not certify the resulting film's creative fidelity. Whole-film continuity, product claims, anatomy and readable text still require review of the produced edit. Existing render limitations and media-quality checks remain applicable.

Tests: `tests/film_story/main.swift`, included in `scripts/check.sh`. The production build and normal JavaScript/native checks also apply. Do not commit runtime briefs, credentials or private consultation checkpoints.
