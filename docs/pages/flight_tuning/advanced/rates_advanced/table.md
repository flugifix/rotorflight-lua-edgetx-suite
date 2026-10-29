---
title: Rate Table
sidebar_label: Rate Table
sidebar_position: 30
---

# Rate Table

Chooses the rate system for the active rate profile, whose number appears in the page heading. The selected system determines the curve and the columns shown on the Rates page.

## Where to find it

*Configuration* → *Flight Tuning* → *Advanced* → *Rates (Advanced)* → *Rate Table*

Read-only while the model is armed.

## Settings

| Setting | What it does |
| --- | --- |
| Rates Type | Selects None, Betaflight, Raceflight, KISS, Actual, Quick or Rotorflight. None applies no rate curve; Rotorflight is the default system. Saving a changed type asks for confirmation before resetting its rate, shape and expo values to that type's defaults. |

## Saving

Confirming the rate-type reset writes the selected type and its defaults; cancelling writes nothing. Save writes the whole active rate profile, commits it once to EEPROM, and reports success only once the flight controller has stored the values; a failed write or commit is reported, and a successful save re-reads the profile without a reboot.

## Related

- [Rotorflight documentation: Rates](https://doc.rotorflight.org/configurator/tabs/rates/)
- [Rotorflight documentation: Profiles](https://doc.rotorflight.org/configurator/tabs/profiles/)

*Documented against RFSuite 0.2.1.*
