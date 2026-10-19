---
title: Standby screen
sidebar_label: Standby screen
sidebar_position: 40
---

# Standby screen

The standby screen shows radio information in the fullscreen dashboard while it waits for a flight controller. It is disabled by default.

## Where to find it

*System* → *Settings* → *Dashboard* → *Standby screen*

Always available.

## Settings

| Setting | What it does |
| --- | --- |
| Standby screen | Replaces the fullscreen connection splash before a flight controller is ready. The normal splash remains in widget zones. |
| Position 1–8 | Chooses and orders up to eight items: clock, date, transmitter battery, selected EdgeTX model, model timers, transmitter GPS, radio uptime, firmware, or the optional ELRS summary. A dash or Remove deletes an item; Move up and Move down retain its size. |
| Size | Gives the selected item a small, wide, or full-row tile. The ELRS summary needs a wide or full row. |

The Suite checks the selected locale, fonts, values, and radio screen size before saving. If all items do not fit readably on one screen, the edit is refused and the last valid saved screen remains active.
The initial layout contains Clock, TX battery, and Selected model.

## Notes

The transmitter battery uses the radio's battery minimum, maximum, and warning settings. TX GPS is the GPS built into the transmitter; *No fix* is a waiting state and does not describe the aircraft. Missing readings remain unavailable rather than becoming zero.

The existing connection reason and progress remain visible. Flight link loss and the postflight or offline summary keep their existing surfaces.

*Documented against RFSuite 0.1.x.*
