# Chief of Staff reliability validation — November 12, 2026

The release priority is one loop: a user request becomes a director assignment, the director returns a complete result, the ledger records the outcome, and Results exposes the saved deliverable. Film features and live board debates remain experimental; no new film feature is required for this milestone.

## Real provider checks

Run: `.build/release/Jarvis --core-live-check` after `swift build -c release --disable-sandbox`.

The test uses real Keychain credentials, real provider calls, an isolated ledger and Results directory, and the same persistent director budget as the app. It does not start the normal app or touch existing tasks. Each provider is asked for a fixed marker and a short explanation of why failed tasks must not be called completed. The marker must be present in the saved result, and the parent task must be completed. This is a small delivery smoke test, not a quality benchmark.

| Seat | Observed result |
| --- | --- |
| Claude / technology | Connection verified; real assignment completed; full result saved; result-ready event emitted. |
| Grok / research | Connection verified; real assignment completed via plain-text fallback; full result saved; result-ready event emitted. No live web research claim. |
| Cursor / creative | Connection verified; assignment blocked by the monetary guard before launch. Agent execution remains unverified. |

[Machine-readable evidence](reliability-live-results.json) records exact model IDs, provider token usage, timestamps, outputs and task outcomes. Exit code 2 intentionally reflects the incomplete three-seat result. Do not describe this as three passing live integrations. Microphone capture, spoken output, semantic routing and rendered UI are not asserted by this headless command; those boundaries have separate automated tests, not a full physical end-to-end demonstration.

## Code structure and fast checks

`main.swift` now contains CLI entry points (273 lines). `JarvisApp.swift` owns lifecycle, state and the frontend bridge. `AppAssignments`, `AppConversation`, `AppProviders`, `AppOperations`, `AppResults`, `AppVoice`, `AppVideo`, `AppDebate` and `AppWorkspace` separate responsibilities without replacing the existing orchestration contracts.

`Resources/app.js` is formatted with pinned Prettier 3.6.2. JavaScript statements are expanded for review; long HTML string literals remain intact to preserve markup. `npm run format:ui` applies the format. `npm run check:ui` (or `scripts/check.sh --ui`) checks syntax, formatting and DOM behavior without compiling Swift, invoking film tests or calling providers. The measured wall time on this Mac was 8.19 seconds.

Validation passed: release native build, fast UI suite, and all full-suite checks (the interrupted run was completed with the remaining checks plus the affected budget/router/health checks).

The full suite includes budget boundaries, concurrent reservations, persistence failure, rollover, settlement replay protection, provider continuation and failure handling, voice-turn dispatch, ledger state, routing, results and existing film regressions. Live debate consensus and successful Operations execution on GPT-6-Sol have not been demonstrated in this pass; the README labels them accordingly.

## Recovery and limitations

The GitHub branch `codex/recovery-2026-11-12` contains a Git bundle with the original 33 unpublished commits and the working-copy snapshot. The downloaded remote bundle matched the local bundle byte-for-byte and passed `git bundle verify`; original commit IDs are preserved there. The normal source publication uses the connected GitHub Git-data tools because local HTTPS Git credentials are unavailable.

[Spending controls](spending-controls.md) document the $10 daily director allowance and disabled unbounded launch paths. No account-wide cap, existing-job cancellation or installed-app deployment is claimed. Installation and screenplay/voice repairs are coordinated with the owner's separate repair chat.
