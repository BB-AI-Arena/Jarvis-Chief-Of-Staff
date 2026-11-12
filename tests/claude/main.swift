import Foundation
assert(ClaudeClient.defaultModel == "claude-sonnet-5-5")
assert(ClaudeClient.sanitize("  claude-sonnet-5-5 \n") == "claude-sonnet-5-5")
assert(ClaudeClient.sanitize("claude-opus-5-5") == "claude-opus-5-5")
assert(ClaudeClient.sanitize("") == nil)
assert(ClaudeClient.sanitize("bad model") == nil)
assert(ClaudeClient.sanitize("claude/sonnet") == nil)
print("PASS: Claude model id defaults to the current Sonnet API id and rejects malformed ids")
let calls = ClaudeClient.toolCalls([["type": "text", "text": "Let me check."], ["type": "tool_use", "id": "toolu_1", "name": "lookup", "input": ["brief": "Neon boardroom"]]])
assert(calls.count == 1 && calls[0].id == "toolu_1" && calls[0].name == "lookup" && calls[0].brief == "Neon boardroom")
assert(ClaudeClient.toolCalls([["type": "text", "text": "No tools"]]).isEmpty)
print("PASS: Claude tool_use blocks are parsed into id, name and brief; text-only replies have no tool calls")
let uses = ClaudeClient.toolUses([["type": "text", "text": "Looking."], ["type": "tool_use", "id": "toolu_2", "name": "read_file", "input": ["path": "source/Package.swift", "start_line": 1]]])
assert(uses.count == 1 && uses[0].name == "read_file" && uses[0].input["path"] as? String == "source/Package.swift" && uses[0].input["start_line"] as? Int == 1)
assert(ClaudeClient.maxToolRounds == 8)
print("PASS: the CTO's tool calls carry their full input, with a bounded number of rounds")
let search = ClaudeClient.searchBody(model: "claude-sonnet-5-5", system: "SYS", messages: [["role": "user", "content": "Find competitors"]])
assert((search["tools"] as! [[String: Any]])[0]["type"] as? String == "web_search_20260209")
assert((search["tools"] as! [[String: Any]])[0]["max_uses"] as? Int == 5)
assert(search["fallbacks"] as? String == "default")
assert(ClaudeClient.searchBody(model: "claude-haiku-5-5", system: "S", messages: [])["fallbacks"] == nil)
let blocks: [[String: Any]] = [
    ["type": "server_tool_use", "id": "srv_1", "name": "web_search", "input": ["query": "handyman software"]],
    ["type": "web_search_tool_result", "tool_use_id": "srv_1", "content": []],
    ["type": "text", "text": "Jobber leads the market. ", "citations": [["type": "web_search_result_location", "url": "https://example.com/a", "title": "A", "cited_text": "Jobber"]]],
    ["type": "text", "text": "Housecall Pro is second.", "citations": [["type": "web_search_result_location", "url": "https://example.com/a"], ["type": "web_search_result_location", "url": "https://example.com/b"]]]
]
assert(ClaudeClient.searchReport(blocks) == "Jobber leads the market. Housecall Pro is second.\n\nSources:\n- https://example.com/a\n- https://example.com/b")
assert(ClaudeClient.searchReport([["type": "text", "text": "Plain answer."]]) == "Plain answer.")
let uncited: [[String: Any]] = [
    ["type": "web_search_tool_result", "tool_use_id": "srv_2", "content": [["type": "web_search_result", "url": "https://example.com/g2", "title": "G2"], ["type": "web_search_result", "url": "https://example.com/g2"], ["type": "web_search_result", "url": "https://example.com/capterra"]]],
    ["type": "text", "text": "Jobber and Housecall Pro."]]
assert(ClaudeClient.searchReport(uncited) == "Jobber and Housecall Pro.\n\nSources searched:\n- https://example.com/g2\n- https://example.com/capterra")
assert(ClaudeClient.searchReport([["type": "server_tool_use", "id": "x"]]) == nil)
print("PASS: Research can fall back to Claude with live web search, keeping the answer and its cited sources")
