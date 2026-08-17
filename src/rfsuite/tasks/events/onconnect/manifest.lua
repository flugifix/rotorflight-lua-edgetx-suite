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
}
