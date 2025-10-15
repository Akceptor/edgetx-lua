-- Roller-based LED Toggler (simple ON/OFF, green)
-- Page 1: LEDs 0..9
-- Page 2: LEDs 10..19
-- NAV:
--  - Roller RIGHT: next LED
--  - Roller LEFT : prev LED
--  - Press roller (ENTER): toggle on/off
--  - PAGE+ / PAGE-: switch pages (0 or 1)

local ledState = {}    -- [0..19] boolean
local page = 0         -- 0 => 0..9, 1 => 10..19
local cursor = 0       -- 0..9 index within page

-- Layout
local screenW, screenH = 480, 272
local cols, rows = 5, 2
local btnW, btnH = 80, 48
local gapX, gapY = 10, 10

-- Center grid
local gridW = cols * btnW + (cols - 1) * gapX
local gridH = rows * btnH + (rows - 1) * gapY
local startX = (screenW - gridW) // 2
local startY = (screenH - gridH) // 2

-- Colors
local ON_R, ON_G, ON_B = 0, 255, 0  -- green

local function applyLeds()
  for i = 0, 19 do
    if ledState[i] then
      setRGBLedColor(i, ON_R, ON_G, ON_B)
    else
      setRGBLedColor(i, 0, 0, 0)
    end
  end
  applyRGBLedColors()
end

local function drawButton(col, row, label, selected, on)
  local x = startX + col * (btnW + gapX)
  local y = startY + row * (btnH + gapY)

  lcd.drawRectangle(x, y, btnW, btnH, 0)
  if selected then
    lcd.drawRectangle(x+2, y+2, btnW-4, btnH-4, INVERS)
  end

  if on then
    lcd.drawFilledRectangle(x+btnW-14, y+10, 8, 8, SOLID)
  else
    lcd.drawRectangle(x+btnW-14, y+10, 8, 8, 0)
  end

  lcd.drawText(x + (btnW//2) - 10, y + (btnH//2) - 6, tostring(label), MIDSIZE)
end

local function drawUI()
  lcd.clear()
  lcd.drawText(4, 4, "LED Toggler | Page "..(page+1).."/2", INVERS)

  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local idx = row * cols + col
      local ledNum = page * 10 + idx
      local selected = (idx == cursor)
      drawButton(col, row, ledNum, selected, ledState[ledNum])
    end
  end

  lcd.drawText(4, screenH - 20, "Roll LEFT/RIGHT=Move  ENTER=Toggle  PAGE+/PAGE-=Change page", SMLSIZE)
end

local function nextIndex(i)
  return (i + 1) % 10
end

local function prevIndex(i)
  return (i - 1 + 10) % 10
end

local function handleKeys(event)
  if event == EVT_ROT_RIGHT then
    cursor = nextIndex(cursor)
  elseif event == EVT_ROT_LEFT then
    cursor = prevIndex(cursor)
  elseif event == EVT_ENTER_BREAK or event == EVT_MENU_BREAK then
    local ledNum = page * 10 + cursor
    ledState[ledNum] = not ledState[ledNum]
  elseif event == EVT_PAGE_BREAK or event == EVT_PAGEDN_FIRST or event == EVT_PAGEUP_FIRST then
    page = (page + 1) % 2
  elseif event == EVT_LEFT_BREAK then
    cursor = prevIndex(cursor)
  elseif event == EVT_RIGHT_BREAK then
    cursor = nextIndex(cursor)
  elseif event == EVT_UP_BREAK then
    cursor = (cursor - 5 + 10) % 10
  elseif event == EVT_DOWN_BREAK then
    cursor = (cursor + 5) % 10
  end
end

local function init()
  for i = 0, 19 do ledState[i] = false end
  page = 0
  cursor = 0
  applyLeds()
end

local function run(event)
  if event then
    handleKeys(event)
  end
  drawUI()
  applyLeds()
  return 0
end

return { run = run, init = init }