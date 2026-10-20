---
title: Helicopter wizard MSP and lifecycle
---

# Helicopter wizard MSP and lifecycle

The [Helicopter Setup page](../pages/helicopter_setup.md) uses the Suite's normal
MSP queue and API modules. It never opens another telemetry transport.

| API module | Command | Wire contract |
| --- | --- | --- |
| `servo` | 103 | PWM/bus output pulses, U16 values; length determines count. |
| `rc_command` | 113 | Signed S16 roll, pitch, yaw, collective and throttle commands. |
| `rx_channels` | 114 | Raw receiver channels as U16, before function mapping. |
| `motor_telemetry` | 139 | U8 count, then 16 bytes per motor: U32 RPM; U16 invalid ratio, mV, mA and mAh; S16 tenths of degrees for two temperatures. |
| `tail_motor_output` | `0x5F14` | Empty read, or U8 action 0/read, 1/SERVO 4, 2/MOTOR 2. Reply is U8 output plus U8 result; movement is unsaved until EEPROM/reboot. |
| `arming_disable` | 99 | U8 1 on wizard entry; verify MSP disable bit 16 in STATUS before enabling controls. U8 0 after cleanup on exit. Reassert after reboot. |
| `servo_override` | 192/193 | Read eight U16 values; write U8 index + U16 value, with optional U16 timeout. OFF = 2001. |
| `servo_override_all` | 196 | U16 value, optionally U16 timeout. A timed OFF is the capability probe. |
| `mixer_override` | 190/191 | Read 29 U16 values; write one U8 index + U16 value, optionally U16 timeout. OFF = 2501; passthrough = 2502. |
| `mixer_input` | 170/171 | Read signed rate/min/max records, indexed from zero; write U8 index plus three S16 values. Stabilized axes are 1, 2, 3, 4. |
| `servo_configurations` | 120/212 | U8 count plus 16-byte records; a write has the packed U8 index followed by one complete record. |
| `acc_calibration` / `attitude` | 205 / 108 | Empty calibration command; S16 tenths of degrees roll/pitch and S16 degree yaw. |
| `board_auto_align` | `0x5F13` | U8 start; query state and three signed alignment angles. Optional firmware extension. |
| `rx_serial_trial` | `0x5F12` | U8 start/stop; state, combination, inversion, half-duplex, pin swap and elapsed time. Optional firmware extension. |
| `esc_sensor_trial` | `0x5F0C` | U8 start/stop; state, combination, half-duplex, pin swap and elapsed time. Optional firmware extension. |

Timeout support is not a version predicate. Pre-extension API 12.10 firmware can
silently treat a five-byte per-servo/mixer override as permanent. The four-byte
196 OFF probe is rejected on that firmware and cannot deflect a servo. Only an ACK
permits timed holds; ordinary releases have no timeout bytes. Motor override 195
keeps its independent firmware timeout and always has the three-byte payload.

The transport decodes one reply, loads one API, dispatches one request, or expands
one indexed record per call. It never recursively continues from an MSP callback.
Configuration writes remain ordered before EEPROM. Profile transactions restore
the previous PID/rate profile, including a best-effort restore after failure.

The host's `buildScene` recognizes `hideSuiteFrame = true` on a page module. It
passes full-screen bounds and omits the native page/header. Lifecycle, queue ownership
and RTN/EXIT remain in `ui/home.lua`; the native standalone/widget cancel event feeds
that dispatch. The page supplies its own Back/Continue/Save navigation.

Scene assembly is paced, and MSP callbacks only publish buffers. Live labels and
control properties read cached page state. All visit state is released in `onClose`.
No radio code uses `os`, coroutines, canvas drawing or image rotation.

*Documented against RFSuite 0.2.1 and the fixed Configurator reference recorded on
the page. This is a protocol/code review, not a physical-radio test.*
