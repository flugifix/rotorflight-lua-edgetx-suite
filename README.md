# RFSuite for EdgeTX

This workspace contains the EdgeTX LVGL-based RFSuite UI.

## Current scope

- Responsive viewport abstraction for different display sizes.
- BorderLayout (north/south/west/east/center regions).
- GridLayout (rows, columns, spans, weighted tracks).
- FlowLayout (horizontal flow with wrap).
- Main application with:
  - Header area with Back and Help buttons.
  - Breadcrumb text in the blue header area.
  - Main card area (grid-based buttons) with icons.
  - Footer chip area (flow-based layout buttons).
- Dynamic menu registry (section/page based cards).
- Basic i18n runtime for `de` and `en`.

## Entrypoint

- Tool entrypoint source: `src/main.lua` (deployed as `SCRIPTS/TOOLS/rfsuite.lua`)
- Core package source: `src/rfsuite/` (deployed as `SCRIPTS/TOOLS/rfsuite-core/`)
- Widget source: `src/widgets/rfsuite/` (deployed as `WIDGETS/rfsuite/`)

## VS Code Run Configuration

- Run/Debug config: `RFSuite: Deploy to Simulator`
- Run/Debug config: `RFSuite: Deploy to Radio`
- Run/Debug config: `RFSuite: Deploy + Run Simulator (TX16S MK3)`
- Run/Debug config: `RFSuite: Deploy + Run Simulator (TX16S)`
- Run/Debug config: `RFSuite: Deploy + Run Simulator (TX15)`
- Task: `RFSuite: Deploy to Simulator`
- Task: `RFSuite: Deploy to Radio`
- Task: `RFSuite: Start EdgeTX Simulator (TX16S MK3)`
- Task: `RFSuite: Deploy + Start Simulator (TX16S MK3)`
- Task: `RFSuite: Start EdgeTX Simulator (TX16S)`
- Task: `RFSuite: Deploy + Start Simulator (TX16S)`
- Task: `RFSuite: Start EdgeTX Simulator (TX15)`
- Task: `RFSuite: Deploy + Start Simulator (TX15)`
- Deploy targets:
  - `simulator/SCRIPTS/TOOLS/rfsuite.lua`
  - `simulator/SCRIPTS/TOOLS/rfsuite-core/`
  - `simulator/WIDGETS/rfsuite/`

The radio deploy configuration uses the same copy logic, but writes into the mounted radio SD-card root configured via `rfsuite.radioSdPath`.

The run configuration executes a pre-launch deploy task that copies the tool entrypoint,
core package, and widget folder into the simulator SD card layout. This keeps the simulator
copy in sync for quick iteration.
The combined run configurations then start `simulator.exe` with one of these radio targets:

- `edgetx-tx16smk3`
- `edgetx-tx16s`
- `edgetx-tx15`

All simulator launch tasks use `--sd-path ${workspaceFolder}/simulator`.

### Simulator Path Setup (Per Developer)

The simulator executable path is centralized via the VS Code setting `rfsuite.simulatorPath`.
All start tasks in `tasks.json` use `${config:rfsuite.simulatorPath}`.

If your local Companion version/path differs, set it once in your **User Settings**
(`Preferences: Open User Settings (JSON)`):

Hint: press `Ctrl+Shift+P`, run `Preferences: Open User Settings (JSON)`, then add/update the value.

```json
{
  "rfsuite.simulatorPath": "C:\\Program Files (x86)\\EdgeTX\\Companion 2.12\\bin\\simulator.exe"
}
```

After that, all run configurations continue to work without editing task definitions.

### Radio SD Path Setup (Per Developer)

`RFSuite: Deploy to Radio` now auto-detects the mounted radio storage when possible (same idea as Ethos-style drive detection).

If auto-detection does not find the correct target on your system, set the mounted SD-card root once in your **User Settings**:

```json
{
  "rfsuite.radioSdPath": "E:\\"
}
```

