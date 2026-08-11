# Changelog

All notable changes to the RFSuite project since 2026-07-29.

## [0.0.2] - 2026-08-11

### Features
- **Compile-time Translation Inlining**: Introduced static translation inlining at compile time, simplified settings, and bumped version to 0.0.2.
- **Fuel Announcements**: Added initial fuel announcement and implemented differentiation between electric and gas/glow models in fuel callouts.
- **Developer Logging**: Made exit shutdown logging conditional on the developer `debug_level`.

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
- **Telemetry Freezes & Hangs**:
  - Unconditionally run `Events.wakeup()` in `home.lua` to keep the background `telemetry_bg` task running.
  - Skip onconnect tasks when armed in `tasks/events/runtime.lua` to prevent FBL configuration requests.
  - Run the `telemetry_bg` task even when armed to parse custom CRSF frames and update radio sensors.
  - Skip startup version and UID reads when armed in `tasks/msp/runtime.lua`.
- **Audio Processing**: Deactivated `Audio.process` in the configuration tool.
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
