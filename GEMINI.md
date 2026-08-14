# RFSuite for EdgeTX - Project Instructions

This project is a Lua-based configuration and dashboard suite for Rotorflight, specifically designed for EdgeTX radios equipped with LVGL (Light and Versatile Graphics Library) support.

## Project Overview

RFSuite provides a modern, touch-friendly interface for configuring Rotorflight flight controllers and viewing real-time telemetry.

### Core Technologies
- **Lua**: Primary scripting language.
- **EdgeTX Lua API**: Specifically the LVGL-enabled subset for high-performance graphics.
- **MSP (Multiwii Serial Protocol)**: Communication protocol with the flight controller.
- **LVGL**: Underlying graphics library used via the EdgeTX abstraction.

### Architecture
- **`src/main.lua`**: Entry point for the EdgeTX "TOOLS" menu. It boots the home screen from the core package.
- **`src/rfsuite/`**: The core package (deployed as `rfsuite-core`).
  - **`app/`**: Application-level logic, including the menu manifest and registry.
  - **`core/`**: Framework fundamentals like the viewport abstraction and layout engines (Grid, Flow, Border).
  - **`ui/`**: User interface screens and reusable controls (`controls.lua`).
  - **`lib/`**: Supporting libraries for logging, preferences (INI parsing), and sensors (telemetry mapping).
  - **`tasks/`**: Background tasks for MSP communication and telemetry synchronization.
  - **`widgets/`**: Dashboard widgets and runtime logic.
- **`src/widgets/rfsuite/`**: Standalone EdgeTX telemetry widgets.

## Building and Running

The project uses VS Code tasks for deployment and testing in the EdgeTX Simulator.

### Key VS Code Tasks
- `RFSuite: Deploy to Simulator`: Copies `src/` files to the local `simulator/` SD card structure.
- `RFSuite: Start EdgeTX Simulator`: Launches the simulator pointing to the project's `simulator/` directory.
- `RFSuite: Deploy + Run Simulator`: Combined task for quick iteration.
- `RFSuite: Deploy to Radio`: Deploys to a physical radio's SD card (path configurable in VS Code settings via `rfsuite.radioSdPath`).

### Deployment Structure
- **Main Tool**: `SCRIPTS/TOOLS/rfsuite.lua`
- **Core Package**: `SCRIPTS/TOOLS/rfsuite-core/`
- **User Config**: `SCRIPTS/TOOLS/rfsuite.user/`
- **Widgets**: `WIDGETS/rfsuite/`

## Development Conventions

### Module Loading
Modules are typically loaded using `loadScript` with absolute paths to ensure compatibility with the EdgeTX environment.
```lua
local Sensors = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/sensors.lua", "t"))()
```

### UI Development
The framework uses a declarative approach for UI building. Reusable components in `src/rfsuite/ui/controls.lua` append widget definitions to a `children` table which is then passed to `lvgl.build()`.
- Use `Controls.appendRadioSwitch` for booleans.
- Use `Controls.appendNumberField` for numeric settings.
- Use `Controls.appendComboSelect` for dropdowns/choices.

### Performance & Memory
- **Memory Management**: Explicitly trigger `collectgarbage("collect")` after large I/O or JSON operations.
- **Telemetry Optimization**: Use `Sensors.getValue(name)` which includes miss-caching to prevent CPU limit errors on physical hardware.
- **CPU Limits**: Keep the `refresh()` loop of widgets and UI pages efficient. Avoid redundant `getValue` calls.

### Localization (i18n)
- Strings are localized via files in `src/rfsuite/i18n/`.
- Use the `@i18n(key)@` syntax in manifests or the `i18n.t(key)` function in code.

### Logging
Use the centralized `Log` library for consistent output:
```lua
local Log = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/log.lua", "t"))()
Log.emit("tag", "message", "info") -- levels: info, debug, warn, error
```

## Telemetry & MSP
- **Sensors**: Centralized in `src/rfsuite/lib/sensors.lua`. Maps 4-character OpenTX/EdgeTX sensor names to human-readable internal aliases.
- **MSP Tasks**: Background communication logic lives in `src/rfsuite/tasks/msp/`.
