import Foundation
assert(ClaudeClient.defaultModel == "claude-sonnet-5-5")
assert(ClaudeClient.sanitize("  claude-sonnet-5-5 \n") == "claude-sonnet-5-5")
assert(ClaudeClient.sanitize("claude-opus-5-5") == "claude-opus-5-5")
assert(ClaudeClient.sanitize("") == nil)
assert(ClaudeClient.sanitize("bad model") == nil)
assert(ClaudeClient.sanitize("claude/sonnet") == nil)
print("PASS: Claude model id defaults to the current Sonnet API id and rejects malformed ids")
