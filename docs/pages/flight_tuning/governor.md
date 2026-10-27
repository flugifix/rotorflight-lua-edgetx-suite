---
title: Governor
sidebar_label: Governor
sidebar_position: 40
---

# Governor

Tune headspeed, throttle limits, governor gains, precompensation and Tail Torque Assist in
the active PID profile. The heading shows the profile number and stored governor mode.

## Where to find it

*Configuration* → *Flight Tuning* → *Governor*

Read-only while the model is armed.
Needs MSP API 12.09; hidden on an older flight controller.

With governor mode OFF the page shows a disabled message instead of fields, and Save and
Reload are disabled. LIMIT and DIRECT show only the two throttle limits. ELECTRO (the page's
name for ELECTRIC) and NITRO show all fields below.

## Settings

Values are read from the flight controller. All fields except the throttle limits are shown
only in ELECTRO and NITRO modes.

| Setting | What it does |
| --- | --- |
| Full headspeed (rpm) | Headspeed target at 100% throttle input. Range: 0 to 30000 rpm, in steps of 10. |
| Min throttle (%) | Minimum throttle output the governor may use. Range: 10 to 100%; also shown in LIMIT and DIRECT. |
| Max throttle (%) | Maximum throttle output the governor may use. Range: 10 to 100%; also shown in LIMIT and DIRECT. |
| Master gain | Overall governor PID loop gain. Range: 0 to 255. |
| Gains / P | Proportional gain for headspeed error. Range: 0 to 255. |
| Gains / I | Integral gain for accumulated headspeed error. Range: 0 to 255. |
| Gains / D | Derivative gain for damping headspeed changes. Range: 0 to 255. |
| Gains / FF | Collective/cyclic feedforward gain. Range: 0 to 255; disabled when transmitter precompensation is enabled in the stored profile flags. |
| Precomp / YAW | Yaw weight mixed into feedforward to anticipate load changes. Range: 0 to 255; disabled with transmitter precompensation. |
| Precomp / CYC | Cyclic weight mixed into feedforward to anticipate load changes. Range: 0 to 255; disabled with transmitter precompensation. |
| Precomp / COL | Collective weight mixed into feedforward to anticipate load changes. Range: 0 to 255; disabled with transmitter precompensation. |
| Tail Torque Assist / MASTER GAIN | Raises headspeed to use main-rotor torque for yaw assistance on motorized tails. Range: 0 to 255. |
| Tail Torque Assist / LIMIT | Caps the headspeed increase above Full headspeed. Page range: 0 to 255%, in steps of 1%. |

## Notes

- Set the operating mode under *Setup* → *Governor* → *General*; this page changes only the
  governor profile, including the fields shared with *Flight Tuning* → *Advanced* → *Tail Rotor*.
- Changing headspeed can require the PID controller gains to be tuned again.
- A profile switch keeps unsaved edits on screen and refuses Save until the original profile
  is selected again or Reload reads the new one.
- Save writes the values present when pressed, then commits them to EEPROM without a restart;
  success is reported only after the flight controller confirms storage, and the page reads
  back the values. A refused or failed save keeps the edits unsaved.
  See [Saving configuration](../../reference/saving.md).

## Related

- [Rotorflight governor documentation](https://doc.rotorflight.org/docs/configurator/tabs/governor)
- [Rotorflight governor profile settings](https://doc.rotorflight.org/docs/configurator/tabs/governor#governor-profile-settings)

*Documented against RFSuite 0.2.1.*
