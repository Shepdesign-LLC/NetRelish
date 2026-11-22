import Foundation
import Pantry
import Testing
@testable import NetRelish

/// The welcome sheet (ADR 0038): three cards, shown once at the first launch and again from
/// Help. `welcome.seen` lives in the injected defaults, so each test has its own and none
/// touches the app's.
@Suite("Welcome") @MainActor struct WelcomeTests {

    private func scratchDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
    }

    /// A Workbench as the app makes it for its own launch: allowed to open the sheet by itself.
    private func launched(_ defaults: UserDefaults) throws -> Workbench {
        let bench = Workbench(store: try PantryStore(), defaults: defaults)
        bench.welcomesAtLaunch = true
        return bench
    }

    // MARK: When it opens

    @Test("The first launch opens it, and closing it is what marks it seen")
    func firstLaunchOpensIt() throws {
        let defaults = try scratchDefaults()
        let bench = try launched(defaults)
        #expect(!bench.showingWelcome)   // nothing until a window is up

        bench.welcomeAtFirstLaunch()
        #expect(bench.showingWelcome)
        #expect(!defaults.bool(forKey: "welcome.seen"))   // open isn't seen: quit now and it comes back

        bench.closeWelcome(start: false)
        bench.welcomeClosed()
        #expect(!bench.showingWelcome)
        #expect(defaults.bool(forKey: "welcome.seen"))
    }

    @Test("The next launch doesn't open it")
    func shownOnce() throws {
        let defaults = try scratchDefaults()
        let first = try launched(defaults)
        first.welcomeAtFirstLaunch()
        first.closeWelcome(start: false)
        first.welcomeClosed()

        let second = try launched(defaults)
        second.welcomeAtFirstLaunch()
        #expect(!second.showingWelcome)
    }

    @Test("Quitting with it open shows it again at the next launch")
    func leftOpenComesBack() throws {
        let defaults = try scratchDefaults()
        let first = try launched(defaults)
        first.welcomeAtFirstLaunch()
        #expect(first.showingWelcome)   // and the app quits here, the sheet never closed

        let second = try launched(defaults)
        second.welcomeAtFirstLaunch()
        #expect(second.showingWelcome)
    }

    @Test("A second window in the same launch doesn't bring it back")
    func oncePerLaunch() throws {
        let bench = try launched(try scratchDefaults())
        bench.welcomeAtFirstLaunch()
        bench.closeWelcome(start: false)   // closed, and its dismissal hasn't been heard yet
        #expect(!bench.showingWelcome)

        bench.welcomeAtFirstLaunch()       // another window appears
        #expect(!bench.showingWelcome)
    }

    @Test("It never opens by itself for the tests or the UI test's fixture, whose defaults are always new")
    func neverInATestLaunch() throws {
        let bench = Workbench(store: try PantryStore(), defaults: try scratchDefaults())
        #expect(!bench.welcomesAtLaunch)   // the app alone sets it, for its own launch
        bench.welcomeAtFirstLaunch()
        #expect(!bench.showingWelcome)

        // The fixture's jars are added to a Workbench the app never marked as its own launch.
        UITestFixture.stock(bench)
        bench.welcomeAtFirstLaunch()
        #expect(!bench.showingWelcome)
    }

    @Test("Help opens it again after it has been seen, and closing it then changes nothing else")
    func helpOpensItAgain() throws {
        let defaults = try scratchDefaults()
        defaults.set(true, forKey: "welcome.seen")
        let bench = try launched(defaults)
        bench.welcomeAtFirstLaunch()
        #expect(!bench.showingWelcome)

        bench.showingWelcome = true        // Help › Welcome to NetRelish
        let asked = bench.addressFocusRequest
        bench.closeWelcome(start: false)
        bench.welcomeClosed()
        #expect(!bench.showingWelcome)
        #expect(bench.addressFocusRequest == asked)
        #expect(defaults.bool(forKey: "welcome.seen"))
    }

    // MARK: Start

    @Test("Start hands the keyboard to the address field once the sheet has gone, and only once")
    func startAsksForTheAddressField() throws {
        let bench = try launched(try scratchDefaults())
        bench.welcomeAtFirstLaunch()
        let asked = bench.addressFocusRequest

        bench.closeWelcome(start: true)
        #expect(!bench.showingWelcome)
        #expect(bench.addressFocusRequest == asked)       // not while the sheet is still leaving

        bench.welcomeClosed()
        #expect(bench.addressFocusRequest == asked + 1)

        bench.welcomeClosed()                             // a second dismissal asks for nothing
        #expect(bench.addressFocusRequest == asked + 1)
    }

    @Test("Escape closes it without touching the address field")
    func escapeLeavesTheKeyboardAlone() throws {
        let bench = try launched(try scratchDefaults())
        bench.welcomeAtFirstLaunch()
        let asked = bench.addressFocusRequest

        bench.closeWelcome(start: false)
        bench.welcomeClosed()
        #expect(bench.addressFocusRequest == asked)
    }

    // MARK: The cards

    @Test("Three cards: a jar, Brine, Seal")
    func threeCards() {
        #expect(WelcomeText.cards.map(\.title) == [
            "A jar is a project",
            "Idle tabs sink into Brine",
            "Seal a page to keep it",
        ])
        #expect(WelcomeText.position(0) == "1 of 3")
        #expect(WelcomeText.position(2) == "3 of 3")
    }

    @Test("Next and Back stop at the ends")
    func neighborsHoldAtTheEnds() {
        #expect(WelcomeText.neighbor(of: 0, by: 1) == 1)
        #expect(WelcomeText.neighbor(of: 1, by: 1) == 2)
        #expect(WelcomeText.neighbor(of: 2, by: 1) == 2)
        #expect(WelcomeText.neighbor(of: 0, by: -1) == 0)
        #expect(WelcomeText.neighbor(of: 2, by: -1) == 1)
        #expect(WelcomeText.neighbor(of: 9, by: 0) == 2)    // a snapshot asking past the end
        #expect(WelcomeText.neighbor(of: -4, by: 0) == 0)
    }

    @Test("A card is said whole when it changes: its headline, its lines, then where it is")
    func spokenCard() {
        let card = WelcomeText.cards[1]
        #expect(WelcomeText.spoken(1) == "\(card.title). \(card.body) 2 of 3.")
        for index in WelcomeText.cards.indices {
            #expect(WelcomeText.spoken(index).hasPrefix(WelcomeText.cards[index].title))
            #expect(WelcomeText.spoken(index).hasSuffix("\(index + 1) of 3."))
        }
    }

    /// docs/voice: no exclamation marks, none of the words the product never says, and the
    /// straight apostrophe never stands in for the real one.
    @Test("The cards follow the voice rules")
    func voice() {
        let banned = [
            "terminal", "command line", "cli", "wp-cli", "sql", "query", "stdout", "stderr",
            "webhook", "endpoint", "payload", "daemon", "instance", "container", "provision",
            "deprecated", "stack trace", "exception",
            "folder", "workspace", "collection", "bookmark", "trash", "history", "inspector",
            "sidebar", "drawer",
            "seamlessly", "effortlessly", "oops", "whoops",
        ]
        let buttons = [WelcomeText.next, WelcomeText.back, WelcomeText.start, WelcomeText.menu]
        let strings = WelcomeText.cards.flatMap { [$0.title, $0.body] } + buttons
        for text in strings {
            #expect(!text.isEmpty)
            #expect(!text.contains("!"), "\(text)")
            #expect(!text.contains("'"), "\(text)")
            let words = text.lowercased().split { !($0.isLetter || $0 == "-") }.map(String.init)
            for word in banned where !word.contains(" ") {
                #expect(!words.contains(word), "“\(word)” in: \(text)")
            }
            for phrase in banned where phrase.contains(" ") {
                #expect(!text.lowercased().contains(phrase), "“\(phrase)” in: \(text)")
            }
        }
        // A headline is a sentence without its period; the lines under it end theirs.
        for card in WelcomeText.cards {
            #expect(!card.title.hasSuffix("."))
            #expect(card.body.hasSuffix("."))
        }
    }

    // MARK: The cards say only what the app does

    @Test("“Pinned tabs never sink”, and a tab left alone past its jar’s shelf life does")
    func brineCardIsTrue() throws {
        let bench = Workbench(store: try PantryStore(), defaults: try scratchDefaults())
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let jar = try #require(bench.jars.first { $0.name == "Ash" })
        let tab = try #require(bench.newTab(url: "https://ash.example"))
        let later = Date().addingTimeInterval(4 * ShelfLife.secondsPerDay)

        #expect(ShelfLife.shouldSink(tab, in: jar, now: later))
        var pinned = tab
        pinned.isPinned = true
        #expect(!ShelfLife.shouldSink(pinned, in: jar, now: later))
        #expect(WelcomeText.cards[1].body.contains("Pinned tabs never sink."))
    }

    @Test("The keys the Seal card names are the ones the menu and ⌘K’s rows carry")
    func sealCardNamesRealKeys() throws {
        let body = WelcomeText.cards[2].body
        #expect(body.contains("⌘S"))
        #expect(body.contains("⌘K"))
        let bench = Workbench(store: try PantryStore(), defaults: try scratchDefaults())
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        _ = try #require(bench.newTab(url: "https://ash.example"))
        let seal = try #require(PaletteSource.commands(bench).first { $0.id == "cmd.seal" })
        #expect(seal.shortcut == "⌘S")
    }
}
