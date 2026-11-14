import Foundation
import Testing
@testable import NetRelish

/// What a zest:// URL may read (ADR 0015, ADR 0033): the path rules, the files behind them,
/// the content types, the policy header and byte ranges. All pure, or against a folder the
/// test makes, so nothing here needs WebKit.
@Suite("Zest files") struct ZestFilesTests {

    private func components(_ path: String, host: String? = "app") -> [String]? {
        ZestFiles.components(host: host, percentEncodedPath: path)
    }

    @Test("A folder means its index.html, and the studio is the root")
    func folders() {
        #expect(components("/") == ["index.html"])
        #expect(components("") == ["index.html"])
        #expect(components("/mail/") == ["mail", "index.html"])
        #expect(components("/md/index.html") == ["md", "index.html"])
        #expect(components("/image/fonts/Inter.woff2") == ["image", "fonts", "Inter.woff2"])
    }

    @Test("Percent-encoded names decode once, and only once")
    func decoding() {
        #expect(components("/image/my%20logo.png") == ["image", "my logo.png"])
        // A double-encoded dot is a literal file name with a percent sign in it, not "..".
        #expect(components("/%252e%252e/secret") == ["%2e%2e", "secret"])
    }

    @Test("Traversal is refused, however it is spelled",
          arguments: [
              "/../etc/passwd", "/mail/../../etc/passwd", "/..", "/./index.html", "/mail/./index.html",
              "/%2e%2e/etc/passwd", "/%2E%2E/%2E%2E/etc/passwd", "/mail/%2e%2e/%2e%2e/secret",
              "/.%2e/secret", "/%2e./secret",
              "/..%2fetc%2fpasswd", "/mail%2F..%2F..%2Fsecret", "/%2fetc/passwd",
              "/..%5c..%5csecret", "/mail\\..\\secret", "/%5cetc",
              "//etc/passwd", "/mail//index.html", "///", "/index.html%00.png",
              "/.hidden", "/mail/.DS_Store", "/%0a", "/bad%zzencoding",
              "etc/passwd",
          ])
    func traversal(_ path: String) {
        #expect(components(path) == nil, "\(path) should be refused")
    }

    @Test("Only zest://app is served")
    func hosts() {
        #expect(components("/", host: "APP") == ["index.html"])
        #expect(components("/", host: nil) == nil)
        #expect(components("/", host: "") == nil)
        #expect(components("/", host: "example.com") == nil)
        #expect(ZestFiles.components(for: URL(string: "zest://app/mail/")) == ["mail", "index.html"])
        #expect(ZestFiles.components(for: URL(string: "https://app/mail/")) == nil)
        #expect(ZestFiles.components(for: URL(string: "zest:///etc/passwd")) == nil)
        #expect(ZestFiles.components(for: URL(string: "zest://app//etc/passwd")) == nil)
        #expect(ZestFiles.components(for: URL(string: "zest://app/mail/?q=..%2f")) == ["mail", "index.html"])
    }

    // MARK: Files on disk

