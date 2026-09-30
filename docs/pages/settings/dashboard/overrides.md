---
title: Model Overrides
sidebar_label: Model Overrides
sidebar_position: 25
---

# Model Overrides

The theme settings the connected model uses instead of the standard ones. The page lists every
setting the model changes, next to the standard value it replaces, lets each of them be reset,
and opens the settings of each theme the model draws for this model alone.

## Where to find it

*System* → *Settings* → *Dashboard* → *Settings* → *Model Overrides*, the first tile of that grid.

The tile is there only while a flight controller is connected and model overrides are on for
its model: *Allow model overrides* and *Overrides for this model* on
[*Design*](theme.md), or — on a card that has not stored those switches yet — a model that
already has a theme or theme settings of its own. The grid checks this when it is opened, so a
switch turned on under *Design* shows the tile the next time the grid is entered.

## Settings

| Setting | What it does |
| --- | --- |
| *Model:* and the name | The model the page is about: the craft name the flight controller reports, or the radio's model name where it reports none. |
| *(one row per setting)* | The theme, the setting and the model's value, followed by the standard value it replaces — *standard* and the radio's value, or *theme default* where the radio has none. |
| Reset | Removes this one value from the model. The model then uses the standard value, and follows it when the standard changes later. Saved at once. |
| Reset all | Removes every theme setting of the model, after asking. Saved at once. |
| *(one row per theme the model draws)* | The flight phases the theme is drawn in — *All flight phases*, or the phases it covers when *Per-Phase Themes* gives a phase a theme of its own — and a button with the theme's name that opens its settings for this model. The settings page's first line reads *Overrides for this model*. |

With no row to show, the page says the model uses the standard values.

Only the themes this model draws are listed: its own theme for each phase, or the standard theme
where it has none. A setting of any other theme would be stored and never shown. When none of
them has settings, the page says so.

## Notes

- **Only what differs is stored.** Saving a theme's page for this model stores the values that
  differ from the standard — the radio's value where it has one, the theme's default otherwise —
  and removes the ones that are equal. The list therefore shows what the model changes, and a
  later change of the standard reaches every value the model does not change.
- A card from an earlier version stored every value of a theme saved while a flight controller
  was connected, so its list can show rows whose value equals the standard. Saving that theme
  once from here, or resetting the rows, removes them.
- A reset does not turn overrides off: the model keeps *Overrides for this model* on, and its
  theme choice on *Design* is not touched. Turning overrides off is done on *Design*, and keeps
  the values.
- A row whose theme is no longer installed is still listed, as *Theme not installed*, so it can be
  reset.
- The page needs the flight controller. When the connection is lost the tool returns to the
  start screen; a theme page opened for the model that is left without the model's file refuses
  to save rather than writing into the standard values.

## Related

- [Design](theme.md) — the switches that turn model overrides on.
- [Settings](settings.md) — the standard theme settings.

*Documented against RFSuite 0.1.7.*
