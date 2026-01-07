
-- TNS|ConfigWizard|TNE
local childPath = "_internal/vtx_auto.lua"
local cfgPath = "vtxConfig_auto.cfg"
local child = nil
local done = false
local errorMsg = nil
local page = 0
local switches = { "SA", "SB", "SC", "SD" }
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

local function isPageNext(event)
  return event == EVT_PAGEDN_FIRST
    or event == EVT_PAGEDN_LONG
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

local function readCfgLines()
  local lines = {}
  local content = ""
  local file = io.open(cfgPath, "r")
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

local function appendCfgLine(line)
  local file = io.open(cfgPath, "a")
  if not file then
    return false
  end
  io.write(file, line, "\n")
  io.close(file)
  return true
end

local function writeCfgLines(lines)
  local file = io.open(cfgPath, "w")
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
  local lines = readCfgLines()
  if #lines == 0 then
    return appendCfgLine(key .. ": " .. value)
  end
  local filtered = {}
  for i = 1, #lines do
    if not string.find(lines[i], "^" .. key .. ":%s*") then
      filtered[#filtered + 1] = lines[i]
    end
  end
  filtered[#filtered + 1] = key .. ": " .. value
  return writeCfgLines(filtered)
end

local function updateCfgSwitch(value)
  return updateCfgKey("Switch", value)
end

local function updateCfgPositions(value)
  return updateCfgKey("Positions", value)
end

local function updateCfgPositionValues(values)
  local lines = readCfgLines()
  if #lines == 0 then
    local file = io.open(cfgPath, "a")
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
  return writeCfgLines(filtered)
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
      lcd.clear()
    lcd.drawText(2, 2, "VTX Admin initialized")
    lcd.drawText(2, 16, "Press PAGE> to continue")
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
      if updateCfgSwitch(switches[switchIndex]) then
        page = 2
      else
        errorMsg = "CFG write failed"
      end
    end

    lcd.clear()
    lcd.drawText(2, 2, "Select switch")
    lcd.drawText(2, 16, "Switch: " .. switches[switchIndex])
    lcd.drawText(2, 30, "ROTARY change")
    lcd.drawText(2, 44, "PAGE> save")
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
    lcd.drawText(2, 2, "Select positions")
    lcd.drawText(2, 16, "Positions: " .. positions[positionIndex])
    lcd.drawText(2, 30, "ROTARY change")
    lcd.drawText(2, 44, "PAGE> save")
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
    lcd.drawText(2, 2, "Pos " .. posIndex .. "/" .. positionsCount)
    lcd.drawText(2, 16, "Band: " .. bands[bandIndex])
    lcd.drawText(2, 30, "Channel: " .. channels[channelIndex])
    lcd.drawText(2, 44, "ROTARY change, PAGE> next")
  else
    lcd.clear()
    lcd.drawText(2, 2, "Setup saved")
  end

  return 0
end

return { init = init, run = run }
