// TimestampService.swift — the app's RFC 3161 authority for Pro provenance (ADR 0022).
//
// Non-negotiable 5 lists RFC 3161 timestamping as one of the app's only network calls. This
// is it: one POST of a fingerprint and a random number to the address in the build settings
// (`NR_TIMESTAMP_URL`, read from Info.plist as `NRTimestampURL`). The page, its address and
// its title never leave the Mac.
//
// The request travels in the clear, so anyone on the network between can answer it. The
// reply is therefore treated as a stranger's until it proves otherwise (ADR 0025):
//   - it is read from the address that was asked, never from wherever a redirect points;
//   - it is read up to the size of a timestamp and no further;
//   - before it is kept, its signature is checked with the Security framework, and the
//     signer must hold a certificate issued for time stamping that this Mac trusts;
//   - a reply that fails any of that is the same as no reply. The page waits for the next
//     try, and nothing a stranger sends can mark it failed.

import Foundation
import Pantry
import Security
import os

struct TimestampService: TimestampAuthority {
    let url: URL
    private let session: URLSession
    var name: String { url.host ?? url.absoluteString }

    private static let log = Logger(subsystem: "com.shepdesign.netrelish", category: "provenance")

    /// A real reply is a few kilobytes. Anything longer isn't one, and isn't read.
    static let replyLimit = 65_536

    /// No cookies and no cache. The authority, and the network on the way to it, still see
    /// this Mac's address and when each request is made.
    private static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        // The whole exchange, not only the pauses in it: a reply that trickles is given up on.
        configuration.timeoutIntervalForResource = 60
        // NETRELISH-ALLOW-ENDPOINT: adr-0022 — RFC 3161 timestamping, allowed by rule 5
        return URLSession(configuration: configuration)
    }()

    /// The authority this build is set up with, or nil when none is (provenance then only
    /// fingerprints).
    static var configured: TimestampService? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "NRTimestampURL") as? String else { return nil }
        return TimestampService(address: text)
    }

    /// Nil unless `address` is a plain web address: http or https, a host, and no sign-in
    /// folded into it. Anything else in the build settings means no authority. Tests pass
    /// a session that answers for the authority; the app always uses its own.
    init?(address: String, session: URLSession? = nil) {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        self.url = url
        self.session = session ?? TimestampService.shared
    }

    func timestamp(_ request: TimestampRequest) async throws -> Data {
        var post = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        post.httpMethod = "POST"
        post.setValue(TimestampRequest.contentType, forHTTPHeaderField: "Content-Type")
        post.setValue("application/timestamp-reply", forHTTPHeaderField: "Accept")
        // Says what is asking and nothing about this Mac: no build, no system version, no language.
        post.setValue("NetRelish", forHTTPHeaderField: "User-Agent")
        post.setValue("en", forHTTPHeaderField: "Accept-Language")
        post.httpBody = request.der
        let data: Data
        do {
            data = try await reply(to: post)
        } catch let error as URLError {
            TimestampService.log.error("timestamp request: \(error.localizedDescription, privacy: .public)")
            throw TimestampUnreachable()
        }
        // Read it (which checks it answers this request), then check who signed it. Whatever
        // is wrong with it, the page isn't blamed: a refusal, a reply for another request and
        // a bad signature can all be sent by anyone on the network, so each one only waits.
        let stamp: Timestamp
        do {
            stamp = try Timestamp(response: data, for: request)
        } catch {
            TimestampService.log.error("timestamp request: the reply wasn't a timestamp for this page (\(String(describing: error), privacy: .public))")
            throw TimestampUnreachable()
        }
        guard TimestampService.signatureIsValid(stamp.token) else {
            TimestampService.log.error("timestamp token: signature or certificate didn't check out")
            throw TimestampUnreachable()
        }
        return data
    }

    /// Sends `post` and returns the reply's bytes. A redirect, anything but a 200 (a server
    /// error, a Wi-Fi sign-in page answering for everyone) and a reply longer than a timestamp
    /// all count as not reaching the authority.
    private func reply(to post: URLRequest) async throws -> Data {
        // NETRELISH-ALLOW-ENDPOINT: adr-0022 — the one POST of a fingerprint to the authority
        let (stream, response) = try await session.bytes(for: post, delegate: StayPut())
        defer { stream.task.cancel() }   // whatever is left unread stops arriving
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            TimestampService.log.error("timestamp request: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw TimestampUnreachable()
        }
        let limit = TimestampService.replyLimit
        guard response.expectedContentLength <= Int64(limit) else {
            TimestampService.log.error("timestamp request: the reply is too long to be a timestamp")
            throw TimestampUnreachable()
        }
        // One byte past the limit is enough to know, and is where reading stops.
        let bytes = try await stream.prefix(limit + 1).reduce(into: Data()) { $0.append($1) }
        guard bytes.count <= limit else {
            TimestampService.log.error("timestamp request: the reply is too long to be a timestamp")
            throw TimestampUnreachable()
        }
        return bytes
    }

    /// True when the token is a CMS message signed by a time-stamping certificate this Mac
    /// trusts, and what it signed is the timestamp the Pantry read.
    static func signatureIsValid(_ token: Data) -> Bool {
        // The time-stamping policy, not the basic one. The basic policy accepts any certificate
        // this Mac trusts for anything (signing mail, signing code), and such a certificate is
        // easy to come by. This one also requires that the certificate was issued for time
        // stamping, which only a timestamp authority's is.
        guard let policy = SecPolicyCreateWithProperties(kSecPolicyAppleTimeStamping, nil),
              let read = try? Timestamp.signedContent(in: token) else { return false }
        var made: CMSDecoder?
        guard CMSDecoderCreate(&made) == errSecSuccess, let decoder = made else { return false }
        let fed = token.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, buffer.count)
        }
        guard fed == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return false }
        var signers = 0
        guard CMSDecoderGetNumSigners(decoder, &signers) == errSecSuccess, signers == 1 else { return false }
        // The decoder is handed the signed content rather than left to find it. Asked as-is it
        // never answers "valid" for a timestamp token: what a token signs is a TSTInfo, not
        // plain data, and the decoder only hashes plain data on its own, so it answers "needs
        // the content" for every real token there is. What it's handed are the very bytes the
        // Pantry read the fingerprint, the nonce and the time from, so the timestamp that was
        // verified and the timestamp that was read cannot be two different things.
        guard CMSDecoderSetDetachedContent(decoder, read as CFData) == errSecSuccess else { return false }
        // `true` evaluates the signer's certificate chain against this Mac's trust settings:
        // `.valid` means the signature checks out and the certificate is trusted for this.
        var status = CMSSignerStatus.unsigned
        var chain = errSecSuccess
        let checked = CMSDecoderCopySignerStatus(decoder, 0, policy, true, &status, nil, &chain)
        guard checked == errSecSuccess, status == .valid, chain == errSecSuccess else {
            log.error("timestamp token: OSStatus \(checked), signer status \(status.rawValue), chain \(chain)")
            return false
        }
        return true
    }
}

/// Refuses to follow a redirect. The fingerprint goes to the authority that was asked, and
/// the answer comes from it; a 301 or 302 comes back as the reply, and isn't a timestamp.
private final class StayPut: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
