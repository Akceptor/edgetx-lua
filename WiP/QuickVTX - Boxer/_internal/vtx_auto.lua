---- #########################################################################
---- #                                                                       #
---- # Copyright (C) OpenTX, adapted for ExpressLRS                          #
-----#                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #                                                                       #
---- #########################################################################
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
    local hash = computeDeviceIdHash(commandId)
    local filename = "_internal/license_" .. hash .. ".txt"
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
