import Foundation
import AVFoundation

/// Renders one shot to a local .mp4. Completion gets the file, or nil and a plain reason. Calls back on the main queue.
protocol ShotRenderer {
    func render(_ shot: VideoPlan.Shot, to file: URL, isCancelled: @escaping () -> Bool, completion: @escaping (URL?, String?) -> Void)
}

private func onMain(_ work: @escaping () -> Void) { DispatchQueue.main.async(execute: work) }
private func download(_ url: URL, to file: URL, completion: @escaping (Bool) -> Void) {
    URLSession.shared.downloadTask(with: url) { temp, response, _ in
        let ok = (response as? HTTPURLResponse)?.statusCode == 200 && temp != nil
        if ok, let temp {
            try? FileManager.default.removeItem(at: file)
            let moved = (try? FileManager.default.moveItem(at: temp, to: file)) != nil
            onMain { completion(moved) }
        } else { onMain { completion(false) } }
    }.resume()
}

/// xAI Grok Imagine (docs.x.ai video generation, read 2026-11-11): POST /v1/videos/generations → request_id,
/// then GET /v1/videos/{request_id} until status is done (video.url, a temporary URL) or failed.
struct GrokVideo: ShotRenderer {
    let apiKey: String
    var model = VideoPlan.grokModel
    var resolution = "1080p"
    var aspect = "16:9"
    /// Reference-to-video guides subjects without fixing the opening frame. Kept opt-in by callers.
    var referenceImages: [String] = []
    static func body(_ shot: VideoPlan.Shot, model: String, resolution: String, aspect: String, referenceImages: [String] = []) -> [String: Any] {
        var body: [String: Any] = ["model": model, "prompt": shot.prompt, "duration": shot.seconds, "resolution": referenceImages.isEmpty ? resolution : "720p", "aspect_ratio": aspect]
        if !referenceImages.isEmpty { body["reference_images"] = referenceImages.prefix(14).map { ["url": $0] } }
        return body
    }
    /// (status, video URL, error message) from a poll response.
    static func poll(_ data: Data) -> (status: String, url: URL?, error: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let status = json["status"] as? String else { return nil }
        let url = ((json["video"] as? [String: Any])?["url"] as? String).flatMap(URL.init(string:))
        let error = (json["error"] as? [String: Any])?["message"] as? String
        return (status, url, error)
    }
    private func request(_ path: String, body: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1" + path)!)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }
    func render(_ shot: VideoPlan.Shot, to file: URL, isCancelled: @escaping () -> Bool, completion: @escaping (URL?, String?) -> Void) {
        // Owner policy: every video is rendered by local models on DARK's RTX 4090.
        // Retain legacy response parsers for saved history, but never launch a cloud video.
        onMain { completion(nil, "Cloud video rendering is disabled. Video must render locally on DARK RTX 4090.") }
    }

    private func wait(_ id: String, file: URL, started: Date, isCancelled: @escaping () -> Bool, completion: @escaping (URL?, String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if isCancelled() { return }
            guard Date().timeIntervalSince(started) < 900 else { completion(nil, "Grok Imagine took longer than 15 minutes on one shot."); return }
            URLSession.shared.dataTask(with: self.request("/videos/" + id)) { data, _, _ in
                let state = data.flatMap(GrokVideo.poll)
                onMain {
                    switch state?.status {
                    case "done":
                        guard let url = state?.url else { completion(nil, "Grok Imagine finished without a video link."); return }
                        download(url, to: file) { ok in completion(ok ? file : nil, ok ? nil : "The finished shot could not be downloaded.") }
                    case "failed": completion(nil, "Grok Imagine failed the shot: " + (state?.error ?? "no reason given"))
                    case "expired": completion(nil, "Grok Imagine's job expired before it finished.")
                    default: self.wait(id, file: file, started: started, isCancelled: isCancelled, completion: completion)
                    }
                }
            }.resume()
        }
    }
}

/// ComfyUI on the 4090. Uses ComfyUI's HTTP API (POST /prompt, GET /history/{id}, GET /view) with a workflow Brandon exported
/// in API format, where "{{prompt}}" marks the positive prompt and "{{frames}}" / "{{seed}}" mark the length and seed.
struct ComfyVideo: ShotRenderer {
    let server: String
    let workflow: [String: Any]
    /// ComfyUI sends live progress over its websocket to this client id (see ComfyMonitor).
    var clientID = "jarvis"
    var artwork: [VideoArtwork.Reference] = []
    var artworkIndex = 0
    /// Called on the main queue with the shot's ComfyUI prompt id once the job is queued.
    var onQueued: ((String) -> Void)? = nil
    static let defaultServer = "http://192.168.4.31:8188"
    /// Removes Jarvis's waiting jobs from the queue and interrupts the running one only if it is Jarvis's.
    static func cancel(server: String, promptIDs: [String]) {
        guard !promptIDs.isEmpty, let queueURL = URL(string: server + "/queue") else { return }
        func post(_ path: String, _ body: [String: Any]) {
            var request = URLRequest(url: URL(string: server + path)!)
            request.httpMethod = "POST"; request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request).resume()
        }
        post("/queue", ["delete": promptIDs])
        URLSession.shared.dataTask(with: queueURL) { data, _, _ in
            let running = ((data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["queue_running"] as? [[Any]]) ?? []
            if running.contains(where: { $0.count > 1 && promptIDs.contains(($0[1] as? String) ?? "") }) { post("/interrupt", [:]) }
        }.resume()
    }
    static func reachable(_ server: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: server + "/system_stats") else { completion(false); return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            onMain { completion(ok) }
        }.resume()
    }
    func render(_ shot: VideoPlan.Shot, to file: URL, isCancelled: @escaping () -> Bool, completion: @escaping (URL?, String?) -> Void) {
        let graph: [String: Any]
        if !artwork.isEmpty {
            guard let conditioned = VideoArtwork.conditioned(workflow, image: artwork[artworkIndex % artwork.count].image) else {
                completion(nil, "The ComfyUI workflow does not support artwork conditioning. No text-only fallback was used."); return
            }
            graph = conditioned
        } else { graph = workflow }
        let filled = VideoPlan.fill(graph, prompt: shot.prompt, frames: VideoPlan.frames(seconds: shot.seconds, fps: VideoPlan.fps(in: workflow)), seconds: shot.seconds, seed: Int.random(in: 1...999_999_999))
        var request = URLRequest(url: URL(string: server + "/prompt")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": filled, "client_id": clientID])
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard status == 200, let id = json?["prompt_id"] as? String else {
                let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
                onMain { completion(nil, "ComfyUI did not accept the workflow (HTTP \(status))" + (message.isEmpty ? "" : ": " + String(message.prefix(160)))) }
                return
            }
            if let onQueued = self.onQueued { onMain { onQueued(id) } }
            self.wait(id, file: file, started: Date(), isCancelled: isCancelled, completion: completion)
        }.resume()
    }
    private func wait(_ id: String, file: URL, started: Date, isCancelled: @escaping () -> Bool, completion: @escaping (URL?, String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if isCancelled() { return }
            guard Date().timeIntervalSince(started) < 1800 else { completion(nil, "The 4090 took longer than 30 minutes on one shot."); return }
            URLSession.shared.dataTask(with: URL(string: self.server + "/history/" + id)!) { data, _, _ in
                let entry = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?[id] as? [String: Any]
                onMain {
                    guard let entry else { self.wait(id, file: file, started: started, isCancelled: isCancelled, completion: completion); return }
                    if (entry["status"] as? [String: Any])?["status_str"] as? String == "error" { completion(nil, "ComfyUI reported an error while rendering the shot."); return }
                    guard let output = VideoPlan.comfyOutput(entry) else {
                        if (entry["status"] as? [String: Any])?["completed"] as? Bool == true { completion(nil, "ComfyUI finished but the workflow saved no video file.") }
                        else { self.wait(id, file: file, started: started, isCancelled: isCancelled, completion: completion) }
                        return
                    }
                    var parts = URLComponents(string: self.server + "/view")!
                    parts.queryItems = [URLQueryItem(name: "filename", value: output.filename), URLQueryItem(name: "subfolder", value: output.subfolder), URLQueryItem(name: "type", value: output.type)]
                    download(parts.url!, to: file) { ok in completion(ok ? file : nil, ok ? nil : "The finished shot could not be downloaded from the 4090.") }
                }
            }.resume()
        }
    }
}

