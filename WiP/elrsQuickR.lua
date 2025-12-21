-- TNS|Quick VTX|TNE
-- Minimal helper to send fixed VTX payload sequences for R2/R3

-- Device constants, moist likely not to change
local deviceId = 0xEE
local handsetId = 0xEF
local CENTER_FLAG = CENTER or 0

-- Command constants, moist likely to change depending on your radio
local BAND_COMMAND = 0x0B -- 0x0B for TX15 ELRS -- 0x0E for TX15+Mafia -- 0x0D for Boxer + Mafia
local CHANNEL_COMMAND = 0x0C --0x0C for TX15 ELRS -- 0x0F for TX15+Mafia -- 0x0E for Boxer + Mafia
local APPLY_COMMAND = 0x0F -- 0x0F for TX15 ELRS -- 0x12 for TX15+Mafia -- 0x11 for Boxer + Mafia
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

local frequencies = {
  A = {5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725},
  B = {5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866},
  E = {5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945},
  F = {5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880},
  R = {5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917},
  L = {5362, 5399, 5436, 5473, 5510, 5547, 5584, 5621},
  X = {4990, 5020, 5050, 5080, 5110, 5140, 5170, 5200},
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
        frequency = frequencies[band.prefix] and frequencies[band.prefix][channelIndex] or nil,
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

local DEFAULT_BAND, DEFAULT_CHANNEL = "R", 3
local lastMessage
local messageTimeout = 0
local lastSwitchIndex
local selectedBandIndex = 1
local selectedChannelIndex = DEFAULT_CHANNEL
local refreshButtons
local layout = {
  margin = 10,
  gap = 6,
  btnH = 38,
  bandY = 18,
  rowGap = 12,
  applyH = 40,
}
layout.chanY = layout.bandY + (layout.btnH + layout.gap) * 2 + layout.rowGap
local ui = {
  page = nil,
  bandButtons = {},
  channelButtons = {},
  messageLabel = nil,
  applyButton = nil,
}
local ACTIVE_COLOR = COLOR_THEME_PRIMARY1 or lcd.RGB(0, 180, 255)
local INACTIVE_COLOR = COLOR_THEME_SECONDARY1 or lcd.RGB(70, 70, 70)
local TEXT_COLOR = COLOR_THEME_PRIMARY3 or lcd.RGB(255, 255, 255)

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

local function bandIndexFromValue(val)
  for i, band in ipairs(bands) do
    if band.value == val then
      return i
    end
  end
end

local function bandIndexFromPrefix(prefix)
  for i, band in ipairs(bands) do
    if band.prefix == prefix then
      return i
    end
  end
end

local function setSelection(bandIdx, channelIdx, shouldQueue)
  if bandIdx then
    selectedBandIndex = math.max(1, math.min(#bands, bandIdx))
  end
  if channelIdx then
    selectedChannelIndex = math.max(1, math.min(8, channelIdx))
  end
  local opt = menuRows[selectedBandIndex] and menuRows[selectedBandIndex][selectedChannelIndex]
  if opt then
    if shouldQueue then
      queueVtxSequence(opt)
    end
  end
  if refreshButtons then
    refreshButtons()
  end
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
    local opt = {
      name = preset.name or string.format("%s#%d", SWITCH_SOURCE:upper(), idx),
      bandValue = preset.bandValue,
      channelValue = preset.channelValue,
    }
    local bandIdx = bandIndexFromValue(preset.bandValue)
    if bandIdx then
      setSelection(bandIdx, preset.channelValue, false)
    end
    queueVtxSequence(opt)
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

local function changeChannel(step)
  local newChannel = selectedChannelIndex + step
  if newChannel < 1 then
    newChannel = 8
  elseif newChannel > 8 then
    newChannel = 1
  end
  setSelection(selectedBandIndex, newChannel, false)
end

local function changeBand(step)
  local newBand = selectedBandIndex + step
  if newBand < 1 then
    newBand = #bands
  elseif newBand > #bands then
    newBand = 1
  end
  setSelection(newBand, selectedChannelIndex, false)
end

local function currentOption()
  return menuRows[selectedBandIndex] and menuRows[selectedBandIndex][selectedChannelIndex]
end

local function freqText()
  local band = bands[selectedBandIndex]
  if not band then
    return "Band/Channel not available"
  end
  local opt = currentOption()
  if opt and opt.frequency then
    return string.format("%s%d - %d MHz", band.prefix, selectedChannelIndex, opt.frequency)
  elseif opt then
    return string.format("%s%d - -- MHz", band.prefix, selectedChannelIndex)
  end
  return "Band/Channel not available"
end

local function messageText()
  if lastMessage and getTime() < messageTimeout then
    return lastMessage
  end
  return ""
end

refreshButtons = function()
  for i, btn in ipairs(ui.bandButtons) do
    if btn then
      btn:set({
        color = (i == selectedBandIndex) and ACTIVE_COLOR or INACTIVE_COLOR,
        textColor = TEXT_COLOR,
      })
    end
  end
  for i, btn in ipairs(ui.channelButtons) do
    if btn then
      btn:set({
        color = (i == selectedChannelIndex) and ACTIVE_COLOR or INACTIVE_COLOR,
        textColor = TEXT_COLOR,
      })
    end
  end
  if ui.applyButton then
    ui.applyButton:set({
      text = freqText(),
      color = ACTIVE_COLOR,
      textColor = TEXT_COLOR,
    })
  end
end

local function buildUi()
  lvgl.clear()
  ui.page = lvgl.page({
    title = "Quick VTX",
    subtitle = "",
    scrollable = false,
    titleColor = ACTIVE_COLOR,
    titleFont = DBLSIZE,
  })

  local margin = layout.margin
  local gap = layout.gap
  local btnH = layout.btnH
  local bandY = layout.bandY
  local chanY = layout.chanY

  local function buttonWidth(count, cols)
    local columns = cols or count
    return math.max(60, math.floor((LCD_W - (margin * 2) - (columns - 1) * gap) / columns))
  end

  local function placeRow(items, cols, yStart, buttonsTable, onPress)
    local perRow = cols
    local btnW = buttonWidth(#items, perRow)
    for i = 1, #items do
      local c = ((i - 1) % perRow)
      local r = math.floor((i - 1) / perRow)
      local x = margin + c * (btnW + gap)
      local y = yStart + r * (btnH + gap)
      buttonsTable[i] = ui.page:button({
        x = x,
        y = y,
        w = btnW,
        h = btnH,
        text = items[i].text,
        font = DBLSIZE,
        color = INACTIVE_COLOR,
        textColor = TEXT_COLOR,
        press = function() onPress(i) end
      })
    end
  end

  local bandItems = {}
  for i, b in ipairs(bands) do
    bandItems[i] = { text = b.prefix }
  end
  placeRow(bandItems, 4, bandY, ui.bandButtons, function(idx)
    setSelection(idx, nil, false)
  end)

  local chanItems = {}
  for i = 1, 8 do
    chanItems[i] = { text = tostring(i) }
  end
  placeRow(chanItems, 4, chanY, ui.channelButtons, function(idx)
    setSelection(nil, idx, false)
  end)

  local applyY = chanY + (2 * (btnH + gap)) + 10
  ui.applyButton = ui.page:button({
    x = margin,
    y = applyY,
    w = LCD_W - (margin * 2),
    h = layout.applyH,
    text = freqText(),
    font = MIDSIZE,
    color = ACTIVE_COLOR,
    textColor = TEXT_COLOR,
    press = function()
      local opt = currentOption()
      if opt then
        queueVtxSequence(opt)
      else
        lastMessage = "No band/channel selected"
        messageTimeout = getTime() + 50
      end
    end
  })

  local messageY = applyY + layout.applyH + 4
  ui.messageLabel = ui.page:label({
    x = 0,
    y = messageY,
    w = LCD_W,
    h = 12,
    font = SMLSIZE,
    align = lvgl.ALIGN_CENTER,
    text = function() return messageText() end
  })

  refreshButtons()
end

local function init()
  local defaultBandIdx = bandIndexFromPrefix(DEFAULT_BAND) or 1
  setSelection(defaultBandIdx, DEFAULT_CHANNEL, false)
  buildUi()
end

local function run(event, touchState)
  processQueue()
  handleSwitchPresets()

  if event == nil then
    return 2
  end

  if event == EVT_VIRTUAL_NEXT then
    changeChannel(1)
  elseif event == EVT_VIRTUAL_PREV then
    changeChannel(-1)
  elseif event == EVT_VIRTUAL_ENTER then
    local chosen = menuRows[selectedBandIndex] and menuRows[selectedBandIndex][selectedChannelIndex]
    if chosen then
      queueVtxSequence(chosen)
    end
  elseif event == EVT_VIRTUAL_EXIT then
    return 1
  elseif event == EVT_ROT_RIGHT then
    changeBand(1)
  elseif event == EVT_ROT_LEFT then
    changeBand(-1)
  end
  return 0
end

return { init = init, run = run, useLvgl = true }
