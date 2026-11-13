# Follow-up validation and installed-build provenance

This follow-up adds a shared native budget broker for the film worker, exact-script production gating, local-DARK-only video rendering and ordered British speech chunks. It does not claim that a completed production film has passed creative acceptance or that Cursor agent execution has been verified.

## Checks

Passed November 12, 2026: the regression suite (initial checks plus the complete remainder after the coordinated source rebuild), real local voice chunk checks, and shell/Python syntax checks. The final package and installation are accepted separately by the provenance audit below.

The regression run covers voice handoffs, native compilation, routing, ledger state, provider parsing and continuations, spending boundaries/settlement, workflow approval, film worker/supervisor behavior, UI behavior and the new broker contracts. Separate real local speech checks verify that both utterances produce ordered non-empty PCM files with exactly one final marker. They are not a physical-listening quality assessment or a latency guarantee.

New tests check that paid Python calls cannot fall back around the native broker, unsupported provider URLs are rejected before credential access, still-image request shape and pricing are bounded, cloud video rendering is refused, and stale/conditional/disconnected screenplay approval cannot start production.

## Installed-source verification

The pre-build [source manifest](followup-source-manifest.json) records SHA-256 hashes for every Swift source, bundled resource, script and Package.swift. Packaging now recreates the generated resource directory so deleted source assets and Python caches cannot survive an upgrade.

After publication, run this read-only audit from the checkout:

```sh
python3 tests/check_installed_build.py --ref origin/main \
  --manifest docs/followup-source-manifest.json \
  --output .build/installed-publication-verification.json
```

It requires every manifest entry to match the selected Git commit and working source, verifies strict code signatures, compares every installed bundle file with the built package, rejects extra or missing resources, compares the installed executable with the release binary after removing signatures from temporary copies only (signing legitimately changes Mach-O bytes), and invokes the installed broker with an unsupported destination to prove refusal before provider access. The report records the exact commit, tree and executable/bundle hashes.

Private runtime state, credentials, saved scripts and results are not part of source publication. Installation retains the existing Keychain helper and a rollback bundle. A matching installed bundle establishes build provenance; it does not independently establish director consensus, audible voice quality or final-film quality.
