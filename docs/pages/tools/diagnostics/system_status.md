---
title: System Status
sidebar_label: System Status
sidebar_position: 57
---

# System Status

The two packed status sensors of the flight controller, decoded: *System Status* (CRSF `STAT`,
S.Port `5140`) carries the live state -- armed, airborne, failsafe, rescue, governor state and
more -- and *System Config* (CRSF `SCFG`, S.Port `5141`) the slower configuration -- the three
profiles, unsaved changes, which sensors the board has, the governor mode. The page to open when a
value the suite takes from these sensors looks wrong, or to see whether the two sensors arrive at
all.

## Where to find it

*System* → *Tools* → *Diagnostics* → *System Status*

Available without a connection to the flight controller: the page reads the radio's telemetry
sensors and sends nothing. Read-only while armed, like the other diagnostics pages: the tool
pauses its pages while the model is armed, so a page left open keeps the values of its last read
until the model is disarmed. The flight controller sends the two sensors from MSP API 12.10 on,
when they are in its telemetry sensor list.

## What it shows

The page has no settings. It reads the sensors twice a second while it is open, and the values
change in place.

**For each of the two sensors:**

| Row | What it shows |
| --- | --- |
| System Status / System Config | *Receiving* while values arrive; *Not current* once the sensor has stopped arriving or the link is down (the last value stays on the page); *Not received* when the model has the sensor but no value has arrived since the model was loaded; *No sensor* when the model has no such sensor. |
| Sensor | The name of the radio sensor that is read: `STAT` / `SCFG` on CRSF, `5140` / `5141` on S.Port. |
| Raw value | The 32-bit value as it arrived, in hexadecimal. |

**System Status, one row per field:** Armed, Airborne, Motors running, RX link up, Failsafe phase
(*Idle*, *RX loss detected*, *Landing*, *Landed*, *RX loss monitoring*, *RX loss recovered*, *GPS
rescue*), GPS fix (*None*, *Fix*, *Fix and home*), GPS healthy, Spooled up, Battery state (*OK*,
*Warning*, *Critical*, *Not present*, *Init*), Control saturated, Gyro overflow, ACC not calibrated,
Override active (a servo, motor or mixer test of the Configurator is on), Rescue state (*Off*,
*Pull-up*, *Flip*, *Climb*, *Hover*, *Exit*), Blackbox logging, Governor state.

**System Config, one row per field:** PID profile, Rate profile, Battery profile (each counted
from 1), Unsaved changes, Saving, Reboot required, Beeper on, ACC present, Baro present, Mag
present, GPS present, Blackbox full, RPM source active, Governor mode.

A field the firmware was built without (no GPS, no accelerometer) reads *No*, or its first value.

**Shared fields.** Five fields are also sent as sensors of their own: arm state (`ARM`), governor
state (`Gov`), PID profile (`PID#`), rate profile (`RTE#`) and battery profile (`BAT#`). Each is
shown twice, *Packed* as decoded from the packed sensor and *Own sensor* as its own sensor reads,
so the two sources can be compared on a real link. A value that disagrees reads *(differs)*; an
own sensor the model does not have, or that has not arrived, says so instead of a value. For
`ARM`, only its ARMED bit is compared: the sensor carries all arming flags, the packed sensor only
that one.

When neither packed sensor is received, the page says so in one line instead of the rows.

## Notes

- **A sensor the model does not have is not read.** The radio creates a telemetry sensor when the
  first value arrives while sensor discovery is on. If the flight controller sends both sensors and
  the page still says *No sensor*, run *Discover new sensors* on the model's telemetry page.
- **Which sensors the flight controller sends is set on the flight controller.** This suite's
  *Telemetry* page (*Configuration* → *Setup* → *Telemetry*) offers *System Status* and *System
  Config* on MSP API 12.10 and later.
- **Reload looks for every sensor again**, after one was discovered or deleted while the page was
  open. A sensor the model does not have is otherwise looked for again every two seconds.
- **Where the suite uses these sensors:** arm state, governor state and the three profiles are
  read from their own sensors, and from the packed sensors only when the own sensor is missing.
  This page shows both, whichever the suite uses.

## Related

- [Rotorflight documentation](https://doc.rotorflight.org/)

*Documented against RFSuite 0.1.7.*
