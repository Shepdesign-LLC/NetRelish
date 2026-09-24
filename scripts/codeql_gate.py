#!/usr/bin/env python3
"""The gate for CLAUDE.md non-negotiable 5, and the exemption mechanism it honours.

`github/codeql-action/analyze` uploads findings but never fails the job, and it
has no `fail-on` input. So the workflow enforces the rule itself: analyze writes
SARIF, and this script fails the build if `netrelish/outbound-network-call`
produced any result that is not approved in writing. A MISSING SARIF also fails
— a gate that silently passes when it did not run is exactly the false assurance
this query pack exists to prevent.

Gating repo-side would work too (code scanning's check-failure severity, or a
ruleset), but that is a console toggle a fork, a clone or a forgetful afternoon
loses. This travels with the repo.

WHY THIS IS A FILE AND NOT A HEREDOC IN THE WORKFLOW
----------------------------------------------------
It used to be a heredoc. Every defect this mechanism has had — five now — was in
its ENFORCEMENT rather than its design:

    1. no approved path at all
    2. markers matched inside string literals; cited ADRs never had to exist
    3. SARIF URIs treated as plain filenames
    4. markers inside /* block comments */ accepted
    5. one marker approving every finding that shared its line

Each idea was right; each implementation had a hole. A heredoc cannot be tested,
so every one of those was caught by a human reading it, or not caught at all.

That list is the HISTORICAL set — the five that existed before this file did.
Review of the branch that extracted it found FIFTEEN more, every one of them
failing open: markers hidden in extended regex literals, in interpolated nested
strings, and behind a bare regex's own closing delimiter; an escaped delimiter
ending an extended regex early; a trailing marker exempting the line below it;
ADR citations satisfied by a directory, by a symlink, by a symlinked parent
directory, and by a longer number that merely started with a real one; a
missing SARIF start line defaulting to 1; columnless findings merging on their
message; malformed columns merging two findings into one; source paths escaping
the checkout entirely; absolute paths rebased against the working directory
rather than the checkout being judged; and two spellings of one path splitting
a shared line into two. One of the fifteen was introduced by the fix for
another, and defended in review before it was checked.

Twenty defects, not one of them in the design. That is the case for the suite
in scripts/tests/, which runs on every push — including while CodeQL itself
cannot build this project. See scripts/tests/test_codeql_gate.py.

The lesson is in the ratio rather than the number: reading this code carefully
has never once been sufficient. Anything added here needs a test that fails
without it.

FAIL CLOSED, ALWAYS
-------------------
Every ambiguity here resolves toward blocking the build. An unreadable source
file, an ADR citation matching two files, two findings sharing one line, a
mangled SARIF URI: all block. Being wrong in the blocking direction costs
someone an explanation. Being wrong in the approving direction costs the rule
its meaning.
"""

from __future__ import annotations

import argparse
import glob
import json
import pathlib
import re
import sys
from urllib.parse import unquote, urlparse

# The gate. `netrelish/remote-capable-url-read` is the audit and is deliberately
# NOT gated: it has two legitimate baseline hits, and failing on it would teach
# everyone to ignore a red CodeQL job — the opposite of what the split was for.
GATE = "netrelish/outbound-network-call"

# An approved exception is a comment on the flagged line or the one directly
# above it, citing the ADR that approved it:
#
#     // NETRELISH-ALLOW-ENDPOINT: adr-0007 — RFC 3161 timestamping
#
# It lives beside the code rather than in a list, so it shows up in every diff
# that touches the call, cannot drift away from what it exempts, and dies with
# the line. The ADR reference is required because CLAUDE.md already says an
# uncovered decision gets one, and an exception with no written reason is how a
# rule rots.
#
# Dismissing the alert in the Security tab deliberately does NOT satisfy this:
# that is invisible from the repository.
#
# The trailing guard matters: `\d{4}` alone matched the first four digits of
# `adr-00070` and captured `adr-0007`, so a malformed citation was silently
# accepted whenever ADR 0007 happened to exist. The number must end where the
# citation ends.
MARKER = re.compile(r"NETRELISH-ALLOW-ENDPOINT:\s*(adr-\d{4})(?![\w-])")


