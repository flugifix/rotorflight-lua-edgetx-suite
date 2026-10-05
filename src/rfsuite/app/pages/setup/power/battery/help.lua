return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.setup_power_battery.help_message")
    or "With per-profile cells on the flight controller, the cell settings follow Selected Battery, and each voltage stays between its neighbours.\nSelected Battery: the active profile; changing it here switches it.\nBattery 1 to 6: the capacity stored in each profile.\nMax cell voltage: top of a cell's range; used to detect the cell count.\nFull cell voltage: what a full cell reads.\nWarn cell voltage: the low-voltage warning starts here.\nMin cell voltage: the low-voltage alarm level.\nCell count: 0 lets the flight controller detect it.\nConsumption reserve: the share of the capacity held back."

  return {
    message = message
  }
end
