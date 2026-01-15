-- TNS|Quick VTX|TNE
-- Minimal helper to send fixed VTX payload sequences for R2/R3

-- Device constants, moist likely not to change
local deviceId = 0xEE
local handsetId = 0xEF
local CENTER_FLAG = CENTER or 0
local RIGHT_FLAG = RIGHT or 0

-- Command constants loaded from config
local BAND_COMMAND
local CHANNEL_COMMAND
local APPLY_COMMAND
-- This is static as well, just put it here
local APPLY_VALUE = 0x01
local cfgPathTemplate = "_internal/vtxConfig_%s.cfg"
local cfgPathResolved = nil
local childPath = "_internal/vtx_auto.lua"
local child = nil
local childActive = false
local childError = nil
local mainInitDone = false

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
local SCAN_STEP_TICKS_DEFAULT = 500 -- ~5s per channel

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
local scanActive = false
local scanMode = nil
local scanBandIndex = 1
local scanChannelIndex = 1
local scanNextTick = 0
local scanStepTicks = SCAN_STEP_TICKS_DEFAULT
local scanDirection = 1
local lastVirtualNextTick = -1
local lastVirtualPrevTick = -1
local lastPageEventTick = -100
local PAGE_EVENT_COOLDOWN = 20
local skipBands = {}

local function isPageNext(event)
  if event == EVT_PAGEDN_FIRST or event == EVT_PAGEDN_LONG then
    local now = (getTime and getTime()) or lastPageEventTick or 0
    lastPageEventTick = now
    return true
  end
  if event == EVT_VIRTUAL_NEXT_PAGE then
    local now = (getTime and getTime()) or lastPageEventTick or 0
    if type(lastPageEventTick) ~= "number" then
      lastPageEventTick = now
    end
    if now == lastVirtualNextTick or (now - lastPageEventTick) <= PAGE_EVENT_COOLDOWN then
      return false
    end
    lastVirtualNextTick = now
    lastPageEventTick = now
    return true
  end
  return false
end

local function isPagePrev(event)
  if event == EVT_PAGEUP_FIRST or event == EVT_PAGEUP_LONG then
    local now = (getTime and getTime()) or lastPageEventTick or 0
    lastPageEventTick = now
    return true
  end
  if event == EVT_VIRTUAL_PREV_PAGE then
    local now = (getTime and getTime()) or lastPageEventTick or 0
    if type(lastPageEventTick) ~= "number" then
      lastPageEventTick = now
    end
    if now == lastVirtualPrevTick or (now - lastPageEventTick) <= PAGE_EVENT_COOLDOWN then
      return false
    end
    lastVirtualPrevTick = now
    lastPageEventTick = now
    return true
  end
  return false
end

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

local function toHexByte(val)
  if not val then
    return ""
  end
  return string.format("0x%02X", val)
end

local function computeDeviceIdHash(commandId)
  local ver, radio, maj, minor, rev, osname = getVersion()
  local input = (ver or "") .. "|" .. (radio or "") .. "|" .. (osname or "") .. "|" .. tostring(commandId or "")
  local hash = 5381
  if bit32 then
    for i = 1, #input do
      hash = bit32.band(bit32.lshift(hash, 5) + hash + string.byte(input, i), 0xFFFFFFFF)
    end
  else
    for i = 1, #input do
      hash = (hash * 33 + string.byte(input, i)) % 4294967296
    end
  end
  return string.format("%08X", hash)
end

local function cfgPathForHash(hash)
  if not hash or hash == "" then
    return nil
  end
  return string.format(cfgPathTemplate, hash)
end

local function updateResolvedConfigPath(commandId)
  local hash = commandId and computeDeviceIdHash(commandId) or nil
  cfgPathResolved = hash and cfgPathForHash(hash) or nil
end

local function initChild()
  local loaded = loadScript(childPath)
  if type(loaded) == "function" then
    loaded = loaded()
  end
  if type(loaded) ~= "table" or type(loaded.run) ~= "function" then
    childError = "Child load failed"
    return false
  end
  child = loaded
  if type(child.init) == "function" then
    child.init()
  end
  return true
end

local vtxAutoInitDone = false

local function getCommandIdFromInternal()
  if VTX_AUTO_LAST_COMMAND_ID then
    return VTX_AUTO_LAST_COMMAND_ID
  end
  local loaded = loadScript("_internal/vtx_auto.lua")
  if type(loaded) == "function" then
    loaded = loaded()
  end
  if type(loaded) == "table" then
    if not vtxAutoInitDone and type(loaded.init) == "function" then
      loaded.init()
      vtxAutoInitDone = true
    end
    if type(loaded.getLastCommandId) == "function" then
      return loaded.getLastCommandId()
    end
  end
  return nil
