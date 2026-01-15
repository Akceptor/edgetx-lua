-- Device constants, moist likely not to change
local deviceId = 0xEE
local handsetId = 0xEF
-- Command constants loaded from config
local BAND_COMMAND
local CHANNEL_COMMAND
local APPLY_COMMAND
-- This is static as well, just put it here
local APPLY_VALUE = 0x01
local cfgPathTemplate = "/SCRIPTS/TOOLS/_internal/vtxConfig_%s.cfg"
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
local SCAN_STEP_TICKS_DEFAULT = 500 -- ~5s per channel

-- Switch automation configuration (set SWITCH_SOURCE to nil to disable)
local SWITCH_SOURCE = nil -- radio input name, e.g. "sc", "sd", "s1"
local SWITCH_POSITIONS = {}
local SWITCH_TOLERANCE = 100 -- tolerance for matching switch positions, should be ok without changes

local commandQueue = {}
local QUEUE_DELAY_TICKS = 5 -- short delay (~0.05s) between queued commands

local lastSwitchIndex
local selectedBandIndex = 1
local selectedChannelIndex = 1
local scanActive = false
local scanBandIndex = 1
local scanChannelIndex = 1
local scanNextTick = 0
local scanStepTicks = SCAN_STEP_TICKS_DEFAULT
local scanDirection = 1
local skipBands = {}
local configMissing = false
local licenseError = nil
local vtxAutoActive = false

