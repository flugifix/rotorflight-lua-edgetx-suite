#!/usr/bin/env python3
"""Check the release-notes rule on a pull request.

A change that reaches the radio carries a release note, as one file under
`release-notes/` (see `release-notes/README.md`). A pull request that changes `src/`
and genuinely needs none says so in its body, on a line of its own beginning with
`Release notes:`, and gives the reason.

The check is the same shape as the documentation rule's, and as narrow:

  * a pull request that changes nothing under `src/` is asked nothing at all
  * a pull request that changes `src/` and adds a file under `release-notes/` passes
  * a pull request that changes `src/` and edits `Releases.md` itself passes as well,
    so that pull requests written before `release-notes/` existed are not stopped
  * otherwise it passes only if its body carries the statement

Whether the reason is a good one is the reviewer's call; that a change cannot skip the
note in silence is what this makes sure of.

    python bin/release/verify_release_notes_rule.py --base <sha> --body-file <path>
    python bin/release/verify_release_notes_rule.py --self-test
"""

import argparse
import re
import subprocess
import sys

OBSERVABLE_PREFIX = "src/"
NOTES_PREFIX = "release-notes/"
RELEASES = "Releases.md"

#: The statement, as a line of its own. Bullets and bold markers are ignored.
STATEMENT_RE = re.compile(
    r"^\s*(?:[-*+]\s+)?[*_]{0,2}release[ -]notes?[*_]{0,2}\s*[:.][*_]{0,2}\s*(\S.*)$",
    re.IGNORECASE,
)


def is_note(path):
    return path.startswith(NOTES_PREFIX) and path.lower() != NOTES_PREFIX + "readme.md"


def verdict(added, changed, body):
    """Return (ok, reason) for the added and changed paths and a pull-request body."""
    if not any(p.startswith(OBSERVABLE_PREFIX) for p in changed):
        return True, "nothing under %s changed" % OBSERVABLE_PREFIX
    if any(is_note(p) for p in added):
        return True, "the pull request adds a release note under %s" % NOTES_PREFIX
    if RELEASES in changed:
        return True, "the pull request edits %s directly" % RELEASES
    for line in (body or "").splitlines():
        m = STATEMENT_RE.match(line)
        if m:
            return True, "no release note, and the body says why: %s" % m.group(1).strip()
    return False, (
        "this pull request changes %s and adds no release note.\n"
        "  Add one file under %s -- release-notes/<short-name>.<feature|fix|build>.md,\n"
        "  holding the entry as it should read in %s -- or, if the change genuinely\n"
        "  needs none, say so in the pull request body on a line of its own, for example\n"
        "\n"
        "      Release notes: none -- this only renames a local variable.\n"
        "\n"
        "  The format is in release-notes/README.md." % (OBSERVABLE_PREFIX, NOTES_PREFIX, RELEASES))


SRC = "src/rfsuite/lib/utils.lua"

SELF_TEST = (
    ([], [SRC], "", False, "a source file changes and nothing is said"),
    (["release-notes/utils-rename.fix.md"], [SRC, "release-notes/utils-rename.fix.md"], "",
     True, "the change carries a release note"),
    (["release-notes/README.md"], [SRC, "release-notes/README.md"], "",
     False, "adding the README is not a release note"),
    ([], [SRC, "release-notes/old.fix.md"], "",
     False, "deleting or editing an existing note is not this change's note"),
    ([], [SRC, RELEASES], "", True, "Releases.md is edited directly, the way it used to be"),
    ([], [SRC], "Summary\n\nRelease notes: none -- this only renames a local variable.\n",
     True, "the statement is there, as a line of its own"),
    ([], [SRC], "- **Release notes.** None: nothing here reaches a pilot.\n",
     True, "the statement is there, as a bold bullet"),
    ([], [SRC], "We will add release notes later.\n",
     False, "the words appear inside a sentence, which is not a statement"),
    ([], [SRC], "Release notes:\n", False, "a marker with no reason after it is not a statement"),
    ([], [SRC], "<!-- Release notes: say why, or delete this line -->\n",
     False, "a template placeholder left in a comment is not a statement"),
    ([], ["README.md", ".github/workflows/pr.yml"], "",
     True, "nothing that reaches the radio changed"),
)


def self_test():
    failures = 0
    for added, changed, body, expected, what in SELF_TEST:
        ok, reason = verdict(added, changed, body)
        mark = "ok  " if ok == expected else "FAIL"
        if ok != expected:
            failures += 1
        print("  %s  %-9s %s" % (mark, "expects " + ("pass" if expected else "fail"), what))
        if ok != expected:
            print("        got %s: %s" % ("pass" if ok else "fail", reason.splitlines()[0]))
    if failures:
        print("\n%d self-test case(s) failed -- this check proves nothing." % failures)
        return 1
    print("\n%d case(s), both verdicts reached: the check can pass and can go red."
          % len(SELF_TEST))
    return 0


def diff_names(base, head, extra=()):
    out = subprocess.run(["git", "diff", "--name-only", *extra, base, head],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("git diff %s %s failed\n%s" % (base, head, out.stderr.strip()))
        sys.exit(2)
    return [p.strip() for p in out.stdout.splitlines() if p.strip()]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", help="the commit the pull request is measured against")
    ap.add_argument("--head", default="HEAD", help="the commit under test")
    ap.add_argument("--body-file", help="a file holding the pull request body")
    ap.add_argument("--self-test", action="store_true", help="run the control and exit")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.base:
        ap.error("--base is required unless --self-test is given")

    body = ""
    if args.body_file:
        with open(args.body_file, encoding="utf-8") as fh:
            body = fh.read()

    changed = diff_names(args.base, args.head)
    added = diff_names(args.base, args.head, ("--diff-filter=A",))
    ok, reason = verdict(added, changed, body)
    print("%d file(s) changed between %s and %s" % (len(changed), args.base, args.head))
    if ok:
        print("OK -- %s" % reason)
        return 0
    print("FAILED -- %s" % reason)
    return 1


if __name__ == "__main__":
    sys.exit(main())
