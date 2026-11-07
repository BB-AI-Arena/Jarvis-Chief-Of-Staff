import Foundation
let credential = Process(), pipe = Pipe()
credential.executableURL = URL(fileURLWithPath:"/usr/bin/security")
credential.arguments = ["find-generic-password","-s","ai.fourfront.jarvis.realtime-voice","-a","openai-api-key","-w"]
credential.standardOutput = pipe; credential.standardError = FileHandle.nullDevice
try credential.run(); let keyData = pipe.fileHandleForReading.readDataToEndOfFile(); credential.waitUntilExit()
guard credential.terminationStatus == 0, let key=String(data:keyData,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines), !key.isEmpty else { exit(2) }
var request=URLRequest(url:URL(string:"wss://api.openai.com/v1/live/sessions")!);request.setValue("Bearer "+key,forHTTPHeaderField:"Authorization")
let session=URLSession(configuration:.ephemeral), ws=session.webSocketTask(with:request)
func send(_ value:[String:Any]) async throws { let d=try JSONSerialization.data(withJSONObject:value);try await ws.send(.string(String(data:d,encoding:.utf8)!)) }
Task {
 do {
  let start=Date();ws.resume()
  try await send(["type":"session.start","session":["model":"gpt-live-1","instructions":"You are Jarvis. Speak concise British English. When asked for a greeting say: At your service.","audio":["format":["type":"audio/pcm","rate":24000],"output":["voice":"cedar"]],"delegation":["type":"client"]]])
  var ready=false;var speechAt=Date()
  var sender:Task<Void,Never>?
  while Date().timeIntervalSince(start)<35 {
   let value=try await ws.receive();let data:Data
   switch value {case .data(let d):data=d;case .string(let s):data=Data(s.utf8);@unknown default:continue}
   guard let event=try JSONSerialization.jsonObject(with:data) as? [String:Any],let type=event["type"] as? String else {continue}
   if type=="error" {let e=event["error"] as? [String:Any];print("API error:",e?["code"] ?? "unknown",e?["message"] ?? "no details");break}
   if type=="session.started" {
    ready=true;speechAt=Date();print("Session ready in",Date().timeIntervalSince(start));fflush(stdout)
    sender=Task {while !Task.isCancelled {try? await send(["type":"session.input_audio.append","audio":Data(count:1920).base64EncodedString()]);try? await Task.sleep(nanoseconds:40_000_000)}}
    try await send(["type":"session.commentary.append","event_id":"greeting_probe","delegation_id":NSNull(),"content":"Greet the caller now. Say: At your service. Then listen."])
   }
   if type=="session.output_audio.delta", let delta=event["delta"] as? String,!delta.isEmpty {
    print("PASS: actual API audio received; first audio seconds:",Date().timeIntervalSince(speechAt));sender?.cancel();try? await send(["type":"session.close","event_id":"close_probe"]);ws.cancel(with:.normalClosure,reason:nil);exit(0)
   }
   if type=="session.closed" {break}
  }
  sender?.cancel();print("No audio completed; ready:",ready);ws.cancel(with:.normalClosure,reason:nil);exit(1)
 }catch {print("Voice connection failed:",error.localizedDescription);exit(1)}
}
DispatchQueue.main.asyncAfter(deadline:.now()+40){ws.cancel(with:.goingAway,reason:nil);print("Voice test timed out");exit(1)}
dispatchMain()
