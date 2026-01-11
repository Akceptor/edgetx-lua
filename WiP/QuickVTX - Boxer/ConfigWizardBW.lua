
-- TNS|QVTx - ConfigWizard|TNE
local childPath = "_internal/vtx_auto.lua"
local cfgPathTemplate = "_internal/vtxConfig_%s.cfg"
local child = nil
local done = false
local errorMsg = nil
local page = 0
local switches = { "--", "SA", "SB", "SC", "SD", "SE", "SF" }
local switchIndex = 1
local positions = { 2, 3, 4, 5, 6 }
local positionIndex = 1
local positionsCount = 2
local bands = { "A", "B", "E", "F", "R", "L", "X" }
local channels = { 1, 2, 3, 4, 5, 6, 7, 8 }
local bandIndex = 1
local channelIndex = 1
local posIndex = 1
local posSelections = {}
local posField = "band"
local deviceIdHash = nil
local baseConfigWritten = false
local licenseWritten = false

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

local function writeLicenseFile(hash)
  if not hash or hash == "" then
    return false
  end
  local filename = "_internal/license_" .. hash .. ".txt"
  local existing = io.open(filename, "r")
  if existing then
    io.close(existing)
    return true
  end
  local file = io.open(filename, "w")
  if not file then
    return false
  end
  io.write(file, "DEVICEID = ", hash, "\n")
  io.close(file)
  return true
end

local function isPageNext(event)
  return event == EVT_PAGEDN_FIRST
          or event == EVT_PAGEDN_LONG
end

local function isPagePrev(event)
  return event == EVT_PAGEUP_FIRST
          or event == EVT_PAGEUP_LONG
end

local function isRotNext(event)
  return event == EVT_ROT_RIGHT
end

local function isRotPrev(event)
  return event == EVT_ROT_LEFT
end

local function init()
  local loaded = loadScript(childPath)
  if type(loaded) == "function" then
    child = loaded()
  else
    child = loaded
  end

  if child == nil or type(child.run) ~= "function" then
    errorMsg = "Load failed"
    child = nil
    return
  end

  if type(child.init) == "function" then
    child.init()
  end
end

