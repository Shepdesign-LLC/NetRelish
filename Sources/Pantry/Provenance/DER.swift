// DER.swift — just enough ASN.1 DER to write an RFC 3161 timestamp request and read the
// reply. Definite lengths and one-byte tags only, which is all RFC 3161 and CMS use; anything
// else is refused rather than guessed at.

import Foundation

enum DER {
    enum Failure: Error, Equatable {
        case truncated
        case unsupported
        case unexpected(String)
    }

    static let sequence: UInt8 = 0x30
    static let set: UInt8 = 0x31
    static let boolean: UInt8 = 0x01
    static let integer: UInt8 = 0x02
    static let octetString: UInt8 = 0x04
    static let null: UInt8 = 0x05
    static let objectIdentifier: UInt8 = 0x06
    static let generalizedTime: UInt8 = 0x18
    static let context0: UInt8 = 0xA0

    /// One TLV: its tag, its value bytes, and the whole element as it was encoded.
    struct Element: Equatable {
        let tag: UInt8
        let value: [UInt8]
        let raw: [UInt8]

        /// The elements inside a constructed one (a SEQUENCE, a SET, an explicit [n] tag).
        func children() throws -> [Element] {
            guard tag & 0x20 != 0 else { throw Failure.unexpected("not constructed") }
            return try DER.parseAll(value)
        }

        /// The value checked against an expected tag.
        func expect(_ expected: UInt8) throws -> Element {
            guard tag == expected else {
                throw Failure.unexpected(String(format: "tag %02X, expected %02X", tag, expected))
            }
            return self
        }
    }

    // MARK: Reading

    /// Exactly one element, with nothing after it.
    static func parseOne(_ bytes: [UInt8]) throws -> Element {
        var index = 0
        let element = try parse(bytes, at: &index)
        guard index == bytes.count else { throw Failure.unexpected("trailing bytes") }
        return element
    }

    static func parseAll(_ bytes: [UInt8]) throws -> [Element] {
        var index = 0
        var out: [Element] = []
        while index < bytes.count { out.append(try parse(bytes, at: &index)) }
        return out
    }

    static func parse(_ bytes: [UInt8], at index: inout Int) throws -> Element {
        let start = index
        guard index < bytes.count else { throw Failure.truncated }
        let tag = bytes[index]
        guard tag & 0x1F != 0x1F else { throw Failure.unsupported }   // multi-byte tags
        index += 1
        guard index < bytes.count else { throw Failure.truncated }
        let first = bytes[index]
        index += 1
        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            guard count > 0 else { throw Failure.unsupported }        // indefinite length (BER)
            guard count <= 4 else { throw Failure.unsupported }
            guard index + count <= bytes.count else { throw Failure.truncated }
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard length >= 0, index + length <= bytes.count else { throw Failure.truncated }
        let value = Array(bytes[index..<(index + length)])
        index += length
        return Element(tag: tag, value: value, raw: Array(bytes[start..<index]))
    }

    /// An INTEGER's value as an unsigned number, for small ones (versions, statuses).
    static func smallInt(_ element: Element) throws -> Int {
        _ = try element.expect(integer)
        guard !element.value.isEmpty, element.value.count <= 4 else { throw Failure.unsupported }
        return element.value.reduce(0) { ($0 << 8) | Int($1) }
    }

    /// A GeneralizedTime ("20261105222131Z", optionally with fractional seconds) as a Date.
    static func generalizedTime(_ element: Element) throws -> Date {
        _ = try element.expect(generalizedTime)
        guard let text = String(bytes: element.value, encoding: .ascii), text.hasSuffix("Z"),
              text.count >= 15 else { throw Failure.unexpected("time") }
        let digits = Array(text.utf8)
        func number(_ from: Int, _ count: Int) throws -> Int {
            var value = 0
            for i in from..<(from + count) {
                let d = Int(digits[i]) - 48
                guard (0...9).contains(d) else { throw Failure.unexpected("time") }
                value = value * 10 + d
            }
            return value
        }
        var parts = DateComponents()
        parts.year = try number(0, 4)
        parts.month = try number(4, 2)
        parts.day = try number(6, 2)
        parts.hour = try number(8, 2)
        parts.minute = try number(10, 2)
        parts.second = try number(12, 2)
        var fraction = 0.0
        if digits.count > 15, digits[14] == UInt8(ascii: ".") {
            let tail = String(decoding: digits[15..<(digits.count - 1)], as: UTF8.self)
            fraction = Double("0." + tail) ?? 0
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: parts) else { throw Failure.unexpected("time") }
        return date.addingTimeInterval(fraction)
    }

    // MARK: Writing

    static func encode(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [tag]
        if value.count < 0x80 {
            out.append(UInt8(value.count))
        } else {
            var length = value.count
            var bytes: [UInt8] = []
            while length > 0 {
                bytes.insert(UInt8(length & 0xFF), at: 0)
                length >>= 8
            }
            out.append(0x80 | UInt8(bytes.count))
            out += bytes
        }
        return out + value
    }

    static func sequenceOf(_ parts: [[UInt8]]) -> [UInt8] {
        encode(sequence, parts.flatMap { $0 })
    }

    /// A non-negative INTEGER from big-endian bytes, made minimal.
    static func unsignedInteger(_ bytes: [UInt8]) -> [UInt8] {
        var value = Array(bytes.drop { $0 == 0 })
        if value.isEmpty { value = [0] }
        if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
        return encode(integer, value)
    }
}
