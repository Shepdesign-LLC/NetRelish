#!/usr/bin/env python3
"""Tests for the non-negotiable-5 gate.

Every defect this exemption mechanism has had was in its enforcement rather
than its design, and every one was found by a human reading the code — because
the code was a heredoc inside a workflow and could not be run any other way.
Each named bypass below has a test here, and the tests run on every push,
independently of whether CodeQL itself can build the project.

Run:  python3 -m unittest discover -s scripts/tests
"""

import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import codeql_gate  # noqa: E402

REPO = pathlib.Path(__file__).resolve().parents[2]

MARKER = "NETRELISH-ALLOW-ENDPOINT: adr-0007"
CALL = "_ = try await URLSession.shared.data(from: url)"


def sarif(*results):
    return {"runs": [{"results": list(results)}]}


def result(uri, line, rule=codeql_gate.GATE, message="outbound network call",
           start_column=None, end_column=None):
    region = {"startLine": line}
    if start_column is not None:
        region["startColumn"] = start_column
    if end_column is not None:
        region["endColumn"] = end_column
    return {
        "ruleId": rule,
        "message": {"text": message},
        "locations": [{
            "physicalLocation": {
                "artifactLocation": {"uri": uri},
                "region": region,
            }
        }],
    }


class Checkout:
    """A throwaway checkout: some Swift, some ADRs, some SARIF."""

    def __init__(self, stack):
        self.root = pathlib.Path(stack.enter_context(tempfile.TemporaryDirectory()))
        (self.root / "docs" / "adr").mkdir(parents=True)
        (self.root / ".codeql-results").mkdir()
        self.adr("0007-timestamping.md")

    def adr(self, name):
        (self.root / "docs" / "adr" / name).write_text("# ADR\n")

    def swift(self, name, body):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
        return path

    def results(self, document, name="swift.sarif"):
        (self.root / ".codeql-results" / name).write_text(json.dumps(document))

    def evaluate(self):
        return codeql_gate.evaluate(self.root / ".codeql-results", self.root)


