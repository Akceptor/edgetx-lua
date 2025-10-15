-- Records CH1..CH5 at 50 Hz to /LOGS/stickrec.csv and replays them via GV1..GV5.
-- SD↑ = RECORD (LEDs RED), SD↓ = PLAY (LEDs GREEN), SD– = STOP (LEDs OFF)

local FILE = "/LOGS/stickrec.csv"
local LED_STRIP_LENGTH = 20
local TICK = 2 -- 20ms = 50Hz
local FLIGHT_PHASE = 0 -- Normal phase

local state = "IDLE"  -- "IDLE" | "REC" | "PLAY"
local f = nil
local nextTick = 0

local buf, bufCount, MAX_BUF = {}, 0, 100
local playBuf = "" -- chunked-read buffer for playback

local function safeBeep(freq) pcall(playTone, freq, 120, 0, 0) end

local function setAllLED(r, g, b)
  r, g, b = r or 0, g or 0, b or 0
  for i = 0, LED_STRIP_LENGTH - 1 do pcall(setRGBLedColor, i, r, g, b) end
  pcall(applyRGBLedColors)
end

local function ledsForState(s)
  if s == "REC" then setAllLED(255, 0, 0)
  elseif s == "PLAY" then setAllLED(0, 255, 0)
  else setAllLED(0, 0, 0) end
end

local function sdPos()
  local v = getValue and (getValue("sd") or 0) or 0
  if v > 100 then return "UP"
  elseif v < -100 then return "DOWN"
  else return "MID" end
end

local function stopAll()
  if f then pcall(io.close, f); f = nil end
  state = "IDLE"
  ledsForState(state)
end

local function flushBuf()
  if not f or bufCount == 0 then return end
  for i = 1, bufCount do
    pcall(io.write, f, buf[i]); pcall(io.write, f, "\n")
    buf[i] = nil
  end
  bufCount = 0
  pcall(io.flush, f)
end

local function startRec()
  stopAll()
  local ok, file = pcall(io.open, FILE, "w")
  if not ok or not file then safeBeep(400); return end
  f = file
  state = "REC"
  ledsForState(state)
  nextTick = getTime()
  safeBeep(1200)
end

local function startPlay()
  stopAll()
  local ok, file = pcall(io.open, FILE, "r")
  if not ok or not file then safeBeep(400); return end
  f = file
  playBuf = ""  -- reset chunk buffer
  state = "PLAY"
  ledsForState(state)
  nextTick = getTime()
  safeBeep(800)
end

local function clampInt(v)
  v = v or 0
  if v > 1024 then return 1024
  elseif v < -1024 then return -1024
  else return (v // 1) end
end

local function writeGV(idx, value)
  pcall(model.setGlobalVariable, idx, FLIGHT_PHASE, value)
end

local function recordStep()
  local g = getValue or function() return 0 end
  local ch1 = clampInt(g("ch1"))
  local ch2 = clampInt(g("ch2"))
  local ch3 = clampInt(g("ch3"))
  local ch4 = clampInt(g("ch4"))
  local ch5 = clampInt(g("ch5"))

  -- passthrough to GV
  writeGV(0, ch1); writeGV(1, ch2); writeGV(2, ch3); writeGV(3, ch4); writeGV(4, ch5)

  bufCount = bufCount + 1
  buf[bufCount] = string.format("%d;%d;%d;%d;%d", ch1, ch2, ch3, ch4, ch5)
  if bufCount >= MAX_BUF then flushBuf() end
end

local function passthroughStep()
  local g = getValue or function() return 0 end
  writeGV(0, clampInt(g("ch1")))
  writeGV(1, clampInt(g("ch2")))
  writeGV(2, clampInt(g("ch3")))
  writeGV(3, clampInt(g("ch4")))
  writeGV(4, clampInt(g("ch5")))
end

local function parseLine(line)
  if not line then return end
  line = string.gsub(line, "\r", "") -- handle CRLF
  local t, i = {}, 1
  for num in string.gmatch(line, "([^;]+)") do
    t[i] = tonumber(num) or 0
    i = i + 1
    if i > 5 then break end
  end
  if i < 6 then return end
  return t[1], t[2], t[3], t[4], t[5]
end

-- Read exactly ONE full CSV line, using 512-byte chunked reads
-- Crappy, but I can't do better for now
local function readOneLine()
  while true do
    local nl = string.find(playBuf, "\n", 1, true)
    if nl then
      local line = string.sub(playBuf, 1, nl - 1)
      playBuf = string.sub(playBuf, nl + 1)
      if #line > 0 then return line end
      -- if empty line, continue searching (skip)
    end
    -- need more data
    if not f then return nil, "eof" end
    local ok, chunk = pcall(io.read, f, 512)
    if not ok or not chunk or #chunk == 0 then
      return nil, "eof"
    end
    playBuf = playBuf .. chunk
  end
end

local function playStep()
  local line, err = readOneLine()
  if not line then
    -- EOF or read error → stop playback
    safeBeep(600)
    stopAll()
    return
  end
  local a, b, c, d, e = parseLine(line)
  if not a then return end
  writeGV(0, clampInt(a))
  writeGV(1, clampInt(b))
  writeGV(2, clampInt(c))
  writeGV(3, clampInt(d))
  writeGV(4, clampInt(e))
end

local function tickDue()
  local now = getTime()
  if now >= nextTick then nextTick = now + TICK; return true end
  return false
end

local function step()
  local pos = sdPos()
  if pos == "UP" and state ~= "REC" then
    startRec()
  elseif pos == "DOWN" and state ~= "PLAY" then
    startPlay()
  elseif pos == "MID" and state ~= "IDLE" then
    if state == "REC" then flushBuf() end
    safeBeep(900)
    stopAll()
  end

  ledsForState(state)
  if not tickDue() then return end

  if state == "REC" then
    recordStep()
  elseif state == "PLAY" then
    playStep()  -- emits ONE line per tick
  else
    passthroughStep()
  end
end

local function init()
  state = "IDLE"
  nextTick = getTime()
  ledsForState(state)
end

local function run(event)
  step()
  return 0
end

local function background()
  step()
end

return { init = init, run = run, background = background }
