# Documentation Maintenance Rule

## Mandatory Workflow Requirement
Whenever changes are made to the codebase that a pilot can observe (a new configuration page, a new or removed setting, changed behaviour, a new widget or dashboard theme option, a new audio announcement, or a removed feature) and a Pull Request is prepared, the documentation under `docs/` is updated in the same PR. A PR that changes `src/` and no file under `docs/` says why in its body, on a line of its own beginning with `Documentation:`; the `Documentation rule` job in `.github/workflows/pr.yml` reads that line.

The rule in full -- which file, the page template, the hiding and locking conditions, and keeping `help.lua` consistent -- is in `CONTRIBUTING.md` under *Documentation*. Read it before writing the page.