class ScannerTests(unittest.TestCase):
    """Where a marker is, and is not, a comment."""

    def comment_on(self, source, line):
        return codeql_gate.line_comments(source).get(line)

    def test_whole_line_comment(self):
        self.assertIn(MARKER, self.comment_on("// " + MARKER + "\n" + CALL, 1))

    def test_trailing_comment_after_code(self):
        self.assertIn(MARKER, self.comment_on(CALL + "  // " + MARKER, 1))

    def test_doc_comment_counts(self):
        self.assertIn(MARKER, self.comment_on("/// " + MARKER, 1))

    def test_marker_in_string_literal_is_not_a_comment(self):
        self.assertIsNone(self.comment_on('let s = "// ' + MARKER + '"', 1))

    def test_marker_in_block_comment_is_not_a_comment(self):
        # Bypass 4. `line.partition("//")` accepted this.
        self.assertIsNone(self.comment_on("/* // " + MARKER + " */", 1))

    def test_marker_in_multi_line_block_comment_is_not_a_comment(self):
        source = "/* disabled for now\n   // " + MARKER + "\n*/\n" + CALL
        self.assertIsNone(self.comment_on(source, 2))

    def test_nested_block_comment_stays_closed(self):
        # Swift block comments nest, so the first `*/` does not end this one.
        source = "/* outer /* inner */ // " + MARKER + " */\n" + CALL
        self.assertIsNone(self.comment_on(source, 1))

    def test_code_after_nested_block_comment_is_code_again(self):
        source = "/* a /* b */ c */ // " + MARKER
        self.assertIn(MARKER, self.comment_on(source, 1))

    def test_unterminated_block_comment_swallows_the_rest(self):
        source = "/* oops\n// " + MARKER + "\n" + CALL
        self.assertEqual(codeql_gate.line_comments(source), {})

    def test_comment_after_a_string_containing_slashes(self):
        # The hole the previous implementation documented as unclosable: a `//`
        # inside a string literal ahead of the real comment.
        source = 'let u = URL(string: "https://example.com")!  // ' + MARKER
        self.assertIn(MARKER, self.comment_on(source, 1))

    def test_escaped_quote_does_not_end_the_string(self):
        source = 'let s = "a \\" // ' + MARKER + '"'
        self.assertIsNone(self.comment_on(source, 1))

    def test_raw_string_is_not_a_comment(self):
        self.assertIsNone(self.comment_on('let s = #"// ' + MARKER + '"#', 1))

    def test_raw_string_with_two_hashes(self):
        self.assertIsNone(self.comment_on('let s = ##"// ' + MARKER + '"##', 1))

    def test_quote_hash_inside_double_hash_raw_string_does_not_close_it(self):
        source = 'let s = ##"a "# b // ' + MARKER + '"##'
        self.assertIsNone(self.comment_on(source, 1))

    def test_multiline_string_is_not_a_comment(self):
        source = 'let s = """\n// ' + MARKER + '\n"""\n' + CALL
        self.assertIsNone(self.comment_on(source, 2))

    def test_line_after_multiline_string_is_code_again(self):
        source = 'let s = """\nbody\n"""\n// ' + MARKER
        self.assertIn(MARKER, self.comment_on(source, 4))

    def test_marker_in_an_interpolated_string_is_not_a_comment(self):
        # Flat state mistook the nested opening quote for the outer closer and
        # fell out into "code" mid-literal, recording the marker as a comment.
        source = 'let s = "\\("// ' + MARKER + '")"\n' + CALL
        self.assertIsNone(self.comment_on(source, 1))

    def test_marker_in_a_raw_string_interpolation_is_not_a_comment(self):
        source = 'let s = #"\\#("// ' + MARKER + '")"#'
        self.assertIsNone(self.comment_on(source, 1))

    def test_marker_in_doubly_nested_interpolation_is_not_a_comment(self):
        source = 'let s = "\\("\\("// ' + MARKER + '")")"'
        self.assertIsNone(self.comment_on(source, 1))

    def test_marker_in_a_multiline_string_interpolation_is_not_a_comment(self):
        source = 'let s = """\n\\("// ' + MARKER + '")\n"""'
        self.assertIsNone(self.comment_on(source, 2))

    def test_comment_after_an_interpolation_is_a_comment(self):
        source = 'let s = "\\(a)"  // ' + MARKER
        self.assertIn(MARKER, self.comment_on(source, 1))

    def test_nested_parentheses_inside_an_interpolation(self):
        # The interpolation ends at its own matching paren, not the first one.
        source = 'let s = "\\(f(g(x)))"  // ' + MARKER
        self.assertIn(MARKER, self.comment_on(source, 1))

    def test_escaped_backslash_does_not_open_an_interpolation(self):
        source = 'let s = "\\\\(a)"  // ' + MARKER
        self.assertIn(MARKER, self.comment_on(source, 1))

    def test_string_opened_inside_an_interpolation_still_hides_a_marker(self):
        source = 'let s = "\\(x)" + "// ' + MARKER + '"'
        self.assertIsNone(self.comment_on(source, 1))

    def test_bare_regex_closing_delimiter_does_not_start_a_comment(self):
        # In `/\//` the escaped slash and the closing delimiter are textually
        # `//`, so the rest of the line was read as a comment.
        source = r'let r = /\//; let s = "' + MARKER + '"'
        self.assertIsNone(self.comment_on(source, 1))

    def test_a_real_comment_after_a_bare_regex_still_counts(self):
        source = r'let r = /\//  // ' + MARKER
        self.assertIn(MARKER, self.comment_on(source, 1))

    def test_escaped_delimiter_does_not_end_an_extended_regex(self):
        # `find("/#")` matched the `/` of an escaped `\/` and ended the literal
        # early, leaving the rest of the pattern to be read as code.
        source = r'let r = #/ a\/# b // ' + MARKER + ' /#'
        self.assertIsNone(self.comment_on(source, 1))

    def test_extended_regex_literal_is_not_a_comment(self):
        # Extended regex ignores whitespace, so the marker inside one reads
        # exactly like an approval to a scanner that does not know the form.
        self.assertIsNone(self.comment_on("let r = #/ // " + MARKER + " /#", 1))

    def test_extended_regex_literal_with_two_hashes(self):
        self.assertIsNone(self.comment_on("let r = ##/ // " + MARKER + " /##", 1))

    def test_slash_hash_inside_double_hash_regex_does_not_close_it(self):
        source = "let r = ##/ a /# b // " + MARKER + " /##"
        self.assertIsNone(self.comment_on(source, 1))

    def test_code_after_a_regex_literal_is_code_again(self):
        self.assertIn(MARKER, self.comment_on("let r = #/ a /#  // " + MARKER, 1))

    def test_multiline_regex_literal_is_not_a_comment(self):
        source = "let r = #/\n// " + MARKER + "\n/#\n" + CALL
        self.assertIsNone(self.comment_on(source, 2))

    def test_unterminated_regex_literal_swallows_the_rest(self):
        source = "let r = #/ oops\n// " + MARKER + "\n" + CALL
        self.assertEqual(codeql_gate.line_comments(source), {})

    def test_hash_directives_do_not_open_a_string(self):
        source = "#if DIRECT_BUILD\n#Preview { EmptyView() }\n#endif\n// " + MARKER
        self.assertIn(MARKER, self.comment_on(source, 4))

    def test_line_numbers_survive_multiline_constructs(self):
        source = 'let s = """\na\nb\n"""\n/* x\ny */\n// ' + MARKER
        self.assertIn(MARKER, self.comment_on(source, 7))

    def test_first_comment_on_the_line_wins(self):
        self.assertEqual(self.comment_on("// a // b", 1), " a // b")


