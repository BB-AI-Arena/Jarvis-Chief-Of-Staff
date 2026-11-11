#!/bin/zsh
# The Keychain helper must refuse anything that is not one of Jarvis's own entries, and must not take a value from arguments.
# Nothing here reads or writes a real key.
set -u
tool="$1"
expect() { local want="$1"; shift; "$@" >/dev/null 2>&1 </dev/null; local got=$?; [[ $got -eq $want ]] || { echo "FAIL: $* exited $got, expected $want"; exit 1; } }
expect 2 "$tool"
expect 2 "$tool" get com.apple.something account
expect 2 "$tool" get "ai.fourfront.jarvis.claude; rm -rf" account
expect 2 "$tool" get ai.fourfront.jarvis.claude "bad account"
expect 2 "$tool" set ai.fourfront.jarvis.claude anthropic-api-key extra-value
expect 2 "$tool" dump ai.fourfront.jarvis.claude anthropic-api-key
expect 44 "$tool" get ai.fourfront.jarvis.no-such-entry nothing
echo "PASS: the Keychain helper only touches Jarvis's own entries and never takes a key from its arguments"
