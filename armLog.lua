-- Arming logger 

local armed = false
local function getSwitch()
  local ok, v = pcall(getValue, "sa")
  if not ok or v == nil then return 0 end
  return v
end

local function getTimeParts()
  local ok, t = pcall(getDateTime)
  if not ok or not t then
    return 0,0,0,0,0,0
  end
  return t.year or 0, t.mon or 0, t.day or 0,
         t.hour or 0, t.min or 0, t.sec or 0
end

local function write(text, newline)
  local y,mo,d = getTimeParts()
  local filename = string.format("/LOGS/%02d_%02d_%04d.txt", d, mo, y)

  local ok, f = pcall(io.open, filename, "a")
  if ok and f then
    pcall(io.write, f, text)
    if newline then
      pcall(io.write, f, "\n")
    end
    pcall(io.flush, f)
    pcall(io.close, f)
  else
    playTone(400, 200, 0, 0)
  end
end

local function step()
  local v = getSwitch()
  if v >= 100 and not armed then
    armed = true
    local _,_,_, h,m,s = getTimeParts()

    local msg = "Armed: " .. h .. ":" .. m .. ":" .. s .. "; "
    write(msg, false)   -- NO newline

    playTone(1500, 120, 0, 0)
  end
  if v < 100 and armed then
    armed = false
    local _,_,_, h,m,s = getTimeParts()

    local msg = "Disarmed: " .. h .. ":" .. m .. ":" .. s .. ";"
    write(msg, true)    -- WITH newline

    playTone(900, 120, 0, 0)
  end
end

local function init() end
local function run(e) step() return 0 end
local function background() step() end

return { init = init, run = run, background = background }
