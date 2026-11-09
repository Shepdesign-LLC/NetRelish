#!/usr/bin/env python3
"""Tests for scripts/release_notes.py: release notes come from git objects, never a link.

The release workflow publishes docs/releases/<tag>.md as a public release body. Each way a
commit could point that at something else on the runner has a test here: the file as a
symlink, `docs` or `docs/releases` as one, a submodule in the path, and a working tree that
disagrees with the commit. Built in throwaway repositories, so nothing here needs a Mac.

Run:  python3 -m unittest discover -s scripts/tests
"""

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import release_notes  # noqa: E402

TAG = "v9.9.9"
PATH = f"docs/releases/{TAG}.md"
NOTES = "The ninth preview. Pickled, not preserved in brine.\n"
SECRET = "AUTHORIZATION: basic eC1hY2Nlc3MtdG9rZW46c2VjcmV0\n"


class Repo:
    """A scratch git repository with a secret file beside it, outside the tree."""

    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.dir = self.root / "repo"
        self.dir.mkdir()
        self.secret = self.root / "credentials.config"
        self.secret.write_text(SECRET)
        self.git("init", "-q")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("config", "user.name", "CI")
        self.git("config", "commit.gpgsign", "false")

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", str(self.dir), *args], check=True, capture_output=True, text=True
        ).stdout.strip()

    def write(self, rel, text):
        path = self.dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def link(self, rel, target):
        path = self.dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(target, path)

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", "test")
        return self.git("rev-parse", "HEAD")

    def read(self, commit, tag=TAG):
        return release_notes.read_notes(str(self.dir), commit, tag)


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Repo(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def assertRefused(self, commit, fragment, tag=TAG):
        with self.assertRaises(release_notes.NotesError) as caught:
            self.repo.read(commit, tag)
        self.assertIn(fragment, str(caught.exception))
        # Nothing from the planted secret reaches the message.
        self.assertNotIn(SECRET.split()[-1], str(caught.exception))

    # What should be published is published.

    def test_reads_a_regular_file(self):
        self.repo.write(PATH, NOTES)
        self.assertEqual(self.repo.read(self.repo.commit()), NOTES)

    def test_reads_an_executable_file(self):
        (self.repo.write(PATH, NOTES)).chmod(0o755)
        self.assertEqual(self.repo.read(self.repo.commit()), NOTES)

    def test_reads_the_commit_not_the_working_tree(self):
        self.repo.write(PATH, NOTES)
        commit = self.repo.commit()
        # Someone swaps the checked-out file for a link after the commit: the commit wins.
        (self.repo.dir / PATH).unlink()
        os.symlink(self.repo.secret, self.repo.dir / PATH)
        self.assertEqual(self.repo.read(commit), NOTES)

    # Every way of pointing the notes somewhere else is refused.

    def test_refuses_the_notes_file_as_a_symlink(self):
        self.repo.link(PATH, str(self.repo.secret))
        self.assertRefused(self.repo.commit(), "not a regular file")

    def test_refuses_a_relative_symlink_escaping_the_repository(self):
        self.repo.link(PATH, "../../../credentials.config")
        self.assertRefused(self.repo.commit(), "not a regular file")

    def test_refuses_docs_releases_as_a_symlink(self):
        self.repo.write(f"elsewhere/{TAG}.md", NOTES)
        self.repo.link("docs/releases", "../elsewhere")
        self.assertRefused(self.repo.commit(), "docs/releases is not a directory")

    def test_refuses_docs_as_a_symlink(self):
        self.repo.write(f"elsewhere/releases/{TAG}.md", NOTES)
        self.repo.link("docs", "elsewhere")
        self.assertRefused(self.repo.commit(), "docs is not a directory")

    def test_refuses_docs_as_a_submodule(self):
        self.repo.write("README", "x")
        commit = self.repo.commit()
        self.repo.git("update-index", "--add", "--cacheinfo", f"160000,{commit},docs")
        self.repo.git("commit", "-q", "-m", "gitlink")
        self.assertRefused(self.repo.git("rev-parse", "HEAD"), "docs is not a directory")

    def test_refuses_the_notes_path_as_a_directory(self):
        self.repo.write(f"{PATH}/inner", NOTES)
        self.assertRefused(self.repo.commit(), "not a regular file")

    def test_refuses_the_notes_path_as_a_submodule(self):
        self.repo.write("README", "x")
        commit = self.repo.commit()
        self.repo.git("update-index", "--add", "--cacheinfo", f"160000,{commit},{PATH}")
        self.repo.git("commit", "-q", "-m", "gitlink")
        self.assertRefused(self.repo.git("rev-parse", "HEAD"), "not a regular file")

    def test_refuses_a_tree_that_lists_a_name_twice(self):
        blob = subprocess.run(["git", "-C", str(self.repo.dir), "hash-object", "-w", "--stdin"],
                              input=NOTES.encode(), capture_output=True, check=True).stdout.decode().strip()
        bad = subprocess.run(["git", "-C", str(self.repo.dir), "hash-object", "-w", "--stdin"],
                             input=SECRET.encode(), capture_output=True, check=True).stdout.decode().strip()

        def tree(entries):
            body = b"".join(mode + b" " + name + b"\0" + bytes.fromhex(oid) for mode, name, oid in entries)
            return subprocess.run(
                ["git", "-C", str(self.repo.dir), "hash-object", "-t", "tree", "--literally", "-w", "--stdin"],
                input=body, capture_output=True, check=True).stdout.decode().strip()

        name = f"{TAG}.md".encode()
        releases = tree([(b"100644", name, blob), (b"100644", name, bad)])
        docs = tree([(b"40000", b"releases", releases)])
        root = tree([(b"40000", b"docs", docs)])
        commit = self.repo.git("commit-tree", root, "-m", "duplicate")
        self.assertRefused(commit, "more than once")

    def test_reads_the_root_notes_from_a_subdirectory(self):
        self.repo.write(PATH, NOTES)
        self.repo.write(f"sub/{PATH}", SECRET)   # a decoy, at the same path under sub/
        commit = self.repo.commit()
        cwd = os.getcwd()
        os.chdir(self.repo.dir / "sub")
        try:
            self.assertEqual(release_notes.read_notes(".", commit, TAG), NOTES)
        finally:
            os.chdir(cwd)

    # Missing, empty, too big, not text, or a bad tag: nothing is published.

    def test_refuses_missing_notes(self):
        self.repo.write("docs/releases/v0.0.1.md", NOTES)
        self.assertRefused(self.repo.commit(), "Write the release notes")

    def test_refuses_a_missing_docs_directory(self):
        self.repo.write("README", "x")
        self.assertRefused(self.repo.commit(), "there is no docs")

    def test_refuses_empty_notes(self):
        self.repo.write(PATH, "")
        self.assertRefused(self.repo.commit(), "is empty")

    def test_refuses_oversized_notes(self):
        self.repo.write(PATH, "x" * (release_notes.MAX_BYTES + 1))
        self.assertRefused(self.repo.commit(), "at most")

    def test_refuses_notes_that_are_not_utf8(self):
        (self.repo.dir / "docs/releases").mkdir(parents=True)
        (self.repo.dir / PATH).write_bytes(b"\xff\xfe binary")
        self.assertRefused(self.repo.commit(), "not UTF-8")

    def test_refuses_a_tag_that_is_not_a_version(self):
        self.repo.write(PATH, NOTES)
        commit = self.repo.commit()
        for tag in ["../../etc/passwd", "v1.2", "main", "v1.2.3/../../x", "", "v1.2.3\n", "v1.2.3\n.md"]:
            with self.subTest(tag=tag):
                self.assertRefused(commit, "is not vMAJOR.MINOR.PATCH", tag=tag)

    # Writing the output never follows a link either.

    def test_write_refuses_a_symlinked_output(self):
        out = self.repo.root / "notes.md"
        os.symlink(self.repo.secret, out)
        with self.assertRaises(release_notes.NotesError):
            release_notes.write_notes(NOTES, str(out))
        self.assertEqual(self.repo.secret.read_text(), SECRET)

    def test_main_writes_nothing_for_a_symlinked_notes_file(self):
        self.repo.link(PATH, str(self.repo.secret))
        commit = self.repo.commit()
        out = self.repo.root / "notes.md"
        cwd = os.getcwd()
        os.chdir(self.repo.dir)
        try:
            self.assertEqual(release_notes.main(["x", commit, TAG, str(out)]), 1)
        finally:
            os.chdir(cwd)
        self.assertFalse(out.exists())

    def test_main_writes_the_notes_and_fails_closed(self):
        self.repo.write(PATH, NOTES)
        commit = self.repo.commit()
        out = self.repo.root / "notes.md"
        cwd = os.getcwd()
        os.chdir(self.repo.dir)
        try:
            self.assertEqual(release_notes.main(["x", commit, TAG, str(out)]), 0)
            self.assertEqual(out.read_text(), NOTES)
            bad = self.repo.root / "bad.md"
            self.assertEqual(release_notes.main(["x", commit, "v0.0.0", str(bad)]), 1)
            self.assertFalse(bad.exists())
        finally:
            os.chdir(cwd)


if __name__ == "__main__":
    unittest.main()
