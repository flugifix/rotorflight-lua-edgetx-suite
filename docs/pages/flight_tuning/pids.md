---
title: PIDs
sidebar_label: PIDs
sidebar_position: 10
---

# PIDs

Tune the PID controller gains for Roll, Pitch and Yaw in the active PID profile. The heading
shows the profile number; each row is an axis and each column is a gain.

## Where to find it

*Configuration* → *Flight Tuning* → *PIDs*

Read-only while the model is armed.

## Settings

Every gain ranges from 0 to 1000. Values are read from the flight controller.

| Setting | What it does |
| --- | --- |
| Roll / P | Corrects roll rate error; more gain tightens tracking, but too much causes fast oscillation. |
| Roll / I | Corrects accumulated roll error and drift; raise gradually for stable piro pitch pumps, keeping Roll and Pitch equal. |
| Roll / D | Damps roll overshoot and disturbances; too much amplifies gyro noise. |
| Roll / FF | Adds roll response from stick commands without reacting to model motion; higher gain sharpens response but risks overshoot or strikeback. |
| Roll / O | Sets the High Speed Integral Offset gain, active at large collective angles to stabilize high-speed flight and large collective pitch changes. |
| Roll / B | Boosts feedforward using the rate of change of the roll setpoint to sharpen response without the drawbacks of high P or FF gains. |
| Pitch / P | Corrects pitch rate error; more gain tightens tracking, but too much causes fast oscillation. |
| Pitch / I | Corrects accumulated pitch error and drift; match Roll, as too much gain causes slow oscillation at stops or under load. |
| Pitch / D | Damps pitch overshoot and disturbances; too much amplifies gyro noise. |
| Pitch / FF | Adds pitch response from stick commands without reacting to model motion; higher gain sharpens response but risks overshoot or strikeback. |
| Pitch / O | Sets the High Speed Integral Offset gain, active at large collective angles to stabilize high-speed flight and large collective pitch changes. |
| Pitch / B | Boosts feedforward using the rate of change of the pitch setpoint to sharpen response without the drawbacks of high P or FF gains. |
| Yaw / P | Corrects tail rate error; increase until slight wobble appears in funnels, then back off slightly. |
| Yaw / I | Holds the tail against sustained disturbances; raise for firm hold in hard moves, as too much causes slow wag. |
| Yaw / D | Damps tail overshoot for smooth stops; use more for slow servos and less for fast servos. |
| Yaw / FF | Adds yaw response from stick commands without reacting to model motion; higher gain sharpens response but risks overshoot or strikeback. |
| Yaw / B | Boosts feedforward using the rate of change of the yaw setpoint to sharpen response without the drawbacks of high P or FF gains. |

## Notes

- There is no O gain on Yaw. Fly, observe and fine-tune the gains under real conditions.
- A profile switch keeps unsaved edits on screen and refuses Save until the original profile
  is selected again or Reload reads the new one.
- Save writes the values present when pressed, then commits them to EEPROM without a restart;
  success is reported only after the flight controller confirms storage, and the page reads
  back the values. A refused or failed save keeps the edits unsaved.
  See [Saving configuration](../../reference/saving.md).

## Related

- [Rotorflight PID controller gains](https://doc.rotorflight.org/docs/configurator/tabs/profiles#pid-controller-gains)
- [Rotorflight offset gains](https://doc.rotorflight.org/docs/configurator/tabs/profiles#offset-limitgain)

*Documented against RFSuite 0.2.1.*
