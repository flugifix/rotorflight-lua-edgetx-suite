---
title: PID Controller
sidebar_label: PID Controller
sidebar_position: 20
---

# PID Controller

Sets how the flight controller's I-term behaves: how fast the accumulated error decays on the ground and in flight, how far it may grow, and where I-term accumulation is held back during fast stick movements; on firmware that has them, also two master gains that scale the feedback gains as a whole. The settings belong to the active PID profile, whose number the page title shows.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *PID Controller*

Read-only while the model is armed.

## Settings

| Setting | What it does |
| --- | --- |
| Ground Error Decay | Time constant for the decay of the accumulated error while the helicopter is on the ground, so it does not tip over before take-off. 0.0 to 25.0 s, default 2.5 s; 0 leaves the ground phase to the in-flight decay. |
| Inflight Error Decay (Time / Limit) | Time is the time constant of the decay in flight, 0.0 to 25.0 s, default 25.0 s; 0 switches it off. Limit caps how fast the decay may remove the error, 0 to 250, default 12; 0 removes the cap. |
| Error Decay Stick Gain | *MSP API 12.10 and later.* Makes the roll and pitch error decay faster the further the cyclic stick is deflected, on the ground and in flight, so the I-term does not wind up while the stick is held against a helicopter that cannot follow, for example on a slope take-off. 0 to 250, default 0 (off). |
| Master Gain (Cyclic / Yaw) | *Firmware with rotorflight-firmware#538.* Cyclic scales the roll and pitch P, I, D and Offset gains together, Yaw the tail P, I and D gains, keeping the ratios between them and the tail's CW/CCW stop gain balance. Feedforward, Boost and the precompensations are not scaled, so the stick response stays as tuned. Changing a master gain in flight does not upset the trim already held by I and Offset; only how fast they build up changes. 25 to 200 %, default 100 %. #538 did not change the MSP API version, so the row is shown when the flight controller's PID profile reply carries the two gains, and a firmware without them shows no row. |
| Error limit (R / P / Y) | Angle limit for the I-term on roll, pitch and yaw. 0 to 180°, defaults 45°, 45°, 60°. |
| HSI Offset limit (R / P) | Angle limit for the High Speed Integral (O-term) on roll and pitch. 0 to 180°, default 90°. |
| Error rotation | *MSP API 12.08 only.* Lets the accumulated error be shared between the axes. |
| I-term relax | Off, RP or RPY: the axes on which I-term accumulation is limited during fast stick movements, which reduces bounce-back after them. Default RPY. |
| Cut-off point (R / P / Y) | Cut-off frequency of the I-term relax on each axis. 1 to 100 Hz, default 10 Hz. |

## Notes

- Save writes the whole PID profile and commits it once to EEPROM, reporting success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the profile without a reboot. PID Bandwidth, Autolevel, Main Rotor and Tail Rotor write the same profile; a save there writes back the Error Decay Stick Gain and the Master Gains it read and changes nothing. The Master Gains are sent only while the last PID profile reply of the connection carried them, so a flight controller without them never receives the two bytes.
- The flight controller applies Error Decay Stick Gain in its default PID mode (`pid_mode = 3`) only. The CLI name of the setting is `error_decay_gain_cyclic`.
- The CLI names of the master gains are `cyclic_master_gain` and `yaw_master_gain`. In flight they can be changed with the *Cyclic Master Gain* and *Yaw Master Gain* adjustment functions ([Adjustments](../../setup/controls/adjustments.md)).

## Related

- [Rotorflight documentation: Profiles tab](https://doc.rotorflight.org/configurator/tabs/profiles/)

*Documented against RFSuite 0.1.7.*
