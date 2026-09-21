---
title: Adding a dashboard theme
sidebar_label: Dashboard themes
sidebar_position: 60
---

# Adding a dashboard theme

A dashboard theme is a folder with a manifest and one module per flight phase. The manifest
says what the theme is called and which module belongs to which phase; each module declares a
grid and a list of boxes, and the engine turns that into the LVGL node list the widget hands
to the radio. Nothing in a theme draws anything itself.

This page is the contract: the folder, the manifest keys, **what puts the widget into each of
the three phases**, the shape a phase module returns, the box vocabulary, the rule for a value
given as a function, and the per-theme settings page. What a pilot needs in order to copy and
edit a theme is [user themes](../dashboard/user-themes.md); this page is the source-level
version of the same thing, plus what a theme shipped in this repository additionally owes.

## Where a theme lives

| Kind | In this repository | On the card |
| --- | --- | --- |
| Shipped | `src/rfsuite/widgets/dashboard/themes/<folder>/` | `/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/<folder>/` |
| User | not in this repository | `/SCRIPTS/TOOLS/rfsuite.user/dashboard/<folder>/` |

Both are scanned the same way, shipped first, and a theme is addressed everywhere by the path
`<source>/<folder>` — `system/default`, `user/mytheme`. That string is what a preference
stores, what the theme selector resolves and what the per-theme settings are keyed on.

The scan (`app/pages/settings/dashboard/lib.lua`, `scanThemes`) takes every entry of the
folder that is not `.` or `..` and whose name does not end in a dotted extension, loads
`<folder>/init.lua`, and accepts the folder as a theme when that returns a table with a
string `name`. A folder with no readable `init.lua` is skipped silently — it appears in the
log at *DEBUG*, and nowhere else.

`app/pages/settings/dashboard/theme_index.lua` is a checked-in list of the shipped themes and
is read **only when the scan found nothing at all**, which is the case on a radio whose
firmware offers neither `dir()` nor `system.listFiles`. A new shipped theme therefore needs a
row there as well, or it is invisible on exactly those radios.

## The manifest: `init.lua`

`init.lua` returns a flat table. It is loaded by the theme selector to list the theme, and by
the widget to find the module for the phase it is in.

| Key | Type | What it does |
| --- | --- | --- |
| `name` | string | The name in the theme selector. Required: a table without it is not a theme. |
| `preflight` | string | File name of the preflight module, relative to the theme folder. |
| `inflight` | string | File name of the inflight module. |
| `postflight` | string | File name of the postflight module. |
| `configure` | string | File name of the per-theme settings module. Omit it and the theme has no settings page. |
| `pages` | table | Optional. Splits the theme's settings into pages, one tile each. See [Splitting the settings into pages](#splitting-the-settings-into-pages). |
| `standalone` | boolean | `true` keeps the theme off the *Dashboard* → *Settings* page even if it declares `configure`. |

Beside it, `icon.png` is the tile the theme selector draws. The path is built from the folder
name and is not checked before use, so a theme without one shows an empty tile rather than an
error.

```lua
local init = {
  name = "Default",
  preflight = "preflight.lua",
  inflight = "inflight.lua",
  postflight = "postflight.lua",
  configure = "configure.lua",
  standalone = false,
}

return init
```

## What puts the widget into each phase

The phase is not something a theme chooses or a pilot sets. It is computed once per background
pass from the flight controller's own telemetry, in `computeFlightMode`
(`src/rfsuite/widgets/dashboard/runtime.lua`), out of four readings: the arm flag, the governor
state, the throttle percentage, and — with the governor off — headspeed and current.

The arm flag is the spine. It comes from the `armflags` sensor, and the widget keeps the
previous pass's value beside it, so an arm and a disarm are edges rather than states.

| Phase | Reached when |
| --- | --- |
| `preflight` | Not armed and no inflight phase has been reached in this armed session. This is also the phase the widget starts in, the phase on the pass the model arms, and the phase an armed model stays in until one of the inflight conditions below is met. |
| `inflight` | Armed, and — on a later pass than the arm edge — the governor is active, or the throttle is above its threshold, or the direct-drive condition is met. |
| `postflight` | Not armed, and the inflight phase had been reached in the armed session that just ended. |

**Arming alone does not leave preflight.** The pass on which the arm flag goes from false to
true returns `preflight` and clears the inflight latch, so the ground screen stays up through
spool-up. This matches what the same dashboard does on the other radio platform, and it is why
a model that is armed on the bench and never spooled shows the preflight screen the whole time
and produces no postflight screen on disarm.

