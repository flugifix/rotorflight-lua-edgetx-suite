# RFSuite for EdgeTX (Prototype)

This workspace contains a first implementation step for an EdgeTX LVGL-based RFSuite UI.

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
- Dynamic menu registry prototype (section/page based cards).
- Basic i18n runtime for `de` and `en`.

## Entrypoint

- Tool entrypoint source: `src/main.lua` (deployed as `SCRIPTS/TOOLS/rfsuite.lua`)
- Core package source: `src/rfsuite/` (deployed as `SCRIPTS/TOOLS/rfsuite-core/`)
- Widget source: `src/widgets/rfsuite/` (deployed as `WIDGETS/rfsuite/`)

## VS Code Run Configuration

- Run/Debug config: `RFSuite: Deploy to Simulator`
- Run/Debug config: `RFSuite: Deploy + Run Simulator (TX16S MK3)`
- Run/Debug config: `RFSuite: Deploy + Run Simulator (TX16S)`
- Run/Debug config: `RFSuite: Deploy + Run Simulator (TX15)`
- Task: `RFSuite: Deploy to Simulator`
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
- Settings rows use an enlarged shared row height derived from `ROW_H` and `NUMBER_H` so toggle, number, and choice controls align consistently.
- Choice popups are now handled by EdgeTX itself; pages no longer need local open/close popup state for `appendComboSelect(...)`.
- Save button state is driven by page-local `ui.dirty`; pages may trigger a one-time rebuild on the first dirty transition so the header refreshes without rebuilding on every edit.

## License

This project is licensed under the GPL-3.0 license. See [LICENSE](LICENSE).
