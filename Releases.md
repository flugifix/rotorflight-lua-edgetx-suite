# 0.1.4

### Bug Fixes & Improvements
- **Blackbox Status Page**:
  - Fixed a nil index error (`attempt to index a nil value (upvalue 'SdcardSummaryApi')`) occurring when navigating away or closing the Blackbox status page while MSP summary queries are in flight.
  - Safeguarded asynchronous MSP response callbacks against page unloads and nil module references.
- **Controls & Modes Setup (`setup/controls/modes`)**:
  - Standardized control heights for range inputs and action buttons (`+ Add`, `Set`, `X`, AUX/Logic choices, Min/Max numbers) to match the standard widget height used in the Rates and PIDs tables.
  - Fixed focus loss when editing numbers or dropdowns by removing premature full-page rebuild calls from value setters.
  - Expanded row heights and inter-row spacing to prevent separator lines from intersecting input controls.
- **Controls & Failsafe Setup (`setup/controls/failsafe`)**:
  - Standardized mode choice and failsafe pulse value inputs to native framework widget dimensions.
  - Adjusted row height to `56 px` with centered vertical offsets to ensure clean visual separation and avoid divider line clipping.
- **Hobbywing Platinum V5 ESC Configuration (`setup/esc_motors/esc_tools/hw5`)**:
  - Fixed MSP parameter parsing and write serialization by implementing dynamic `itemBytes` profile layouts (`DEFAULT_LAYOUT`, `HW1132_LAYOUT`, `HW1128_LAYOUT`, `OPTO_LAYOUT`) matching Rotorflight firmware specifications.
  - Fixed shifted and corrupted field values on OPTO ESCs (130A HV, 200A HV, 260A HV) caused by omitted BEC voltage field in OPTO telemetry payloads.
  - Corrected raw offset translation for `startup_time` (`value = raw + 4`) on reading and writing.
  - Fixed inverted `Active Freewheel` option mapping (`0 = Enabled`, `1 = Disabled`).
  - Added support for `response_time` setting (1–10) on compatible ESC models (e.g. HW1132).
  - Improved ESC model string decoding in `init.lua` to read full 31-byte model identification.
  - Corrected profile detection and layout field filtering in `profile.lua`.

# 0.1.3

### Bug Fixes & Improvements
- **Dashboard & Themes**:
  - Fixed model-specific dashboard theme switching (`model_override`) to immediately take effect without requiring a radio restart.
  - Corrected theme resolution fallback when model override is active and inflight/postflight themes are unassigned, ensuring the model's preflight theme remains active.
  - Ensured theme configuration adjustments (e.g. BEC voltage bounds, RPM limits, ESC temperature thresholds) are saved synchronously to both global (`preferences.ini`) and model-specific (`<mcu_id>.ini`) configuration files.
  - Added inter-process reload signaling between the configuration tool and standalone dashboard widgets using EdgeTX Global Variables (GV9 for FM0/FM8) and memory reload flags.
  - Fixed runtime crash after FBL initialization caused by single-argument `lcd.RGB` call in `@srb-rc` theme and safeguarded color conversion helpers in `common.lua` and `gauge.lua`.
  - Removed obsolete full-screen placeholder boxes in `@srb-rc` (`preflight.lua`, `inflight.lua`, `postflight.lua`) that caused unintended `"--"` text labels across the display.
  - Adjusted Postflight grid layout from 7 rows to 3 rows to eliminate the bottom background gap and utilize 100% of the screen height.
  - Corrected theme fallback loader in `runtime.lua` to properly fall back to the active flight mode's default theme script instead of non-existent `widget.lua`.
- **Save Progress & Localization**:
  - Fixed translation inlining for the save progress dialog (`app.saving` -> "Speichere...", `app.saving_settings` -> "Einstellungen werden angewendet").
  - Fixed English language package deployment by standardizing internal code fallbacks to English across settings pages (`settings_general`, `settings_audio_events`, `settings_audio_switches`, `settings_audio_timer`, `settings_localization`).
  - Enhanced the `precompile_i18n.py` build script to capture and inline dynamic `tr()` helper functions, `ctx.i18n` lookups, and section/item table definitions (`titleKey`/`titleFallback`, `labelKey`/`labelFallback`) during deployment and packaging.
- **Scorpion ESC Parameter Writing**:
  - Completed MSP 218 payload structure for Scorpion ESC (added missing `stick_max` and `stick_zero` fields to form full 84-byte payload) and named `serial_number`/`firmware_version` fields correctly to fix parameter save failures.
- **ELRS Link & Telemetry**:
  - Fixed ELRS packet rate parsing, RF link synchronization, and telemetry reload handling.
