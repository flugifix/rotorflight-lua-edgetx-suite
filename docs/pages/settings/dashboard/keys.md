---
title: Keys
sidebar_label: Keys
sidebar_position: 29
---

# Keys

Choose the dashboard's hardware shortcuts at fullscreen, including before the flight controller
connects. These choices belong to the radio and apply to every theme and model.

## Where to find it

*System* → *Settings* → *Dashboard* → *Keys*. Always available, including without a flight controller.

## Settings

| Setting | What it does |
| --- | --- |
| PAGE >, PAGE <, MDL, SYS, TELE | One action per key. **Theme** (default) uses the theme binding, then the host fallback. **Nothing** disables the key. **Quick menu**, **Main menu**, **Flight log** and **Exit fullscreen** override any theme binding. A radio without one of these keys never sends it; its saved choice still remains. |

## Notes

- Save applies the choices to every model; no per-model copy is written. Saving Theme stores no override.
- A theme may bind keys in its manifest or fullscreen build. Default uses SYS for the suite tool,
  TELE for the quick menu and MDL for nothing. Without another binding the host's page keys open the menu.
- A theme's own views remain theme bindings, rather than choices on this global page.
- On the connection screen, explicit global actions and declared theme bindings already work.
  A free-form theme's build-time bindings become available when that theme has built.
- An opened menu can be closed with its bound menu key. Short RTN keeps the current Back/Close
  behavior, and long RTN leaves fullscreen. Nothing also consumes the key before LVGL sees it.
- While the suite tool or in-flight tuning owns the fullscreen, these shortcuts do not take its keys.
- The suite tool is refused while armed. Flight Log also requires its preview switch.
  The quick menu's FC writes stay hidden until the connection is ready and the model is disarmed.
- A failed SD-card save reports the error and leaves the page marked as unsaved.
- Unknown stored action values use Theme. Existing theme configuration is not changed by this page.

## Related

- [Quick menu](../../../dashboard/quick-menu.md)
- [Dashboard themes](../../../dashboard/themes.md)

*Documented against RFSuite 0.2.1.*
