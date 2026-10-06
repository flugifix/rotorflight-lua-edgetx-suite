---
title: Select Profile
sidebar_label: Select Profile
sidebar_position: 20
---

# Select Profile

Switches the flight controller to another PID profile and another rate profile, so a different tune
can be flown without the Rotorflight Configurator.

## Where to find it

*Tools* → *Select Profile*

Greyed out until the flight controller answers. Read-only while the model is armed.

## Settings

| Setting | What it does |
| --- | --- |
| PID Profile | The PID profile the flight controller flies after SAVE. |
| Rate Profile | The rate profile the flight controller flies after SAVE. |

Both lists offer the profiles the flight controller reports it has, and the two kinds are counted
separately: a board built with more than 256 kB of flash has six of each, one with more than 128 kB
has three PID profiles and six rate profiles, and a smaller one has two and three. A profile the board does
not have is not offered, because the board would not refuse it: it switches to profile 1 instead
and reports the change as done. Until the flight controller's status has been read, both lists
offer six.

## Notes

**The page follows the board.** When the profile is changed from the transmitter, for example by a
switch, the lists follow within about a second, as long as the telemetry carries the two profile
sensors and neither list has been changed since the page was opened, reloaded or saved. After SAVE
the page reads the board's status again, so the lists show what the board actually switched to.

**A SAVE that cannot be sent says so.** Without a connection to the flight controller, or while
the previous change is still being sent, nothing is written and the save notice says why.

## Related

- [Rotorflight documentation](https://www.rotorflight.org/docs/)

*Documented against RFSuite 0.1.7.*