/// Listens to ComfyUI's websocket (/ws?clientId=…) for the live events it sends about Jarvis's jobs:
/// execution_start, executing (which node; nil node = finished), progress (sampler step of max). Reconnects until stopped.
final class ComfyMonitor {
    struct Event: Equatable { let type: String; let promptID: String; let node: String?; let value: Int?; let max: Int? }
    let server: String, clientID: String
    var onEvent: (Event) -> Void = { _ in }
    private var socket: URLSessionWebSocketTask?
    private var stopped = false
    init(server: String, clientID: String) { self.server = server; self.clientID = clientID }
    func start() {
        guard !stopped, var parts = URLComponents(string: server + "/ws") else { return }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.queryItems = [URLQueryItem(name: "clientId", value: clientID)]
        guard let url = parts.url else { return }
        socket = URLSession.shared.webSocketTask(with: url)
        socket?.maximumMessageSize = 8 << 20
        socket?.resume()
        receive()
    }
    func stop() { stopped = true; socket?.cancel(with: .normalClosure, reason: nil); socket = nil }
    private func receive() {
        socket?.receive { [weak self] result in
            guard let self, !self.stopped else { return }
            switch result {
            case .success(.string(let text)):
                if let event = ComfyMonitor.parse(text) { onMain { if !self.stopped { self.onEvent(event) } } }
                self.receive()
            case .success: self.receive()   // binary preview frames
            case .failure: DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.start() }
            }
        }
    }
    static func parse(_ text: String) -> Event? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], let type = json["type"] as? String,
              ["execution_start", "executing", "progress", "execution_error", "execution_success"].contains(type),
              let data = json["data"] as? [String: Any], let prompt = data["prompt_id"] as? String else { return nil }
        let node = (data["node"] as? String) ?? (data["node"] as? Int).map(String.init)
        return Event(type: type, promptID: prompt, node: node, value: data["value"] as? Int, max: data["max"] as? Int)
    }
}

