return function(ctx)
	local i18n = ctx and ctx.i18n or nil
	local keyPrefix = "app.pages.flight_tuning_pids"
	local fallback = {
		"FeedForward (Roll/Pitch): Start at 70, increase until stops are sharp with no drift. Keep roll and pitch equal.",
		"I Gain (Roll/Pitch): Raise gradually for stable piro pitch pumps. Too high causes wobbles; match roll/pitch values.",
		"Tail P/I/D Gains: Increase P until slight wobble in funnels, then back off slightly. Raise I until tail holds firm in hard moves (too high causes slow wag). Adjust D for smooth stops-higher for slow servos, lower for fast ones.",
		"Test & Adjust: Fly, observe, and fine-tune for best performance in real conditions."
	}

	local parts = {}
	for i = 1, 4 do
		local key = keyPrefix .. ".help_p" .. tostring(i)
		local text = fallback[i]
		if i18n and i18n.t then
			local translated = i18n.t(key)
			if translated and translated ~= key and translated ~= "" then
				text = translated
			end
		end
		parts[#parts + 1] = text
	end

	return {
		message = table.concat(parts, "\n\n")
	}
end