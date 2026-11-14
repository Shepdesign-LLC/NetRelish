#!/usr/bin/env python3
"""The privacy manifests say what the code does, and the Info.plist keys stay paired (ADR 0032).

App Store Connect reads PrivacyInfo.xcprivacy from each bundle that has code: the app, the
Share extension and the Pantry framework (and the PantryKit package, for Duo). It rejects a
manifest with keys it doesn't know. Apple asks for a reason for each "required-reason" API a
bundle's code calls. These tests sweep each bundle's Swift sources for those APIs and fail when
a manifest leaves one out, or still claims one the code no longer uses. They also check the
App Store build's privacy answers: no tracking, nothing collected, no license address, and
each protected resource's entitlement paired with its purpose string.

Pure Python over the files in the repository, so it runs on Linux beside the gate's tests.

Run:  python3 -m unittest discover -s scripts/tests
"""

import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Each bundle with code: its manifest, and the Swift that ends up in its binary. The app links
# the Pantry framework, so the app's manifest answers for it too.
BUNDLES = {
    "NetRelish.app": {
        "manifest": "Resources/PrivacyInfo.xcprivacy",
        "sources": ["Sources/App", "Sources/UI", "Sources/Shelf", "Sources/Bench", "Sources/Vault", "Sources/Zest",
                    "Sources/Pantry"],
    },
    "NetRelishShare.appex": {
        "manifest": "Sources/ShareExtension/PrivacyInfo.xcprivacy",
        "sources": ["Sources/ShareExtension", "Sources/Pantry/Store/ShareInbox.swift"],
    },
    "Pantry.framework and PantryKit": {
        "manifest": "Sources/Pantry/PrivacyInfo.xcprivacy",
        "sources": ["Sources/Pantry"],
    },
}

TOP_LEVEL_KEYS = {"NSPrivacyTracking", "NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes",
                  "NSPrivacyAccessedAPITypes"}

# Apple's reason codes per category (developer.apple.com, "Describing use of required reason API").
REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"3EC4.1", "54BD.1"},
}

# What the sweep looks for. UserDefaults is split by whose defaults: the app's own (CA92.1) or
# the App Group's (1C8F.1), because the two need different reasons.
STANDARD_DEFAULTS = re.compile(
    r"UserDefaults\.standard|UserDefaults\(\)|UserDefaults\s*=\s*\.standard|@AppStorage|NSUserDefaults")
GROUP_DEFAULTS = re.compile(r"UserDefaults\(suiteName:")
OTHER_CATEGORIES = {
    # The date properties count only as API members (`.creationDate`, `values.contentModificationDate`,
    # `.contentModificationDateKey`), so a model's own `var modificationDate` isn't flagged.
    "NSPrivacyAccessedAPICategoryFileTimestamp": re.compile(
        r"\.(creationDate|modificationDate|contentModificationDate|contentAccessDate|"
        r"attributeModificationDate|fileModificationDate|fileCreationDate)(Key)?\b"
        r"|\b(attributesOfItem|NSFileCreationDate|NSFileModificationDate|f?getattrlist(bulk|at)?)\b"
        r"|\b[fl]?stat(at)?\("),
    "NSPrivacyAccessedAPICategorySystemBootTime": re.compile(r"\b(systemUptime|mach_absolute_time)\b"),
    "NSPrivacyAccessedAPICategoryDiskSpace": re.compile(
        r"\b(volumeAvailableCapacity\w*|volumeTotalCapacity\w*|systemFreeSize|systemSize|"
        r"attributesOfFileSystem|f?statv?fs)\b"),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": re.compile(r"\bactiveInputModes\b"),
}


def swift_files(paths):
    for rel in paths:
        path = ROOT / rel
        yield from ([path] if path.is_file() else sorted(path.rglob("*.swift")))


def code_lines(path):
    """The file's lines with // comments dropped, so prose that names an API doesn't count."""
    return code_lines_of(path.read_text(encoding="utf-8"))


def code_lines_of(text):
    for line in text.splitlines():
        yield line.split("//", 1)[0]


def used_reasons(paths):
    """{category: {reason, ...}} the sources need, with the file:line that needs each."""
    needs = {}
    for path in swift_files(paths):
        for number, line in enumerate(code_lines(path), 1):
            where = f"{path.relative_to(ROOT)}:{number}"
            if STANDARD_DEFAULTS.search(line):
                needs.setdefault("NSPrivacyAccessedAPICategoryUserDefaults", {}).setdefault("CA92.1", where)
            if GROUP_DEFAULTS.search(line):
                needs.setdefault("NSPrivacyAccessedAPICategoryUserDefaults", {}).setdefault("1C8F.1", where)
            for category, pattern in OTHER_CATEGORIES.items():
                if pattern.search(line):
                    needs.setdefault(category, {}).setdefault("?", where)
    return needs