# --------------------------------------------------------------------------
# Where a marker is allowed to live
# --------------------------------------------------------------------------

def line_comments(source: str) -> dict[int, str]:
    """Map 1-based line number -> the text of the genuine `//` comment on it.

    A marker only counts inside real line-comment text. Deciding what that means
    is the whole job, and text matching is not up to it:

        let s = "NETRELISH-ALLOW-ENDPOINT: adr-0001"   // a string, not a comment
        /* // NETRELISH-ALLOW-ENDPOINT: adr-0006 */    // commented-out, not a comment
        let u = "https://x/"  // NETRELISH-ALLOW-ENDPOINT: adr-0007   <- this one is real

    The earlier `line.partition("//")` accepted the first two. The second was
    the dangerous one: a commented-out block that happens to contain a marker
    silently approves whatever line follows it.

    So this scans the file once, front to back, tracking every lexical context
    that can hide or reveal a `//`: block comments (which NEST in Swift), string
    literals, raw strings (`#"..."#` at any hash count, where the escape is
    `\\#`), extended regex literals (`#/.../#`), the multiline forms of each,
    and string interpolation.

    Interpolation is why the contexts are a STACK rather than a few flags.
    `\\(` returns to code INSIDE a string, that code can open another string,
    and that one can interpolate again. Flat state mistook the nested opening
    quote for the outer closer and fell out into "code" mid-literal, so

        let s = "\\("// NETRELISH-ALLOW-ENDPOINT: adr-0007")"

    recorded a line comment and approved the call below it. Each construct now
    pushes; its terminator pops; a `//` is only recorded as a comment when the
    stack is empty, which is the one place a genuine comment can be.

    Unterminated constructs fail closed for free: an unclosed `/*`, string or
    `#/` swallows the rest of the file, so no further line records a comment,
    so nothing below it can be approved.

    This is a comment/string scanner, not a Swift parser, and that is the
    correct scope — it needs to answer one question, and it answers it for every
    way Swift can spell these constructs.
    """
    comments: dict[int, str] = {}
    source_length = len(source)
    index = 0
    line = 1

    depth = 0    # block-comment nesting depth; 0 means we are not in one

    # Innermost context last. Either ["str", hashes, multiline] or
    # ["interp", paren_depth] — the latter is code again, inside a literal.
    stack: list[list] = []

    def in_string() -> bool:
        return bool(stack) and stack[-1][0] == "str"

    def advance(count: int) -> None:
        """Step `count` characters, keeping the line number honest."""
        nonlocal index, line
        line += source.count("\n", index, index + count)
        index += count

    while index < source_length:
        char = source[index]

        if char == "\n":
            # A single-line string cannot span a newline. Reaching one means the
            # source is malformed; resync at the line break rather than treating
            # the remainder of the file as string content.
            #
            # Only the directly-enclosing string is resynced. A newline inside
            # an interpolation is legal within a multiline literal, and guessing
            # which one this is would risk resyncing out of a construct that is
            # genuinely open. Not resyncing only swallows more of the file,
            # which approves nothing.
            if in_string() and not stack[-1][2]:
                stack.pop()
            advance(1)
            continue

        if depth:
            if source.startswith("/*", index):
                depth += 1
                advance(2)
            elif source.startswith("*/", index):
                depth -= 1
                advance(2)
            else:
                advance(1)
            continue

        if in_string():
            _, hashes, multiline = stack[-1]
            escape = "\\" + "#" * hashes
            closer = '"""' if multiline else '"'

            # Interpolation first: `\(` is also a prefix of the generic escape,
            # and treating it as one would skip the paren and read the rest of
            # the interpolation as string content.
            if source.startswith(escape + "(", index):
                stack.append(["interp", 0])
                advance(len(escape) + 1)
            elif source.startswith(escape, index):
                advance(len(escape) + 1)   # the escape, then the character it escapes
            elif source.startswith(closer + "#" * hashes, index):
                stack.pop()
                advance(len(closer) + hashes)
            else:
                advance(1)
            continue

        # Code — either the top level, or inside an interpolation.
        if stack:   # ["interp", paren_depth]
            if char == "(":
                stack[-1][1] += 1
                advance(1)
                continue
            if char == ")":
                if stack[-1][1]:
                    stack[-1][1] -= 1
                else:
                    stack.pop()   # interpolation over; the string resumes
                advance(1)
                continue

        if source.startswith("//", index):
            end = source.find("\n", index)
            end = source_length if end == -1 else end
            # First genuine `//` wins: everything after it on the line is inside
            # that same comment.
            #
            # Recorded only at the top level. A `//` inside an interpolation
            # would comment out the closing paren and quote, so it cannot occur
            # in code that compiles — and code that does not compile is code
            # CodeQL never flagged. Skipping it here costs nothing and cannot
            # approve anything.
            if not stack:
                comments.setdefault(line, source[index + 2:end])
            advance(end - index)
            continue

        if source.startswith("/*", index):
            depth = 1
            advance(2)
            continue

        # A run of `#` opens a string when a quote follows it and an extended
        # regex literal when a slash does; `#if` and `#Preview` are neither.
        run = 0
        while index + run < source_length and source[index + run] == "#":
            run += 1
        opener_at = index + run

        if opener_at < source_length and source[opener_at] == '"':
            is_multiline = source.startswith('"""', opener_at)
            stack.append(["str", run, is_multiline])
            advance(run + (3 if is_multiline else 1))
            continue

        if run and opener_at < source_length and source[opener_at] == "/":
            # Extended regex literal, `#/ ... /#` at any hash count, possibly
            # spanning lines. Its contents are pattern text, so a `//` in there
            # is not a comment — and in extended syntax whitespace is ignored,
            # which makes `#/ // NETRELISH-ALLOW-ENDPOINT: adr-0007 /#` read
            # exactly like an approval to the naive scanner. Skip to the
            # matching delimiter; unterminated swallows the rest, which fails
            # closed.
            #
            # Escape-aware, because `source.find("/#")` matched the `/` of an
            # escaped `\/` and ended the literal early — leaving the rest of the
            # pattern to be read as code, where a `//` in it became a comment.
            closer = "/" + "#" * run
            scan, end = opener_at + 1, source_length
            while scan < source_length:
                if source[scan] == "\\":
                    scan += 2
                    continue
                if source.startswith(closer, scan):
                    end = scan + len(closer)
                    break
                scan += 1
            advance(end - index)
            continue

        if char == "\\":
            # An escape in code is opaque: skip it and whatever it escapes.
            #
            # This is what makes the BARE `/.../` regex form safe to leave
            # untracked. I claimed two unescaped slashes would end such a
            # literal at the first, so `//` could not occur inside one. True,
            # and beside the point: the literal's own ending supplies the
            # second slash. In `let r = /\//` the `\/` and the closing `/` are
            # textually `//`, and the rest of the line was read as a comment.
            #
            # Skipping `\/` as one token leaves the closing `/` alone, with
            # nothing after it to pair with. Disambiguating regex from division
            # is not needed, and is not something this scanner should attempt.
            advance(2)
            continue

        advance(1)

    return comments


