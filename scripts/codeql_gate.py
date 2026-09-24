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
The mechanism is now a module with a test suite beside it in scripts/tests/, and
that suite runs on every push — including while CodeQL itself cannot build this
project. See scripts/tests/test_codeql_gate.py.

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
MARKER = re.compile(r"NETRELISH-ALLOW-ENDPOINT:\s*(adr-\d{4})")


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

    So this scans the file once, front to back, tracking the three lexical
    contexts that can hide or reveal a `//`: block comments (which NEST in
    Swift), string literals, and raw string literals (`#"..."#`, any number of
    hashes, where the escape is `\\#`). Multiline `\"\"\"..\"\"\"` too, since a
    marker inside one spans lines and would otherwise look like a comment.

    Unterminated constructs fail closed for free: an unclosed `/*` swallows the
    rest of the file, so no further line records a comment, so nothing below it
    can be approved.

    This is a comment/string scanner, not a Swift parser, and that is the
    correct scope — it needs to answer one question, and it answers it for every
    way Swift can spell these three things.
    """
    comments: dict[int, str] = {}
    source_length = len(source)
    index = 0
    line = 1

    depth = 0             # block-comment nesting depth; 0 means we are not in one
    in_string = False
    multiline = False     # the \"\"\" form, which may contain newlines
    hashes = 0            # raw-string delimiter count: #"..."# is 1, ##"..."## is 2

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
            if in_string and not multiline:
                in_string = False
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

        if in_string:
            closer = '"""' if multiline else '"'
            if source.startswith("\\" + "#" * hashes, index):
                advance(1 + hashes + 1)   # backslash, its hashes, the escaped character
            elif source.startswith(closer + "#" * hashes, index):
                in_string = False
                advance(len(closer) + hashes)
            else:
                advance(1)
            continue

        # Ordinary code.
        if source.startswith("//", index):
            end = source.find("\n", index)
            end = source_length if end == -1 else end
            # First genuine `//` wins: everything after it on the line is inside
            # that same comment.
            comments.setdefault(line, source[index + 2:end])
            advance(end - index)
            continue

        if source.startswith("/*", index):
            depth = 1
            advance(2)
            continue

        # A run of `#` only opens a string when a quote follows it; `#if` and
        # `#Preview` are not string literals.
        run = 0
        while index + run < source_length and source[index + run] == "#":
            run += 1
        quote_at = index + run
        if quote_at < source_length and source[quote_at] == '"':
            in_string = True
            hashes = run
            multiline = source.startswith('"""', quote_at)
            advance(run + (3 if multiline else 1))
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
    matches = sorted(p.name for p in (repo_root / "docs" / "adr").glob(number + "-*.md"))

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
    """
    parsed = urlparse(uri)
    raw = unquote(parsed.path) if parsed.scheme == "file" else unquote(uri)
    path = pathlib.Path(raw)
    if path.is_absolute():
        try:
            path = path.relative_to(pathlib.Path.cwd())
        except ValueError:
            pass  # genuinely outside the checkout; leave it absolute
    return path


class Finding:
    """One gate result, reduced to the parts that decide its fate."""

    __slots__ = ("path", "line", "start_column", "end_column", "message")

    def __init__(self, path, line, start_column, end_column, message):
        self.path = path
        self.line = line
        self.start_column = start_column
        self.end_column = end_column
        self.message = message

    def identity(self):
        """What makes two findings the same call rather than two calls.

        The same result can appear in more than one SARIF file. Columns
        distinguish two genuinely different calls that share a line, so they
        belong in the key — otherwise deduplication would quietly merge the very
        case the shared-line rule exists to catch.
        """
        return (self.path, self.line, self.start_column, self.end_column, self.message)


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

    findings = {}
    for path in paths:
        with open(path) as handle:
            sarif = json.load(handle)
        for run in sarif.get("runs", []):
            for result in run.get("results", []):
                if result.get("ruleId") != GATE:
                    continue
                where = result["locations"][0]["physicalLocation"]
                region = where.get("region", {})
                finding = Finding(
                    path=str(source_path(where["artifactLocation"]["uri"])),
                    line=region.get("startLine", 1),
                    start_column=region.get("startColumn"),
                    end_column=region.get("endColumn"),
                    message=result["message"]["text"],
                )
                findings[finding.identity()] = finding

    # Group by the unit the exemption mechanism can actually address. A marker
    # names a line, not a call, so a line carrying two gate findings cannot be
    # approved by one — that was bypass 5: adding a second call beside an
    # already-approved one got past the gate. Fail closed instead of inventing
    # an approval the author never wrote.
    lines: dict[tuple, list[Finding]] = {}
    for finding in findings.values():
        lines.setdefault((finding.path, finding.line), []).append(finding)

    source_cache: dict[str, dict[int, str] | None] = {}

    for (path, line), group in sorted(lines.items()):
        if path not in source_cache:
            candidate = repo_root / path
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
