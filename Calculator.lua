-- Compact Touchscreen Calculator (TX15 / TOOLS mode)
-- Supports + - * /

local buttons = {}
local current, operand, operator, result = "", nil, nil, nil

-- Layout (480x272)
local W, H = 480, 272
local COLS, ROWS = 4, 4
local BW, BH = 80, 40
local GX, GY = 10, 10

local gridW = COLS * BW + (COLS - 1) * GX
local gridH = ROWS * BH + (ROWS - 1) * GY
local startX = (W - gridW) // 2
local startY = (H - gridH) // 2 + 50

-- Colors
local WHITE   = lcd.RGB(255,255,255)
local GREEN   = lcd.RGB(0,255,120)
local CYAN    = lcd.RGB(0,180,255)
local RED     = lcd.RGB(255,0,0)

local keys = {
  "7","8","9","/",
  "4","5","6","*",
  "1","2","3","-",
  "0",".","=","+"
}

-------------------------------------------------------------
local function isOperator(label)
  return (label == "+" or label == "-" or label == "*" or label == "/" or label == "=")
end

local function drawButton(c, r, label)
  local x = startX + c * (BW + GX)
  local y = startY + r * (BH + GY)

  local borderColor = GREEN
  if isOperator(label) then borderColor = CYAN end
  if label == "C" then borderColor = RED end

  lcd.setColor(CUSTOM_COLOR, borderColor)
  lcd.drawRectangle(x, y, BW, BH, CUSTOM_COLOR)

  -- text always white
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawText(x + BW/2, y + BH/2 - 12, label, CENTER + MIDSIZE + CUSTOM_COLOR)

  table.insert(buttons, {x=x, y=y, w=BW, h=BH, label=label})
end

local function drawClearButton()
  local cw, ch = 50, 40
  local cx, cy = 40, 30

  lcd.setColor(CUSTOM_COLOR, RED)
  lcd.drawRectangle(cx, cy, cw, ch, CUSTOM_COLOR)

  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawText(cx + cw/2, cy + ch/2 - 12, "C", CENTER + MIDSIZE + CUSTOM_COLOR)

  table.insert(buttons, {x=cx, y=cy, w=cw, h=ch, label="C"})
end

local function hitTest(x, y)
  for _, b in ipairs(buttons) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      return b.label
    end
  end
end

-------------------------------------------------------------
local function eval()
  if operand and operator and current ~= "" then
    local a = tonumber(operand)
    local b = tonumber(current)
    if a and b then
      if operator == "+" then result = a + b
      elseif operator == "-" then result = a - b
      elseif operator == "*" then result = a * b
      elseif operator == "/" then result = (b ~= 0) and (a / b) or "Err"
      end
      operand, current, operator = tostring(result), "", nil
    end
  end
end

-------------------------------------------------------------
local function drawUI()
  lcd.clear()
  buttons = {}

  -- [C] button
  drawClearButton()

  -- Display bar
  local dx, dy, dw, dh = 100, 30, 340, 40
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawRectangle(dx, dy, dw, dh, CUSTOM_COLOR)
  local txt = current ~= "" and current or (result and tostring(result) or "0")
  lcd.drawText(dx + dw - 10, dy + 5, txt, RIGHT + DBLSIZE + CUSTOM_COLOR) -- moved 15 px higher

  -- Keypad
  for i, label in ipairs(keys) do
    local idx = i - 1
    local r = math.floor(idx / COLS)
    local c = idx % COLS
    drawButton(c, r, label)
  end
end

-------------------------------------------------------------
local function handleTouch(event, t)
  if event == EVT_TOUCH_TAP and t and t.x and t.y then
    local label = hitTest(t.x, t.y)
    if not label then return end

    if label >= "0" and label <= "9" then
      current = current .. label
    elseif label == "." then
      if not string.find(current, ".", 1, true) then
        current = current .. "."
      end
    elseif label == "C" then
      operand, operator, current, result = nil, nil, "", nil
    elseif label == "=" then
      eval()
    elseif isOperator(label) then
      if current ~= "" then
        if operand and operator then eval()
        else operand = current end
        current = ""
      end
      operator = label
    end
  end
end

-------------------------------------------------------------
local function run(event, touchState)
  if event and event ~= 0 then
    handleTouch(event, touchState)
  end
  drawUI()
  return 0
end

return { run = run }