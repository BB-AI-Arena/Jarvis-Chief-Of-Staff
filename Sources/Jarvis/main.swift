import AppKit
import WebKit
import AVFoundation
import Speech


if let index = CommandLine.arguments.firstIndex(of:"--story-revision-request") ?? CommandLine.arguments.firstIndex(of:"--director-writing-request") {
    let workshop = CommandLine.arguments[index] == "--director-writing-request"
    let fileIndex = index + (workshop ? 2 : 1)
    let seat = workshop && CommandLine.arguments.indices.contains(index+1) ? CommandLine.arguments[index+1] : ""
    guard CommandLine.arguments.indices.contains(fileIndex), (!workshop || ["creative","research"].contains(seat)) else { print("Usage: --story-revision-request /absolute/feedback.txt");exit(2) }
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis")
    do {
        let feedback = try String(contentsOfFile:CommandLine.arguments[fileIndex],encoding:.utf8)
        guard !feedback.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw NSError(domain:"StoryRevision",code:1) }
        let story = try JSONDecoder().decode(FilmStory.self,from:Data(contentsOf:support.appendingPathComponent("film-story.json")))
        let controller = JarvisApp()
        guard workshop ? ["needs_attention","awaiting_approval","completed","production_needs_attention"].contains(story.phase) : controller.canReviseFilmStory(story) else { print("Story is busy or cannot be revised from its current phase.");exit(2) }
        let request = StoryRevisionRequest(storyID:story.id,expectedHash:story.hash,feedback:feedback,writingSeat:workshop ? seat : nil)
        let inbox = support.appendingPathComponent("story-revision-inbox")
        try FileManager.default.createDirectory(at:inbox,withIntermediateDirectories:true)
        try JSONEncoder().encode(request).write(to:inbox.appendingPathComponent(request.id + ".json"),options:.atomic)
        print("Queued writing-only revision request " + request.id + ". Jarvis must be running; rendering requires fresh owner approval.")
    } catch { print("Could not queue story revision: " + error.localizedDescription);exit(2) }
} else if CommandLine.arguments.contains("--film-provider-request") {
    FilmProviderBroker.run()
} else if CommandLine.arguments.contains("--core-live-check") {
    CoreLiveCheck.run()
    dispatchMain()
} else if CommandLine.arguments.contains("--self-test") {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
    try Data("test".utf8).write(to: temp.appendingPathComponent("hello.swift"))
    try Data("skip".utf8).write(to: temp.appendingPathComponent("node_modules/skip.js"))
    let nodes = JarvisApp.folderNodes(temp)
    assert(nodes.count == 2 && nodes.contains { ($0["label"] as? String) == "hello.swift" })
    try FileManager.default.removeItem(at: temp)
    print("PASS: file enumeration includes root and file, excludes dependency trees")
} else if CommandLine.arguments.contains("--acceptance") {
    // Headless: ten realistic requests through the live router. Exit 1 if any lands in the wrong place.
    guard let apiKey = ClaudeCredential.read() else { print("FAIL  no Anthropic key in Keychain, so the fast router cannot be tested"); exit(1) }
    Acceptance.run(apiKey: apiKey, persona: Personas.text("jarvis") ?? "") { failed in
        print(failed == 0 ? "ALL \(Acceptance.cases.count) REQUESTS ROUTED CORRECTLY" : "\(failed) OF \(Acceptance.cases.count) REQUESTS WENT TO THE WRONG PLACE")
        exit(failed == 0 ? 0 : 1)
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--cto-check") {
    // Headless: one real CTO question that can only be answered by reading the source with the read-only tools.
    guard let apiKey = ClaudeCredential.read() else { print("FAIL  no Anthropic key in Keychain"); exit(1) }
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis")
    let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "JarvisProjectRoot") as? String ?? FileManager.default.currentDirectoryPath)
    let tools = WorkspaceTools(roots: ["source": root])
    var used: [String] = []
    let system = Personas.system("cto", fallback: ClaudeClient.ctoFallback) + "\n\nYou have read-only tools over source/ (the Jarvis app source). Check the real code before answering."
    ClaudeClient.converse("In one sentence: what does TaskLedger.nextQueued return, and which file defines it? Read the file first.", model: HealthCheck.Settings.load(support: support).claudeModel, apiKey: apiKey, system: system, tools: WorkspaceTools.definitions, isCancelled: { false }, tool: { name, input, reply in
        used.append(name + " " + ((input["path"] as? String) ?? (input["query"] as? String) ?? ""))
        reply(tools.run(name, input))
    }) { text in
        used.forEach { print("TOOL  " + $0) }
        let ok = text != nil && !used.isEmpty && (text ?? "").contains("TaskLedger")
        print((ok ? "PASS  " : "FAIL  ") + "CTO answered from the code: " + (text.map { String($0.prefix(300)) } ?? "no reply"))
        exit(ok ? 0 : 1)
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--grok-models") {
    // Headless: the model ids this xAI key can use (no key is printed).
    guard let key = GrokCredential.read() else { print("FAIL  no xAI key"); exit(1) }
    var request = URLRequest(url: URL(string: "https://api.x.ai/v1/models")!)
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    URLSession.shared.dataTask(with: request) { data, _, _ in
        let ids = ((data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        print(ids.sorted().joined(separator: "\n")); exit(ids.isEmpty ? 1 : 0)
    }.resume()
    dispatchMain()
} else if CommandLine.arguments.contains("--research-timing") {
    // Headless: one research question through each Grok path (chat, web search, web search + DARK tool), timed with tokens.
    guard let key = GrokCredential.read() else { print("FAIL  no xAI key"); exit(1) }
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis")
    let model = ProcessInfo.processInfo.environment["GROK_MODEL"].flatMap(GrokClient.sanitize) ?? HealthCheck.Settings.load(support: support).grokModel
    let system = Personas.system("research", fallback: GrokClient.researchFallback) + "\n\nThis call is an assignment from Jarvis. Use live web search for anything current, cite your sources, and separate facts from estimates." + BoardMemory(file: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Jarvis Workspace/Memory/board.md")).context()
    let question = "Research the top three field-service scheduling apps for solo handymen and their monthly prices."
    let dark = DarkServer.load(support: support)
    print("model \(model) · system prompt \(system.count) chars")
    func tokens() -> String { let t = ((TokenMeter.snapshot()["today"] as? [String: [String: Any]])?["research"]) ?? [:]; return "\(t["calls"] ?? 0) calls · \(t["input"] ?? 0) in · \(t["output"] ?? 0) out" }
    func step(_ index: Int) {
        TokenMeter.reset()
        let start = Date()
        let report: (String, String?) -> Void = { name, text in
            print(String(format: "%-26@ %5.1f s · %@ · %d chars", name as NSString, Date().timeIntervalSince(start), tokens() as NSString, text?.count ?? 0))
            if index < 2 { step(index + 1) } else { exit(0) }
        }
        TokenMeter.charge("research") {
            switch index {
            case 0: GrokClient.research(question, model: model, apiKey: key, system: system) { report("chat (no search)", $0) }
            case 1: GrokClient.researchLive(question, model: model, apiKey: key, system: system, isCancelled: { false }) { text, live in report(live ? "web search" : "web search FELL BACK", text) }
            default: GrokClient.researchWithTools(question, model: model, apiKey: key, system: system + " " + DarkTool.promptNote, tools: [DarkTool.responsesFunction], isCancelled: { false }, tool: { _, input, reply in print("  (DARK: \(input["command"] ?? ""))"); DarkTool.run(input, dark: dark, completion: reply) }) { text, _ in report("web search + DARK tool", text) }
            }
        }
    }
    step(0)
    DispatchQueue.main.asyncAfter(deadline: .now() + 900) { print("TIMEOUT"); exit(2) }
    dispatchMain()
} else if CommandLine.arguments.contains("--research-check") {
    // Headless: one real Research question answered by Claude with live web search (the fallback used when Grok is off).
    guard let apiKey = ClaudeCredential.read() else { print("FAIL  no Anthropic key in Keychain"); exit(1) }
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis")
    let start = Date()
    ClaudeClient.research("In two sentences: what are two widely used field-service scheduling apps for small handyman businesses? Cite sources.", model: HealthCheck.Settings.load(support: support).claudeModel, apiKey: apiKey, system: GrokClient.researchFallback, isCancelled: { false }) { text, failure in
        let cited = text?.contains("Sources:\n- http") == true || text?.contains("Sources searched:\n- http") == true
        print((text != nil && cited ? "PASS  " : "FAIL  ") + "Claude web research in \(Int(Date().timeIntervalSince(start))) s" + (cited ? " with cited sources" : " WITHOUT sources"))
        print(text ?? failure ?? "no reply")
        exit(text != nil && cited ? 0 : 1)
    }
    dispatchMain()
 } else if CommandLine.arguments.contains("--local-film-check") {
    func argument(_ flag:String)->String? { guard let i=CommandLine.arguments.firstIndex(of:flag),CommandLine.arguments.indices.contains(i+1) else { return nil };return CommandLine.arguments[i+1] }
    let home=FileManager.default.homeDirectoryForCurrentUser
    let support=home.appendingPathComponent("Library/Application Support/Jarvis")
    let project=URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"JarvisProjectRoot") as? String ?? FileManager.default.currentDirectoryPath)
    let brief=argument("--story") ?? "Create a 15 second cinematic film: Drop Assassin comes to life and uses the app to find chase items, using my artwork as reference."
    let seconds=min(600,max(3,argument("--seconds").flatMap(Int.init) ?? 15))
    let folder=argument("--output").map { URL(fileURLWithPath:$0) } ?? home.appendingPathComponent("Documents/Jarvis Workspace/Video/local-film-\(Int(Date().timeIntervalSince1970))")
    guard let directory=VideoArtwork.directory(for:brief,sources:VideoArtwork.loadSources(support:support)),
          let data=try? Data(contentsOf:home.appendingPathComponent("Documents/Jarvis Workspace/Video/comfyui-workflow-api.json")),
          let workflow=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
          let script=Bundle.main.url(forResource:"film_supervisor",withExtension:"py") else { print("FAIL missing local film source, workflow or worker");exit(1) }
    let dark=DarkServer.load(support:support)
    let server=(try? String(contentsOf:support.appendingPathComponent("comfy-url.txt"),encoding:.utf8)).flatMap(OllamaClient.sanitizeHost) ?? ComfyVideo.defaultServer
    var worker:Process?
    VideoArtwork.prepare(directory:directory,brief:brief,server:server,workflow:workflow,dark:dark) { refs,error in
        guard var refs else { print("FAIL " + (error ?? "Missing artwork"));exit(1) }
        if let look=VideoArtwork.approvedLook(for:brief,support:support) { refs.append(look) }
        let id="jarvis-local-" + String(folder.lastPathComponent.filter { $0.isLetter || $0.isNumber || $0=="-" || $0=="_" }.prefix(65))
        let spec=LocalFilmWorker.spec(brief:brief,seconds:seconds,artwork:refs,workflow:workflow,server:server,dark:dark,project:project,model:ClaudeClient.defaultModel,clientID:id)
        worker=LocalFilmWorker.start(spec:spec,folder:folder,project:project,script:script,event:{ event in
            switch event["type"] as? String {
            case "usage":if let u=event["usage"],let data=try? JSONSerialization.data(withJSONObject:["usage":u]) { TokenMeter.record(event["seat"] as? String,model:event["model"] as? String ?? "",data:data) }
            case "plan":print("PLAN READY");fflush(stdout)
            default:if let data=try? JSONSerialization.data(withJSONObject:event,options:[.sortedKeys]),let text=String(data:data,encoding:.utf8) { print(text) }
            }
        },completion:{ status in _=worker;fflush(stdout);exit(status) })
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--artwork-check") {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let support = home.appendingPathComponent("Library/Application Support/Jarvis")
    let brief = "Create a 3 second Drop Assassin video from drop-assassin-logo.png artwork"
    guard let directory = VideoArtwork.directory(for: brief, sources: VideoArtwork.loadSources(support: support)),
          let data = try? Data(contentsOf: home.appendingPathComponent("Documents/Jarvis Workspace/Video/comfyui-workflow-api.json")),
          let workflow = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          VideoArtwork.conditioned(workflow, image: "test.png") != nil else { print("FAIL missing artwork source or compatible workflow"); exit(1) }
    let server = (try? String(contentsOf: support.appendingPathComponent("comfy-url.txt"), encoding: .utf8)).flatMap(OllamaClient.sanitizeHost) ?? ComfyVideo.defaultServer
    let folder = home.appendingPathComponent("Documents/Jarvis Workspace/Video/artwork-check-\(Int(Date().timeIntervalSince1970))")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    VideoArtwork.prepare(directory: directory, brief: brief, server: server, workflow: workflow, dark: DarkServer.load(support: support)) { refs, error in
        guard let refs, refs.count == 1 else { print("FAIL " + (error ?? "Expected exactly the named logo")); exit(1) }
        print(VideoArtwork.manifest(refs, shots: 1))
        let renderer = ComfyVideo(server: server, workflow: workflow, artwork: refs, onQueued: { print("Image-conditioned ComfyUI prompt: " + $0) })
        renderer.render(VideoPlan.Shot(prompt: VideoArtwork.motionPrompt, seconds: 3), to: folder.appendingPathComponent("final.mp4"), isCancelled: { false }) { file, error in
            guard let file else { print("FAIL " + (error ?? "No video")); exit(1) }
            VideoStitcher.thumbnail(file) { thumb in
                if let thumb, let encoded = thumb.split(separator: ",").last, let data = Data(base64Encoded: String(encoded)) { try? data.write(to: folder.appendingPathComponent("preview.jpg")) }
                print("PASS real artwork image-conditioned render: " + file.path)
                exit(0)
            }
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 600) { print("FAIL artwork render timed out"); exit(2) }
    dispatchMain()
} else if CommandLine.arguments.contains("--video-check") {
    // Headless: renders one 4-second shot and joins it twice, to prove render + download + stitch.
    // Default is Grok Imagine (about $0.32); --comfy uses DARK's 4090 (free), starting ComfyUI over SSH if needed.
    let home = FileManager.default.homeDirectoryForCurrentUser
    let folder = home.appendingPathComponent("Documents/Jarvis Workspace/Video/check-\(Int(Date().timeIntervalSince1970))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let start = Date()
    let shot = VideoPlan.Shot(prompt: "Cinematic close-up of raindrops falling in slow motion past a red neon sign at night, shallow depth of field, film grain", seconds: 4)
    func renderCheck(_ renderer: ShotRenderer, name: String) {
      renderer.render(shot, to: folder.appendingPathComponent("shot-1.mp4"), isCancelled: { false }) { file, failure in
        guard let file else { print("FAIL  render: " + (failure ?? "unknown")); exit(1) }
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int) ?? 0
        print("PASS  rendered 1 shot on \(name) in \(Int(Date().timeIntervalSince(start))) s · \(size / 1024) KB")
        VideoStitcher.join([file, file], to: folder.appendingPathComponent("final.mp4")) { ok in
            Task {
                let asset = AVURLAsset(url: folder.appendingPathComponent("final.mp4"))
                let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
                let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
                let size = tracks.isEmpty ? .zero : ((try? await tracks[0].load(.naturalSize)) ?? .zero)
                let audio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty ? "no sound" : "with sound"
                print((ok && seconds > 6 ? "PASS  " : "FAIL  ") + String(format: "joined 2 copies: %.1f s, %dx%d, %@", seconds, Int(size.width), Int(size.height), audio))
                print("Saved: " + folder.path)
                exit(ok && seconds > 6 ? 0 : 1)
            }
        }
      }
    }
    if CommandLine.arguments.contains("--comfy") {
        let support = home.appendingPathComponent("Library/Application Support/Jarvis")
        let server = ComfyVideo.defaultServer
        let workflowFile = home.appendingPathComponent("Documents/Jarvis Workspace/Video/comfyui-workflow-api.json")
        guard let data = try? Data(contentsOf: workflowFile), let workflow = try? JSONSerialization.jsonObject(with: data) as? [String: Any], VideoPlan.hasPromptSlot(workflow) else {
            print("FAIL  no ComfyUI workflow with {{prompt}} at " + workflowFile.path); exit(1)
        }
        DarkServer.load(support: support).ensureComfy(server: server) { up, note in
            print((up ? "PASS  " : "FAIL  ") + note)
            guard up else { exit(1) }
            renderCheck(ComfyVideo(server: server, workflow: workflow), name: "the 4090 (ComfyUI)")
        }
    } else {
        guard let apiKey = GrokCredential.read() else { print("FAIL  no xAI key in Keychain"); exit(1) }
        renderCheck(GrokVideo(apiKey: apiKey), name: "Grok Imagine")
    }
    dispatchMain()
 } else if CommandLine.arguments.contains("--projects-check") {
    guard let key = ClaudeCredential.read() else { print("FAIL no Claude key"); exit(1) }
    let projects = ProjectsTool()
    var returned = false
    let prompt = "Call delegate_to_projects exactly once. Subtask: summarize launch notes. Instructions: Return one sentence stating the launch date and owner. Input text: The launch is December 3. Maya owns the launch. Then repeat Projects' answer."
    TokenMeter.charge("technology") {
        ClaudeClient.converse(prompt, model: ClaudeClient.defaultModel, apiKey: key, system: ProjectsTool.promptNote, tools: [ProjectsTool.anthropic], isCancelled: { false }, tool: { name, input, reply in
            guard name == ProjectsTool.name else { reply("Unknown tool"); return }
            projects.run(input, isCancelled: { false }, event: { phase, title in print("CTO → Projects: \(title) · \(phase)") }) { output in
                print("qwen3.5:latest: " + output)
                returned = output.contains("Maya") && output.contains("3") && TokenMeter.used("projects") > 0
                reply(output)
            }
        }) { answer in
            print("CTO: " + (answer ?? "no answer"))
            let ok = returned && projects.count == 1 && answer != nil
            print((ok ? "PASS" : "FAIL") + " CTO delegated to Projects · projects tokens \(TokenMeter.used("projects"))")
            exit(ok ? 0 : 1)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 180) { print("FAIL Projects check timeout"); exit(2) }
    dispatchMain()
} else if CommandLine.arguments.contains("--dark-check") {
    // Headless: each director's real model is asked to use run_on_dark; every command it runs is printed. Costs a few cents.
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis")
    let dark = DarkServer.load(support: support)
    guard dark.hasKey else { print("FAIL  no SSH key for DARK"); exit(1) }
    let question = "Use the run_on_dark tool to find DARK's GPU name with its total and used VRAM, and the file names in ~/ComfyUI/models/checkpoints. Answer in two short lines with the real values you got."
    var pending = 0, failed = false
    var successfulTools = Set<String>()
    func tool(_ who: String) -> (String, [String: Any], @escaping (String) -> Void) -> Void {
        { name, input, reply in
            print("  \(who) → \(name): \((input["command"] as? String) ?? "?")")
            guard name == DarkTool.name else { reply("Unknown tool"); return }
            DarkTool.run(input, dark: dark) { output in
                if output.hasPrefix("exit 0\n") { successfulTools.insert(who) }
                reply(output)
            }
        }
    }
    func finish(_ who: String, _ text: String?, seat: String) {
        let ok = successfulTools.contains(seat) && (text.map { $0.contains("4090") } ?? false)
        if !ok { failed = true }
        print((ok ? "PASS  " : "FAIL  ") + who + ": " + (text.map { $0.replacingOccurrences(of: "\n", with: " / ").prefix(300).description } ?? "no answer"))
        pending -= 1
        if pending == 0 { exit(failed ? 1 : 0) }
    }
    let system = "You are a director on Jarvis's board. " + DarkTool.promptNote
    if let key = ClaudeCredential.read() {
        pending += 1
        ClaudeClient.converse(question, model: ClaudeClient.defaultModel, apiKey: key, system: system, tools: [DarkTool.anthropic], isCancelled: { false }, tool: tool("CTO")) { finish("CTO (Claude)", $0, seat: "CTO") }
    } else { print("SKIP  CTO: no Claude key") }
    if let key = GrokCredential.read() {
        pending += 1
        GrokClient.researchWithTools(question, model: GrokClient.defaultModel, apiKey: key, system: system, tools: [DarkTool.responsesFunction], isCancelled: { false }, tool: tool("Research")) { text, _ in finish("Research (Grok)", text, seat: "Research") }
    } else { print("SKIP  Research: no xAI key") }
    let projectsModel = (try? String(contentsOf: support.appendingPathComponent("projects-model.txt"), encoding: .utf8)).flatMap(OllamaClient.sanitize)
    if let model = projectsModel {
        pending += 1
        OllamaClient.base = OllamaClient.defaultServer
        OllamaClient.converse(question, model: model, system: system, tools: [DarkTool.function], isCancelled: { false }, tool: tool("Projects")) { finish("Projects (\(model))", $0, seat: "Projects") }
    } else { print("SKIP  Projects: no model") }
    if pending == 0 { exit(1) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 300) { print("TIMEOUT"); exit(2) }
    dispatchMain()
} else if CommandLine.arguments.contains("--health") {
    // Headless: one live call per connection, printed without keys. Exit 1 if anything failed.
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis")
    let brain = ConversationBrain()
    HealthCheck.run(settings: .load(support: support), brain: brain) { results in
        results.forEach { print($0.line) }
        brain.cancel()
        exit(results.contains { $0.status == "failed" } ? 1 : 0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 150) { print("TIMEOUT    health check did not finish in 150 s"); exit(2) }
    dispatchMain()
} else {
    let app = NSApplication.shared
    let delegate = JarvisApp(); app.delegate = delegate; app.run()
}
