---
title: Failsafe
sidebar_label: Failsafe
sidebar_position: 30
---

# Failsafe

Configure each receiver channel's fallback mode and value for loss of RC signal.
The page lists as many channels as the flight controller's receiver delivers: 16 on
CRSF/ELRS, up to 18 otherwise.

## Where to find it

*Configuration* → *Setup* → *Controls* → *Failsafe*

Read-only while the model is armed.

## Settings

Each channel row has a Mode selector followed by a Value field. Rows appear in this order:
Roll, Pitch, Yaw, Collective, Throttle, then the available AUX channels (AUX 1 to AUX 13).

| Setting | What it does |
| --- | --- |
| Mode | *Auto* uses the firmware's failsafe center for Roll, Pitch, Yaw and Collective, its failsafe throttle value for Throttle, and the last good value for AUX channels. *Hold* keeps the channel's last good value. *Set* uses the configured Value. |
| Value | The channel value used in *Set* mode, 875 to 2125 µs in steps of 5 µs; editable only when *Set* is selected. |

## Notes

- Save writes each edited channel separately through the shared save pipeline.
- Reload discards unsaved edits and reads the channels again; rows above the reported channel
  count are removed.

## Related

- [Rotorflight Failsafe](https://doc.rotorflight.org/configurator/tabs/failsafe/)

*Documented against RFSuite 0.2.1.*
