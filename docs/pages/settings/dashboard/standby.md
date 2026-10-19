---
title: Standby screen
sidebar_label: Standby screen
sidebar_position: 40
---

# Standby screen

The standby screen shows radio information in the dashboard while it waits for a flight controller. It is disabled by default.
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
| Position 1–8 | Chooses and orders positions 1 through 8, with up to eight items: clock, date, transmitter battery, selected EdgeTX model, model timers, transmitter GPS, radio uptime, firmware, or the optional ELRS summary. A dash or Remove deletes an item; Move up and Move down retain its size. |
| Size | Gives the selected item a small, wide, or full-row tile. The ELRS summary needs a wide or full row. |

Selecting ELRS for a new position starts it at Wide, the smallest supported size.

The Suite checks the selected locale, actual font metrics, bounded display formats, and full radio screen size before enabling a layout. If an item does not fit readably, its position, tile name, and the required correction appear directly below that item and in the Save error. A dashboard widget zone is validated again at its actual size. If the complete configured layout cannot fit there, the zone shows a localized fit prerequisite instead of hiding tiles or adding pages. Switching the standby screen off still saves; an invalid draft is discarded and the last valid saved layout is retained.
The initial layout contains Clock, TX battery, and Selected model. TX GPS is optional, is not part of the initial layout, and is read only when its tile is selected. Small shows fix state and satellite count. Wide and Full row additionally show latitude, longitude, altitude in metres, speed in metres per second, course in degrees, and HDOP normalized from EdgeTX's hundredths representation; an unavailable member remains `-`.

The screen reserves a fixed information strip for the highest-priority connection prerequisite. It derives this summary from the dashboard's existing connection state, while the exact connection reason and progress remain visible below it. The strip does not add another radio or telemetry probe.

## Notes

The transmitter battery uses the radio's battery minimum, maximum, and warning settings for both its text and filled battery symbol. TX GPS is the GPS built into the transmitter; *No fix* is a waiting state and does not describe the aircraft or prove that GPS hardware is present. EdgeTX does not expose whether GPS time has been received, and its radio clock does not prove GPS synchronization, so the tile reports the time status as unknown. The API also provides no reception timestamp, so the screen makes no freshness claim. A true GPS-time or receive-heartbeat indicator requires a future EdgeTX Lua API extension. Missing readings remain unavailable rather than becoming zero.

The optional ELRS tile reads the active transmitter module and never writes a parameter. It preserves the module's Packet Rate, Telemetry Ratio, Max Power, and Dynamic labels. Max Power is the configured ceiling, not the currently emitted RF power. The tile marks a completed snapshot with its read age; it starts a bounded refresh when the standby screen is entered again or the model/module identity changes. EdgeTX routes CRSF to the internal module when both internal and external CRSF modules are active.

Offline regressions cover configuration, source formatting, fit, and state routing. The final packaged screen and read timing on physical ELRS and internal-GPS hardware still require validation.

The existing connection reason and progress remain visible. Flight link loss and the postflight or offline summary keep their existing surfaces.

*Documented against RFSuite 0.2.1.*