- **Audio & Telemetry**:
  - Restored model name and battery/initial fuel announcements upon model reconnect (e.g. plugging in a new battery) by resetting audio tracking states on connect and disconnect edges.
  - Enabled `name`, `battery_config`, and `smartfuel_config` background OnConnect tasks in both tool and widget contexts so battery capacity and model names are immediately available.
  - Added fallback to EdgeTX radio model name in `announceModelName()` if the FBL model name has not yet been received via MSP.
  - Aligned fuel audio callout behavior in the RFSuite tool with the dashboard widget by prioritizing Smart Fuel (`SmFt` / `smartfuel`) telemetry over standard fuel (`Bat%` / `fuel`) and adding `smartfuel = "SmFt"` to sensor aliases.
  - Renamed fuel callout option "Default (Only at 10%)" to "Only at 10%" ("Nur bei 10%") in audio event settings for clearer option distinction.
- **Deployment & Tooling**:
  - Supported configurable deployment language via VS Code settings (`rfsuite.deploy.language`) and build tasks.

# 0.1.2

### Performance & Memory Optimizations
- **Module & Singleton Memoization (`require.lua`)**:
  - Implemented centralized `rfsuite.require` module loader with bytecode and instance memoization to eliminate redundant disk reads and Lua compilations.
  - Integrated memoization into Tools entrypoint, telemetry widgets, background tasks, and dashboard runtime.
- **Dashboard Startup Pacing & Instruction Budget**:
  - Preloaded and memoized all dashboard object wrappers and subrenderers (`text`, `image`, `time`, `gauge`).
  - Removed artificial 14-box cap in simulator, allowing full layouts to render smoothly.
- **Garbage Collection & GC-Churn Reduction**:
  - Streamlined `Engine.renderKey` dirty-checking to eliminate intermediate table arrays and string allocations during refresh cycles.
  - Guarded debug log string concatenations in hot telemetry polling paths.
  - Eliminated anonymous closure allocations in repetitive MSP polling loops (`msp/queue.lua`) and background event runners.
- **SD Card I/O Reduction & Asset Cleanup**:
  - Removed redundant `io.open`/`close` probes in `help_registry.lua`.
  - Added in-memory path caches for audio WAV events and model images to avoid repeated file system checks.
  - Cleaned up obsolete legacy root icons from `src/rfsuite/assets/icons/`.

# 0.1.1

### Bug Fixes & Improvements
- **ESC Forward Programming & MSP Communication**:
  - Removed 4-Way Interface (`4wif_esc_fwd_prog`, MSP 244 target=100) from non-4WIF ESC manufacturers (XD-Fly, OMP, ZTW, Hobbywing Platinum V5, YGE, Scorpion, Flyrotor), eliminating motor beeping and communication timeouts.
  - Corrected header byte layout (`esc_version` before `esc_model`) in `esc_parameters_xdfly.lua`, `esc_parameters_omp.lua`, and `esc_parameters_ztw.lua`.
  - Fixed Governor P & I Gain active field mask indices for XD-Fly, OMP, and ZTW.
- **Dynamic On-Connect ESC Telemetry Detection**:
  - Added background OnConnect task `esc_sensor_config.lua` (with tool-only execution context) to query and dynamically enable active ESC tiles in the tools menu.
- **Audio & Telemetry Reliability**:
  - Restored `Audio.process` execution in configuration tool for announcements.
  - Fast-tracked simulator sensor reloads (0.5s interval).

# 0.1.0

### Features
- **Telemetry Flight Logs & Dashboard (`diagnostics/flight_logs`)**:
  - Implemented flight log browser and analytical dashboard to inspect EdgeTX CSV log files directly on the radio.
  - Added statistics calculations including min/max/average cell voltages, battery capacity consumption, RPM, temperatures, and flight durations.
  - Added interactive `LoadingOverlay` with non-blocking incremental parsing and proactive memory cleanup to keep the UI responsive on large CSV files.
- **RFSuite EdgeTX Updater Tool & CI**:
  - Added standalone and integrated EdgeTX Updater tool for automatic online and local updating of RFSuite packages.
  - Automated detection of available languages from repository branches and release tags.
  - Added multi-language CI build workflows and packaging scripts.
- **Governor Setup Pages**:
  - Ported Governor General setup page (`governor/general`).
  - Ported Governor Ramp Time configuration (`governor/ramps`).
  - Ported Governor Filters setup page (`governor/filters`).
  - Ported Governor Bypass Curve configuration (`governor/bypass`).
- **Dynamic ESC Sensor Detection**:
  - Added background `esc_sensor_config` task triggered on connection to query and identify active ESC telemetry protocol.