def cited_adr(comment: str, repo_root: pathlib.Path, report: "Report") -> str | None:
    """The ADR this comment cites, if it cites exactly one that exists.

    Checking only the adr-NNNN SHAPE meant `adr-9999` passed with no written
    decision existing at all, which made the ADR requirement decoration rather
    than a control. So the file has to be there.

    It also has to be the ONLY file there. `docs/adr/` has held two different
    ADRs both numbered 0006, and a citation that resolves to two unrelated
    decisions approves against whichever one the reader assumes. That is an
    ambiguous exemption, so it is refused and reported.
    """
    found = MARKER.search(comment)
    if not found:
        return None

    citation = found.group(1)
    number = citation[len("adr-"):]
    # A match counts only if it is a regular file that actually lives here.
    #
    # `glob` also returns directories, so `0007-placeholder.md/` would satisfy
    # the citation with no written decision inside it. `is_file()` follows
    # symlinks, so `0007-anything.md -> /etc/hosts` would satisfy it with a
    # decision that is not in the repository at all. And checking only the
    # matched file left its PARENT unchecked, so `docs/adr -> /tmp/decisions`
    # handed back perfectly ordinary regular files from outside the checkout.
    #
    # Hence `inside_checkout`, which resolves the whole path rather than
    # inspecting its last component: every one of those is an approval backed
    # by something this repository does not contain, which is the failure the
    # ADR requirement exists to prevent.
    matches = sorted(
        p.name for p in (repo_root / "docs" / "adr").glob(number + "-*.md")
        if not p.is_symlink() and p.is_file()
        and inside_checkout(repo_root, p) is not None
    )

    if not matches:
        report.errors.append(
            citation + " is cited but no docs/adr/" + number + "-*.md exists"
        )
        return None

    if len(matches) > 1:
        report.errors.append(
            citation + " is ambiguous: it matches " + ", ".join(matches)
            + ". Renumber so the citation names one decision."
        )
        return None

    return citation


