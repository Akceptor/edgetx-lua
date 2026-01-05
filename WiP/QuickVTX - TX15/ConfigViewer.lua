-- TNS|Config Viewer|TNE
local cfgPathLegacy = "vtxConfig_auto.cfg"
local cfgPathLegacyFallback = "/SCRIPTS/TOOLS/vtxConfig_auto.cfg"
local cfgPathTemplate = "vtxConfig_%s.cfg"
local values = {}
local positions = {}
local errorMsg = nil
local loaded = false
local debugLines = nil
local licenseInfo = nil

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

local function buildLicenseInput(deviceId, email)
  return normalizeDeviceId(deviceId) .. "|" .. normalizeEmail(email)
end

local function lastByte(text)
  if not text or #text == 0 then
    return nil
  end
  return string.byte(text, #text)
end

local function hexTail(text, count)
  if not text then
    return ""
  end
  local len = #text
  local start = len - (count or 8) + 1
  if start < 1 then
    start = 1
  end
  local parts = {}
  for i = start, len do
    parts[#parts + 1] = string.format("%02X", string.byte(text, i))
  end
  return table.concat(parts, "")
end

local function hexHead(text, count)
  if not text then
    return ""
  end
  local len = #text
  local last = count or 8
  if last > len then
    last = len
  end
  local parts = {}
  for i = 1, last do
    parts[#parts + 1] = string.format("%02X", string.byte(text, i))
  end
  return table.concat(parts, "")
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

local function loadConfig()
  values = {}
  positions = {}
  debugLines = nil
  licenseInfo = nil
  local lines = readFileLines(cfgPathLegacy)
  if not lines then
    lines = readFileLines(cfgPathLegacyFallback)
  end
  if not lines then
    errorMsg = "vtxConfig not found"
    return
  end

  local function stripPrefix(line, label)
    if not line then
      return nil
    end
    local pattern = "^%s*" .. label .. "%s*[:=]%s*(.+)%s*$"
    return string.match(line, pattern)
  end

  local function findValue(linesList, label)
    for i = 1, #linesList do
      local value = stripPrefix(linesList[i], label)
      if value then
        return value
      end
    end
    return nil
  end

  local commandVal = findValue(lines, "Command")
  local commandId = parseHexByte(commandVal) or (commandVal and tonumber(commandVal) or nil)
  if commandId then
    local deviceHash = computeDeviceIdHash(commandId)
    local hashPath = cfgPathForHash(deviceHash)
    if hashPath then
      local hashLines = readFileLines(hashPath)
      if not hashLines then
        hashLines = readFileLines("/SCRIPTS/TOOLS/" .. hashPath)
      end
      if hashLines and #hashLines > 0 then
        lines = hashLines
      end
    end
  end

  values["Band"] = findValue(lines, "Band")
  values["Channel"] = findValue(lines, "Channel")
  values["Command"] = findValue(lines, "Command")
  values["Switch"] = findValue(lines, "Switch")
  values["Positions"] = findValue(lines, "Positions")

  if #lines == 0 or (values["Band"] == nil and values["Channel"] == nil and values["Switch"] == nil) then
    errorMsg = "No data in vtxConfig"
    debugLines = lines
    return
  end

  local positionsCount = tonumber(values["Positions"] or "0") or 0
  local positionsMap = {}
  for i = 1, #lines do
    local posIndex, posValue = string.match(lines[i], "^%s*Pos(%d+)%s*[:=]%s*(.+)%s*$")
    if posIndex and posValue then
      positionsMap[tonumber(posIndex)] = posValue
    end
  end
  for i = 1, positionsCount do
    local pos = positionsMap[i]
    if pos and pos ~= "" then
      positions[#positions + 1] = pos
    end
  end

  commandId = parseHexByte(values["Command"]) or (values["Command"] and tonumber(values["Command"]) or nil)
  if commandId then
    local deviceHash = computeDeviceIdHash(commandId)
    local licenseName = "license_" .. deviceHash .. ".txt"
    local licenseLines = readFileLines(licenseName)
    if not licenseLines then
      licenseLines = readFileLines("/SCRIPTS/TOOLS/" .. licenseName)
    end
    if licenseLines then

      local deviceId = nil
      local email = nil
      local licenseVal = nil
      for i = 1, #licenseLines do
        deviceId = deviceId or stripPrefix(licenseLines[i], "DEVICEID")
        email = email or stripPrefix(licenseLines[i], "EMAIL")
        licenseVal = licenseVal or stripPrefix(licenseLines[i], "LICENSE")
      end

      local expectedDeviceId = deviceHash
      local licenseInput = (deviceId and email) and buildLicenseInput(deviceId, email) or nil
      local expectedLicense = licenseInput and computeLicense(deviceId, email) or nil
      local deviceMatch = deviceId and normalizeHex(deviceId) == normalizeHex(expectedDeviceId)
      local licenseMatch = expectedLicense and licenseVal and normalizeHex(licenseVal) == normalizeHex(expectedLicense)

      if deviceMatch and licenseMatch then
        licenseInfo = {
          status = "OK",
          deviceId = deviceId,
          email = email,
          license = licenseVal,
          expectedDeviceId = expectedDeviceId,
          expectedLicense = expectedLicense,
          inputLen = licenseInput and #licenseInput or 0,
          inputLast = lastByte(licenseInput),
        }
      else
        local reason = "Invalid"
        if not deviceMatch then
          reason = "Device ID mismatch"
        elseif not licenseMatch then
          reason = "License mismatch"
        end
        licenseInfo = {
          status = reason,
          deviceId = deviceId,
          email = email,
          license = licenseVal,
          expectedDeviceId = expectedDeviceId,
          expectedLicense = expectedLicense,
          inputLen = licenseInput and #licenseInput or 0,
          inputLast = lastByte(licenseInput),
        }
      end
    else
      licenseInfo = { status = "Missing", deviceId = deviceHash, expectedDeviceId = deviceHash }
    end
  else
    licenseInfo = { status = "Command missing" }
  end

  loaded = true
end

local function drawTextLine(y, label, value)
  lcd.drawText(2, y, label .. (value or ""))
end

local function draw()
  lcd.clear()
  if errorMsg then
    lcd.drawText(2, 2, errorMsg, INVERS)
    if debugLines and #debugLines > 0 then
      local y = 14
      for i = 1, #debugLines do
        lcd.drawText(2, y, debugLines[i])
        y = y + 10
        if y > 54 then
          break
        end
      end
    end
    return
  end

  if licenseInfo and licenseInfo.status then
    drawTextLine(2, "Device ID: ", licenseInfo.deviceId)
    drawTextLine(16, "Email: ", licenseInfo.email)
    drawTextLine(30, "License: ", licenseInfo.license)
    drawTextLine(44, "Expect Lic: ", licenseInfo.expectedLicense)
    drawTextLine(58, "Status: ", licenseInfo.status)
  else
    drawTextLine(2, "Band Command: ", values["Band"])
    drawTextLine(16, "Channel Command: ", values["Channel"])
    drawTextLine(30, "Switch Name: ", values["Switch"])
    drawTextLine(44, "Switch Positions: ", values["Positions"])
    if #positions > 0 then
      drawTextLine(58, "Positions: ", table.concat(positions, ", "))
    end
  end
end

local function init()
  loadConfig()
end

local function run(event)
  if not loaded and not errorMsg then
    loadConfig()
  end
  draw()
  return 0
end

return { init = init, run = run }
