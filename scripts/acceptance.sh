#!/bin/zsh
# Live acceptance run: build, then send ten realistic requests through Jarvis's real router and check every connection.
# Uses the keys in Keychain (never printed). Costs a fraction of a cent. Run before pushing.
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build.sh >/dev/null
echo "== Routing: ten requests"
dist/Jarvis.app/Contents/MacOS/Jarvis --acceptance
echo "== CTO reading the source with its tools"
dist/Jarvis.app/Contents/MacOS/Jarvis --cto-check
echo "== Research fallback: Claude with web search"
dist/Jarvis.app/Contents/MacOS/Jarvis --research-check
echo "== Connections"
dist/Jarvis.app/Contents/MacOS/Jarvis --health
