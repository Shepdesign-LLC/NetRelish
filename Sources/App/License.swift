// License.swift — the Direct build's license key (ADR 0027).
//
// Pro in the App Store build is StoreKit's business (Pro.swift). The Direct build is sold
// through Creem instead, and Creem's license API needs the store's secret key, which can't
// ship inside an app. So the app talks to a relay on netrelish.com (`NR_LICENSE_ACTIVATION_URL`,
// read from Info.plist as `NRLicenseActivationURL`) that holds the key and forwards the call.
//
// Non-negotiable 5 names this as the one license call the app may make. What it sends is the
// license key and a random name for this Mac, nothing else. It goes out only when the person
// presses Activate, Check Again or Deactivate This Mac: never at launch, never on a timer.
// What comes back is kept in the Keychain, on this Mac only.

import Foundation
import Security
import os

/// What the relay says about a key. The first four are Creem's own; `invalid` is a key the
/// store doesn't know, `rejected` one it refused (in use on as many Macs as it allows, say),
/// and `unknown` anything else it said.
enum LicenseStatus: String, Codable, Sendable {
    case active, inactive, expired, disabled, invalid, rejected, unknown
}

/// A license on this Mac, as the Keychain keeps it.
struct License: Codable, Equatable, Sendable {
    let key: String
    /// Creem's name for this Mac's activation. Needed to check it again or to give it up.
    let instanceID: String
    var status: LicenseStatus
    /// When the license runs out, for a yearly one. Nil for one that doesn't.
    var expires: Date?
    /// When the relay last said any of this.
    var checked: Date

    func unlocks(at now: Date) -> Bool {
        status == .active && (expires.map { $0 > now } ?? true)
    }

    /// The key as the person typed or pasted it, tidied: spaces, tabs and line breaks around
    /// it dropped. Nil unless what's left could be a key: 8 to 128 letters, digits, `-` or `_`.
    static func normalized(_ typed: String) -> String? {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...128).contains(key.count),
              key.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") })
        else { return nil }
        return key
    }

    /// The name this Mac goes by in the store: random, so it says nothing about the person or
    /// the Mac. The store shows it beside the key, which is how a Mac is told apart there.
    static func newInstanceName() -> String {
        "NetRelish-" + UUID().uuidString.prefix(8).lowercased()
    }
}

/// The relay's answer, reduced to what decides Pro.
struct LicenseReply: Equatable, Sendable {
    let status: LicenseStatus
    let instanceID: String?
    let expires: Date?
}

/// The relay couldn't be reached, or answered with something that isn't an answer.
struct LicenseUnreachable: Error {}

/// A build whose relay address is set but isn't one: every question goes unanswered, so Pro
/// stays locked instead of open.
struct NoLicenseRelay: LicenseAuthority {
    func activate(key: String, instanceName: String) async throws -> LicenseReply { throw LicenseUnreachable() }
    func validate(key: String, instanceID: String) async throws -> LicenseReply { throw LicenseUnreachable() }
    func deactivate(key: String, instanceID: String) async throws -> LicenseReply { throw LicenseUnreachable() }
}

/// Who answers for license keys. The app has one, `LicenseRelay`; tests bring their own.
protocol LicenseAuthority: Sendable {
    func activate(key: String, instanceName: String) async throws -> LicenseReply
    func validate(key: String, instanceID: String) async throws -> LicenseReply
    func deactivate(key: String, instanceID: String) async throws -> LicenseReply
}

/// Where this Mac's license is kept. The app has one, `LicenseKeychain`; tests bring their own.
protocol LicenseVault: Sendable {
    func load() throws -> License?
    func save(_ license: License) throws
    func remove() throws
}

// MARK: - The relay

struct LicenseRelay: LicenseAuthority {
    let url: URL
    private let session: URLSession

    private static let log = Logger(subsystem: "com.shepdesign.netrelish", category: "license")

    /// A real answer is a few hundred bytes. Anything longer isn't one, and isn't read.
    static let replyLimit = 8_192

