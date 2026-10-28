---
title: Advanced
sidebar_label: Advanced
sidebar_position: 10
---

# Advanced

Sets the stick-response dynamics in the active rate profile, whose number appears in the Dynamics heading. These settings apply regardless of the rate system.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Rates (Advanced)* → *Advanced*

Read-only while the model is armed.

## Settings

| Setting | What it does |
| --- | --- |
| Response Time | Smooths stick inputs for Roll, Pitch, Yaw and Collective. Larger values add smoothing but can delay the response. Range: 0 to 250 ms. |
| Accelerometer Limit | Limits acceleration for Roll, Pitch, Yaw and Collective; this is a rate-response setting, not an accelerometer setting. Displayed range: 0 to 50000. |
| Setpoint boost gain | Boosts stick inputs for a snappier response on each axis; zero disables the boost. Range: 0 to 250. Shown from MSP API 12.08. |
| Setpoint boost cutoff | Controls how quickly the boost decays on each axis; higher values shorten the boost. Range: 0 to 250 Hz. Shown from MSP API 12.08. |
| Dynamic ceiling gain | Reduces the stick travel needed to reach the maximum yaw setpoint when rapidly approaching full stick. Range: 0 to 250, Yaw only. Shown from MSP API 12.08. |
| Dynamic deadband gain | Enlarges the yaw deadband when rapidly returning to center, helping produce a more precise stop. Range: 0 to 250, Yaw only. Shown from MSP API 12.08. |
| Dynamic deadband filter | Sets the dynamic yaw deadband filter frequency. Range: 0 to 25.0 Hz, Yaw only. Shown from MSP API 12.08. |

## Saving

Save writes the whole active rate profile, commits it once to EEPROM, and reports success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the profile without a reboot.

## Related

- [Rotorflight documentation: Rates dynamics](https://doc.rotorflight.org/configurator/tabs/rates/#dynamics)
- [Rotorflight documentation: Profiles](https://doc.rotorflight.org/configurator/tabs/profiles/)

*Documented against RFSuite 0.2.1.*
