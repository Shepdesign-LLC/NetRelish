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
      // Foundation's HTTP stack, in every spelling it has ever had.
      type.matches(["URLSession%", "NSURLSession%"])
      or
      type = ["NSURLConnection", "NSURLDownload"]
      or
      // The Network framework: raw sockets, TLS, Bonjour.
      type.matches("NW%")
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
    c.getShortName().matches(["CFStream%", "CFSocket%", "CFHost%", "CFNetwork%"])
    or
    c.getShortName() =
      [
        "socket", "connect", "bind", "listen", "accept", "send", "sendto", "sendmsg", "recv",
        "recvfrom", "recvmsg", "getaddrinfo", "gethostbyname"
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
    "those four, dismiss this alert saying which; otherwise it is a fifth endpoint and the rule " +
    "says no.", target, api