The three inflight conditions, any one of which is enough:

| Condition | Reading | Trigger |
| --- | --- | --- |
| Governor active | `governor` state | between `4` and `8` inclusive |
| Throttle | `throttle_percent` | above `35` |
| Direct drive | `governor` state `0` or `100` (off/disabled) **and** any of headspeed `rpm` ≥ `500`, `current` ≥ `8` A, `throttle_percent` ≥ `8` | any one of the three |

Once any of them has been true, a latch is set and the phase stays `inflight` for the rest of
the armed session — a governor dropping out or the throttle coming back through the threshold
in autorotation does not send the screen back to preflight. The latch is cleared on the next
arm edge, and on the flight controller reconnect edge; the disarm hands it to the postflight
phase, which is what makes a landing produce a summary screen and a bench arm not produce one.

Two consequences worth knowing before writing a theme:

- **The postflight screen outlives the link.** While the inflight latch is set and the flight
  controller is no longer answering, the widget stops reading telemetry rather than letting the
  values decay, so the summary a pilot walks back to the bench with keeps standing. A postflight
  module can rely on the last flight's numbers still being there; it cannot rely on anything live.
- **A model that never publishes `armflags` never leaves preflight.** The arm reading is what
  every phase decision is built on, and the widget deliberately distinguishes *read as disarmed*
  from *never read at all*.

### What a phase change costs

A phase change is a full theme reload, not a redraw. The widget resolves the theme path for the
new phase, loads that phase's module, rebuilds the box list and tears the standing LVGL tree
down; the scene is then built in chunks of eight boxes, one chunk per pass, and swapped in at
the end. So the three modules of one theme are three independent screens that share nothing at
runtime except what they both read off the state table.

The path is resolved per phase as well (`resolveThemePathForState`), which is what the
*Per-Phase Themes* switch under *System* → *Settings* → *Dashboard* → *Design* acts on. With it
off, one theme covers all three phases and the phase keys keep their values for whoever turns
it back on. With it on, the first of these that names a theme wins: the model's phase override,
then the model's own theme — both only while that model overrides the global choice — then the
global phase override, then the global theme, then `system/default`. A model theme is a context
of its own, so an unset phase override falls back to the model's theme rather than jumping to
the global one.

## What a phase module returns

A phase module returns a table, and there are two kinds of theme. The widget decides which by
what the table carries.

**Declarative** — `layout` and `boxes`. This is what all shipped themes are. The engine
(`widgets/dashboard/engine.lua`) computes the grid, renders each box into plain Lua tables and
hands the result to LVGL, and because it renders box by box it can spread a build over several
passes.

**Free-form** — a `build(zone, state)` function returning an LVGL node list. The widget calls
it and builds the result in one step. Nothing chunks it, so the whole scene is constructed
inside a single instruction budget; a free-form theme of any size is the surest way to a CPU
limit fault on a slower radio.

A module that carries neither is not a theme: the loader falls through to
`system/default/<phase>.lua`, and to `system/default/preflight.lua` if even that is missing.
The same fallback catches a module that fails to compile. A theme whose `init.lua` names no
module for the phase is looked for under `widget.lua` in the theme folder first — which is how
a single-screen theme covers all three phases with one file.

### `layout`

| Key | Default | What it does |
| --- | --- | --- |
| `cols` | `1` | Grid columns. |
| `rows` | `1` | Grid rows. |
| `padding` | `0` | Pixels between tracks. |
| `bgcolor` | black | The full-zone rectangle drawn under every box. `false` draws none, and the radio's own theme background shows through the gaps. |

The grid divides the zone evenly and gives the remainder pixels to the right and bottom edges,
so early tracks keep their size when the zone changes. `padding` is spacing only — nothing
draws in it, which is why the background rectangle exists.

`header_layout` and `header_boxes` declare a second grid across the top sixteen per cent of the
zone, at least 24 px, drawn after the main grid and therefore above it. No shipped theme uses
them.

### `boxes`

`boxes` is either a list or a function `(box, state)` returning one. A function is called once
per build, which is where a theme resolves anything that depends on the zone size or on its own
configuration.

Every box takes its place from four fields — `col`, `row`, `colspan`, `rowspan`, all
1-based and clamped to the grid — and its content from `type` and `subtype`:

