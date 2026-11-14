// ZestFiles.swift — what a zest:// URL may read, and how it is answered (ADR 0015, ADR 0033).
//
// The Zest tools are files in the app bundle, under Resources/Zest, served read-only on the
// zest: scheme. Everything here is a pure function of its inputs, so the rules that keep a
// page inside that folder are unit-tested on their own (ZestFilesTests). The scheme handler
// only strings them together.

import Foundation

enum ZestFiles {
    /// The scheme, and the one host it answers for: zest://app/…
    static let scheme = "zest"
    static let host = "app"

    /// The bundled tools: Contents/Resources/Zest, a folder reference. `zest/build.sh --app`
    /// writes it from zest/apps and zest/vendor (ADR 0033), and CI rebuilds it and diffs it
    /// against the committed copy, so it is never hand-edited.
    static var bundledRoot: URL? {
        Bundle.main.resourceURL?.appending(path: "Zest", directoryHint: .isDirectory)
    }

    // MARK: Path resolution

    /// The file a zest:// URL names, as path components under the Zest folder, or nil when it
    /// names nothing a tool may read. `percentEncodedPath` is the URL's path exactly as it
    /// arrived, still percent-encoded, so an encoded separator can't hide in it.
    ///
    /// Refused: any host but `app`; an encoded slash, backslash or NUL; a literal backslash;
    /// an empty segment (`//`, which is how an absolute path would get in); any segment that
    /// starts with a dot (`.`, `..`, `%2e%2e`, hidden files); a segment that doesn't decode;
    /// control characters. A folder (`/`, `/mail/`) means its index.html.
    static func components(host: String?, percentEncodedPath: String) -> [String]? {
        guard host?.lowercased() == Self.host else { return nil }
        let path = percentEncodedPath.isEmpty ? "/" : percentEncodedPath
        guard path.hasPrefix("/"), !path.contains("\\") else { return nil }
        let lowered = path.lowercased()
        for encoded in ["%2f", "%5c", "%00"] where lowered.contains(encoded) { return nil }

        var relative = String(path.dropFirst())
        if relative.isEmpty || relative.hasSuffix("/") { relative += "index.html" }

        var components: [String] = []
        for segment in relative.split(separator: "/", omittingEmptySubsequences: false) {
            guard let decoded = String(segment).removingPercentEncoding,
                  !decoded.isEmpty, !decoded.hasPrefix("."),
                  !decoded.contains("/"), !decoded.contains("\\"),
                  !decoded.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
            else { return nil }
            components.append(decoded)
        }
        return components
    }

    /// The components for a URL, or nil when it isn't a zest:// URL a tool may read.
    static func components(for url: URL?) -> [String]? {
        guard let url, url.scheme?.lowercased() == scheme else { return nil }
        return components(host: url.host(percentEncoded: false), percentEncodedPath: url.path(percentEncoded: true))
    }

