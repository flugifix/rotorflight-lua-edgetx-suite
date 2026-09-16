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

Hidden until *System* → *Settings* → *General* → *Preview* → *Flight Log* is on. Read-only while
the model is armed.

## Settings

The log itself is switched on under *Settings*, not here. This page only reads what has been
written.

| Setting | What it does |
| --- | --- |
| Log flights | Off by default. While it is off nothing is written, and this page stays empty. |
| Minimum flight | An arm shorter than this is a spool-up check rather than a flight, and is not logged. 30 s by default; 0 logs every arm. |

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
| `sags`, `sag_min` | Voltage-sag events — not recorded yet, always empty |

Per-cell voltage needs a cell count, which comes from the flight controller's battery
configuration. On a model where that has not been read, the two per-cell columns stay empty rather
than being divided by a guess.

A flight that produced no statistics at all — telemetry gone for the whole armed window — is
written as the five-field line it has always been, rather than as a line of empty columns.

## Notes

The file is plain text, one flight per line, with a header naming every column. It is meant to be
opened on a computer as well as here; editing a line on the card changes what this page shows and
leaves the rest of the file alone.

The battery registry beside it is the same kind of file. A pack picked under *Batteries* goes into
the flight's line, and that pack's first flight of a session counts one cycle against it.

A flight counts as logged only once the file on the card has grown by exactly the bytes its line
takes. Where the card will not say how large a file on it is, the flight is not written at all and
the log says which step refused, rather than a line being appended to a file whose contents cannot
be established. The registry is held to the same standard: a pack's cycle count and the edits made
under *Batteries* are refused, with a message on the screen, rather than rewriting the file from a
read that may have been cut short. A registry of the size a pilot keeps is unaffected either way.

*Documented against RFSuite 0.1.7.*