| `type` | `subtype` | Shows |
| --- | --- | --- |
| `text` | `telemetry` (default) | A telemetry value, formatted. |
| `text` | `governor` | The governor state as a label. |
| `text` | `blackbox` | Blackbox usage. |
| `text` | `stats` | One flight statistic, chosen with `stattype`. |
| `text` | `text` | Nothing — a decorative container. |
| `gauge` | `arc`, `bar` | The value between `min` and `max`; `arc` is the default. |
| `time` | `flight`, `count`, `total` | The flight clock, the flight count, the lifetime total. |
| `image` | `image`, `model` | A file from the card, or the model picture. |
| `dial` | — | Container only: no subrenderer ships for this type. |

An unknown `type` draws a container with `--` in it, which is the shape a typo takes on the
radio.

The value a box reads is `source`, and the names are resolved in
`widgets/dashboard/objects/common.lua`, `mapTelemetrySource`: a fixed set that comes straight
off the widget state — `voltage`, `bec_voltage`, `current`, `watts`, `rpm`, `fuel`,
`smartfuel`, `smartconsumption`, `altitude`, `governor`, `esc_temp`, `mcu_temp`,
`throttle_percent`, `link`, `pid_profile`, `rate_profile`, `battery_profile`, `model_name`,
`esc_load` — and, for anything else, the sensor of that name from `lib/sensors.lua`.

### `esc_load`

Not a sensor. It is the current as a percentage of the current limit the speed controller is
set to allow, and it exists so that a tile can show a figure a pilot can judge without knowing
the controller. The limit is kept per flight controller, in its preferences file on the radio: an AM32, Scorpion or
YGE controller reports its own and the suite takes it from the parameter block when that
family's page is opened, and for the other seven families it is typed in under *Setup* →
*Power* → *Preferences* ([page](../pages/setup/power/preferences.md)).

Where no limit is on file the source resolves to `nil`, which a box draws as `--`. That is the
state every model is in until one of the two routes has supplied a figure, so a theme shipping
an `esc_load` box should expect `--` to be what most radios show.

Give the box `unit = "%"`, and for a gauge a range of `min = 0, max = 150`: the interesting part
is above 100, where the controller is being asked for more than it is set to allow, and a gauge
ending at 100 has nowhere to draw that.

The rest of a box is presentation and is shared across the types that can use it: `title`,
`titlepos`, `titlealign`, `titlecolor`, `textcolor`, `bgcolor`, `font`, `unit`, `decimals`,
`transform`, `autosize_chars`, `thresholds`. Thresholds — the dynamic colour lists and how a
temperature limit is converted for a radio set to Fahrenheit — are described once, in
[user themes](../dashboard/user-themes.md); they behave identically in a shipped theme.

**`source` is read as a literal, once, at theme load.** When a theme is loaded the widget walks
its boxes and collects every `source` that is a string into the list the derived snapshot is
built from, and it is that snapshot a box reads per frame. A `source` given as a function is
resolved at render time but is not in the list, so unless some other box names the same source
as a literal, it resolves against a snapshot that does not carry it and the box shows `--`.
Give `source` as a plain string.

## A value given as a function

Almost every field of a box may be a function `(box, state)` instead of a value, and the two
are resolved at different moments:

- **Structure is resolved once, when the box is built** — `layout`, `boxes`, `subtype`, a
  gauge's `min` and `max`, a threshold's limit and its colours, a named colour string. Anything
  such a function reads must be something whose change rebuilds the screen. The theme
  configuration is: saving it reloads the active theme. Live telemetry is not.
- **Display is resolved per frame, in the firmware's reactive sweep** — every function field
  handed to `lvgl.build()`. That sweep runs on whatever instruction budget the widget's own
  pass left over, outside the widget's `pcall`, so the rule in [GEMINI.md](../../GEMINI.md)
  under *Dashboard Reactive Closures* applies to a theme's closures exactly as it applies to
  the object modules: read precomputed state, probe nothing, no unbounded loop, format at most
  one string per value change.

A function that raises is caught and resolves to `nil`, which on the radio looks like a box
that draws its container and no value.

## `configure.lua`

A theme with settings returns a **factory**: a function taking the page context and returning
the page module. The context carries the theme the page was opened for, and the factory takes
the theme's path out of it. That is what makes a copied theme store its own values instead of
writing over the original's.

```lua
local THEME_PATH = "system/default"    -- fallback for a caller that passes no theme

-- ... the page module M, with getHeaderActions, onReload, onSave and build ...

return function(ctx)
  local theme = ctx and ctx.theme
  if type(theme) == "table" and type(theme.path) == "string" and theme.path ~= "" then
    THEME_PATH = theme.path
  end
  return M
end
```

