// ContactsImport.swift — "Import from my card": read the Contacts Me card once, copy it into
// the Keychain, and never look at Contacts again. Needs the addressbook sandbox entitlement
// and NSContactsUsageDescription (both in project.yml).

import Contacts

enum ContactsImport {
    enum Failure: Error, CustomStringConvertible {
        case denied, noMeCard
        var description: String {
            switch self {
            case .denied: "NetRelish wasn't allowed to read Contacts. You can allow it in System Settings → Privacy & Security → Contacts."
            case .noMeCard: "Contacts has no “My Card” yet. Set one in Contacts (Card → Make This My Card), or fill it in by hand."
            }
        }
    }

    static var keys: [CNKeyDescriptor] {
        [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey,
         CNContactPhoneNumbersKey, CNContactPostalAddressesKey] as [CNKeyDescriptor]
    }

    /// One read. Throws `.denied` if the person says no, `.noMeCard` if Contacts has none.
    static func meCard() async throws -> Identity {
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else { throw Failure.denied }
        do {
            return Identity(contact: try store.unifiedMeContactWithKeys(toFetch: keys))
        } catch let error as CNError where error.code == .recordDoesNotExist {
            throw Failure.noMeCard
        }
    }
}

extension Identity {
    /// The first email, phone, and postal address on the card. Pure — tested directly.
    init(contact: CNContact) {
        self.init()
        givenName = contact.givenName
        familyName = contact.familyName
        email = contact.emailAddresses.first.map { String($0.value) } ?? ""
        phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        if let address = contact.postalAddresses.first?.value {
            street = address.street.replacingOccurrences(of: "\n", with: ", ")
            city = address.city
            state = address.state
            postalCode = address.postalCode
            country = address.country
        }
    }
}
