import Foundation

/// SSH access to Brandon's GPU server "DARK" (RTX 4090), so the board can use it: GPU status, starting ComfyUI, and
/// running its commands. Uses a dedicated key (~/.ssh/jarvis_dark) with BatchMode, so it never asks for or stores a password.
/// Settings live in ~/Library/Application Support/Jarvis/dark.json; every field has a default.
struct DarkServer {
    var host = "192.168.4.31"
    var user = "bradshaw"
    var key = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/jarvis_dark").path
    /// Shell command on DARK that starts ComfyUI listening on the network, e.g.
    /// "cd ~/ComfyUI && nohup ./venv/bin/python main.py --listen 0.0.0.0 --port 8188 > ~/comfyui.log 2>&1 &". Empty until known.
    var comfyStart = ""

    static func load(support: URL) -> DarkServer {
        var server = DarkServer()
        guard let data = try? Data(contentsOf: support.appendingPathComponent("dark.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return server }
        if let host = json["host"] as? String, sanitizeHost(host) { server.host = host }
        if let user = json["user"] as? String, user.range(of: "^[a-z_][a-z0-9_-]{0,31}$", options: .regularExpression) != nil { server.user = user }
        if let key = json["key"] as? String, key.hasPrefix("/") { server.key = key }
        if let start = json["comfyStart"] as? String { server.comfyStart = String(start.prefix(1000)) }
        return server
    }
    func save(support: URL) {
        let json: [String: Any] = ["host": host, "user": user, "key": key, "comfyStart": comfyStart]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: support.appendingPathComponent("dark.json"), options: .atomic) }
    }
    static func sanitizeHost(_ host: String) -> Bool { host.range(of: "^[A-Za-z0-9.-]{1,253}$", options: .regularExpression) != nil }
    var hasKey: Bool { FileManager.default.fileExists(atPath: key) }
    var publicKey: String { key + ".pub" }
    var target: String { user + "@" + host }

