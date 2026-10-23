---
title: Tune Advisor
sidebar_label: Tune Advisor
sidebar_position: 30
---

# Tune Advisor

While you fly in rate mode, the flight controller measures how the heli answers the sticks. This page reads
those measurements and suggests one change at a time for each axis. It changes nothing by itself: make the
change on *PIDs*, *Rates* or *PID Controller*, fly again and come back.

The flight controller counts only rate flight while spooled up and airborne, with the heli moving on some axis.
Time in Angle, Horizon, Trainer, Altitude hold, Rescue, GPS rescue or failsafe is left out. The data builds up
over several flights. Clear it with *\** after confirming, or it clears at the next arming when the PIDs, the
I-term relax cut-off, the PID mode, the rates (type, RC rate, expo, S-rate), the PID profile or the rate profile
differ from the last arming. Nothing is cleared while you fly. A useful set is about ten seconds of rolls,
flips and pirouettes with the stick centred after each one. The measurements live in the flight controller's
memory and are lost at power-off.

## Where to find it

*Configuration* → *Flight Tuning* → *Tune Advisor*

Needs MSP API 12.10; greyed out on an older flight controller. Read-only while the model is armed.

The page refreshes every 2 seconds. A flight controller that does not know the Tune Advisor command -- a 12.10
firmware from before it, or a board built without it -- shows "Needs newer firmware", and the page stops asking;
Reload asks again. When the link drops for a moment, the last measurements stay on screen until the next answer.

## Settings

| Line | What it shows |
| --- | --- |
| #n (heading at the top) | The rate profile the advice is for. A profile switch with the page open is followed at once, when the radio sees the profile. |
| Axis | Roll, Pitch or Yaw. Everything below is for the chosen axis. |
| Flight data | Minutes and seconds of rate flight measured, and whether measuring is happening now (collecting) or not (paused). |
| Response | How fast the heli turns compared with the rate the stick asks for, for example "53% faster than asked". "Needs more flying" shows how much data is still needed; "Too uneven to judge" means the response varies too much. |
| Stops | How much the heli bounces back after you centre the stick, as a share of the turn rate. Needs 10 stops. |
| Suggested changes | Up to three changes, each named by the page, row and column to change, in the units that page shows, for example *PIDs > Roll > FF: 100 -> 80* and *Rates > Roll > Max Rate: 720 -> 900*. |
| Why | The reason for each change, and a fact worth knowing when there is room (for example how much faster the heli turns at high collective). |
| * (header) | Clears the measurements on the flight controller after asking to confirm. |

The suggestions follow these rules:

- **Turns faster or slower than asked** (more than 15% off): change FF and the rates by the same amount in
  opposite directions, so the stick feel stays the same but the heli flies the rate you ask for. One step
  changes FF by at most 20%. With Actual, Quick and Rotorflight rates the page gives the exact rate values,
  never beyond what the *Rates* page takes for that column; with the other rate types it gives a percentage. An axis with FF set to 0 (often the tail) gets no FF advice.
- **Full stick asks for more rate than the heli reaches** (roll and pitch), with the cyclic at its limit: lower
  the rates to what the heli reaches.
- **Stops bounce back 12% or more**: if the I-term pushes back, lower *Advanced > PID Controller > Cut-off point*
  by 20%. If FF does not match yet, fix FF first. Otherwise the controller is barely braking the stop: raise P
  by 20% (or add B).

## Getting a clean measurement

- A rate profile switch in flight clears nothing: the set then mixes both profiles, and the advice is worked
  out against the profile active when you look. Fly one profile per measurement.
- Switching polar cyclic on or off clears nothing either: it is not part of what the flight controller checks
  at arming. Clear once with *\** after toggling it.
- Fly, land, open the page, make one change, then fly again. The next arming starts a fresh set by itself when
  the tune changed.

## Notes

- The names in a suggestion are the ones the target page shows. Which rate columns are named depends on the
  rate type: *Center Sens* and *Max Rate* for Actual, *RC Rate* and *Max Rate* for Quick, *Rate* for Rotorflight.
- With polar cyclic rates (*Advanced* → *Rates (Advanced)* → *Cyclic Behaviour*), the *Rates* page shows one
  *Cyclic* row, which edits the Pitch rates. While polar is on, the flight controller applies that one curve
  to the whole cyclic stick, roll included, and a rate change on that row changes both axes in flight. The
  Roll rates are not changed by the row; they are kept as they were and apply again once polar is switched
  off. With polar on, Roll and Pitch rate suggestions name the *Cyclic* row and work from the Pitch rates.
  The page reads the polar setting after the first advisor answer, again when the active rate profile changes,
  and on Reload. Until the first read answers, or if it fails, suggestions name the per-axis rows as before;
  a later read that fails keeps the previous answer. The profile switch is seen through the radio's rate
  profile telemetry sensor, otherwise the profile known at connect is used. Without that sensor, a switch
  made on the transmitter is not seen; Reload reads again. Feed-forward and P/cut-off suggestions stay per axis.
  Roll and Pitch are still judged separately, so their cards can ask for different changes to the one *Cyclic*
  row: change it once, fly, and check both again.

## Related

- [Rates](rates.md)
- [Rotorflight documentation](https://doc.rotorflight.org/)

*Documented against RFSuite 0.1.7.*
