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
