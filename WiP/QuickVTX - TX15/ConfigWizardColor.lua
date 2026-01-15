-- TNS|QVTx - ConfigWizard|TNE
local childPath = "_internal/vtx_auto.lua"
local logoPath = "_internal/logo.png"
local cfgPathTemplate = "_internal/vtxConfig_%s.cfg"
local child = nil
local done = false
local errorMsg = nil
local page = 0
local switches = { "--", "SA", "SB", "SC", "SD", "SE", "SF", "S1", "S2", "S3" }
local switchIndex = 1
local positions = { 2, 3, 4, 5, 6, 7, 8 }
local positionIndex = 1
local positionsCount = 2
local bands = { "A", "B", "E", "F", "R", "L", "X", "Scan>", "Scan<", "None" }
local channels = { 1, 2, 3, 4, 5, 6, 7, 8 }
local scanDurations = { 2, 3, 4, 5, 6, 7, 8, 9, 10 }
local switchCandidates = { "SA", "SB", "SC", "SD", "SE", "SF", "S1", "S2", "S3" }
local lastSwitchValues = {}
local lastVirtualNextTick = -1
local lastVirtualPrevTick = -1
local lastPageEventTick = -100
local PAGE_EVENT_COOLDOWN = 20
local bandIndex = 1
local channelIndex = 1
local posIndex = 1
local posSelections = {}
local posField = "band"
local selectedSwitch = nil
local configWritten = false
local deviceIdHash = nil
local baseConfigWritten = false
local logoImage = nil
local logoImageW = nil
local logoImageH = nil
local logoCornerImage = nil
local logoCornerW = nil
local logoCornerH = nil
local logoCornerScale = 0.5

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
  if event == EVT_PAGEDN_FIRST or event == EVT_PAGEDN_LONG then
    lastPageEventTick = getTime and getTime() or lastPageEventTick
    return true
  end
  if event == EVT_VIRTUAL_NEXT_PAGE then
    local now = getTime and getTime() or 0
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
    lastPageEventTick = getTime and getTime() or lastPageEventTick
    return true
  end
  if event == EVT_VIRTUAL_PREV_PAGE then
    local now = getTime and getTime() or 0
    if now == lastVirtualPrevTick or (now - lastPageEventTick) <= PAGE_EVENT_COOLDOWN then
      return false
    end
    lastVirtualPrevTick = now
    lastPageEventTick = now
    return true
  end
  return false
end

local function isRotNext(event)
  return event == EVT_ROT_RIGHT
end

local function isRotPrev(event)
  return event == EVT_ROT_LEFT
end

local function detectSwitchFlip()
  if not getValue then
    return nil
  end
  for i = 1, #switchCandidates do
    local name = string.lower(switchCandidates[i])
    local val = getValue(name)
    if val ~= nil then
      local last = lastSwitchValues[name]
      lastSwitchValues[name] = val
      if last ~= nil and val ~= last then
        return switchCandidates[i]
      end
    end
  end
  return nil
end

local function init()
  local loaded = loadScript(childPath)
  if type(loaded) == "function" then
    child = loaded()
  else
    child = loaded
  end

  if type(child) ~= "table" or type(child.run) ~= "function" then
    errorMsg = "Load failed"
    child = nil
    return
  end

  if type(child.init) == "function" then
    child.init()
  end
end

local function loadLogoImage()
  if logoImage ~= nil or lcd.RGB == nil or Bitmap == nil then
    return
  end
  local ok, img = pcall(Bitmap.open, logoPath)
  if ok and img then
    logoImage = img
    if Bitmap.getSize then
      local w, h = Bitmap.getSize(img)
      logoImageW, logoImageH = w, h
    end
  end
end

