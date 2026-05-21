local M = {}

local function loadModule(path)
	local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
	local chunk = loadScript(fullPath, "t")
	if type(chunk) ~= "function" then return nil end
	local ok, mod = pcall(chunk)
	if not ok then return nil end
	return mod
end

local Controls = nil
local Common = nil
local ModelPreferences = nil
local MspRuntime = nil
local SmartfuelApi = nil
local ApiVersion = nil
local LoadingOverlay = nil
local t = nil

local function newRuntime()
	return {
		localSourceSet = nil,
		firmwareModeSet = nil,
		voltageSet = nil,
		chargeSet = nil,
		sagSet = nil,
		readPending = false,
		requestRebuild = nil
	}
end

local ui = {
	loaded = false,
	dirty = false,
	config = {
		local_source = 0,
		firmware_mode = 0,
		voltage_drop_rate = 10,
		charge_drop_rate = 50,
		sag_gain = 40
	},
	support = {
		firmware = false
	},
	runtime = newRuntime(),
	loading = false,
	progress = 0
}

local function ensureRuntime()
	if type(ui.runtime) ~= "table" then
		ui.runtime = newRuntime()
	end
end

local function getSession()
	local root = _G and _G.rfsuite
	return root and root.session or nil
end

local function isFirmwareSupported(session)
	local apiVersion = ApiVersion and ApiVersion.parse and ApiVersion.parse(session and session.apiVersion)
	return ApiVersion and ApiVersion.isAtLeast and ApiVersion.isAtLeast(apiVersion, { 12, 0, 9 }) or false
end

local function clampInt(value, minValue, maxValue, fallback)
	local n = tonumber(value)
	if n == nil then n = fallback end
	n = math.floor((n or fallback or minValue) + 0.5)
	if n < minValue then n = minValue end
	if n > maxValue then n = maxValue end
	return n
end

local function ensureDeps()
	if not Common then Common = loadModule("app/pages/settings/common.lua") end
	if not Controls then Controls = loadModule("ui/controls.lua") end
	if not ModelPreferences then ModelPreferences = loadModule("lib/model_preferences.lua") end
	if not MspRuntime then MspRuntime = loadModule("tasks/msp/runtime.lua") end
	if not SmartfuelApi then SmartfuelApi = loadModule("tasks/msp/api/smartfuel_config.lua") end
	if not ApiVersion then ApiVersion = loadModule("lib/api_version.lua") end
	if not LoadingOverlay then LoadingOverlay = loadModule("ui/loading_overlay.lua") end
	if not t then t = Common and Common.pageT("setup_power_smartfuel") or nil end
end

local function pageText(i18n, key, fallback)
	if t then
		return t(i18n, key, fallback)
	end
	return fallback
end

local function markDirty()
	ui.dirty = true
end

local function buildModeOptions()
	return {
		{ value = 0, label = "OFF (LOCAL)" },
		{ value = 1, label = "VOLTAGE" },
		{ value = 2, label = "CURRENT" },
		{ value = 3, label = "COMBINED" }
	}
end

local function buildLocalOptions()
	return {
		{ value = 0, label = "CURRENT" },
		{ value = 1, label = "VOLTAGE" },
		{ value = 2, label = "COMBINED" }
	}
end

local function getBatteryPrefs(session)
	if type(session) ~= "table" then return nil end
	if type(session.modelPreferences) ~= "table" then
		session.modelPreferences = {}
	end
	if type(session.modelPreferences.battery) ~= "table" then
		session.modelPreferences.battery = {}
	end
	return session.modelPreferences.battery
end

