// Timestamp.swift — RFC 3161, the one outside service Pro provenance uses (non-negotiable 5).
//
// What leaves the Mac is a SHA-256 fingerprint of the saved copy and a random number, nothing
// else: never the page, its address or its title. The authority signs "this fingerprint
// existed at this time" and sends the signature back as a token, which anyone can check
// later with standard tools (`openssl ts -verify`).
//
// This file writes the request and reads the reply. It checks that the reply answers our
// request: the same fingerprint, the same nonce. Checking the authority's signature is the
// app's job (Security framework, macOS only), so this stays plain Swift for PantryKit.

import Foundation

public enum TimestampError: Error, Equatable {
    /// The authority answered but refused, with its PKIStatus (2 rejection, 3 waiting, ...).
    case refused(status: Int)
    /// The reply wasn't a timestamp reply, or not one we can read.
    case malformed
    /// The reply is a valid token for some other request.
    case doesNotMatch
}

/// A timestamp request for one fingerprint.
public struct TimestampRequest: Sendable, Equatable {
    /// SHA-256 of the saved copy, 32 bytes.
    public let digest: [UInt8]
    /// A random number the reply must echo, so an old reply can't be replayed.
    public let nonce: [UInt8]

    /// sha256: 2.16.840.1.101.3.4.2.1
    static let sha256OID: [UInt8] = [0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]

    public init(digest: [UInt8], nonce: [UInt8]? = nil) {
        precondition(digest.count == 32, "a SHA-256 digest is 32 bytes")
        self.digest = digest
        self.nonce = nonce ?? TimestampRequest.randomNonce()
    }

    /// Eight random bytes, top bit clear and never zero first, so the INTEGER is positive and
    /// minimal exactly as written.
    static func randomNonce() -> [UInt8] {
        var bytes = (0..<8).map { _ in UInt8.random(in: 0...255) }
        bytes[0] = UInt8.random(in: 1...0x7F)
        return bytes
    }

    /// The DER TimeStampReq: version 1, the SHA-256 imprint, the nonce, and certReq so the
    /// token carries the authority's certificate and can be checked on its own.
    public var der: Data {
        let algorithm = DER.sequenceOf([TimestampRequest.sha256OID, [DER.null, 0x00]])
        let imprint = DER.sequenceOf([algorithm, DER.encode(DER.octetString, digest)])
        let request = DER.sequenceOf([
            DER.encode(DER.integer, [0x01]),
            imprint,
            DER.unsignedInteger(nonce),
            [DER.boolean, 0x01, 0xFF],
        ])
        return Data(request)
    }

    /// The media type authorities expect for `der`.
    public static let contentType = "application/timestamp-query"
}

/// A timestamp the authority granted, read from its token.
public struct Timestamp: Sendable, Equatable {
    /// The signed token (a CMS SignedData), exactly as the authority sent it. This is the proof.
    public let token: Data
    /// When the authority says the fingerprint existed.
    public let time: Date
    /// The authority's serial number for this stamp, in hex.
    public let serial: String

    /// Reads a TimeStampResp, and checks it answers `request`.
    public init(response: Data, for request: TimestampRequest) throws {
        let parts: [DER.Element]
        do {
            parts = try DER.parseOne(Array(response)).expect(DER.sequence).children()
        } catch {
            throw TimestampError.malformed
        }
        guard let statusInfo = parts.first,
              let statusElement = try? statusInfo.expect(DER.sequence).children().first,
              let status = try? DER.smallInt(statusElement) else { throw TimestampError.malformed }
        // 0 granted, 1 granted with modifications. Anything else is a refusal.
        guard status == 0 || status == 1 else { throw TimestampError.refused(status: status) }
        guard parts.count > 1 else { throw TimestampError.malformed }
        try self.init(token: Data(parts[1].raw), for: request)
    }

    /// Reads a token on its own (as stored, or from an exported proof), and checks it answers
    /// `request` when one is given.
    public init(token: Data, for request: TimestampRequest? = nil) throws {
        let info: TSTInfo
        do {
            info = try TSTInfo(token: Array(token))
        } catch {
            throw TimestampError.malformed
        }
        if let request {
            guard info.algorithm == TimestampRequest.sha256OID, info.digest == request.digest,
                  info.nonce.map({ Timestamp.sameInteger($0, request.nonce) }) ?? false
            else { throw TimestampError.doesNotMatch }
        }
        self.token = token
        self.time = info.time
        self.serial = info.serial.map { String(format: "%02X", $0) }.joined()
    }