local function readCfgLines(path)
  local lines = {}
  local content = ""
  local file = io.open(path, "r")
  if file then
    local ok, data = pcall(function() return io.read(file, "*a") end)
    if ok and data then
      content = data
    end
    io.close(file)
  end
  for line in string.gmatch(content, "([^\r\n]+)") do
    lines[#lines + 1] = line
  end
  return lines
end

local function getCommandId()
  local commandId = nil
  if child and type(child.getLastCommandId) == "function" then
    commandId = child.getLastCommandId()
  elseif VTX_AUTO_LAST_COMMAND_ID then
    commandId = VTX_AUTO_LAST_COMMAND_ID
  end
  return commandId
end

local function getDeviceIdHash()
  if deviceIdHash then
    return deviceIdHash
  end
  local commandId = getCommandId()
  if not commandId then
    return nil
  end
  deviceIdHash = computeDeviceIdHash(commandId)
  return deviceIdHash
end

local function writeBaseConfig()
  local commandId = getCommandId()
  if not commandId then
    return false
  end
  deviceIdHash = computeDeviceIdHash(commandId)
  local path = cfgPathForHash(deviceIdHash)
  if not path then
    return false
  end
  local file = io.open(path, "w")
  if not file then
    return false
  end
  local bandId = commandId - 4
  local channelId = commandId - 3
  io.write(file, "Band: ", toHexByte(bandId), "\n")
  io.write(file, "Channel: ", toHexByte(channelId), "\n")
  io.write(file, "Command: ", toHexByte(commandId), "\n")
  io.close(file)
  return true
end

local function appendCfgLine(path, line)
  local file = io.open(path, "a")
  if not file then
    return false
  end
  io.write(file, line, "\n")
  io.close(file)
  return true
end

local function writeCfgLines(path, lines)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  for i = 1, #lines do
    io.write(file, lines[i], "\n")
  end
  io.close(file)
  return true
end

local function updateCfgKey(key, value)
  local hash = getDeviceIdHash()
  local path = cfgPathForHash(hash)
  if not path then
    return false
  end
  local lines = readCfgLines(path)
  if #lines == 0 then
    return appendCfgLine(path, key .. ": " .. value)
  end
  local filtered = {}
  for i = 1, #lines do
    if not string.find(lines[i], "^" .. key .. ":%s*") then
      filtered[#filtered + 1] = lines[i]
    end
  end
  filtered[#filtered + 1] = key .. ": " .. value
  return writeCfgLines(path, filtered)
end

local function updateCfgSwitch(value)
  return updateCfgKey("Switch", value)
end

local function updateCfgPositions(value)
  return updateCfgKey("Positions", value)
end

local function updateCfgPositionValues(values)
  local hash = getDeviceIdHash()
  local path = cfgPathForHash(hash)
  if not path then
    return false
  end
  local lines = readCfgLines(path)
  if #lines == 0 then
    local file = io.open(path, "a")
    if not file then
      return false
    end
    for i = 1, #values do
      local v = values[i]
      io.write(file, "Pos" .. i .. ": " .. v.band .. v.channel, "\n")
    end
    io.close(file)
    return true
  end
  local filtered = {}
  for i = 1, #lines do
    if not string.find(lines[i], "^Pos%d+:%s*") then
      filtered[#filtered + 1] = lines[i]
    end
  end
  for i = 1, #values do
    local v = values[i]
    filtered[#filtered + 1] = "Pos" .. i .. ": " .. v.band .. v.channel
  end
  return writeCfgLines(path, filtered)
end

local function loadSelectionForPosition(index)
  local sel = posSelections[index]
  if sel then
    for i = 1, #bands do
      if bands[i] == sel.band then
        bandIndex = i
        break
      end
    end
    for i = 1, #channels do
      if channels[i] == sel.channel then
        channelIndex = i
        break
      end
    end
  else
    bandIndex = 1
    channelIndex = 1
  end
end

local function run(event, touchState)
  if errorMsg then
    lcd.clear()
    lcd.drawText(2, 2, errorMsg)
    return 0
  end

  if not child then
    lcd.clear()
    lcd.drawText(2, 2, "Loading...")
    return 0
  end

  if page == 0 then
    if not done then
      local res = child.run(event, touchState)
      if res == 1 then
        done = true
      end
    end

    if done then
      if not baseConfigWritten then
        baseConfigWritten = writeBaseConfig()
        if not baseConfigWritten then
          errorMsg = "Config write failed"
          return 0
        end
      end
      if not licenseWritten then
        local hash = getDeviceIdHash()
        licenseWritten = writeLicenseFile(hash)
      end
      lcd.clear()
      local hash = getDeviceIdHash()
      local idText = hash and ("Device ID: " .. hash) or "Device ID: N/A"
      lcd.drawText(2, 2, idText, SMLSIZE)
      lcd.drawText(2, 16, "Press PAGE> to continue", SMLSIZE)
      if isPageNext(event) then
        page = 1
      end
    end
  elseif page == 1 then
    if isRotNext(event) then
      switchIndex = (switchIndex % #switches) + 1
    elseif isRotPrev(event) then
      switchIndex = ((switchIndex - 2) % #switches) + 1
    elseif isPageNext(event) then
      local selectedSwitch = switches[switchIndex]
      if updateCfgSwitch(selectedSwitch) then
        if selectedSwitch == "--" then
          positionsCount = 0
          if updateCfgPositions(positionsCount) and updateCfgPositionValues({}) then
            page = 4
          else
            errorMsg = "CFG write failed"
          end
        else
          page = 2
        end
      else
        errorMsg = "CFG write failed"
      end
    end

    lcd.clear()
    lcd.drawText(2, 2, "Select switch                  ", INVERS)
    lcd.drawText(2, 16, "Switch: " .. switches[switchIndex], MIDSIZE)
    lcd.drawText(2, 30, "ROTARY change", SMLSIZE)
    lcd.drawText(2, 40, "PAGE> save", SMLSIZE)
  elseif page == 2 then
    if isRotNext(event) then
      positionIndex = (positionIndex % #positions) + 1
    elseif isRotPrev(event) then
      positionIndex = ((positionIndex - 2) % #positions) + 1
    elseif isPageNext(event) then
      positionsCount = positions[positionIndex]
      if updateCfgPositions(positionsCount) then
        page = 3
        posIndex = 1
        posField = "band"
        loadSelectionForPosition(posIndex)
      else
        errorMsg = "CFG write failed"
      end
    end

    lcd.clear()
    lcd.drawText(2, 2, "Select positions            ", INVERS)
    lcd.drawText(2, 16, "Positions: " .. positions[positionIndex], MIDSIZE)
    lcd.drawText(2, 30, "ROTARY change", SMLSIZE)
    lcd.drawText(2, 40, "PAGE> save", SMLSIZE)
  elseif page == 3 then
    if isRotNext(event) then
      if posField == "band" then
        bandIndex = (bandIndex % #bands) + 1
      else
        channelIndex = (channelIndex % #channels) + 1
      end
    elseif isRotPrev(event) then
      if posField == "band" then
        bandIndex = ((bandIndex - 2) % #bands) + 1
      else
        channelIndex = ((channelIndex - 2) % #channels) + 1
      end
    elseif isPageNext(event) then
      if posField == "band" then
        posField = "channel"
      else
        posSelections[posIndex] = {
          band = bands[bandIndex],
          channel = channels[channelIndex],
        }
        if posIndex < positionsCount then
          posIndex = posIndex + 1
          posField = "band"
          loadSelectionForPosition(posIndex)
        else
          if updateCfgPositionValues(posSelections) then
            page = 4
          else
            errorMsg = "CFG write failed"
          end
        end
      end
    end

    lcd.clear()
    lcd.drawText(2, 2, "Pos " .. posIndex .. "/" .. positionsCount .. "                            ", INVERS)
    local bandLabel = "Band: " .. bands[bandIndex]
    local channelLabel = "Channel: " .. channels[channelIndex]
    if posField == "band" then
      bandLabel = ">" .. bandLabel
    else
      channelLabel = ">" .. channelLabel
    end
    lcd.drawText(2, 16, bandLabel, MIDSIZE)
    lcd.drawText(2, 30, channelLabel, MIDSIZE)
    lcd.drawText(2, 44, "ROTARY change", SMLSIZE)
    lcd.drawText(2, 54, "PAGE> next", SMLSIZE)
  else
    lcd.clear()
    lcd.drawText(2, 2, "Setup saved", DBLSIZE)
  end

  return 0
end

return { init = init, run = run }
