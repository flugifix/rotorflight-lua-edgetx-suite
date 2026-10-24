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
| `tail_motor_output` | `0x5F14` | U8 action 0/read, 1/SERVO 4, 2/MOTOR 2. Reply is U8 output plus U8 result; movement is unsaved until EEPROM/reboot. |
| `arming_disable` | 99 | U8 1 on wizard entry; verify MSP disable bit 16 in STATUS before enabling controls. U8 0 after cleanup on exit. Reassert after reboot. |
| `servo_override` | 192/193 | Read eight U16 values; write U8 index + U16 value, with optional U16 timeout. OFF = 2001. |
| `servo_override_all` | 196 | U16 value, optionally U16 timeout. Kept as a direct all-servo API; not used to infer mixer support. |
| `mixer_override` | 190/191 | Read 29 U16 values; write one U8 index + U16 value, optionally U16 timeout. OFF = 2501; passthrough = 2502. |
| `mixer_input` | 170/171 | Read signed rate/min/max records, indexed from zero; write U8 index plus three S16 values. Stabilized axes are 1, 2, 3, 4. |
| `get_servo_config` / `servo_configurations` | 125/212 | Read U8 raw servo-parameter index, reply one 16-byte record. PWM slots retain their index; packed bus slots map to raw 8–25. Writes retain packed U8 index plus one complete record. Bulk command 120 is not used. |
| `get_adjustment_range` / `set_adjustment_range` | 156/53 | Read U8 index, reply one 14-byte record; all 42 slots are read sequentially. Bulk command 52 is not used. |
| `rc_config` | 66/67 | A complete 12-byte RC configuration is required; truncated throttle/deflection data is refused. |
| `governor_profile` | 148/149 | Per PID profile: U16 RPM target `governor_headspeed`. Read complete profiles through `profileLoop`, save only edited targets and preserve all other fields. Restore the active PID profile after reads/writes; profile 1 only when assignment is unknown. Never part of startup `READS`. |
| `governor_config` | 142/143 | Existing shared configuration read. New U16 fields `gov_spoolup_time`, `gov_spooldown_time`, `gov_recovery_time` are deciseconds; display seconds with the same shared formatter/limits as the Governor ramp page. |
| `filter_config` | 92 | Read-only `rpm_preset` after governor entry: 0 means CUSTOM; 1/2/3 mean Low/Medium/High. No command 93 from the wizard. |
| `rpm_filter_v2` | 154 | Read-only CUSTOM check: request U8 axis 0/1/2, read 16 source/U16 center/Q records per axis. Any nonzero `notch_source_1..16` enables a custom notch. A complete 64-byte response is required. No command 155 from the wizard. |
| `esc_parameters_yge` / `esc_parameters_hw5` | 217/218 | Additional Suite parameter-link integration beyond Configurator. Existing APIs alone parse, validate family signatures and encode complete blocks. `lib/esc_params.lua` owns read-before-write, changed-field overlay and matching readback. Read jobs use retryOnErrorReply, timeout 1 second, maxRetries 3. HW1128/HW1132 expose no flight_mode through the API's _supported metadata. |
| `motor_config` | 131/222 | Range button changes only mincommand/minthrottle/maxthrottle, preserving the complete record. Existing save/EEPROM and reboot handling apply; command 131 verifies the FC values before command 218. API limits are the single source for the Suite throttle page and wizard's unchanged 50..2250 us bounds. |
| `acc_calibration` / `attitude` | 205 / 108 | Empty calibration command; S16 tenths of degrees roll/pitch and S16 degree yaw. |
| `board_auto_align` | `0x5F13` | U8 start; query state and three signed alignment angles. Optional firmware extension. |
| `rx_serial_trial` | `0x5F12` | U8 start/stop; state, combination, inversion, half-duplex, pin swap and elapsed time. Wire codec retained; radio wizard directs detection to USB and sends no START. |
| `esc_sensor_trial` | `0x5F0C` | U8 start/stop; state, combination, half-duplex, pin swap and elapsed time. Optional firmware extension. |

Bulk adjustment command 52 returns 588 bytes, beyond the firmware's 320-byte
telemetry response buffer. A servo table with bus channels can also exceed it.
Indexed reads publish a complete table only after every record succeeds. Each
request remains a read, with one U8 index. A timeout or malformed record stops
startup without offering partially loaded settings. Progress is a cached label.

