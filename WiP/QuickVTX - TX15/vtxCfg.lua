-- ########################################################
-- ## CONFIGURABLE PART. FEEL FREE TO ADJUST YOUR VALUES ##
-- ########################################################

return {
  -- Command constants, most likely to change depending on your radio
  BAND_COMMAND = 0x0D, -- 0x0D for Boxer + Mafia
  CHANNEL_COMMAND = 0x0E, -- 0x0E for Boxer + Mafia
  APPLY_COMMAND = 0x11, -- 0x11 for Boxer + Mafia

  -- Switch automation configuration (set SWITCH_SOURCE to nil to disable)
  SWITCH_SOURCE = "sc", -- radio input name, e.g. "sc", "sd", "s1"
  SWITCH_POSITIONS = {
    { value = 1000,  bandValue = 0x05, channelValue = 0x01, name = "R1" }, -- switch fully up
    { value = 0,     bandValue = 0x06, channelValue = 0x04, name = "L4" }, -- middle
    { value = -1000, bandValue = 0x07, channelValue = 0x08, name = "X8" }, -- fully down
  },
}