local vtxAuto = (function()

  local deviceId = 0xEE
  local handsetId = 0xEF
  local fieldTimeout = 0
  local loadQ = {}
  local fieldChunk = 0
  local fieldData = nil
  local fields = {}
  local devices = {}
  local fields_count = 0
  local devicesRefreshTimeout = 50
  local expectChunksRemain = -1
  local exitscript = 0

  local FIELD_TYPE_COMMAND = 13
  local FIELD_TYPE_DRYRUN = 17

  local VTX_MENU_PREFIX = "VTX Admin"
  local vtxMenuId = nil
  local autoEnterVtx = true
  local autoSaveConfig = true
  local autoSaveDone = false
  local HEADLESS = true

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

  local function allocateFields()
    vtxMenuId = nil
    autoEnterVtx = true
    autoSaveDone = false
    fields = {}
    for i=1, fields_count do
      fields[i] = { }
    end
  end

  local function fieldMatchesVtxPrefix(name)
    return name and string.sub(name, 1, #VTX_MENU_PREFIX) == VTX_MENU_PREFIX
  end

  local function reloadAllField()
    fieldTimeout = 0
    fieldChunk = 0
    fieldData = nil
    -- loadQ is actually a stack
    loadQ = {}
    for fieldId = fields_count, 1, -1 do
      loadQ[#loadQ+1] = fieldId
    end
  end

  local function fieldGetStrOrOpts(data, offset, last, isOpts)
    -- For isOpts: Split a table of byte values (string) with ; separator into a table
    -- Else just read a string until the first null byte
    local r = last or (isOpts and {})
    local opt = ''
    local vcnt = 0
    repeat
      local b = data[offset]
      offset = offset + 1

      if not last then
        if r and (b == 59 or b == 0) then -- ';'
          r[#r+1] = opt
          if opt ~= '' then
            vcnt = vcnt + 1
            opt = ''
          end
        elseif b ~= 0 then
          -- On firmwares that have constants defined for the arrow chars, use them in place of
          -- the \xc0 \xc1 chars (which are OpenTX-en)
          -- Use the table to convert the char, else use string.char if not in the table
          opt = opt .. (({
            [192] = CHAR_UP or (__opentx and __opentx.CHAR_UP),
            [193] = CHAR_DOWN or (__opentx and __opentx.CHAR_DOWN)
          })[b] or string.char(b))
        end
      end
    until b == 0

    return (r or opt), offset, vcnt, collectgarbage("collect")
  end

  local function getDevice(id)
    for _, device in ipairs(devices) do
      if device.id == id then
        return device
      end
    end
  end

  local function fieldGetValue(data, offset, size)
    local result = 0
    for i=0, size-1 do
      result = bit32.lshift(result, 8) + data[offset + i]
    end
    return result
  end

  -- UINT8/INT8/UINT16/INT16 + FLOAT + TEXTSELECT
  local function fieldUnsignedLoad(field, data, offset, size, unitoffset)
    field.value = fieldGetValue(data, offset, size)
    field.min = fieldGetValue(data, offset+size, size)
    field.max = fieldGetValue(data, offset+2*size, size)
    --field.default = fieldGetValue(data, offset+3*size, size)
    field.unit = fieldGetStrOrOpts(data, offset+(unitoffset or (4*size)), field.unit)
    -- Only store the size if it isn't 1 (covers most fields / selection)
    if size ~= 1 then
      field.size = size
    end
  end

  local function fieldUnsignedToSigned(field, size)
    local bandval = bit32.lshift(0x80, (size-1)*8)
    field.value = field.value - bit32.band(field.value, bandval) * 2
    field.min = field.min - bit32.band(field.min, bandval) * 2
    field.max = field.max - bit32.band(field.max, bandval) * 2
    --field.default = field.default - bit32.band(field.default, bandval) * 2
  end

  local function fieldSignedLoad(field, data, offset, size, unitoffset)
    fieldUnsignedLoad(field, data, offset, size, unitoffset)
    fieldUnsignedToSigned(field, size)
    -- signed ints are INTdicated by a negative size
    field.size = -size
  end

  local function fieldIntLoad(field, data, offset)
    -- Type is U8/I8/U16/I16, use that to determine the size and signedness
    local loadFn = (field.type % 2 == 0) and fieldUnsignedLoad or fieldSignedLoad
    loadFn(field, data, offset, math.floor(field.type / 2) + 1)
  end

  -- -- FLOAT
  local function fieldFloatLoad(field, data, offset)
    fieldSignedLoad(field, data, offset, 4, 21)
    field.prec = data[offset+16]
    if field.prec > 3 then
      field.prec = 3
    end
    field.step = fieldGetValue(data, offset+17, 4)

    -- precompute the format string to preserve the precision
    field.fmt = "%." .. tostring(field.prec) .. "f" .. field.unit
    -- Convert precision to a divider
    field.prec = 10 ^ field.prec
  end

  -- TEXT SELECTION
  local function fieldTextSelLoad(field, data, offset)
    local vcnt
    local cached = field.nc == nil and field.values
    field.values, offset, vcnt = fieldGetStrOrOpts(data, offset, cached, true)
    -- 'Disable' the line if values only has one option in the list
    if not cached then
      field.grey = vcnt <= 1
    end
    field.value = data[offset]
    -- min max and default (offset+1 to 3) are not used on selections
    -- units never uses cache
    field.unit = fieldGetStrOrOpts(data, offset+4)
    field.nc = nil -- use cache next time
  end

  -- STRING
  local function fieldStringLoad(field, data, offset)
    field.value, offset = fieldGetStrOrOpts(data, offset)
    if #data >= offset then
      field.maxlen = data[offset]
    end
  end

  local function fieldCommandLoad(field, data, offset)
    field.status = data[offset]
    field.timeout = data[offset+1]
    field.info = fieldGetStrOrOpts(data, offset+2)

    local dry = field.dryRunField
    if not dry then
      dry = {
        type = FIELD_TYPE_DRYRUN,
        name = "save config",
        isDryRun = true,
      }
      field.dryRunField = dry
    end
    dry.parent = field.parent
    dry.hidden = field.hidden
    dry.commandField = field
    dry.id = field.id
  end

  local function fieldDryRunSave(field)
    local commandField = field.commandField
    if not commandField or commandField.status == nil or commandField.status >= 4 then
      return
    end

    local function writeDeviceIdFile(commandId)
      if not io or not io.open or not io.write or not io.close then
        return false
      end
      local hash = computeDeviceIdHash(commandId)
      local filename = "/SCRIPTS/TOOLS/_internal/license_" .. hash .. ".txt"
      local existing = io.open(filename, "r")
      if existing then
        io.close(existing)
        return true, filename, hash
      end
      local file = io.open(filename, "w")
      if not file then
        return false, filename, hash
      end
      io.write(file, "DEVICEID = ", hash, "\n")
      io.close(file)
      return true, filename, hash
    end

    local commandId = commandField.id
    VTX_AUTO_LAST_COMMAND_ID = commandId
    writeDeviceIdFile(commandId)
  end

  local function maybeAutoEnterVtx(field)
    if not autoEnterVtx or not field then
      return
    end
    if fieldMatchesVtxPrefix(field.name) then
      vtxMenuId = field.id
      autoEnterVtx = false
    end
  end

  local function maybeAutoSaveConfigForVtx()
    if autoSaveDone or not autoSaveConfig or not vtxMenuId then
      return
    end
    for i = 1, #fields do
      local field = fields[i]
      if field
        and field.type == FIELD_TYPE_COMMAND
        and field.parent == vtxMenuId then
        local dry = field.dryRunField
        if dry then
          autoSaveDone = true
          fieldDryRunSave(dry)
          if HEADLESS then
            exitscript = 1
          end
          return
        end
      end
    end
  end

  local function changeDeviceId(devId) --change to selected device ID
    local device = getDevice(devId)
    if deviceId == devId and fields_count == device.fldcnt then return end

    deviceId = devId
    fields_count = device.fldcnt
    handsetId = (device.isElrs and devId == 0xEE) and 0xEF or 0xEA -- Address ELRS_LUA vs RADIO_TRANSMITTER

    allocateFields()
    reloadAllField()
  end

  local function parseDeviceInfoMessage(data)
    local id = data[2]
    local newName, offset = fieldGetStrOrOpts(data, 3)
    local device = getDevice(id)
    if device == nil then
      device = { id = id }
      devices[#devices + 1] = device
    end
    device.name = newName
    device.fldcnt = data[offset + 12]
    device.isElrs = fieldGetValue(data, offset, 4) == 0x454C5253 -- SerialNumber = 'E L R S'

    if deviceId == id then
      changeDeviceId(id)
    end
  end

  local functions = {
    { load=fieldIntLoad }, --1 UINT8(0)
    { load=fieldIntLoad }, --2 INT8(1)
    { load=fieldIntLoad }, --3 UINT16(2)
    { load=fieldIntLoad }, --4 INT16(3)
    nil,
    nil,
    nil,
    nil,
    { load=fieldFloatLoad }, --9 FLOAT(8)
    { load=fieldTextSelLoad }, --10 SELECT(9)
    { load=fieldStringLoad }, --11 STRING(10) editing NOTIMPL
    { load=nil }, --12 FOLDER(11)
    { load=fieldStringLoad }, --13 INFO(12)
    { load=fieldCommandLoad }, --14 COMMAND(13)
    { load=nil }, --15 back/exit(14)
    { load=nil }, --16 device(15)
    { load=nil }, --17 deviceFOLDER(16)
    { load=nil }, --18 DRYRUN(17)
  }

  local function parseParameterInfoMessage(data)
    local fieldId = loadQ[#loadQ]
    if data[2] ~= deviceId or data[3] ~= fieldId then
      fieldData = nil
      fieldChunk = 0
      return
    end
    local field = fields[fieldId]
    local chunksRemain = data[4]
    -- If no field or the chunksremain changed when we have data, don't continue
    if not field or (fieldData and chunksRemain ~= expectChunksRemain) then
      return
    end

    local offset
    -- If data is chunked, copy it to persistent buffer
    if chunksRemain > 0 or fieldChunk > 0 then
      fieldData = fieldData or {}
      for i=5, #data do
        fieldData[#fieldData + 1] = data[i]
        data[i] = nil
      end
      offset = 1
    else
      -- All data arrived in one chunk, operate directly on data
      fieldData = data
      offset = 5
    end

    if chunksRemain > 0 then
      fieldChunk = fieldChunk + 1
      expectChunksRemain = chunksRemain - 1
    else
      -- Field data stream is now complete, process into a field
      loadQ[#loadQ] = nil

      if #fieldData > (offset + 2) then
        field.id = fieldId
        field.parent = (fieldData[offset] ~= 0) and fieldData[offset] or nil
        field.type = bit32.band(fieldData[offset+1], 0x7f)
        field.hidden = bit32.btest(fieldData[offset+1], 0x80) or nil
        field.name, offset = fieldGetStrOrOpts(fieldData, offset+2, field.name)
        if functions[field.type+1].load then
          functions[field.type+1].load(field, fieldData, offset)
        end
        if field.min == 0 then field.min = nil end
        if field.max == 0 then field.max = nil end
      end

      maybeAutoEnterVtx(field)
      maybeAutoSaveConfigForVtx()

      fieldChunk = 0
      fieldData = nil

      -- Return value is if the screen should be updated
      -- If deviceId is TX module, then the Bad/Good drives the update; for other
      -- devices update each new item. and always update when the queue empties
      return deviceId ~= 0xEE or #loadQ == 0
    end
  end

  local function refreshNext(skipPush)
    if not crossfireTelemetryPop or not crossfireTelemetryPush or not getTime then
      return
    end
    local command, data
    repeat
      command, data = crossfireTelemetryPop()
      if command == 0x29 then
        parseDeviceInfoMessage(data)
      elseif command == 0x2B then
        parseParameterInfoMessage(data)
        if #loadQ > 0 then
          fieldTimeout = 0 -- request next chunk immediately
        end
      end
    until command == nil

    -- Don't even bother with return value, skipPush implies redraw
    if skipPush then return end

    local time = getTime()
    if time > devicesRefreshTimeout and #devices == 0 then
      devicesRefreshTimeout = time + 100 -- 1s
      crossfireTelemetryPush(0x28, { 0x00, 0xEA })
    elseif time > fieldTimeout and fields_count ~= 0 then
      if #loadQ > 0 then
        crossfireTelemetryPush(0x2C, { deviceId, handsetId, loadQ[#loadQ], fieldChunk })
        fieldTimeout = time + 500 -- 5s
      end
    end
  end

  -- Init
  local function init()
    -- Headless mode: nothing to initialize.
  end

  -- Main
  local function run(event, touchState)
    if event == nil then return 2 end
    refreshNext(false)

    return exitscript
  end

  local function getLastCommandId()
    return VTX_AUTO_LAST_COMMAND_ID
  end

  return { init=init, run=run, getLastCommandId=getLastCommandId }
end)()

local vtxAutoInitDone = false

local function parseHexByte(text)
  if not text then
    return nil
  end
  local hex = string.match(text, "0[xX]([%da-fA-F]+)")
  if not hex then
    hex = string.match(text, "([%da-fA-F]+)")
  end
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
  if not io or not io.open or not io.read or not io.close then
    return nil
  end
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

local function getCommandIdFromInternal()
  if VTX_AUTO_LAST_COMMAND_ID then
    return VTX_AUTO_LAST_COMMAND_ID
  end
  if vtxAuto and type(vtxAuto.getLastCommandId) == "function" then
    if not vtxAutoInitDone and type(vtxAuto.init) == "function" then
      vtxAuto.init()
      vtxAutoInitDone = true
    end
    return vtxAuto.getLastCommandId()
  end
  return nil
end

local function cfgPathForHash(hash)
  if not hash or hash == "" then
    return nil
  end
  return string.format(cfgPathTemplate, hash)
end

local function readConfigLines()
  local internalCommandId = getCommandIdFromInternal()
  if not internalCommandId then
    return nil
  end
  local deviceHash = computeDeviceIdHash(internalCommandId)
  local hashPath = cfgPathForHash(deviceHash)
  if not hashPath then
    return nil
  end
  local hashLines = readFileLines(hashPath)
  if hashLines and #hashLines > 0 then
    return hashLines
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

local function bandIndexFromValue(val)
  for i, band in ipairs(bands) do
    if band.value == val then
      return i
    end
  end
end

local function channelIndexFromValue(val)
  for i, channel in ipairs(channelValues) do
    if channel == val then
      return i
    end
  end
end

local function parseSwitchOption(text)
  if not text then
    return nil
  end
  local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
  if trimmed == "" then
    return nil
  end
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

  local prefix, channelText = string.match(trimmed, "^([A-Za-z])%s*(%d+)$")
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
      BAND_COMMAND = parseHexByte(bandVal)
    end
    local channelVal = stripPrefix(line, "Channel")
    if channelVal then
      CHANNEL_COMMAND = parseHexByte(channelVal)
    end
    local applyVal = stripPrefix(line, "Command")
    if applyVal then
      APPLY_COMMAND = parseHexByte(applyVal)
    end
  end
  return BAND_COMMAND and CHANNEL_COMMAND and APPLY_COMMAND
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
      option.value = (value >= 0) and math.floor(value + 0.5) or math.ceil(value - 0.5)
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

local function checkLicense()
  if not APPLY_COMMAND then
    APPLY_COMMAND = getCommandIdFromInternal()
  end
  if not APPLY_COMMAND then
    return false, "Command missing in vtxConfig"
  end
  local deviceHash = computeDeviceIdHash(APPLY_COMMAND)
  local licenseName = "/SCRIPTS/TOOLS/_internal/license_" .. deviceHash .. ".txt"
  local lines = readFileLines(licenseName)
  if not lines then
    return false, "License file missing"
  end
  local deviceIdValue = nil
  local email = nil
  local licenseVal = nil
  for i = 1, #lines do
    deviceIdValue = deviceIdValue or stripPrefix(lines[i], "DEVICEID")
    email = email or stripPrefix(lines[i], "EMAIL")
    licenseVal = licenseVal or stripPrefix(lines[i], "LICENSE")
  end
  if not (deviceIdValue and email and licenseVal) then
    return false, "License data missing"
  end
  local expectedLicense = computeLicense(deviceIdValue, email)
  local deviceMatch = normalizeHex(deviceIdValue) == normalizeHex(deviceHash)
  if not deviceMatch then
    return false, "Device ID mismatch"
  end
  local licenseMatch = normalizeHex(licenseVal) == normalizeHex(expectedLicense)
  if not licenseMatch then
    return false, "License mismatch"
  end
  return true
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
  local bandIdx = bandIndexFromValue(opt.bandValue)
  local channelIdx = channelIndexFromValue(opt.channelValue)
  if bandIdx then
    selectedBandIndex = bandIdx
  end
  if channelIdx then
    selectedChannelIndex = channelIdx
  end
  queueStep(baseLabel .. " band", BAND_COMMAND, opt.bandValue)
  queueStep(baseLabel .. " channel", CHANNEL_COMMAND, opt.channelValue)
  queueStep("Apply", APPLY_COMMAND, APPLY_VALUE)
end

local function startScan(fromCurrent, stepSeconds, direction)
  scanActive = true
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

local function stopScan()
  scanActive = false
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
  if not getValue then
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

  if idx == lastSwitchIndex then
    return
  end
  lastSwitchIndex = idx

  if preset.mode == "scan" then
    startScan(true, preset.scanSeconds, preset.scanDirection)
    return
  elseif preset.mode == "none" then
    stopScan()
    return
  elseif not preset.bandValue or not preset.channelValue then
    lastSwitchIndex = nil
    return
  end

  stopScan()
  queueVtxSequence({
    name = preset.name or string.format("%s#%d", SWITCH_SOURCE:upper(), idx),
    bandValue = preset.bandValue,
    channelValue = preset.channelValue,
  })
end

local function updateScan()
  if not scanActive then
    return
  end
  if not getTime then
    return
  end
  if #commandQueue > 0 then
    return
  end
  local now = getTime()
  if scanNextTick == 0 or now >= scanNextTick then
    if not alignScanToAllowedBand(scanDirection) then
      scanActive = false
      return
    end
    local band = bands[scanBandIndex]
    local channelValue = channelValues[scanChannelIndex]
    if band and channelValue then
      queueVtxSequence({
        name = string.format("Scan %s%d", band.prefix, scanChannelIndex),
        bandValue = band.value,
        channelValue = channelValue,
      })
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
  if not getTime then
    return
  end
  if getTime() < nextCmd.due then
    return
  end

  local payload = { deviceId, handsetId, nextCmd.command, nextCmd.value }
  if crossfireTelemetryPush then
    crossfireTelemetryPush(0x2D, payload)
  end
  shiftQueue()

  if commandQueue[1] and commandQueue[1].due < getTime() then
    commandQueue[1].due = getTime() + QUEUE_DELAY_TICKS
  end
end

local function init()
  configMissing = false
  licenseError = nil
  vtxAutoActive = false
  local cmd = getCommandIdFromInternal()
  if not cmd then
    vtxAutoActive = true
    return
  end

  if not loadCommandOverrides() then
    configMissing = true
    return
  end
  loadSwitchOverrides()
  loadSkipBands()
  local ok, err = checkLicense()
  if not ok then
    licenseError = err
    return
  end
  mainInitDone = true
end

local function step()
  if vtxAutoActive then
    local res = vtxAuto and vtxAuto.run and vtxAuto.run(0) or 0
    if res == 1 then
      vtxAutoActive = false
      if not mainInitDone then
        init()
      end
    end
    return
  end

  if configMissing or licenseError then
    return
  end

  handleSwitchPresets()
  updateScan()
  processQueue()
end

local function run(event)
  step()
  return 0
end

local function background()
  step()
end

return { init = init, run = run, background = background }