local function loadFromSession()
	local session = getSession()
	local batteryPrefs = getBatteryPrefs(session)
	local cfg = (type(session) == "table" and type(session.smartfuel_config) == "table") and session.smartfuel_config or nil

	ui.support.firmware = isFirmwareSupported(session)
	ui.config.local_source = clampInt((batteryPrefs and batteryPrefs.smartfuel_source) or (batteryPrefs and batteryPrefs.calc_local), 0, 2, 0)
	ui.config.firmware_mode = clampInt(cfg and cfg.smartfuel_mode, 0, 3, 0)

	local voltageDrop = (cfg and cfg.voltage_drop_rate) or (batteryPrefs and batteryPrefs.voltage_drop_rate)
	local chargeDrop = (cfg and cfg.charge_drop_rate) or (batteryPrefs and batteryPrefs.charge_drop_rate)
	local sagGain = (cfg and cfg.sag_gain) or (batteryPrefs and batteryPrefs.sag_gain)
	ui.config.voltage_drop_rate = clampInt(voltageDrop, 0, 250, 10)
	ui.config.charge_drop_rate = clampInt(chargeDrop, 0, 250, 50)
	ui.config.sag_gain = clampInt(sagGain, 0, 100, 40)
end

local function queueSmartfuelRead()
	ensureRuntime()
	if ui.runtime.readPending then
		return false, "read_pending"
	end
	if not ui.support.firmware then
		return false, "firmware_not_supported"
	end
	if not SmartfuelApi or not MspRuntime or type(MspRuntime.getState) ~= "function" then
		return false, "msp_runtime_unavailable"
	end

	local session = getSession()
	local mspState = MspRuntime.getState()
	local queue = mspState and mspState.queue
	if not queue or type(queue.add) ~= "function" then
		return false, "msp_queue_unavailable"
	end

	ui.runtime.readPending = true
	ui.loading = true
	ui.progress = 0
	queue:add({
		command = SmartfuelApi.command,
		simulatorResponse = SmartfuelApi.simulatorResponse,
		timeout = 5.0,
		processReply = function(_, buf)
			ui.runtime.readPending = false
			ui.loading = false
			ui.progress = 1
			if type(session) == "table" then
				local parsed = SmartfuelApi.parse and SmartfuelApi.parse(buf) or nil
				if type(parsed) == "table" then
					session.smartfuel_config = parsed.parsed or parsed
					if type(session.battery_config) == "table" then
						session.battery_config.smartfuelRemoteSource = tonumber(session.smartfuel_config.smartfuel_mode) or 0
					end
				end
			end
			if not ui.dirty then
				loadFromSession()
			end
			if type(ui.runtime.requestRebuild) == "function" then
				ui.runtime.requestRebuild()
			end
		end,
		errorHandler = function()
			ui.runtime.readPending = false
			ui.loading = false
			ui.progress = 1
		end
	})

	return true, nil
end

local function ensureLoaded()
	ensureRuntime()
	if ui.loaded then return end
	loadFromSession()
	ui.loaded = true
	ui.dirty = false
	queueSmartfuelRead()
end

local function saveModelPreferences(session)
	if not session or not ModelPreferences or type(ModelPreferences.saveByMcuId) ~= "function" then
		return false, "model_preferences_unavailable"
	end
	if not session.mcu_id then
		return false, "missing_mcu_id"
	end
	return ModelPreferences.saveByMcuId(session.mcu_id, session.modelPreferences)
end

local function queueSmartfuelWrite(session)
	if not ui.support.firmware then
		return true, nil
	end
	if not SmartfuelApi or not MspRuntime or type(MspRuntime.getState) ~= "function" then
		return false, "msp_runtime_unavailable"
	end

	local mspState = MspRuntime.getState()
	local queue = mspState and mspState.queue
	if not queue or type(queue.add) ~= "function" then
		return false, "msp_queue_unavailable"
	end

	local payload = SmartfuelApi.buildWritePayload({
		smartfuel_mode = ui.config.firmware_mode,
		voltage_drop_rate = ui.config.voltage_drop_rate,
		charge_drop_rate = ui.config.charge_drop_rate,
		sag_gain = ui.config.sag_gain
	})

	queue:add({
		command = SmartfuelApi.writeCommand,
		payload = payload,
		timeout = 5.0,
		isWrite = true,
		processReply = function()
			if type(session) == "table" then
				session.smartfuel_config = session.smartfuel_config or {}
				session.smartfuel_config.smartfuel_mode = ui.config.firmware_mode
				session.smartfuel_config.voltage_drop_rate = ui.config.voltage_drop_rate
				session.smartfuel_config.charge_drop_rate = ui.config.charge_drop_rate
				session.smartfuel_config.sag_gain = ui.config.sag_gain
			end
		end,
		errorHandler = function()
			-- Keep local values; FC write can be retried with Save.
		end
	})

	return true, nil