    /// The command line a director's worker uses to run something on DARK (same options as `arguments`).
    var sshCommand: String { "ssh -i '\(key)' -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \(target)" }
    /// ssh arguments: key only, no password prompts, no agent forwarding, short connect timeout.
    func arguments(_ command: String) -> [String] {
        ["-i", key, "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=accept-new",
         "-o", "ForwardAgent=no", "-o", "ServerAliveInterval=15", target, command]
    }
    /// Runs one command on DARK. Completion (main queue) gets the exit code and combined output (last 20 KB).
    func run(_ command: String, timeout: TimeInterval = 120, completion: @escaping (Int32, String) -> Void) {
        guard hasKey else { DispatchQueue.main.async { completion(255, "No SSH key for DARK yet. Use Settings → Connect DARK… once.") }; return }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments(command)
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        var output = Data()
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock(); output.append(chunk); if output.count > 200_000 { output.removeFirst(output.count - 200_000) }; lock.unlock()
        }
        process.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            lock.lock(); let text = String(decoding: output.suffix(20_000), as: UTF8.self); lock.unlock()
            DispatchQueue.main.async { completion(process.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        do { try process.run() } catch { DispatchQueue.main.async { completion(255, "ssh could not start: \(error.localizedDescription)") }; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
    }
    static let gpuQuery = "nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits"
    /// "NVIDIA GeForce RTX 4090 · 1.2 / 24.0 GB VRAM · 3% busy · 41 °C" from one nvidia-smi CSV line.
    static func describeGPU(_ csv: String) -> String? {
        let fields = (csv.split(separator: "\n").first ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 5, let used = Double(fields[1]), let total = Double(fields[2]) else { return nil }
        return String(format: "%@ · %.1f / %.1f GB VRAM · %@%% busy · %@ °C", fields[0], used / 1024, total / 1024, fields[3], fields[4])
    }
    /// Starts ComfyUI if it is not answering, then waits up to 90 s for it. Completion gets whether it is answering.
    func ensureComfy(server: String, completion: @escaping (Bool, String) -> Void) {
        ComfyVideo.reachable(server) { up in
            if up { completion(true, "ComfyUI already running"); return }
            guard self.hasKey else { completion(false, "ComfyUI is not reachable and Jarvis has no SSH key for DARK yet"); return }
            guard !self.comfyStart.isEmpty else { completion(false, "ComfyUI is not reachable and no start command is saved for DARK"); return }
            self.run(self.comfyStart, timeout: 30) { code, output in
                guard code == 0 else { completion(false, "Starting ComfyUI on DARK failed (exit \(code)): " + String(output.suffix(200))); return }
                func poll(_ left: Int) {
                    ComfyVideo.reachable(server) { up in
                        if up { completion(true, "Started ComfyUI on DARK"); return }
                        guard left > 0 else { completion(false, "Started ComfyUI on DARK, but it did not answer within 90 s"); return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { poll(left - 1) }
                    }
                }
                poll(18)
            }
        }
    }
}

/// The "run_on_dark" tool the directors call. Their models run at Anthropic, xAI or in Ollama and cannot reach Brandon's
/// network; Jarvis runs the command on DARK over his own key and hands the output back. Destructive commands are refused
/// (a guard against mistakes, not a security boundary: the commands still run as bradshaw).
enum DarkTool {
    static let name = "run_on_dark"
    static let description = "Run one shell command on DARK, Brandon's GPU server on the home network: Ubuntu, NVIDIA RTX 4090 (24 GB), 64 GB RAM, ComfyUI in ~/ComfyUI (port 8188, models in ~/ComfyUI/models), Ollama (port 11434), Docker. It runs as user bradshaw over SSH and returns the exit code and the last 12,000 characters of output. Use it to check the GPU (nvidia-smi), list files, models and logs, inspect containers, query Ollama or ComfyUI, or run jobs. Commands that delete files, use sudo, reboot, or change the firewall, users or SSH keys are refused."
    static let schema: [String: Any] = ["type": "object", "properties": [
        "command": ["type": "string", "description": "The shell command to run on DARK, for example: nvidia-smi"],
        "timeout_seconds": ["type": "integer", "description": "How long to wait, 5 to 600 seconds. Default 120."]
    ], "required": ["command"]]
    /// Claude tool format.
    static var anthropic: [String: Any] { ["name": name, "description": description, "input_schema": schema] }
    /// OpenAI-style function format (Grok chat, Ollama).
    static var function: [String: Any] { ["type": "function", "function": ["name": name, "description": description, "parameters": schema]] }
    /// Responses API function format (Grok with live web search).
    static var responsesFunction: [String: Any] { ["type": "function", "name": name, "description": description, "parameters": schema] }
    /// Plain words for the system prompt.
    static let promptNote = "You can run shell commands on DARK, Brandon's RTX 4090 server, with the run_on_dark tool whenever it helps the task: check the GPU, files, models, logs, ComfyUI, Ollama or containers, or run jobs. Report what you ran and what came back. Deleting files, sudo, reboots and firewall, user or SSH key changes are refused."

    private static let blocked: [(pattern: String, reason: String)] = [
        ("\\b(sudo|doas)\\b|(^|[;&|]\\s*)su(\\s|$)", "uses sudo or su"),
        ("\\b(rm|rmdir|shred|unlink|truncate|srm)\\b|\\s-delete\\b", "deletes files"),
        ("\\b(reboot|shutdown|poweroff|halt)\\b|\\binit\\s+[06]\\b|\\bsystemctl\\s+(stop|disable|mask|kill|poweroff|reboot|halt|isolate)\\b", "stops or restarts the machine or its services"),
        ("\\b(ufw|iptables|ip6tables|nft|firewall-cmd)\\b", "changes the firewall"),
        ("\\b(useradd|userdel|usermod|adduser|deluser|passwd|chpasswd|visudo|groupadd|groupdel)\\b", "changes users"),
        ("authorized_keys|\\.ssh(/|\\b)|\\bssh-keygen\\b", "touches SSH keys"),
        ("\\b(mkfs[.a-z0-9]*|fdisk|sfdisk|parted|wipefs|mkswap)\\b|\\bdd\\b|>\\s*/dev/(sd|nvme|disk)", "writes to disks"),
        (":\\(\\)\\s*\\{", "is a fork bomb"),
        ("\\bkill(all)?\\b[^;&|]*\\s-?(9\\s+)?1(\\s|$)|\\bpkill\\s+-9\\s+(systemd|sshd)", "kills system processes"),
        ("\\bdocker\\s+(system|volume|image|container)\\s+prune\\b|\\bdocker\\s+rmi?\\b", "deletes containers or images"),
        ("\\bchmod\\s+-r\\b|\\bchown\\s+-r\\b", "changes permissions recursively"),
        ("\\bcurl\\b[^|]*\\|\\s*(sudo\\s+)?(ba|z)?sh\\b|\\bwget\\b[^|]*\\|\\s*(ba|z)?sh\\b", "pipes a download into a shell")
    ]
    /// True when a task is about DARK or what runs on it, so the tool is worth offering.
    static func relevant(_ task: String) -> Bool {
        let lower = task.lowercased()
        return ["dark", "4090", "gpu", "vram", "comfy", "ollama", "the server", "my server", "192.168.", "ssh", "docker", "render", "nvidia", "checkpoint", "workflow"].contains { lower.contains($0) }
    }
    /// Why a command is refused, or nil when it may run.
    static func refusal(_ command: String) -> String? {
        let text = command.lowercased().replacingOccurrences(of: "--rm", with: " ")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "the command is empty" }
        guard command.count <= 4000 else { return "the command is too long" }
        return blocked.first { text.range(of: $0.pattern, options: .regularExpression) != nil }?.reason
    }
    /// Runs a tool call on DARK and returns the text the model sees.
    static func run(_ input: [String: Any], dark: DarkServer, completion: @escaping (String) -> Void) {
        let command = ((input["command"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason = refusal(command) { completion("Refused: this command \(reason). Nothing was run on DARK. Ask Brandon if it is really needed."); return }
        let seconds = (input["timeout_seconds"] as? Int) ?? (input["timeout_seconds"] as? Double).map { Int($0) } ?? 120
        dark.run(command, timeout: TimeInterval(min(max(seconds, 5), 600))) { code, output in
            let body = output.isEmpty ? "(no output)" : String(output.suffix(12_000))
            completion("exit \(code)\n" + body)
        }
    }
    /// Parses a function call's JSON arguments string.
    static func arguments(_ raw: Any?) -> [String: Any] {
        if let object = raw as? [String: Any] { return object }
        guard let text = raw as? String, let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
}
