local CONFIG_PATH = "/SCRIPTS/MIXES/vtxCfg.lua"
local CONFIG

if loadScript then
  local cfgChunk = assert(loadScript(CONFIG_PATH))
  local cfg = assert(cfgChunk())
  assert(type(cfg) == "table", "Config must return a table")
  CONFIG = cfg
else
  -- desktop fallback (luac/dofile on PC)
  CONFIG = assert(dofile("vtxCfg.lua"))
end

-- ###################################################################
-- ## DO NOT CHANGE THINGS BELOW UNLESS YOU KNOW WHAT YOU ARE DOING ##
-- ###################################################################
local BAND_COMMAND = CONFIG.BAND_COMMAND
local CHANNEL_COMMAND = CONFIG.CHANNEL_COMMAND
local APPLY_COMMAND = CONFIG.APPLY_COMMAND

local SWITCH_SOURCE = CONFIG.SWITCH_SOURCE
local SWITCH_POSITIONS = CONFIG.SWITCH_POSITIONS or {}
local SWITCH_TOLERANCE = 100 -- tolerance for matching switch positions, should be ok without changes

-- Device constants, moist likely not to change
local deviceId = 0xEE
local handsetId = 0xEF
local CENTER_FLAG = CENTER or 0

local commandQueue = {}
local QUEUE_DELAY_TICKS = 5 -- short delay (~0.05s) between queued commands

local lastSwitchIndex

local function queueStep(command, value)
  if not command or value == nil then
    return
  end
  local due = getTime()
  if #commandQueue > 0 then
    local lastDue = commandQueue[#commandQueue].due
    if lastDue and lastDue >= due then
      due = lastDue + QUEUE_DELAY_TICKS
    end
  end
  commandQueue[#commandQueue + 1] = {
    due = due,
    command = command,
    value = value,
  }
end

local function queueVtxSequence(opt)
  if not opt or not opt.bandValue or not opt.channelValue then
    return
  end
  commandQueue = {}
  queueStep(BAND_COMMAND, opt.bandValue)
  queueStep(CHANNEL_COMMAND, opt.channelValue)
  queueStep(APPLY_COMMAND, 0x01)
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
  shiftQueue()

  if commandQueue[1] and commandQueue[1].due < getTime() then
    commandQueue[1].due = getTime() + QUEUE_DELAY_TICKS
  end
end

local function init()
  commandQueue = {}
  lastSwitchIndex = nil
end

local function background()
  processQueue()
  handleSwitchPresets()

  return 0
end

local function run(event)
  background()

  return 0
end

return { init = init, run = run, background = background }