end

function M.getHeaderActions()
	ensureDeps()
	return {
		save = true,
		reload = true,
		help = true,
		menu = true
	}
end

function M.allowMemAutoRefresh()
	return true
end

function M.onReload()
	ensureDeps()
	ui.loaded = false
	ensureLoaded()
	return false
end

function M.onSave(ctx)
	ensureDeps()
	ensureLoaded()

	local session = getSession()
	local batteryPrefs = getBatteryPrefs(session)
	if not batteryPrefs then
		return false
	end

	if not ui.support.firmware then
		batteryPrefs.smartfuel_source = ui.config.local_source
		batteryPrefs.calc_local = ui.config.local_source
	end
	batteryPrefs.voltage_drop_rate = ui.config.voltage_drop_rate
	batteryPrefs.charge_drop_rate = ui.config.charge_drop_rate
	batteryPrefs.sag_gain = ui.config.sag_gain

	local okPrefs, errPrefs = saveModelPreferences(session)
	if not okPrefs then
		if lvgl and lvgl.alert then
			lvgl.alert({ title = "Error", message = "Saving SmartFuel prefs failed: " .. tostring(errPrefs or "io") })
		end
		return false
	end

	if ui.support.firmware then
		session.smartfuel_config = session.smartfuel_config or {}
		session.smartfuel_config.smartfuel_mode = ui.config.firmware_mode
		session.smartfuel_config.voltage_drop_rate = ui.config.voltage_drop_rate
		session.smartfuel_config.charge_drop_rate = ui.config.charge_drop_rate
		session.smartfuel_config.sag_gain = ui.config.sag_gain

		if type(session.battery_config) == "table" then
			session.battery_config.smartfuelRemoteSource = ui.config.firmware_mode
		end
	end

	local okMsp, errMsp = queueSmartfuelWrite(session)
	if not okMsp then
		if lvgl and lvgl.alert then
			lvgl.alert({ title = "Warning", message = "Saved local SmartFuel values. FC write pending: " .. tostring(errMsp or "msp") })
		end
	else
		if lvgl and lvgl.alert then
			local savedTitle = pageText(ctx and ctx.i18n, "saved_title", "Saved")
			local savedMessage = pageText(ctx and ctx.i18n, "saved_message", "SmartFuel settings saved")
			lvgl.alert({ title = savedTitle, message = savedMessage })
		end
	end

	-- Force smart calculator to pick up new config immediately.
	if _G and _G.rfsuite and _G.rfsuite.tasks and _G.rfsuite.tasks.events then
		local bg = _G.rfsuite.tasks.events.telemetry_bg
		if type(bg) == "table" and type(bg.reset) == "function" then
			pcall(bg.reset)
		end
	end

	ui.dirty = false
	return true
end

local function getLocalSourceSetter()
	if ui.runtime.localSourceSet then return ui.runtime.localSourceSet end
	ui.runtime.localSourceSet = function(value)
		local nextValue = clampInt(value, 0, 2, 0)
		if ui.config.local_source == nextValue then return end
		ui.config.local_source = nextValue
		markDirty()
	end
	return ui.runtime.localSourceSet
end

local function getFirmwareModeSetter()
	if ui.runtime.firmwareModeSet then return ui.runtime.firmwareModeSet end
	ui.runtime.firmwareModeSet = function(value)
		local nextValue = clampInt(value, 0, 3, 0)
		if ui.config.firmware_mode == nextValue then return end
		ui.config.firmware_mode = nextValue
		markDirty()
	end
	return ui.runtime.firmwareModeSet
end

local function getVoltageSetter()
	if ui.runtime.voltageSet then return ui.runtime.voltageSet end
	ui.runtime.voltageSet = function(value)
		local nextValue = clampInt(value, 0, 250, 10)
		if ui.config.voltage_drop_rate == nextValue then return end
		ui.config.voltage_drop_rate = nextValue
		markDirty()
	end
	return ui.runtime.voltageSet
end

