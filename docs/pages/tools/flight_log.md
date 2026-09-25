---
title: Flight Log
sidebar_label: Flight Log
sidebar_position: 30
---

# Flight Log

A line per flight, written to the card when the craft disarms: when it flew, on which model, on
which pack, how long it was armed, and what the flight's telemetry reached. The page lists those
lines, newest first, and opens one to show the flight in full.

## Where to find it

*Tools* → *Flight Log*

Hidden until *System* → *Settings* → *General* → *Preview* → *Flight Log* is on
(`visibleWhen = "previewFlightLog"`). The tile is locked while the model is armed
(`lockedWhileArmed = true`), so the page cannot be opened in flight.

## Getting around the page

Four tabs across the top — *Flights*, *Models*, *Batteries*, *Settings* — and the tab of the view
on screen is drawn as the active one. A flight opened out of the list and a pack opened out of the
registry are not tabs of their own: they keep the tab they came from marked and carry a heading
naming what they show, the flight's date and time and the pack's name.

Back steps out of whatever was opened before it leaves the page: an open pack editor, then a
flight or a pack detail, then a filtered flight list, then the page itself.

## Settings

The log itself is switched on under *Settings*, not here. This page only reads what has been
written.

| Setting | What it does |
| --- | --- |
| Write a flight log | Off by default. While it is off nothing is written, and this page stays empty. |
| Minimum flight length | An arm shorter than this is a spool-up check rather than a flight, and is not logged. 30 s by default; 0 logs every arm. |

## Batteries

The registry of packs, the editor for it, and the pack the next flight is logged against.

*Battery for the next flight* offers the packs that name this craft in their model list, plus
*None*. The choice is kept for this model, so the same pack is offered again the next time the
craft is connected; the flight's line records it, and a pack's first flight of a session counts
one cycle against it.

*New battery* opens the editor, which takes the whole screen until *Save* or *Cancel* — the tabs
are not drawn while it is open, because one press on a tab would discard what has been typed.
Back cancels it. A pack already in the list is opened with the `>` button, which shows what it
holds together with how many logged flights name it and when it was last used, and offers *Edit*
and *Delete*. Deleting asks first.

| Field | What it holds |
| --- | --- |
| Id | The name the flight's line and the model's own choice refer to the pack by. Letters, digits, `_` and `-`; anything else is dropped. It has to be unique, and a new pack is offered the lowest number the registry has free. |
| Name | What the pack is called on the page and in the flight list. Up to 24 characters. |
| Capacity | The pack's capacity in mAh, in steps of 100. `0` means it is not recorded and the field is left out of the file. |
| Models | The craft this pack is offered for, as a comma-separated list of model names. Empty means every model. |
| Battery profile | The flight controller's battery profile this pack belongs to, 1 to 6. `0` means none is recorded and the field is left out of the file. |
| Cycles | How many charges the pack has seen. It is counted up by flying, and is editable here for a pack that was already in use before it was entered. |

Renaming a pack's id, or deleting it, takes the *battery for the next flight* with it: the choice
follows the new id, or goes back to *None*.

## What a line holds

The first five fields are always there: the date and time the craft armed, the model name, the pack
the flight was flown on, and the armed seconds.

Everything after them is the flight's own statistics, taken from the record the suite keeps while
the craft is armed. A field that was never recorded is left empty, so a line may carry all of them,
some of them or none.

| Column | What it is |
| --- | --- |
| `mah` | Capacity used, as the flight controller reported it, rounded down to whole mAh |
| `vcel_min`, `vcel_max` | Lowest and highest pack voltage, per cell |
| `curr_min`, `curr_max` | Lowest and highest current |
| `tesc_min`, `tesc_max` | Lowest and highest ESC temperature |
| `vbec_min`, `vbec_max` | Lowest and highest BEC voltage |
| `hs1_min` … `hs3_max` | Headspeed per PID profile — not recorded yet, always empty |
| `sags`, `sag_min` | How many times the pack sagged to the flight controller's minimum cell voltage, and the deepest per-cell voltage it reached |

Per-cell voltage needs a cell count, which comes from the flight controller's battery
configuration. On a model where that has not been read, the two per-cell columns stay empty rather
than being divided by a guess.

A sag is a dip to or below the flight controller's own *Min cell voltage*, counted once per dip:
the pack has to come back 0.05 V a cell above the line before the next one counts. A reading at or
below 1 V is the main power gone rather than a sag and is not counted. `sags` is `0` where the
pack was watched and nothing happened, and empty where it could not be watched at all — no cell
count, or no minimum cell voltage from the board. The statistics are sampled every 0.5 s, so a dip
shorter than that can fall between two samples.

A flight that produced no statistics at all — telemetry gone for the whole armed window — is
written as the five-field line it has always been, rather than as a line of empty columns.

## Notes

The file is plain text, one flight per line, with a header naming every column. It is meant to be
opened on a computer as well as here; editing a line on the card changes what this page shows and
leaves the rest of the file alone.

The battery registry beside it is the same kind of file, one pack per line, and it is meant to be
kept by hand as readily as from the editor: an edit made here rewrites the one line it changes and
leaves comments, unknown fields and the rest of the file exactly as they were.

A flight counts as logged only once the file on the card has grown by exactly the bytes its line
takes. Where the card will not say how large a file on it is, the flight is not written at all and
the log says which step refused, rather than a line being appended to a file whose contents cannot
be established. The registry is held to the same standard: a pack's cycle count and the edits made
under *Batteries* are refused, with a message on the screen, rather than rewriting the file from a
read that may have been cut short. A registry of the size a pilot keeps is unaffected either way.

*Documented against RFSuite 0.1.7.*
