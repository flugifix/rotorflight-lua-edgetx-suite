---
title: PID Bandwidth
sidebar_label: PID Bandwidth
sidebar_position: 30
---

# PID Bandwidth

Sets the overall PID-loop bandwidth and the D-term and B-term cutoff frequencies independently for Roll, Pitch and Yaw in the active PID profile, whose number appears in the page title.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *PID Bandwidth*

Read-only while the model is armed.

## Settings

Each row has a separate value for Roll, Pitch and Yaw, in that order.

| Setting | What it does |
| --- | --- |
| PID Bandwidth | Overall PID-loop bandwidth, using an extra low-pass filter on each axis. Higher values weaken filtering. Range: 0 to 250 Hz per axis. |
| D-term cut-off | Cutoff frequency of the additional first-order low-pass filter for the D-term, reducing its sensitivity to noise. Range: 0 to 250 Hz per axis. |
| B-term cut-off | Cutoff frequency for setpoint boost (B-term), controlling how quick the boost feels. Range: 0 to 250 Hz per axis. |

## Saving

Save writes the whole active PID profile, commits it once to EEPROM, and reports success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the profile without a reboot.

## Related

- [Rotorflight documentation: PID Controller Bandwidth](https://doc.rotorflight.org/configurator/tabs/profiles/#pid-controller-bandwidth)

*Documented against RFSuite 0.2.1.*