Values are read and written with `DashboardLib.getThemeConfig(prefs, path, defaults, modelPrefs)`
and `setThemeConfig`, which store them under `cfg_<path with every non-alphanumeric character
replaced by an underscore>_<key>` — `system/default` and the key `v_min` give
`cfg_system_default_v_min`. Two themes therefore cannot collide, and a theme copied to a
different folder starts from the defaults rather than inheriting.

Where the flight controller's id is known the values go to the per-model preferences, and the
page saves them with `model_preferences.saveByMcuId`; where it is not, they are stored globally.
Read and write must agree on that condition — a read that takes the per-model table where the
write did not silently loses the setting.

The widget hands the resolved configuration to the theme as `state.themeConfig`, which is where
a box's `min`, `max` or threshold limit reads it from.

## Splitting the settings into pages

A theme with more settings than one screen carries may declare `pages` in its `init.lua`. Its
tile under *Dashboard* → *Settings* then opens a grid of those pages instead of the settings
page itself, and each tile opens the same `configure.lua` with the page it stands for named on
the context. There is one level of it: a page holds settings, never a further grid.

```lua
pages = {
  { id = "look", title = "Look",       icon = "icons/look.png" },
  { id = "rows", title = "Value Rows", icon = "icons/rows.png" },
},
```

| Key | Type | What it does |
| --- | --- | --- |
| `id` | string | Lowercase letters, digits and underscores. It becomes part of the menu id, and it is what the module reads to tell the pages apart. Unique within the theme; a repeat of one is dropped. |
| `title` | string | The tile label and the page's header title. Required, and it takes the same `@i18n(key)@` form a theme's `name` takes. |
| `icon` | string | Optional, relative to the theme folder. |

**Fewer than two usable entries and the theme behaves as though it declared none**, because a
grid holding a single tile is a press a pilot pays for nothing. An entry missing its `id` or
`title`, or carrying an `id` the menu cannot hold, is dropped rather than costing the theme its
settings page.

Icons are resolved against the folder the theme was found in and looked up before use: a page
icon that is not there falls back to the theme's own `icon.png`, and that to the settings
icon of the tool. The theme's own tile follows the same chain, so a configurable theme is now
listed under *Settings* with its `icon.png` rather than with the settings icon.

The page is handed to `configure.lua` as `ctx.page` — on the factory context beside `theme`,
and on the context of every `build`, `onReload` and `onSave` call, because a module returned as
a plain table never sees a factory context:

```lua
ctx.page = { id = "rows", title = "Value Rows" }   -- nil when the theme declares no pages
```

Each page loads and saves the whole configuration: `loadConfig` and `saveConfig` are unchanged,
and a page is expected to build the controls belonging to `ctx.page.id` and to leave the rest of
the values as it found them. **Leaving a page discards the module.** The page registry drops the
settings module when the menu id changes (`app/pages/init.lua`, `closePageModule`), so switching
between two pages of one theme re-loads `configure.lua` and calls the factory again — an edit
that has not been saved is gone. Save before leaving a page, or keep what must survive in the
preferences.

A radio that offers no directory enumeration reads the theme list from
`theme_index.lua` instead of from `init.lua`, and the packager copies the declared pages into
it, so the split is there as well.

## Checklist for a theme shipped in this repository

1. `src/rfsuite/widgets/dashboard/themes/<folder>/` with `init.lua`, the three phase modules
   and `icon.png`.
2. A row in `app/pages/settings/dashboard/theme_index.lua`, or the theme is missing on a radio
   without directory enumeration.
3. `configure.lua` as a factory, or no `configure` key at all.
4. Every string a pilot reads through i18n — box titles take the `@i18n(key)@` form, which the
   packager resolves for a shipped theme and the widget resolves at runtime for a user theme,
   falling back to the last segment of the key when it cannot.
5. A budget row. `bin/accounting/measure.lua` prices every shipped theme — its worst pass and
   one full sweep of the tree it leaves standing — and every box type the shipped themes
   declare. A theme or a box type with no row in `budgets.lua` fails `--check`, which is what
   makes a new theme ship its cost with the pull request that adds it. See
   `bin/accounting/README.md`.
6. The documentation: this page for a change to the contract, `docs/dashboard/` for what a pilot
   sees, and an entry in `Releases.md`.

## Related

- [User themes](../dashboard/user-themes.md) — copying and editing a theme on the card, box
  styling, named colours and threshold lists.
- [Dashboard widget](../dashboard/README.md) — the pilot-facing side of the widget.
- [GEMINI.md](../../GEMINI.md) — the code conventions, and the reactive-closure rule in full.

*Documented against RFSuite 0.1.7.*