Receiver setup requires a working MSP radio link. Receiver wiring detection must
run through USB Configurator: the firmware trial closes/reopens the receiver UART
that also carries radio MSP. The page explains this instead of starting a trial
that can disconnect itself. ESC trials and board alignment remain available.

Timeout support is not a version predicate. Pre-extension API 12.10 firmware can
silently treat a five-byte per-output override as permanent. Each command (193 and
191) is probed with OFF only: valid five-byte payload ACK plus explicit refusal
of the invalid four-byte payload. Trailing-byte acceptance and transport timeout
both leave that command on legacy holds. Servo capability never authorizes mixer
timeouts. Ordinary releases have no timeout bytes. Motor override 195 keeps its
independent firmware expiry and always has the three-byte payload.

Cleanup has its own bounded queue owner. One OFF is in flight at a time and its
callback queues at most one next OFF; STATUS can run between them. Normal close
waits for all required OFF acknowledgements before releasing MSP_ARMING_DISABLE.
A missing connection cannot prove cleanup: the page requires physical power-off
before exit. External teardown retains the FC lock and marks this FC for a power
cycle on the next visit in the same Suite session. No automatic rollback is
claimed after external teardown; an FC power cycle clears unsaved RAM.

The transport decodes one reply, loads one API, dispatches one request, or expands
one indexed record per call. It never recursively continues from an MSP callback.
Configuration writes remain ordered before EEPROM. Profile transactions restore
the previous PID/rate profile, including a best-effort restore after failure.

## ESC range and mode field audit

These are additions beyond the pinned Configurator. The table inventories complete
records, including fields serialized unchanged. Layouts and codecs remain solely
in the existing API modules. YGE range changes zero/range; mode changes governor
or flight_mode. FC range changes mincommand/minthrottle/maxthrottle. There are no
ESC parameter reads in startup READS and no automatic parameter writes.

The family descriptor owns the seven YGE and four HW5 mode value-to-i18n-key
mappings under app.pages.setup_esc_motors. Literal markers survive packaging
without runtime locale bundles; the wizard has no second mode-name list. The
existing ESC tools option lists remain unchanged for a later migration: YGE
page.lua:507-515 (consumed at 517), HW5 page.lua:516-521 (consumed at 523), both
under app/pages/setup/esc_motors/esc_tools/escmfg/<family>/.

Additional existing inputs used by the step are esc_sensor_config.protocol and
half_duplex, serial_config.port_1..12_function_mask (ESC function bit),
feature_config.enabledFeatures (governor bit), governor_config.gov_mode and
motor_telemetry.motors[1].voltage/temperature. These come from existing load/poll
reads. Live Esc# telemetry is passed to lib/esc_status.decode; its transient
restart verdict is latched for the pending transaction, without another signature
check or MSP layout. EEPROM uses the existing empty command 250; STATUS and
arming-disable retain the wizard's existing lifecycle.

