#if DEBUG
import Foundation
import Pantry
import Testing
import WebKit
@testable import NetRelish

/// The capture → jar → seal UI test (Tests/NetRelishUITests) and the fixture it launches the
/// app with. The fixture must stay off unless the test asks for it, its page must ask for
/// nothing (non-negotiable 5), and the words the UI test waits for must be the words the app
/// composes and VoiceOver says, so the UI test can't drift into checking something nobody hears.
@Suite("UI test fixture") @MainActor struct UITestFixtureAccessibilityTests {

    private static let uiTestSource = "Tests/NetRelishUITests/CaptureJarSealUITests.swift"

    private func uiTest() throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(Self.uiTestSource), encoding: .utf8)
    }

    @Test("Off unless the UI test launches the app with -NRUITestFixture")
    func offByDefault() {
        #expect(!ProcessInfo.processInfo.arguments.contains(UITestFixture.argument))
        #expect(!UITestFixture.isOn)
        #expect(!UITestFixture.serves(UITestFixture.scheme))
        #expect(UITestFixture.makeWorkbench() == nil)
    }

    @Test("Without the fixture, a link on its scheme is another app's, as it always was")
    func handoffUnchanged() throws {
        let url = try #require(URL(string: UITestFixture.pageURL))
        #expect(JarWebView.handoff(url, clicked: true) == .ask(url))
        #expect(JarWebView.handoff(url, clicked: false) == .ask(url))
    }

    @Test("The page is on the fixture's scheme, at the walkthrough's site")
    func pageAddress() throws {
        let url = try #require(URL(string: UITestFixture.pageURL))
        #expect(url.scheme == UITestFixture.scheme)
        #expect(url.host == "juniperbakery.example")
        // WebKit doesn't handle it itself, so a scheme handler can be set for it.
        #expect(!WKWebView.handlesURLScheme(UITestFixture.scheme))
    }

    @Test("The page has its title, its heading and its marker line, and asks for nothing else")
    func pageContent() {
        let page = UITestFixture.page
        #expect(page.contains("<title>\(UITestFixture.pageTitle)</title>"))
        #expect(page.contains("<h1>\(UITestFixture.pageTitle)</h1>"))
        #expect(page.contains(UITestFixture.pageMarker))
        for asks in ["http", "src=", "href=", "<script", "<link", "<img", "<iframe", "url("] {
            #expect(!page.contains(asks), "The fixture page asks for something: \(asks)")
        }
    }

    @Test("The UI test types the fixture's address and waits for the fixture's page and jars")
    func uiTestMatchesFixture() throws {
        let source = try uiTest()
        #expect(source.contains("static let pageURL = \"\(UITestFixture.pageURL)\""))
        #expect(source.contains("static let pageTitle = \"\(UITestFixture.pageTitle)\""))
        #expect(source.contains("static let pageMarker = \"\(UITestFixture.pageMarker)\""))
        #expect(source.contains("static let firstJar = \"\(UITestFixture.jarNames[0])\""))
        #expect(source.contains("static let targetJar = \"\(UITestFixture.jarNames[1])\""))
        #expect(source.contains("\"\(UITestFixture.argument)\""))
        let host = try #require(URL(string: UITestFixture.pageURL)?.host)
        #expect(source.contains("static let pageHost = \"\(host)\""))
    }

    @Test("The UI test waits for the words VoiceOver hears at each step")
    func uiTestHearsTheAppsWords() throws {
        let source = try uiTest()
        let jar = UITestFixture.jarNames[1]
        // ⌘D's status line.
        #expect(source.contains("\"\(Workbench.capturedLine)\""))
        // ⌘S's status line, built from the jar's name the same way.
        #expect(Workbench.sealedLine(jarName: jar) == "Sealed into \(jar)")
        #expect(source.contains("\"Sealed into \\(jar)\""))
        // The Brine pill after one capture.
        #expect(ShellText.brineValue(count: 1, fresh: 1).hasPrefix("1 item"))
        #expect(ShellText.brineValue(count: 1, fresh: 0).hasPrefix("1 item"))
        #expect(source.contains("\"1 item\""))
        // The strip VoiceOver enters, named for its jar.
        #expect(TabStrip.stripLabel(jarName: jar) == "\(jar) tabs")
        #expect(source.contains("\"\\(jar) tabs\""))
        // The kept card on the board, once sealed.
        #expect(KeptCard.spokenValue(kind: .page, isSealed: true, when: "now",
                                     domain: "juniperbakery.example").hasPrefix("Page, sealed"))
        #expect(source.contains("\"Page, sealed\""))
        // The row in Brine says its site; the row in Sealed says its jar.
        #expect(SmartJarRowView.spokenValue(host: "juniperbakery.example", jarName: nil, fromJar: true,
                                            when: "Sank now").contains("juniperbakery.example"))
        #expect(SmartJarRowView.spokenValue(host: "juniperbakery.example", jarName: jar, fromJar: false,
                                            when: "Sealed now").contains("in \(jar)"))
        #expect(source.contains("\"in \\(jar)\""))
    }
}

#endif
