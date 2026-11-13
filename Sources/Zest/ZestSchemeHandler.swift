// ZestSchemeHandler.swift — serves the bundled Zest tools on zest://app/, read-only
// (ADR 0015, ADR 0033). It reads files under one folder and nothing else: no network, no
// writes, no listing. What a path may reach is decided by ZestFiles, which is tested alone.
//
// Isolation: WebKit calls a scheme handler on the main thread, but the SDK doesn't mark the
// protocol @MainActor. So the class carries no isolation of its own, holds only a Sendable
// `let`, and steps onto the main actor with `MainActor.assumeIsolated` (which traps if WebKit
// ever calls from elsewhere) before it touches the task. The task isn't Sendable, so it goes
// in through a `nonisolated(unsafe)` local: it is only ever used on the main thread. Each
// request is answered in full inside `start`, so `stop` never has a request of ours running.

import Foundation
import OSLog
import WebKit

private let log = Logger(subsystem: "com.shepdesign.netrelish", category: "zest")

final class ZestSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The folder the tools are read from: Contents/Resources/Zest, or a test's own folder.
    let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let root = self.root
        // The task never leaves the main thread: it is used inside this call and dropped.
        nonisolated(unsafe) let task = urlSchemeTask
        MainActor.assumeIsolated {
            Self.answer(task, root: root)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Nothing to stop: every request was answered before `start` returned.
    }

    /// Answers one request completely: a file, a 404, or a 405 for anything but GET and HEAD.
    @MainActor
    private static func answer(_ task: any WKURLSchemeTask, root: URL) {
        let request = task.request
        guard let url = request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let method = (request.httpMethod ?? "GET").uppercased()
        guard method == "GET" || method == "HEAD" else {
            respond(task, url: url, status: 405, headers: ["Content-Type": "text/plain; charset=utf-8",
                                                           "Content-Security-Policy": ZestFiles.contentSecurityPolicy],
                    body: Data())
            return
        }
        guard let components = ZestFiles.components(for: url),
              let file = ZestFiles.file(for: components, in: root),
              let data = FileManager.default.contents(atPath: file.path(percentEncoded: false)) else {
            log.info("zest: not found")
            let page = Data(ZestFiles.notFoundPage.utf8)
            respond(task, url: url, status: 404,
                    headers: ZestFiles.headers(contentType: "text/html; charset=utf-8", length: page.count),
                    body: method == "HEAD" ? Data() : page)
            return
        }
        let type = ZestFiles.mimeType(forPath: file.lastPathComponent)
        if let range = ZestFiles.byteRange(header: request.value(forHTTPHeaderField: "Range"), length: data.count) {
            var headers = ZestFiles.headers(contentType: type, length: range.count)
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)"
            respond(task, url: url, status: 206, headers: headers,
                    body: method == "HEAD" ? Data() : data.subdata(in: range))
            return
        }
        respond(task, url: url, status: 200, headers: ZestFiles.headers(contentType: type, length: data.count),
                body: method == "HEAD" ? Data() : data)
    }

    @MainActor
    private static func respond(_ task: any WKURLSchemeTask, url: URL, status: Int,
                                headers: [String: String], body: Data) {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: headers) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        if !body.isEmpty { task.didReceive(body) }
        task.didFinish()
    }
}
