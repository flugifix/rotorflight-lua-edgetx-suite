---
title: Quick menu
sidebar_label: Quick menu
---

# Quick menu

The screen the dashboard widget shows when it is put full screen: a short list of things a
pilot wants to reach from the flight line without leaving the dashboard for the tool.

## Where to find it

Put the *RFSuite* widget full screen the way EdgeTX puts any widget full screen — the widget's
own context menu on the screen it sits on, then *Full screen*. The quick menu is what full
screen shows; there is no other way in and no way for the widget to open it by itself.

The one exception is the [in-flight tuning overlay](inflight-tuning.md): while the interlock
switch has brought it up, it takes full screen instead and the quick menu is not drawn.

The menu's colours are the radio's, not the dashboard theme's. It uses the same theme colours
EdgeTX gives every script, so it looks the same whichever dashboard theme is selected.

## What it offers

| Entry | What it does |
| --- | --- |
| **ERASE BLACKBOX** | Erases the flight controller's blackbox storage, then reads the storage summary back so the dashboard shows the free space it has now. Closes the menu and leaves full screen. |
| **IN-FLIGHT TUNING** | Opens the in-flight tuning surface at full size. It stays full screen rather than closing. Only listed while the feature is switched on — see below. |
| **BATTERY PROFILE** | A grid of the model's battery profiles; pressing one makes it the profile in force. |

**IN-FLIGHT TUNING is a preview entry.** It appears only while *System* → *Settings* →
*General* → *Preview* → *In-flight tuning* is on **and** the widget is carrying the overlay's
state for this model. With the preview switch off the entry is not listed at all, so the menu
offers no route into a feature the widget has stopped driving. What the surface itself does is
in [in-flight tuning](inflight-tuning.md); the screen it opens sends nothing until the
interlock switch is thrown.

## The battery profile grid

One button per battery profile the flight controller carries a capacity for — profiles 1 to 6,
and a profile whose capacity is zero is left out rather than shown as an empty one. Each button
is labelled with that profile's capacity in mAh, and the profile the flight controller reports
is highlighted. Which one that is comes from the *BatP* telemetry sensor; a model that is not
sending it keeps the last profile that was read, and profile 1 until one has been read at all.

Pressing a capacity sets that battery profile on the flight controller and writes the setting
to the board's own storage, which is what makes the board apply the change and tell the rest of
the radio about it. The menu then closes and leaves full screen.

The grid is two buttons wide, one wide on a narrow widget zone, and three wide on a screen at
least 400 pixels across when there are more than four profiles, so all six still fit below the
entries above it. It stops at the bottom edge of the screen: a profile whose button would not
fit is not drawn.

## Closing it

The **X** in the header closes the menu and leaves full screen. So does every entry except
in-flight tuning, which swaps one full-screen surface for another. EdgeTX's own way out of full
screen — a long press on the return key — works as it does anywhere else.

## For contributors

The menu's content is a list rather than drawing code. `M.entries(widget)` in
`src/rfsuite/widgets/dashboard/fullscreen_menu.lua` returns it, and
`M.build(children, widget, entries)` draws whatever list it is given; with the third argument
omitted it draws `M.entries(widget)`, which is what the dashboard runtime asks for.

An entry carries the vocabulary `src/rfsuite/app/manifest.lua` already uses for the tool's own
menus:

| Key | What it says |
| --- | --- |
| `id` | The entry's name, for anything that has to refer to it. |
| `title` | The text on the row, already translated. |
| `kind` | `action` for a single button, `choice` for a title over a grid of options. |
| `visibleWhen` | The name of a condition that decides whether the row exists at all. Omitted, the row is always there. |
| `press` | What an `action` does when it is pressed. |
| `options` | For a `choice`: a list, or a function of the widget returning one, of `{ label, current, press }`. The battery-profile grid is this and nothing else. |

Two things are worth knowing before adding an entry:

- **A title is resolved in `entries()`, from a complete literal key.** The translation
  precompiler rewrites the keys it can read and leaves alone the ones it cannot, so a key
  assembled from parts ships the English fallback in every language with nothing reporting it.
- **A `visibleWhen` name is resolved in the same file, and an unknown name hides its row** —
  the same way an unresolvable condition hides a tool menu entry in
  `src/rfsuite/app/menu_registry.lua`. `enabledWhen`, `lockedWhileArmed` and `confirm` belong
  to the same vocabulary and no entry uses one yet, so the first entry that needs one brings
  its resolver with it.

## Related

- [In-flight tuning overlay](inflight-tuning.md) — the other surface full screen can show.
- [Rotorflight documentation](https://www.rotorflight.org/docs/) — battery profiles and the
  blackbox themselves: what a profile holds, and what the flight controller records.

*Documented against RFSuite 0.1.7.*