- **Manufacturer ESC Tools Integration**:
  - Ported and integrated full ESC configuration suites for Bluejay, BLHeli_S, Flyrotor, Hobbywing V5, OMP, Scorpion, XD-Fly, YGE, and ZTW.

### Localization (i18n)
- Localized flight tuning pages (PIDs, Rates, Governor, Rates Advanced) in German and English with fallback cleanup.

### Bug Fixes & Performance
- **Telemetry CSV Parsing Accuracy**: Improved header validation, outlier filtering (e.g. 0 RPM spikes), and memory efficiency during log analysis.
- **Reconnect Performance**: Resolved telemetry reconnect slowdowns and memory buildup using proactive garbage collection and cached LQ checks.

# 0.0.2

### Features
- **Compile-time Translation Inlining**: Introduced static translation inlining at compile time, simplified settings, and bumped version to 0.0.2.
- **Fuel Announcements**: Added initial fuel announcement and implemented differentiation between electric and gas/glow models in fuel callouts.
- **Developer Logging**: Made exit shutdown logging conditional on the developer `debug_level`.
- **Dynamic ESC Tools Lockout**: Automatically enable/disable manufacturer-specific ESC Tool menu tiles based on the active telemetry protocol queried via `esc_sensor_config`.
- **YGE ESC 12V BEC Support**: Dynamically adjust BEC voltage range up to 12.0V for supported models (205 HVT, 205 HVT BEC, 165 HVT, Aureus 105v2, Aureus 135v2, Saphir 155v2), capping older/standard models at 8.4V and synchronizing the `flags_bec12v` bit automatically.

### Security & Armed State (Model Armed)
- **Model Armed Blocking**:
  - Implemented `isModelArmed()` check in `home.lua` using the passive ARM telemetry sensor.
  - Blocked `MspRuntime.tick()` and active page wakeup from executing when model is armed to avoid serial connection hangs.
  - Added a full-screen armed warning screen at boot and during runtime if the model is armed.
  - Blocked subpage navigation, reloading, and saving actions with a warning dialog when armed.
  - Added German & English localizations for the armed title and warning messages.
- **Armed Warning Screen & Telemetry Check Optimization**:
  - Kept `MspRuntime.tick()` running when armed to drain the serial RX buffer and prevent telemetry loss.
  - Wrapped the armed warning screen in a standard page with a Close button and back-navigation support.
  - Checked `getRSSI()` to detect telemetry loss, skipping the check in the simulator to allow simulation of the armed state.

### Performance
- **Lag Reduction**: Cached compiled Lua chunks and optimized the exit cleanup sequence to resolve lags.

### Bug Fixes
- **Audio Callouts & Alarms**:
  - Corrected empty battery warning path for electric models to `"stat/alerts/lowbat.wav"` ("Flugakku leer") instead of the radio's native low battery warning.
  - Optimized fuel threshold countdown logic to jump directly to the lowest crossed threshold without stepped intermediate announcements.
- **Focus Preservation & Page Rebuilds**:
  - Redesigned `buildSessionSignature()` across all ESC pages (AM32, BLHeli_S, Bluejay, Flycolor, Hobbywing V5, OMP, Scorpion, XD-Fly, YGE, ZTW) to prevent background wakeup loops from stealing focus while editing fields.
  - Added value-change guards in `controls.lua` for number fields and combo selectors to ignore layout-time init events and prevent unintended dirty states.
- **Telemetry Freezes & Hangs**:
  - Unconditionally run `Events.wakeup()` in `home.lua` to keep the background `telemetry_bg` task running.
  - Skip onconnect tasks when armed in `tasks/events/runtime.lua` to prevent FBL configuration requests.
  - Run the `telemetry_bg` task even when armed to parse custom CRSF frames and update radio sensors.
  - Skip startup version and UID reads when armed in `tasks/msp/runtime.lua`.
- **Audio Processing**: Enabled `Audio.process` in the configuration tool for live voice feedback (profiles, rates, telemetry).
- **ESC Configuration (AM32)**:
  - Restored ESC target to 100 on `am32/page.lua` close and performed a post-save reset cycle to apply and save settings.
  - Fixed MotorConfigApi command reference in `am32/page.lua` (using `.command` instead of `.readCommand`).
  - Implemented retry logic for motor config reads when the FBL returns empty buffers.
  - Added German & English localizations for ESC config loading and saving messages.
- **Alignment Page**:
  - Added guards for `ui.runtime` checks in `alignment/page.lua` async callbacks to prevent nil errors after page close.

### UI & Miscellaneous
- **Layout Redesign**: Redesigned alignment layout to two rows, widened Roll/Nick/Yaw fields and Magnetometer combobox to 160px.
- **Git Config**: Updated `.gitignore`.
