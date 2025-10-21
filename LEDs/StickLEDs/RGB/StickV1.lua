-- Stick Edge LED Visualizer
-- Uses both sticks to light LEDs 0–19 according to direction & deflection
-- Left stick = LEDs 10–19 (CCW, 10 rightmost)
-- Right stick = LEDs 0–9  (CW, 0 leftmost)

--------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------
local COLOR_ACTIVE  = { r = 0, g = 0, b = 255 }  -- blue
local COLOR_PASSIVE  = { r = 0, g = 0, b = 0 }  -- off
local EDGE_THRESHOLD = 0.9  -- deflection needed to activate LED

--------------------------------------------------------------------
-- LED MAPPINGS
--------------------------------------------------------------------
local RIGHT_LED_MAP = {
  [0] = 3,  [1] = 4,  [2] = 5,  [3] = 6,  [4] = 7,
  [5] = 8,  [6] = 9,  [7] = 0,  [8] = 1,  [9] = 2,
}

local LEFT_LED_MAP = {
  [0] = 18, [1] = 19, [2] = 20, [3] = 11, [4] = 12,
  [5] = 13, [6] = 14, [7] = 15, [8] = 16, [9] = 17,
}

--------------------------------------------------------------------
-- INTERNAL STATE
--------------------------------------------------------------------
local dots = 10
local function clamp(x, lo, hi)
  if x < lo then return lo elseif x > hi then return hi else return x end
end

local function norm(v) return clamp(v / 1024, -1, 1) end

local function angleDiff(a, b)
  local d = (a - b) % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  return math.abs(d)
end

--------------------------------------------------------------------
local function drawRingAngle(angle, active)
  local step = 2 * math.pi / dots
  local activeIndex = nil
  for i = 0, dots - 1 do
    local a = step * i - math.pi / 2
    if active and angleDiff(a, angle) < (step / 2) then
      activeIndex = i
      break
    end
  end
  return activeIndex
end

--------------------------------------------------------------------
-- INIT / RUN / BACKGROUND
--------------------------------------------------------------------
local function init()
  -- initialize: turn all LEDs off
  for i = 0, 19 do setRGBLedColor(i, 0, 0, 0) end
  applyRGBLedColors()
end

local function run()
  -- Read channels (TX15 mapping)
  local roll  = norm(getValue("ch1"))
  local pitch = norm(getValue("ch2"))
  local thr   = norm(getValue("ch3"))
  local yaw   = norm(getValue("ch4"))

  -- compute active ring positions
  local magL = math.sqrt(yaw * yaw + thr * thr)
  local magR = math.sqrt(roll * roll + pitch * pitch)
  local activeLeft  = magL >= EDGE_THRESHOLD
  local activeRight = magR >= EDGE_THRESHOLD
  local angleLeft   = math.atan2(-thr, yaw)
  local angleRight  = math.atan2(-pitch, roll)
  local idxL = drawRingAngle(angleLeft, activeLeft)
  local idxR = drawRingAngle(angleRight, activeRight)
  local leftLed  = idxL and LEFT_LED_MAP[idxL]
  local rightLed = idxR and RIGHT_LED_MAP[idxR]

  -- update LEDs
  for i = 0, 19 do
    setRGBLedColor(i, COLOR_PASSIVE.r, COLOR_PASSIVE.g, COLOR_PASSIVE.b)
  end
  if leftLed  then setRGBLedColor(leftLed,  COLOR_ACTIVE.r, COLOR_ACTIVE.g, COLOR_ACTIVE.b) end
  if rightLed then setRGBLedColor(rightLed, COLOR_ACTIVE.r, COLOR_ACTIVE.g, COLOR_ACTIVE.b) end
  applyRGBLedColors()
end

local function background()
  -- Nothing needed while off
end

return { run = run, background = background, init = init }