/// Joins the shots into one .mp4 with AVFoundation (no ffmpeg needed). Keeps each clip's sound when it has any.
enum VideoStitcher {
    /// A small JPEG (data URL) from the middle of a clip, for the Studio card.
    static func thumbnail(_ clip: URL, completion: @escaping (String?) -> Void) {
        Task {
            let asset = AVURLAsset(url: clip)
            let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 320)
            var url: String?
            if let (image, _) = try? await generator.image(at: CMTime(seconds: max(seconds / 2, 0), preferredTimescale: 600)) {
                let data = NSMutableData()
                if let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
                    if CGImageDestinationFinalize(dest) { url = "data:image/jpeg;base64," + (data as Data).base64EncodedString() }
                }
            }
            onMain { completion(url) }
        }
    }
    static func join(_ clips: [URL], to output: URL, completion: @escaping (Bool) -> Void) {
        Task {
            let ok = await join(clips, to: output)
            onMain { completion(ok) }
        }
    }
    static func join(_ clips: [URL], to output: URL) async -> Bool {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return false }
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var hasAudio = false
        for clip in clips {
            let asset = AVURLAsset(url: clip)
            guard let duration = try? await asset.load(.duration), let source = try? await asset.loadTracks(withMediaType: .video).first else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            do { try video.insertTimeRange(range, of: source, at: cursor) } catch { continue }
            if cursor == .zero, let transform = try? await source.load(.preferredTransform) { video.preferredTransform = transform }
            if let sound = try? await asset.loadTracks(withMediaType: .audio).first, let audio {
                try? audio.insertTimeRange(range, of: sound, at: cursor)
                hasAudio = true
            }
            cursor = cursor + duration
        }
        if !hasAudio, let audio { composition.removeTrack(audio) }
        guard cursor > .zero, let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return false }
        try? FileManager.default.removeItem(at: output)
        do { try await export.export(to: output, as: .mp4) } catch { return false }
        return FileManager.default.fileExists(atPath: output.path)
    }
}
