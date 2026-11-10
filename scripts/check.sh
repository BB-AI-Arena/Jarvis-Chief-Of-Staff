#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build
swift build -c release
swiftc Sources/Jarvis/VoiceTurn.swift tests/voice_turns/main.swift -o .build/check-voice-turns
.build/check-voice-turns
swiftc Sources/Jarvis/RouteDecision.swift tests/routing/main.swift -o .build/check-routing
.build/check-routing
swiftc Sources/Jarvis/TaskLedger.swift tests/ledger/main.swift -o .build/check-ledger
.build/check-ledger
node --check Resources/app.js
npm test
python3 -m py_compile scripts/voice.py scripts/visemes.py