    /// The SHA-256 fingerprint the token vouches for.
    public static func digest(in token: Data) throws -> [UInt8] {
        do {
            let info = try TSTInfo(token: Array(token))
            guard info.algorithm == TimestampRequest.sha256OID else { throw TimestampError.malformed }
            return info.digest
        } catch {
            throw TimestampError.malformed
        }
    }

    /// The bytes the authority signed (the TSTInfo inside the token), as this parser finds
    /// them. Whoever checks the signature compares these with what the signature covers, so
    /// the timestamp that was read and the timestamp that was verified are the same one.
    public static func signedContent(in token: Data) throws -> Data {
        do {
            return Data(try TSTInfo.content(of: Array(token)))
        } catch {
            throw TimestampError.malformed
        }
    }

    /// Two INTEGER values compared as numbers (a leading zero byte doesn't change one).
    static func sameInteger(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        Array(a.drop { $0 == 0 }) == Array(b.drop { $0 == 0 })
    }
}

/// The signed content of a timestamp token (RFC 3161 §2.4.2), as much of it as we read.
struct TSTInfo {
    let algorithm: [UInt8]   // the OID element, whole
    let digest: [UInt8]
    let serial: [UInt8]
    let time: Date
    let nonce: [UInt8]?

    /// id-signedData 1.2.840.113549.1.7.2
    static let signedDataOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
    /// id-ct-TSTInfo 1.2.840.113549.1.9.16.1.4
    static let tstInfoOID: [UInt8] = [0x06, 0x0B, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x10, 0x01, 0x04]

    init(token: [UInt8]) throws {
        let fields = try DER.parseOne(try TSTInfo.content(of: token)).expect(DER.sequence).children()
        // TSTInfo ::= SEQUENCE { version, policy, messageImprint, serialNumber, genTime,
        //                        accuracy OPTIONAL, ordering DEFAULT FALSE, nonce OPTIONAL, ... }
        guard fields.count >= 5 else { throw DER.Failure.unexpected("TSTInfo") }
        let imprint = try fields[2].expect(DER.sequence).children()
        guard imprint.count == 2, let algorithm = try imprint[0].expect(DER.sequence).children().first else {
            throw DER.Failure.unexpected("imprint")
        }
        self.algorithm = algorithm.raw
        self.digest = try imprint[1].expect(DER.octetString).value
        self.serial = try fields[3].expect(DER.integer).value
        self.time = try DER.generalizedTime(fields[4])
        // The nonce is the only bare INTEGER after genTime (accuracy is a SEQUENCE, ordering
        // a BOOLEAN, tsa and extensions are tagged).
        self.nonce = fields.dropFirst(5).first { $0.tag == DER.integer }?.value
    }

    /// The signed bytes inside a token: the OCTET STRING that holds the TSTInfo.
    static func content(of token: [UInt8]) throws -> [UInt8] {
        // ContentInfo ::= SEQUENCE { contentType, [0] EXPLICIT SignedData }
        let contentInfo = try DER.parseOne(token).expect(DER.sequence).children()
        guard contentInfo.count == 2, contentInfo[0].raw == TSTInfo.signedDataOID else {
            throw DER.Failure.unexpected("not SignedData")
        }
        // SignedData ::= SEQUENCE { version, digestAlgorithms, encapContentInfo, ... }
        let signedData = try contentInfo[1].expect(DER.context0).children()
        guard let signed = try signedData.first?.expect(DER.sequence).children(), signed.count >= 3 else {
            throw DER.Failure.unexpected("SignedData")
        }
        // EncapsulatedContentInfo ::= SEQUENCE { eContentType, [0] EXPLICIT OCTET STRING }
        let encapsulated = try signed[2].expect(DER.sequence).children()
        guard encapsulated.count == 2, encapsulated[0].raw == TSTInfo.tstInfoOID,
              let content = try encapsulated[1].expect(DER.context0).children().first else {
            throw DER.Failure.unexpected("not TSTInfo")
        }
        return try content.expect(DER.octetString).value
    }
}