# --------------------------------------------------------------------------
# Reading what CodeQL produced
# --------------------------------------------------------------------------

def source_path(uri: str) -> pathlib.Path:
    """The checkout-relative path for a SARIF artifactLocation.

    SARIF gives a URI, not a filename. CodeQL usually emits a repo-relative one,
    but a file:///... form (often with a uriBaseId) is equally legal, and
    pathlib.Path would treat the whole thing as a literal relative name. The
    source would then never open, no marker would be found, and a VALID
    exemption would block the build with a misleading message.

    Fails closed either way, but closed-and-wrong is still wrong.

    An absolute path is left absolute. It used to be rebased against
    `Path.cwd()`, which is not necessarily the checkout being evaluated: with a
    `--repo-root` elsewhere, `file:///<cwd>/Sources/A.swift` was rewritten to
    `Sources/A.swift` and then looked up under the OTHER root. If a file lived
    there too, the gate read it — and approved the finding using a marker from
    a checkout the finding had nothing to do with.

    Canonicalising against the root that is actually in use is `inside_checkout`'s
    job, and it is the only one that knows which root that is.
    """
    parsed = urlparse(uri)
    raw = unquote(parsed.path) if parsed.scheme == "file" else unquote(uri)
    return pathlib.Path(raw)


def positive_int(value):
    """The value if it is a real 1-based SARIF coordinate, else None.

    `isinstance(True, int)` is True in Python, so booleans are excluded
    explicitly rather than by accident.
    """
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        return None
    return value


def inside_checkout(repo_root: pathlib.Path, path) -> pathlib.Path | None:
    """The source file, but only if it really is one of ours.

    SARIF is input, and this one names the file whose comments decide whether a
    network call is approved. Nothing constrained it: an absolute `file:` URI,
    or a relative one containing `..`, escaped `repo_root` when joined and was
    read anyway — so a location pointing at any file on the runner that happens
    to contain a valid marker was approved.

    Resolution also follows symlinks, so a tracked source file pointing outside
    the checkout is rejected for the same reason.

    Returns None when the path does not stay inside, which the caller treats as
    an exemption it could not check, and therefore blocks.
    """
    try:
        resolved = (repo_root / path).resolve()
        resolved.relative_to(repo_root.resolve())
    except (ValueError, OSError, RuntimeError):
        return None
    return resolved


