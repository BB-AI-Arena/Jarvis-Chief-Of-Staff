import Foundation
import WebKit

/// Lets the page play and show finished results (videos, images, shot lists) from Jarvis Workspace/Results only.
/// jarvis-media://results/<path inside Results>. Supports byte ranges so videos can seek. Anything outside Results,
/// hidden files and other file types are refused.
final class ResultMedia: NSObject, WKURLSchemeHandler {
    static let scheme = "jarvis-media"
    static let types = ["mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "webm": "video/webm",
                        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp", "gif": "image/gif"]
    let root: () -> URL?
    init(root: @escaping () -> URL?) { self.root = root }

    static func url(for relative: String) -> String {
        "\(scheme)://results/" + (relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative)
    }
    /// The file a media URL points at, or nil when it is outside Results, hidden, or not a media type.
    static func resolve(_ url: URL, root: URL) -> URL? {
        guard url.scheme == scheme, url.host == "results" else { return nil }
        let relative = String(url.path.drop { $0 == "/" })
        let parts = relative.split(separator: "/")
        guard !relative.isEmpty, !parts.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let file = base.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(base.path + "/"), types[file.pathExtension.lowercased()] != nil else { return nil }
        return file
    }
    /// "bytes=a-b", "bytes=a-" or "bytes=-n" against a file of `length` bytes.
    static func range(_ header: String?, length: Int) -> ClosedRange<Int>? {
        guard let header, header.hasPrefix("bytes="), length > 0 else { return nil }
        let spec = header.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let ends = spec.split(separator: "-", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard ends.count == 2 else { return nil }
        switch (ends[0], ends[1]) {
        case let (start?, end?) where start <= end && start < length: return start...min(end, length - 1)
        case let (start?, nil) where start < length: return start...(length - 1)
        case let (nil, suffix?) where suffix > 0: return max(length - suffix, 0)...(length - 1)
        default: return nil
        }
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let root = root(), let file = ResultMedia.resolve(url, root: root),
              let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int,
              let handle = try? FileHandle(forReadingFrom: file) else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)); return
        }
        defer { try? handle.close() }
        let mime = ResultMedia.types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        var headers = ["Content-Type": mime, "Accept-Ranges": "bytes", "Cache-Control": "no-store"]
        let status: Int, data: Data
        if let range = ResultMedia.range(task.request.value(forHTTPHeaderField: "Range"), length: size) {
            try? handle.seek(toOffset: UInt64(range.lowerBound))
            data = (try? handle.read(upToCount: range.count)) ?? Data()
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.lowerBound + data.count - 1)/\(size)"
            status = 206
        } else {
            data = (try? handle.readToEnd()) ?? Data()
            status = 200
        }
        headers["Content-Length"] = String(data.count)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