local function loadCornerLogoImage()
  if logoCornerImage ~= nil or lcd.RGB == nil or Bitmap == nil then
    return
  end
  loadLogoImage()
  if not logoImage then
    return
  end
  if Bitmap.resize and logoImageW and logoImageH then
    local w = math.floor(logoImageW * logoCornerScale)
    local h = math.floor(logoImageH * logoCornerScale)
    local ok, img = pcall(Bitmap.resize, logoImage, w, h)
    if ok and img then
      logoCornerImage = img
      if Bitmap.getSize then
        local rw, rh = Bitmap.getSize(img)
        logoCornerW, logoCornerH = rw, rh
      else
        logoCornerW, logoCornerH = w, h
      end
      return
    end
  end
  logoCornerImage = logoImage
  logoCornerW = logoImageW
  logoCornerH = logoImageH
end

local function beginPage()
  lcd.clear()
  if lcd.RGB then
    lcd.setColor(CUSTOM_COLOR, BLACK)
    lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, WHITE)
    return CUSTOM_COLOR
  end
  return 0
end

local function drawTextTheme(x, y, text, flags, colorFlag)
  local f = flags or 0
  if colorFlag and colorFlag ~= 0 then
    f = f + colorFlag
  elseif lcd.RGB then
    f = f + CUSTOM_COLOR
  end
  lcd.drawText(x, y, text, f)
end

local function drawCornerLogo()
  loadCornerLogoImage()
  if not logoCornerImage then
    return nil, nil
  end
  local x = 2
  local y = 2
  lcd.drawBitmap(logoCornerImage, x, y)
  local w = logoCornerW or 0
  local h = logoCornerH or 0
  return x + w + 4, y, h
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

local function getDeviceIdHash()
  if deviceIdHash then
    return deviceIdHash
  end
  local commandId = nil
  if child and type(child.getLastCommandId) == "function" then
    commandId = child.getLastCommandId()
  elseif VTX_AUTO_LAST_COMMAND_ID then
    commandId = VTX_AUTO_LAST_COMMAND_ID
  end
  if not commandId then
    return nil
  end
  deviceIdHash = computeDeviceIdHash(commandId)
  return deviceIdHash
end

local function writeBaseConfig()
  local commandId = nil
  if child and type(child.getLastCommandId) == "function" then
    commandId = child.getLastCommandId()
  elseif VTX_AUTO_LAST_COMMAND_ID then
    commandId = VTX_AUTO_LAST_COMMAND_ID
  end
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

