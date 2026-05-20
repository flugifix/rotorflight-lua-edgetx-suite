local M = {}

function M.registerPage(ctx)
	local msg = {
		message = "@i18n(app.pages.setup.telemetry.help_message)@"
	}
	return msg
end

return M
