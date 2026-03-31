-- LVGL Touch Calculator for EdgeTX (TOOLS script)
-- Simple calculator with basic operations and error handling
-- Supports: +, -, *, /, decimal point, clear, and equals
-- Designed for use with LVGL on EdgeTX
-- Requires: EdgeTX with LVGL support andTOOLS script environment

local exitTool = false

local current, operand, operator, result = "", nil, nil, nil
local displayLabel = nil

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

local function displayText()
  if current ~= "" then return current end
  if result ~= nil then return tostring(result) end
  return "0"
end

local function eval()
  if operand and operator and current ~= "" then
    local a = tonumber(operand)
    local b = tonumber(current)
    if a and b then
      if operator == "+" then result = a + b
      elseif operator == "-" then result = a - b
      elseif operator == "*" then result = a * b
      elseif operator == "/" then
        if b == 0 then result = "Err" else result = a / b end
      end
      operand, current, operator = tostring(result), "", nil
    end
  end
end

local function onKeyPress(label)
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

  elseif label == "+" or label == "-" or label == "*" or label == "/" then
    if current ~= "" then
      if operand and operator then eval() else operand = current end
      current = ""
    end
    operator = label
  end

  return 0
end

local function close()
  lvgl.confirm({
    title = "Exit",
    message = "Really exit?",
    confirm = function() exitTool = true end
  })
end

local function init()
  lvgl.clear()

  local pg = lvgl.page({
    title = "Calculator",
    subtitle = "LVGL",
    back = close,
    scrollable = false
  })

  displayLabel = pg:label({
    x = 10, y = 10,
    w = 360, h = 50,
    font = DBLSIZE,
    align = lvgl.ALIGN_RIGHT,
    text = function() return displayText() end
  })

  pg:button({
    x = 360, y = 10,
    w = 80, h = 45,
    text = "C",
    font = MIDSIZE,
    color = RED,
    textColor = WHITE,
    press = function() onKeyPress("C") end
  })

  local BW, BH = 100, 45
  local GX, GY = 10, 10
  local startX = 10
  local startY = 65

  local i = 0
  for _, label in ipairs(keys) do
    local r = math.floor(i / 4)
    local c = i % 4

    local col = GREEN
    if label == "+" or label == "-" or label == "*" or label == "/" or label == "=" then
      col = CYAN
    end

    pg:button({
      x = startX + c * (BW + GX),
      y = startY + r * (BH + GY),
      w = BW, h = BH,
      text = label,
      font = MIDSIZE,
      color = col,
      textColor = WHITE,
      press = function() onKeyPress(label) end
    })

    i = i + 1
  end
end

local function run(event, touchState)
  if exitTool then return 2 end
  return 0
end

return { init = init, run = run, useLvgl = true }