| API | Field | Direction in this integration | Source definition |
| --- | --- | --- | --- |
| esc_sensor_config | protocol | existing read | src/rfsuite/tasks/msp/api/esc_sensor_config.lua:47 |
| esc_sensor_config | half_duplex | existing read | src/rfsuite/tasks/msp/api/esc_sensor_config.lua:48 |
| serial_config | port_1..12_function_mask | existing read | src/rfsuite/tasks/msp/api/serial_config.lua:13 |
| feature_config | enabledFeatures | existing read | src/rfsuite/tasks/msp/api/feature_config.lua:17 |
| governor_config | gov_mode | existing read | src/rfsuite/tasks/msp/api/governor_config.lua:60 |
| motor_telemetry | motors[1].voltage | existing poll read | src/rfsuite/tasks/msp/api/motor_telemetry.lua:18 |
| motor_telemetry | motors[1].temperature | existing poll read | src/rfsuite/tasks/msp/api/motor_telemetry.lua:20 |
| motor_config | minthrottle | read/write (changed) | src/rfsuite/tasks/msp/api/motor_config.lua:12 |
| motor_config | maxthrottle | read/write (changed) | src/rfsuite/tasks/msp/api/motor_config.lua:13 |
| motor_config | mincommand | read/write (changed) | src/rfsuite/tasks/msp/api/motor_config.lua:14 |
| motor_config | motor_count_blheli | read only | src/rfsuite/tasks/msp/api/motor_config.lua:15 |
| motor_config | motor_pole_count_blheli | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:16 |
| motor_config | use_dshot_telemetry | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:17 |
| motor_config | motor_pwm_protocol | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:18 |
| motor_config | motor_pwm_rate | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:19 |
| motor_config | use_unsynced_pwm | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:20 |
| motor_config | motor_pole_count_0 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:21 |
| motor_config | motor_pole_count_1 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:22 |
| motor_config | motor_pole_count_2 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:23 |
| motor_config | motor_pole_count_3 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:24 |
| motor_config | motor_rpm_lpf_0 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:25 |
| motor_config | motor_rpm_lpf_1 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:26 |
| motor_config | motor_rpm_lpf_2 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:27 |
| motor_config | motor_rpm_lpf_3 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:28 |
| motor_config | main_rotor_gear_ratio_0 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:29 |
| motor_config | main_rotor_gear_ratio_1 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:30 |
| motor_config | tail_rotor_gear_ratio_0 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:31 |
| motor_config | tail_rotor_gear_ratio_1 | read/write (preserved) | src/rfsuite/tasks/msp/api/motor_config.lua:32 |
| esc_parameters_yge | esc_signature | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:10 |
| esc_parameters_yge | esc_command | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:10 |
| esc_parameters_yge | esc_model | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:10 |
| esc_parameters_yge | esc_version | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:10 |
| esc_parameters_yge | governor | read/write (changed) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:11 |
| esc_parameters_yge | lv_bec_voltage | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:11 |
| esc_parameters_yge | timing | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:11 |
| esc_parameters_yge | acceleration | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:11 |
| esc_parameters_yge | gov_p | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:12 |
| esc_parameters_yge | gov_i | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:12 |
| esc_parameters_yge | throttle_response | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:12 |
| esc_parameters_yge | auto_restart_time | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:12 |
| esc_parameters_yge | cell_cutoff | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:13 |
| esc_parameters_yge | active_freewheel | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:13 |
| esc_parameters_yge | esc_type | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:13 |
| esc_parameters_yge | firmware_version | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:13 |
| esc_parameters_yge | serial_number | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:14 |
| esc_parameters_yge | unknown_1 | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:14 |
| esc_parameters_yge | stick_zero_us | read/write (changed) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:14 |
| esc_parameters_yge | stick_range_us | read/write (changed) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:14 |
| esc_parameters_yge | unknown_2 | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:15 |
| esc_parameters_yge | motor_poll_pairs | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:15 |
| esc_parameters_yge | pinion_teeth | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:15 |
| esc_parameters_yge | main_teeth | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:15 |
| esc_parameters_yge | min_start_power | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:16 |
| esc_parameters_yge | max_start_power | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:16 |
| esc_parameters_yge | unknown_3 | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:16 |
| esc_parameters_yge | flags | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:16 |
| esc_parameters_yge | unknown_4 | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:17 |
| esc_parameters_yge | current_limit | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:17 |
| esc_parameters_yge | unknown_5 | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:23 |
| esc_parameters_yge | unknown_6 | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_yge.lua:23 |
| esc_parameters_hw5 | flight_mode | read/write (changed when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:10 |
| esc_parameters_hw5 | lipo_cell_count | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:11 |
| esc_parameters_hw5 | cutoff_type | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:12 |
| esc_parameters_hw5 | cutoff_voltage | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:13 |
| esc_parameters_hw5 | bec_voltage | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:14 |
| esc_parameters_hw5 | startup_time | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:15 |
| esc_parameters_hw5 | response_time | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:16 |
| esc_parameters_hw5 | gov_p_gain | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:17 |
| esc_parameters_hw5 | gov_i_gain | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:18 |
| esc_parameters_hw5 | auto_restart | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:19 |
| esc_parameters_hw5 | restart_time | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:20 |
| esc_parameters_hw5 | brake_type | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:21 |
| esc_parameters_hw5 | brake_force | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:22 |
| esc_parameters_hw5 | timing | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:23 |
| esc_parameters_hw5 | rotation | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:24 |
| esc_parameters_hw5 | active_freewheel | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:25 |
| esc_parameters_hw5 | startup_power | read/write (preserved when supported) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:26 |
| esc_parameters_hw5 | esc_signature | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:230 |
| esc_parameters_hw5 | command | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:231 |
| esc_parameters_hw5 | firmware_version | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:232 |
| esc_parameters_hw5 | hardware_version | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:233 |
| esc_parameters_hw5 | esc_type2 | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:234 |
| esc_parameters_hw5 | esc_type | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:235 |
| esc_parameters_hw5 | raw_strings | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:236 |
| esc_parameters_hw5 | model_name | read derived/metadata | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:243 |
| esc_parameters_hw5 | _itemBytes | read/write (preserved) | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:249 |
| esc_parameters_hw5 | _profile | read derived/metadata | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:252 |
| esc_parameters_hw5 | _layout | read derived/metadata | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:253 |
| esc_parameters_hw5 | _supported | read derived/metadata | src/rfsuite/tasks/msp/api/esc_parameters_hw5.lua:254 |

Local ESC-page duplication retained for a later migration:

- YGE: queueYgeReadActual decodes/caches the complete block; queueYgeRead invalidates
  the previous cache; queueYgeWrite checks read-before-write, copies the cached
  block, overlays page fields and builds the whole-block payload. packFlags remains
  page-specific. This YGE page currently does not queue a readback from its write
  acknowledgement; the shared module adds that verification and bounded cache retry.
- Hobbywing V5: queueHw5ReadActual decodes/caches the block and enables cache-error
  retry; queueHw5Read invalidates/reloads the cache; queueHw5Write checks prior read,
  overlays the full block, encodes it and calls queueHw5Read after acknowledgement.
  Those transaction responsibilities duplicate the new shared module. Both pages
  remain unchanged; their UI state and field adapters are outside this part.

## Governor write audit

This inventories settings changed by the governor step, rather than every field
serialized unchanged by the full-record API codecs. The four marked additions
extend the pinned Configurator wizard; they do not claim source parity.

| API | Fields changed | Scope |
| --- | --- | --- |
| `feature_config` | `enabledFeatures` bits 26 (governor) and 28 (frequency sensor) | Existing mode/source controls; source selection also works for filtering with governor Off. |
| `motor_config` | `use_dshot_telemetry` | Existing bidirectional DShot source control. |
| `governor_config` | `gov_mode`, `gov_throttle_type` | Existing mode/type controls. |
| `governor_profile` | `governor_headspeed` | **Addition beyond Configurator**: only edited configured PID profiles, Electric/Nitro only. |
| `governor_config` | `gov_spoolup_time`, `gov_spooldown_time`, `gov_recovery_time` | **Additions beyond Configurator**: Electric/Nitro editors, shared limits 0–600 / 0–600 / 0–100 raw deciseconds. |
| `set_pid_profile` | Selection byte | Existing sequential transaction reused for read-only entry and edited-profile saves; original selection restored. |
| `eeprom_write` | Empty payload | Existing save boundary after successful configuration writes. |

`bin/wizard/source-map.json` records all four additional writable fields and the
read-only filter dependencies. `audit_source.py` checks their API/source bindings
and named contracts. Contracts verify exact payloads, untouched profile fields,
profile selection/restoration, discard, failure before EEPROM and filter reads
without filter writes. `lib/governor_fields.lua` holds the page's extracted editor
limits and seconds formatter; wire parsing/encoding remains in the existing APIs.

The host's `buildScene` recognizes `hideSuiteFrame = true` on a page module. It
omits the native page/header while reserving space for its independent ARMED banner. Lifecycle, queue ownership
and RTN/EXIT remain in `ui/home.lua`; the native standalone/widget cancel event feeds
that dispatch. The page supplies its own Back/Continue/Save navigation.
Its `handlesDisconnect` opt-in also retains the visit through an expected reboot's
RF-link interruption. The wizard owns reconnection and stops desired overrides;
other pages keep the host's normal return-to-root behaviour.

Scene assembly is paced, and MSP callbacks only publish buffers. Live labels and
control properties read cached page state. Normal close releases visit state after cleanup; an external teardown retains the recovery marker.
STATUS refresh can preempt indexed jobs, saving/rollback transactions and wiring trials. A status older than three
seconds releases overrides before waiting for pending replies. Successful wiring
trials remain live for inspection until save/cancel/leave; STOP uses cleanup ownership.

No radio code uses `os`, coroutines, canvas drawing or image rotation.

*Documented against RFSuite 0.2.1 and the fixed Configurator reference recorded on
the page. This is a protocol/code review, not a physical-radio test.*
