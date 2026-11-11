import Foundation

/// Anthropic key for the Chief Technology Officer and the fast router. Stored in the macOS Keychain through KeychainBroker; the page never receives this value.
enum ClaudeCredential {
    private static let service = "ai.fourfront.jarvis.claude"
    private static let account = "anthropic-api-key"
    static func read() -> String? { KeychainBroker.read(service: service, account: account) }
    static func save(_ key: String) -> Bool { KeychainBroker.save(service: service, account: account, value: key) }
}
