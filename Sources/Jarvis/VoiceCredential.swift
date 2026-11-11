import Foundation

/// OpenAI key for realtime voice. Stored in the macOS Keychain through KeychainBroker; the page never receives this value.
enum VoiceCredential {
    private static let service = "ai.fourfront.jarvis.realtime-voice"
    private static let account = "openai-api-key"
    static func read() -> String? { KeychainBroker.read(service: service, account: account) }
    static func save(_ key: String) -> Bool { KeychainBroker.save(service: service, account: account, value: key) }
}
