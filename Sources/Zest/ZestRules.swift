// ZestRules.swift — the content rule list every Zest web view carries (ADR 0015, ADR 0033).
// It blocks every http(s), ws(s) and file load, whatever the page asks for: the third layer
// of Zest's offline rule, under the static scan and the Content-Security-Policy, and the one
// that holds even if a tool's markup is wrong. Non-negotiable 5: the tools add no endpoint.
//
// A rule list matches URL loads only. WebRTC reaches the network with none (a STUN or TURN
// server, over UDP), and no policy directive governs it, so this list doesn't stop it:
// ZestWebView takes the peer-connection constructors away in every frame instead, and the
// static scan fails on any use of them in the tools.
//
// Compiled once per launch, asynchronously. A Zest web view is never made before the list
// is here (ZestWebView takes it as a non-optional argument), so nothing loads unblocked.

import Observation
import OSLog
import WebKit

private let log = Logger(subsystem: "com.shepdesign.netrelish", category: "zest")

@MainActor
@Observable
final class ZestRules {
    static let shared = ZestRules()

    /// The compiled list, once it's ready.
    private(set) var list: WKContentRuleList?
    /// True if WebKit refused to compile it. Zest stays closed: no list, no tools.
    private(set) var failed = false
    @ObservationIgnored private var started = false

    /// The rule store's name for the list. Recompiling under it replaces the old one.
    nonisolated static let identifier = "com.shepdesign.netrelish.zest.offline"

    /// The rules, as WebKit reads them. `url-filter` is a regular expression matched against
    /// the whole URL, case-insensitively by default. Every rule blocks; none is scoped to a
    /// domain or a resource type, so main-frame loads, frames, fetches, sockets, images and
    /// fonts are all covered.
    nonisolated static let json = """
    [
      {"trigger": {"url-filter": "^https?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^wss?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^file:"}, "action": {"type": "block"}}
    ]
    """

    /// Starts compiling, once. Safe to call from every Zest window as it appears.
    func prepare() {
        guard !started else { return }
        started = true
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: Self.identifier, encodedContentRuleList: Self.json
        ) { [weak self] list, error in
            // WebKit calls back on the main thread.
            let compiled = list
            let failure = error.map(errorKind)
            MainActor.assumeIsolated {
                guard let self else { return }
                if let compiled {
                    self.list = compiled
                } else {
                    self.failed = true
                    log.error("zest rules: \(failure ?? "no list", privacy: .public)")
                }
            }
        }
    }
}
