---
title: Keys
sidebar_label: Keys
sidebar_position: 29
---

# Keys

Choose the dashboard's hardware shortcuts at fullscreen, including before the flight controller
connects. These choices belong to the radio and apply to every theme and model.
Out of the box, SYS opens the suite tool and TELE the quick menu; the other keys are the theme's.

## Where to find it

*System* → *Settings* → *Dashboard* → *Keys*. Always available, including without a flight controller.

## Settings

| Setting | What it does |
| --- | --- |
| PAGE >, PAGE <, MDL | One action per key, **Theme** by default. **Theme** leaves the key to the theme: it does what the theme binds, and nothing where the theme binds nothing — except the page keys, which then open the quick menu. **Nothing** disables the key. **Quick menu**, **Main menu**, **Flight log** and **Exit fullscreen** override any theme binding. |
| SYS | As above, **Main menu** by default. |
| TELE | As above, **Quick menu** by default. |

A radio without one of these keys never sends it; its saved choice still remains.

## Notes

- Save applies the choices to every model; no per-model copy is written. A key left on its
  default stores nothing, so SYS and TELE on **Theme** are stored as Theme.
- SYS and TELE hold their default for **every** theme, including themes whose full screen is
  the quick menu: SYS opens the suite tool there as well, and TELE answers with the quick menu
  that is already on screen. Put either on **Theme** to give it back to the theme.
- A theme binds keys in its full-screen build. Urban, Grid and Deck let the pilot bind them on
  their own *Keys* settings page, which only acts on keys left on **Theme** here. Default binds
  none, so on Default a key on **Theme** does nothing, the page keys aside.
- On the connection screen, global actions already work. A theme's bindings become available when
  that theme has built.
- An opened menu can be closed with its bound menu key. Short RTN keeps the current Back/Close
  behavior, and long RTN leaves fullscreen. A key on Theme does nothing while another view is on
  top unless the theme binds it to that view; a global action — a default included — still
  applies there. Nothing also consumes the key before LVGL sees it.
- While the suite tool or in-flight tuning owns the fullscreen, these shortcuts do not take its keys.
- Main menu is refused while armed. Flight log also requires its preview switch.
  The quick menu's FC writes stay hidden until the connection is ready and the model is disarmed.
- A failed SD-card save reports the error and leaves the page marked as unsaved.
- Unknown stored action values use the key's default. Existing theme configuration is not changed
  by this page.

## Related

- [Quick menu](../../../dashboard/quick-menu.md)
- [Dashboard themes](../../../dashboard/themes.md)

*Documented against RFSuite 0.2.1.*
