std = "lua54"

-- EdgeTX/OpenTX Ethos Environment Globals
globals = {
  -- Scripting Engine
  "loadScript",
  "loadModuleChunk",
  "registerTelemetry",
  "registerForm",
  "registerGadget",
  
  -- System/Time/Model
  "getTime",
  "system",
  "model",
  "getVersion",
  "getField",
  "setField",
  "getFieldInfo",
  
  -- Telemetry/Sensors
  "getValue",
  "getSensor",
  
  -- Display/LCD
  "lcd",
  "lvgl",
  "LCD_W",
  "LCD_H",
  
  -- Colors
  "WHITE",
  "BLACK",
  "GREY_DEFAULT",
  "RED",
  "GREEN",
  "YELLOW",
  "BLUE",
  "MAGENTA",
  "CYAN",
  "COLOR_THEME_PRIMARY1",
  "COLOR_THEME_PRIMARY2",
  "COLOR_THEME_PRIMARY3",
  "COLOR_THEME_WARNING",
  "COLOR_THEME_FOCUS",
  "COLOR_THEME_ACTIVE",
  "COLOR_THEME_EDIT",
  
  -- Font sizes
  "DBLSIZE",
  "MIDSIZE",
  "SMLSIZE",
  "XXLSIZE",
  
  -- Alignment
  "CENTER",
  "LEFT",
  "RIGHT",
  "TOP",
  "BOTTOM",
  
  -- Bit operations
  "bit32",
  
  -- Global state (RF2/Ethos)
  "rfsuite",
  "Rf2Runtime",
  "_G",
}

-- Code style rules
max_line_length = 140
max_code_line_length = 140

-- Allow unused arguments in functions (common in callbacks)
unused_args = false
unused_secondaries = false