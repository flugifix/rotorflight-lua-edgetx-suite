-- What a pass, a box type and a theme are allowed to cost, in Lua VM instructions.
--
-- EdgeTX bills a widget call at 20 000 instructions (lua_widget.cpp, MAX_INSTRUCTIONS),
-- and refresh() plus the LVGL reactive sweep that follows it share that one budget. Every
-- target below is a share of it, and the row that actually decides whether the widget
-- survives is `theme.*`: the worst pass of a theme plus the full sweep of the tree it
-- leaves standing.
--
-- `target` is what the check enforces. `measured` is what the row cost when it was written
-- -- kept so that a number which has moved is visible even while it is still inside its
-- target. `proposed` is the figure that sat on the row before anything had been measured;
-- where it differs from `target` the report says so on every run, so a re-apportioned
-- budget can never pass for the original one.
--
-- Adding a box type or a theme means adding its row here, measured rather than estimated:
-- `lua5.3 bin/accounting/measure.lua --emit` prints the table body of a run.

return {
  -- The cost of one call through the empty-closure loop the sweep is replayed in,
  -- subtracted from every sweep row. It is a property of this check rather than of the
  -- suite: a run whose control has moved is measuring differently, and fails itself.
  sweepControl = 4.007,
  sweepControlTolerance = 0.25,

  rows = {
    ----------------------------------------------------------------------------
    -- Pass classes. The dispatcher runs exactly one work class per pass, so these
    -- are alternatives rather than terms that add up.
    --
    -- The STATE and JOB shares are not the ones first written down. Measurement
    -- moved the weight the other way: the background half is the expensive pass
    -- and the build chunk is cheap, where the first split had assumed the reverse.
    -- The ceiling below is unchanged, and the STATE target is derived from it --
    -- 14 000 less the largest shipped theme's sweep -- rather than chosen.
    ----------------------------------------------------------------------------
    ["pass.state"] = { target = 12200, measured = 11437, proposed = 8000 },
    ["pass.job.prepare"] = { target = 1250, measured = 986 },
    ["pass.job.build"] = { target = 5700, measured = 4527, proposed = 10000 },
    ["pass.swap"] = { target = 3400, measured = 2702, proposed = 6000 },
    ["pass.splash"] = { target = 2300, measured = 1826 },

    -- The cold start, before the link is up and the first scene is on screen. It is
    -- the pass that loads modules, and it is the closest any pass comes to the
    -- firmware's hard limit -- which is why the entry point's "CPU limit" back-off
    -- is still in place. The target holds it at today's cost; it is not a share of
    -- a budget anyone would call comfortable.
    ["pass.startup.worst"] = { target = 18000, measured = 17542 },

    -- The service widget's background pass: the same two runtimes, with no scene
    -- build and no sweep of a theme mixed into it.
    ["pass.service"] = { target = 1600, measured = 1251 },

    ----------------------------------------------------------------------------
    -- The ceiling, and the row that carries the safety argument: the worst pass of
    -- this theme plus one full sweep of the tree it leaves standing. The margin to
    -- 20 000 covers the C-side work, the difference between this interpreter and
    -- the firmware's, and the variance neither of them accounts for.
    ----------------------------------------------------------------------------
    ["theme.@aerc"] = { target = 14000, measured = 11600 },
    ["theme.@aerc-n"] = { target = 14000, measured = 10950 },
    ["theme.@rt-rc"] = { target = 14000, measured = 11676 },
    ["theme.@rt-rc-n"] = { target = 14000, measured = 11170 },
    ["theme.@srb-rc"] = { target = 14000, measured = 12887 },
    ["theme.default"] = { target = 14000, measured = 13237 },
    ["theme.rfstatus"] = { target = 14000, measured = 10515 },

    ----------------------------------------------------------------------------
    -- Per box type: one render into the node table, and one sweep of the reactive
    -- references that render collected. A theme's cost is the sum of its boxes
    -- through these two rows, which is what makes a new theme priceable before it
    -- is built.
    ----------------------------------------------------------------------------
    ["box.dial"] = { target = 200, measured = 121 },
    ["sweep.dial"] = { target = 50, measured = 0 },
    ["box.gauge"] = { target = 800, measured = 614 },
    ["sweep.gauge"] = { target = 400, measured = 316 },
    ["box.gauge/arc"] = { target = 1150, measured = 907 },
    ["sweep.gauge/arc"] = { target = 450, measured = 329 },
    ["box.gauge/bar"] = { target = 1300, measured = 1018 },
    ["sweep.gauge/bar"] = { target = 350, measured = 251 },
    ["box.image/image"] = { target = 200, measured = 159 },
    ["sweep.image/image"] = { target = 50, measured = 0 },
    ["box.image/model"] = { target = 400, measured = 306 },
    ["sweep.image/model"] = { target = 50, measured = 0 },
    ["box.text/blackbox"] = { target = 600, measured = 473 },
    ["sweep.text/blackbox"] = { target = 500, measured = 385 },
    ["box.text/governor"] = { target = 600, measured = 465 },
    ["sweep.text/governor"] = { target = 500, measured = 389 },
    ["box.text/stats"] = { target = 300, measured = 233 },
    ["sweep.text/stats"] = { target = 300, measured = 205 },
    ["box.text/telemetry"] = { target = 600, measured = 473 },
    ["sweep.text/telemetry"] = { target = 450, measured = 328 },
    ["box.time/count"] = { target = 600, measured = 469 },
    ["sweep.time/count"] = { target = 300, measured = 210 },
    ["box.time/flight"] = { target = 650, measured = 489 },
    ["sweep.time/flight"] = { target = 300, measured = 205 },
    ["box.time/total"] = { target = 300, measured = 237 },
    ["sweep.time/total"] = { target = 300, measured = 224 },

    ----------------------------------------------------------------------------
    -- Per unit. These do not gate a pass on their own -- they are the terms a pass
    -- is built from, and the place a regression shows up as itself rather than as
    -- a pass that has quietly grown.
    ----------------------------------------------------------------------------
    -- The whole background half of a STATE pass: the event runner, the
    -- custom-telemetry drain and the arm/disarm edges. The largest single term in
    -- a STATE pass, at roughly two fifths of it.
    ["unit.events.wakeup"] = { target = 5600, measured = 4457 },
    -- The custom-telemetry drain with a full frame backlog waiting: POP_CAP frames
    -- popped and accounted, DECODE_CAP of them walked through the per-sensor
    -- decoders. This is what the two counts in telemetry_bg/tasks.lua buy.
    ["unit.telemetry.drain"] = { target = 3300, measured = 2610 },
    ["unit.msp.pump"] = { target = 300, measured = 218 },
    -- The API-layer parse of the largest reply the suite scripts, in one piece. It
    -- lands in whatever pass completes the reassembly.
    ["unit.msp.parse.max"] = { target = 2750, measured = 2175 },
  },
}
