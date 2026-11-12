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
assert(OllamaClient.base == "http://192.168.4.31:11434" && OllamaClient.local == "http://127.0.0.1:11434")
assert(OllamaClient.sanitizeHost("http://192.168.4.31:11434/") == "http://192.168.4.31:11434")
assert(OllamaClient.sanitizeHost("http://dark.local:8188") == "http://dark.local:8188")
for bad in ["https://evil.example.com:11434", "http://user:pw@192.168.4.31:11434", "http://192.168.4.31:11434/api?x=1", "ftp://192.168.4.31", "http://8.8.8.8"] { assert(OllamaClient.sanitizeHost(bad) == nil, bad) }
print("PASS: Projects talks to the 4090's Ollama by default and only accepts local-network model servers")
