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
# Ad-hoc signature. macOS ties Keychain "Always Allow" to the exact build unless the app has an Apple Team ID,
# and a self-signed certificate does not change that (tried 2026-11-10). So the app never reads the Keychain itself:
# it asks the jarvis-keys helper below, which is rebuilt only when its own source changes.
codesign --force --deep --sign "${JARVIS_SIGN_IDENTITY:--}" "$app"
# The Keychain helper is rebuilt only when its source changes: its exact build is what macOS remembers for
# "Always Allow", so leaving it alone is what stops the Keychain prompts after app rebuilds.
keys_src="Tools/jarvis-keys/main.swift"
keys_bin="$HOME/Library/Application Support/Jarvis/bin/jarvis-keys"
keys_want="$(shasum -a 256 "$keys_src" | cut -d' ' -f1)"
if [[ ! -x "$keys_bin" || "$(cat "$keys_bin.sha256" 2>/dev/null)" != "$keys_want" ]]; then
  mkdir -p "${keys_bin:h}"
  swiftc -O "$keys_src" -o "$keys_bin"
  print -r -- "$keys_want" > "$keys_bin.sha256"
  echo "Rebuilt the Keychain helper: macOS will ask once per saved key. Click Always Allow; it will not ask again after app rebuilds."
fi
printf '%s\n' "$app"
