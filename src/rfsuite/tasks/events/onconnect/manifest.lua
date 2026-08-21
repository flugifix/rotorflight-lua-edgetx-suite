-- Manifest for onconnect tasks (ordered)
return {
  "apiversion",
  "uid",
  "rtc",
  { name = "flight_stats", context = "widget" },
  { name = "dataflash_summary", context = "widget" },
  { name = "battery_config", context = "both" },
  { name = "governor_config", context = "both" },
  { name = "esc_sensor_config", context = "tool" },
  { name = "smartfuel_config", context = "both" },
  { name = "name", context = "both" },
  -- After `name`, which is what fills session.modelName.
  { name = "model_name_sync", context = "both" },
  { name = "model_params_sync", context = "both" },
}
