// TimestampService.swift — the app's RFC 3161 authority for Pro provenance (ADR 0022).
//
// Non-negotiable 5 lists RFC 3161 timestamping as one of the app's only network calls. This
// is it: one POST of a fingerprint and a random number to the address in the build settings
// (`NR_TIMESTAMP_URL`, read from Info.plist as `NRTimestampURL`). The page, its address and
// its title never leave the Mac.
//
// The authority's reply is signed. Before it is kept, its signature and certificate chain are
// checked with the Security framework, so a reply that was tampered with on the way, or came
// from somewhere else, is refused.

import Foundation
import Pantry
import Security
import os

struct TimestampService: TimestampAuthority {
    let url: URL
    var name: String { url.host ?? url.absoluteString }

    private static let log = Logger(subsystem: "com.shepdesign.netrelish", category: "provenance")

    /// No cookies, no cache, nothing kept between requests: no stamp can be linked to another.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        // NETRELISH-ALLOW-ENDPOINT: adr-0022 — RFC 3161 timestamping, allowed by rule 5
        return URLSession(configuration: configuration)
    }()

    /// The authority this build is set up with, or nil when none is (provenance then only
    /// fingerprints).
    static var configured: TimestampService? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "NRTimestampURL") as? String,
              !text.isEmpty, let url = URL(string: text), url.host != nil else { return nil }
        return TimestampService(url: url)
    }

    func timestamp(_ request: TimestampRequest) async throws -> Data {
        var post = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        post.httpMethod = "POST"
        post.setValue(TimestampRequest.contentType, forHTTPHeaderField: "Content-Type")
        post.setValue("application/timestamp-reply", forHTTPHeaderField: "Accept")
        post.httpBody = request.der
        let data: Data
        let response: URLResponse
        do {
            // NETRELISH-ALLOW-ENDPOINT: adr-0022 — the one POST of a fingerprint to the authority
            (data, response) = try await TimestampService.session.data(for: post)
        } catch let error as URLError {
            TimestampService.log.error("timestamp request: \(error.localizedDescription, privacy: .public)")
            throw TimestampUnreachable()
        }
        // Anything but a timestamp reply (a server error, a Wi-Fi sign-in page answering for
        // everyone) is treated as not reaching the authority: it waits, and isn't counted.
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            TimestampService.log.error("timestamp request: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw TimestampUnreachable()
        }
        // Read it (which checks it answers this request), then check who signed it.
        let stamp: Timestamp
        do {
            stamp = try Timestamp(response: data, for: request)
        } catch TimestampError.malformed {
            TimestampService.log.error("timestamp request: the reply wasn't a timestamp")
            throw TimestampUnreachable()
        }
        guard TimestampService.signatureIsValid(stamp.token) else {
            TimestampService.log.error("timestamp token: signature or certificate didn't check out")
            throw TimestampError.malformed
        }
        return data
    }

    /// True when the token is a CMS message signed by a certificate this Mac trusts.
    static func signatureIsValid(_ token: Data) -> Bool {
        var made: CMSDecoder?
        guard CMSDecoderCreate(&made) == errSecSuccess, let decoder = made else { return false }
        let fed = token.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, buffer.count)
        }
        guard fed == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return false }
        var signers = 0
        guard CMSDecoderGetNumSigners(decoder, &signers) == errSecSuccess, signers == 1 else { return false }
        // `true` evaluates the signer's certificate chain against this Mac's trust settings:
        // `.valid` means the signature checks out and the certificate is trusted.
        var status = CMSSignerStatus.unsigned
        let checked = CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), true, &status, nil, nil)
        if checked != errSecSuccess || status != .valid {
            log.error("timestamp token: OSStatus \(checked), signer status \(status.rawValue)")
        }
        return checked == errSecSuccess && status == .valid
    }
}
