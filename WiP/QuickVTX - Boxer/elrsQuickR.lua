-- TNS|Quick VTX|TNE
-- Minimal helper to send fixed VTX payload sequences for R2/R3

-- Device constants, moist likely not to change
local deviceId = 0xEE
local handsetId = 0xEF
local CENTER_FLAG = CENTER or 0

-- Command constants, moist likely to change depending on your radio
local DEFAULT_BAND_COMMAND = 0x0D -- 0x0B for TX15 ELRS -- 0x0E for TX15+Mafia -- 0x0D for Boxer + Mafia
local DEFAULT_CHANNEL_COMMAND = 0x0E -- 0x0C for TX15 ELRS -- 0x0F for TX15+Mafia -- 0x0E for Boxer + Mafia
local DEFAULT_APPLY_COMMAND = 0x11 -- 0x0F for TX15 ELRS -- 0x12 for TX15+Mafia -- 0x11 for Boxer + Mafia
local BAND_COMMAND = DEFAULT_BAND_COMMAND
local CHANNEL_COMMAND = DEFAULT_CHANNEL_COMMAND
local APPLY_COMMAND = DEFAULT_APPLY_COMMAND
-- This is static as well, just put it here
local APPLY_VALUE = 0x01

-- Adjust values to match your VTX band mapping if needed
local bands = {
  { prefix = "A", value = 0x01 },
  { prefix = "B", value = 0x02 },
  { prefix = "E", value = 0x03 },
  { prefix = "F", value = 0x04 },
  { prefix = "R", value = 0x05 },
  { prefix = "L", value = 0x06 },
  { prefix = "X", value = 0x07 },
}

-- Switch automation configuration (set SWITCH_SOURCE to nil to disable)
local SWITCH_SOURCE = "sc" -- radio input name, e.g. "sc", "sd", "s1"
local SWITCH_POSITIONS = {
  { value = 1000,  bandValue = 0x05, channelValue = 0x01, name = "R1" }, -- switch fully up
  { value = 0,     bandValue = 0x06, channelValue = 0x04, name = "L4" }, -- middle
  { value = -1000, bandValue = 0x07, channelValue = 0x08, name = "X8" }, -- fully down
}
local SWITCH_TOLERANCE = 100 -- tolerance for matching switch positions, should be ok without changes

