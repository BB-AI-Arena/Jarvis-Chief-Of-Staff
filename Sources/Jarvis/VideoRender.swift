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
    static func body(_ shot: VideoPlan.Shot, model: String, resolution: String, aspect: String) -> [String: Any] {
        ["model": model, "prompt": shot.prompt, "duration": shot.seconds, "resolution": resolution, "aspect_ratio": aspect]
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
        URLSession.shared.dataTask(with: request("/videos/generations", body: GrokVideo.body(shot, model: model, resolution: resolution, aspect: aspect))) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard status == 200, let id = json?["request_id"] as? String else {
                let message = (json?["error"] as? String) ?? ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
                onMain { completion(nil, "Grok Imagine did not start the shot (HTTP \(status))" + (message.isEmpty ? "" : ": " + String(message.prefix(160)))) }
                return
            }
            self.wait(id, file: file, started: Date(), isCancelled: isCancelled, completion: completion)
        }.resume()
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
    static let defaultServer = "http://192.168.4.31:8188"
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
        let filled = VideoPlan.fill(workflow, prompt: shot.prompt, frames: VideoPlan.frames(seconds: shot.seconds, fps: VideoPlan.fps(in: workflow)), seconds: shot.seconds, seed: Int.random(in: 1...999_999_999))
        var request = URLRequest(url: URL(string: server + "/prompt")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": filled, "client_id": "jarvis"])
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard status == 200, let id = json?["prompt_id"] as? String else {
                let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
                onMain { completion(nil, "ComfyUI did not accept the workflow (HTTP \(status))" + (message.isEmpty ? "" : ": " + String(message.prefix(160)))) }
                return
            }
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

/// Joins the shots into one .mp4 with AVFoundation (no ffmpeg needed). Keeps each clip's sound when it has any.
enum VideoStitcher {
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
