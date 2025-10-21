-- LEDHelper.lua
-- Roller + Touch LED toggler using event-based touch handling
-- TX15 / EdgeTX 2.9+

local ledState = {}     -- [0..19] booleans
local page, cursor = 0, 0
local pressIdx = nil    -- index of button being pressed
local flash = { idx = nil, t = 0 }

-- Layout (480×272)
local W, H = 480, 272
local COLS, ROWS = 5, 2
local BW, BH = 80, 48
local GX, GY = 10, 10

local gridW = COLS * BW + (COLS - 1) * GX
local gridH = ROWS * BH + (ROWS - 1) * GY
local startX = (W - gridW) // 2
local startY = (H - gridH) // 2

local ON_R, ON_G, ON_B = 0, 255, 0

--------------------------------------------------------------------
local function applyLeds()
  for i = 0, 19 do
    if ledState[i] then setRGBLedColor(i, ON_R, ON_G, ON_B)
    else setRGBLedColor(i, 0, 0, 0) end
  end
  applyRGBLedColors()
end

local function hitTest(x, y)
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local bx = startX + c * (BW + GX)
      local by = startY + r * (BH + GY)
      if x >= bx and x <= bx + BW and y >= by and y <= by + BH then
        return r * COLS + c
      end
    end
  end
end

local function drawButton(c, r, label, sel, on)
  local x = startX + c * (BW + GX)
  local y = startY + r * (BH + GY)
  lcd.drawRectangle(x, y, BW, BH, 0)
  if sel then lcd.drawRectangle(x + 2, y + 2, BW - 4, BH - 4, INVERS) end
  if on then lcd.drawFilledRectangle(x + BW - 14, y + 10, 8, 8, SOLID)
  else lcd.drawRectangle(x + BW - 14, y + 10, 8, 8, 0) end
  lcd.drawText(x + (BW//2) - 10, y + (BH//2) - 6, tostring(label), MIDSIZE)
end

local function drawUI()
  lcd.clear()
  lcd.drawText(4, 4, string.format("LED Helper | Page %d/2", page + 1), INVERS)

  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local idx = r * COLS + c
      local led = page * 10 + idx
      drawButton(c, r, led, idx == cursor, ledState[led])
    end
  end

  -- pressed highlight
  if pressIdx then
    local r = math.floor(pressIdx / COLS)
    local c = pressIdx % COLS
    local x = startX + c * (BW + GX)
    local y = startY + r * (BH + GY)
    lcd.drawRectangle(x, y, BW, BH, SOLID + INVERS)
  end

  -- flash for taps
  if flash.idx and getTime() - flash.t < 80 then
    local r = math.floor(flash.idx / COLS)
    local c = flash.idx % COLS
    local x = startX + c * (BW + GX)
    local y = startY + r * (BH + GY)
    lcd.drawRectangle(x + 3, y + 3, BW - 6, BH - 6, INVERS)
  end

  lcd.drawText(4, H - 20,
    "Tap/Enter=Toggle | Swipe/Page=Page | Roller=Move", SMLSIZE)
end

--------------------------------------------------------------------
local function handleKeys(event)
  if event == EVT_ROT_RIGHT then cursor = (cursor + 1) % 10
  elseif event == EVT_ROT_LEFT then cursor = (cursor - 1 + 10) % 10
  elseif event == EVT_ENTER_BREAK or event == EVT_MENU_BREAK then
    local n = page * 10 + cursor
    ledState[n] = not ledState[n]
    flash = { idx = cursor, t = getTime() }
  elseif event == EVT_PAGE_BREAK or event == EVT_PAGEDN_FIRST or event == EVT_PAGEUP_FIRST then
    page = (page + 1) % 2
  end
end

local function handleTouch(event, t)
  if not t then return end

  if event == EVT_TOUCH_FIRST then
    pressIdx = hitTest(t.x or -1, t.y or -1)

  elseif event == EVT_TOUCH_BREAK then
    pressIdx = nil

  elseif event == EVT_TOUCH_TAP then
    local idx = hitTest(t.x or -1, t.y or -1)
    if idx then
      local led = page * 10 + idx
      ledState[led] = not ledState[led]
      flash = { idx = idx, t = getTime() }
    end

  elseif event == EVT_TOUCH_SLIDE then
    if t.swipeLeft then page = (page + 1) % 2
    elseif t.swipeRight then page = (page - 1 + 2) % 2 end
  end
end

--------------------------------------------------------------------
local function init()
  for i = 0, 19 do ledState[i] = false end
  page, cursor = 0, 0
  applyLeds()
end

local function run(event, touchState)
  if event and event ~= 0 then
    handleKeys(event)
    handleTouch(event, touchState)
  end
  drawUI()
  applyLeds()
  return 0
end

return { run = run, init = init }