def load(rel):
    with open(ROOT / rel, "rb") as handle:
        return plistlib.load(handle)


class Manifests(unittest.TestCase):
    def test_only_keys_app_store_connect_accepts(self):
        for bundle, spec in BUNDLES.items():
            with self.subTest(bundle=bundle):
                manifest = load(spec["manifest"])
                self.assertEqual(set(manifest), TOP_LEVEL_KEYS)
                for entry in manifest["NSPrivacyAccessedAPITypes"]:
                    self.assertEqual(set(entry), {"NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"})
                    category = entry["NSPrivacyAccessedAPIType"]
                    self.assertIn(category, REASONS)
                    reasons = entry["NSPrivacyAccessedAPITypeReasons"]
                    self.assertTrue(reasons, f"{category} lists no reason")
                    self.assertLessEqual(set(reasons), REASONS[category])
                    self.assertEqual(len(reasons), len(set(reasons)), "a reason is listed twice")

    def test_no_tracking_and_nothing_collected(self):
        # The App Store build's label is "Data Not Collected" (ADR 0032). Declaring something here
        # changes what the App Store page says, so it changes with an ADR, not on its own.
        for bundle, spec in BUNDLES.items():
            with self.subTest(bundle=bundle):
                manifest = load(spec["manifest"])
                self.assertIs(manifest["NSPrivacyTracking"], False)
                self.assertEqual(manifest["NSPrivacyTrackingDomains"], [])
                self.assertEqual(manifest["NSPrivacyCollectedDataTypes"], [])

    def test_each_reason_the_code_needs_is_declared(self):
        for bundle, spec in BUNDLES.items():
            with self.subTest(bundle=bundle):
                declared = {entry["NSPrivacyAccessedAPIType"]: set(entry["NSPrivacyAccessedAPITypeReasons"])
                            for entry in load(spec["manifest"])["NSPrivacyAccessedAPITypes"]}
                for category, reasons in used_reasons(spec["sources"]).items():
                    for reason, where in reasons.items():
                        if reason == "?":
                            self.assertIn(category, declared,
                                          f"{where} uses a {category} API: declare it with the reason that fits")
                        else:
                            self.assertIn(reason, declared.get(category, set()),
                                          f"{where} needs {category} {reason} in {spec['manifest']}")

    def test_nothing_declared_that_the_code_no_longer_uses(self):
        for bundle, spec in BUNDLES.items():
            with self.subTest(bundle=bundle):
                used = used_reasons(spec["sources"])
                for entry in load(spec["manifest"])["NSPrivacyAccessedAPITypes"]:
                    category = entry["NSPrivacyAccessedAPIType"]
                    self.assertIn(category, used, f"{spec['manifest']} declares {category}, which nothing uses")
                    if category == "NSPrivacyAccessedAPICategoryUserDefaults":
                        for reason in entry["NSPrivacyAccessedAPITypeReasons"]:
                            self.assertIn(reason, used[category],
                                          f"{spec['manifest']} declares {reason}, which nothing needs")

    def test_the_sweep_sees_what_it_should(self):
        # A guard on the guard: if these patterns stop matching, every test above passes vacuously.
        self.assertTrue(STANDARD_DEFAULTS.search("UserDefaults.standard.set(true, forKey: k)"))
        self.assertTrue(STANDARD_DEFAULTS.search("defaults: UserDefaults = .standard"))
        self.assertTrue(STANDARD_DEFAULTS.search('@AppStorage("x") var x = 1'))
        self.assertFalse(STANDARD_DEFAULTS.search("private let defaults: UserDefaults"))
        self.assertTrue(GROUP_DEFAULTS.search('UserDefaults(suiteName: "group")'))
        timestamps = OTHER_CATEGORIES["NSPrivacyAccessedAPICategoryFileTimestamp"]
        self.assertTrue(timestamps.search("let date = values.contentModificationDate"))
        self.assertTrue(timestamps.search("let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]"))
        self.assertTrue(timestamps.search("attributes[.modificationDate] as? Date"))
        self.assertTrue(timestamps.search("try FileManager.default.attributesOfItem(atPath: p)"))
        self.assertTrue(timestamps.search("stat(path, &info)"))
        self.assertTrue(timestamps.search("fstatat(fd, name, &info, 0)"))
        self.assertTrue(timestamps.search("getattrlistbulk(fd, &list, buf, size, 0)"))
        self.assertFalse(timestamps.search("item.sealedAt = .now"))
        self.assertFalse(timestamps.search("public var modificationDate: Date?"))
        self.assertTrue(OTHER_CATEGORIES["NSPrivacyAccessedAPICategoryDiskSpace"].search("fstatfs(fd, &info)"))
        self.assertTrue(OTHER_CATEGORIES["NSPrivacyAccessedAPICategorySystemBootTime"].search(
            "ProcessInfo.processInfo.systemUptime"))
        self.assertTrue(OTHER_CATEGORIES["NSPrivacyAccessedAPICategoryDiskSpace"].search(
            "[.volumeAvailableCapacityForImportantUsageKey]"))
        self.assertEqual(list(code_lines_of("let a = 1 // UserDefaults.standard")), ["let a = 1 "])

    def test_package_ships_the_pantry_manifest(self):
        # SwiftPM leaves a file out of the bundle unless the target lists it (Duo needs it on iOS).
        package = (ROOT / "Package.swift").read_text(encoding="utf-8")
        self.assertRegex(package, r'resources:\s*\[\s*\.copy\("PrivacyInfo\.xcprivacy"\)\s*\]')

    def test_one_manifest_per_bundle(self):
        # Resources/ is copied flat into the app: a second manifest there would collide with the
        # app's. The extension's lives in its own folder, which is its own target.
        found = sorted(str(p.relative_to(ROOT)) for p in ROOT.rglob("PrivacyInfo.xcprivacy")
                       if ".build" not in p.parts and ".git" not in p.parts)
        self.assertEqual(found, sorted(spec["manifest"] for spec in BUNDLES.values()))


