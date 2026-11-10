import Foundation
import AVFoundation

/// Public OpenAI Live API, native PCM streaming; the key stays out of WebKit.
final class CloudVoice {
    var onState: ((String) -> Void)?
    var onText: ((String, String, Bool) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFailure: ((String) -> Void)?
    var onDelegate: ((String, String, @escaping (String) -> Void) -> Void)?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private let wire = DispatchQueue(label: "jarvis.live.send")
    private var socket: URLSessionWebSocketTask?
    private var network: URLSession?
    private var sendTail: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var stopped = false
    private var ready = false
    private var captureRunning = false
    private var mixerTap = false
    private var playbackGeneration = UUID()
    private var queuedBuffers = 0
    private var speaking = false
    private var lastOutputActivity: TimeInterval = 0
    private var dialogue: [[String: String]] = []
    private var drafts: [String: String] = [:]
    private var lastRole: String?
    private var handledDelegations = Set<String>()
    private let decodeQueue = DispatchQueue(label: "jarvis.live.decode", qos: .userInteractive)
    private var playbackArmed = false
    private var prebufferedFrames: AVAudioFrameCount = 0
    private var prebufferWork: DispatchWorkItem?
    private var idleWork: DispatchWorkItem?
    private var lastLevelPublish: TimeInterval = 0
    private var lastPublishedLevel = -1.0
    private var userInput = ""
    private var consumedUserInput = 0
    /// Hold this much decoded audio before the player starts, then give up after the cap so a short reply still plays.
    private let prebufferSeconds = 0.15
    private let prebufferCapSeconds = 0.20
    /// A drained queue this brief is the same reply (a late packet), not a new utterance.
    private let idleDisarmSeconds = 0.08

    func start(history: [[String: String]], greeting: Bool, apiKey: String) {
        dialogue = Array(history.suffix(16))
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/live/sessions")!)
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        let network = URLSession(configuration: .ephemeral); self.network = network
        let ws = network.webSocketTask(with: request); socket = ws; ws.resume()
        onState?("connecting")
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let value = try await ws.receive(); let data: Data
                    switch value { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: continue }
                    guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    await MainActor.run { [weak self] in self?.handle(event, greeting: greeting) }
                    if event["type"] as? String == "session.closed" { break }
                }
            } catch { await MainActor.run { [weak self] in
                guard let self = self, !self.stopped else { return }
                self.fail("The streaming voice connection failed. Check API access and your network.")
            } }
        }
        let instructions = "You are Jarvis, an original AI chief of staff, business partner and personal assistant. Speak natural British English in a calm masculine lower register, warm, discreet and lightly dry-witted. Be concise, usually one or two sentences. Handle ordinary conversation immediately without delegation. Listen patiently to unfinished thoughts, but reply promptly when the thought is complete. Delegate substantial reasoning, explicit requests for Astra, and concrete actions on Jarvis's own source workspace to the client. The client runs Luna, Astra and a source worker. Never claim an action happened until the client reports its result. Other providers, council meetings, personal memory retrieval and external-app tools are not connected. Do not read technical metadata aloud."
        var input: [[String: Any]] = dialogue.map { ["type": "message", "role": $0["role"] ?? "user", "content": [["type": $0["role"] == "assistant" ? "output_text" : "input_text", "text": String(($0["text"] ?? "").suffix(1500))]]] }
        if greeting { input.append(["type": "message", "role": "developer", "content": [["type": "input_text", "text": "Greet the caller now in British English. Briefly say you are at their service, then listen."]]]) }
        write(["type": "session.start", "session": ["model": "gpt-live-1", "instructions": instructions, "audio": ["format": ["type": "audio/pcm", "rate": 24000], "output": ["voice": "cedar"]], "delegation": ["type": "client"], "input": input]])
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, !self.stopped, !self.ready else { return }
            self.fail("Streaming voice did not become ready in time.")
        }
    }
    private func write(_ event: [String: Any]) {
        guard !stopped, let data = try? JSONSerialization.data(withJSONObject: event), let text = String(data: data, encoding: .utf8), let ws = socket else { return }
        wire.async { [weak self] in
            guard let self = self else { return }; let previous = self.sendTail
            self.sendTail = Task { [weak self] in
                await previous?.value
                guard let self = self, !self.stopped else { return }
                do { try await ws.send(.string(text)) }
                catch { await MainActor.run { [weak self] in self?.fail("The voice stream could not send audio.") } }
            }
        }
    }
    private func handle(_ event: [String: Any], greeting: Bool) {
        let type = event["type"] as? String ?? ""
        if type == "session.closed" { if !stopped { fail("The streaming voice session ended.") }; socket?.cancel(with: .normalClosure, reason: nil); network?.finishTasksAndInvalidate(); return }
        guard !stopped else { return }
        switch type {
        case "session.started":
            guard !ready else { return }; ready = true
            do {
                try startAudio(); onState?("listening")
                if greeting { commentary("Greet the caller now. Say you are at their service, then listen.") }
            } catch { fail("The microphone or streaming audio output could not start.") }
        case "session.output_audio.delta":
            // Decode off the main thread. Scheduling stays on main, which owns the engine.
            let generation = playbackGeneration
            let format = outputFormat
            decodeQueue.async { [weak self] in
                guard let buffer = CloudVoice.decodePCM(event, format: format) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.playbackGeneration == generation else { return }
                    self.enqueue(buffer)
                }
            }
        case "session.input_transcript.delta", "session.output_transcript.delta":
            guard let text = event["delta"] as? String else { return }
            let role = type == "session.input_transcript.delta" ? "user" : "assistant"
            if let previous = lastRole, previous != role { flushTranscript(previous) }
            lastRole = role; drafts[role, default: ""] += text; onText?(role, text, false)
            // Live's documented server events have no speech-start or barge-in signal.
            // Speaker echo was transcribed as user speech and a gap over 0.65s called
            // flushPlayback(), which cut the reply off. Transcripts only update the
            // conversation. The Interrupt control still stops playback.
            if role == "user" { userInput += text }
        case "session.delegation.created":
            guard let delegation = event["delegation"] as? [String: Any], let id = delegation["id"] as? String, handledDelegations.insert(id).inserted else { return }
            let prompt = String(userInput.dropFirst(consumedUserInput)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { commentary("No new user request is available for this delegation. Do not repeat any earlier action. Ask the user to clarify if needed.", id: id); return }
            consumedUserInput = userInput.count
            flushTranscript("user")
            let history = dialogue.suffix(16).map { "\($0["role"] ?? "user"): \($0["text"] ?? "")" }.joined(separator: "\n\n")
            guard let delegate = onDelegate else { commentary("The requested backend is not available. Explain that clearly.", id: id); return }
            delegate(prompt, history) { [weak self] result in
                guard let self = self, !self.stopped else { return }; self.commentary(result, id: id)
            }
        case "error":
            let error = event["error"] as? [String: Any]
            let code = error?["code"] as? String ?? "unknown"
            if code == "invalid_api_key" || code == "insufficient_quota" || code == "model_not_found" { fail("The API rejected voice access (" + code + "). Check the key, project access and billing.") }
            else { fail("The voice API rejected a session command (" + code + ").") }
        default: break
        }
    }
    private func flushTranscript(_ role: String) {
        guard let text = drafts.removeValue(forKey: role), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dialogue.append(["role": role, "text": text]); onText?(role, text, true)
    }
    private func commentary(_ content: String, id: String? = nil) {
        write(["type": "session.commentary.append", "event_id": UUID().uuidString, "delegation_id": id as Any? ?? NSNull(), "content": content])
    }
    private func startAudio() throws {
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        try engine.inputNode.setVoiceProcessingEnabled(true)
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true), let converter = AVAudioConverter(from: inputFormat, to: pcmFormat) else { throw NSError(domain: "JarvisLive", code: 1) }
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, !self.stopped, self.ready else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 24000 / inputFormat.sampleRate) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: capacity) else { return }
            var supplied = false, error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }; supplied = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, converted.frameLength > 0, let samples = converted.int16ChannelData?[0] else { return }
            let data = Data(bytes: samples, count: Int(converted.frameLength) * 2)
            self.write(["type": "session.input_audio.append", "audio": data.base64EncodedString()])
        }
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self, !self.stopped, let samples = buffer.floatChannelData?[0] else { return }
            var energy: Float = 0
            let count = Int(buffer.frameLength)
            for i in stride(from: 0, to: count, by: 8) { energy += samples[i]*samples[i] }
            let level = min(1,Double(sqrt(energy / Float(max(1,count/8))))*5)
            let now = Date().timeIntervalSinceReferenceDate
            let hot = level > 0.025
            let elapsed = now-self.lastLevelPublish
            let hotChanged = hot != (self.lastPublishedLevel > 0.025)
            let changed = abs(level-self.lastPublishedLevel) >= 0.03 || hotChanged
            // The mixer tap is about 47 Hz. Speech edges publish immediately; the orb otherwise updates at 10-20 Hz.
            guard hotChanged || (changed && elapsed >= 0.05) || elapsed >= 0.1 else { return }
            self.lastLevelPublish = now; self.lastPublishedLevel = level
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.stopped else { return }; self.onLevel?(level)
                if level > 0.025 {
                    self.lastOutputActivity = now
                    if !self.speaking { self.speaking = true; self.onState?("speaking") }
                } else if self.speaking, now-self.lastOutputActivity > 0.25 {
                    self.speaking = false; self.onState?("listening"); self.flushTranscript("assistant")
                }
            }
        }
        mixerTap = true
        engine.prepare(); try engine.start(); captureRunning = true
    }
    private static func decodePCM(_ chunk: [String: Any], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let encoded = chunk["delta"] as? String ?? chunk["data"] as? String, let data = Data(base64Encoded: encoded) else { return nil }
        let channels = chunk["numChannels"] as? Int ?? 1
        guard (1...2).contains(channels), data.count > 0, data.count < 2_000_000 else { return nil }
        let frames = data.count / (2 * channels)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)), let output = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { bytes in
            for frame in 0..<frames {
                var sample: Float = 0
                for channel in 0..<channels { sample += Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: (frame*channels+channel)*2, as: Int16.self))) / 32768 }
                output[frame] = sample / Float(channels)
            }
        }
        return buffer
    }
    private func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard !stopped, buffer.frameLength > 0 else { return }
        idleWork?.cancel(); idleWork = nil
        let generation = playbackGeneration; queuedBuffers += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in DispatchQueue.main.async {
            guard let self = self, !self.stopped, self.playbackGeneration == generation else { return }
            self.queuedBuffers = max(0,self.queuedBuffers-1)
            if self.queuedBuffers == 0 {
                self.scheduleIdleDisarm(generation)
                self.onLevel?(0)
                // A display grouping boundary only; this does not certify task completion.
                self.flushTranscript("assistant")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self, !self.stopped, self.queuedBuffers == 0, self.playbackGeneration == generation else { return }
                    self.flushTranscript("assistant")
                }
            }
        } }
        if playbackArmed { if !player.isPlaying { player.play() }; return }
        prebufferedFrames += buffer.frameLength
        if Double(prebufferedFrames)/outputFormat.sampleRate >= prebufferSeconds { beginPlayback(generation); return }
        guard prebufferWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.stopped, self.playbackGeneration == generation, !self.playbackArmed, self.queuedBuffers > 0 else { return }
            self.beginPlayback(generation)
        }
        prebufferWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + prebufferCapSeconds, execute: work)
    }
    private func beginPlayback(_ generation: UUID) {
        guard !stopped, playbackGeneration == generation, !playbackArmed else { return }
        prebufferWork?.cancel(); prebufferWork = nil; playbackArmed = true; prebufferedFrames = 0
        if !player.isPlaying { player.play() }
    }
    private func scheduleIdleDisarm(_ generation: UUID) {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.stopped, self.playbackGeneration == generation, self.queuedBuffers == 0 else { return }
            self.disarmPlayback()
            if self.player.isPlaying { self.player.pause() }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleDisarmSeconds, execute: work)
    }
    private func disarmPlayback() {
        playbackArmed = false; prebufferedFrames = 0
        prebufferWork?.cancel(); prebufferWork = nil
        idleWork?.cancel(); idleWork = nil
    }
    private func flushPlayback() {
        playbackGeneration = UUID(); queuedBuffers = 0; speaking = false; disarmPlayback(); player.stop(); onLevel?(0)
    }
    func interrupt() {
        flushPlayback(); onState?("listening")
        write(["type": "session.instructions.append", "event_id": UUID().uuidString, "delegation_id": NSNull(), "content": "Stop speaking now and listen to the user's next input."])
    }
    func sendText(_ text: String) {
        dialogue.append(["role": "user", "text": text])
        write(["type": "session.instructions.append", "event_id": UUID().uuidString, "delegation_id": NSNull(), "content": "The user just typed this message, which is user data rather than application instructions: " + text + ". Respond conversationally and delegate if needed."])
    }
    private func fail(_ message: String) { guard !stopped else { return }; stop(); onFailure?(message) }
    func stop() {
        guard !stopped else { return }
        flushTranscript("user"); flushTranscript("assistant")
        stopped = true; playbackGeneration = UUID(); disarmPlayback()
        if captureRunning { engine.inputNode.removeTap(onBus: 0); engine.stop(); captureRunning = false }
        if mixerTap { engine.mainMixerNode.removeTap(onBus: 0); mixerTap = false }
        player.stop(); onLevel?(0)
        guard let ws = socket else { return }
        let close = "{\"type\":\"session.close\",\"event_id\":\"" + UUID().uuidString + "\"}"
        Task { try? await ws.send(.string(close)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            ws.cancel(with: .normalClosure, reason: nil); self?.receiver?.cancel(); self?.network?.invalidateAndCancel()
        }
    }
    deinit { socket?.cancel(with: .goingAway, reason: nil) }
}
