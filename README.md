# Jarvis-Chief-Of-Staff

A voice-first chief of staff for macOS, created and maintained by [BeastBreaker](https://github.com/BB-AI-Arena).

Jarvis puts a cinematic android presence at the center of the experience: talk through an idea, request deeper reasoning, delegate a source task, or explore your files as a graph.

**Noncommercial use:** project-authored code is available under [PolyForm Noncommercial 1.0.0](LICENSE). See [NOTICE](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md).

## What works

- Native AppKit application with a bundled WKWebView interface; no Electron or hosted frontend.
- Portrait home screen, animated eyes, facial relief, and a floating desktop orb. Conversation history is a separate view.
- Direct OpenAI Live API voice streaming with British delivery, microphone input, playback and interruption controls. The API key is entered through a native secure field and stored in macOS Keychain.
- Luna handles delegated conversation requests, with Astra available for deeper reasoning through the local agent-runtime adapter.
- Explicit requests concerning Jarvis’s own source can launch an Astra worker in a workspace-write sandbox. Results return to Conversation; a stop control is available. The worker does not replace the running installed app.
- Ollama model discovery and local conversation, selectable in Settings.
- Local Kokoro speech with Lewis by default and selectable voices for other roles. Local speech uses real phoneme timings for approximate closed-lip, rounded-vowel, wide-vowel and jaw poses.
- Folder maps and Graphify code relationships, including search, pan, zoom and Reveal in Finder.
- Local conversation history, project briefs and preferences.

## Current limitations

This is an early source build. The portrait is a relief mesh with image deformation, not a fully rigged head. API speech drives approximate facial movement from actual playback power; Kokoro supplies more detailed local phoneme timing.

Cloud audio and model calls have provider usage charges and network latency. A standalone API greeting test received its first audio in approximately 0.75–0.79 seconds after the greeting request; this is not an end-to-end spoken-turn guarantee. Device playback, interruption quality and conversation latency still need broader testing.

Jarvis MCP, multi-provider councils, a durable job queue, semantic long-term memory retrieval and local-model fine-tuning are not connected yet. Saved conversation is not model training. Claude and Grok entries describe planned roles, not active integrations.

## Build on a Mac

Requires Apple Silicon, macOS 14 or later, Swift 6 command-line tools and Python 3.12. Node.js is needed only for frontend development and UI tests. The Luna/Astra and coding-worker adapters expect a separately installed, signed-in local agent runtime supporting the app-server and exec protocols; set `JARVIS_AGENT_RUNTIME` to its absolute executable path before building. The build embeds that path into the local app bundle. A private `.agent-runtime-path` file can provide the same value and is ignored by Git. Ollama is optional for local conversation.

```sh
./scripts/bootstrap.sh
./scripts/build.sh
open dist/Jarvis.app
```

`bootstrap.sh` creates local Python environments and downloads speech weights. These are development dependencies outside the app bundle. Set `JARVIS_PYTHON` if Python 3.12 is installed somewhere other than the script default.

The generated app embeds its source-workspace location for helper scripts. Keep the source folder and environments available. This is an ad-hoc signed development build, not a notarized distributable installer.

For API voice, open **Settings → Connect OpenAI realtime voice**, enter your own key, select realtime conversation audio and start a conversation. Keys, personal chat history, folder indexes and runtime caches are excluded from this repository. Credentials never pass through the web interface.

## Frontend development and checks

```sh
npm install
npm run build:presence
npm test
./scripts/check.sh
```

Bundled frontend assets are committed so a normal native build does not require a Node bundler. Optional integration checks in `tests` exercise real local models, speech weights and Graphify. `scripts/probe_live.py` performs a bounded public-API audio check using this Mac’s Keychain entry without capturing the microphone or printing credentials.

## Design direction

A fast spoken business partner with persistent project memory and specialist delegation. Prefer focused task context, retrieve relevant facts, record verified outcomes and curate reusable skills. Any future weight training should use reviewed examples and evaluation, separately from ordinary chat memory.

The assistant is an original persona with composed British delivery and restrained dry wit. It is not affiliated with Marvel.