local function cfgPathsForWrite()
  local paths = {}
  local hashPath = cfgPathForHash(deviceIdHash)
  if hashPath then
    paths[#paths + 1] = hashPath
  end
  return paths
end

local function updateCfgKey(key, value)
  local lines = nil
  local hashPath = cfgPathForHash(deviceIdHash)
  if hashPath then
    lines = readCfgLines(hashPath)
  end
  if #lines == 0 then
    local ok = true
    local paths = cfgPathsForWrite()
    if #paths == 0 then
      return false
    end
    for i = 1, #paths do
      ok = appendCfgLine(paths[i], key .. ": " .. value) and ok
    end
    return ok
  end
  local filtered = {}
  for i = 1, #lines do
    if not string.find(lines[i], "^" .. key .. ":%s*") then
      filtered[#filtered + 1] = lines[i]
    end
  end
  filtered[#filtered + 1] = key .. ": " .. value
  local ok = true
  local paths = cfgPathsForWrite()
  if #paths == 0 then
    return false
  end
  for i = 1, #paths do
    ok = writeCfgLines(paths[i], filtered) and ok
  end
  return ok
end

local function updateCfgSwitch(value)
  return updateCfgKey("Switch", value)
end

local function updateCfgPositions(value)
  return updateCfgKey("Positions", value)
end

local function updateCfgPositionValues(values)
  local lines = nil
  local hashPath = cfgPathForHash(deviceIdHash)
  if hashPath then
    lines = readCfgLines(hashPath)
  end
  if #lines == 0 then
    local ok = true
    local paths = cfgPathsForWrite()
    if #paths == 0 then
      return false
    end
    for p = 1, #paths do
      local file = io.open(paths[p], "a")
      if not file then
        ok = false
      else
        for i = 1, #values do
          local v = values[i]
          io.write(file, "Pos" .. i .. ": " .. v.band .. v.channel, "\n")
        end
        io.close(file)
      end
    end
    return ok
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
  local ok = true
  local paths = cfgPathsForWrite()
  if #paths == 0 then
    return false
  end
  for i = 1, #paths do
    ok = writeCfgLines(paths[i], filtered) and ok
  end
  return ok
end

local function writeWizardConfig()
  local switchValue = selectedSwitch or switches[switchIndex]
  local count = (switchValue == "--") and 0 or positionsCount
  local selections = {}
  if count > 0 then
    for i = 1, count do
      selections[i] = posSelections[i]
    end
  end
  if not updateCfgSwitch(switchValue) then
    return false
  end
  if not updateCfgPositions(count) then
    return false
  end
  return updateCfgPositionValues(selections)
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
    if string.sub(sel.band or "", 1, 4) == "Scan" then
      for i = 1, #scanDurations do
        if scanDurations[i] == sel.channel then
          channelIndex = i
          break
        end
      end
    elseif sel.band ~= "None" then
      for i = 1, #channels do
        if channels[i] == sel.channel then
          channelIndex = i
          break
        end
      end
    else
      channelIndex = 1
    end
  else
    bandIndex = 1
    channelIndex = 1
  end
end

local function bandAllowsChannel(band)
  return band ~= "None"
end

local function channelOptionsForBand(band)
  if string.sub(band or "", 1, 4) == "Scan" then
    return scanDurations
  end
  return channels
end

local function channelLabelForBand(band, index)
  local options = channelOptionsForBand(band)
  local value = options[index]
  if string.sub(band or "", 1, 4) == "Scan" then
    return tostring(value) .. "s"
  end
  return tostring(value)
end

local function clampChannelIndex(band)
  local options = channelOptionsForBand(band)
  if channelIndex < 1 then
    channelIndex = 1
  elseif channelIndex > #options then
    channelIndex = #options
  end
end

local function run(event, touchState)
  if errorMsg then
    local textFlags = beginPage()
    drawTextTheme(2, 2, errorMsg, nil, textFlags)
    return 0
  end

  if not child then
    local textFlags = beginPage()
    drawTextTheme(2, 2, "Loading...", nil, textFlags)
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
      local textFlags = beginPage()
      loadLogoImage()
      local hash = getDeviceIdHash()
      local idText = hash and ("Licensing device ID = " .. hash) or "Licensing device ID = N/A"
      local infoText = "Press PAGE> to continue"
      local imageY = 0
      if logoImage then
        local x = 0
        local y = 0
        if logoImageW and logoImageH then
          x = math.floor((LCD_W - logoImageW) / 2)
          y = math.floor((LCD_H - logoImageH) / 2)
          if x < 0 then x = 0 end
          if y < 0 then y = 0 end
        end
        lcd.drawBitmap(logoImage, x, y)
        imageY = y
      end
      local textX = 2
      local idY = 2
      if lcd.getTextWidth then
        local idW = lcd.getTextWidth(0, idText)
        textX = math.floor((LCD_W - idW) / 2)
        if textX < 0 then textX = 0 end
      end
      if logoImage and logoImageH then
        idY = imageY - 14
        if idY < 2 then idY = 2 end
      end
      drawTextTheme(textX, idY, idText, nil, textFlags)
      local infoX = 2
      if lcd.getTextWidth then
        local infoW = lcd.getTextWidth(0, infoText)
        infoX = math.floor((LCD_W - infoW) / 2)
        if infoX < 0 then infoX = 0 end
      end
      local infoY = idY + 14
      if logoImage and logoImageH then
        infoY = imageY + logoImageH + 2
      end
      if infoY < 2 then infoY = 2 end
      if infoY > LCD_H - 12 then infoY = LCD_H - 12 end
      drawTextTheme(infoX, infoY-20, infoText, nil, textFlags)
      if isPageNext(event) then
        page = 1
      end
    end
  elseif page == 1 then
    local flipped = detectSwitchFlip()
    if flipped then
      for i = 1, #switches do
        if switches[i] == flipped then
          switchIndex = i
          break
        end
      end
    end
    if isRotNext(event) then
      switchIndex = (switchIndex % #switches) + 1
    elseif isRotPrev(event) then
      switchIndex = ((switchIndex - 2) % #switches) + 1
    elseif isPagePrev(event) then
      page = 0
    elseif isPageNext(event) then
      selectedSwitch = switches[switchIndex]
      if selectedSwitch == "--" then
        positionsCount = 0
        posSelections = {}
        page = 4
      else
        page = 2
      end
    end

    local textFlags = beginPage()
    local textX, textY, logoH = drawCornerLogo()
    if not textX then textX = 2 end
    if not textY then textY = 2 end
    local lineY = textY
    if logoH and logoH > 0 then
      lineY = textY + 2
    end
    drawTextTheme(textX, lineY, "Select switch", MIDSIZE, textFlags)
    drawTextTheme(textX, lineY + 22, "Switch: " .. switches[switchIndex], nil, textFlags)
    drawTextTheme(textX, lineY + 40, "ROTARY change", nil, textFlags)
    drawTextTheme(textX, lineY + 58, "Flip switch to detect", nil, textFlags)
    drawTextTheme(textX, lineY + 76, "PAGE> next", nil, textFlags)
    drawTextTheme(textX, lineY + 94, "PAGE< back", nil, textFlags)
  elseif page == 2 then
    if isRotNext(event) then
      positionIndex = (positionIndex % #positions) + 1
    elseif isRotPrev(event) then
      positionIndex = ((positionIndex - 2) % #positions) + 1
    elseif isPagePrev(event) then
      page = 1
    elseif isPageNext(event) then
      positionsCount = positions[positionIndex]
      page = 3
      posIndex = 1
      posField = "band"
      loadSelectionForPosition(posIndex)
    end

    local textFlags = beginPage()
    local textX, textY, logoH = drawCornerLogo()
    if not textX then textX = 2 end
    if not textY then textY = 2 end
    local lineY = textY
    if logoH and logoH > 0 then
      lineY = textY + 2
    end
    drawTextTheme(textX, lineY, "Select positions", MIDSIZE, textFlags)
    drawTextTheme(textX, lineY + 22, "Positions: " .. positions[positionIndex], nil, textFlags)
    drawTextTheme(textX, lineY + 40, "ROTARY change", nil, textFlags)
    drawTextTheme(textX, lineY + 58, "PAGE> next", nil, textFlags)
    drawTextTheme(textX, lineY + 76, "PAGE< back", nil, textFlags)
  elseif page == 3 then
    if isRotNext(event) then
      if posField == "band" then
        bandIndex = (bandIndex % #bands) + 1
        clampChannelIndex(bands[bandIndex])
      else
        if bandAllowsChannel(bands[bandIndex]) then
          local options = channelOptionsForBand(bands[bandIndex])
          channelIndex = (channelIndex % #options) + 1
        end
      end
    elseif isRotPrev(event) then
      if posField == "band" then
        bandIndex = ((bandIndex - 2) % #bands) + 1
        clampChannelIndex(bands[bandIndex])
      else
        if bandAllowsChannel(bands[bandIndex]) then
          local options = channelOptionsForBand(bands[bandIndex])
          channelIndex = ((channelIndex - 2) % #options) + 1
        end
      end
    elseif isPagePrev(event) then
      if posField == "channel" then
        posField = "band"
      elseif posIndex > 1 then
        posIndex = posIndex - 1
        posField = "channel"
        loadSelectionForPosition(posIndex)
      else
        page = 2
      end
    elseif isPageNext(event) then
      if posField == "band" and bandAllowsChannel(bands[bandIndex]) then
        posField = "channel"
      else
        local channelValue
        if bandAllowsChannel(bands[bandIndex]) then
          channelValue = channelOptionsForBand(bands[bandIndex])[channelIndex]
        else
          channelValue = ""
        end
        posSelections[posIndex] = {
          band = bands[bandIndex],
          channel = channelValue,
        }
        if posIndex < positionsCount then
          posIndex = posIndex + 1
          posField = "band"
          loadSelectionForPosition(posIndex)
        else
          page = 4
        end
      end
    end

    local textFlags = beginPage()
    local textX, textY, logoH = drawCornerLogo()
    if not textX then textX = 2 end
    if not textY then textY = 2 end
    local lineY = textY
    if logoH and logoH > 0 then
      lineY = textY + 2
    end
    drawTextTheme(textX, lineY, "Pos " .. posIndex .. "/" .. positionsCount, MIDSIZE, textFlags)
    local bandLabel = " Band: " .. bands[bandIndex]
    local channelLabel
    if bandAllowsChannel(bands[bandIndex]) then
      channelLabel = " Channel: " .. channelLabelForBand(bands[bandIndex], channelIndex)
    else
      channelLabel = " Channel: --"
    end
    if posField == "band" then
      bandLabel = ">" .. bandLabel
      channelLabel = " " .. channelLabel
    elseif bandAllowsChannel(bands[bandIndex]) then
      channelLabel = ">" .. channelLabel
      bandLabel = " " .. bandLabel
    end
    drawTextTheme(textX, lineY + 22, bandLabel, nil, textFlags)
    drawTextTheme(textX, lineY + 40, channelLabel, nil, textFlags)
    drawTextTheme(textX, lineY + 58, "ROTARY change,", nil, textFlags)
    drawTextTheme(textX, lineY + 76, "PAGE> next", nil, textFlags)
    drawTextTheme(textX, lineY + 94, "PAGE< back", nil, textFlags)
  elseif page == 4 then
    if isPagePrev(event) then
      if selectedSwitch == "--" then
        page = 1
      else
        page = 3
      end
    elseif isPageNext(event) then
      if not configWritten then
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
        configWritten = writeWizardConfig()
        if not configWritten then
          errorMsg = "CFG write failed"
          return 0
        end
      end
      page = 5
    end

    local textFlags = beginPage()
    local textX, textY, logoH = drawCornerLogo()
    if not textX then textX = 2 end
    if not textY then textY = 2 end
    local lineY = textY
    if logoH and logoH > 0 then
      lineY = textY + 2
    end
    drawTextTheme(textX, lineY, "Save config                  ", MIDSIZE, textFlags)
    drawTextTheme(textX, lineY + 58, "PAGE> save", nil, textFlags)
    drawTextTheme(textX, lineY + 76, "PAGE< back", nil, textFlags)
  else
    local textFlags = beginPage()
    loadLogoImage()
    if logoImage then
      local x = 0
      local y = 0
      if logoImageW and logoImageH then
        x = math.floor((LCD_W - logoImageW) / 2)
        y = math.floor((LCD_H - logoImageH) / 2)
        if x < 0 then x = 0 end
        if y < 0 then y = 0 end
      end
      lcd.drawBitmap(logoImage, x, y)
    end
    local savedText = "Setup saved"
    local savedX = 2
    if lcd.getTextWidth then
      local savedW = lcd.getTextWidth(0, savedText)
    end
    local savedY = LCD_H - 50
    if savedY < 2 then savedY = 2 end
    drawTextTheme(300, savedY, savedText, DBLSIZE, textFlags)
  end

  return 0
end

return { init = init, run = run }
