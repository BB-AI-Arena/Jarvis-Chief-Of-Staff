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
