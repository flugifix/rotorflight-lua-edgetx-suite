---
title: Dashboard fullscreen views
sidebar_label: Dashboard views
sidebar_position: 65
---

# Dashboard fullscreen views

What the dashboard widget shows when it is put full screen, and what happens after a button on
that screen is pressed. Both are decided in one module,
`src/rfsuite/widgets/dashboard/views.lua`: a list of views, a small stack of the ones that are
open, and one function that performs whatever follows a press.

**A pilot sees no change from this.** Full screen shows the battery prompt while it is waiting
for an answer and the [quick menu](../dashboard/quick-menu.md) otherwise, every button does and
leaves exactly what it did before, and the menu and the picker draw the same screens node for
node. What changed is where those decisions are made: one exit instead of five, one build step
instead of two identical ones, and one stack instead of two flags.

## Where to find it

| File | What it holds |
| --- | --- |
| `widgets/dashboard/views.lua` | The view registry, the stack, the conditions, the actions and `navigate()`. |
| `widgets/dashboard/runtime.lua` | The fullscreen branch of `widget.refresh`, which asks `views.resolve()` which view to show, and `viewJobStep`, which builds it. |
| `widgets/dashboard/fullscreen_menu.lua` | The quick menu view. |
| `widgets/dashboard/battery_pick_menu.lua` | The battery picker view. |

`views.lua` is loaded on the first fullscreen pass and never on a zone pass, so a dashboard
that is never put full screen does not pay for it. The one exception is a call to
`rfsuite.batteryPick`, which loads it wherever it is made. The in-flight tuning surface is not a view:
it takes full screen ahead of all of them while it is up, is decided before any of this runs,
and keeps its own close box.

## Views

A view is a registry entry and a module:

| Key | What it says |
| --- | --- |
| `id` | The view's name. It is the render key, and the job that builds the view is named after it: the widget's job log line reads `menu` and `battery_pick`, and the quick menu's job keeps its `menu` pass class in `bin/accounting/measure.lua`. |
| `module` | The file that draws it. The module has `build(children, widget)`, which appends the whole fullscreen tree, and may have `renderKey(widget)`; its result is appended to the id (`menu|<key>`), and the view is rebuilt whenever it changes. |
| `openWhen` | Optional. The name of a condition that opens the view on its own — see below. |

The shipped registry, in this order:

| id | module | openWhen |
| --- | --- | --- |
| `battery_pick` | `widgets/dashboard/battery_pick_menu.lua` | `batteryPickPending` |
| `menu` | `widgets/dashboard/fullscreen_menu.lua` | — |

Each widget gets its own copy of the list, entries included. A view's module is loaded by the
job that first builds it and kept on that widget's entry; the state pass reads a view's own
`renderKey` only from a module that is already loaded, and never loads one.

## The stack and the base layer

Which view is on screen is a stack of view ids, held in one field, `widget._viewStack`. Each
entry is `{ id = <id>, auto = true | nil }`.

- The view on top of the stack is the one shown.
- Opening a view that is already on the stack returns to it — everything above it is closed —
  rather than opening it a second time.
- The stack holds at most **four** views. Opening a fifth is refused: nothing changes, nothing
  is rebuilt, and the refusal is logged once until the stack next changes.
- Opening a view the widget has no entry for is refused the same way, with a log line. A job
  for a view no module can build would otherwise be queued again on every pass.
- A pass that arrives without an event — full screen has been left, possibly by a long press
  on RTN that Lua never sees — drops the whole stack in one assignment. So does a reconnect.

The stack lies above a **base layer**, `widget._viewBase`. When the stack is empty the base
layer is what full screen shows. Nothing in the widget sets it yet: it is the hook a later
theme mode that draws its own full screen will use, and that mode also brings what draws it:
`views.resolve()` reports the base layer as `nil`, and the runtime builds nothing for it yet.
**With no base layer, an empty stack shows the quick menu**, which is what full screen has
always shown on entry.

## Views that open themselves

A view with `openWhen` opens on its own while that condition holds. On every fullscreen pass,
in this order:

1. A view that its own condition opened (`auto = true`) and whose condition no longer holds is
   closed again. That is what keeps the battery prompt the way it was: it shows while it is
   pending, and three places end the pending state without closing anything — arming
   (`updateDerivedFlightState`), a pick (`batteryPickApplyStep`) and a reconnect.
