---
title: MSP setup API modules
---

# MSP setup API modules

These modules use the existing MSP API loader and queue. Loading a codec does not
start polling, change a setting or establish firmware support. A caller must handle
unsupported commands and validate the flight controller's state before writing.
No page or menu entry is added.

| Module | Command | Contract |
| --- | --- | --- |
| `servo` | 103 | U16 live outputs, 1–32 entries. |
| `attitude` | 108 | Three signed S16 values; roll/pitch in tenths of degrees, yaw in degrees. |
| `rc_command` | 113 | Signed function commands, at least roll, pitch, yaw, collective and throttle. |
| `rx_channels` | 114 | 1–18 raw receiver channels before RX_MAP. These differ from mapped MSP_RC functions. |
| `motor_telemetry` | 139 | Count followed by 16-byte records: U32 RPM, four U16 fields and two S16 temperatures. Up to four motors; zero is valid. |
| `arming_disable` | 99 | U8 inhibit 1/release 0, scoped by firmware to the MSP connection. The caller owns entry, readback and cleanup. |
| `acc_calibration` | 205 | Empty write payload. The caller owns calibration preconditions and completion checks. |
| `rx_serial_trial` | `0x5F12` | Trial action and seven-byte state. Receiver UART reinitialization can interrupt a radio MSP link; this codec does not make radio-side START safe. |
| `tail_motor_output` | `0x5F14` | Actions 0/read, 1/SERVO 4, 2/MOTOR 2. Reply: output and result. Requires firmware implementing the extension. |
| `servo_configurations` | 120/212 | Existing count/table decoder plus U8 index and a complete 16-byte configuration write. Retains all calibration fields. |
| `mixer_input` | 170/171 | Adds zero-based signed `inputs[index]` records alongside the existing unsigned flat fields. |
| `rc_config` | 66/67 | Refuses replies shorter than the complete 12-byte configuration. |

The optional `0x5F12`/`0x5F14` commands are protocol codecs, not a claim that an
API-version number proves support. Their callers must establish support from an
actual reply. Existing board-alignment and ESC-wiring codecs are separate changes.

Large tables may exceed a telemetry transport's reply limit. The bulk servo codec
remains available; callers on a radio link should use existing indexed reads when
the whole table cannot fit. This change does not add a bulk-read retry fallback.

Run `lua5.3 bin/msp/verify_msp_setup_apis.lua` for byte vectors, signs, record order,
truncated replies and complete servo write/read round trips. These are offline
protocol checks; no physical flight controller or actuator was tested.
