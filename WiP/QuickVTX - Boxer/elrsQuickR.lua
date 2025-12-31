-- TNS|Quick VTX|TNE
-- Minimal helper to send fixed VTX payload sequences for R2/R3

-- Device constants, moist likely not to change
local deviceId = 0xEE
local handsetId = 0xEF
local CENTER_FLAG = CENTER or 0

-- Command constants loaded from config
local BAND_COMMAND
local CHANNEL_COMMAND
local APPLY_COMMAND
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
local channelValues = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 }

-- Switch automation configuration (set SWITCH_SOURCE to nil to disable)
local SWITCH_SOURCE = nil -- radio input name, e.g. "sc", "sd", "s1"
local SWITCH_POSITIONS = {}
local SWITCH_TOLERANCE = 100 -- tolerance for matching switch positions, should be ok without changes

local frequencies = {
  A = {5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725},
  B = {5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866},
  E = {5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945},
  F = {5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880},
  R = {5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917},
  L = {5362, 5399, 5436, 5473, 5510, 5547, 5584, 5621},
  X = {4990, 5020, 5050, 5080, 5110, 5140, 5170, 5200},
}

local commandQueue = {}
local QUEUE_DELAY_TICKS = 5 -- short delay (~0.05s) between queued commands

local selectedBandIndex = 1
local selectedChannelIndex = 1
local focusRow = 1 -- 1=band, 2=channel, 3=apply
local bandRowIndex = 1
local switchDisplayMode = "name"
local lastMessage
local messageTimeout = 0
local lastSwitchIndex

local function parseHexByte(text)
  if not text then
    return nil
  end
  local hex = string.match(text, "0x[%da-fA-F]+")
  if hex then
    return tonumber(string.sub(hex, 3), 16)
  end
  local hexRaw = string.match(text, "^[%da-fA-F]+$")
  if hexRaw then
    return tonumber(hexRaw, 16)
  end
  return tonumber(text)
end

local function bandValueFromPrefix(prefix)
  for _, band in ipairs(bands) do
    if band.prefix == prefix then
      return band.value
    end
  end
end

local function bandIndexFromValue(value)
  for i, band in ipairs(bands) do
    if band.value == value then
      return i
    end
  end
end

local function channelIndexFromValue(value)
  for i, chan in ipairs(channelValues) do
    if chan == value then
      return i
    end
  end
end

local function parseSwitchOption(text)
  if not text then
    return nil
  end
  local prefix, channelText = string.match(text, "^%s*([A-Za-z])%s*(%d+)%s*$")
  local channelNum = tonumber(channelText)
  if not prefix or not channelNum then
    return nil
  end
  prefix = string.upper(prefix)
  local bandValue = bandValueFromPrefix(prefix)
  local channelValue = channelValues[channelNum]
  if not bandValue or not channelValue then
    return nil
  end
  return {
    name = string.format("%s%d", prefix, channelNum),
    bandValue = bandValue,
    channelValue = channelValue,
  }
end

