#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
python_bin="${JARVIS_PYTHON:-/opt/homebrew/bin/python3.12}"
[[ -d .graphify ]] || "$python_bin" -m venv .graphify
[[ -d .voice ]] || "$python_bin" -m venv .voice
.graphify/bin/pip install -r requirements-graphify.txt
.voice/bin/pip install -r requirements-voice.txt
mkdir -p .voice/models
for name in kokoro-v1.0.onnx voices-v1.0.bin; do
    if [[ ! -f ".voice/models/$name" ]]; then
        curl -fL --retry 2 "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/$name" -o ".voice/models/$name.part"
        mv ".voice/models/$name.part" ".voice/models/$name"
    fi
done
