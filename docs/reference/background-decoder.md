---
title: Background telemetry decoder
sidebar_label: Background decoder
---

# Background telemetry decoder

Rotorflight sends its own telemetry values in a custom frame that EdgeTX does not decode by
itself, so something on the radio has to unpack it and hand the values to the sensors. The
dashboard does that on its own, in the widget, and it works — but a widget call is stopped at a
fixed instruction count, so when frames arrive faster than the widget can decode them the older
part of the backlog is dropped.

The suite can move that work into a small script the radio runs outside the widgets:
`SCRIPTS/FUNCTIONS/rfsbg.lua`. A call there is paused and continued on the next turn instead of
being cut off, so it decodes every frame it takes. The same script also makes the adjustment
announcements.

## Where to find it

*Model* → *Special Functions*, as an entry named `rfsbg` on the always-on switch.

The suite adds that entry itself, once, the first time a model connects to a flight controller.
It takes effect the next time the model is loaded, because the radio reads a model's special
functions when it loads it. Nothing is asked of you and there is nothing to confirm.

## Turning it off

Untick the entry on the *Special Functions* page. The suite leaves an entry it can see alone,
ticked or not, so it stays off.

Deleting the entry instead frees the script slot, and the suite adds it again on the next
connect — deleting is not how to switch it off.

Without the script, the dashboard decodes for itself exactly as it did before. Nothing is lost
and nothing needs to be configured.

## Notes

- **The radio has only a handful of script slots** — seven or nine, shared by every mixer and
  special-function script on it. This takes one of them.
- **A model that already runs another background decoder does not get this one.** Rotorflight's
  earlier Lua scripts install `rf2bg`, which reads the same frames. Every special-function
  script on a radio shares one telemetry queue, so whichever runs first takes the frames and a
  second decoder receives nothing at all. Where the suite sees such an entry on the model it
  installs nothing and writes the reason to the log; the dashboard then decodes for itself.
- **Opening a tool pauses it**, together with every other permanent script, for as long as the
  tool is open. The dashboard notices within a second and takes the decoding back.
- **It cannot be seen from the suite if it is configured as a global function** rather than on
  the model. The radio offers no way for a script to read the global special functions, so a
  background decoder installed there is invisible to the check above.
