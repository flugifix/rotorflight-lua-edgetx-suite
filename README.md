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

- `src/main.lua` (tools script name: `RFSuite`)

## VS Code Run Configuration

- Run/Debug config: `RFSuite: Deploy to Simulator`
- Run/Debug config: `RFSuite: Deploy + Run Simulator (TX16S MK3)`
- Task: `RFSuite: Deploy to Simulator`
- Task: `RFSuite: Start EdgeTX Simulator (TX16S MK3)`
- Task: `RFSuite: Deploy + Start Simulator (TX16S MK3)`
- Deploy target: `simulator/SCRIPTS/TOOLS/rfsuite`

The run configuration executes a pre-launch deploy task that copies all files from `src/`
to the simulator tool folder. This keeps the simulator copy in sync for quick iteration.
The combined run configuration then starts `simulator.exe` using `--radio edgetx-tx16smk3`
and `--sd-path ${workspaceFolder}/simulator`.

## Notes

- The demo script returns `useLvgl = true` and expects EdgeTX with LVGL support.
- The script is packaged as a TOOLS script (`-- TNS|RFSuite|TNE`) and runs fullscreen.
- Menu cards and breadcrumb are now built from `src/rfsuite/app/manifest.lua` through `src/rfsuite/app/menu_registry.lua`.
- Main screen implementation lives in `src/rfsuite/ui/home.lua`.
- i18n lookups are handled by `src/rfsuite/i18n/init.lua` using locale bundles in `src/rfsuite/i18n/`.
