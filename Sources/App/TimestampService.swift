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
            (data, response) = try await URLSession.shared.data(for: post)
        } catch let error as URLError {
            TimestampService.log.error("timestamp request: \(error.localizedDescription, privacy: .public)")
            throw TimestampUnreachable()
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TimestampError.malformed
        }
        // Read it (which checks it answers this request), then check who signed it.
        let stamp = try Timestamp(response: data, for: request)
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
        return checked == errSecSuccess && status == .valid
    }
}
