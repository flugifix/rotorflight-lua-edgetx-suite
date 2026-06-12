local function loadModule(path)
	local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
	local chunk = loadScript(fullPath, "t")
	if type(chunk) ~= "function" then return nil end
	local ok, mod = pcall(chunk)
	if not ok then return nil end
	return mod
end

return function(ctx)
	local Common = loadModule("app/pages/settings/common.lua")
	local t = Common and Common.pageT("flight_tuning_governor") or function(_, _, fb) return fb end
	local i18n = ctx.i18n

	local message = t(i18n, "help_p1", "Full headspeed: Headspeed target when at 100% throttle input.") .. "\n\n" ..
		t(i18n, "help_p2", "Master gain: How hard the governor works to hold the RPM.") .. "\n\n" ..
		t(i18n, "help_p3", "Gains: Fine tuning of the governor.") .. "\n\n" ..
		t(i18n, "help_p4", "Precomp: Governor precomp gain for yaw, cyclic, and collective inputs.") .. "\n\n" ..
		t(i18n, "help_p5", "Max throttle: The maximum throttle % the governor is allowed to use.") .. "\n\n" ..
		t(i18n, "help_p6", "Tail Torque Assist: For motorized tails. Gain and limit of headspeed increase when using main rotor torque for yaw assist.")

	return {
		title = t(i18n, "title", "Governor"),
		message = message
	}
end
