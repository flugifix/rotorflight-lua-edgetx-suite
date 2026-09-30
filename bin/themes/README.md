# Theme checks

`validate.lua` checks a dashboard theme that takes fullscreen (`fullscreen = "theme"` in its
`init.lua`) for the duties [dashboard themes](../../docs/developer/dashboard-themes.md#a-theme-that-takes-fullscreen)
gives it. It runs offline, with desktop Lua 5.3, from the repository root:

```sh
lua5.3 bin/themes/validate.lua <theme folder>
lua5.3 bin/themes/validate.lua <theme folder> --size 480x272
```

The folder is a theme folder anywhere on disk — a shipped one under
`src/rfsuite/widgets/dashboard/themes/`, or a user theme copied off the card. The size is the
fullscreen size the theme is built at, `800x480` when omitted.

## What it does

Each phase module the theme declares is resolved the way the widget resolves it (`armed` falls
back to `preflight`, `offline` to `postflight`, a phase with no module to `widget.lua`), and each
distinct module is built once at the fullscreen size with a `ctx` that records what it is asked
to do. Every `press` in the tree the build returns is then fired, and `ctx.keys` is read once
the build and the presses have run.

A theme is **red** where:

| Finding | Why it matters |
| --- | --- |
| no press opens the quick menu (`openView:menu`, or a menu built through `ctx.menu`) | the menu is where ERASE BLACKBOX, BATTERY and the battery profiles are, and a touch radio has no other way to it |
| nothing leaves fullscreen | a way out is a press with `exitFullscreen`, or `ctx.keys.exit = "exitFullscreen"` — a short press on RTN, which every radio has — or `fullscreenExit = "longRtn"` declared in `init.lua`: the author relies on a long press on RTN, which always leaves fullscreen |
| a `rectangle` is drawn over a node that has a press | built in fullscreen, a rectangle takes the press and hands it to its parent, so it swallows every press that lands on it |
| a press or a `ctx.keys` entry names an unknown action or view | the widget ignores it, so the control or the key does nothing |
| a build raises or does not return a node list | |

A tree that binds no press at all is green, because the widget then draws its own menu control
and X over it, and so is a declarative theme, which cannot bind one. A theme without the
`fullscreen` key is not checked.

Exit status: `0` green, `1` red — one line per finding, beginning `RED:` — and `2` when the theme
cannot be read.

## What it does not do

It does not look at the picture, and it does not measure cost: that is
`bin/accounting/measure.lua`. The firmware and the widget are stubbed in the file itself; the
state a build receives is a fixture of typical readings, so a theme that reads anything else sees
`nil`, as it may on a radio before the first telemetry arrives. It is not part of the CI
workflow.
