---
title: Autolevel
sidebar_label: Autolevel
sidebar_position: 40
---

# Autolevel

Sets the gains and angle limits for Acro trainer, Angle mode and Horizon mode in the active PID profile, whose number appears in the page title. Acro trainer limits tilt without self-leveling; Angle and Horizon provide leveling.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Autolevel*

Read-only while the model is armed.

## Settings

| Setting | What it does |
| --- | --- |
| Acro trainer: Gain | How strongly the helicopter returns to the maximum roll or pitch angle when it exceeds that limit in TRAINER mode. Range: 25 to 255. |
| Acro trainer: Max | Maximum roll or pitch angle in TRAINER mode; this mode does not self-level. Range: 10 to 80°. |
| Angle mode: Gain | How strongly the helicopter returns to level in ANGLE mode. Range: 0 to 200. |
| Angle mode: Max | Maximum roll or pitch angle in ANGLE mode. Range: 10 to 90°. |
| Horizon mode: Gain | How strongly the helicopter returns to level in HORIZON mode. Range: 0 to 200. |

## Saving

Save writes the whole active PID profile, commits it once to EEPROM, and reports success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the profile without a reboot.

## Related

- [Rotorflight documentation: Auto Leveling Settings](https://doc.rotorflight.org/configurator/tabs/profiles/#auto-leveling-settings)

*Documented against RFSuite 0.2.1.*
