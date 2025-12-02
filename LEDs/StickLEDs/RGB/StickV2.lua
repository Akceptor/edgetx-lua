-- Stick Edge LED Visualizer (3-Threshold Version)
-- Green = 30–50%, Red = 50–90%, Blue = >=90%

--------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------
local COLOR_MAX   = { r = 0,   g = 0,   b = 255 }  -- blue (>=90%)
local COLOR_MID   = { r = 255, g = 0,   b = 0   }  -- red (50–90%)
local COLOR_LOW   = { r = 0,   g = 255, b = 0   }  -- green (30–50%)
local COLOR_OFF   = { r = 0,   g = 0,   b = 0   }

local LOW_THRESHOLD = 0.30
local MID_THRESHOLD = 0.50
local MAX_THRESHOLD = 0.90

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
local dots = 10

local function clamp(x, lo, hi)
  if x < lo then return lo elseif x > hi then return hi else return x end
  return x
end

local function norm(v)
  return clamp(v / 1024, -1, 1)
end

local function angleDiff(a, b)
  local d = (a - b) % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  return math.abs(d)
end

local function findSegment(angle, active)
  if not active then return nil end
  local step = 2 * math.pi / dots
  for i = 0, dots - 1 do
    local a = step * i - math.pi / 2
    if angleDiff(a, angle) < (step / 2) then
      return i
    end
  end
  return nil
end

--------------------------------------------------------------------
-- INIT / RUN / BACKGROUND
--------------------------------------------------------------------
local function init()
  for i = 0, 19 do setRGBLedColor(i, 0, 0, 0) end
  applyRGBLedColors()
end

local function run()
  -- Read TX channels
  local roll  = norm(getValue("ch1"))
  local pitch = norm(getValue("ch2"))
  local thr   = norm(getValue("ch3"))
  local yaw   = norm(getValue("ch4"))

  -- Stick magnitudes
  local magL = math.sqrt(yaw * yaw + thr * thr)
  local magR = math.sqrt(roll * roll + pitch * pitch)

  -- Threshold checks
  local L_low = magL >= LOW_THRESHOLD
  local L_mid = magL >= MID_THRESHOLD
  local L_max = magL >= MAX_THRESHOLD

  local R_low = magR >= LOW_THRESHOLD
  local R_mid = magR >= MID_THRESHOLD
  local R_max = magR >= MAX_THRESHOLD

  -- Stick angles
  local angleLeft  = math.atan2(-thr, yaw)
  local angleRight = math.atan2(-pitch, roll)

  -- Segment indices per threshold
  local idxL_low = findSegment(angleLeft,  L_low)
  local idxL_mid = findSegment(angleLeft,  L_mid)
  local idxL_max = findSegment(angleLeft,  L_max)

  local idxR_low = findSegment(angleRight, R_low)
  local idxR_mid = findSegment(angleRight, R_mid)
  local idxR_max = findSegment(angleRight, R_max)

  -- Map to actual LED IDs
  local LED_L_low = idxL_low and LEFT_LED_MAP[idxL_low]
  local LED_L_mid = idxL_mid and LEFT_LED_MAP[idxL_mid]
  local LED_L_max = idxL_max and LEFT_LED_MAP[idxL_max]

  local LED_R_low = idxR_low and RIGHT_LED_MAP[idxR_low]
  local LED_R_mid = idxR_mid and RIGHT_LED_MAP[idxR_mid]
  local LED_R_max = idxR_max and RIGHT_LED_MAP[idxR_max]

  -- Clear all LEDs
  for i = 0, 19 do
    setRGBLedColor(i, COLOR_OFF.r, COLOR_OFF.g, COLOR_OFF.b)
  end

  -- Low (green)
  if LED_L_low then setRGBLedColor(LED_L_low, COLOR_LOW.r, COLOR_LOW.g, COLOR_LOW.b) end
  if LED_R_low then setRGBLedColor(LED_R_low, COLOR_LOW.r, COLOR_LOW.g, COLOR_LOW.b) end

  -- Mid (red) overrides Low
  if LED_L_mid then setRGBLedColor(LED_L_mid, COLOR_MID.r, COLOR_MID.g, COLOR_MID.b) end
  if LED_R_mid then setRGBLedColor(LED_R_mid, COLOR_MID.r, COLOR_MID.g, COLOR_MID.b) end

  -- Max (blue) overrides Mid & Low
  if LED_L_max then setRGBLedColor(LED_L_max, COLOR_MAX.r, COLOR_MAX.g, COLOR_MAX.b) end
  if LED_R_max then setRGBLedColor(LED_R_max, COLOR_MAX.r, COLOR_MAX.g, COLOR_MAX.b) end

  applyRGBLedColors()
end

local function background() end

return { run = run, background = background, init = init }
