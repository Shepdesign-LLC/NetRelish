#!/usr/bin/env python3
"""release_notes.py: read a release's notes from git's object database, never the checkout.

The release workflow publishes docs/releases/<tag>.md as the public body of a GitHub
release. Reading that file through the working tree would follow a symlink. That could be
the notes file itself, or `docs` or `docs/releases` committed as a link. The release would
then publish whatever the link points at on the runner: the checkout's saved credentials,
a keychain, or anything else the job can read.

So this walks the path through the commit's own trees. Git never follows a link there.
Every directory on the way must be a tree, and the notes a regular file: a blob of mode
100644 or 100755. A symlink (120000), a submodule (160000) or anything else stops it, and
nothing is written.

    python3 -I scripts/release_notes.py <commit> <tag> <out-file>

It runs on the macOS runner's own python3, so it keeps to what Python 3.9 has.
"""

import os
import re
import subprocess
import sys

TAG = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$")
REGULAR_FILE_MODES = {"100644", "100755"}
TREE_MODE = "040000"
# GitHub refuses a release body longer than 125,000 characters; bytes are a safe bound.
MAX_BYTES = 125_000


class NotesError(Exception):
    """The notes can't be published as they are; the message says why."""


def _git(repo, *args):
    try:
        return subprocess.run(
            ["git", "-C", repo, *args], check=True, capture_output=True
        ).stdout
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", "replace").strip()
        raise NotesError(f"git {' '.join(args)} failed: {detail}") from None


def _entries(repo, tree):
    """Every entry of one tree, by exact name: {name: (mode, type, object id)}."""
    entries = {}
    for record in _git(repo, "ls-tree", "-z", tree).split(b"\0"):
        if not record:
            continue
        meta, _, name = record.partition(b"\t")
        mode, kind, oid = meta.decode("ascii").split(" ")
        entries[name.decode("utf-8", "surrogateescape")] = (mode, kind, oid)
    return entries


def notes_path(tag):
    if not TAG.match(tag):
        raise NotesError(f"'{tag}' is not vMAJOR.MINOR.PATCH (optionally -preview.N)")
    return f"docs/releases/{tag}.md"


def read_notes(repo, commit, tag):
    """The notes for `tag` as committed in `commit`, as text. Raises NotesError otherwise."""
    path = notes_path(tag)
    tree = _git(repo, "rev-parse", "--verify", f"{commit}^{{tree}}").decode().strip()
    *directories, filename = path.split("/")
    walked = []
    for name in directories:
        walked.append(name)
        entry = _entries(repo, tree).get(name)
        if entry is None:
            raise NotesError(f"{path} isn't in {commit}: there is no {'/'.join(walked)}")
        mode, kind, oid = entry
        if mode != TREE_MODE or kind != "tree":
            raise NotesError(
                f"{'/'.join(walked)} is not a directory in {commit} (mode {mode}); "
                "release notes are read only through real directories"
            )
        tree = oid
    entry = _entries(repo, tree).get(filename)
    if entry is None:
        raise NotesError(f"Write the release notes for {tag} at {path} before releasing")
    mode, kind, oid = entry
    if mode not in REGULAR_FILE_MODES or kind != "blob":
        raise NotesError(
            f"{path} is not a regular file in {commit} (mode {mode}); "
            "a symlink or submodule is never published as release notes"
        )
    size = int(_git(repo, "cat-file", "-s", oid).decode().strip())
    if size == 0:
        raise NotesError(f"{path} is empty")
    if size > MAX_BYTES:
        raise NotesError(f"{path} is {size} bytes; a release body holds at most {MAX_BYTES}")
    data = _git(repo, "cat-file", "blob", oid)
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise NotesError(f"{path} is not UTF-8 text") from None


def write_notes(text, out):
    """Write to `out` without following a link someone put there first."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(out, flags, 0o644)
    except OSError as error:
        raise NotesError(f"can't write {out}: {error.strerror}") from None
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)


def main(argv):
    if len(argv) != 4:
        print(f"usage: {argv[0]} <commit> <tag> <out-file>", file=sys.stderr)
        return 2
    _, commit, tag, out = argv
    try:
        write_notes(read_notes(".", commit, tag), out)
    except NotesError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print(f"release notes for {tag}: {notes_path(tag)} at {commit}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
