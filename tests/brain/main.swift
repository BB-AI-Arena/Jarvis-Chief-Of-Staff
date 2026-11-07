import Foundation
let brain = ConversationBrain()
let started = Date()
let checks: [(String, String)] = [
    ("Hello Jarvis. Reply with one short greeting.", "reply"),
    ("Ask Astra to analyse the tradeoffs of an append-only event log versus mutable task rows for an agent office.", "astra"),
    ("In your own Jarvis source folder, create a file called worker-smoke-test.txt containing hello. This is a request to execute the task.", "task")
]
func check(_ index: Int) {
    if index == checks.count { brain.cancel(); exit(0) }
    let time = Date()
    brain.ask(checks[index].0, history: "") { text, route, error in
        guard error == nil, route == checks[index].1, !(text ?? "").isEmpty else {
            print("FAIL: \(index) \(error ?? route ?? "empty")"); brain.cancel(); exit(1)
        }
        print("PASS: \(route!) routing in \(String(format: "%.2f", Date().timeIntervalSince(time)))s")
        check(index + 1)
    }
}
check(0)
dispatchMain()
