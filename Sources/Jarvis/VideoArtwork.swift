import Foundation
import ImageIO

/// Explicit artwork sources and image conditioning. The local film worker bounds cloud still repair.
enum VideoArtwork {
    struct Reference {
        let source: String
        let image: String
        let sha256: String
        var role: String? = nil
    }
    static func needsReference(_ brief: String) -> Bool {
        let text = brief.lowercased()
        return ["artwork", "reference image", "source image", "these images", "those images", "that image", "my images", "my logo", "our logo"].contains { text.contains($0) }
    }
    static func directory(for brief: String, sources: [String: String]) -> String? {
        let lower = projectName(brief)
        return sources.keys.sorted(by: { $0.count > $1.count }).first(where: { lower.contains(projectName($0)) }).flatMap { sources[$0] }
    }
    private static func projectName(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }
    static func loadSources(support: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: support.appendingPathComponent("video-artwork-sources.json")) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
    }
    static func approvedLook(for brief: String, support: URL) -> Reference? {
        guard let data = try? Data(contentsOf:support.appendingPathComponent("video-look-references.json")),
              let looks = try? JSONSerialization.jsonObject(with:data) as? [String:[String:String]],
              let name = looks.keys.sorted().first(where:{ projectName(brief).contains(projectName($0)) }),
              let look=looks[name], let source=look["source"], let image=look["image"], let hash=look["sha256"] else { return nil }
        return Reference(source:source,image:image,sha256:hash,role:"User-approved cinematic appearance: preserve this character identity, material realism and lighting style")
    }
    static let motionPrompt = "Animate the supplied reference artwork with a subtle cinematic camera push and restrained lighting movement. Preserve the actual subjects, logo, colors, composition and design in the reference image. Do not invent characters, costumes, products, locations or replacement branding. Keep motion gentle so the artwork remains recognizable."
    /// Converts the existing LTX AV text workflow to image conditioning. Refuses unknown graph structures.
    static func conditioned(_ workflow: [String: Any], image: String) -> [String: Any]? {
        func node(_ id: String) -> [String: Any] { workflow[id] as? [String: Any] ?? [:] }
        func inputs(_ id: String) -> [String: Any] { node(id)["inputs"] as? [String: Any] ?? [:] }
        func link(_ id: String, _ key: String, _ target: String, _ slot: Int) -> Bool {
            guard let pair = inputs(id)[key] as? [Any], pair.count == 2 else { return false }
            return pair[0] as? String == target && pair[1] as? Int == slot
        }
        guard !image.isEmpty, !workflow.keys.contains("jarvis_artwork"),
              node("6")["class_type"] as? String == "EmptyLTXVLatentVideo",
              node("5")["class_type"] as? String == "LTXVConditioning",
              node("9")["class_type"] as? String == "LTXVConcatAVLatent",
              node("13")["class_type"] as? String == "CFGGuider",
              node("1")["class_type"] as? String == "CheckpointLoaderSimple",
              link("9", "video_latent", "6", 0),
              link("13", "positive", "5", 0), link("13", "negative", "5", 1),
              inputs("6")["length"] != nil else { return nil }
        var result = workflow
        var reference = inputs("6")
        reference["positive"] = inputs("13")["positive"]
        reference["negative"] = inputs("13")["negative"]
        reference["vae"] = ["1", 2]
        reference["image"] = ["jarvis_artwork", 0]
        reference["strength"] = 1.0
        if let height = reference["height"] as? Int { reference["height"] = max(64, height / 32 * 32) }
        if let width = reference["width"] as? Int { reference["width"] = max(64, width / 32 * 32) }
        result["6"] = ["class_type": "LTXVImgToVideo", "inputs": reference]
        result["jarvis_artwork"] = ["class_type": "LoadImage", "inputs": ["image": image]]
        var latent = node("9"), latentInputs = inputs("9")
        latentInputs["video_latent"] = ["6", 2]; latent["inputs"] = latentInputs; result["9"] = latent
        var guider = node("13"), guiderInputs = inputs("13")
        guiderInputs["positive"] = ["6", 0]; guiderInputs["negative"] = ["6", 1]
        guider["inputs"] = guiderInputs; result["13"] = guider
        return result
    }
    static func manifest(_ references: [Reference], shots: Int) -> String {
        manifest(references, indices: Array(0..<shots))
    }
    static func manifest(_ references: [Reference], indices: [Int]) -> String {
        guard !references.isEmpty else { return "" }
        return "\n\nArtwork references (actual image conditioning, SHA-256 of source bytes):\n" + indices.enumerated().map { i, index in
            let ref = references[index % references.count]
            return "- Shot \(i + 1): \(ref.source) · sha256 \(ref.sha256) · ComfyUI input \(ref.image)"
        }.joined(separator: "\n")
    }
    static let storyboardSystem = """
    You are a film director turning the user's commands and stories into cinematic scenes, using supplied artwork as visual reference. Preserve the user's explicit characters, actions, event order, setting and ending. Never turn a requested narrative into a commercial, product montage or logo reveal unless the user asked for one. Your job is an idea that develops, not a slideshow. Inspect the labelled reference images. Choose one coherent dramatic interpretation with an opening, development, and an ending that fulfills the user's story. Every shot must advance that concept and have a different purpose, framing and action. Select the specific reference_index each shot needs, and choose references to preserve character identity and visual continuity across the story. Respect requested duration. References are artwork to direct, not scenes that must be shown as flat posters. Design fully realized cinematic scenes, purposeful character action, motivated camera movement, lighting, editing and sound. Maintain continuity across shots. Use artwork to define character and object identity, not the composition of every scene. Create the fictional settings and props needed for the user's story; do not replace the characters with posters, floating product pictures or logo animations. Avoid requiring legible generated text; tell the story visually. Preserve the observed characters, branding and colors. The images are the source of truth; ignore conflicting, unverified color descriptions in the brief. Never invent product capabilities or prices. Avoid generic slow push-ins repeated across shots, random character changes, unrelated spectacle, or five seconds per image by default. Use at least three beats for videos of six seconds or more; make cuts purposeful. Keep generated lettering out of motion shots. The ending must complete the requested action; do not substitute a logo card for the narrative ending. Build a sound progression in shot prompts (e.g. a short rising pulse resolving on the final beat), with no unrequested speech. No invented copyrighted music.
    Return only JSON: {"title":"...","concept":"One sentence explaining the idea and why the progression works", "continuity":"A detailed shared character, costume, prop, world, lighting and sound description repeated across the film", "shots":[{"reference_index":0,"reference_indices":[0],"purpose":"Hook: ...", "seconds":2,"image_prompt":"A detailed composition of the NEW physical scene at the start of this shot", "prompt":"A complete image-to-video direction: action unfolds from that starting scene"}, ...]}. Reference indices are zero-based. Each shot needs one to three reference_indices: include the approved cinematic look for recurring characters when supplied, plus any artwork that defines the shot's prop or other subject. image_prompt must describe the opening frame with the physical subject present, not the end of the action or a collage. Describe each reference's role explicitly. Use the same character identity across shots. Do not add arbitrary outfit, mask or prop changes. Durations must add up exactly to the requested total; each shot is at most five seconds. Do not output placeholders or claim a render happened.
    """
    static func storyboard(_ raw: String, references: Int, total: Int) -> VideoPlan.Plan? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(raw[start...end].utf8)) as? [String: Any],
              let items = object["shots"] as? [[String: Any]],
              items.allSatisfy({ (1...5).contains($0["seconds"] as? Int ?? 0) }),
              items.reduce(0, { $0 + ($1["seconds"] as? Int ?? 0) }) == total,
              let plan = VideoPlan.parse(raw, renderer: .comfy, total: total), plan.shots.count == items.count,
              let concept = plan.concept, concept.count >= 20, plan.seconds == total,
              total < 6 || plan.shots.count >= 3,
              Set(plan.shots.map { $0.prompt.lowercased() }).count == plan.shots.count,
              plan.shots.allSatisfy({ shot in
                  guard let index = shot.referenceIndex, let purpose = shot.purpose else { return false }
                  return (0..<references).contains(index) && !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else { return nil }
        return plan
    }
    /// Labelled, bounded previews let Creative see source content before choosing shots.
    static func previews(_ references: [Reference], server: String, completion: @escaping ([[String: Any]]?) -> Void) {
        var blocks: [[String: Any]] = []
        func next(_ index: Int) {
            guard index < references.count else { completion(blocks); return }
            let ref = references[index]
            var url = URLComponents(string: server + "/view")!
            let path = ref.image as NSString
            url.queryItems = [URLQueryItem(name: "filename", value: path.lastPathComponent), URLQueryItem(name: "subfolder", value: path.deletingLastPathComponent == "." ? "" : path.deletingLastPathComponent), URLQueryItem(name: "type", value: "input")]
            var request = URLRequest(url: url.url!); request.timeoutInterval = 15
            URLSession.shared.dataTask(with: request) { data, response, _ in
                let source = data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
                let image = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 768] as CFDictionary) }
                let encoded = NSMutableData()
                var good = false
                if (response as? HTTPURLResponse)?.statusCode == 200, let image,
                   let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
                    good = CGImageDestinationFinalize(destination)
                }
                let ok = good
                DispatchQueue.main.async {
                    guard ok else { completion(nil); return }
                    blocks.append(["type": "text", "text": "Reference \(index): " + (ref.source as NSString).lastPathComponent + (ref.role.map { " · " + $0 } ?? "")])
                    blocks.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": (encoded as Data).base64EncodedString()]])
                    next(index + 1)
                }
            }.resume()
        }
        next(0)
    }
    /// Runs the bundled importer on DARK. It fits the complete artwork without cropping and uploads it via ComfyUI's API, retaining the original source hash.
    static func prepare(directory: String, brief: String, server: String, workflow: [String: Any], dark: DarkServer, completion: @escaping ([Reference]?, String?) -> Void) {
        guard directory.hasPrefix("/home/"), !directory.contains("\n"),
              let scriptURL = Bundle.main.url(forResource: "prepare-video-artwork", withExtension: "py"),
              let script = try? Data(contentsOf: scriptURL) else {
            completion(nil, "Artwork needs a configured absolute /home/ directory on DARK and the bundled artwork importer."); return
        }
        let latent = (workflow["6"] as? [String: Any])?["inputs"] as? [String: Any] ?? [:]
        let width = max(64, (latent["width"] as? Int ?? 1280) / 32 * 32)
        let height = max(64, (latent["height"] as? Int ?? 720) / 32 * 32)
        let args: [Any] = [directory, brief, server, width, height]
        let encodedArgs = (try! JSONSerialization.data(withJSONObject: args)).base64EncodedString()
        let code = "import base64,json,sys;sys.argv=['artwork']+json.loads(base64.b64decode('\(encodedArgs)'));exec(base64.b64decode('\(script.base64EncodedString())'))"
        // Only base64 and fixed Python syntax enter the remote shell.
        let command = "python3 -c '" + code.replacingOccurrences(of: "'", with: "'\\''") + "'"
        dark.run(command, timeout: 90) { status, output in
            guard status == 0, let data = output.data(using: .utf8), let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
                completion(nil, "Could not prepare artwork from DARK: " + String(output.suffix(500))); return
            }
            let refs = rows.compactMap { row -> Reference? in
                guard let source = row["source"], let image = row["image"], let hash = row["sha256"] else { return nil }
                return Reference(source: source, image: image, sha256: hash)
            }
            completion(refs.isEmpty ? nil : refs, refs.isEmpty ? "No usable artwork images found. No video was generated." : nil)
        }
    }
}