class CitationTests(unittest.TestCase):
    """A marker is only an exemption if it names exactly one real decision."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name)
        (self.root / "docs" / "adr").mkdir(parents=True)
        self.addCleanup(self._tmp.cleanup)

    def cite(self, comment):
        report = codeql_gate.Report()
        return codeql_gate.cited_adr(comment, self.root, report), report

    def test_real_adr_is_accepted(self):
        (self.root / "docs" / "adr" / "0007-timestamping.md").write_text("#\n")
        adr, report = self.cite(" " + MARKER)
        self.assertEqual(adr, "adr-0007")
        self.assertEqual(report.errors, [])

    def test_absent_adr_is_refused(self):
        adr, report = self.cite(" NETRELISH-ALLOW-ENDPOINT: adr-9999")
        self.assertIsNone(adr)
        self.assertIn("no docs/adr/9999", report.errors[0])

    def test_ambiguous_adr_number_is_refused(self):
        # docs/adr/ has held two different decisions both numbered 0006.
        (self.root / "docs" / "adr" / "0006-one.md").write_text("#\n")
        (self.root / "docs" / "adr" / "0006-two.md").write_text("#\n")
        adr, report = self.cite(" NETRELISH-ALLOW-ENDPOINT: adr-0006")
        self.assertIsNone(adr)
        self.assertIn("ambiguous", report.errors[0])
        self.assertIn("0006-one.md", report.errors[0])
        self.assertIn("0006-two.md", report.errors[0])

    def test_a_directory_named_like_an_adr_is_refused(self):
        # glob() returns directories too, so `0007-placeholder.md/` would
        # satisfy the citation with no written decision inside it.
        (self.root / "docs" / "adr" / "0007-placeholder.md").mkdir()
        adr, report = self.cite(" " + MARKER)
        self.assertIsNone(adr)
        self.assertIn("no docs/adr/0007", report.errors[0])

    def test_a_real_adr_beside_a_directory_of_the_same_number(self):
        (self.root / "docs" / "adr" / "0007-placeholder.md").mkdir()
        (self.root / "docs" / "adr" / "0007-timestamping.md").write_text("#\n")
        adr, report = self.cite(" " + MARKER)
        self.assertEqual(adr, "adr-0007")   # the directory is not a clash
        self.assertEqual(report.errors, [])

    def test_a_symlinked_adr_is_refused(self):
        # is_file() follows symlinks, so this would otherwise accept a decision
        # that is not in the repository at all.
        outside = self.root / "elsewhere.md"
        outside.write_text("# not an ADR\n")
        (self.root / "docs" / "adr" / "0007-fake.md").symlink_to(outside)
        adr, report = self.cite(" " + MARKER)
        self.assertIsNone(adr)
        self.assertIn("no docs/adr/0007", report.errors[0])

    def test_a_symlink_beside_a_real_adr_is_not_a_clash(self):
        outside = self.root / "elsewhere.md"
        outside.write_text("# not an ADR\n")
        (self.root / "docs" / "adr" / "0007-fake.md").symlink_to(outside)
        (self.root / "docs" / "adr" / "0007-timestamping.md").write_text("#\n")
        adr, report = self.cite(" " + MARKER)
        self.assertEqual(adr, "adr-0007")
        self.assertEqual(report.errors, [])

    def test_an_adr_behind_a_symlinked_parent_is_refused(self):
        # Checking only the matched file left its parent unchecked, so
        # `docs/adr -> /tmp/decisions` returned ordinary regular files from
        # outside the checkout.
        import tempfile
        with tempfile.TemporaryDirectory() as elsewhere:
            (pathlib.Path(elsewhere) / "0007-planted.md").write_text("# not ours\n")
            (self.root / "docs" / "adr").rmdir()
            (self.root / "docs" / "adr").symlink_to(elsewhere)
            adr, report = self.cite(" " + MARKER)
        self.assertIsNone(adr)
        self.assertIn("no docs/adr/0007", report.errors[0])

    def test_comment_without_a_marker_is_not_an_error(self):
        adr, report = self.cite(" just an ordinary comment")
        self.assertIsNone(adr)
        self.assertEqual(report.errors, [])


class GateTests(unittest.TestCase):
    """End to end: SARIF in, verdict out."""

    def setUp(self):
        import contextlib
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.checkout = Checkout(self.stack)

    def test_missing_sarif_fails(self):
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertIn("the gate did not run", report.errors[0])

    def test_clean_sarif_passes(self):
        self.checkout.results(sarif())
        self.assertTrue(self.checkout.evaluate().ok)

    def test_audit_rule_alone_passes(self):
        self.checkout.swift("Sources/A.swift", CALL)
        self.checkout.results(sarif(
            result("Sources/A.swift", 1, rule="netrelish/remote-capable-url-read")
        ))
        self.assertTrue(self.checkout.evaluate().ok)

    def test_unapproved_gate_hit_blocks(self):
        self.checkout.swift("Sources/A.swift", CALL)
        self.checkout.results(sarif(result("Sources/A.swift", 1)))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(len(report.blocking), 1)

    def test_marker_on_the_line_above_approves(self):
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL)
        self.checkout.results(sarif(result("Sources/A.swift", 2)))
        report = self.checkout.evaluate()
        self.assertTrue(report.ok)
        self.assertEqual(report.approved[0][1], "adr-0007")

    def test_marker_on_the_same_line_approves(self):
        self.checkout.swift("Sources/A.swift", CALL + "  // " + MARKER)
        self.checkout.results(sarif(result("Sources/A.swift", 1)))
        self.assertTrue(self.checkout.evaluate().ok)

    def test_marker_two_lines_above_does_not_approve(self):
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n\n" + CALL)
        self.checkout.results(sarif(result("Sources/A.swift", 3)))
        self.assertFalse(self.checkout.evaluate().ok)

    def test_block_comment_marker_does_not_approve(self):
        # Bypass 4, end to end.
        self.checkout.swift("Sources/A.swift", "/* // " + MARKER + " */\n" + CALL)
        self.checkout.results(sarif(result("Sources/A.swift", 2)))
        self.assertFalse(self.checkout.evaluate().ok)

    def test_string_literal_marker_does_not_approve(self):
        self.checkout.swift("Sources/A.swift", 'let s = "' + MARKER + '"\n' + CALL)
        self.checkout.results(sarif(result("Sources/A.swift", 2)))
        self.assertFalse(self.checkout.evaluate().ok)

    def test_unknown_adr_does_not_approve(self):
        self.checkout.swift(
            "Sources/A.swift",
            "// NETRELISH-ALLOW-ENDPOINT: adr-9999\n" + CALL,
        )
        self.checkout.results(sarif(result("Sources/A.swift", 2)))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertTrue(any("9999" in e for e in report.errors))

    def test_two_findings_on_one_line_fail_closed(self):
        # Bypass 5: one valid marker used to approve every finding on the line,
        # so a second call beside an approved one got in free.
        self.checkout.swift(
            "Sources/A.swift",
            "// " + MARKER + "\n" + CALL + "; " + CALL,
        )
        self.checkout.results(sarif(
            result("Sources/A.swift", 2, start_column=5, end_column=40),
            result("Sources/A.swift", 2, start_column=60, end_column=95),
        ))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(len(report.blocking), 2)
        self.assertEqual(report.approved, [])
        self.assertIn("share this line", report.blocking[0][1])

    def test_trailing_marker_does_not_approve_the_next_flagged_line(self):
        # The shared-line bypass wearing a newline: a marker beside one call
        # must not also serve as the comment "above" the call below it.
        self.checkout.swift(
            "Sources/A.swift",
            CALL + "  // " + MARKER + "\n" + CALL,
        )
        self.checkout.results(sarif(
            result("Sources/A.swift", 1, start_column=5, end_column=46),
            result("Sources/A.swift", 2, start_column=5, end_column=46),
        ))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(len(report.approved), 1)   # line 1, beside its marker
        self.assertEqual(len(report.blocking), 1)
        self.assertEqual(report.blocking[0][0].line, 2)

    def test_standalone_comment_above_still_approves_a_flagged_line(self):
        # The guard above must not break the ordinary form, where the line above
        # holds only the comment and is never itself a finding.
        self.checkout.swift(
            "Sources/A.swift",
            "// " + MARKER + "\n" + CALL + "\n// " + MARKER + "\n" + CALL,
        )
        self.checkout.results(sarif(
            result("Sources/A.swift", 2, start_column=5, end_column=46),
            result("Sources/A.swift", 4, start_column=5, end_column=46),
        ))
        self.assertTrue(self.checkout.evaluate().ok)

    def test_interpolated_string_marker_does_not_approve(self):
        self.checkout.swift(
            "Sources/A.swift",
            'let s = "\\("// ' + MARKER + '")"\n' + CALL,
        )
        self.checkout.results(sarif(result("Sources/A.swift", 2)))
        self.assertFalse(self.checkout.evaluate().ok)

    def test_regex_literal_marker_does_not_approve(self):
        self.checkout.swift(
            "Sources/A.swift",
            "let r = #/ // " + MARKER + " /#\n" + CALL,
        )
        self.checkout.results(sarif(result("Sources/A.swift", 2)))
        self.assertFalse(self.checkout.evaluate().ok)

    def test_one_position_reworded_is_still_one_finding(self):
        # Same call site, different message text: description, not identity.
        # Splitting it would invent a shared line and block a valid exemption.
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL)
        self.checkout.results(sarif(
            result("Sources/A.swift", 2, start_column=5, end_column=46,
                   message="outbound network call"),
        ), "a.sarif")
        self.checkout.results(sarif(
            result("Sources/A.swift", 2, start_column=5, end_column=46,
                   message="outbound network call via URLSession"),
        ), "b.sarif")
        report = self.checkout.evaluate()
        self.assertTrue(report.ok)
        self.assertEqual(len(report.approved), 1)

    def test_columnless_findings_on_one_line_still_fail_closed(self):
        # With no columns there is nothing to tell two calls apart, so the
        # message stays in the key and the shared line blocks.
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL + "; " + CALL)
        self.checkout.results(sarif(
            result("Sources/A.swift", 2, message="call to data(from:)"),
            result("Sources/A.swift", 2, message="call to bytes(from:)"),
        ))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(len(report.blocking), 2)

    def test_columnless_findings_with_the_same_message_fail_closed(self):
        # The common case, and the one a message-based key got wrong: two
        # separate calls on one line usually carry identical text, so keying on
        # the message merged them and one marker approved both.
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL + "; " + CALL)
        self.checkout.results(sarif(
            result("Sources/A.swift", 2, message="outbound network call"),
            result("Sources/A.swift", 2, message="outbound network call"),
        ))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(len(report.blocking), 2)
        self.assertEqual(report.approved, [])

    def test_a_finding_without_a_start_line_cannot_be_approved(self):
        # Defaulting to line 1 let a marker on line 1 approve a finding whose
        # location is unknown.
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL)
        hit = result("Sources/A.swift", 1)
        del hit["locations"][0]["physicalLocation"]["region"]["startLine"]
        self.checkout.results(sarif(hit))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(report.approved, [])
        self.assertTrue(any("no usable startLine" in e for e in report.errors))

    def test_a_finding_with_an_invalid_start_line_cannot_be_approved(self):
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL)
        hit = result("Sources/A.swift", 1)
        hit["locations"][0]["physicalLocation"]["region"]["startLine"] = 0
        self.checkout.results(sarif(hit))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertTrue(any("no usable startLine" in e for e in report.errors))

    def test_the_same_finding_in_two_sarif_files_is_one_finding(self):
        # Deduplication must not turn a duplicate report into a shared line.
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL)
        hit = result("Sources/A.swift", 2, start_column=5, end_column=40)
        self.checkout.results(sarif(hit), "a.sarif")
        self.checkout.results(sarif(hit), "b.sarif")
        report = self.checkout.evaluate()
        self.assertTrue(report.ok)
        self.assertEqual(len(report.approved), 1)

    def test_two_approved_findings_on_separate_lines(self):
        self.checkout.swift(
            "Sources/A.swift",
            "// " + MARKER + "\n" + CALL + "\n// " + MARKER + "\n" + CALL,
        )
        self.checkout.results(sarif(
            result("Sources/A.swift", 2),
            result("Sources/A.swift", 4),
        ))
        report = self.checkout.evaluate()
        self.assertTrue(report.ok)
        self.assertEqual(len(report.approved), 2)

    def test_unreadable_source_blocks(self):
        self.checkout.results(sarif(result("Sources/Gone.swift", 1)))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertTrue(any("cannot read" in e for e in report.errors))

    def test_two_spellings_of_one_path_are_one_line(self):
        # SARIF chooses the spelling. Grouping on the raw string put two
        # findings on one physical line into two groups of one, and a single
        # marker approved both.
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL + "; " + CALL)
        self.checkout.results(sarif(
            result("Sources/A.swift", 2, start_column=5, end_column=46),
            result("Sources/../Sources/A.swift", 2, start_column=60, end_column=101),
        ))
        report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(report.approved, [])
        self.assertEqual(len(report.blocking), 2)
        self.assertIn("share this line", report.blocking[0][1])

    def test_a_traversing_uri_that_lands_back_inside_is_canonicalised(self):
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL)
        self.checkout.results(sarif(result("Sources/../Sources/A.swift", 2)))
        report = self.checkout.evaluate()
        self.assertTrue(report.ok)
        self.assertEqual(report.approved[0][0].path, "Sources/A.swift")

    def test_a_source_outside_the_checkout_is_not_trusted(self):
        # A SARIF location naming any file on the runner that happens to carry
        # a valid marker used to be read, and approved.
        import tempfile
        with tempfile.TemporaryDirectory() as elsewhere:
            planted = pathlib.Path(elsewhere) / "Evil.swift"
            planted.write_text("// " + MARKER + "\n" + CALL)
            self.checkout.results(sarif(result(planted.as_uri(), 2)))
            report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(report.approved, [])
        self.assertTrue(any("outside the checkout" in e for e in report.errors))

    def test_a_traversing_relative_uri_is_not_trusted(self):
        import tempfile
        with tempfile.TemporaryDirectory() as elsewhere:
            planted = pathlib.Path(elsewhere) / "Evil.swift"
            planted.write_text("// " + MARKER + "\n" + CALL)
            hops = pathlib.Path(*([".."] * 12)) / planted.relative_to("/")
            self.checkout.results(sarif(result(str(hops), 2)))
            report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(report.approved, [])
        self.assertTrue(any("outside the checkout" in e for e in report.errors))

    def test_a_symlinked_source_pointing_outside_is_not_trusted(self):
        import tempfile
        with tempfile.TemporaryDirectory() as elsewhere:
            planted = pathlib.Path(elsewhere) / "Evil.swift"
            planted.write_text("// " + MARKER + "\n" + CALL)
            link = self.checkout.root / "Sources" / "A.swift"
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(planted)
            self.checkout.results(sarif(result("Sources/A.swift", 2)))
            report = self.checkout.evaluate()
        self.assertFalse(report.ok)
        self.assertEqual(report.approved, [])
        self.assertTrue(any("outside the checkout" in e for e in report.errors))

    def test_file_uri_resolves(self):
        path = self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL)
        self.checkout.results(sarif(result(path.as_uri(), 2)))
        self.assertTrue(self.checkout.evaluate().ok)

    def test_percent_encoded_uri_resolves(self):
        self.checkout.swift("Sources/My App.swift", "// " + MARKER + "\n" + CALL)
        self.checkout.results(sarif(result("Sources/My%20App.swift", 2)))
        self.assertTrue(self.checkout.evaluate().ok)


class ExitCodeTests(unittest.TestCase):
    """main() is what CI actually runs."""

    def setUp(self):
        import contextlib
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.checkout = Checkout(self.stack)

    def run_main(self):
        return codeql_gate.main([
            str(self.checkout.root / ".codeql-results"),
            "--repo-root", str(self.checkout.root),
        ])

    def test_clean_exits_zero(self):
        self.checkout.results(sarif())
        self.assertEqual(self.run_main(), 0)

    def test_blocking_exits_one(self):
        self.checkout.swift("Sources/A.swift", CALL)
        self.checkout.results(sarif(result("Sources/A.swift", 1)))
        self.assertEqual(self.run_main(), 1)

    def test_missing_sarif_exits_one(self):
        self.assertEqual(self.run_main(), 1)

    def test_approved_exits_zero(self):
        self.checkout.swift("Sources/A.swift", "// " + MARKER + "\n" + CALL)
        self.checkout.results(sarif(result("Sources/A.swift", 2)))
        self.assertEqual(self.run_main(), 0)


class RepositoryTests(unittest.TestCase):
    """Invariants of this repo that the gate depends on."""

    def test_adr_numbers_are_unique(self):
        seen = {}
        for path in sorted((REPO / "docs" / "adr").glob("[0-9][0-9][0-9][0-9]-*.md")):
            seen.setdefault(path.name[:4], []).append(path.name)
        clashes = {n: f for n, f in seen.items() if len(f) > 1}
        self.assertEqual(
            clashes, {},
            "Two ADRs share a number, so NETRELISH-ALLOW-ENDPOINT: adr-NNNN "
            "cannot name one decision: " + repr(clashes),
        )


if __name__ == "__main__":
    unittest.main()
