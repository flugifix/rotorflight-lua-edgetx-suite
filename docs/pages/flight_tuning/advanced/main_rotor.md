---
title: Main Rotor
sidebar_label: Main Rotor
sidebar_position: 50
---

# Main Rotor

Sets collective-to-pitch compensation and cyclic cross-coupling compensation in the active PID profile, whose number appears in the page title.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Main Rotor*

Read-only while the model is armed.

## Settings

| Setting | What it does |
| --- | --- |
| Col. Pitch Comp | Compensates the nose-up tendency during collective pitch pumps by mixing collective into elevator control. Range: 0 to 250. |
| Cyclic Cross coupling: Gain | Amount of pitch-to-roll compensation, used to remove roll wobble when only elevator is applied. Range: 0 to 250. |
| Ratio | Amount of roll-to-pitch compensation relative to pitch-to-roll compensation. Range: 0 to 200 %. |
| Cutoff | Frequency limit for cross-coupling compensation; higher values make the compensation act faster. Range: 0.0 to 25.0 Hz. |

## Saving

Save writes the whole active PID profile, commits it once to EEPROM, and reports success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the profile without a reboot.

## Related

- [Rotorflight documentation: Main Rotor Settings](https://doc.rotorflight.org/configurator/tabs/profiles/#main-rotor-settings)

*Documented against RFSuite 0.2.1.*
