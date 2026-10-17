#!/usr/bin/env python3
"""File the pending release notes under their release in `Releases.md`.

A pull request does not write into `Releases.md`. It adds one file under
`release-notes/`, and that file carries the entry exactly as it would have stood in
`Releases.md`. Nothing in it names a version: which release a change belongs to is only
known when it is released, and a pull request that waited past a version bump used to
carry its entry under the release before -- or collided in `Releases.md` with every
other open pull request, because all of them inserted at the same place.

The file name says the section:

    release-notes/<short-name>.feature.md   ->  ### Features & Enhancements
    release-notes/<short-name>.fix.md       ->  ### Bug Fixes & Improvements
    release-notes/<short-name>.build.md     ->  ### Performance & Build System

At release time this script moves every pending file into `Releases.md`, under the
header of the version in `src/rfsuite/lib/version.lua` (created at the top if it is not
there yet, appended to if it is), one `###` block per section in the order above, and
deletes the files it filed. Where the commit that added a file names its pull request
-- `subject (#123)` for a squash, `Merge pull request #123 ...` for a merge commit --
the number is added to the entry unless the entry already names it.

    python bin/release/collect_release_notes.py              # file them, delete the files
    python bin/release/collect_release_notes.py --dry-run    # print what would be filed
    python bin/release/collect_release_notes.py --check      # validate the pending files
    python bin/release/collect_release_notes.py --require-empty   # fail while any is pending
    python bin/release/collect_release_notes.py --self-test
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
NOTES_DIR = "release-notes"
RELEASES = "Releases.md"
VERSION_LUA = os.path.join("src", "rfsuite", "lib", "version.lua")

#: File-name suffix -> section header, in the order the sections are written.
SECTIONS = (
    ("feature", "Features & Enhancements"),
    ("fix", "Bug Fixes & Improvements"),
    ("build", "Performance & Build System"),
)
KINDS = dict(SECTIONS)

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*\.(%s)\.md$" % "|".join(KINDS))
SQUASH_RE = re.compile(r"\(#(\d+)\)\s*$")
MERGE_RE = re.compile(r"^Merge pull request #(\d+)\b")


def read_text(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    newline = "\r\n" if b"\r\n" in raw else "\n"
    return raw.decode("utf-8").replace("\r\n", "\n"), newline


def write_text(path, text, newline):
    with open(path, "wb") as fh:
        fh.write(text.replace("\n", newline).encode("utf-8"))


def read_version(root):
    text, _ = read_text(os.path.join(root, VERSION_LUA))
    parts = []
    for name in ("MAJOR", "MINOR", "PATCH"):
        m = re.search(r"^M\.%s\s*=\s*(\d+)" % name, text, re.MULTILINE)
        if not m:
            raise SystemExit("%s: no M.%s = <number>" % (VERSION_LUA, name))
        parts.append(m.group(1))
    return ".".join(parts)


def pending(root):
    """Every file under release-notes/ except the README, sorted by name."""
    folder = os.path.join(root, NOTES_DIR)
    if not os.path.isdir(folder):
        return []
    return sorted(n for n in os.listdir(folder)
                  if n.lower() != "readme.md" and os.path.isfile(os.path.join(folder, n)))


def problems(name, text):
    """What is wrong with one pending file, as a list of sentences; empty when it is fine."""
    out = []
    if not NAME_RE.match(name):
        out.append("the name must be <short-name>.<%s>.md, lower case" % "|".join(KINDS))
    lines = text.strip("\n").split("\n") if text.strip() else []
    if not lines:
        out.append("the file is empty")
        return out
    if not lines[0].startswith("- "):
        out.append("the entry must start with a list item, '- '")
    for line in lines:
        if line.startswith("#"):
            out.append("no headers: the section comes from the file name, the version from the release")
            break
    for line in lines:
        if line.startswith("***"):
            out.append("no '***' line: the release-notes extractor reads it as the end of a section")
            break
    return out


def pr_number(root, relpath):
    """The pull request that added `relpath`, read off the first-parent history, or None."""
    out = subprocess.run(
        ["git", "log", "--first-parent", "--diff-filter=A", "--format=%s", "--", relpath],
        cwd=root, capture_output=True, text=True)
    if out.returncode != 0:
        return None
    subjects = [s for s in out.stdout.splitlines() if s.strip()]
    if not subjects:
        return None
    subject = subjects[-1]  # the oldest: the commit that first added the file
    m = SQUASH_RE.search(subject) or MERGE_RE.match(subject)
    return m.group(1) if m else None


def with_number(entry, number):
    """Add `(#N)` to the entry's bold title, the way the entries in Releases.md carry it,
    or to the end of the first line where the entry has no bold title."""
    if not number:
        return entry
    lines = entry.split("\n")
    first = lines[0]
    if re.search(r"#%s\b" % number, first):
        return entry
    m = re.match(r"^(- \*\*)(.+?)(\*\*.*)$", first)
    if m:
        lines[0] = "%s%s (#%s)%s" % (m.group(1), m.group(2).rstrip(), number, m.group(3))
    else:
        lines[0] = "%s (#%s)" % (first.rstrip(), number)
    return "\n".join(lines)


def render(entries):
    """entries: list of (kind, text). Returns the markdown of the new blocks."""
    blocks = []
    for kind, header in SECTIONS:
        items = [text for k, text in entries if k == kind]
        if items:
            blocks.append("### %s\n\n%s\n" % (header, "\n".join(items)))
    return "\n".join(blocks)


def insert(releases_text, version, blocks):
    """Put `blocks` at the end of the `# version` section, creating it at the top if absent."""
    lines = releases_text.split("\n")
    header = "# " + version
    start = next((i for i, line in enumerate(lines) if line.strip() == header), None)
    if start is None:
        return "%s\n\n%s\n%s" % (header, blocks, releases_text)
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].startswith("# ") or lines[i].startswith("***")), len(lines))
    head = "\n".join(lines[:end]).rstrip("\n")
    tail = "\n".join(lines[end:])
    return "%s\n\n%s\n%s" % (head, blocks, tail)


def collect(root, version, dry_run=False, out=sys.stdout):
    names = pending(root)
    if not names:
        print("no pending release notes under %s/" % NOTES_DIR, file=out)
        return 0
    bad = 0
    entries = []
    for name in names:
        rel = "%s/%s" % (NOTES_DIR, name)
        text, _ = read_text(os.path.join(root, rel))
        issues = problems(name, text)
        if issues:
            bad += 1
            print("%s: %s" % (rel, "; ".join(issues)), file=out)
            continue
        kind = NAME_RE.match(name).group(1)
        entries.append((kind, with_number(text.strip("\n"), pr_number(root, rel))))
    if bad:
        print("%d file(s) refused, nothing filed" % bad, file=out)
        return 1

    blocks = render(entries)
    if dry_run:
        print("# %s\n\n%s" % (version, blocks), file=out)
        return 0

    path = os.path.join(root, RELEASES)
    text, newline = read_text(path)
    write_text(path, insert(text, version, blocks), newline)
    for name in names:
        os.remove(os.path.join(root, NOTES_DIR, name))
    print("filed %d release note(s) under # %s in %s" % (len(names), version, RELEASES), file=out)
    return 0


def check(root, out=sys.stdout):
    names = pending(root)
    bad = 0
    for name in names:
        rel = "%s/%s" % (NOTES_DIR, name)
        text, _ = read_text(os.path.join(root, rel))
        issues = problems(name, text)
        if issues:
            bad += 1
            print("FAIL  %s: %s" % (rel, "; ".join(issues)), file=out)
    print("%d pending release note(s), %d refused" % (len(names), bad), file=out)
    return 1 if bad else 0


def require_empty(root, out=sys.stdout):
    names = pending(root)
    if not names:
        print("no pending release notes", file=out)
        return 0
    print("%d release note(s) are still pending under %s/ and would be missing from this "
          "release:" % (len(names), NOTES_DIR), file=out)
    for name in names:
        print("  %s/%s" % (NOTES_DIR, name), file=out)
    print("Run python bin/release/collect_release_notes.py and commit the result before tagging.",
          file=out)
    return 1


# --- self-test ---------------------------------------------------------------------------

def _git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True)


def _write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def self_test():
    """Build a throw-away repository with a squash merge, a merge commit and a direct
    commit, collect, and compare against what is known without running anything. The
    refusal cases are the point: a check that cannot go red proves nothing."""
    failures = []

    def expect(what, ok):
        print("  %s  %s" % ("ok  " if ok else "FAIL", what))
        if not ok:
            failures.append(what)

    # Pure cases first: the file checks.
    expect("a well-formed file is accepted",
           problems("x.fix.md", "- **A fix (`lib/a.lua`)**: it works.\n") == [])
    expect("an unknown section suffix is refused",
           problems("x.misc.md", "- entry\n") != [])
    expect("an empty file is refused", problems("x.fix.md", "\n") != [])
    expect("a version header inside the file is refused",
           problems("x.fix.md", "- entry\n# 0.2.1\n") != [])
    expect("a '***' line is refused", problems("x.fix.md", "- entry\n***\n") != [])
    expect("an entry that is not a list item is refused",
           problems("x.fix.md", "Some prose.\n") != [])
    expect("(#N) goes inside the closing bold marker",
           with_number("- **Title (`a.lua`)**:", "12") == "- **Title (`a.lua`) (#12)**:")
    expect("an entry that already names its number keeps it as it is",
           with_number("- **Title (#12)**:", "12") == "- **Title (#12)**:")
    expect("no number, no change", with_number("- **Title**:", None) == "- **Title**:")

    with tempfile.TemporaryDirectory() as root:
        _git(root, "init", "-q", "-b", "master")
        _git(root, "config", "user.email", "test@example.invalid")
        _git(root, "config", "user.name", "test")
        _git(root, "config", "commit.gpgsign", "false")
        _write(root, VERSION_LUA, "local M = {}\nM.MAJOR = 0\nM.MINOR = 2\nM.PATCH = 1\nreturn M\n")
        _write(root, RELEASES, "# 0.2.1\n\n### Features & Enhancements\n\n- **Existing (#1)**:\n"
                               "  - kept.\n\n# 0.2.0\n\n### Bug Fixes & Improvements\n\n- **Old**\n")
        _write(root, NOTES_DIR + "/README.md", "how to\n")
        _git(root, "add", "-A")
        _git(root, "commit", "-q", "-m", "base")

        # A squash merge: the subject ends in (#41).
        _write(root, NOTES_DIR + "/squash.feature.md", "- **Squashed (`lib/a.lua`)**:\n  - detail.\n")
        _git(root, "add", "-A")
        _git(root, "commit", "-q", "-m", "feat: a squashed change (#41)")

        # A merge commit: the file is added on a side branch whose own commit names nothing.
        _git(root, "checkout", "-q", "-b", "side")
        _write(root, NOTES_DIR + "/merged.fix.md", "- **Merged (`lib/b.lua`)**: fixed.\n")
        _git(root, "add", "-A")
        _git(root, "commit", "-q", "-m", "fix: the side change")
        _git(root, "checkout", "-q", "master")
        _git(root, "merge", "-q", "--no-ff", "side", "-m", "Merge pull request #42 from someone/side")

        # A direct commit with no number at all.
        _write(root, NOTES_DIR + "/direct.build.md", "- **Direct**: built.\n")
        _git(root, "add", "-A")
        _git(root, "commit", "-q", "-m", "build: a direct commit")

        expect("the squash merge's number is found",
               pr_number(root, NOTES_DIR + "/squash.feature.md") == "41")
        expect("the merge commit's number is found, not the side commit's subject",
               pr_number(root, NOTES_DIR + "/merged.fix.md") == "42")
        expect("a commit that names no pull request gives no number",
               pr_number(root, NOTES_DIR + "/direct.build.md") is None)
        expect("the version is read from version.lua", read_version(root) == "0.2.1")

        with open(os.devnull, "w") as null:
            expect("--require-empty fails while files are pending", require_empty(root, null) == 1)
            expect("--check accepts the pending files", check(root, null) == 0)
            rc = collect(root, read_version(root), out=null)
        expect("collecting succeeds", rc == 0)

        text, _ = read_text(os.path.join(root, RELEASES))
        want = ("# 0.2.1\n\n### Features & Enhancements\n\n- **Existing (#1)**:\n  - kept.\n\n"
                "### Features & Enhancements\n\n- **Squashed (`lib/a.lua`) (#41)**:\n  - detail.\n\n"
                "### Bug Fixes & Improvements\n\n- **Merged (`lib/b.lua`) (#42)**: fixed.\n\n"
                "### Performance & Build System\n\n- **Direct**: built.\n\n"
                "# 0.2.0\n\n### Bug Fixes & Improvements\n\n- **Old**\n")
        expect("the entries land at the end of the 0.2.1 section, in section order", text == want)
        if text != want:
            print("        got:")
            print("\n".join("        | " + l for l in text.split("\n")))
        expect("the filed files are deleted and the README stays",
               os.listdir(os.path.join(root, NOTES_DIR)) == ["README.md"])
        with open(os.devnull, "w") as null:
            expect("--require-empty passes once they are filed", require_empty(root, null) == 0)

        # A version with no header yet gets one at the top.
        _write(root, NOTES_DIR + "/next.fix.md", "- **Next**: fixed.\n")
        with open(os.devnull, "w") as null:
            collect(root, "0.2.2", out=null)
        text, _ = read_text(os.path.join(root, RELEASES))
        expect("a release with no header yet gets one at the top",
               text.startswith("# 0.2.2\n\n### Bug Fixes & Improvements\n\n- **Next**: fixed.\n\n# 0.2.1\n"))

        # A refused file stops the whole run: nothing is half filed.
        _write(root, NOTES_DIR + "/Bad Name.md", "- entry\n")
        _write(root, NOTES_DIR + "/good.fix.md", "- **Good**: fine.\n")
        before, _ = read_text(os.path.join(root, RELEASES))
        with open(os.devnull, "w") as null:
            expect("--check fails on a refused file", check(root, null) == 1)
            expect("collecting refuses when any file is refused", collect(root, "0.2.2", out=null) == 1)
        after, _ = read_text(os.path.join(root, RELEASES))
        expect("a refused run leaves Releases.md and the files untouched",
               before == after and "good.fix.md" in os.listdir(os.path.join(root, NOTES_DIR)))

    if failures:
        print("\n%d self-test case(s) failed -- this script proves nothing." % len(failures))
        return 1
    print("\nAll cases passed, and the refusals were reached: the checks can go red.")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="print what would be filed")
    mode.add_argument("--check", action="store_true", help="validate the pending files")
    mode.add_argument("--require-empty", action="store_true",
                      help="fail while any release note is pending (used on a release tag)")
    mode.add_argument("--self-test", action="store_true", help="run the control and exit")
    ap.add_argument("--version", help="the release to file under (default: version.lua)")
    args = ap.parse_args(argv)

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if args.self_test:
        return self_test()
    if args.check:
        return check(ROOT)
    if args.require_empty:
        return require_empty(ROOT)
    return collect(ROOT, args.version or read_version(ROOT), dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
