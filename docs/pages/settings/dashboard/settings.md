---
title: Settings
sidebar_label: Settings
sidebar_position: 20
---

# Settings

The settings the dashboard themes themselves offer. The page is a grid of tiles, one per theme
that has settings, and a tile opens that theme's own page — the battery bounds it draws its
gauges against, the values it puts in its rows, the colours it uses. Nothing here is a setting
of the suite: what a tile opens is written by the theme, so two radios with different themes
installed see different pages.

Which theme a model actually shows is chosen on *Design*, and a theme keeps its settings
whether or not it is the one in use.

## Where to find it

*System* → *Settings* → *Dashboard* → *Settings*

Always available. A theme appears here when it ships a settings module and does not declare
itself standalone; a theme with neither is configured nowhere, and one whose module offers
nothing opens a page saying so.

## Settings

| Setting | What it does |
| --- | --- |
| *(one tile per theme)* | Opens that theme's settings. What the page holds is the theme's own business; several of the shipped themes offer the battery voltage bounds their gauges are scaled to. |

A theme may split its settings into pages. Its tile then opens a second grid, one tile per
page, and each of those opens part of the theme's settings — the same settings, divided so a
page fits the screen. Themes that do not split show their settings directly.

## Notes

- Settings are stored per theme, so a theme copied into
  `/SCRIPTS/TOOLS/rfsuite.user/dashboard/` starts from its defaults rather than inheriting the
  original's values, and configuring the copy does not change the original.
- Where the flight controller has been read, the values are stored for that model; where it has
  not, they are stored for the radio and are what a model with none of its own falls back to.
- A theme split into pages saves the page that is open. Leaving a page for another one of the
  same theme discards what has not been saved, so save before stepping across.
- Saving reloads the dashboard, so a change is visible on the widget as soon as the tool is
  closed.

## Related

- [Dashboard themes](../../../dashboard/README.md) — what the widget shows and which themes ship
  with the suite.
- [User themes](../../../dashboard/user-themes.md) — copying a theme onto the card and editing
  it, including the settings a copy carries.

*Documented against RFSuite 0.1.7.*