local function getChargeSetter()
	if ui.runtime.chargeSet then return ui.runtime.chargeSet end
	ui.runtime.chargeSet = function(value)
		local nextValue = clampInt(value, 0, 250, 50)
		if ui.config.charge_drop_rate == nextValue then return end
		ui.config.charge_drop_rate = nextValue
		markDirty()
	end
	return ui.runtime.chargeSet
end

local function getSagSetter()
	if ui.runtime.sagSet then return ui.runtime.sagSet end
	ui.runtime.sagSet = function(value)
		local nextValue = clampInt(value, 0, 100, 40)
		if ui.config.sag_gain == nextValue then return end
		ui.config.sag_gain = nextValue
		markDirty()
	end
	return ui.runtime.sagSet
end

local function isTuningEnabled()
	if not ui.support.firmware then return true end
	return ui.config.firmware_mode == 1 or ui.config.firmware_mode == 3
end

function M.build(ctx)
	ensureDeps()
	ensureLoaded()
	ui.runtime.requestRebuild = ctx and ctx.requestRebuild or nil

	local children = ctx.children
	local x = ctx.x
	local y = ctx.y
	local w = ctx.w
	local i18n = ctx.i18n
	local h = ctx.h or 200

	Controls.appendStaticSectionHeader(children, x, y, w, pageText(i18n, "section_mode", "SmartFuel Mode"))
	local cursorY = y + Controls.STATIC_SECTION_H

	if ui.support.firmware then
		cursorY = cursorY + Controls.appendComboSelect(
			children, x, cursorY, w,
			pageText(i18n, "firmware_mode", "Firmware Source"),
			buildModeOptions(),
			ui.config.firmware_mode,
			getFirmwareModeSetter()
		)
	end

	if not ui.support.firmware then
		cursorY = cursorY + Controls.appendComboSelect(
			children, x, cursorY, w,
			pageText(i18n, "local_mode", "Local Source"),
			buildLocalOptions(),
			ui.config.local_source,
			getLocalSourceSetter()
		)
	end

	cursorY = cursorY + 8
	Controls.appendStaticSectionHeader(children, x, cursorY, w, pageText(i18n, "section_tuning", "SmartFuel Tuning"))
	cursorY = cursorY + Controls.STATIC_SECTION_H

	cursorY = cursorY + Controls.appendNumberField(children, x, cursorY, w,
		pageText(i18n, "voltage_drop_rate", "Voltage drop rate"), {
			min = 0,
			max = 250,
			get = function() return ui.config.voltage_drop_rate end,
			set = getVoltageSetter(),
			enabled = isTuningEnabled,
			display = function(v) return tostring(v) .. " mV/s" end
		})

	cursorY = cursorY + Controls.appendNumberField(children, x, cursorY, w,
		pageText(i18n, "charge_drop_rate", "Charge drop rate"), {
			min = 0,
			max = 250,
			get = function() return ui.config.charge_drop_rate end,
			set = getChargeSetter(),
			enabled = isTuningEnabled,
			display = function(v)
				local value = (tonumber(v) or 0) / 100
				return string.format("%.2f %%/s", value)
			end
		})

	Controls.appendNumberField(children, x, cursorY, w,
		pageText(i18n, "sag_gain", "Sag gain"), {
			min = 0,
			max = 100,
			get = function() return ui.config.sag_gain end,
			set = getSagSetter(),
			enabled = isTuningEnabled,
			display = function(v) return tostring(v) .. "%" end
		})

	if ui.loading then
		local title = pageText(i18n, "loading_title", "Loading")
		local message = pageText(i18n, "loading_message", "Reading SmartFuel config")
		if LoadingOverlay then
			LoadingOverlay.append(children, {
				x = x,
				y = y,
				w = w,
				h = h,
				title = title,
				message = message,
				progress = ui.progress
			})
		end
	end
end

function M.onClose()
	if Common and Common.resetPageState then
		Common.resetPageState(ui)
	else
		ui.loaded = false
		ui.dirty = false
	end
	ui.loading = false
	ui.progress = 0
	Controls = nil
	Common = nil
	ModelPreferences = nil
	MspRuntime = nil
	SmartfuelApi = nil
	LoadingOverlay = nil
	t = nil
end

return M
