import Foundation
import Security

/// All of Jarvis's API keys go through here. Keys stay in the macOS Keychain and never reach the page or the logs.
///
/// Reads and writes are done by the small `jarvis-keys` helper when it is installed, because macOS remembers
/// Keychain permission per exact build: the helper is rebuilt only when its own source changes, so its permission
/// survives app rebuilds. Without the helper, the app talks to the Keychain directly (and macOS asks after each build).
enum KeychainBroker {
    static let helperURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jarvis/bin/jarvis-keys")
    static var helper: URL? { FileManager.default.isExecutableFile(atPath: helperURL.path) ? helperURL : nil }
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func read(service: String, account: String) -> String? {
        let id = service + "/" + account
        lock.lock(); let cached = cache[id]; lock.unlock()
        if let cached { return cached }
        let raw: String?
        if let helper { raw = run(helper, ["get", service, account], input: nil).flatMap { $0.status == 0 ? String(data: $0.output, encoding: .utf8) : nil } }
        else { raw = direct(service: service, account: account) }
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        lock.lock(); cache[id] = value; lock.unlock()
        return value
    }
    @discardableResult
    static func save(service: String, account: String, value: String) -> Bool {
        let id = service + "/" + account
        lock.lock(); cache[id] = nil; lock.unlock()
        if let helper { return run(helper, ["set", service, account], input: Data(value.utf8))?.status == 0 }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if value.isEmpty { let status = SecItemDelete(query as CFDictionary); return status == errSecSuccess || status == errSecItemNotFound }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { return false }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    private static func direct(service: String, account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    /// Runs the helper. The value travels over pipes, never in arguments or the environment.
    private static func run(_ tool: URL, _ arguments: [String], input: Data?) -> (status: Int32, output: Data)? {
        let process = Process(), output = Pipe(), stdin = Pipe()
        process.executableURL = tool
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = stdin
        process.environment = [:]
        do { try process.run() } catch { return nil }
        if let input { stdin.fileHandleForWriting.write(input) }
        try? stdin.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}
