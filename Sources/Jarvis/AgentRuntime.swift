import Foundation

/// The worker adapter is configurable independently of the conversational UI.
enum AgentRuntime {
    static var executable: URL? {
        let path = ProcessInfo.processInfo.environment["JARVIS_AGENT_RUNTIME"]
            ?? Bundle.main.object(forInfoDictionaryKey: "JarvisAgentRuntime") as? String
        guard let path = path, path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