class InfoPlist(unittest.TestCase):
    info = load("Sources/App/Info.plist")
    entitlements = load("NetRelish.entitlements")

    def test_export_compliance_answered(self):
        self.assertIs(self.info.get("ITSAppUsesNonExemptEncryption"), False)

    def test_web_content_is_out_of_ats_and_urlsession_is_not(self):
        ats = self.info["NSAppTransportSecurity"]
        self.assertIs(ats.get("NSAllowsArbitraryLoadsInWebContent"), True)
        # Arbitrary loads for everything would also take the timestamp and license calls out of ATS.
        self.assertNotIn("NSAllowsArbitraryLoads", ats)
        self.assertEqual(set(ats["NSExceptionDomains"]), {"timestamp.digicert.com"})

    def test_each_protected_resource_has_both_halves(self):
        # macOS can end an app that touches one of these with the entitlement and no purpose
        # string; a string with no entitlement promises something the app can't do.
        pairs = {
            "com.apple.security.personal-information.addressbook": "NSContactsUsageDescription",
            "com.apple.security.device.camera": "NSCameraUsageDescription",
            "com.apple.security.device.audio-input": "NSMicrophoneUsageDescription",
            "com.apple.security.personal-information.location": "NSLocationUsageDescription",
            # Since macOS 14 calendar access is full or write-only, each with its own string.
            "com.apple.security.personal-information.calendars": (
                "NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription"),
            "com.apple.security.personal-information.photos-library": "NSPhotoLibraryUsageDescription",
        }
        for entitlement, keys in pairs.items():
            keys = (keys,) if isinstance(keys, str) else keys
            with self.subTest(entitlement=entitlement):
                self.assertEqual(bool(self.entitlements.get(entitlement)), any(k in self.info for k in keys),
                                 f"{entitlement} and {' or '.join(keys)} come together or not at all")

    def test_local_network_is_explained(self):
        self.assertTrue(self.info.get("NSLocalNetworkUsageDescription", "").strip())

    def test_app_store_build_has_no_license_address(self):
        # App Review 2.4.5: the App Store build asks for no license key, and carries no relay.
        assignments = [line.split("=", 1)[1].strip()
                       for line in (ROOT / "Config/AppStore.xcconfig").read_text(encoding="utf-8").splitlines()
                       if re.match(r"\s*NR_LICENSE_ACTIVATION_URL\s*=", line)]
        self.assertTrue(assignments, "AppStore.xcconfig must set NR_LICENSE_ACTIVATION_URL")
        self.assertEqual(assignments[-1], "")


if __name__ == "__main__":
    unittest.main()
