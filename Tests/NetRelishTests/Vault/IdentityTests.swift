import Testing
@testable import NetRelish

@Suite("Identity") struct IdentityTests {

    @Test("A fresh identity is empty; any field makes it non-empty")
    func emptiness() {
        #expect(Identity().isEmpty)
        var me = Identity()
        me.email = "ryan@example.com"
        #expect(!me.isEmpty)
    }

    @Test("Every field answers to at least one autocomplete token, and no token is claimed twice")
    func tokensAreUniqueAndComplete() {
        var seen: [String: IdentityField] = [:]
        for field in IdentityField.allCases {
            #expect(!field.autocompleteTokens.isEmpty, "\(field) has no tokens")
            for token in field.autocompleteTokens {
                #expect(seen[token] == nil, "\(token) claimed by both \(seen[token]!) and \(field)")
                seen[token] = field
            }
        }
    }

    @Test("Standard tokens map to the fields a form would expect")
    func standardTokens() {
        #expect(IdentityField(autocomplete: "given-name") == .givenName)
        #expect(IdentityField(autocomplete: "family-name") == .familyName)
        #expect(IdentityField(autocomplete: "email") == .email)
        #expect(IdentityField(autocomplete: "tel") == .phone)
        #expect(IdentityField(autocomplete: "street-address") == .street)
        #expect(IdentityField(autocomplete: "address-line1") == .street)
        #expect(IdentityField(autocomplete: "address-level2") == .city)
        #expect(IdentityField(autocomplete: "address-level1") == .state)
        #expect(IdentityField(autocomplete: "postal-code") == .postalCode)
        #expect(IdentityField(autocomplete: "country-name") == .country)
        // Section prefixes and the "shipping"/"billing" hints are stripped: "shipping postal-code".
        #expect(IdentityField(autocomplete: "shipping postal-code") == .postalCode)
        #expect(IdentityField(autocomplete: "section-blue billing tel") == .phone)
        #expect(IdentityField(autocomplete: "off") == nil)
        #expect(IdentityField(autocomplete: "cc-number") == nil)
    }

    @Test("v1 ships every field public")
    func allPublic() {
        #expect(IdentityField.allCases.allSatisfy { $0.tier == .public })
    }

    @Test("Values are read and written by field")
    func subscriptByField() {
        var me = Identity()
        me[.city] = "Denver"
        #expect(me[.city] == "Denver")
        #expect(me.city == "Denver")
        #expect(me[.email] == "")
    }

    @Test("Identity round-trips through JSON, which is how it lives in the Keychain")
    func codable() throws {
        var me = Identity()
        me.givenName = "Ryan"; me.postalCode = "80202"
        let data = try Identity.encode(me)
        #expect(try Identity.decode(data) == me)
    }
}

import Contacts

@Suite("Identity from Contacts") struct IdentityFromContactsTests {
    @Test("The first email, phone, and postal address come across; a two-line street becomes one")
    func mapsMeCard() {
        let c = CNMutableContact()
        c.givenName = "Ryan"; c.familyName = "Shepherd"
        c.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "ryan@example.com"), CNLabeledValue(label: CNLabelHome, value: "second@example.com")]
        c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "303-555-0100"))]
        let a = CNMutablePostalAddress()
        a.street = "1 Main St\nSuite 4"; a.city = "Denver"; a.state = "CO"; a.postalCode = "80202"; a.country = "United States"
        c.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: a)]
        let me = Identity(contact: c)
        #expect(me.givenName == "Ryan" && me.familyName == "Shepherd")
        #expect(me.email == "ryan@example.com")
        #expect(me.phone == "303-555-0100")
        #expect(me.street == "1 Main St, Suite 4" && me.city == "Denver" && me.state == "CO")
        #expect(me.postalCode == "80202" && me.country == "United States")
    }

    @Test("An empty card maps to an empty identity")
    func emptyCard() {
        #expect(Identity(contact: CNMutableContact()).isEmpty)
    }
}
