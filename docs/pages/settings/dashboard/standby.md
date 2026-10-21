---
title: Standby screen
sidebar_label: Standby screen
sidebar_position: 40
---

# Standby screen

The standby screen arranges radio information in equal-width fields and rows while the dashboard waits for a flight controller. It is disabled by default.
Where the zone height allows, its header contains the logo; fullscreen mode also includes the Suite control. Zones below 160 pixels omit the logo and header and use a compact information footer. Below 90 pixels, only the localized fit prerequisite remains. There is no separate Standby title.
The dashboard loads this surface only while it is shown and releases its scene, cached readings,
and module reference when the surface closes.

## Where to find it

*System* → *Settings* → *Dashboard* → *Standby screen*

Always available.

## Settings

| Setting | What it does |
| --- | --- |
| Standby screen | Replaces the connection splash before a flight controller is ready, both in fullscreen mode and in dashboard widget zones. Only fullscreen mode includes the Suite control. |
| Row 1, Row 2, … | Groups the fields that share one horizontal row. The radio's screen determines how many rows fit. |
| Field 1, Field 2, … | Chooses a module for that field: clock, date, transmitter battery, selected EdgeTX model, a model timer, transmitter GPS, radio uptime, firmware, or the ELRS configuration. The list contains only modules that fit when every filled field shares the row equally. |
| + Field | Adds an equal-width field to this row. It appears only when the existing choices and every module offered for the new field fit at the resulting width. |
| Remove field | Removes that field. The fields that remain share the whole row equally, without a stored gap. |
| + Row | Adds a row while the radio screen has room for another one. |
| Remove row | Removes the complete row. |

There is no size selector and no move control. Change the row and field structure instead. The Suite filters each list with the selected locale, the radio's own font measurements, bounded display formats, and the screen geometry. A saved token that is no longer supported is skipped while the remaining valid rows are kept, and the page shows a warning. Saving an enabled layout with no row, or with a field that no longer fits, is refused. Switching the standby screen off still saves and retains the last valid saved layout.

Until a layout is saved, a screen narrower than 700 pixels uses Clock plus TX battery in row 1 and ELRS across row 2. A screen at least 700 pixels wide, such as 800x480, uses Clock, TX battery and the selected model in row 1 and ELRS across row 2, leaving row 3 free. On the dashboard the default follows the width of the zone the standby screen is drawn in, so a narrower widget zone on a wide radio keeps the two-field first row. The default ELRS row stays on a radio without an ELRS module and then reads *No ELRS module* (no CRSF module, a CRSF module that is not ELRS, or no answer to the discovery requests); a module that answers but returns none of the four settings reads *Unavailable*. Replace the row with another module to use the space.

A smaller dashboard zone draws only the leading complete rows that fit. Trailing saved rows are retained and return when the widget is placed in a taller zone. The standby screen does not add paging or scrolling.

TX GPS is optional, is read only when its field is selected, and adapts to the available width without a size setting. Compact fields show fix state and satellite count. Where the field can carry the detailed presentation, it also shows latitude, longitude, altitude in metres, speed in metres per second, course in degrees, and HDOP normalized from EdgeTX's hundredths representation; an unavailable member remains `-`.

The screen reserves a fixed information strip for the highest-priority connection prerequisite. It derives this summary from the dashboard's existing connection state, while the exact connection reason and progress remain visible below it. The strip does not add another radio or telemetry probe.

## Notes

The transmitter battery uses the radio's battery minimum, maximum, and warning settings for both its text and filled battery symbol. TX GPS is the GPS built into the transmitter; *No fix* is a waiting state and does not describe the aircraft or prove that GPS hardware is present. EdgeTX does not expose whether GPS time has been received, and its radio clock does not prove GPS synchronization, so the tile reports the time status as unknown. The API also provides no reception timestamp, so the screen makes no freshness claim. A true GPS-time or receive-heartbeat indicator requires a future EdgeTX Lua API extension. Missing readings remain unavailable rather than becoming zero.

The ELRS field reads the active transmitter module and never writes a parameter. On every supported radio it uses two compact value lines, `Rate … | TLM …` and `Max … | Dyn …`, followed by the read age. These preserve the configured Packet Rate, Telemetry Ratio, Max Power, and Dynamic values without showing the module name. Max Power is the configured ceiling, not the currently emitted RF power. Dynamic remains the exact configured label: *Off*, *Dyn*, or *AUX9* through *AUX12* when that choice is available. The field starts a bounded refresh when the standby screen is entered again or the model/module identity changes. EdgeTX routes CRSF to the internal module when both internal and external CRSF modules are active.

Offline regressions cover configuration, source formatting, fit, and state routing. The final packaged screen and read timing on physical ELRS and internal-GPS hardware still require validation.

The existing connection reason and progress remain visible. Flight link loss and the postflight or offline summary keep their existing surfaces.

*Documented against RFSuite 0.2.1.*
