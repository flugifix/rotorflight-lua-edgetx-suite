---
title: Power Preferences
sidebar_label: Preferences
sidebar_position: 50
---

# Power Preferences

The power settings that belong to the radio rather than to the flight controller: what kind of
model this is, which SmartFuel estimate to fall back on when the board computes none, and
whether SmartFuel's two telemetry sensors are published.

## Where to find it

*Configuration* → *Setup* → *Power* → *Preferences*

Always available.

## Settings

| Setting | What it does |
| --- | --- |
| Model Type | What the suite treats this machine as for the fuel estimate and for the announcements: *AUTO*, *ELECTRIC* or *NITRO*. Default *AUTO*, which decides from the battery telemetry. |
| Local SmartFuel Source | Which estimate the suite computes itself when the flight controller does not: *CURRENT*, *VOLTAGE* or *COMBINED*. Default *CURRENT*. Used only where the board has no SmartFuel of its own — see the [SmartFuel page](smartfuel.md). |
| Publish SmFt / SmCp | Whether the remaining fuel and the estimated consumption are published as the `SmFt` and `SmCp` telemetry sensors. **On by default**, which is what the suite has always done; turn it off on a machine whose sensors nothing reads. |

## Notes

- **The settings are stored per flight controller**, in this machine's own file on the card, not
  per radio and not per model. Plugging a different board in brings its own values up.
- ***Publish SmFt / SmCp* only matters for things outside the suite.** The dashboard, the
  per-flight statistics and the spoken announcements read the value directly from the script that
  computes it and are unaffected by this setting either way. Logical switches, special functions,
  the radio's own telemetry screens and the telemetry log can only read a sensor, so they need it
  on. What the two sensors hold is described under
  [custom telemetry sensors](../../../reference/telemetry-sensors.md).
- **Turning it off is worth it only on a machine whose sensors nothing reads**, and what it saves
  is two of the model's telemetry slots plus a model write on every update of them.
- **Switching it off does not delete a sensor the model already has.** `SmFt` stops being
  updated and ages out like any sensor that has stopped arriving; remove the row on the radio's
  own telemetry page if you do not want it there.

## Related

- [SmartFuel page](smartfuel.md) — the estimate the flight controller computes, and its tuning
- [Custom telemetry sensors](../../../reference/telemetry-sensors.md) — what `SmFt` and `SmCp` hold
- [Rotorflight documentation: SmartFuel](https://www.rotorflight.org/docs/setup/smartfuel)

*Documented against RFSuite 0.1.7.*