    /// A Zest folder with a tool, an asset, and three symlinks: one to a file outside, one to
    /// a folder outside, one to a file inside.
    private func folder() throws -> (root: URL, outside: URL) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "zest-files-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = base.appending(path: "Zest", directoryHint: .isDirectory)
        let outside = base.appending(path: "outside", directoryHint: .isDirectory)
        try fm.createDirectory(at: root.appending(path: "mail", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("<p>studio</p>".utf8).write(to: root.appending(path: "index.html"))
        try Data("<p>mail</p>".utf8).write(to: root.appending(path: "mail/index.html"))
        try Data("secret".utf8).write(to: outside.appending(path: "secret.txt"))
        try fm.createSymbolicLink(at: root.appending(path: "leak.txt"), withDestinationURL: outside.appending(path: "secret.txt"))
        try fm.createSymbolicLink(at: root.appending(path: "away"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: root.appending(path: "alias.html"), withDestinationURL: root.appending(path: "index.html"))
        // A sibling whose name starts with the root's: never "inside" by prefix.
        try fm.createDirectory(at: base.appending(path: "Zest2", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try Data("sibling".utf8).write(to: base.appending(path: "Zest2/index.html"))
        return (root, outside)
    }

    @Test("Files inside the folder are found; folders and missing files are not")
    func filesInside() throws {
        let (root, _) = try folder()
        #expect(ZestFiles.file(for: ["index.html"], in: root)?.lastPathComponent == "index.html")
        #expect(ZestFiles.file(for: ["mail", "index.html"], in: root) != nil)
        #expect(ZestFiles.file(for: ["mail"], in: root) == nil)            // a folder
        #expect(ZestFiles.file(for: ["nothing.html"], in: root) == nil)
        #expect(ZestFiles.file(for: ["alias.html"], in: root) != nil)      // a link that stays inside
    }

    @Test("A symlink that resolves outside the folder is refused")
    func symlinksOutside() throws {
        let (root, _) = try folder()
        #expect(ZestFiles.file(for: ["leak.txt"], in: root) == nil)
        #expect(ZestFiles.file(for: ["away", "secret.txt"], in: root) == nil)
    }

    @Test("Even components that slipped past the path rules can't climb out")
    func componentsCannotClimb() throws {
        let (root, _) = try folder()
        #expect(ZestFiles.file(for: ["..", "outside", "secret.txt"], in: root) == nil)
        #expect(ZestFiles.file(for: ["..", "Zest2", "index.html"], in: root) == nil)
        #expect(!ZestFiles.isInside(root.deletingLastPathComponent().appending(path: "Zest2/index.html"), root))
        #expect(!ZestFiles.isInside(root, root))
    }

    // MARK: Types and headers

    @Test("Content types by extension, UTF-8 for text, bytes for the unknown",
          arguments: [
              ("index.html", "text/html; charset=utf-8"),
              ("app.js", "text/javascript; charset=utf-8"),
              ("mod.MJS", "text/javascript; charset=utf-8"),
              ("site.css", "text/css; charset=utf-8"),
              ("zest.json", "application/json; charset=utf-8"),
              ("manifest.webmanifest", "application/manifest+json; charset=utf-8"),
              ("icon.svg", "image/svg+xml"),
              ("photo.PNG", "image/png"),
              ("photo.jpeg", "image/jpeg"),
              ("photo.webp", "image/webp"),
              ("Inter.woff2", "font/woff2"),
              ("KaTeX.ttf", "font/ttf"),
              ("lib.wasm", "application/wasm"),
              ("ding.mp3", "audio/mpeg"),
              ("README", "application/octet-stream"),
              ("blob.bin", "application/octet-stream"),
          ])
    func mimeTypes(_ name: String, _ type: String) {
        #expect(ZestFiles.mimeType(forPath: name) == type)
    }

    @Test("The policy names no web origin in any directive")
    func policy() {
        let directives = ZestFiles.contentSecurityPolicy.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(directives.contains { $0.hasPrefix("connect-src") })
        #expect(directives.contains { $0.hasPrefix("default-src") })
        #expect(directives.contains("object-src 'none'"))
        for directive in directives {
            for source in directive.split(separator: " ").dropFirst() {
                let token = source.lowercased()
                #expect(!token.hasPrefix("http"), "\(directive) allows \(token)")
                #expect(!token.hasPrefix("ws"), "\(directive) allows \(token)")
                #expect(!token.contains("*"), "\(directive) allows a wildcard")
                #expect(!token.hasPrefix("file"), "\(directive) allows \(token)")
            }
        }
        let headers = ZestFiles.headers(contentType: "text/html; charset=utf-8", length: 12)
        #expect(headers["Content-Security-Policy"] == ZestFiles.contentSecurityPolicy)
        #expect(headers["Content-Length"] == "12")
        #expect(headers["X-Content-Type-Options"] == "nosniff")
    }

    @Test("Byte ranges for media, clamped to the file")
    func ranges() {
        #expect(ZestFiles.byteRange(header: nil, length: 100) == nil)
        #expect(ZestFiles.byteRange(header: "bytes=0-9", length: 100) == 0..<10)
        #expect(ZestFiles.byteRange(header: "bytes=90-", length: 100) == 90..<100)
        #expect(ZestFiles.byteRange(header: "bytes=-10", length: 100) == 90..<100)
        #expect(ZestFiles.byteRange(header: "bytes=50-500", length: 100) == 50..<100)
        #expect(ZestFiles.byteRange(header: "bytes=100-", length: 100) == nil)
        #expect(ZestFiles.byteRange(header: "bytes=9-0", length: 100) == nil)
        #expect(ZestFiles.byteRange(header: "bytes=0-1,4-5", length: 100) == nil)
        #expect(ZestFiles.byteRange(header: "items=0-1", length: 100) == nil)
        #expect(ZestFiles.byteRange(header: "bytes=0-0", length: 0) == nil)
    }

    @Test("The missing-file page loads nothing from anywhere")
    func notFoundPage() {
        let page = ZestFiles.notFoundPage.lowercased()
        #expect(!page.contains("http"))
        #expect(!page.contains("src="))
    }
}
