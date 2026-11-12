import Foundation
assert(VideoPlan.isVideoRequest("Create a 30 second cinematic video about Drop Assassin in HD"))
assert(VideoPlan.isVideoRequest("Make a trailer for the app") && VideoPlan.isVideoRequest("an animated logo reveal"))
assert(!VideoPlan.isVideoRequest("Design a logo and a name for the handyman app"))
assert(VideoPlan.requestedSeconds("a 30 second video") == 30 && VideoPlan.requestedSeconds("45-sec promo") == 45 && VideoPlan.requestedSeconds("10s clip") == 10)
assert(VideoPlan.requestedSeconds("a 2 minute film") == 60 && VideoPlan.requestedSeconds("a 300 second video") == 60 && VideoPlan.requestedSeconds("a video") == 15)
print("PASS: Creative recognises video requests and their length, capped at 60 seconds")
let planned = VideoPlan.parse("""
Here is the plan:
```json
{"title": "Drop Assassin", "shots": [
 {"prompt": "Night aerial over a rain-soaked neon city, slow push-in", "seconds": 10},
 {"prompt": "Close-up, raindrops freeze mid-air, camera orbits", "seconds": 12},
 {"prompt": "short", "seconds": 5},
 {"prompt": "Logo forms from falling droplets, red metallic title", "seconds": 10},
 {"prompt": "Extra shot that would exceed the requested length", "seconds": 10}]}
```
""", renderer: .grok, total: 30)!
assert(planned.title == "Drop Assassin")
assert(planned.shots.map(\.seconds) == [10, 10, 10] && planned.seconds == 30)
assert(abs(VideoPlan.cost(planned, renderer: .grok) - 2.40) < 0.001 && VideoPlan.cost(planned, renderer: .comfy) == 0)
assert(VideoPlan.parse("no json here", renderer: .grok, total: 30) == nil)
assert(VideoPlan.parse("{\"shots\": []}", renderer: .grok, total: 30) == nil)
let comfyPlan = VideoPlan.parse("{\"title\":\"T\",\"shots\":[{\"prompt\":\"A long enough prompt\",\"seconds\":10}]}", renderer: .comfy, total: 30)!
assert(comfyPlan.shots[0].seconds == 5)
let fallback = VideoPlan.fallback(brief: "Drop Assassin hero shot", total: 12, renderer: .comfy)
assert(fallback.shots.map(\.seconds) == [5, 5, 2] && fallback.shots[0].prompt.contains("Drop Assassin hero shot"))
assert(VideoPlan.plannerPrompt(brief: "B", seconds: 30, renderer: .grok).contains("Use 3 shots of at most 10 seconds"))
print("PASS: shot lists are read from the planner's JSON and clamped to the requested length and each renderer's clip limit")
let doc = VideoPlan.document(planned, brief: "brief", renderer: .grok, results: ["shot-1.mp4", "failed: timeout"])
assert(doc.contains("grok-imagine-video-1.5, 1080p, about $2.40") && doc.contains("1. 10 s — shot-1.mp4") && doc.contains("2. 10 s — failed: timeout") && doc.contains("3. 10 s — not rendered"))
print("PASS: the shot list document records the renderer, cost and each shot's outcome")
let body = GrokVideo.body(VideoPlan.Shot(prompt: "P", seconds: 10), model: VideoPlan.grokModel, resolution: "1080p", aspect: "16:9")
assert(body["model"] as? String == "grok-imagine-video-1.5" && body["duration"] as? Int == 10 && body["resolution"] as? String == "1080p" && body["aspect_ratio"] as? String == "16:9" && body["prompt"] as? String == "P")
let done = GrokVideo.poll(Data("{\"status\":\"done\",\"video\":{\"url\":\"https://vidgen.x.ai/a/video.mp4\",\"duration\":8},\"model\":\"grok-imagine-video-1.5\"}".utf8))!
assert(done.status == "done" && done.url?.absoluteString == "https://vidgen.x.ai/a/video.mp4")
let failed = GrokVideo.poll(Data("{\"status\":\"failed\",\"error\":{\"code\":\"invalid_argument\",\"message\":\"bad prompt\"}}".utf8))!
assert(failed.status == "failed" && failed.error == "bad prompt" && failed.url == nil)
assert(GrokVideo.poll(Data("{}".utf8)) == nil)
print("PASS: Grok Imagine requests use the documented fields, and finished, failed and malformed replies are told apart")
let workflow: [String: Any] = ["6": ["class_type": "CLIPTextEncode", "inputs": ["text": "{{prompt}}, cinematic"]], "50": ["inputs": ["length": "{{frames}}", "seed": "{{seed}}", "steps": 20]]]
assert(VideoPlan.hasPromptSlot(workflow) && !VideoPlan.hasPromptSlot(["1": ["inputs": ["text": "fixed"]]]))
let filled = VideoPlan.fill(workflow, prompt: "Neon rooftop", frames: 81, seconds: 5, seed: 42) as! [String: Any]
let text = ((filled["6"] as! [String: Any])["inputs"] as! [String: Any])["text"] as? String
let inputs = (filled["50"] as! [String: Any])["inputs"] as! [String: Any]
assert(text == "Neon rooftop, cinematic" && inputs["length"] as? Int == 81 && inputs["seed"] as? Int == 42 && inputs["steps"] as? Int == 20)
assert(VideoPlan.frames(seconds: 5) == 121 && VideoPlan.frames(seconds: 5, fps: 16) == 81 && (VideoPlan.frames(seconds: 7) - 1) % 8 == 0)
assert(VideoPlan.fps(in: ["18": ["class_type": "CreateVideo", "inputs": ["fps": 24.0]]]) == 24 && VideoPlan.fps(in: ["5": ["inputs": ["frame_rate": 16]]]) == 16 && VideoPlan.fps(in: [:]) == 24)
let ltx = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "tests/video/ltx-workflow.json"))) as! [String: Any]
let ltxFilled = VideoPlan.fill(ltx, prompt: "Rooftop drop", frames: VideoPlan.frames(seconds: 5, fps: VideoPlan.fps(in: ltx)), seconds: 5, seed: 7) as! [String: Any]
assert(VideoPlan.hasPromptSlot(ltx) && ((ltxFilled["6"] as! [String: Any])["inputs"] as! [String: Any])["length"] as? Int == 121 && ((ltxFilled["10"] as! [String: Any])["inputs"] as! [String: Any])["noise_seed"] as? Int == 7)
let history: [String: Any] = ["status": ["status_str": "success", "completed": true], "outputs": ["9": ["images": [["filename": "frame.png", "subfolder": "", "type": "output"]]], "12": ["gifs": [["filename": "Wan_00001.mp4", "subfolder": "video", "type": "output"]]]]]
let output = VideoPlan.comfyOutput(history)!
assert(output.filename == "Wan_00001.mp4" && output.subfolder == "video" && output.type == "output")
assert(VideoPlan.comfyOutput(["outputs": ["9": ["images": [["filename": "frame.png"]]]]]) == nil)
print("PASS: the 4090's ComfyUI workflow gets the shot's prompt, frame count and seed, and the rendered video file is found in its history")
var dark = DarkServer()
assert(dark.target == "bradshaw@192.168.4.31" && dark.key.hasSuffix("/.ssh/jarvis_dark"))
let args = dark.arguments("nvidia-smi")
assert(args.contains("BatchMode=yes") && args.contains("IdentitiesOnly=yes") && args.contains("ForwardAgent=no") && args.suffix(2) == ["bradshaw@192.168.4.31", "nvidia-smi"])
assert(!args.contains { $0.lowercased().contains("password") })
assert(DarkServer.describeGPU("NVIDIA GeForce RTX 4090, 1229, 24564, 3, 41") == "NVIDIA GeForce RTX 4090 · 1.2 / 24.0 GB VRAM · 3% busy · 41 °C")
assert(DarkServer.describeGPU("command not found") == nil)
assert(DarkServer.sanitizeHost("192.168.4.31") && DarkServer.sanitizeHost("dark.local") && !DarkServer.sanitizeHost("host; rm -rf /"))
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-dark-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
try! "{\"host\":\"evil; ls\",\"user\":\"Bad User\",\"comfyStart\":\"cd ~/ComfyUI && ./run.sh\"}".write(to: dir.appendingPathComponent("dark.json"), atomically: true, encoding: .utf8)
dark = DarkServer.load(support: dir)
assert(dark.host == "192.168.4.31" && dark.user == "bradshaw" && dark.comfyStart == "cd ~/ComfyUI && ./run.sh")
try? FileManager.default.removeItem(at: dir)
print("PASS: DARK is reached over SSH with Jarvis's own key only (no password, no agent forwarding), and bad settings fall back to safe defaults")
