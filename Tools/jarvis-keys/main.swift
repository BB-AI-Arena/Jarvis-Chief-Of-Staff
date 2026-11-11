import Foundation
import Security

// jarvis-keys: the one program that reads and writes Jarvis's API keys in the macOS Keychain.
//
// Why it exists: macOS ties Keychain "Always Allow" to the exact build of the program that asks. The app is rebuilt
// often, so it was asked again for every key after every build. This helper is built only when THIS file changes,
// so its permission survives app rebuilds.
//
// Trade-off (chosen by the owner on 2026-11-10): any program running as this user can run the helper and read these
// keys without a prompt. It only ever touches Keychain services that start with "ai.fourfront.jarvis.".
//
//   jarvis-keys get <service> <account>      prints the value; exit 44 when there is none
//   jarvis-keys set <service> <account>      reads the value from stdin (never from arguments); empty input deletes

let arguments = CommandLine.arguments
func fail(_ message: String, _ code: Int32) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(code) }
guard arguments.count == 4, ["get", "set"].contains(arguments[1]) else { fail("usage: jarvis-keys get|set <service> <account>", 2) }
let service = arguments[2], account = arguments[3]
let safe = "^[A-Za-z0-9._-]{1,80}$"
guard service.hasPrefix("ai.fourfront.jarvis."), service.range(of: safe, options: .regularExpression) != nil, account.range(of: safe, options: .regularExpression) != nil else {
    fail("jarvis-keys only handles Jarvis's own Keychain entries.", 2)
}
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]

if arguments[1] == "get" {
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &result)
    if status == errSecItemNotFound { exit(44) }
    guard status == errSecSuccess, let data = result as? Data else { fail("Keychain read failed (\(status)).", 1) }
    FileHandle.standardOutput.write(data)
    exit(0)
}

let value = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
if value.isEmpty {
    let status = SecItemDelete(query as CFDictionary)
    exit(status == errSecSuccess || status == errSecItemNotFound ? 0 : 1)
}
var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
if status == errSecItemNotFound {
    var item = query
    item[kSecValueData as String] = Data(value.utf8)
    status = SecItemAdd(item as CFDictionary, nil)
}
exit(status == errSecSuccess ? 0 : 1)
