-- TNS|Quick VTX|TNE
-- Minimal helper to send fixed VTX payload sequences for R2/R3

local deviceId = 0xEE
local handsetId = 0xEF
local CENTER_FLAG = CENTER or 0
-- Adjust accordingly to your device
local BAND_IDX = 0x0E
local CHANNEL_IDX = 0x0F
local APPLY_COMMAND = 0x12
local APPLY_VALUE = 0x01

local bands = {
  { prefix = "R", value = 0x05 },
  { prefix = "L", value = 0x06 },
  { prefix = "X", value = 0x07 },
}

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

local function queueVtxSequence(opt)
  commandQueue = {}
  local baseLabel = opt.name or "Preset"
  queueStep(baseLabel .. " band", BAND_IDX, opt.bandValue)
  queueStep(baseLabel .. " channel", CHANNEL_IDX, opt.channelValue)
  queueStep("Apply", APPLY_COMMAND, APPLY_VALUE)
  lastMessage = "Queued " .. baseLabel .. " sequence"
  messageTimeout = getTime() + 50 -- ~0.5s
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
  lcd.drawText(10, 5, "Quick VTX presets", MIDSIZE)

  local margin = 10
  local maxCols = 0
  for rowIndex = 1, #menuRows do
    if #menuRows[rowIndex] > maxCols then
      maxCols = #menuRows[rowIndex]
    end
  end

  local availableWidth = math.max(1, LCD_W - (margin * 2))
  local colWidth = math.max(14, math.floor(availableWidth / math.max(1, maxCols)))
  local topY = 30
  local availableHeight = math.max(0, LCD_H - topY - 40)
  local lineSpacing = math.min(32, math.max(16, math.floor(availableHeight / math.max(1, #menuRows))))
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
  drawScreen()
end

local function run(event)
  processQueue()

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
