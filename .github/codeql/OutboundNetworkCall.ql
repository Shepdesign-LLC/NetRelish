/**
 * @name Outbound network call in app code
 * @description NetRelish permits exactly four kinds of network traffic: page
 *              loads, StoreKit, RFC 3161 timestamping, and direct-build licence
 *              activation. None of those is a socket this app opens by hand —
 *              page loads go through WKWebView and StoreKit does its own I/O
 *              inside the framework. So a hand-written network call in
 *              first-party code is either a fifth endpoint or a mistake, and
 *              both need a person to look at them.
 * @kind problem
 * @problem.severity error
 * @security-severity 8.0
 * @precision high
 * @id netrelish/outbound-network-call
 * @tags security
 *       netrelish
 *       non-negotiable-5
 */

// KNOWN LIMIT — read before trusting this rule's coverage.
//
// Every prefix below is a CLAIM about coverage that nothing verifies.
// Compiling proves the QL is valid, not that it matches what it says it
// matches, and the canary only exercises the one path a canary was written
// for. Three holes of exactly this shape were found by review on this branch
// alone: URL.resourceBytes matched as an ApplyExpr when it is a property, the
// BSD socket calls missing outright, and CFReadStream/CFWriteStream not being
// matched by "CFStream%". Each read as coverage and was not.
//
// So treat a clean run as "nothing matched these patterns", never as "this app
// makes no network calls". Adding an API here is cheap; assuming one is
// already here is how a rule like this quietly stops meaning anything.
//
// This query is the gate, so every API it names is unambiguously a network
// call. The APIs that only MIGHT be remote — `Data(contentsOf:)` and friends,
// which are equally a local file read — are not here; they are in
// RemoteCapableURLRead.ql, at a lower severity, because mixing them in would
// put permanent false positives on the one rule that is supposed to mean
// something when it fires.
import swift

/**
 * Holds if `c` is a member function that opens a connection to a remote host.
 *
 * Deliberately matched on type-name prefix rather than an exhaustive method
 * list: `URLSession` grows new spellings (`data(for:)`, `bytes(from:)`,
 * `webSocketTask(with:)`) faster than any list here would be updated, and a
 * rule that silently stops covering the API it names is worse than no rule.
 */
private predicate networkMethod(Method c, string api) {
  exists(string type, string func | c.hasQualifiedName(type, func) |
    api = type + "." + func and
    (
      // Foundation's HTTP stack, in every spelling it has ever had, minus the
      // members that only tear a session down. The exclusion is a NEGATIVE list
      // on purpose: if Apple adds a method, it gets flagged rather than
      // silently skipped, so the list going stale fails safe.
      type.matches(["URLSession%", "NSURLSession%"]) and
      // Configuration objects never open anything, and a session built from one
      // is itself a hit, so nothing is lost by leaving them out.
      not type.matches(["URLSessionConfiguration%", "NSURLSessionConfiguration%"]) and
      not c.getShortName() =
        [
          // Teardown.
          "invalidateAndCancel", "finishTasksAndInvalidate", "cancel", "reset", "flush",
          // Introspection. Excluded on the same reasoning as teardown: both can
          // only appear where a session already exists, and creating that
          // session is itself a hit, so the noise is bounded by a finding that
          // is already on the board.
          "getAllTasks", "getTasksWithCompletionHandler", "delegate"
        ]
      // `init` is deliberately NOT excluded. Constructing a URLSession is the
      // single clearest signal that someone is adding an endpoint — it is the
      // line this rule exists to stop. Excluding it to keep the gate quiet
      // would trade a bounded false positive for the one false negative that
      // matters.
      or
      type = ["NSURLConnection", "NSURLDownload"]
      or
      // The Network framework, named types rather than the NW% prefix.
      // NWPathMonitor is deliberately absent: it reports whether a route exists
      // and never opens one, so flagging it would be a false positive on the
      // rule that has to stay clean to be worth blocking a merge with. Unlike
      // URLSession's method surface, this list is small and barely moves.
      type = ["NWConnection", "NWConnectionGroup", "NWListener", "NWBrowser"]
    )
  )
}

/**
 * Holds if `c` is a free function that opens a connection to a remote host:
 * CFNetwork, or the BSD socket calls Swift imports from Darwin.
 *
 * Matched on short name (the name without its argument labels) because the C
 * imports carry `(_:_:_:)`-style labels whose arity varies by overload, and
 * restricted to free functions so that a method called `send` or `connect` —
 * of which there are many — cannot collide. No first-party free function in
 * this repo uses any of these names.
 */
private predicate networkFreeFunction(FreeFunction c, string api) {
  api = c.getName() and
  (
    (
      // Named, not prefixed. "CFReadStream%" was too broad in the other
      // direction: CFReadStreamCreateWithFile opens a local file and
      // CFStreamCreateBoundPair is in-memory, so a prefix put local-only
      // operations on the zero-baseline gate — the same false-positive mistake
      // the audit-query split exists to avoid.
      //
      // An explicit list is safe HERE, unlike URLSession's: CFNetwork is a
      // frozen C API. Apple is not adding constructors to it, so this list
      // cannot silently fall behind the way a Swift API list would.
      c.getShortName() =
        [
          "CFReadStreamCreateForHTTPRequest", "CFReadStreamCreateForStreamedHTTPRequest",
          "CFReadStreamCreateWithFTPURL", "CFWriteStreamCreateWithFTPURL",
          "CFStreamCreatePairWithSocket", "CFStreamCreatePairWithSocketToHost",
          "CFStreamCreatePairWithPeerSocketSignature"
        ]
      or
      // These remain prefixes because every member of them is network by
      // definition — there is no local CFSocket or CFHost.
      c.getShortName().matches(["CFSocket%", "CFHost%", "CFNetwork%"])
    )
    or
    c.getShortName() =
      [
        "socket", "connect", "connectx", "bind", "listen", "accept", "send", "sendto",
        "sendmsg", "sendfile", "recv", "recvfrom", "recvmsg", "getaddrinfo", "gethostbyname"
      ]
  )
}

/**
 * Holds if `f` is a file in this repository, as opposed to an SDK or package
 * source pulled in by the build. `getRelativePath()` has no result for files
 * outside the source root, which is exactly the distinction wanted.
 */
private predicate firstParty(File f) { exists(f.getRelativePath()) }

from ApplyExpr call, Callable target, string api
where
  target = call.getStaticTarget() and
  (networkMethod(target, api) or networkFreeFunction(target, api)) and
  firstParty(call.getFile())
select call,
  "Call to $@ opens a network connection. CLAUDE.md non-negotiable #5 allows only page loads, " +
    "StoreKit, RFC 3161 timestamping and direct-build licence activation. If this is one of " +
    "those four, put a NETRELISH-ALLOW-ENDPOINT: adr-NNNN comment on this line or the one " +
    "above, citing the ADR that approved it. Otherwise it is a fifth endpoint and the rule " +
    "says no.", target, api
