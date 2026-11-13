import AppKit
import WebKit
import AVFoundation
import Speech

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class JarvisApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate, AVAudioPlayerDelegate {
    var onEvent: ((String, Any) -> Void)?
    var healthRunning = false
    var window: NSWindow!
    var orb: FloatingPanel!
    var web: WKWebView!
    var orbWeb: WKWebView!
    var status: NSStatusItem!
    var tasks: [String: Process] = [:]
    var root: URL?
    var voiceProcess: Process?
    var voiceInput: Pipe?
    var voiceBuffer = Data()
    var voiceReady = false
    var orbDragMouse: NSPoint?
    var orbDragOrigin: NSPoint?
    var audio: AVAudioPlayer?
    var speechTask: SFSpeechRecognitionTask?
    let engine = AVAudioEngine()
    var recording = false
    var localTask: URLSessionDataTask?
    var localRequestID = UUID()
    var localWarmRequested = false
    var conversationActive = false
    var conversationID = UUID()
    var recognitionID = UUID()
    var activeSpeechID = UUID().uuidString
    var speechIsConversation = false
    var turn = VoiceTurn()
    var turnTimer: Timer?
    var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    var listeningDeadline: Timer?
    let brain = ConversationBrain()
    var liveVoice: CloudVoice?
    var startupScheduled = false
    var streamText = ""
    var streamVoice: String?
    var streamPlayback = false
    var streamPending = false
    var streamSpoke = false
    var streamAudio: [[String:Any]] = []
    var streamSyntheses = 0
    var outputMeter: Timer?
    var support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis")
    lazy var ledger = TaskStore(directory: support.appendingPathComponent("tasks"))
    var workTaskID: String?
    var quitting = false
    var managerModel: String?
    var knownLocalModels: [String] = []
    var claudeModel = ClaudeClient.defaultModel
    var claudeConnected = false
    /// Shared board memory: decisions, results and facts Brandon asked Jarvis to keep.
    /// Jarvis's visible working folder: saved results and board memory live here so Brandon can open them.
    var workspace = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Jarvis Workspace")
    lazy var memory = BoardMemory(file: workspace.appendingPathComponent("Memory/board.md"))
    /// The voice delegation that asked for a task, so its result can be relayed in the same conversation.
    struct LiveReply { let update: (String) -> Void; weak var voice: CloudVoice? }
    var liveReplies: [String: LiveReply] = [:]
    /// Models on the 4090's Ollama, refreshed at launch; the Operations roster lists these.
    var serverModels: [String] = []
    var grokModel = GrokClient.defaultModel
    var grokConnected = false
    var cursorModel = ""
    var cursorRepo = CursorClient.defaultRepo
    var cursorConnected = false
    var cursorRun: (agent: String, run: String)?
    /// Director of Projects runs on a local Ollama model chosen in the board settings. Unset until Brandon picks an installed model.
    var projectsModel: String?
    /// The live board debate: its ledger task id and in-flight model calls.
    var debateTaskID: String?
    var debateRequests: [URLSessionDataTask] = []
    /// Where the verdict goes: the voice delegation that asked for the debate, while that voice session is still live.
    var debateLiveUpdate: ((String) -> Void)?
    weak var debateVoice: CloudVoice?
    /// Running seat assignments other than the CTO, keyed by director id, with the ledger task id.
    var seatRuns: [String: String] = [:]
    var seatRequests: [String: URLSessionDataTask] = [:]
    /// Live progress of each video job, by its task id (the Studio card).
    var videoJobs: [String: VideoPlan.Progress] = [:]
    var filmWorkers: [String:Process] = [:]
    var filmStoryTimer: Timer?
    var externalFilmTimer: Timer?
    var externalFilms: [String:URL] = [:]
    /// What each director is doing right now, so a reloaded page can redraw the board.
    var workBoard: [String: [String: Any]] = [:]
    /// Set after an in-place UI update until the new page says it is ready; otherwise it is rolled back.
    var uiAwaitingReady = false
    var usagePending = false
    /// Titles of suggested tasks Brandon approved; their results do not offer yet another follow-up.
    var approvedSuggestions: Set<String> = []
    var workerSourcesFingerprint: String?
    lazy var resultMedia = ResultMedia(root: { [weak self] in self?.resultsDirectory })
    var bundlePage: URL { Bundle.main.resourceURL ?? URL(fileURLWithPath: "/") }
    var livePage: URL { support.appendingPathComponent("ui-live") }
    var pageRoot: URL { LiveUI.root(bundle: bundlePage, live: livePage) }
    var project: URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "JarvisProjectRoot") as? String ?? FileManager.default.currentDirectoryPath) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TokenMeter.file = support.appendingPathComponent("usage.json")
        TokenMeter.onChange = { [weak self] in
            guard let self, !self.usagePending else { return }
            self.usagePending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.usagePending = false; self?.send("usage", TokenMeter.snapshot()) }
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: workspace.appendingPathComponent("Results"), withIntermediateDirectories: true)
        startVoice()
        publishTasks(TaskLedger.interruptRunning(ledger.load(), at: TaskLedger.timestamp()))
        if let stored = try? String(contentsOf: support.appendingPathComponent("manager-model.txt"), encoding: .utf8) {
            managerModel = OperationsManager.resolve(stored: stored, advertised: [])
        }
        if let stored = try? String(contentsOf: support.appendingPathComponent("claude-model.txt"), encoding: .utf8), let model = ClaudeClient.sanitize(stored) {
            claudeModel = model
        }
        refreshClaude(announce: false)
        if let stored = try? String(contentsOf: support.appendingPathComponent("grok-model.txt"), encoding: .utf8), let model = GrokClient.sanitize(stored) { grokModel = model }
        if let stored = try? String(contentsOf: support.appendingPathComponent("cursor-model.txt"), encoding: .utf8), let model = CursorClient.sanitizeModel(stored) { cursorModel = model }
        if let stored = try? String(contentsOf: support.appendingPathComponent("cursor-repo.txt"), encoding: .utf8), let repo = CursorClient.sanitizeRepo(stored) { cursorRepo = repo }
        OllamaClient.base = (try? String(contentsOf: support.appendingPathComponent("ollama-host.txt"), encoding: .utf8)).flatMap(OllamaClient.sanitizeHost) ?? OllamaClient.defaultServer
        if let stored = try? String(contentsOf: support.appendingPathComponent("projects-model.txt"), encoding: .utf8), let model = OllamaClient.sanitize(stored) { projectsModel = model }
        refreshCursor(announce: false)
        refreshGrok(announce: false)
        OllamaClient.models { [weak self] names in self?.serverModels = names ?? [] }
        brain.warm()
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Open Jarvis", action: #selector(showWorkspace), keyEquivalent: "j").target = self
        appMenu.addItem(withTitle: "Show floating orb", action: #selector(showOrb), keyEquivalent: "o").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Jarvis", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let menuItem = NSMenuItem(); menuItem.submenu = appMenu; menu.addItem(menuItem)
        NSApp.mainMenu = menu
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Cut", "cut:", "x"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        web = makeWeb(mode: "workspace")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 810), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Jarvis · Chief of Staff"; window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible; window.backgroundColor = NSColor(calibratedRed: 0.018, green: 0.035, blue: 0.065, alpha: 1)
        window.minSize = NSSize(width: 980, height: 650); window.contentView = web; window.center()
        window.isReleasedWhenClosed = false; window.delegate = self
        orbWeb = makeWeb(mode: "orb")
        orb = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 148, height: 172), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        orb.isOpaque = false; orb.backgroundColor = .clear; orb.hasShadow = false
        orb.title = "Jarvis Orb"
        orb.level = .floating; orb.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        orb.isMovableByWindowBackground = true; orb.hidesOnDeactivate = false; orb.contentView = orbWeb
        if let screen = NSScreen.main { orb.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 180, y: screen.visibleFrame.minY + 80)) }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Jarvis")
        let statusMenu = NSMenu()
        statusMenu.addItem(withTitle: "Open workspace", action: #selector(showWorkspace), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Show floating orb", action: #selector(showOrb), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Quit Jarvis", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        status.menu = statusMenu
        showWorkspace()
    }
    func makeWeb(mode: String) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "jarvis")
        configuration.userContentController.addUserScript(WKUserScript(source: "window.JARVIS_MODE='\(mode)';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.setURLSchemeHandler(resultMedia, forURLScheme: ResultMedia.scheme)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground"); view.navigationDelegate = self
        loadPage(view)
        return view
    }
    /// Loads the page from the live UI copy when there is a current one, otherwise from the app bundle.
    func loadPage(_ view: WKWebView) {
        let root = pageRoot
        view.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
    }
    @objc func showWorkspace() { orb?.orderOut(nil); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showOrb() { orb.orderFrontRegardless() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); showOrb(); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { showWorkspace(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        quitting = true
        seatRequests.values.forEach { $0.cancel() }
        filmWorkers.values.forEach { if $0.isRunning { $0.terminate() } }
        debateRequests.forEach { $0.cancel() }
        publishTasks(TaskLedger.interruptRunning(ledger.load(), at: TaskLedger.timestamp()))
        brain.cancel(); liveVoice?.stop(); for process in tasks.values { process.terminate() }; voiceProcess?.terminate(); stopRecording(); outputMeter?.invalidate()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.request.url?.isFileURL == true else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func send(_ event: String, _ payload: Any) {
        onEvent?(event, payload)
        guard let data = try? JSONSerialization.data(withJSONObject: ["event": event, "data": payload]), let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.web?.evaluateJavaScript("window.receive(\(json))", completionHandler: nil)
            self.orbWeb?.evaluateJavaScript("window.receive(\(json))", completionHandler: nil)
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready":
            send("ready", ["voiceReady": voiceReady, "root": root?.path ?? ""]); send("conversation", ["active": conversationActive])
            refreshFilmStory()
            if filmStoryTimer == nil { filmStoryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshFilmStory() } }
            refreshExternalFilms()
            if externalFilmTimer == nil { externalFilmTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshExternalFilms() } }
            publishTasks(ledger.load(), save: false)
            send("managerModel", managerModel ?? "")
            send("claudeStatus", ["connected": claudeConnected, "model": claudeModel])
            sendSeatStatus()
            uiAwaitingReady = false
            for payload in workBoard.values { send("work", payload) }
            for id in videoJobs.keys { publishVideo(id) }
            send("usage", TokenMeter.snapshot())
            if message.webView === web, !startupScheduled {
                startupScheduled = true
                let backend = body["backend"] as? String ?? "local"
                let voice = body["voice"] as? String ?? "bm_lewis"
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.runHealthCheck(startup: true) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                        self.startConversation(backend: backend, history: [], greeting: true, voice: voice)
                    } else { self.speak("At your service. Start a conversation when you are ready.", voice: voice) }
                }
            }
        case "open": showWorkspace()
        case "hideOrb": orb.orderOut(nil)
        case "collapse": window.orderOut(nil); showOrb()
        case "dragBegin": orbDragMouse = NSEvent.mouseLocation; orbDragOrigin = orb.frame.origin
        case "dragMove": if let start = orbDragMouse, let origin = orbDragOrigin {
            let current = NSEvent.mouseLocation
            orb.setFrameOrigin(NSPoint(x: origin.x + current.x - start.x, y: origin.y + current.y - start.y))
        }
        case "dragEnd": orbDragMouse = nil; orbDragOrigin = nil
        case "folder": chooseFolder()
        case "refresh": if let root = root { index(root) }
        case "reveal": if let path = body["path"] as? String, let root = root {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            if url.path == root.path || url.path.hasPrefix(root.path + "/") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        case "chat": if let prompt = body["prompt"] as? String {
            if let live = liveVoice { live.sendText(prompt); return }
            if conversationActive { stopRecording() }
            let model = body["model"] as? String ?? "astra"
            if model == "claude", (body["spoken"] as? Bool == true || conversationActive) {
                streamText = "";streamVoice = body["voice"] as? String ?? "bm_lewis";streamPending = true;streamSpoke = false;streamAudio = [];streamSyntheses = 0
                activeSpeechID = UUID().uuidString;stopRecording()
            }
            if ["astra","luna","claude"].contains(model) { chat(prompt, history: body["history"] as? String ?? "", deep: model == "astra", claudeOnly:model == "claude") }
            else { localChat(prompt, history: body["history"] as? String ?? "", model: model) }
        }
        case "models": localModels()
        case "stopTask": stopAssigned(body["id"] as? String)
        case "openResult": if let id = body["id"] as? String { openResult(id) }
        case "showResult": if let key = body["key"] as? String { showResult(key: key) }
        case "listResults": listResults()
        case "revealResult": if let key = body["key"] as? String { revealResult(key: key) }
        case "reloadUI": reloadUI(reason: "manual")
        case "assignTask": if let id = body["id"] as? String, let director = body["director"] as? String { assignUnrouted(id, director: director) }
        case "setManagerModel": storeManagerModel(body["model"] as? String ?? "")
        case "configureClaude": configureClaude()
        case "setClaudeModel": storeClaudeModel(body["model"] as? String ?? "")
        case "approveFilmStory":
            if let id = body["id"] as? String, let hash = body["hash"] as? String { approveFilmStory(id,hash:hash) }
        case "reviseFilmStory":
            if let id = body["id"] as? String, let feedback = body["feedback"] as? String { reviseFilmStory(id,feedback:feedback) }
        case "approveTask":
            if let title = (body["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, let director = body["director"] as? String, RouteDecision.directors.contains(director) {
                approvedSuggestions.insert(title)
                delegateWork(title, director: director)
            }
        case "configureGrok": configureGrok()
        case "setGrokModel": storeGrokModel(body["model"] as? String ?? "")
        case "setCreativeModel": storeCursorModel(body["model"] as? String ?? "")
        case "setCreativeRepo": storeCursorRepo(body["repo"] as? String ?? "")
        case "configureCursor": configureCursor()
        case "health": runHealthCheck(startup: false)
        case "configureDark": configureDark()
        case "setProjectsModel": storeProjectsModel(body["model"] as? String ?? "")
        case "debate":
            let result = startDebate(body["topic"] as? String ?? "")
            if !result.started { send("notice", result.message) }
        case "configureCloudVoice": configureCloudVoice()
        case "cancel": endConversation(cancelReply: true)
        case "speak": if let text = body["text"] as? String {
            if liveVoice != nil { endConversation(cancelReply: false) }
            speak(text, voice: body["voice"] as? String ?? "bm_lewis", conversational: body["conversation"] as? Bool ?? false)
        }
        case "stopSpeech": activeSpeechID = UUID().uuidString; audio?.stop(); resumeConversation()
        case "microphone": if conversationActive { endConversation(cancelReply: true) } else { startConversation(backend: body["backend"] as? String ?? "local", history: body["history"] as? [[String: String]] ?? [], greeting: true, voice: body["voice"] as? String ?? "bm_lewis") }
        case "interrupt": interruptConversation()
        case "conversationError": endConversation(cancelReply: false)
        default: break
        }
    }
}
