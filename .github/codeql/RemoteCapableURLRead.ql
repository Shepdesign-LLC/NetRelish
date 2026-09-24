/**
 * @name URL read that may be remote
 * @description `Data(contentsOf:)`, `String(contentsOf:)` and `URL.resourceBytes`
 *              read whatever the URL points at. Given a file URL that is a file
 *              read; given an https URL it is a synchronous HTTP GET that looks
 *              nothing like networking. Which one it is depends on a value, so
 *              no rule can decide it — a person has to, once, per call site.
 * @kind problem
 * @problem.severity warning
 * @security-severity 5.0
 * @precision medium
 * @id netrelish/remote-capable-url-read
 * @tags security
 *       netrelish
 *       non-negotiable-5
 */

// Why this is a separate, lower-severity query rather than part of
// OutboundNetworkCall.ql:
//
// These APIs are genuinely ambiguous, and this repo has two legitimate uses —
// reading the vendored defuddle.js out of the app bundle, and reading a sealed
// .webarchive out of Application Support. Neither can be proved local by the
// query: SnapshotStore's directory arrives as an init parameter, so its
// provenance is not visible from the call site at all.
//
// Folding them into the gate would therefore have parked two permanent false
// positives on the rule that is meant to mean something when it fires, and a
// rule that always has hits is a rule everyone learns to scroll past. So the
// two known-good reads get dismissed once, with a note saying which file each
// one reads, and from then on any NEW hit is a new alert on a pull request —
// which is exactly the signal wanted.
import swift

/** Holds if `f` is a file in this repository rather than an SDK or package source. */
private predicate firstParty(File f) { exists(f.getRelativePath()) }

/** Holds if `e` reads the contents of a URL that may be remote. */
private predicate remoteCapableRead(Expr e, string api) {
  // The initialisers. `Data(contentsOf:)` resolves to `init(contentsOf:options:)`
  // once default arguments are applied, hence the prefix match.
  exists(Method m, string type, string func |
    m = e.(ApplyExpr).getStaticTarget() and
    m.hasQualifiedName(type, func) and
    api = type + "." + func
  |
    type = ["Data", "NSData", "String", "NSString"] and
    func.matches("init(contentsOf:%")
    or
    type = "NSString" and
    func.matches("string(withContentsOf:%")
  )
  or
  // `url.resourceBytes` and `url.lines` are property accesses, not calls, so
  // they are never `ApplyExpr` and have to be matched as member references.
  exists(string prop |
    e.(MemberRefExpr).getMember().(FieldDecl).hasQualifiedName("URL", prop) and
    prop = ["resourceBytes", "lines"] and
    api = "URL." + prop
  )
}

from Expr read, string api
where
  remoteCapableRead(read, api) and
  firstParty(read.getFile())
select read,
  "`" + api + "` reads whatever this URL points at, and an https URL here would be an " +
    "outbound request — which CLAUDE.md non-negotiable #5 permits only for page loads, " +
    "StoreKit, RFC 3161 timestamping and direct-build licence activation. If the URL is a " +
    "file URL, dismiss this alert saying which file it reads."
