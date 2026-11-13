import Foundation

/// Film subprocesses use the same persisted Creative allowance as the native app.
/// Only these two bounded provider operations are permitted; credentials stay native.
enum FilmProviderBroker {
    static let version = "jarvis-film-budget-v1"
    static func request(_ packet: [String:Any], key: (String)->String?) -> URLRequest? {
        guard Set(packet.keys) == Set(["url","body"]),let url = packet["url"] as? String,
              let body = packet["body"] as? [String:Any] else { return nil }
        let provider: String
        if url == "https://api.anthropic.com/v1/messages" {
            guard Set(body.keys).isSubset(of:Set(["model","max_tokens","system","messages","thinking"])),
                  ["claude-opus-5-5","claude-sonnet-5-5"].contains(body["model"] as? String ?? ""),
                  body["messages"] is [[String:Any]] else { return nil }
            provider = "claude"
        } else if url == "https://api.x.ai/v1/images/edits" {
            guard Set(body.keys).isSubset(of:Set(["model","prompt","images","n","aspect_ratio","resolution","quality","response_format"])),
                  body["response_format"] as? String == "b64_json", body["aspect_ratio"] as? String == "16:9" else { return nil }
            provider = "grok"
        } else { return nil }
        var request = URLRequest(url:URL(string:url)!)
        request.httpMethod = "POST";request.timeoutInterval = 240
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject:body)
        guard SpendBudget.maximum(request) != nil,let credential = key(provider) else { return nil }
        if provider == "claude" {
            request.setValue(credential,forHTTPHeaderField:"x-api-key")
            request.setValue("2023-06-01",forHTTPHeaderField:"anthropic-version")
        } else { request.setValue("Bearer " + credential,forHTTPHeaderField:"Authorization") }
        return request
    }
    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) { completionHandler(nil) }
    }
    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard data.count <= 40_000_000,let packet = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              let request = request(packet,key:{ $0 == "claude" ? ClaudeCredential.read() : GrokCredential.read() }) else {
            print("{\"error\":\"Film request denied: unsupported operation, pricing, payload or unavailable credential.\"}");exit(2)
        }
        let session = URLSession(configuration:.ephemeral,delegate:NoRedirect(),delegateQueue:nil)
        BudgetHTTP.dataTask(with:request,seat:"creative",session:session) { data,response,error in
            guard error == nil,(response as? HTTPURLResponse)?.statusCode == 200,let data else {
                print("{\"error\":\"Film provider request failed or the daily Creative allowance could not cover it. Checkpoint retained.\"}");exit(3)
            }
            FileHandle.standardOutput.write(data);exit(0)
        }.resume()
        dispatchMain()
    }
}
