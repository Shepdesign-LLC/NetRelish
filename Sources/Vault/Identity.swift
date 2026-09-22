// Identity.swift — the Me card. Nine strings and the HTML autocomplete tokens each one answers
// to. Lives in the Keychain (VaultStore), never in the Pantry — ADR 0006.

import Foundation

/// One card's worth of identity. Empty string means unset.
struct Identity: Codable, Equatable, Sendable {
    var givenName = ""
    var familyName = ""
    var email = ""
    var phone = ""
    var street = ""
    var city = ""
    var state = ""
    var postalCode = ""
    var country = ""

    var isEmpty: Bool { IdentityField.allCases.allSatisfy { self[$0].isEmpty } }

    subscript(field: IdentityField) -> String {
        get {
            switch field {
            case .givenName: givenName
            case .familyName: familyName
            case .email: email
            case .phone: phone
            case .street: street
            case .city: city
            case .state: state
            case .postalCode: postalCode
            case .country: country
            }
        }
        set {
            switch field {
            case .givenName: givenName = newValue
            case .familyName: familyName = newValue
            case .email: email = newValue
            case .phone: phone = newValue
            case .street: street = newValue
            case .city: city = newValue
            case .state: state = newValue
            case .postalCode: postalCode = newValue
            case .country: country = newValue
            }
        }
    }

    static func encode(_ identity: Identity) throws -> Data { try JSONEncoder().encode(identity) }
    static func decode(_ data: Data) throws -> Identity { try JSONDecoder().decode(Identity.self, from: data) }
}

/// The fields, in the order the Settings pane shows them.
enum IdentityField: String, CaseIterable, Sendable {
    case givenName, familyName, email, phone, street, city, state, postalCode, country

    enum Tier: Sendable { case `public`, `private` }

    /// Public fills without asking. Private sits behind Touch ID. v1 ships nothing private.
    var tier: Tier { .public }

    var label: String {
        switch self {
        case .givenName: "First name"
        case .familyName: "Last name"
        case .email: "Email"
        case .phone: "Phone"
        case .street: "Street"
        case .city: "City"
        case .state: "State"
        case .postalCode: "ZIP"
        case .country: "Country"
        }
    }

    /// WHATWG autocomplete field names this field answers to (the last token of the attribute).
    var autocompleteTokens: [String] {
        switch self {
        case .givenName: ["given-name"]
        case .familyName: ["family-name"]
        case .email: ["email"]
        case .phone: ["tel", "tel-national"]
        case .street: ["street-address", "address-line1"]
        case .city: ["address-level2"]
        case .state: ["address-level1"]
        case .postalCode: ["postal-code"]
        case .country: ["country-name", "country"]
        }
    }

    /// Resolves a full `autocomplete` attribute: "section-blue shipping tel" → `.phone`.
    /// "off", "on", and anything we don't hold (cc-*, passwords) resolve to nil.
    init?(autocomplete: String) {
        guard let last = autocomplete.lowercased().split(separator: " ").last else { return nil }
        guard let field = IdentityField.allCases.first(where: { $0.autocompleteTokens.contains(String(last)) }) else { return nil }
        self = field
    }
}