    /// The regular file `components` name under `root`, after every symlink is followed, or
    /// nil if it isn't there, is a folder, or resolves outside `root`. Components are checked
    /// again here, so a caller that skipped `components(host:percentEncodedPath:)` still can't
    /// climb out with "..".
    static func file(for components: [String], in root: URL) -> URL? {
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("/") }),
              let base = realPath(root) else { return nil }
        var candidate = root
        for component in components { candidate = candidate.appending(component: component, directoryHint: .notDirectory) }
        guard let resolved = realPath(candidate), isInside(resolved, base) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false), isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return resolved
    }

    /// The canonical path, every symlink followed (realpath(3)), or nil if nothing is there.
    /// Not `resolvingSymlinksInPath`: that one drops a leading /private only when the result
    /// exists, so two paths in one folder can come back spelled differently.
    static func realPath(_ url: URL) -> URL? {
        guard let resolved = realpath(url.path(percentEncoded: false), nil) else { return nil }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    /// Whether `url` is strictly below `root`, compared component by component, so a sibling
    /// called "Zest2" never counts as inside "Zest".
    static func isInside(_ url: URL, _ root: URL) -> Bool {
        let inner = url.standardizedFileURL.pathComponents
        let outer = root.standardizedFileURL.pathComponents
        return inner.count > outer.count && Array(inner.prefix(outer.count)) == outer
    }

    // MARK: Types

    /// Content types by extension. Text is UTF-8. Anything not listed is served as bytes.
    /// It covers every extension in Resources/Zest (ZestBundleTests walks the folder to hold
    /// that), and the ones a tool might add later.
    static let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "htm": "text/html; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "mjs": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "map": "application/json; charset=utf-8",
        "webmanifest": "application/manifest+json; charset=utf-8",
        "txt": "text/plain; charset=utf-8",
        "md": "text/markdown; charset=utf-8",
        "xml": "application/xml; charset=utf-8",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "avif": "image/avif",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "wasm": "application/wasm",
        "mp3": "audio/mpeg",
        "wav": "audio/wav",
        "ogg": "audio/ogg",
        "m4a": "audio/mp4",
        "mp4": "video/mp4",
        "webm": "video/webm",
        "pdf": "application/pdf",
    ]

    /// Files with no extension that are text: the notices beside the vendored libraries
    /// and fonts. Matched on the whole name, exactly as it is spelled in the bundle.
    static let bareTextNames: Set<String> = ["NOTICE", "LICENSE"]

    static func mimeType(forPath path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty, bareTextNames.contains(name) { return "text/plain; charset=utf-8" }
        return mimeTypes[ext] ?? "application/octet-stream"
    }

    // MARK: Headers

    /// The second layer under the content rule list: nothing on the web, in any directive.
    /// Only the tool's own origin, data: and blob:, plus the inline scripts and styles the
    /// single-file tools are made of.
    ///
    /// What the tools need, and where it is allowed: inline scripts, inline event handlers
    /// and inline styles ('unsafe-inline'); the vendored fonts as files, and as data: faces
    /// in ZestImage's SVG and the exports (font-src); data: and blob: images for previews and
    /// exports (img-src); ZestMail's and the studio's srcdoc preview frames, which take this
    /// policy from their parent and need no frame-src of their own; blob: and data: fetches
    /// for exports (connect-src). There is no 'unsafe-eval' and no 'wasm-unsafe-eval': no
    /// tool calls eval or new Function, KaTeX doesn't, and Mermaid's only Function(...) is
    /// lodash's `Function("return this")()`, the fallback for a page with no `self`, which a
    /// browser page never reaches. zest/tests/inapp.js serves the bundle under this exact
    /// policy and fails on any violation; ZestBundleTests does the same in WebKit.
    static let contentSecurityPolicy = [
        "default-src 'self' zest:",
        "script-src 'self' zest: blob: 'unsafe-inline'",
        "style-src 'self' zest: data: blob: 'unsafe-inline'",
        "img-src 'self' zest: data: blob:",
        "font-src 'self' zest: data: blob:",
        "media-src 'self' zest: data: blob:",
        "connect-src 'self' zest: data: blob:",
        "worker-src 'self' zest: blob:",
        "frame-src 'self' zest: data: blob:",
        "manifest-src 'self' zest:",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'none'",
    ].joined(separator: "; ")

    /// Headers for a file the scheme serves.
    static func headers(contentType: String, length: Int) -> [String: String] {
        [
            "Content-Type": contentType,
            "Content-Length": String(length),
            "Content-Security-Policy": contentSecurityPolicy,
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "no-cache",
            "Accept-Ranges": "bytes",
        ]
    }

    /// What a missing file gets: a plain sentence, no outside references.
    static let notFoundPage = """
    <!doctype html><html><head><meta charset="utf-8"><title>Not in this build</title>
    <style>body{font:13px -apple-system,system-ui,sans-serif;color:#666;display:grid;place-items:center;height:90vh;margin:0}</style>
    </head><body><p>This tool isn’t in this build.</p></body></html>
    """

    // MARK: Ranges

    /// The bytes a `Range: bytes=…` header asks for, clamped to the file, or nil when the
    /// header is absent, malformed, asks for several ranges, or can't be satisfied. Media
    /// elements ask for ranges; everything else reads the whole file.
    static func byteRange(header: String?, length: Int) -> Range<Int>? {
        guard let header, length > 0 else { return nil }
        let value = header.trimmingCharacters(in: .whitespaces).lowercased()
        guard value.hasPrefix("bytes="), !value.contains(",") else { return nil }
        let spec = value.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let first = parts[0].trimmingCharacters(in: .whitespaces)
        let last = parts[1].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            // bytes=-N: the last N bytes.
            guard let suffix = Int(last), suffix > 0 else { return nil }
            return max(0, length - suffix)..<length
        }
        guard let start = Int(first), start >= 0, start < length else { return nil }
        if last.isEmpty { return start..<length }
        guard let end = Int(last), end >= start else { return nil }
        return start..<(min(end, length - 1) + 1)
    }
}
