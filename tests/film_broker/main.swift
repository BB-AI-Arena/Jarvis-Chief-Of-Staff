import Foundation
// No credential read or network call is used by this contract test.
enum ClaudeCredential { static func read()->String? { nil } }
enum GrokCredential { static func read()->String? { nil } }
let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
SpendBudget.directory=root;defer {try? FileManager.default.removeItem(at:root)}
func packet(_ url:String="https://api.anthropic.com/v1/messages",_ body:[String:Any]=["model":"claude-opus-5-5","max_tokens":12000,"system":"Writing","messages":[["role":"user","content":"Script"]]])->[String:Any] { ["url":url,"body":body] }
let valid=FilmProviderBroker.request(packet(),key:{_ in "fixture-not-a-key"})!
assert(valid.url?.absoluteString=="https://api.anthropic.com/v1/messages" && valid.value(forHTTPHeaderField:"x-api-key")=="fixture-not-a-key")
for url in ["http://api.anthropic.com/v1/messages","https://api.anthropic.com.evil.test/v1/messages","https://evil.test/v1/messages","https://api.anthropic.com/v1/messages?redirect=1","https://api.anthropic.com/v1/files"] { assert(FilmProviderBroker.request(packet(url),key:{_ in fatalError("Must reject before credential access")})==nil) }
var bad=packet();var body=bad["body"] as! [String:Any];body["tools"]=[["type":"web_search"]];bad["body"]=body
assert(FilmProviderBroker.request(bad,key:{_ in fatalError("Unexpected tool must be denied")})==nil)
body=["model":"grok-imagine-image-2.0","prompt":"Frame","images":[["type":"image_url","url":"data:image/png;base64,AAAA"]],"n":1,"resolution":"2k","quality":"medium","aspect_ratio":"16:9","response_format":"b64_json"]
let image=FilmProviderBroker.request(packet("https://api.x.ai/v1/images/edits",body),key:{_ in "fixture"})!
assert(SpendBudget.maximum(image)==90_000)
body["n"]=2;assert(FilmProviderBroker.request(packet("https://api.x.ai/v1/images/edits",body),key:{_ in fatalError("Batch refused")})==nil)
assert(SpendBudget.reserve(seat:"creative",microUSD:9_950_000))
assert(SpendBudget.authorize(image,seat:"creative")==nil)
print("PASS: film broker pins provider URLs, rejects tools and extra outputs before reading credentials, prices reference images and enforces shared Creative allowance")
