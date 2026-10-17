# Releases.md Maintenance Rule

## Mandatory Workflow Requirement
Whenever changes are made to the codebase (features, enhancements, bug fixes, UI adjustments, performance optimizations, or build system changes) and a Pull Request is prepared:
1. **Always add a release note as one new file under `release-notes/`** — do not edit `Releases.md`:
   - Name it `release-notes/<short-name>.<section>.md`; the section is `feature` (`Features & Enhancements`), `fix` (`Bug Fixes & Improvements`) or `build` (`Performance & Build System`).
   - Write the entry as a list item exactly as it should read in `Releases.md`, with no header and no `***` line.
   - Reference the affected module / page path in parentheses (e.g. `(`setup/esc_motors/esc_tools`)`).
   - Ensure the description is concise, accurate, and highlights the technical impact and issue references where applicable. Do not write a version or the PR's own number: the release is decided when it is cut, and the number is added from the merge commit.
2. **Include the release note in the PR**:
   - The file must be committed as part of the PR. If a change genuinely needs no release note, say so in the PR body on a line of its own beginning with `Release notes:`; the `Release notes rule` job in `.github/workflows/pr.yml` reads that line.
3. The rule in full -- where the entry goes, its sections and what it names -- is in `CONTRIBUTING.md` under *Release notes*. Read it before writing the entry.
4. **At release time** `python bin/release/collect_release_notes.py` files the pending notes under the version in `src/rfsuite/lib/version.lua`. The format and the release flow are in `release-notes/README.md`.
