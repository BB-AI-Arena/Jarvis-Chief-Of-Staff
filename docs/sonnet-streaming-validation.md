# Sonnet sentence streaming validation

This follow-up uses Claude Sonnet for conversation and streams complete reply sentences into the local British Kokoro voice queue. It retains the full final text and avoids speaking the same completed reply twice. It does not reintroduce the earlier fixed 50-character speech fragments.

The SSE parser accepts one named route tool with matching block indexes. Incomplete, failed, unknown-tool and multiple-tool responses cannot become completed routing decisions. Provider requests reserve the existing daily Jarvis allowance before transport; successful usage settles the hold, while ambiguous failures retain it.

Independent checks passed: UI regression/format checks; no-network URLSession SSE transport with escaped text, exact final speech, invalid block/tool handling and budget settlement; and six real British sentence WAVs retained while waiting for playback. Playback now owns completed-file cleanup and updates mouth/audio timing. Stream failures clear queued speech so the connection error can be spoken.

A separate live native Sonnet smoke request yielded its first complete sentence after approximately 1.86 seconds and returned matching final text. This is one observation, not a latency guarantee or proof of audible installed streaming.

## Release state

The signed build was installed only after production exhausted its bounded retries and no native tasks remained active. The retained screenplay approval and production recovery state were preserved. Source publication to `main` follows independent installed-build verification; this release does not claim that film production completed successfully.

The source manifest contains 100 application inputs. The independent audit uses `tests/check_installed_build.py --ref origin/main --manifest docs/followup-source-manifest.json` against `/Applications/Jarvis.app`, including strict signatures, source digests, complete bundle comparison, resource membership, executable comparison and unsupported broker destination refusal.

## Approved-script artwork repair

The subsequent worker repair permits explicitly identified screen/prop inserts without unrelated artwork references. It verifies the supplied approved screenplay hash, adds that complete script and production constraints to director requests, and bypasses prior local outlines for a locked screenplay. Films configured `local_render_only` refuse the cloud still-image fallback. These checks bind the planning input; creative review is still needed to establish scene fidelity.

Independent regression checks passed: all 53 film-worker tests, film-budget tests and supervisor tests. The signed package was installed at an idle point before publication. The existing screenplay approval and spend records were preserved. This release does not claim a completed or accepted film.

## Planning visibility and protagonist references

Registered supervised films attach to the task view before `plan.json` exists. Startup refreshes external jobs before projecting saved screenplay status, while failed, cancelled and stale-heartbeat supervision still fails closed. Approved-script casting can create a protagonist reference when the supplied artwork is only a logo; canonical references remain specific to that person and are reused on resume.

All 54 worker tests passed, including protagonist reference creation and resume without duplicate generation. `tests/check_external_film_state.py` compiles the actual native refresh methods with real ledger/video state in a disposable directory; it verifies missing-plan attachment, one task record, failure, cancellation and stale-heartbeat behavior without touching runtime jobs.

## Descriptive inserts and bounded render units

Screen/prop inserts accept a descriptive non-empty explanation instead of requiring one exact phrase. Blank, short, non-text reasons and unsupported coverage still fail validation. For locked screenplay batches, a bounded production-editor request can subdivide overlong render units; the returned batch must retain its total duration and every shot must remain within the renderer's one-to-five-second limit. Variable shot counts allow a short title card without forcing another unit over the limit. Story-preservation instructions remain attached; duration validation is not semantic creative acceptance.

All 55 worker tests passed, including invalid explanations, unsupported coverage, retained short-card timing, idempotent valid batches, changed-total rejection and rejection of still-overlong repair results.

## Deterministic approved opening card

A job-scoped opening plate can replace generated lettering with a real-font PNG, bound to the approved screenplay hash, two nonblank distinct approved text lines, image hash and shot timing. Valid PNG dimensions must match metadata. The worker uploads that plate to DARK and uses NVIDIA NVENC for the fade clip, checking encoded dimensions and exact frame count. Cached clips are reused only when their signatures and file hashes match.

All 57 worker tests passed, including malformed text metadata, changed source pixels, dimension mismatches, incorrect export frame counts/dimensions and tampered cache regeneration. The test command uses the existing film Python runtime if the system Python lacks Pillow. These technical checks do not replace visual inspection of the actual encoded opening or creative acceptance of the completed film.

## Whole-batch format repair

Batch validation now checks the full duration, references and required fields before skipping repair. A batch of five valid five-second units no longer passes for a required thirty-second interval. The editor receives assigned approved goals and the reference legend, with at most two repair attempts; unresolved format errors become a non-retryable needs-attention state. Existing valid batches require no editor call.

All 58 worker tests and three supervisor tests passed, including the 25-to-30-second regression and the two-attempt stop. Successful format validation does not establish semantic or visual acceptance of newly generated footage.