    /// No cookies and no cache. The relay sees this Mac's address and the time, as any web
    /// server does, along with the key and this Mac's random name.
    private static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 30
        // NETRELISH-ALLOW-ENDPOINT: adr-0027 — the Direct build's license activation, allowed by rule 5
        return URLSession(configuration: configuration)
    }()

    /// What this build is set up with. Not set (an empty address) keeps the Direct build
    /// unlocked, as previews were before license keys. Set but not an https address fails
    /// closed: Pro stays locked rather than open to everyone.
    enum Setup { case notSet, relay(LicenseRelay), broken }

    static var configured: Setup {
        setup(from: Bundle.main.object(forInfoDictionaryKey: "NRLicenseActivationURL") as? String)
    }

    /// No address is a build without the license key; an address that isn't a relay is a
    /// broken build, which must lock Pro rather than give it away.
    static func setup(from address: String?) -> Setup {
        let text = (address ?? "").trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return .notSet }
        return LicenseRelay(address: text).map(Setup.relay) ?? .broken
    }

    /// Nil unless `address` is an https address with a host and no sign-in folded into it.
    /// A license key never travels in the clear. Tests pass a session that answers for the relay.
    init?(address: String, session: URLSession? = nil) {
        guard let url = URL(string: address), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        self.url = url
        self.session = session ?? LicenseRelay.shared
    }

    func activate(key: String, instanceName: String) async throws -> LicenseReply {
        try await ask(["action": "activate", "key": key, "instance_name": instanceName])
    }

    func validate(key: String, instanceID: String) async throws -> LicenseReply {
        try await ask(["action": "validate", "key": key, "instance_id": instanceID])
    }

    func deactivate(key: String, instanceID: String) async throws -> LicenseReply {
        try await ask(["action": "deactivate", "key": key, "instance_id": instanceID])
    }

    private func ask(_ fields: [String: String]) async throws -> LicenseReply {
        var post = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("application/json", forHTTPHeaderField: "Accept")
        post.setValue("NetRelish", forHTTPHeaderField: "User-Agent")
        post.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        let (status, body): (Int, Data)
        do {
            (status, body) = try await reply(to: post)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            LicenseRelay.log.error("license \(fields["action"] ?? "", privacy: .public): \(errorKind(error), privacy: .public)")
            throw LicenseUnreachable()
        }
        switch status {
        case 200: return try LicenseRelay.read(body)
        // A 404 or 409 is the store's verdict only when the relay itself says so. Any other
        // 404 (a page that moved, an outage, the site mid-move) is no answer: it must never
        // lock Pro, or make Deactivate forget an activation the store still counts.
        case 404 where LicenseRelay.says(.invalid, in: body):
            return LicenseReply(status: .invalid, instanceID: nil, expires: nil)
        case 409 where LicenseRelay.says(.rejected, in: body):
            return LicenseReply(status: .rejected, instanceID: nil, expires: nil)
        default:
            LicenseRelay.log.error("license \(fields["action"] ?? "", privacy: .public): HTTP \(status)")
            throw LicenseUnreachable()
        }
    }

    /// Sends `post` and returns the status and the reply's bytes. A redirect comes back as the
    /// reply, not followed: the key goes to the relay that was asked and nowhere else.
    private func reply(to post: URLRequest) async throws -> (Int, Data) {
        // NETRELISH-ALLOW-ENDPOINT: adr-0027 — the one POST of a license key to the relay
        let (stream, response) = try await session.bytes(for: post, delegate: NoRedirects())
        defer { stream.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw LicenseUnreachable() }
        let limit = LicenseRelay.replyLimit
        guard response.expectedContentLength <= Int64(limit) else { throw LicenseUnreachable() }
        let bytes = try await stream.prefix(limit + 1).reduce(into: Data()) { $0.append($1) }
        guard bytes.count <= limit else { throw LicenseUnreachable() }
        return (http.statusCode, bytes)
    }

    /// `{"status": …, "instance_id": …, "expires_at": …}`, as the relay answers a 200.
    static func read(_ body: Data) throws -> LicenseReply {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let statusText = object["status"] as? String else { throw LicenseUnreachable() }
        // An activation id the relay would refuse to take back is no id: without it this Mac
        // could never check the license again or give the activation back.
        let instanceID = (object["instance_id"] as? String).flatMap { isInstanceID($0) ? $0 : nil }
        // Absent or null means the license doesn't run out. A date that can't be read is no
        // answer, never "forever": the date is what locks a lapsed year without a call.
        var expires: Date?
        if let raw = object["expires_at"], !(raw is NSNull) {
            guard let text = raw as? String, let date = date(from: text) else { throw LicenseUnreachable() }
            expires = date
        }
        return LicenseReply(status: LicenseStatus(rawValue: statusText) ?? .unknown,
                            instanceID: instanceID, expires: expires)
    }

    /// Whether `body` is the relay's own `{"status": "<status>"}`.
    static func says(_ status: LicenseStatus, in body: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        return object["status"] as? String == status.rawValue
    }

    /// The relay's rule for an activation id: 1 to 128 letters, digits, `-` or `_`.
    static func isInstanceID(_ text: String) -> Bool {
        (1...128).contains(text.count)
            && text.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }

    /// ISO 8601, with or without fractional seconds.
    static func date(from text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// Refuses to follow a redirect, so a license key only ever goes to the relay that was asked.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

// MARK: - The Keychain

/// This Mac's license in the login Keychain, never synchronized, as VaultStore keeps the Me
/// card (ADR 0006). One item.
struct LicenseKeychain: LicenseVault {
    static let live = LicenseKeychain(service: "com.shepdesign.netrelish.license")

    let service: String
    private static let account = "license"

    func load() throws -> License? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw VaultError(status: status) }
        // A license this build can't read is the same as none: the person activates again.
        return try? LicenseKeychain.decoder.decode(License.self, from: data)
    }

    func save(_ license: License) throws {
        let data = try LicenseKeychain.encoder.encode(license)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess: return
        case errSecItemNotFound:
            var add = query
            add[kSecValueData as String] = data
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw VaultError(status: added) }
        default: throw VaultError(status: status)
        }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: LicenseKeychain.account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
