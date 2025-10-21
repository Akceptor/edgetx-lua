-- Stick Edge Visualizer + LED integration (TOOLS)
-- Left stick = LEDs 10–19 (CCW, 10 rightmost)
-- Right stick = LEDs 0–9  (CW, 0 leftmost)
-- LEDs match the same color as dots on screen (on + off)

--------------------------------------------------------------------
-- COLOR CONSTANTS
--------------------------------------------------------------------
local COLOR_ACTIVE  = { r = 255, g = 255, b = 0 }  -- yellow
local COLOR_PASSIVE = { r = 0,  g = 0,  b = 255 }  -- blue

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
-- Helpers
--------------------------------------------------------------------
local function clamp(x, lo, hi)
  if x < lo then return lo elseif x > hi then return hi else return x end
end

local function norm(v) return clamp(v / 1024, -1, 1) end

local function angleDiff(a, b)
  local two_pi = 2 * math.pi
  local d = (a - b) % two_pi
  if d > math.pi then d = d - two_pi end
  return math.abs(d)
end

local function drawDot(x, y, r, color)
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(color.r, color.g, color.b))
  if lcd.drawFilledCircle then
    lcd.drawFilledCircle(x, y, r, CUSTOM_COLOR)
  else
    lcd.drawCircle(x, y, r, CUSTOM_COLOR)
  end
end

--------------------------------------------------------------------
-- LED update helpers (TX15 onboard LEDs)
--------------------------------------------------------------------
local function applyAllLeds(passiveColor)
  for i = 0, 19 do
    setRGBLedColor(i, passiveColor.r, passiveColor.g, passiveColor.b)
  end
end

--------------------------------------------------------------------
-- Draw ring, return active sector index (0..9)
--------------------------------------------------------------------
local function drawRing(cx, cy, radius, activeAngle, active, dots)
  local step = 2 * math.pi / dots
  local r = math.floor(radius * 0.95 + 0.5)
  local activeIndex = nil

  for i = 0, dots - 1 do
    local angle = step * i - math.pi / 2
    local x = cx + math.cos(angle) * r
    local y = cy + math.sin(angle) * r
    if active and angleDiff(angle, activeAngle) < (step / 2) then
      drawDot(x, y, 5, COLOR_ACTIVE)
      activeIndex = i
    else
      drawDot(x, y, 2, COLOR_PASSIVE)
    end
  end

  return activeIndex
end

--------------------------------------------------------------------
local function run(event)
  lcd.clear()

  local W, H = LCD_W or 480, LCD_H or 272
  local cy, radius = H // 2, 60
  local lx, rx = W // 4, 3 * W // 4
  local edgeThr, dots = 0.9, 10

  -- Channel mapping (TX15)
  local roll  = norm(getValue("ch1"))
  local pitch = norm(getValue("ch2"))
  local thr   = norm(getValue("ch3"))
  local yaw   = norm(getValue("ch4"))

  lcd.setColor(CUSTOM_COLOR, lcd.RGB(180, 180, 180))
  lcd.drawCircle(lx, cy, radius, CUSTOM_COLOR)
  lcd.drawCircle(rx, cy, radius, CUSTOM_COLOR)

  --------------------------------------------------
  -- LEFT STICK (THR/YAW)
  --------------------------------------------------
  local magL = math.sqrt(yaw * yaw + thr * thr)
  local activeLeft = magL >= edgeThr
  local angleLeft = math.atan2(-thr, yaw)
  local idxL = drawRing(lx, cy, radius, angleLeft, activeLeft, dots)
  local leftLed = idxL and LEFT_LED_MAP[idxL]

  --------------------------------------------------
  -- RIGHT STICK (ROLL/PITCH)
  --------------------------------------------------
  local magR = math.sqrt(roll * roll + pitch * pitch)
  local activeRight = magR >= edgeThr
  local angleRight = math.atan2(-pitch, roll)
  local idxR = drawRing(rx, cy, radius, angleRight, activeRight, dots)
  local rightLed = idxR and RIGHT_LED_MAP[idxR]

  --------------------------------------------------
  -- LED sync with dot colors
  --------------------------------------------------
  applyAllLeds(COLOR_PASSIVE)
  if leftLed  then setRGBLedColor(leftLed,  COLOR_ACTIVE.r, COLOR_ACTIVE.g, COLOR_ACTIVE.b) end
  if rightLed then setRGBLedColor(rightLed, COLOR_ACTIVE.r, COLOR_ACTIVE.g, COLOR_ACTIVE.b) end
  applyRGBLedColors()

  --------------------------------------------------
  -- Labels + LED index text
  --------------------------------------------------
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(255, 255, 255))
  lcd.drawText(lx, cy + radius + 10, "THR/YAW", CUSTOM_COLOR + CENTER)
  lcd.drawText(rx, cy + radius + 10, "PIT/ROL", CUSTOM_COLOR + CENTER)
  if leftLed  then lcd.drawText(lx, cy - 6, tostring(leftLed), DBLSIZE + CENTER) end
  if rightLed then lcd.drawText(rx, cy - 6, tostring(rightLed), DBLSIZE + CENTER) end

  return 0
end

return { run = run }