import Foundation
assert(OllamaClient.sanitize(" gemma4:latest \n") == "gemma4:latest")
assert(OllamaClient.sanitize("library/qwen3:8b") == "library/qwen3:8b")
assert(OllamaClient.sanitize("") == nil)
assert(OllamaClient.sanitize("bad model") == nil)
assert(OllamaClient.sanitize("../etc:x") == nil)
let body = OllamaClient.requestBody("Plan it", model: "gemma4:latest", system: "SYS")
assert(body["model"] as? String == "gemma4:latest" && body["stream"] as? Bool == false)
let messages = body["messages"] as! [[String: String]]
assert(messages[0] == ["role": "system", "content": "SYS"] && messages[1] == ["role": "user", "content": "Plan it"])
assert(OllamaClient.text(from: Data("{\"message\":{\"role\":\"assistant\",\"content\":\" Three milestones. \"}}".utf8)) == "Three milestones.")
assert(OllamaClient.text(from: Data("{\"message\":{\"content\":\"\"}}".utf8)) == nil)
assert(OllamaClient.text(from: Data("{\"error\":\"model not found\"}".utf8)) == nil)
print("PASS: the Projects seat sends a local Ollama chat body and reads only real replies")
