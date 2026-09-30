---
title: Urban theme
sidebar_label: Urban theme
---

# Urban theme

*Urban* is a dashboard theme that draws its own screen from code instead of a grid of boxes, and
takes full screen for itself. It is shipped as a worked example of two things a theme can do —
[take fullscreen](../developer/dashboard-themes.md#a-theme-that-takes-fullscreen) and declare
the telemetry it reads — and **it is a demonstration, not a finished theme**: the gaps it has
are listed at the end of this page.

## Where to find it

*System* → *Settings* → *Dashboard* → *Design*: choose *Urban* for a flight phase, or for all
three. Its settings are under *System* → *Settings* → *Dashboard* → *Settings* → *Urban*, split
into three pages: *Look*, *Value Rows* and *Top Bar*. The settings are stored per model where the
flight controller's id is known. Its words come from the suite's translations, like every other
theme's, so it speaks the language of the package that was installed.

## What it shows

**On the ground and in flight** one screen, which does not change shape at spool-up:

- **Top bar** — in full screen a menu button at the left, then the clock; up to four stacked
  link bars in the middle (the receiver's link quality *RQ*, the transmitter's *TQ*, and the
  signal of each receiver antenna as headroom above the sensitivity floor of the air rate the
  link runs, the second antenna only once one has been seen); the radio's battery at the right.
- **Left panel** — the model picture, the flight count and total flight time, the governor state
  and the throttle, a status line, and the PID, rate and battery profile numbers.
- **Middle** — a vertical battery gauge with the cell count, the fuel percentage and the capacity
  used. Until the model has reported a fuel reading the gauge is empty and reads `--%` rather
  than an empty pack.
- **Right panel** — five value rows, each chosen on the *Value Rows* page.
- **Bottom bar** — the model name, the arm state, the transmitter power and the skipped-frame
  count. While the flight controller names reasons that block arming, the whole bar shows them
  one at a time instead.

The **status line** says, worst news first: the main pack lost while the flight controller still
answers, the arming-disable reasons while disarmed, the speed controller's live verdict where the
controller reports one, and otherwise *No telemetry*, *Ready* or *Armed - OK*.

**After a flight** a statistics screen: the clock and the radio battery across the top, the model
with its totals, and a table of the last flight — cell voltage, headspeed on PID profiles 1 to 3,
current, ESC temperature, BEC voltage and voltage sags — each with the latest reading, the
flight's minimum and its maximum. Beneath it the flight time and the capacity used, and a bar
with the transmitter power, the lowest link quality, the highest MCU temperature and the
skipped frames. The header of the table says *Disconnected* once the flight controller has
stopped answering.

## Full screen

With *Urban* selected, full screen shows the theme itself rather than the quick menu. The menu
button in the top bar and the page keys open the [quick menu](quick-menu.md) over it. The theme
draws no close button: a **long press on RTN** leaves full screen, which the radio always
allows.

## Settings

| Page | Setting | What it does |
| --- | --- | --- |
| Look | Colour scheme | *Light* (default) or *Dark*. |
| Look | Arm state colours | *Green and red* (default): armed green, disarmed red. *Amber and grey*: armed amber, disarmed in the label colour. |
| Value Rows | Row 1 … Row 5 | The value each row of the right panel shows: cell voltage, voltage, headspeed, current, ESC temperature, MCU temperature, BEC voltage, power, throttle, fuel, capacity used, altitude, link quality, ESC load, ESC status, air rate, rate floor, or nothing. Defaults: cell voltage, headspeed, current, ESC temperature, BEC voltage. |
| Value Rows | Units beside the values | *Off* (default) gives the width to the figures. |
| Value Rows | Temperature colours | Colours the ESC and MCU temperature rows. *Off* (default); *Standard*: ESC amber from 90 °C and red from 110 °C, MCU from 75 °C and 90 °C; *Early*: each 10 °C lower. |
| Top Bar | Clock | *Time only* (default) or *Date and time*. |
| Top Bar | RQ bar, TQ bar, RSSI bars | Each link bar on or off. On by default. |
| Top Bar | Transmitter battery | The radio battery at the right end of the top bar. On by default. |
| Top Bar | Status bar: TPWR | The transmitter power in the bottom bar. On by default. |
| Top Bar | Colour the bars | *Always* (default) colours a good link green; *Only on warning* leaves it neutral until a bar drops to its warning step. |
| Top Bar | Link good above | Where the link-quality bars turn amber, 50 % to 90 %, default 80 %; they turn red thirty points lower. |
| Top Bar | Signal good above | Where the signal bars turn amber, 10 % to 25 % of the headroom, default 15 %; they turn red at half of it. |

The cell voltage row turns red below the minimum pack voltage the widget works out for the
model — the cell count times the flight controller's minimum cell voltage — and the gauge, the
voltage rows and the status line turn red while the main pack is lost.

## What it reads

Besides the fields every theme gets, the flight screen declares the transmitter's link quality
and power (`TQly`, `TPWR`), the air rate's sensitivity floor, whether a second antenna has been
seen, the skipped-frame count (`*Skp`) and the speed controller's live status, and whatever a
chosen value row needs (ESC load, ESC status, air rate, rate floor). The statistics screen
declares nothing and reads the flight record. A reading the model does not carry shows `-`.

The skipped-frame count is published by the suite itself under the name `*Skp`
(`tasks/events/telemetry_bg/drain.lua`, `setTelemetryValue(0xEE02, …, "*Skp")`), and `*Skp` is
the name the theme declares and reads. The `Skp` in `common.lua`'s label table is only the word
drawn beside the number; a bare `Skp` is declared nowhere on purpose, because nothing creates a
sensor of that name and a declared name that is absent is still searched for.

## What it does not do yet

- **Not priced by `bin/accounting/measure.lua`.** The instrument cannot settle a dashboard that
  draws a free-form theme, so the theme carries no budget row.
- **No colour for a pack that was not full when it was plugged in.** The gauge is green above
  20 %, yellow at 20 % and below and red at nothing left. Telling a part-used pack apart needs a
  verdict taken at the connect, and a theme has no pass of its own to take it in.
- **The transmitter power on the statistics bar is the last reading, not the flight's maximum**:
  the flight record keeps no transmitter power.
- **The arming-disable names cover bits 0 to 25**, named the same whatever MSP API version the
  flight controller runs.
- **Only the menu button takes a press.** The gauge, the value rows, the link bars and the status
  line open nothing.
- **A copy in the user folder draws with the shipped files**: its settings are its own, but its
  phase modules load `layout.lua` and `common.lua` from the shipped folder.
- The *Transmitter power*, *TQ* and skipped-frame cells read `-` on a link that does not report
  those sensors.

## Related

- [Dashboard themes](../developer/dashboard-themes.md) — the manifest keys, `fullscreen`,
  `sources` and the settings pages this theme uses.
- [Quick menu](quick-menu.md) — what opens over the theme in full screen.
- [User themes](user-themes.md) — copying a theme to the card.

*Documented against RFSuite 0.1.7.*
