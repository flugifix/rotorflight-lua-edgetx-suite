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

A dashboard theme can take full screen for itself instead (a theme author's choice, see
[dashboard themes](../developer/dashboard-themes.md#a-theme-that-takes-fullscreen)). Full screen
then shows the theme, and the quick menu opens over it from the theme's menu control or with
the page keys.

One exception is the [in-flight tuning overlay](inflight-tuning.md): while the interlock
switch has brought it up, it takes full screen instead and the quick menu is not drawn.

The other is the battery prompt. With *Ask which pack after connecting* on (the
[Flight Log](../pages/tools/flight_log.md) page, *Settings*), full screen shows the battery
picker instead of the quick menu once per connection, until the pilot has picked a pack,
closed it or armed the model.

The menu's colours are the radio's, not the dashboard theme's. It uses the same theme colours
EdgeTX gives every script, so it looks the same whichever dashboard theme is selected.

## What it offers

| Entry | What it does |
| --- | --- |
| **ERASE BLACKBOX** | Erases the flight controller's blackbox storage, then reads the storage summary back so the dashboard shows the free space it has now. Closes the menu and leaves full screen (over a theme that takes full screen: closes the menu and shows the theme again). |
| **IN-FLIGHT TUNING** | Opens the in-flight tuning surface at full size. It stays full screen rather than closing. Only listed while the feature is switched on — see below. |
| **BATTERY** | Brings the battery prompt back, with this model's packs. It stays full screen, the picker taking the menu's place. Only listed while the battery registry has a pack for this model and the model is disarmed. |
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
the radio about it. The menu then closes and leaves full screen, or, over a theme that takes
full screen, shows the theme again.

The grid is two buttons wide, one wide on a narrow widget zone, and three wide on a screen at
least 400 pixels across when there are more than four profiles, so all six still fit below the
entries above it. It stops at the bottom edge of the screen: a profile whose button would not
fit is not drawn.

## Closing it

The **X** in the header closes the menu and leaves full screen. So does every entry except
in-flight tuning and BATTERY, which swap one full-screen surface for another. The battery
picker's packs, *NO BATTERY* and its own X leave full screen as well, and the next entry into
full screen shows the quick menu, with BATTERY to bring the picker back. EdgeTX's own way out of
full screen — a long press on the return key — works as it does anywhere else.

Over a theme that takes full screen, the same X, entries and picker answers close what is open
and show the theme again instead; the theme's own close control, or a long press on the return
key, leaves full screen. On a radio with page keys, PAGE opens and closes the menu there, and a
short press on the return key closes the menu or the picker.

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
| `view` | For a `choice` whose options are drawn by a view of their own: that view's id. The menu then draws the row as the single button that opens it (its `after`), and the view draws the options. |
| `visibleWhen` | The name of a condition that decides whether the row exists at all. Omitted, the row is always there. |
| `press` | The work an `action` does when it is pressed, and nothing else. Optional: a row whose whole effect is its `after` has none. |
| `after` | What follows the press, as data: `done`, `openView:<id>`, `closeView`, `exitFullscreen` or `none`. Missing means `none`. The actions are described in [dashboard views](../developer/dashboard-views.md). |
| `options` | For a `choice`: a list, or a function returning one, of `{ id, label, current, press, after }`. `id` is what a run is matched by: a battery profile's number, 1 to 6, and a pack's registry id. The battery-profile grid is one, and the battery picker's packs are the other. |
| `close` | Optional, `{ press, after }`: what closing the surface that draws the options does. |
| `info` | Optional, a function returning what the entry knows about the state it acts on, read when it is called. ERASE BLACKBOX has one: `{ used, total }` of the blackbox, from the summary the flight controller last sent. |

`M.entry(widget, id)` returns one entry of the list, building that one only, and `M.run(widget, entry, option, after,
report)` runs it: the work — the option's `press` when an option is given, else the entry's —
and then its `after`, or the `after` given in its place. It is the one place both happen, for
the menu's own buttons, the picker's and a theme's. `report` is handed to the work: an entry
that sends messages to the flight controller queues them as one chain and reports on the chain
through it (`"busy"`, then `"ok"` on the last message's reply or `"failed"` on any message's
error). The menu's own buttons pass none, so what they queue is what they always queued.

**Menus are lists of entry ids.** `M.LISTS` names them — `quick` is `erase_blackbox`,
`inflight_tuning`, `battery_pick`, `battery_profile`, which is what the quick menu draws — and
`M.list(widget, name)` returns the entries of one. `M.resolve(widget, entry, option)` finds
the menu's own record and option for what a caller hands in, by `id`, and
`M.coreList(widget, list)` the records for a list of them. A theme reaches the same records
through its `ctx` and may draw them its own way, but it adds none and changes none: see
[dashboard themes](../developer/dashboard-themes.md#the-theme-draws-the-widget-acts).

**BATTERY is the battery prompt's record.** `battery_pick` is a `choice` with `view =
"battery_pick"`: in the menu it is the BATTERY button, and the battery picker
(`widgets/dashboard/battery_pick_menu.lua`) is the view that draws its options. They are one per
pack this model has — `label` the pack's name, `detail` the capacity and profile line under it,
`pack` the registry entry, `id` its registry id, `current` for the pack picked this connection
— and a last one marked `none`, *NO BATTERY*. Each records the pick and is followed by `done`. Its `close` ends the
prompt for this connection, which is what the picker's X and a short press on RTN do. What a
pick does is therefore written in one place, the record; the picker is only its drawing.
`options()` needs no argument: the widget is the one the list was made for.

Two things are worth knowing before adding an entry:

- **A title is resolved in `entries()`, from a complete literal key.** The translation
  precompiler rewrites the keys it can read and leaves alone the ones it cannot, so a key
  assembled from parts ships the English fallback in every language with nothing reporting it.
- **A `visibleWhen` name is resolved in `src/rfsuite/widgets/dashboard/views.lua`, and an
  unknown name hides its row** — the same way an unresolvable condition hides a tool menu entry
  in `src/rfsuite/app/menu_registry.lua`. It is the same list a fullscreen view's `openWhen`
  is resolved against. `enabledWhen`, `lockedWhileArmed` and `confirm` belong
  to the same vocabulary and no entry uses one yet, so the first entry that needs one brings
  its resolver with it.

## Related

- [In-flight tuning overlay](inflight-tuning.md) — another surface full screen can show.
- [Flight Log](../pages/tools/flight_log.md) — the battery prompt, and the battery registry it
  offers.
- [Rotorflight documentation](https://www.rotorflight.org/docs/) — battery profiles and the
  blackbox themselves: what a profile holds, and what the flight controller records.

*Documented against RFSuite 0.1.7.*