This path must point to the root of the mounted radio storage, not to `SCRIPTS` itself. The `RFSuite: Deploy to Radio` run configuration then updates:

- `SCRIPTS/TOOLS/rfsuite.lua`
- `SCRIPTS/TOOLS/rfsuite-core/`
- `WIDGETS/rfsuite/`
- `SOUNDS/rfsuite/`

## Audio Setup

RFSuite provides status and event-based audio announcements (e.g., arming state, governor mode, profiles, battery/fuel alerts).

### Installation of Audio Packs
To use the built-in announcements, copy the audio files from the repository to your SD card:
1. Locate the `src/rfsuite/audio/` directory in the project.
2. Copy the contents (including language subfolders like `en/`, `de/`) to the `/SOUNDS/rf/` directory on your SD card.
   - Example path: `/SOUNDS/rf/en/evt/armed.wav`

### Model Announcements
You can have the radio announce the name of your model when starting the RFSuite tool.
1. Create or obtain a `.wav` file for your model.
2. Place the file directly into the `/SOUNDS/` directory on your SD card.
3. **Naming:** The file name must match your model name in EdgeTX (e.g., `Kraken.wav`). Spaces in the model name can be replaced by underscores (e.g., `My_Heli.wav`).

### Model Images
RFSuite can display model-specific images in **dashboard widgets**.
The image resolution follows this priority:
1. **FBL Model Name:** An image in `/IMAGES/` matching the name reported by Rotorflight (e.g., `/IMAGES/Kraken.png`). Spaces can be replaced by underscores.
2. **EdgeTX Model Image:** The image assigned to the model memory in EdgeTX settings.
3. **Fallback:** The default Rotorflight logo.

**Features:**
- **Automatic Scaling:** The image is automatically scaled to fit the widget box.
- **Model Name Display:** If a model name is retrieved from the flight controller, it is displayed in a small font below the image, and the image is automatically adjusted to make room.

**Requirements:**
- **Format:** `.png` (recommended) or `.jpg`.
- **Location:** All images must be in the `/IMAGES/` directory at the root of your SD card.
- **Dimensions:** For best results, use standard EdgeTX model image sizes (e.g., 192x114 or 160x128).

### Activation
By default, some announcements might be disabled. To configure them:
1. Open the **RFSuite** tool on your radio.
2. Navigate to **System** -> **Settings** -> **Audio** -> **Audio Events**.
3. Enable the desired events (e.g., `Model Announcement`, `Arming-Flags`, etc.).

## Notes

- The demo script returns `useLvgl = true` and expects EdgeTX with LVGL support.
- The script is packaged as a TOOLS script (`-- TNS|RFSuite|TNE`) and runs fullscreen.
- Menu cards and breadcrumb are now built from `src/rfsuite/app/manifest.lua` through `src/rfsuite/app/menu_registry.lua`.
- Main screen implementation lives in `src/rfsuite/ui/home.lua`.
- i18n lookups are handled by `src/rfsuite/i18n/init.lua` using locale bundles in `src/rfsuite/i18n/`.

## Settings Controls

- Shared settings controls live in `src/rfsuite/ui/controls.lua`.
- Boolean settings use native LVGL `toggle` via `Controls.appendRadioSwitch(...)`.
- Numeric settings use native LVGL `numberEdit` via `Controls.appendNumberField(...)`.
- Choice settings use native LVGL `choice` via `Controls.appendComboSelect(children, x, y, w, labelText, options, selectedValue, onSelect)`.
- Settings rows use a shared row height derived from `math.max(44, UI_ELEMENT_HEIGHT + 12)` so toggle, number, and choice controls align consistently.
- Choice popups are now handled by EdgeTX itself; pages no longer need local open/close popup state for `appendComboSelect(...)`.

## License

This project is licensed under the GPL-3.0 license. See [LICENSE](LICENSE).
