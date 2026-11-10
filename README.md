<div align="center">

<img src="Resources/jarvis-android.jpg" alt="Jarvis — a cyan-lit android with a cinematic presence" width="320" />

# J A R V I S
### Your voice. Your vision. Your AI executive team.

**A cinematic, voice-first chief of staff for your Mac.**<br>
Brainstorm face-to-face. Bring in specialist directors. Turn the next big idea into an accountable assignment.

[![macOS](https://img.shields.io/badge/macOS-14%2B-111827?style=for-the-badge&logo=apple&logoColor=white)](#build-your-jarvis)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-Native-00c8df?style=for-the-badge)](#built-for-the-mac)
[![Voice First](https://img.shields.io/badge/Voice-First-7856ff?style=for-the-badge)](#a-presence-you-can-talk-to)
[![License](https://img.shields.io/badge/License-Noncommercial-f2b85b?style=for-the-badge)](LICENSE)

[Explore the experience](#a-presence-you-can-talk-to) · [Meet the board](#your-ai-boardroom) · [Build your Jarvis](#build-your-jarvis) · [See the roadmap](#where-jarvis-goes-next)

Created and maintained by **[BeastBreaker / BB-AI-Arena](https://github.com/BB-AI-Arena)**

</div>

---

## Big ideas deserve a chief of staff

Imagine opening your Mac and talking through the business you want to build. Jarvis listens, helps sharpen the idea, and brings the right specialist into the conversation. Engineering goes to the CTO. Research goes to the Research Director. Creative work goes to the Creative Director. Work has an owner, a visible status and a place to return its results.

That is the direction of **Jarvis-Chief-Of-Staff**: a personal AI headquarters with a memorable face, a distinctive voice and the beginnings of a real executive team.

**Already in the source:** streaming voice, local model support, an animated boardroom, provider adapters, approval-based task suggestions, a persistent task ledger and an interactive file graph. This is an actively developed source build; provider seats require configuration, and the larger autonomous office is still being built.

## See the actual app

<img src="docs/screenshots/jarvis-home.jpg" alt="Actual Jarvis macOS development app showing the portrait-first home, navigation and voice conversation controls" width="100%" />

*Captured from the running macOS development app. This is the real interface, not a mockup.*

## A presence you can talk to

| Experience | What makes it Jarvis |
| :--- | :--- |
| 🎙️ **Voice at the center** | Streaming microphone input and spoken replies, interruption controls and a separate conversation log. |
| 🧊 **A cinematic face** | Cyan eyes, facial depth, speech-reactive lips and jaw, subtle motion and a portrait-first home. |
| 🫧 **A floating companion** | Collapse the workspace into a draggable desktop orb and return when you need the full view. |
| 🇬🇧 **A distinctive personality** | Composed British delivery, discreet assistance and restrained dry wit. |
| 🔊 **Local speech** | Kokoro voices, including **bm_lewis**, plus selectable voices and previews for team roles. |
| 🧠 **Your choice of intelligence** | Luna conversation routing, Astra for deeper reasoning and selectable Ollama models for local conversation. |
| 🕸️ **Files you can explore** | Folder maps and Graphify code relationships with search, pan, zoom and Reveal in Finder. |

> **“Jarvis, help me think this through.”**<br>
> Start with a conversation. Move toward a clear brief, the right director and an assignment you can track.

## Your AI boardroom

<img src="docs/screenshots/jarvis-boardroom.jpg" alt="Actual Jarvis app showing the full Board of Directors, all six character seats, provider labels and the task table" width="100%" />

*The full boardroom in the running development app: all six directors, their connection labels and the task table. Availability reflects the configuration at capture time; some seats are not connected. Screenshots show a development build and may include visual updates ahead of the published source.*

The board gives each specialist a seat, a persona and a clear responsibility. Connection indicators distinguish configured providers from seats that are still waiting for a backend.

| Seat | Responsibility | Current implementation |
| :--- | :--- | :--- |
| **Jarvis · Chief of Staff** | Conversation, clarification and delegation | Voice frontend with Luna/Astra routing and local conversation options. |
| **Chief Technology Officer** | Engineering judgment and technical coordination | Anthropic/Claude adapter, configurable model, native tool-call handling and bounded tool rounds. Requires a verified API connection. |
| **Director of Research** | Research and alternative perspectives | xAI/Grok request adapter and configurable model. Requires a verified API connection; live web research is not supplied by this adapter alone. |
| **Creative Director** | Design direction, naming, copy and repository work | Cursor Cloud Agents adapter with a configurable repository/model, run polling, result links and cancellation. Requires API access and repository authorization. |
| **Director of Operations** | Scoped execution and source-workspace coordination | Configurable manager backed by the local agent runtime; can dispatch a constrained Jarvis source worker. |
| **Director of Projects** | Planning and project coordination | Persona and assignment seat; execution backend remains unconnected. |

A staged debate playback demonstrates turn-taking and agreement animation. It is labeled as a **demo**, separate from real provider calls. Autonomous multi-model council deliberation is on the roadmap.

## From conversation to accountable work

**Discuss → assign → track → review.**

- **Suggestions wait for approval.** A task suggested during conversation is not added to the ledger until approved. Explicit task requests can be routed directly to the relevant director.
- **Assignments have owners.** Director and worker relationships are recorded with parent task IDs.
- **State survives a restart.** The local ledger stores proposed, running, completed, failed and cancelled work, timestamps and result summaries.
- **Interrupted work stays honest.** A task left running at shutdown is marked interrupted/failed on relaunch; it does not silently become “done.”
- **You can stop active work.** Task controls target the running assignment, including supported remote-agent cancellation.
- **Source workers have a boundary.** The Operations worker is instructed to work inside Jarvis’s source workspace and report its changes and validation. It does not automatically replace the installed app.

The ledger is a foundation for dependable execution. Automatic dependency scheduling, retries, resume and independent result verification are future work.

## Built for the Mac

**Swift + AppKit · WKWebView · Three.js · Python helpers**

The native shell hosts bundled HTML, CSS and JavaScript. Three.js provides the portrait presence; Kokoro handles local speech; Graphify extracts code relationships; Ollama supplies optional local conversation models.

| Layer | Purpose |
| :--- | :--- |
| `Sources/Jarvis/main.swift` | Native app lifecycle, frontend bridge, task orchestration and provider configuration. |
| `CloudVoice.swift` / `ConversationBrain.swift` | Streaming audio and delegated model routing. |
| `ClaudeClient.swift` / `GrokClient.swift` / `CursorClient.swift` | Specialist provider adapters. |
| `TaskLedger.swift` / `Personas.swift` | Persistent task records and bundled executive personas. |
| `Frontend/presence.mjs` / `Resources/` | Portrait renderer, boardroom and application interface. |
| `scripts/voice.py` / `scripts/visemes.py` | Local speech generation and phoneme-aligned facial cues. |

API credentials are entered through native secure fields and stored in **macOS Keychain**. Keys are not passed into frontend JavaScript. Personal conversation history, indexes, caches, model weights and private runtime configuration are excluded from the public repository.

Local processing is available for selected workflows. Cloud voice and connected providers transmit the relevant audio, prompts or repository work to their services and may incur usage charges.

## Build your Jarvis

### Requirements

- Apple Silicon Mac, macOS 14 or later.
- Swift 6 command-line tools and Python 3.12.
- Node.js for frontend development and UI checks.
- Optional: Ollama and a downloaded local model.
- For Luna/Astra routing and Operations workers: a separately installed, signed-in agent runtime supporting the app-server and exec protocols.
- For cloud voice and specialist directors: your own provider credentials and appropriate service access.

Development has been checked on an **M5 MacBook Air with 32 GB unified memory**. Local model suitability depends on model size, quantization and the other applications running.

```sh
git clone https://github.com/BB-AI-Arena/Jarvis-Chief-Of-Staff.git
cd Jarvis-Chief-Of-Staff

# Optional: point to your compatible local agent runtime before building.
export JARVIS_AGENT_RUNTIME="/absolute/path/to/your/agent-runtime"

./scripts/bootstrap.sh
./scripts/build.sh
open dist/Jarvis.app
```

`bootstrap.sh` creates Python environments and downloads speech weights. If necessary, set `JARVIS_PYTHON` to your Python 3.12 executable. A private, ignored `.agent-runtime-path` file can also configure the runtime executable.

### Make it yours

1. Open **Settings**, connect OpenAI realtime voice through the native secure key field and select realtime conversation audio.
2. Start a conversation and choose your conversation brain. Use Ollama for a local conversation path or Luna/Astra through the configured runtime.
3. Open the board to configure the specialist providers you want to use. A seat becomes connected only after its connection check succeeds.
4. Select a local folder to explore its structure and available Graphify relationships.
5. Save a project brief, discuss it with Jarvis and give a connected director a concrete assignment.

This is an ad-hoc signed development app. Helper environments and the source workspace must remain available; a self-contained, notarized installer is a future milestone.

## Development and validation

```sh
npm ci
npm run build:presence
npm test
./scripts/check.sh
```

Bundled frontend assets are committed, so a normal native build does not require rebuilding them with Node. The check script exercises compilation, turn detection, routing, voice activity, task records, provider parsing, personas and conversation UI behavior. These checks do not establish that every external provider is configured or available.

See [VALIDATION.md](VALIDATION.md) for earlier device and integration observations. The optional `scripts/probe_live.py` checks real cloud audio using the local Keychain credential without capturing the microphone or printing the key.

<details>
<summary><strong>Performance and animation: what has actually been measured?</strong></summary>

Two standalone API greeting probes received first audio approximately **0.75–0.79 seconds after the greeting request**. Session startup was measured separately. These are greeting probes, not a guarantee for complete spoken conversations; network, turn detection, delegation and provider load affect latency.

The portrait uses a relief mesh with image deformation rather than a fully rigged 3D head. Cloud speech uses playback activity for approximate facial motion; Kokoro supplies phoneme timing for more detailed local mouth cues. Playback, interruption and facial naturalness remain active areas of development.

</details>

## Where Jarvis goes next

The ambition is a chief of staff who can help take an idea all the way to a reviewed, working product.

- [ ] **Persistent project memory** — retrieve decisions, preferences, commitments and relevant files with source references.
- [ ] **A dependable execution engine** — dependencies, retries, restart recovery and independently verified outcomes.
- [ ] **Real executive meetings** — specialist deliberation, disagreement resolution and recorded decisions.
- [ ] **Smarter model economics** — measured speed, token usage and budget-aware routing, with local models handling suitable work.
- [ ] **Jarvis MCP and business tools** — scoped calendar, email and external application capabilities.
- [ ] **Concept-to-app delivery** — briefs, architecture, artwork, implementation, tests and reviewable builds.
- [ ] **Evaluated local improvement** — reviewed training examples and separate fine-tuning/evaluation workflows.
- [ ] **A distributable Mac app** — bundled dependencies, signing, notarization and a simpler first-run experience.

Saved history is already available; semantic memory and local weight training are not yet implemented. Provider adapters and the task ledger are present; the complete autonomous office is still ahead.

## Follow the build

If a voice-first AI chief of staff belongs on your Mac, **star the repository** and follow the build. Reproducible bug reports and focused feature ideas help turn the vision into a dependable daily companion.

**Discoverability:** `jarvis` · `ai-assistant` · `chief-of-staff` · `macos` · `apple-silicon` · `voice-assistant` · `voice-first` · `ai-agents` · `multi-agent` · `agent-orchestration` · `local-llm` · `ollama` · `kokoro` · `text-to-speech` · `graphify` · `swift` · `threejs` · `claude` · `grok` · `cursor`

---

<div align="center">

**Built by [BeastBreaker](https://github.com/BB-AI-Arena). Built around your ambition.**

[PolyForm Noncommercial 1.0.0](LICENSE) · [Copyright notice](NOTICE) · [Third-party notices](THIRD_PARTY_NOTICES.md)

Project-authored code is available for noncommercial use under the license terms. Third-party components retain their own licenses. Jarvis is an original assistant persona and is not affiliated with Marvel or the model providers.

</div>
