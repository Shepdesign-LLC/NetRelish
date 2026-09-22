# Vault — the Me card (design, 2026-09-21)

Approved in chat by Ryan. Companion ADR: `docs/adr/0006-identity-lives-in-keychain.md`.

## What
A Keychain-backed identity ("Me card") that NetRelish fills into web forms **only when asked**
(Bench → Fill from Me, ⌘⇧F), optionally overridden per jar. Everything native: Keychain for
storage, Contacts for a one-shot seed, LocalAuthentication for the private tier, Apple's own
Passwords app for passwords (we do not build a password manager).

## Not in v1
Private fields (cards, IDs), the "offer to fill" bar, iframes, autofill on load, the ⌘K entry
(lands with the palette PR).

## 1. Storage — `Sources/Vault/`
- `Identity: Codable, Equatable` — givenName, familyName, email, phone, street, city, state,
  postalCode, country. All `String`, empty = unset. `isEmpty`.
- `IdentityField: CaseIterable` — one case per property, each with a `tier` (`.public`/`.private`)
  and the HTML `autocomplete` tokens it answers to. v1: every field is `.public`.
- `VaultStore` — Security-framework wrapper. Service `com.shepdesign.netrelish.vault`,
  accounts `me` and `jar:<jarId>`. Attributes: `kSecUseDataProtectionKeychain`,
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`.
  Private-tier writes take a `SecAccessControl(.biometryCurrentSet)` (path exists, unused in v1).
  API: `identity(for jarId: String?) -> Identity?` (jar override wins, then `me`),
  `save(_:for:)`, `remove(for:)`, `hasOverride(for:)`. Errors are thrown, never swallowed.
- **Not in the Pantry / MSON.** Identity is not browsing data; keeping it out of GRDB keeps it
  out of FTS, embeddings, and Ask the Pantry by construction.

## 2. Per-jar override
Keychain account `jar:<jarId>`. `JarSheet` gains a disclosure "Use a different card in this jar"
with the same fields; deleting a jar removes its item. No schema change.

## 3. Seed from Contacts
"Import from my card" → `CNContactStore.unifiedMeContactWithKeys` once, copy into `me`. Needs
`NSContactsUsageDescription` and `com.apple.security.personal-information.addressbook`. No
ongoing access.

## 4. Fill — `Sources/Bench/FormFill.swift`
- Nothing injected on load. On ⌘⇧F, `evaluateJavaScript` (main frame, `.page` world) runs a
  script that scans `input/select/textarea`, matches by `autocomplete` token first, then
  `name`/`id`/`type` heuristics, sets values through the native value setter and dispatches
  `input` + `change` so framework forms notice, and returns the count filled.
- Bench menu item "Fill from Me" ⌘⇧F, disabled with no active tab.
- Feedback: "Filled 4 fields from Me" in the address bar for ~2 s. No toast, no relish.
- Empty card → onboarding sheet instead of filling (see 5).

## 5. Settings + onboarding
- `Settings` scene (⌘,) with a "Me" pane: the fields, Import from my card, Clear.
- First ⌘⇧F with an empty card: sheet with the cog at 48pt (manifest §7 onboarding placement),
  one line — "Your card stays in your Keychain. NetRelish fills forms only when you ask." —
  primary **Import from my card**, secondary **Fill it in by hand** (opens Settings → Me).

## 6. Tests
- Hosted `VaultStoreTests`: round-trip, jar override precedence, remove, non-sync attribute.
- Hosted `FormFillTests`: local HTML fixture in a real `WKWebView`; counts and values; a field
  with `autocomplete="off"` and a `password` field are never touched.
- `IdentityTests` (unhosted): field→token mapping, `isEmpty`, Contacts→Identity mapping.

## Rule check
#4 (script, no model, nothing reads the page except field metadata on demand) · #5 (device-only,
non-syncing Keychain; Contacts read once, locally) · #6 (per-jar card mirrors per-jar profile).

## Brand check
§4 relish placements only (primary button, focus ring) · §7 cog in onboarding · §8 no new Bench
chrome · no emoji.

## Plan
1. `Sources/Vault/Identity.swift` + unhosted `IdentityTests` (TDD).
2. `VaultStore` + hosted `VaultStoreTests`.
3. `FormFill` script + hosted `FormFillTests`.
4. Menu, Workbench hook, address-bar status, onboarding sheet, Settings pane, JarSheet override.
5. Entitlement + usage string, project.yml, regenerate xcodeproj, CI green, demo.
