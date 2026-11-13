import Foundation

// A bounded proof of the narrative/reference workflow. No render runs without an explicit budget.
let story = "Drop Assassin comes to life and uses the app to find chase items."
let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Jarvis Workspace/Video/film-prototype")
try! FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
let root = "/home/bradshaw/services/collectibles-alert-engine/artwork/"
let named = [("DropAssassinIcon.png","dd394e400e0275ad806902357a63f49f7b109281937fd30eafa6eab98e8c9d8e"),("drop-assassin-logo.png","9ada41c21d410d6b4de6342bd5ba2c2722effc04eb9bdad63d7b033a3c61be64"),("luffy-chase.png","317824cb63d99c59fb3beb7c6d21090d9980a405dd986ea4d184cab68da31872")]
let refs = named.map { VideoArtwork.Reference(source: root + $0.0, image: "jarvis-artwork-" + $0.1 + "-1280x704.png", sha256:$0.1) }
let roles = """
<IMAGE_0>: Use ONLY the central hooded, masked Drop Assassin figure as the recurring protagonist's design reference. Preserve his black hood, angular mask, gold eyes and gold/red accents. Depict him as one consistent fully realized cinematic CG character with a body, interacting physically with his world. The surrounding poster composition and other figures are not the scene.
<IMAGE_1>: Reference for Drop Assassin's visual identity and the phone/app look. Use its app/phone visual language as a reference for the phone he actually holds and operates. Do not turn the story into a logo or product montage.
<IMAGE_2>: The chase collectible he is searching for. Preserve that collectible's design so the object he finds matches the one he first sees in the app.
"""
let prompt = """
Create one coherent 15-second cinematic CG short with three purposeful shots. The user's story is: \(story)
Treat the images as character/object design references for NEW scenes. This is a little film with cause and effect. Maintain the same protagonist, clothes, phone and target collectible throughout.
\(roles)
0–5s — THE AWAKENING. In a dark, cinematic collector's room, gold eyes ignite within the hood. The real three-dimensional Drop Assassin character steps out of the shadows into a pool of warm light. Begin close on his eyes, then reveal his full physical presence. Tactile cloth, polished mask edges, motivated lighting. His phone pulses in his hand; his attention turns to it. No animated poster, no floating logos.
5–10s — THE LEAD. Cut over the same character's shoulder to his hand opening the Drop Assassin app on the same phone. A visual card of the target chase collectible from <IMAGE_2> appears as a find/lead. No dependence on readable tiny text. His thumb selects the lead; his head turns decisively toward a nearby illuminated collector's display. Make the phone interaction the cause of his next action. A short notification ping connects the cut.
10–15s — THE FIND. Follow the SAME character's purposeful move to that display. He reaches past ordinary boxed collectibles and reveals the matching rare chase collectible from <IMAGE_2>, lifting it for a satisfying close-up. End on the same gold-eyed hooded figure holding the found item, phone still in his other hand, the app and the physical find visibly connected. End the story here; do not replace the ending with a brand slate.
One coherent cinematic score: quiet low pulse on awakening, a crisp phone notification and rising momentum on the lead, then one satisfying resolved hit on the find. Cloth, footsteps and handling sounds; no dialogue or narration. High-end cinematic CG lighting, deliberate framing, physical action, coherent spatial continuity, stable character identity. No extra characters, no random spectacle, no collage or generic Ken Burns slideshow.
"""
try! ("USER STORY\n" + story + "\n\nDIRECTOR'S TREATMENT\n" + prompt + "\n\nREFERENCES\n" + refs.map(\.source).joined(separator:"\n") + "\n\nEstimated single request: 15 × $0.14 + 3 × $0.01 = $2.13. Maximum authorized budget required: $3. No automatic generation retries.\n").write(to: support.appendingPathComponent("treatment.txt"), atomically:true, encoding:.utf8)
let render = CommandLine.arguments.contains("--render")
guard render else { print("PREPARED treatment: " + support.appendingPathComponent("treatment.txt").path); print("No generation request sent. Estimate $2.13; --render and JARVIS_FILM_TEST_BUDGET=3 are both required."); exit(0) }
guard let budget = Double(ProcessInfo.processInfo.environment["JARVIS_FILM_TEST_BUDGET"] ?? ""), budget >= 2.13, budget <= 3 else { print("FAIL: explicit budget between $2.13 and $3 required"); exit(1) }
guard let key = GrokCredential.read() else { print("FAIL: no Grok key in Keychain"); exit(1) }
VideoArtwork.previews(refs, server: ComfyVideo.defaultServer) { blocks in
    guard let blocks else { print("FAIL: reference previews unavailable; no render sent"); exit(1) }
    let images = blocks.compactMap { block -> String? in
        guard let source = block["source"] as? [String:Any], let data = source["data"] as? String else { return nil }
        return "data:image/jpeg;base64," + data
    }
    guard images.count == refs.count else { print("FAIL: missing references; no render sent"); exit(1) }
    print("Submitting exactly one 15-second reference-to-video request with 3 images. Estimated $2.13. No retry.")
    let engine = GrokVideo(apiKey:key, resolution:"720p", referenceImages:images)
    engine.render(.init(prompt:prompt,seconds:15), to:support.appendingPathComponent("film.mp4"), isCancelled:{false}) { file, error in
        guard let file else { print("FAIL: " + (error ?? "No video")); exit(1) }
        print("RENDERED draft for review: " + file.path)
        VideoStitcher.thumbnail(file) { thumb in
            if let encoded = thumb?.split(separator:",").last, let data = Data(base64Encoded:String(encoded)) { try? data.write(to:support.appendingPathComponent("preview.jpg")) }
            exit(0)
        }
    }
}
DispatchQueue.main.asyncAfter(deadline:.now()+1000) { print("FAIL: timed out; no automatic retry"); exit(2) }
dispatchMain()