local function loadCommandOverrides()
  local file = io.open("vtxConfig_auto.cfg", "r")
  if not file then
    file = io.open("/SCRIPTS/TOOLS/vtxConfig_auto.cfg", "r")
  end
  if not file then
    return false
  end

  local lines = {}
  local maxLines = 12
  while #lines < maxLines do
    local chunk = io.read(file, 128)
    if not chunk or #chunk == 0 then
      break
    end
    for line in string.gmatch(chunk, "([^\r\n]+)") do
      lines[#lines + 1] = line
      if #lines >= maxLines then
        break
      end
    end
  end
  io.close(file)

  local function stripPrefix(line, label)
    if not line then
      return nil
    end
    local pattern = "^%s*" .. label .. "%s*:%s*(.+)%s*$"
    return string.match(line, pattern)
  end

  local bandVal = stripPrefix(lines[1], "Band")
  local channelVal = stripPrefix(lines[2], "Channel")
  local applyVal = stripPrefix(lines[3], "Command")
  BAND_COMMAND = parseHexByte(bandVal) or BAND_COMMAND
  CHANNEL_COMMAND = parseHexByte(channelVal) or CHANNEL_COMMAND
  APPLY_COMMAND = parseHexByte(applyVal) or APPLY_COMMAND
  return true
end

local function roundValue(value)
  if value >= 0 then
    return math.floor(value + 0.5)
  end
  return math.ceil(value - 0.5)
end

local function loadSwitchOverrides()
  local file = io.open("vtxConfig_auto.cfg", "r")
  if not file then
    file = io.open("/SCRIPTS/TOOLS/vtxConfig_auto.cfg", "r")
  end
  if not file then
    return
  end

  local lines = {}
  while #lines < 64 do
    local chunk = io.read(file, 128)
    if not chunk or #chunk == 0 then
      break
    end
    for line in string.gmatch(chunk, "([^\r\n]+)") do
      lines[#lines + 1] = line
      if #lines >= 64 then
        break
      end
    end
  end
  io.close(file)

  local positionsCount
  local positionsMap = {}
  for _, line in ipairs(lines) do
    local switchVal = string.match(line, "^%s*Switch:%s*(.+)%s*$")
    if switchVal then
      switchVal = string.lower(switchVal)
      SWITCH_SOURCE = (switchVal ~= "" and switchVal) or nil
    end
    local positionsVal = string.match(line, "^%s*Positions:%s*(.+)%s*$")
    if positionsVal then
      positionsCount = tonumber(positionsVal)
    end
    local posIndex, posValue = string.match(line, "^%s*Pos(%d+)%s*:%s*(.+)%s*$")
    if posIndex and posValue then
      positionsMap[tonumber(posIndex)] = posValue
    end
  end

  local count = positionsCount or 0
  if count < 1 then
    count = #positionsMap
  end
  if count < 1 then
    return
  end

  local step = (count > 1) and (2000 / (count - 1)) or 0
  local overrides = {}
  for i = 1, count do
    local option = parseSwitchOption(positionsMap[i])
    if option then
      local value = (count == 1) and 0 or (1000 - (i - 1) * step)
      option.value = roundValue(value)
      overrides[#overrides + 1] = option
    end
  end

  if #overrides > 0 then
    SWITCH_POSITIONS = overrides
  end
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
  if not BAND_COMMAND or not CHANNEL_COMMAND or not APPLY_COMMAND then
    lastMessage = "Commands not configured"
    messageTimeout = getTime() + 50
    return
  end
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
    local bandIdx = bandIndexFromValue(preset.bandValue)
    local channelIdx = channelIndexFromValue(preset.channelValue)
    if bandIdx then
      selectedBandIndex = bandIdx
      if bandRowIndex <= #bands then
        bandRowIndex = bandIdx
      end
    end
    if channelIdx then
      selectedChannelIndex = channelIdx
    end
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

local function currentOption()
  local band = bands[selectedBandIndex]
  if not band then
    return nil
  end
  local channelValue = channelValues[selectedChannelIndex]
  if not channelValue then
    return nil
  end
  local frequency = frequencies[band.prefix] and frequencies[band.prefix][selectedChannelIndex] or nil
  return {
    name = string.format("%s%d", band.prefix, selectedChannelIndex),
    bandValue = band.value,
    channelValue = channelValue,
    frequency = frequency,
  }
end

local function freqText()
  local opt = currentOption()
  if not opt then
    return "Apply: --"
  end
  if opt.frequency then
    return string.format("Apply: %s - %d", opt.name, opt.frequency)
  end
  return string.format("Apply: %s - --", opt.name)
end

local function switchButtonText()
  if switchDisplayMode == "count" then
    return tostring(#SWITCH_POSITIONS)
  end
  if not SWITCH_SOURCE then
    return "--"
  end
  return string.upper(SWITCH_SOURCE)
end

local function drawRow(items, selectedIndex, y, columns, isFocused, forceInvertIndex)
  local margin = 6
  local availableWidth = math.max(1, LCD_W - (margin * 2))
  local colWidth = math.max(14, math.floor(availableWidth / math.max(1, columns)))
  for i = 1, #items do
    local attr = (isFocused and i == selectedIndex) and INVERS or 0
    if forceInvertIndex and i == forceInvertIndex then
      attr = INVERS
    end
    local centerX = margin + (i - 0.5) * colWidth
    lcd.drawText(centerX, y, items[i], attr + CENTER_FLAG)
  end
end

local function drawScreen()
  lcd.clear()

  local bandItems = {}
  for i, band in ipairs(bands) do
    bandItems[i] = band.prefix
  end
  bandItems[#bandItems + 1] = switchButtonText()
  local channelItems = {}
  for i = 1, #channelValues do
    channelItems[i] = tostring(i)
  end

  drawRow(bandItems, bandRowIndex, 0, #bandItems, focusRow == 1, #bandItems)
  drawRow(channelItems, selectedChannelIndex, 14, #channelItems, focusRow == 2)
  local applyAttr = INVERS + CENTER_FLAG
  lcd.drawText(math.floor(LCD_W / 2), 28, freqText(), applyAttr)

  if lastMessage and getTime() < messageTimeout then
    lcd.drawText(2, LCD_H - 12, lastMessage, 0)
  end
end

local function init()
  loadCommandOverrides()
  loadSwitchOverrides()
  drawScreen()
end

local function run(event)
  processQueue()
  handleSwitchPresets()

  if event == nil then
    return 2
  end

  if event == EVT_PAGEDN_FIRST then
    focusRow = focusRow + 1
    if focusRow > 3 then
      focusRow = 1
    end
  elseif event == EVT_PAGEUP_FIRST then
    focusRow = focusRow - 1
    if focusRow < 1 then
      focusRow = 3
    end
  elseif event == EVT_VIRTUAL_ENTER then
    if focusRow == 1 and bandRowIndex == (#bands + 1) then
      if switchDisplayMode == "name" then
        switchDisplayMode = "count"
      else
        switchDisplayMode = "name"
      end
    elseif focusRow == 3 then
      local chosen = currentOption()
      if chosen then
        queueVtxSequence(chosen)
      end
    end
  elseif event == EVT_VIRTUAL_EXIT then
    return 1
  elseif event == EVT_ROT_RIGHT then
    if focusRow == 1 then
      bandRowIndex = bandRowIndex + 1
      if bandRowIndex > (#bands + 1) then
        bandRowIndex = 1
      end
      if bandRowIndex <= #bands then
        selectedBandIndex = bandRowIndex
      end
    elseif focusRow == 2 then
      selectedChannelIndex = selectedChannelIndex + 1
      if selectedChannelIndex > #channelValues then
        selectedChannelIndex = 1
      end
    end
  elseif event == EVT_ROT_LEFT then
    if focusRow == 1 then
      bandRowIndex = bandRowIndex - 1
      if bandRowIndex < 1 then
        bandRowIndex = #bands + 1
      end
      if bandRowIndex <= #bands then
        selectedBandIndex = bandRowIndex
      end
    elseif focusRow == 2 then
      selectedChannelIndex = selectedChannelIndex - 1
      if selectedChannelIndex < 1 then
        selectedChannelIndex = #channelValues
      end
    end
  end

  drawScreen()
  return 0
end

return { init = init, run = run }
