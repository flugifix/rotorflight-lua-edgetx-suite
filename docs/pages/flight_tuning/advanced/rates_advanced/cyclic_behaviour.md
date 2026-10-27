---
title: Cyclic Behaviour
sidebar_label: Cyclic Behaviour
sidebar_position: 20
---

# Cyclic Behaviour

Sets how combined roll and pitch inputs are processed in the active rate profile, whose number appears in the page heading. The cyclic ring limits diagonal inputs; polar coordinates apply the rate curve to their combined direction and magnitude.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Rates (Advanced)* → *Cyclic Behaviour*

Read-only while the model is armed.

## Settings

| Setting | What it does |
| --- | --- |
| Polar coordinates | Applies cyclic rates to the combined direction and magnitude when on; when off, Roll and Pitch rates are applied independently. |
| Cyclic ring | Enables a limit on combined roll and pitch input to prevent excessive diagonal rates. Turning it on from off sets the level to 150%. |
| Cyclic ring % | Sets how strongly the ring limits diagonal input. At 100% the limit is circular; higher values allow more diagonal input. Range: 50 to 250%. Shown only while Cyclic ring is on. |

## Saving

Save writes the whole active rate profile, commits it once to EEPROM, and reports success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the profile without a reboot.

## Related

- [Rotorflight documentation: Cyclic Ring](https://doc.rotorflight.org/configurator/tabs/rates/#cyclic-ring)
- [Rotorflight documentation: Profiles](https://doc.rotorflight.org/configurator/tabs/profiles/)

*Documented against RFSuite 0.2.1.*