end

local function normalizeDeviceId(deviceId)
  return string.upper(string.gsub(deviceId or "", "^%s*(.-)%s*$", "%1"))
end

local function normalizeEmail(email)
  return string.lower(string.gsub(email or "", "^%s*(.-)%s*$", "%1"))
end

local function normalizeHex(text)
  local hex = string.match(text or "", "0x([%da-fA-F]+)")
  if not hex then
    hex = string.match(text or "", "([%da-fA-F]+)")
  end
  if not hex then
    return ""
  end
  return string.upper(hex)
end

local function computeLicense(deviceId, email)
  local input = normalizeDeviceId(deviceId) .. "|" .. normalizeEmail(email)
  local hash = 5381
  if bit32 then
    for i = 1, #input do
      hash = bit32.band(bit32.lshift(hash, 5) + hash + string.byte(input, i), 0xFFFFFFFF)
    end
  else
    for i = 1, #input do
      hash = (hash * 33 + string.byte(input, i)) % 4294967296
    end
  end
  return string.format("%08X", hash)
end

local function readFileLines(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local lines = {}
  local pending = ""
  while true do
    local chunk = io.read(file, 128)
    if not chunk or #chunk == 0 then
      break
    end
    local text = pending .. chunk
    local start = 1
    while true do
      local i, j = string.find(text, "[\r\n]", start)
      if not i then
        break
      end
      local line = string.sub(text, start, i - 1)
      if line ~= "" then
        lines[#lines + 1] = line
      end
      start = j + 1
      while start <= #text do
        local c = string.sub(text, start, start)
        if c ~= "\r" and c ~= "\n" then
          break
        end
        start = start + 1
      end
    end
    pending = string.sub(text, start)
  end
  if pending ~= "" then
    lines[#lines + 1] = pending
  end
  io.close(file)
  return lines
end

local function stripPrefix(line, label)
  if not line then
    return nil
  end
  local pattern = "^%s*" .. label .. "%s*[:=]%s*(.+)%s*$"
  return string.match(line, pattern)
end

local configMissing = false
local licenseError = nil
local configMissingDetail = nil

local function readConfigLines()
  configMissingDetail = nil
  local internalCommandId = getCommandIdFromInternal()
  if internalCommandId then
    updateResolvedConfigPath(internalCommandId)
    local deviceHash = computeDeviceIdHash(internalCommandId)
    local hashPath = cfgPathForHash(deviceHash)
    if hashPath then
      local hashLines = readFileLines(hashPath)
      if not hashLines then
        hashLines = readFileLines("/SCRIPTS/TOOLS/" .. hashPath)
      end
      if hashLines and #hashLines > 0 then
        return hashLines
      end
    end
  end
  if cfgPathResolved then
    local resolvedLines = readFileLines(cfgPathResolved)
    if not resolvedLines then
      resolvedLines = readFileLines("/SCRIPTS/TOOLS/" .. cfgPathResolved)
    end
    if resolvedLines and #resolvedLines > 0 then
      return resolvedLines
    end
  end
  if internalCommandId and cfgPathResolved then
    configMissingDetail = cfgPathResolved .. " (cmd " .. toHexByte(internalCommandId) .. ")"
  else
    configMissingDetail = cfgPathResolved or cfgPathTemplate
  end
  return nil
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
  local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
  local lowered = string.lower(trimmed)
  if string.match(lowered, "^scan") then
    local scanSeconds = tonumber(string.match(lowered, "(%d+)"))
    local scanDirection = (string.find(lowered, "<") ~= nil) and -1 or 1
    if scanSeconds then
      if scanSeconds < 1 then
        scanSeconds = 1
      elseif scanSeconds > 10 then
        scanSeconds = 10
      end
    end
    return {
      name = "Scan",
      mode = "scan",
      scanDirection = scanDirection,
      scanSeconds = scanSeconds,
    }
  elseif lowered == "none" then
    return {
      name = "None",
      mode = "none",
    }
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
  local lines = readConfigLines()
  if not lines then
    return false
  end

  for i = 1, #lines do
    local line = lines[i]
    local bandVal = stripPrefix(line, "Band")
    if bandVal then
      BAND_COMMAND = parseHexByte(bandVal) or BAND_COMMAND
    end
    local channelVal = stripPrefix(line, "Channel")
    if channelVal then
      CHANNEL_COMMAND = parseHexByte(channelVal) or CHANNEL_COMMAND
    end
    local applyVal = stripPrefix(line, "Command")
    if applyVal then
      APPLY_COMMAND = parseHexByte(applyVal) or APPLY_COMMAND
    end
  end
  return true
end

local function roundValue(value)
  if value >= 0 then
    return math.floor(value + 0.5)
  end
  return math.ceil(value - 0.5)
end

local function loadSwitchOverrides()
  local lines = readConfigLines()
  if not lines then
    return
  end

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
      local value = (count == 1) and 0 or (-1000 + (i - 1) * step)
      option.value = roundValue(value)
      overrides[#overrides + 1] = option
    end
  end

  if #overrides > 0 then
    SWITCH_POSITIONS = overrides
  end
end

local function loadSkipBands()
  skipBands = {}
  local lines = readConfigLines()
  if not lines then
    return
  end
  for _, line in ipairs(lines) do
    local skipVal = stripPrefix(line, "Skip")
    if skipVal then
      local letters = string.match(skipVal, "^%s*([A-Za-z]+)")
      for letter in string.gmatch(letters or "", "%a") do
        local prefix = string.upper(letter)
        if bandValueFromPrefix(prefix) then
          skipBands[prefix] = true
        end
      end
    end
  end
end

local function isBandSkipped(prefix)
  return skipBands[string.upper(prefix or "")] == true
end

local function alignScanToAllowedBand(direction)
  if #bands == 0 then
    return false
  end
  local guard = 0
  local band = bands[scanBandIndex]
  local channelReset = (direction == -1) and #channelValues or 1
  while band and isBandSkipped(band.prefix) and guard < #bands do
    scanBandIndex = scanBandIndex + (direction or 1)
    if scanBandIndex > #bands then
      scanBandIndex = 1
    elseif scanBandIndex < 1 then
      scanBandIndex = #bands
    end
    scanChannelIndex = channelReset
    band = bands[scanBandIndex]
    guard = guard + 1
  end
  return band and not isBandSkipped(band.prefix)
end

local function bandRowType(index)
  local switchIndex = #bands + 1
  if index <= #bands then
    return "band", index
  end
  if index == switchIndex then
    return "switch"
  end
end

local function startScan(fromCurrent, stepSeconds, direction)
  scanActive = true
  scanMode = "scan"
  scanDirection = direction or 1
  if stepSeconds and stepSeconds > 0 then
    scanStepTicks = stepSeconds * 100
  else
    scanStepTicks = SCAN_STEP_TICKS_DEFAULT
  end
  if fromCurrent then
    scanBandIndex = selectedBandIndex or 1
    scanChannelIndex = selectedChannelIndex or 1
  else
    scanBandIndex = 1
    scanChannelIndex = 1
  end
  scanNextTick = 0
end

local function stopScan(mode)
  scanActive = false
  if mode == "none" then
    scanMode = "none"
  else
    scanMode = nil
  end
end

local function setSwitchMode()
  scanActive = false
  scanMode = "switch"
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

local function queueVtxSequence(opt, suppressMessage)
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
  if not suppressMessage then
    lastMessage = "Queued " .. baseLabel .. " sequence"
    messageTimeout = getTime() + 50 -- ~0.5s
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
  if not preset then
    lastSwitchIndex = nil
    return
  end

  if idx ~= lastSwitchIndex then
    lastSwitchIndex = idx
    if preset.mode == "scan" then
      bandRowIndex = #bands + 1
      startScan(true, preset.scanSeconds, preset.scanDirection)
      return
    elseif preset.mode == "none" then
      bandRowIndex = #bands + 2
      stopScan("none")
      return
    elseif not preset.bandValue or not preset.channelValue then
      lastSwitchIndex = nil
      return
    else
      setSwitchMode()
    end
    local bandIdx = bandIndexFromValue(preset.bandValue)
    local channelIdx = channelIndexFromValue(preset.channelValue)
    if bandIdx then
      selectedBandIndex = bandIdx
      bandRowIndex = bandIdx
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

local function updateScan()
  if not scanActive then
    return
  end
  if #commandQueue > 0 then
    return
  end
  local now = getTime()
  if scanNextTick == 0 or now >= scanNextTick then
    if not alignScanToAllowedBand(scanDirection) then
      scanActive = false
      lastMessage = "Scan: no bands"
      messageTimeout = getTime() + 100
      return
    end
    local band = bands[scanBandIndex]
    local channelValue = channelValues[scanChannelIndex]
    if band and channelValue then
      queueVtxSequence({
        name = string.format("Scan %s%d", band.prefix, scanChannelIndex),
        bandValue = band.value,
        channelValue = channelValue,
      }, true)
      scanNextTick = now + scanStepTicks
      scanChannelIndex = scanChannelIndex + scanDirection
      if scanChannelIndex > #channelValues then
        scanChannelIndex = 1
        local guard = 0
        repeat
          scanBandIndex = scanBandIndex + scanDirection
          if scanBandIndex > #bands then
            scanBandIndex = 1
          elseif scanBandIndex < 1 then
            scanBandIndex = #bands
          end
          guard = guard + 1
        until (guard >= #bands) or not isBandSkipped(bands[scanBandIndex].prefix)
      elseif scanChannelIndex < 1 then
        scanChannelIndex = #channelValues
        local guard = 0
        repeat
          scanBandIndex = scanBandIndex + scanDirection
          if scanBandIndex > #bands then
            scanBandIndex = 1
          elseif scanBandIndex < 1 then
            scanBandIndex = #bands
          end
          guard = guard + 1
        until (guard >= #bands) or not isBandSkipped(bands[scanBandIndex].prefix)
      end
    end
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
  if scanActive then
    return "Apply: Auto"
  end
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

  local uiTopOffset = 12
  local cmdForHash = APPLY_COMMAND or getCommandIdFromInternal()
  local hash = cmdForHash and computeDeviceIdHash(cmdForHash) or nil
  local headerText = "Quick VTX: " .. (hash or "N/A")
  lcd.drawText(2, 0, headerText)

  if configMissing or licenseError then
    local title = configMissing and "Config not found!" or "License error"
    local detail = configMissing and (configMissingDetail or cfgPathTemplate) or (licenseError or "License mismatch")
    lcd.drawText(2, uiTopOffset + 2, title)
    lcd.drawText(2, uiTopOffset + 16, detail)
    return
  end

  local bandItems = {}
  for i, band in ipairs(bands) do
    bandItems[i] = band.prefix
  end
  bandItems[#bandItems + 1] = switchButtonText()
  local channelItems = {}
  for i = 1, #channelValues do
    channelItems[i] = tostring(i)
  end

  local switchIndex = #bandItems
  drawRow(bandItems, bandRowIndex, uiTopOffset, #bandItems, focusRow == 1, switchIndex)
  drawRow(channelItems, selectedChannelIndex, uiTopOffset + 14, #channelItems, focusRow == 2)
  local applyAttr = INVERS + CENTER_FLAG
  local applyText = freqText()
  if focusRow == 3 then
    applyText = "> " .. applyText .. " <"
  end
  lcd.drawText(math.floor(LCD_W / 2), uiTopOffset + 28, applyText, applyAttr)

  if lastMessage and getTime() < messageTimeout then
    lcd.drawText(2, LCD_H - 12, lastMessage, 0)
  end
  if scanMode then
    local modeText
    if scanMode == "scan" then
      local seconds = math.max(1, math.floor((scanStepTicks or SCAN_STEP_TICKS_DEFAULT) / 100))
      local dir = (scanDirection == -1) and "<" or ">"
      modeText = string.format("Scan(%d)%s", seconds, dir)
    elseif scanMode == "none" then
      modeText = "None"
    else
      modeText = "Switch"
    end
    lcd.drawText(LCD_W - 2, LCD_H - 12, modeText, INVERS + RIGHT_FLAG)
  end
end

local function checkLicense()
  if not APPLY_COMMAND then
    APPLY_COMMAND = getCommandIdFromInternal() or APPLY_COMMAND
  end
  if APPLY_COMMAND then
    updateResolvedConfigPath(APPLY_COMMAND)
  end
  if not APPLY_COMMAND then
    local cfgLines = readConfigLines()
    if cfgLines then
      local seenCommand = nil
      for i = 1, #cfgLines do
        local applyVal = stripPrefix(cfgLines[i], "Command")
        if applyVal then
          seenCommand = applyVal
          APPLY_COMMAND = parseHexByte(applyVal) or APPLY_COMMAND
          if APPLY_COMMAND then
            break
          end
        end
      end
      if not APPLY_COMMAND and seenCommand then
        return false, "Command parse failed: " .. tostring(seenCommand)
      end
    end
  end
  if not APPLY_COMMAND then
    return false, "Command missing in vtxConfig"
  end
  local deviceHash = computeDeviceIdHash(APPLY_COMMAND)
  local licenseName = "_internal/license_" .. deviceHash .. ".txt"
  local lines = readFileLines(licenseName)
  if not lines then
    lines = readFileLines("/SCRIPTS/TOOLS/" .. licenseName)
  end
  if not lines then
    return false, "License file missing: " .. deviceHash
  end
  local deviceId = nil
  local email = nil
  local licenseVal = nil
  for i = 1, #lines do
    deviceId = deviceId or stripPrefix(lines[i], "DEVICEID")
    email = email or stripPrefix(lines[i], "EMAIL")
    licenseVal = licenseVal or stripPrefix(lines[i], "LICENSE")
  end
  if not (deviceId and email and licenseVal) then
    return false, "License data missing"
  end
  local expectedLicense = computeLicense(deviceId, email)
  local deviceMatch = normalizeHex(deviceId) == normalizeHex(deviceHash)
  if not deviceMatch then
    return false, "Device ID mismatch"
  end
  local licenseMatch = normalizeHex(licenseVal) == normalizeHex(expectedLicense)
  if not licenseMatch then
    return false, "License mismatch"
  end
  return true
end

local function init()
  local cmd = getCommandIdFromInternal()
  if cmd then
    updateResolvedConfigPath(cmd)
  else
    if initChild() then
      childActive = true
      return
    end
  end

  if not loadCommandOverrides() then
    configMissing = true
    drawScreen()
    return
  end
  loadSwitchOverrides()
  loadSkipBands()
  local ok, err = checkLicense()
  if not ok then
    licenseError = err
    drawScreen()
    return
  end
  drawScreen()
  mainInitDone = true
end

local function run(event)
  if childActive then
    if childError then
      configMissing = true
      drawScreen()
      childActive = false
      return 0
    end
    local res = child and child.run and child.run(event) or 0
    if res == 1 then
      childActive = false
      local cmd = getCommandIdFromInternal()
      if cmd then
        updateResolvedConfigPath(cmd)
      end
      if not mainInitDone then
        init()
      end
    end
    return 0
  end

  if configMissing or licenseError then
    if event == EVT_VIRTUAL_EXIT then
      return 1
    end
    return 0
  end

  processQueue()
  handleSwitchPresets()
  updateScan()

  if event == nil then
    return 2
  end

  if isPageNext(event) then
    focusRow = focusRow + 1
    if focusRow > 3 then
      focusRow = 1
    end
  elseif isPagePrev(event) then
    focusRow = focusRow - 1
    if focusRow < 1 then
      focusRow = 3
    end
  elseif event == EVT_VIRTUAL_ENTER then
    local rowType = bandRowType(bandRowIndex)
    if focusRow == 1 and rowType == "switch" then
      if switchDisplayMode == "name" then
        switchDisplayMode = "count"
      else
        switchDisplayMode = "name"
      end
    elseif focusRow == 3 then
      local chosen = currentOption()
      if scanActive then
        if chosen then
          scanBandIndex = selectedBandIndex
          scanChannelIndex = selectedChannelIndex
          scanNextTick = 0
        end
      else
        stopScan()
        if chosen then
          queueVtxSequence(chosen)
        end
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
      local rowType = bandRowType(bandRowIndex)
      if rowType == "band" then
        selectedBandIndex = bandRowIndex
        if not scanActive and scanMode then
          stopScan()
        end
      end
    elseif focusRow == 2 then
      selectedChannelIndex = selectedChannelIndex + 1
      if selectedChannelIndex > #channelValues then
        selectedChannelIndex = 1
      end
      if not scanActive and scanMode then
        stopScan()
      end
    end
  elseif event == EVT_ROT_LEFT then
    if focusRow == 1 then
      bandRowIndex = bandRowIndex - 1
      if bandRowIndex < 1 then
        bandRowIndex = #bands + 1
      end
      local rowType = bandRowType(bandRowIndex)
      if rowType == "band" then
        selectedBandIndex = bandRowIndex
        if not scanActive and scanMode then
          stopScan()
        end
      end
    elseif focusRow == 2 then
      selectedChannelIndex = selectedChannelIndex - 1
      if selectedChannelIndex < 1 then
        selectedChannelIndex = #channelValues
      end
      if not scanActive and scanMode then
        stopScan()
      end
    end
  end

  drawScreen()
  return 0
end

return { init = init, run = run }
