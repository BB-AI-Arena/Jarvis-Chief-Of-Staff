# Film story consultation

Jarvis owns the durable consultation checkpoint in its private Application Support `film-story.json`. It dispatches writing-only jobs to the configured Research and Creative seats through the normal task ledger. Every handoff uses the full brief and saved result, rather than the ledger's truncated summary. Consultation jobs cannot enter the native video path.

Research advises; Creative writes; Research reviews; Creative explicitly confirms the unchanged screenplay. Up to six completed review rounds are allowed before an unresolved disagreement is reported. Research must return a complete StoryReview JSON judgment bound to the exact screenplay hash; Creative must return its actual acceptance confirmation. Progress notes, stale hashes and contradictory accept-with-blockers responses are not valid reviews. Invalid deliveries receive bounded re-prompts without consuming creative revision rounds. A missing runtime or failed seat blocks progress visibly. Review-delivery failures are reported separately from genuine concrete disagreement.

The agreed screenplay and consultation record appear in Results. Its task offers approval and revision controls. Approval requires opening the current result, the current screenplay SHA-256, a valid explicit runtime, and the awaiting-approval phase. The saved owner authorization precedes production queueing. Repeated clicks, changed scripts, and stale hashes are rejected. Revisions reset approval and return to consultation. The render receives the approved screenplay as its full brief and instructions to preserve its story commitments.

This gate authorizes production; it does not certify the resulting film's creative fidelity. Whole-film continuity, product claims, anatomy and readable text still require review of the produced edit. Existing render limitations and media-quality checks remain applicable.

Tests: `tests/film_story/main.swift`, included in `scripts/check.sh`. The production build and normal JavaScript/native checks also apply. Do not commit runtime briefs, credentials or private consultation checkpoints.

## Owner rendering policy and budget bridge (November 12, 2026)

Video generation is local-only on DARK's RTX 4090 (ComfyUI/LTX). Unavailability stops the job; cloud/frontier video generation is disabled at the legacy renderer entry point as well. Claude Opus 5.5 writes/directs and Grok 4.7 reviews the screenplay; these prose roles do not render video.

New film subprocesses send their paid Claude planning/review and optional xAI still-image repair calls through the installed app's `--film-provider-request` broker. It allowlists the exact provider paths and bounded payloads, reads credentials internally, refuses redirects, and shares Creative's persisted daily allowance. A missing broker or an unpriced request fails closed. Motion remains local even when a still needs repair. Budget exhaustion retains the checkpoint and reports a blocker; approval is never fabricated or re-requested merely to retry the same unchanged approved version.

The xAI still-edit bound uses explicit medium/2K/one-output settings: $0.08 output plus $0.01 per input image, verified against https://docs.x.ai/developers/models/grok-imagine-image-2.0 on November 12, 2026. Pricing expires with the native budget policy. This is a still-image charge, not video rendering.

Focused tests: `tests/film_workflow/main.swift`, `tests/film_broker/main.swift`, and `tests/check_voice_chunks.py`. The workflow test executes real stage transitions with disposable director results and never calls providers or manufactures live consensus.

## Writing-only revision while the screen is locked

The running app polls a private local revision inbox independently of WebKit readiness. Submit the owner's complete feedback with:

```sh
/Applications/Jarvis.app/Contents/MacOS/Jarvis --story-revision-request /absolute/path/to/feedback.txt
```

This queues a version-bound writing request; it does not unlock the Mac or authorize production. Jarvis must be running. The app accepts revisions only for awaiting-approval, completed or production-needs-attention stories. It archives the previous workflow and request, preserves the historical approval record, clears the replacement's approval, and dispatches Creative through the existing consultation workflow. Stale screenplay versions cannot start another consultation. A replacement still requires review and fresh owner approval of its exact version. Processing status is retained in the private story-revision-history directory.

The workflow regression checks old approval preservation, once-only dispatch, full feedback delivery and stale request rejection.

Failed Creative writing requests can be retried from needs-attention when the current saved consultation task is a failed Creative task. A failed Research review cannot use this entry to send the old screenplay forward. Consultation failure also terminalizes the aggregate story task. Sonnet 5.5 screenplay requests use its documented `between_tools` thinking mode with no tools, leaving output for the deliverable; ordinary clients retain their existing defaults. Provider limit diagnostics report block types and text length without persisting reasoning contents.

Latest owner revision direction is stored separately from the evolving Research feedback. Every later writer/reviewer/confirmation handoff includes it verbatim alongside the baseline brief and source evidence. Tests ensure a reviewer report cannot erase the owner's new direction.

Writing requests omit the tools field when no tools are available. Response-limit diagnostics retain only request/response model names, thinking mode, tool count, stop reason, numeric usage and content-block types/lengths; no raw reasoning or credentials are persisted. A thinking-only response remains a failed delivery, not a screenplay or director acceptance.

## Independent story architecture workshop

At a terminal screenplay checkpoint, `--director-writing-request creative /absolute/brief.txt` queues a separate real writing-only consultation task. The command also accepts `research` for a later independent critique of the complete saved spine. These tasks do not modify the screenplay workflow, approval, hash or script, and do not auto-start another screenplay or render. The request archive records the actual task ID. Research is submitted manually only after Creative's full saved result is available; workshop agreement is not screenplay approval.

The dispatch regression verifies that the saved screenplay bytes remain unchanged and a repeated inbox scan cannot duplicate the workshop task.

Scoped Research writing tasks use the configured Grok model's no-tools review path (4,096 output tokens, 540-second request and 600-second assignment watchdog). They preserve the format requested by the brief, without silently using web research or switching to the fast model. Provider failures keep the original reservations and return the review path's explicit diagnostic.

## Present a separately reviewed complete assembly

At an idle terminal checkpoint, `--adopt-reviewed-story /absolute/script.md research-task-id creative-task-id` queues an exact-version validation. Both actual saved parent tasks must be completed, belong to their respective seats, and contain the complete same script and SHA-256 in their original instructions. The full Research result must parse as an acceptance of that hash with no changes. The Creative result body must consist of the standalone acceptance marker and the exact screenplay hash, with no contradictory text. Runtime must be valid.

Successful validation archives the previous workflow, adoption request and full director results, preserves owner direction/history, and presents the complete assembled script as awaiting approval. Viewed and approval fields are cleared; adoption does not open the result on behalf of the owner, queue a production task or dispatch rendering. The owner must open and explicitly approve that exact version through the existing gate. Failed evidence validation leaves the screenplay unchanged.

Regression coverage includes changed content, stale reviews, running calls, mismatched or contradictory confirmation, retained history, unread owner gate and no render dispatch.
