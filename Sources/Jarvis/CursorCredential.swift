import Foundation

/// Cursor key for the Creative Director. Stored in the macOS Keychain through KeychainBroker; the page never receives this value.
enum CursorCredential {
    private static let service = "ai.fourfront.jarvis.cursor"
    private static let account = "cursor-api-key"
    static func read() -> String? { KeychainBroker.read(service: service, account: account) }
    static func save(_ key: String) -> Bool { KeychainBroker.save(service: service, account: account, value: key) }
}
