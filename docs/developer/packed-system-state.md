---
title: Packed system state
sidebar_label: Packed system state
---

# Packed system state

Rotorflight sends two packed status sensors, *System Status* (CRSF `STAT`, S.Port `5140`) and
*System Config* (CRSF `SCFG`, S.Port `5141`), each one 32-bit word of bit fields. The layout is
the firmware's `src/main/telemetry/status.h`. Two pieces of the suite read them.

## The decoder: `lib/system_state.lua`

`fields` lists every field `status.h` defines, per word (`system_status`, `system_config`), in
bit order: `{ key, shift [, mask] }`, where an entry without a mask is a one-bit flag. The System
Status diagnostics page builds its rows from this list, so the layout has one owner.

`decode(source, word)` returns a table with one entry per field and `word` holding the original
integer, or `nil`. Flags decode to booleans; enums and the three profiles (one-based, as the
firmware sends them) to integers. Reserved bits are ignored. A word that is not a whole number
from 0 to `0x7FFFFFFF` is refused (bit 31 is reserved in both words); a zero is valid data.

`read(Sensors, source)` is `decode(source, Sensors.getLiveValue(source))`, and `nil` when the
sensor module has no `getLiveValue`. Call it from a bounded wakeup pass and cache the result for
reactive properties rather than calling it from a property.

## The strict read: `Sensors.getLiveValue(source)`

An opt-in counterpart to `Sensors.getValue`. It finds the sensor exactly as `getValue` does --
the same source aliases, duplicate-slot selection and search throttles -- and then accepts the
value only when `getSourceValue` returns a number and its second result, *current*, is `true`. A
missing `getSourceValue`, an unknown or false *current*, and an error raised by the source all
return `nil`. For the six sources `getValue` can take from a packed word (arm state, governor
state, rescue state and the three profiles) it falls back the same way, to a packed word that is
itself current. `getValue` and its readers are unchanged and still receive a held value.

**What *current* proves.** In EdgeTX 2.12 a sensor stays current for up to 20 seconds after its
last value (`TELEMETRY_SENSOR_TIMEOUT_START`, 125 x 160 ms), and every sensor turns old about one
second after the telemetry stream stops (`TELEMETRY_TIMEOUT10ms`). An unchanged value cannot say
how old it is inside that window. So a live read is information for the pilot, not the
acknowledgement of a configuration write, and `STAT` carries the ARMED bit, not the
arming-disable flags: keep the MSP reply and an MSP read-back where a tool needs either.

Without either sensor, a caller keeps whatever it did before. Neither an MSP API version nor a
sensor row in the model proves that a current value has arrived. This module does not choose which
sensors the flight controller sends.

## Checks

`lua5.3 bin/telemetry/verify_system_state.lua --self-test` runs offline: every field at its bit
position in isolation, refused words, the strict read against held, stopped, unknown and failing
sources, the packed fallbacks, reconnect after `Sensors.reset()`, duplicate sensor slots, the
instruction count of one read, the System Status page decoding through the shared module, and a
negative control that substitutes the held `getValue` for the strict read and must be refused.
