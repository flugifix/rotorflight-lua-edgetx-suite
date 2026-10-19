---
title: Standby screen
sidebar_label: Standby screen
sidebar_position: 40
---

# Standby screen

The standby screen shows radio information in the fullscreen dashboard while it waits for a flight controller. It is disabled by default.
The dashboard loads this surface only while it is shown and releases its scene, cached readings,
and module reference when the surface closes.

## Where to find it

*System* → *Settings* → *Dashboard* → *Standby screen*

Always available.

## Settings

| Setting | What it does |
| --- | --- |
| Standby screen | Replaces the fullscreen connection splash before a flight controller is ready. The normal splash remains in widget zones. |
| Position 1–8 | Chooses and orders positions 1 through 8, with up to eight items: clock, date, transmitter battery, selected EdgeTX model, model timers, transmitter GPS, radio uptime, firmware, or the optional ELRS summary. A dash or Remove deletes an item; Move up and Move down retain its size. |
| Size | Gives the selected item a small, wide, or full-row tile. The ELRS summary needs a wide or full row. |

Selecting ELRS for a new position starts it at Wide, the smallest supported size.

The Suite checks the selected locale, actual font metrics, bounded display formats, and radio screen size before enabling a layout. If all items do not fit readably on one screen, the layout cannot be enabled. Switching the standby screen off still saves; an invalid draft is discarded and the last valid saved layout is retained.
The initial layout contains Clock, TX battery, and Selected model. TX GPS is optional, is not part of the initial layout, and is read only when its tile is selected.

The screen reserves a fixed information strip for the highest-priority connection prerequisite. It derives this summary from the dashboard's existing connection state, while the exact connection reason and progress remain visible below it. The strip does not add another radio or telemetry probe.

## Notes

The transmitter battery uses the radio's battery minimum, maximum, and warning settings for both its text and filled battery symbol. TX GPS is the GPS built into the transmitter; *No fix* is a waiting state and does not describe the aircraft. The API provides no reception timestamp, so the screen makes no freshness claim. Missing readings remain unavailable rather than becoming zero.

The optional ELRS tile reads the active transmitter module and never writes a parameter. It preserves the module's Packet Rate, Telemetry Ratio, Max Power, and Dynamic labels. Max Power is the configured ceiling, not the currently emitted RF power. The tile marks a completed snapshot with its read age; it starts a bounded refresh when the standby screen is entered again or the model/module identity changes. EdgeTX routes CRSF to the internal module when both internal and external CRSF modules are active.

Offline regressions cover configuration, source formatting, fit, and state routing. The final packaged screen and read timing on physical ELRS and internal-GPS hardware still require validation.

The existing connection reason and progress remain visible. Flight link loss and the postflight or offline summary keep their existing surfaces.

*Documented against RFSuite 0.2.1.*
