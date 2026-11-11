import Foundation

/// xAI key for the Director of Research. Stored in the macOS Keychain through KeychainBroker; the page never receives this value.
enum GrokCredential {
    private static let service = "ai.fourfront.jarvis.grok"
    private static let account = "xai-api-key"
    static func read() -> String? { KeychainBroker.read(service: service, account: account) }
    static func save(_ key: String) -> Bool { KeychainBroker.save(service: service, account: account, value: key) }
}
