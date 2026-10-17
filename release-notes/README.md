# Pending release notes

A pull request does not write into `Releases.md`. It adds **one file here**, holding its
entry exactly as it should read in `Releases.md`. The file names no version and no pull
request number: which release a change belongs to is decided when it is released, and the
number is added from the merge commit. Two pull requests never touch the same file, so
their release notes cannot conflict.

## The file

`release-notes/<short-name>.<section>.md` — lower case, the short name usually the branch's
topic. The section is the suffix:

| Suffix | Section in `Releases.md` |
| --- | --- |
| `.feature.md` | `### Features & Enhancements` |
| `.fix.md` | `### Bug Fixes & Improvements` |
| `.build.md` | `### Performance & Build System` |

The content is the entry as a list item, the same shape as the entries in `Releases.md`: a
bold title naming the affected modules or page paths, then the detail. No header and no
`***` line.

```markdown
- **The ESC current limit says where it came from (`app/pages/setup/power/preferences/page.lua`, `docs/pages/setup/power/preferences.md`)**:
  - The row label shows the family page that stored the limit, or that it was typed in by hand.
```

A pull request that changes `src/` and genuinely needs no release note says so in its body,
on a line of its own: `Release notes: none -- <the reason>`. The `Release notes rule` job in
`.github/workflows/pr.yml` checks that one of the two is there
(`bin/release/verify_release_notes_rule.py`).

## At release time

```
python bin/release/collect_release_notes.py --dry-run   # what would be filed
python bin/release/collect_release_notes.py             # file them, delete the files
```

The script files every pending note under the header of the version in
`src/rfsuite/lib/version.lua` — appended to that section if it exists, a new header at the top
if not — one `###` block per section, adds `(#N)` from the commit that merged the file, and
deletes the files it filed. Commit the result, then tag. A `release/*` or `snapshot/*` tag
whose tree still has pending notes stops before anything is built
(`collect_release_notes.py --require-empty`), so no note can be left out of a release in
silence.