class Finding:
    """One gate result, reduced to the parts that decide its fate."""

    __slots__ = ("path", "line", "start_column", "end_column", "message")

    def __init__(self, path, line, start_column, end_column, message):
        self.path = path
        self.line = line
        self.start_column = start_column
        self.end_column = end_column
        self.message = message

    @property
    def locatable(self) -> bool:
        """Whether this finding can be told apart from another on its line.

        Only real columns count. Treating any non-None value as trustworthy
        meant two distinct findings both reported at `startColumn: 0,
        endColumn: 0` shared an identity and collapsed into one, which a single
        marker then approved. Invalid columns carry no position, so they are
        columnless, and columnless findings are never merged.
        """
        return self.start_column is not None and self.end_column is not None

    def identity(self):
        """What makes two findings the same call rather than two calls.

        Only ever asked of a locatable finding. A position is a call site, and
        the message is only description, so two reports of one position are one
        finding however they are worded.

        Findings WITHOUT columns are never deduplicated at all, because nothing
        about them can distinguish one call from another — two separate calls on
        one line usually carry the identical message, so any key built from the
        message would merge them, and a single marker would then approve both.
        That is the shared-line bypass returning through the back door. Keeping
        every occurrence instead can only over-count, which blocks.
        """
        return (self.path, self.line, self.start_column, self.end_column)


class Report:
    def __init__(self):
        self.approved = []   # (Finding, adr)
        self.blocking = []   # (Finding, reason)
        self.errors = []     # strings, printed as ::error and forcing failure
        self.sarif_count = 0

    @property
    def ok(self) -> bool:
        return not self.blocking and not self.errors


