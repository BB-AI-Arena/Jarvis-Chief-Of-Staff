#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ "${1:-}" == "--ui" ]]; then
    exec npm run check:ui
fi
mkdir -p .build
swiftc Sources/Jarvis/SpendBudget.swift tests/budget/main.swift -o .build/check-budget
.build/check-budget
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/VoiceHandoff.swift tests/voice_handoff/main.swift -o .build/check-voice-handoff
.build/check-voice-handoff
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/CloudVoice.swift Sources/Jarvis/VoiceHandoff.swift Sources/Jarvis/VoiceActivity.swift Sources/Jarvis/Personas.swift tests/cloud_handoff/main.swift -o .build/check-cloud-handoff
.build/check-cloud-handoff
swift build -c release --disable-sandbox
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/VoiceTurn.swift tests/voice_turns/main.swift -o .build/check-voice-turns
.build/check-voice-turns
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/RouteDecision.swift tests/routing/main.swift -o .build/check-routing
.build/check-routing
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/VoiceActivity.swift tests/voice_activity/main.swift -o .build/check-voice-activity
.build/check-voice-activity
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/TaskLedger.swift tests/ledger/main.swift -o .build/check-ledger
.build/check-ledger
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/TaskLedger.swift Sources/Jarvis/DirectorResultsContext.swift tests/director_results/main.swift -o .build/check-director-results
.build/check-director-results
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/TokenMeter.swift Sources/Jarvis/ClaudeClient.swift tests/claude/main.swift -o .build/check-claude
.build/check-claude
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/DarkServer.swift Sources/Jarvis/VideoArtwork.swift Sources/Jarvis/VideoRender.swift Sources/Jarvis/VideoPlan.swift Sources/Jarvis/TokenMeter.swift Sources/Jarvis/GrokClient.swift tests/grok/main.swift -o .build/check-grok
.build/check-grok
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/ProjectsTool.swift Sources/Jarvis/OllamaClient.swift Sources/Jarvis/DarkServer.swift Sources/Jarvis/VideoArtwork.swift Sources/Jarvis/VideoRender.swift Sources/Jarvis/VideoPlan.swift Sources/Jarvis/TokenMeter.swift tests/projects/main.swift -o .build/check-projects
.build/check-projects
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/CursorClient.swift tests/cursor/main.swift -o .build/check-cursor
.build/check-cursor
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/BoardDebate.swift tests/debate/main.swift -o .build/check-debate
.build/check-debate
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/DarkServer.swift Sources/Jarvis/VideoArtwork.swift Sources/Jarvis/VideoRender.swift Sources/Jarvis/VideoPlan.swift Sources/Jarvis/TokenMeter.swift Sources/Jarvis/OllamaClient.swift tests/ollama/main.swift -o .build/check-ollama
.build/check-ollama
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/VideoPlan.swift Sources/Jarvis/VideoArtwork.swift Sources/Jarvis/VideoRender.swift Sources/Jarvis/DarkServer.swift tests/video/main.swift -o .build/check-video
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/VideoPlan.swift Sources/Jarvis/VideoArtwork.swift Sources/Jarvis/VideoRender.swift Sources/Jarvis/DarkServer.swift Sources/Jarvis/LocalFilmWorker.swift tests/film_bridge/main.swift -o .build/check-film-bridge
.build/check-film-bridge
.build/check-video
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/VideoPlan.swift Sources/Jarvis/VideoArtwork.swift Sources/Jarvis/VideoRender.swift Sources/Jarvis/DarkServer.swift Sources/Jarvis/LocalFilmWorker.swift tests/film_bridge/main.swift -o .build/check-film-bridge
.build/check-film-bridge
swiftc Tools/jarvis-keys/main.swift -o .build/check-jarvis-keys
zsh tests/keys/check.sh .build/check-jarvis-keys
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/TokenMeter.swift Sources/Jarvis/JarvisRouter.swift Sources/Jarvis/RouteDecision.swift tests/router/main.swift -o .build/check-router
.build/check-router
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/BoardMemory.swift tests/memory/main.swift -o .build/check-memory
.build/check-memory
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/WorkspaceTools.swift tests/workspace/main.swift -o .build/check-workspace
.build/check-workspace
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/WorkspaceTools.swift Sources/Jarvis/SharedWorkspaceContext.swift tests/workspace_context/main.swift -o .build/check-workspace-context
.build/check-workspace-context
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/TokenMeter.swift Sources/Jarvis/Acceptance.swift Sources/Jarvis/JarvisRouter.swift Sources/Jarvis/RouteDecision.swift tests/acceptance/main.swift -o .build/check-acceptance
.build/check-acceptance
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/TokenMeter.swift Sources/Jarvis/HealthCheck.swift Sources/Jarvis/DarkServer.swift Sources/Jarvis/VideoPlan.swift Sources/Jarvis/VideoArtwork.swift Sources/Jarvis/VideoRender.swift Sources/Jarvis/ClaudeClient.swift Sources/Jarvis/GrokClient.swift Sources/Jarvis/OllamaClient.swift Sources/Jarvis/CursorClient.swift Sources/Jarvis/RouteDecision.swift Sources/Jarvis/AgentRuntime.swift Sources/Jarvis/ConversationBrain.swift Sources/Jarvis/Personas.swift Sources/Jarvis/KeychainBroker.swift Sources/Jarvis/VoiceCredential.swift Sources/Jarvis/ClaudeCredential.swift Sources/Jarvis/GrokCredential.swift Sources/Jarvis/CursorCredential.swift tests/health/main.swift -o .build/check-health
.build/check-health
for persona in jarvis cto research operations creative projects board-charter; do test -s "Resources/board/personas/$persona.md" || { echo "FAIL: missing persona $persona"; exit 1; }; grep -q "\"$persona\"" Sources/Jarvis/Personas.swift || { echo "FAIL: persona $persona not loadable"; exit 1; }; done
echo "PASS: every board persona and the charter are bundled and loadable"
node --check Resources/app.js
node --check Resources/live.js
swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/LiveUI.swift Sources/Jarvis/ResultMedia.swift Sources/Jarvis/TokenMeter.swift tests/live/main.swift -o .build/check-live
.build/check-live
npm test
python3 tests/check_video_artwork.py
python3 -B tests/check_film_worker.py
PYTHONPYCACHEPREFIX=/tmp/jarvis-check-pycache python3 -m py_compile scripts/voice.py scripts/visemes.py Resources/prepare-video-artwork.py Resources/film_worker.py Resources/film_sound.py Resources/film_finish.py Resources/film_score.py Resources/film_screen.py

python3 -B tests/check_film_supervisor.py

swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/PromptDelivery.swift Sources/Jarvis/FilmStory.swift tests/film_story/main.swift -o .build/check-film-story
.build/check-film-story

swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/StoryReview.swift tests/story_review/main.swift -o .build/check-story-review
.build/check-story-review

swiftc Sources/Jarvis/SpendBudget.swift Sources/Jarvis/FilmProviderBroker.swift tests/film_broker/main.swift -o .build/check-film-broker
.build/check-film-broker
swiftc Sources/Jarvis/TaskLedger.swift Sources/Jarvis/FilmStory.swift Sources/Jarvis/StoryReview.swift Sources/Jarvis/FilmStoryWorkflow.swift tests/film_workflow/main.swift -o .build/check-film-workflow
.build/check-film-workflow

python3 -B tests/check_film_budget.py
