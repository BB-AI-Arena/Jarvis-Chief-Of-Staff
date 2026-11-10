#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build
swift build -c release
swiftc Sources/Jarvis/VoiceTurn.swift tests/voice_turns/main.swift -o .build/check-voice-turns
.build/check-voice-turns
swiftc Sources/Jarvis/RouteDecision.swift tests/routing/main.swift -o .build/check-routing
.build/check-routing
swiftc Sources/Jarvis/VoiceActivity.swift tests/voice_activity/main.swift -o .build/check-voice-activity
.build/check-voice-activity
swiftc Sources/Jarvis/TaskLedger.swift tests/ledger/main.swift -o .build/check-ledger
.build/check-ledger
swiftc Sources/Jarvis/ClaudeClient.swift tests/claude/main.swift -o .build/check-claude
.build/check-claude
swiftc Sources/Jarvis/GrokClient.swift tests/grok/main.swift -o .build/check-grok
.build/check-grok
swiftc Sources/Jarvis/CursorClient.swift tests/cursor/main.swift -o .build/check-cursor
.build/check-cursor
swiftc Sources/Jarvis/BoardDebate.swift tests/debate/main.swift -o .build/check-debate
.build/check-debate
swiftc Sources/Jarvis/OllamaClient.swift tests/ollama/main.swift -o .build/check-ollama
.build/check-ollama
for persona in jarvis cto research operations creative projects board-charter; do test -s "Resources/board/personas/$persona.md" || { echo "FAIL: missing persona $persona"; exit 1; }; grep -q "\"$persona\"" Sources/Jarvis/Personas.swift || { echo "FAIL: persona $persona not loadable"; exit 1; }; done
echo "PASS: every board persona and the charter are bundled and loadable"
node --check Resources/app.js
npm test
python3 -m py_compile scripts/voice.py scripts/visemes.py
