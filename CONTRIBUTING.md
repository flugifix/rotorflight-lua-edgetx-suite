# Contributing

This file holds the rules every pull request to this repository follows, for people and for
coding agents alike. How to set up the workspace, build and test is in
[DEVELOPMENT.md](DEVELOPMENT.md); the conventions the sources follow — module loading, UI
helpers, logging, memory handling, the dashboard's reactive closures and i18n — are in
[GEMINI.md](GEMINI.md).

A pull request that changes what a pilot can observe carries three things besides the code:
**a release note**, **its documentation**, and **every string through i18n**. Each one is
checked, or asked for, by a job in `.github/workflows/pr.yml`.


## Release notes (`Releases.md`)

- **Mandatory:** with every feature, enhancement, bug fix, UI change, performance
  optimization or build-system change, `Releases.md` is kept up to date, and the updated file
  is committed as part of the pull request so the release notes stay in sync with master at all
  times.
- Record the change under the active / upcoming release header (e.g. `# 0.2.x`), in one of the
  sections `Features & Enhancements`, `Bug Fixes & Improvements` and
  `Performance & Build System`.
- Reference the affected module or page path in parentheses (e.g. `(setup/esc_motors/esc_tools)`),
  and keep the description concise and accurate: what changed, its technical impact, and the
  issue or pull request it belongs to where there is one.


## Documentation (`docs/`)

- **Mandatory:** with every new page, new or removed setting, changed behaviour a pilot can
  observe, new widget or theme option, new audio announcement, or removed feature, the
  documentation under `docs/` is kept up to date in the same pull request.
- Update the file of the page that changed: `docs/pages/<page path>.md`, mirroring the path of
  the page under `src/rfsuite/app/pages/`. A surface that is not a page (the dashboard widget, an
  announcement, the user folder) has its file under `docs/dashboard/`, `docs/audio/` or
  `docs/reference/`. When a page is added or removed, update the index `docs/pages/README.md`
  too.
- Follow [docs/_template.md](docs/_template.md): what the page does, where to find it (the menu
  path, and the conditions under which it is hidden, greyed out or read-only), one line per
  setting, related flight-controller documentation, and the release the page was checked
  against. Record the hiding and locking conditions exactly as the manifest declares them
  (`enabledWhen`, `visibleWhen`, `lockedWhileArmed`, `minApiVersion`, `hideWhenDisabled`).
- Keep the page file and the page's `help.lua` consistent. `help.lua` is the short explanation
  behind the `?` button and the page file is the full one; they must not contradict each other,
  and a change that affects one is applied to both.
- **A pull request that needs no documentation change says so.** If it changes `src/` and no file
  under `docs/`, its body carries a line of its own beginning with `Documentation:` (a bullet and
  bold markers are allowed) and the reason, for example
  `Documentation: no page -- this only renames a local variable.`
  The `Documentation rule` job reads that line (`bin/docs/verify_documentation_rule.py`); it does
  not judge the reason, it only makes sure the rule cannot be skipped in silence.


## Strings and i18n

Every string a pilot reads goes through i18n; a hard-coded English label is a defect, because it
shows in English in every locale. The call forms, why a key has to be a string literal, and the
CI gate behind it are in [docs/developer/i18n.md](docs/developer/i18n.md); the conventions are
in [GEMINI.md](GEMINI.md) under *Localization (i18n)*.


## The checks a pull request runs

The jobs in `.github/workflows/pr.yml` build both locale archives and run the instruction
budget, the i18n precompiler and resolver tests, the translation-coverage report, the erase
confirmation and the documentation rule. [DEVELOPMENT.md](DEVELOPMENT.md) under
*Continuous integration* lists what each one checks. A pull request is ready for review when
they are green.
