---
title: Rescue
sidebar_label: Rescue
sidebar_position: 70
---

# Rescue

Sets rescue behavior in the active PID profile, whose number appears in the page heading: leveling, flipping upright, collective pitch and the timing of each stage.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Rescue*

Read-only while the model is armed.

## Settings

Only **Rescue mode enable** is shown while rescue is off. The other settings appear when it is on, with the additional condition for Altitude hold below.

The three switches have inline help. The page's **?** explains the numeric rows in screen order: **Pull-up**, **Climb**, **Hover**, **Flip**, **Gains**, and **Dynamics**, covering both fields where present.

| Setting | What it does |
| --- | --- |
| Rescue mode enable | Enables or disables rescue in this profile. |
| Altitude hold | Keeps altitude hold enabled, or switches rescue to climbing instead. Shown only when rescue is on and the profile read from the flight controller already uses altitude hold; its altitude and controller gains are not edited on this page. |
| Flip to upright | Flips the helicopter upright if rescue is activated while inverted. |
| Pull-up: Collective | Collective pitch applied for the initial rapid climb. Range: 0 to 100 %. |
| Pull-up: Time | How long pull-up collective is applied before the flip or climb stage. Range: 0.0 to 25.0 s. |
| Climb: Collective | Collective pitch applied during the climb stage. Range: 0 to 100 %. |
| Climb: Time | How long climb collective is applied before switching to hover. Range: 0.0 to 25.0 s. |
| Hover: Collective | Collective pitch for maintaining a stable hover after the climb. Range: 0 to 100 %. |
| Flip: Fail time | Aborts rescue if the helicopter cannot complete the flip within this time. Range: 0.0 to 25.0 s. |
| Flip: Exit time | Time during which collective changes are limited to smooth the return to normal flight. Range: 0.0 to 25.0 s. |
| Gains: Level | How strongly the helicopter levels during rescue. Range: 0 to 250. |
| Gains: Flip | How strongly the helicopter flips upright during inverted rescue. Range: 0 to 250. |
| Dynamics: Rate | Maximum rescue roll/pitch rotation rate. Range: 5 to 1000°/s. |
| Dynamics: Accel | Maximum roll/pitch acceleration during leveling or flipping. Range: 0 to 10000°/s². |

## Saving

Save writes the whole rescue profile, commits it once to EEPROM, and reports success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the profile without a reboot. A profile change after the page was read refuses Save until the active profile is read with Reload, or the original profile is selected again.

## Related

- [Rotorflight documentation: Rescue Settings](https://doc.rotorflight.org/configurator/tabs/profiles/#rescue-settings)

*Documented against RFSuite 0.2.1.*
