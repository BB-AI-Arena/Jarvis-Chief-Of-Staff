# Follow-up validation and installed-build provenance

This follow-up adds a shared native budget broker for the film worker, exact-script production gating, local-DARK-only video rendering and continuous British local speech. It does not claim that a completed production film has passed creative acceptance or that Cursor agent execution has been verified.

## Checks

Passed November 12, 2026: the regression suite (initial checks plus the complete remainder after the coordinated source rebuild), the original local voice chunk checks, and shell/Python syntax checks. The final package and installation are accepted separately by the provenance audit below.

The regression run covers voice handoffs, native compilation, routing, ledger state, provider parsing and continuations, spending boundaries/settlement, workflow approval, film worker/supervisor behavior, UI behavior and the new broker contracts. The original chunk checks verified ordered PCM generation, but the owner subsequently reported robotic cadence. Those checks did not establish acceptable listening quality, and short-phrase chunking has been removed in the corrective follow-up. Continuous speech validation is recorded below.

New tests check that paid Python calls cannot fall back around the native broker, unsupported provider URLs are rejected before credential access, still-image request shape and pricing are bounded, cloud video rendering is refused, and stale/conditional/disconnected screenplay approval cannot start production.

## Installed-source verification

The pre-build [source manifest](followup-source-manifest.json) records SHA-256 hashes for every Swift source, bundled resource, script and Package.swift. Packaging now recreates the generated resource directory so deleted source assets and Python caches cannot survive an upgrade.

After publication, run this read-only audit from the checkout:

```sh
python3 tests/check_installed_build.py --ref origin/main \
  --manifest docs/followup-source-manifest.json \
  --output .build/installed-publication-verification.json
```

It requires every manifest entry to match the selected Git commit and working source, verifies strict code signatures, compares every installed bundle file with the built package, rejects extra or missing resources, compares the installed executable with the release binary after removing signatures from temporary copies only and normalizing only the validated `__LINKEDIT` VM padding left by signing (signing legitimately changes Mach-O bytes), and invokes the installed broker with an unsupported destination to prove refusal before provider access. The report records the exact commit, tree and executable/bundle hashes.

Private runtime state, credentials, saved scripts and results are not part of source publication. Installation retains the existing Keychain helper and a rollback bundle. A matching installed bundle establishes build provenance; it does not independently establish director consensus, audible voice quality or final-film quality.

## Long screenplay review timeout follow-up

Final version-bound Grok screenplay reviews now allow 540 seconds for the provider request and 600 seconds for the Research assignment watchdog. Ordinary Grok requests retain their 180-second request timeout and ordinary Research retains its existing watchdog. The full supplied screenplay and 4,096-token output limit are preserved. No budget balances or reservations are reset.

A no-network transport fixture checks the default and extended request timeouts, the complete request payload, successful completion and timeout failure. A timeout must return a failure rather than a completed review. This fixture and a successful signed release build validate the change; they do not establish successful live director consensus.

## British voice correction

The owner reported robotic cadence from short speech chunks. Speech generation and native playback return to one complete utterance using local Kokoro `bm_lewis` with British English. Claude is selectable for conversation; its text generation is separate from the local voice. Claude-only conversation must report a connection failure instead of silently changing conversation models.

Independent `npm run check:ui` and `python3 tests/check_voice_continuity.py` runs passed. The real British worker produced one continuous 5.85-second WAV with mouth timings; the UI test confirms a spoken turn selects Claude.

Automated PCM checks cannot establish subjective listening quality or promise response latency. The final installation still needs the owner's listening assessment.
