#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
app="$PWD/dist/Jarvis.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Jarvis "$app/Contents/MacOS/Jarvis"
ditto Resources "$app/Contents/Resources"
if [[ ! -f Resources/Jarvis.icns ]]; then
    mkdir -p .build/Jarvis.iconset
    swift scripts/icon.swift .build/icon.png
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" .build/icon.png --out ".build/Jarvis.iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" .build/icon.png --out ".build/Jarvis.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns .build/Jarvis.iconset -o Resources/Jarvis.icns
fi
cp Resources/Jarvis.icns "$app/Contents/Resources/"
python3 - "$app" "$PWD" <<'PY'
import plistlib,sys,os
from pathlib import Path
app,root=sys.argv[1:]
info={'CFBundleName':'Jarvis','CFBundleDisplayName':'Jarvis','CFBundleIdentifier':'ai.fourfront.jarvis.mac','CFBundleVersion':'3','CFBundleShortVersionString':'0.3.0','CFBundleExecutable':'Jarvis','CFBundleIconFile':'Jarvis.icns','CFBundlePackageType':'APPL','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'14.0','NSMicrophoneUsageDescription':'Jarvis listens while voice conversation is on, pauses during replies, and stops when you end the conversation.','NSSpeechRecognitionUsageDescription':'Jarvis recognizes your conversational turns on this Mac and sends the text to your selected model.','JarvisProjectRoot':root}
runtime_file=Path(root)/'.agent-runtime-path'
runtime=os.environ.get('JARVIS_AGENT_RUNTIME') or (runtime_file.read_text().strip() if runtime_file.exists() else '')
if runtime: info['JarvisAgentRuntime']=runtime
with open(Path(app)/'Contents/Info.plist','wb') as f:plistlib.dump(info,f)
PY
codesign --force --deep --sign - "$app"
printf '%s\n' "$app"
