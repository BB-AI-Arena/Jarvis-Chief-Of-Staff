# Validation

Development checks on an Apple M5 MacBook Air with 32 GB unified memory.

- Release native compilation and application signature verification passed.
- Conversation UI checks cover automatic turn submission, spoken replies, cancellation, interruption, portrait persistence and prevention of duplicate orb requests.
- Turn-detection and route-decoding checks passed, including fenced JSON, empty routes and malformed data.
- Kokoro Lewis and Emma generated valid 24 kHz audio with phoneme-aligned mouth cues. Observed synthesis time varied with text length and process warm-up.
- Installed local Gemma routing was exercised for discussion, Astra delegation and explicit source tasks. Warm route decisions were around 1.1–1.5 seconds in short tests; speech and turn detection add time.
- An installed-app source inspection was delegated to Astra, returned a source-backed result and made no file changes.
- Public API authentication and real streaming audio were verified without microphone capture. Two greeting probes received first audio in approximately 0.75 and 0.79 seconds after the greeting request; session startup was measured separately. These are greeting probes, not complete human-conversation latency benchmarks.
- The installed app connected its microphone and received a streamed greeting. Further device playback and full-duplex interruption testing remains necessary.
- Graphify code-only extraction and the folder/relationship display were exercised on a small fixture.

The broader multi-provider office, durable jobs, semantic memory and local weight training remain future work. Test results do not imply unlimited usage, photorealistic articulation or production readiness.