local function generateOptions()
  local rows = {}
  local flat = {}
  local channelValues = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 }

  for bandIndex, band in ipairs(bands) do
    rows[bandIndex] = {}
    for channelIndex = 1, #channelValues do
      local option = {
        name = string.format("%s%d", band.prefix, channelIndex),
        bandValue = band.value,
        channelValue = channelValues[channelIndex],
      }
      option.index = #flat + 1
      option.row = bandIndex
      option.col = channelIndex
      rows[bandIndex][channelIndex] = option
      flat[#flat + 1] = option
    end
  end

  return rows, flat
end

local menuRows, options = generateOptions()

local commandQueue = {}
local QUEUE_DELAY_TICKS = 5 -- short delay (~0.05s) between queued commands

local selection = 1
local lastMessage
local messageTimeout = 0
local lastSwitchIndex

local function parseHexByte(text)
  if not text then
    return nil
  end
  local hex = string.match(text, "0x[%da-fA-F]+")
  if not hex then
    return nil
  end
  return tonumber(hex, 16)
end

local function loadCommandOverrides()
  local ok, file = pcall(io.open, "/SCRIPTS/TOOLS/vtxConfig.cfg", "r")
  if not ok or not file then
    ok, file = pcall(io.open, "vtxConfig.cfg", "r")
  end
  if not ok or not file then
    return
  end

  local function applyLine(line)
    local bandVal = string.match(line, "^%s*Band:%s*(.+)$")
    if bandVal then
      BAND_COMMAND = parseHexByte(bandVal) or BAND_COMMAND
      return
    end
    local channelVal = string.match(line, "^%s*Channel:%s*(.+)$")
    if channelVal then
      CHANNEL_COMMAND = parseHexByte(channelVal) or CHANNEL_COMMAND
      return
    end
    local applyVal = string.match(line, "^%s*Command:%s*(.+)$")
    if applyVal then
      APPLY_COMMAND = parseHexByte(applyVal) or APPLY_COMMAND
      return
    end
  end

  while true do
    local chunk = io.read(file, 128)
    if not chunk or #chunk == 0 then
      break
    end
    for line in string.gmatch(chunk, "([^\r\n]+)") do
      applyLine(line)
    end
  end

  io.close(file)
end

local function queueStep(label, command, value)
  local due = getTime()
  if #commandQueue > 0 then
    local lastDue = commandQueue[#commandQueue].due
    if lastDue and lastDue >= due then
      due = lastDue + QUEUE_DELAY_TICKS
    end
  end
  commandQueue[#commandQueue + 1] = {
    due = due,
    label = label,
    command = command,
    value = value,
  }
end

local function queueVtxSequence(opt)
  commandQueue = {}
  local baseLabel = opt.name or "Preset"
  queueStep(baseLabel .. " band", BAND_COMMAND, opt.bandValue)
  queueStep(baseLabel .. " channel", CHANNEL_COMMAND, opt.channelValue)
  queueStep("Apply", APPLY_COMMAND, APPLY_VALUE)
  lastMessage = "Queued " .. baseLabel .. " sequence"
  messageTimeout = getTime() + 50 -- ~0.5s
end

local function resolveSwitchPreset(value)
  if type(value) ~= "number" then
    return
  end
  for idx, preset in ipairs(SWITCH_POSITIONS) do
    local tolerance = preset.tolerance or SWITCH_TOLERANCE
    if math.abs(value - preset.value) <= tolerance then
      return preset, idx
    end
  end
end

local function handleSwitchPresets()
  if not SWITCH_SOURCE or #SWITCH_POSITIONS == 0 then
    return
  end
  local raw = getValue(SWITCH_SOURCE)
  if raw == nil then
    return
  end

  local preset, idx = resolveSwitchPreset(raw)
  if not preset or not preset.bandValue or not preset.channelValue then
    lastSwitchIndex = nil
    return
  end

  if idx ~= lastSwitchIndex then
    lastSwitchIndex = idx
    queueVtxSequence({
      name = preset.name or string.format("%s#%d", SWITCH_SOURCE:upper(), idx),
      bandValue = preset.bandValue,
      channelValue = preset.channelValue,
    })
  end
end

local function shiftQueue()
  if not commandQueue[1] then
    return
  end
  local count = #commandQueue
  for i = 2, count do
    commandQueue[i - 1] = commandQueue[i]
  end
  commandQueue[count] = nil
end

local function processQueue()
  local nextCmd = commandQueue[1]
  if not nextCmd then
    return
  end
  if getTime() < nextCmd.due then
    return
  end

  local payload = { deviceId, handsetId, nextCmd.command, nextCmd.value }
  crossfireTelemetryPush(0x2D, payload)
  lastMessage = "Sent " .. nextCmd.label
  messageTimeout = getTime() + 50
  shiftQueue()

  if commandQueue[1] and commandQueue[1].due < getTime() then
    commandQueue[1].due = getTime() + QUEUE_DELAY_TICKS
  end
end

local function drawScreen()
  lcd.clear()

  local margin = 10
  local maxCols = 0
  for rowIndex = 1, #menuRows do
    if #menuRows[rowIndex] > maxCols then
      maxCols = #menuRows[rowIndex]
    end
  end

  local availableWidth = math.max(1, LCD_W - (margin * 2))
  local colWidth = math.max(14, math.floor(availableWidth / math.max(1, maxCols)))
  local topY = 0
  local bottomReserve = 20
  local availableHeight = math.max(0, LCD_H - topY - bottomReserve)
  local lineSpacing = math.max(11, math.floor(availableHeight / math.max(1, #menuRows)) - 1)
  local y = topY

  for rowIndex = 1, #menuRows do
    local row = menuRows[rowIndex]
    for colIndex = 1, #row do
      local opt = row[colIndex]
      local attr = (opt.index == selection) and INVERS or 0
      local centerX = margin + (colIndex - 0.5) * colWidth
      lcd.drawText(centerX, y, opt.name, attr + CENTER_FLAG)
    end
    y = y + lineSpacing
  end

  if lastMessage and getTime() < messageTimeout then
    lcd.drawText(10, LCD_H - 20, lastMessage, 0)
  end
end

local function init()
  loadCommandOverrides()
  drawScreen()
end

local function run(event)
  processQueue()
  handleSwitchPresets()

  if event == nil then
    return 2
  end

  if event == EVT_VIRTUAL_NEXT then
    selection = selection + 1
    if selection > #options then
      selection = 1
    end
  elseif event == EVT_VIRTUAL_PREV then
    selection = selection - 1
    if selection < 1 then
      selection = #options
    end
  elseif event == EVT_VIRTUAL_ENTER then
    local chosen = options[selection]
    if chosen then
      queueVtxSequence(chosen)
    end
  elseif event == EVT_VIRTUAL_EXIT then
    return 1
  end

  drawScreen()
  return 0
end

return { init = init, run = run }