2. The first view in registry order whose `openWhen` holds is the only one considered on that
   pass: it is opened unless it is already on the stack. A view already on the stack is left
   where it is and is not raised over what lies above it, and no view listed after it is
   opened while its condition holds. So where several hold, the one listed first is the one
   that opens, not necessarily the one on top; the picker is listed before the menu.
3. The top of the stack is shown; with the stack empty, the base layer, or with none the quick
   menu.

A view opened explicitly — by a button or by `rfsuite.batteryPick.open()` — carries no `auto`
mark, and opening a view explicitly that its condition had already opened takes the mark off.
Such a view stays open when its condition falls, until it is closed.

**The rule for a condition that opens a view: whoever sets it clears it when the view is
answered or closed.** A view whose condition still holds when it is closed opens again on the
very next pass. The battery prompt follows it: its registry load raises `pending`, and a pick,
the picker's close box, `rfsuite.batteryPick.dismiss()`, arming and a reconnect all clear it.

## Conditions

`visibleWhen` on a quick menu entry and `openWhen` on a view name a condition from one list in
`views.lua`. A name that is not in the list is false: it hides the entry and never opens the
view, which is what an unresolvable condition does in `app/menu_registry.lua` as well.

| Condition | True while |
| --- | --- |
| `previewInflightTuning` | the in-flight tuning preview switch is on and the widget carries the overlay's state for this model |
| `batteryPickHasPacks` | the model is disarmed and the battery registry has a pack for it |
| `batteryPickPending` | the battery prompt is waiting for an answer (`state.batteryPick.pending`) |

## What follows a press

A press does its work and nothing else. What happens next is data: an `after` action on the
entry, the option or the button, which `views.navigate(widget, after)` performs. An action is a
string:

| Action | What it does |
| --- | --- |
| `openView:<id>` | Open that view, or return to it where it is already on the stack. |
| `closeView` | Close the view on top; what is under it shows again. |
| `done` | The interaction is finished: the stack is emptied. With no base layer that leaves full screen; with one, the base layer shows again. |
| `exitFullscreen` | Empty the stack and leave full screen, base layer or not. |
| `none` | Nothing. The press did whatever needed doing itself. |

A missing `after`, and anything that is not one of these, is `none`. `views.parseAction()` is
the one place an action is read, so a later form of it is added there and nowhere else.

`navigate()` is the only place a view leaves full screen. Every action but `none` drops what is
built, so the next pass builds the view now on top. The shipped buttons:

| Where | Button | after |
| --- | --- | --- |
| Quick menu | ERASE BLACKBOX | `done` |
| Quick menu | IN-FLIGHT TUNING | `none` — its press raises the tuning surface's own flag |
| Quick menu | BATTERY | `openView:battery_pick` |
| Quick menu | each BATTERY PROFILE option | `done` |
| Quick menu | the header's X | `done` |
| Picker | each pack, and NO BATTERY | `done` |
| Picker | the header's X | `done` |

`views.bind(widget)` returns the actions bound to one widget, for code that has no widget of
its own to pass: `ctx.action(after)` performs `after` exactly as `navigate(widget, after)` does.

## `rfsuite.batteryPick`

The handle the widget publishes for a theme or another widget
([dashboard themes](dashboard-themes.md#rfsuitebatterypick)) maps onto the same stack:

| Call | What it does here |
| --- | --- |
| `open()` | `openView:battery_pick`. |
| `dismiss()` | Ends the prompt for this connection (`dismissed`, and `pending` cleared), then `closeView` if the picker is the view on top. |
| `select(id)` | Records the pick, as before; it opens and closes nothing. |

The handle runs outside the widget's own error guard, so it reaches `views.lua` through a loader
that returns nothing rather than raising when the file cannot be loaded.

## Related

- [Quick menu](../dashboard/quick-menu.md) — the menu's entries and their keys.
- [Dashboard themes](dashboard-themes.md) — `state.batteryPick` and `rfsuite.batteryPick`.
- [In-flight tuning overlay](../dashboard/inflight-tuning.md) — the fullscreen surface that is
  not a view.

*Documented against RFSuite 0.1.7.*