def evaluate(results_dir, repo_root=None) -> Report:
    """Decide the build. Pure: it reads, it does not print or exit."""
    repo_root = pathlib.Path(repo_root or pathlib.Path.cwd())
    root = repo_root.resolve()
    report = Report()

    paths = sorted(glob.glob(str(pathlib.Path(results_dir) / "*.sarif")))
    report.sarif_count = len(paths)
    if not paths:
        # A missing SARIF must never read as "clean" — that is precisely the
        # false assurance this whole query pack exists to prevent.
        report.errors.append(
            "no SARIF in " + str(results_dir) + "; the gate did not run"
        )
        return report

    findings = {}   # locatable, deduplicated by position
    loose = []      # columnless, never deduplicated (see Finding.identity)

    for path in paths:
        with open(path) as handle:
            sarif = json.load(handle)
        for run in sarif.get("runs", []):
            for result in run.get("results", []):
                if result.get("ruleId") != GATE:
                    continue
                where = result["locations"][0]["physicalLocation"]
                region = where.get("region", {})
                named = source_path(where["artifactLocation"]["uri"])

                # Canonicalise here, before this path becomes a grouping key.
                #
                # SARIF chooses the spelling, and `Sources/A.swift` and
                # `Sources/../Sources/A.swift` are the same file under two of
                # them. Grouping on the raw string put two findings on one
                # physical line into two groups of one, and a single marker
                # approved both — the shared-line rule defeated by punctuation.
                located = inside_checkout(repo_root, named)
                if located is None:
                    report.errors.append(
                        str(named) + " is outside the checkout, so an exemption "
                        "there could not be trusted"
                    )
                    continue
                where_file = str(located.relative_to(root))

                # Defaulting a missing startLine to 1 was not fail-closed: a
                # finding whose location is unknown would be handed line 1, and
                # a marker that happened to sit there would approve it. An
                # unlocatable finding cannot be exempted at all.
                start_line = positive_int(region.get("startLine"))
                if start_line is None:
                    report.errors.append(
                        "a gate finding in " + where_file + " has no usable "
                        "startLine, so it cannot be located or exempted"
                    )
                    continue

                finding = Finding(
                    path=where_file,
                    line=start_line,
                    # Validated, not merely present: a malformed column is no
                    # position at all, so the finding counts as columnless and
                    # is never deduplicated against another.
                    start_column=positive_int(region.get("startColumn")),
                    end_column=positive_int(region.get("endColumn")),
                    message=result["message"]["text"],
                )
                if finding.locatable:
                    findings[finding.identity()] = finding
                else:
                    loose.append(finding)

    # Group by the unit the exemption mechanism can actually address. A marker
    # names a line, not a call, so a line carrying two gate findings cannot be
    # approved by one — that was bypass 5: adding a second call beside an
    # already-approved one got past the gate. Fail closed instead of inventing
    # an approval the author never wrote.
    lines: dict[tuple, list[Finding]] = {}
    for finding in list(findings.values()) + loose:
        lines.setdefault((finding.path, finding.line), []).append(finding)

    source_cache: dict[str, dict[int, str] | None] = {}

    # A trailing marker approves the call it sits beside, and nothing else. The
    # line above is offered as a second home for it only when that line is not
    # itself flagged — otherwise
    #
    #     _ = try await URLSession.shared.data(from: a)  // ...ALLOW...: adr-0007
    #     _ = try await URLSession.shared.data(from: b)
    #
    # would let one exemption cover both calls: the shared-line bypass wearing a
    # newline. The standalone-comment-above form is unaffected, because a line
    # holding only a comment is never a finding.
    flagged = set(lines)

    for (path, line), group in sorted(lines.items()):
        if path not in source_cache:
            # Already canonical and already known to be inside the checkout —
            # both were settled when the finding was read.
            candidate = root / path
            if candidate.is_file():
                source_cache[path] = line_comments(
                    candidate.read_text(errors="replace")
                )
            else:
                source_cache[path] = None
                report.errors.append(
                    "cannot read " + path
                    + "; an exemption there could not be checked"
                )
        comments = source_cache[path]

        adr = None
        if comments is not None:
            # The flagged line, or the one directly above it.
            for candidate_line in (line - 1, line):
                if adr:
                    break
                if candidate_line != line and (path, candidate_line) in flagged:
                    continue
                text = comments.get(candidate_line)
                if text:
                    adr = cited_adr(text, repo_root, report)

        if len(group) > 1:
            reason = (
                str(len(group)) + " gate findings share this line, so one marker "
                "cannot approve them individually — split them across lines and "
                "give each its own exemption"
            )
            for finding in sorted(group, key=lambda f: (f.start_column or 0)):
                report.blocking.append((finding, reason))
        elif adr:
            report.approved.append((group[0], adr))
        else:
            report.blocking.append((group[0], group[0].message))

    return report


# --------------------------------------------------------------------------
# Saying it out loud
# --------------------------------------------------------------------------

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "results", nargs="?", default=".codeql-results",
        help="directory holding the SARIF that `analyze` wrote",
    )
    parser.add_argument(
        "--repo-root", default=".",
        help="checkout root that SARIF paths and docs/adr resolve against",
    )
    args = parser.parse_args(argv)

    report = evaluate(args.results, args.repo_root)

    for message in report.errors:
        print("::error::" + message)
    for finding, adr in report.approved:
        print(
            "::notice file=" + finding.path + ",line=" + str(finding.line)
            + "::approved endpoint (" + adr + ")"
        )
    for finding, reason in report.blocking:
        print(
            "::error file=" + finding.path + ",line=" + str(finding.line)
            + "::" + reason
        )

    if report.approved:
        print(
            "\n" + str(len(report.approved))
            + " approved exception(s), re-printed every run so they stay visible."
        )

    if report.blocking:
        print(
            "\n" + GATE + " fired " + str(len(report.blocking))
            + " time(s) with no approved exception. CLAUDE.md non-negotiable 5 "
            "permits page loads, StoreKit, RFC 3161 timestamping and direct-build "
            "licence activation, and nothing else."
        )

    if not report.ok:
        return 1

    print(GATE + ": clean across " + str(report.sarif_count) + " SARIF file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
