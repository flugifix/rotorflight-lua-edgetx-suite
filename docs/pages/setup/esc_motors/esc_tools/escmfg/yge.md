---
title: YGE Configurator
sidebar_label: YGE
sidebar_position: 90
---

# YGE Configurator

Reads the parameter block out of a YGE ESC and writes it back, so the ESC can be set up from
the radio instead of from a computer. The page opens on the ESC's own model name, firmware and
version, and offers its settings in three groups.

## Where to find it

*Configuration* → *Setup* → *ESC & Motors* → *ESC Tools* → *YGE*

Lit only while the flight controller reports this ESC telemetry protocol. Read-only while the
model is armed.

## Settings

The page opens on a summary of the ESC's firmware and version. *Section* switches between three
groups of settings.

| Setting | What it does |
| --- | --- |
| Section | *Basic*, *Advanced* or *Other*. Switching it rebuilds the list below; nothing is read from the ESC again. |

### Basic

| Setting | What it does |
| --- | --- |
| Governor Mode | The ESC's operating mode: *Mode Free*, *Mode Ext*, *Mode Heli*, *Mode Store*, *Mode Glider*, *Mode Air* or *Mode F3A*. |
| Direction | Which way the motor turns, *Normal* or *Reverse*. |
| BEC Voltage | The BEC output, 5.5 V to 8.4 V in 0.1 V steps. On an ESC model that has a 12 V BEC the range runs to 12.0 V, and setting exactly 12.0 V is what turns that BEC on. |
| Auto Restart Type | What the ESC does after a cutoff: *Off*, *Slowdown* or *Cutoff*. |
| Cell Cutoff | The per-cell voltage the ESC cuts at, 2.9 V to 3.4 V. |
| Current Limit | The ESC's current limit, 0.01 A to 655.00 A, adjusted in 1 A steps. |
| F3C Auto | The F3C autorotation setting, *Off* or *On*. |
| Keep mAh | Whether the ESC keeps its consumed-capacity count across a power cycle, *Off* or *On*. |

### Advanced

| Setting | What it does |
| --- | --- |
| Min Start Power | Lower bound of the startup power, 0 % to 26 %. |
| Max Start Power | Upper bound of the startup power, 0 % to 31 %. |
| Startup Response | How hard the ESC comes up, *Normal* or *Smooth*. |
| Throttle Response | *Slow*, *Medium*, *Fast* or *Custom*, the last being the curve set from the ESC's own PC tool. |
| Motor Timing | Commutation timing. Four automatic modes -- *Auto Normal*, *Auto Efficient*, *Auto Power*, *Auto Extreme* -- and six fixed advance angles, *0 deg* to *30 deg* in six-degree steps. |
| Active Freewheel | *Off*, *Auto*, *Unused* or *Always On*. |

### Other

| Setting | What it does |
| --- | --- |
| Governor P Gain | 1 to 10. |
| Governor I Gain | 1 to 10. |
| Motor Pole Pairs | Pole pairs of the motor, 1 to 100. |
| Main Gear Teeth | 1 to 1800. |
| Pinion Teeth | 1 to 255. |
| Stick Zero | Throttle pulse width the ESC reads as zero, 900 us to 1900 us in 10 us steps. |
| Stick Range | Pulse width span from zero to full throttle, 600 us to 1500 us in 10 us steps. |

## Notes

- The page opens behind a safety notice asking for the main and tail blades to be removed. The
  ESC is not read until it is dismissed.
- Saving writes the whole parameter block to the ESC, not only the settings that were changed.
  Every setting the page offers is written back as it was read unless it was edited. The one
  exception is the flags byte, which the page rebuilds from the four switches it carries
  (*Direction*, *F3C Auto*, *Keep mAh* and the 12 V BEC): any other bit the ESC keeps in that
  byte is written back as zero, even by a Save that edited nothing.
- The ESC is read when the page opens. Switching *Section* does not read it again.
- An unsaved edit is marked below the list, and is lost if the page is left without saving.

## Related

- [YGE](https://www.yge.de/) -- the manufacturer's own documentation for what each of these
  settings does inside the ESC, and which of them a given firmware has.
- [Rotorflight documentation](https://www.rotorflight.org/docs/)

*Documented against RFSuite 0.1.7.*
