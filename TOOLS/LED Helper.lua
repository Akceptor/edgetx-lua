-- LED Helper (LVGL)
-- Touch LED toggler using LVGL controls
-- TX15 / EdgeTX 2.11

local PAGE_COUNT = 2
local PER_PAGE = 10

local ledState = {} -- [0..19] booleans
local ledColors = {} -- [0..19] {r,g,b}
local currentPage = 0
local exitTool = false

local ui = {
  page = nil,
  buttons = {},
  colorButtons = {},
  swatchPositions = {},
  activeIndicator = nil
}

local LCD_W = LCD_W or 480
local LCD_H = LCD_H or 272

local WHITE = lcd.RGB(255, 255, 255)
local DARK = lcd.RGB(40, 40, 40)

local currentColorValue565 = 0
local currentColorRgb = { r = 0, g = 255, b = 0 }
local activeSwatchIndex = nil
local COLOR_SWATCHES = {
  { r = 255, g = 0, b = 0 },
  { r = 0, g = 255, b = 0 },
  { r = 0, g = 0, b = 255 },
  { r = 255, g = 255, b = 255 },
  { r = 255, g = 255, b = 0 },
  { r = 255, g = 0, b = 255 }
}

local function rgbColor(r, g, b)
  return lcd.RGB(r, g, b)
end

local function rgbTo565(r, g, b)
  local r5 = math.floor(r * 31 / 255)
  local g6 = math.floor(g * 63 / 255)
  local b5 = math.floor(b * 31 / 255)
  return r5 * 2048 + g6 * 32 + b5
end

local function colorFromValue(value)
  if type(value) == "table" then
    if value.r and value.g and value.b then
      return { r = value.r, g = value.g, b = value.b }
    end
    if value.red and value.green and value.blue then
      return { r = value.red, g = value.green, b = value.blue }
    end
    if type(value.color) == "number" then
      return colorFromValue(value.color)
    end
    if type(value.value) == "number" then
      return colorFromValue(value.value)
    end
  elseif type(value) == "number" then
    local r5 = math.floor(value / 2048) % 32
    local g6 = math.floor(value / 32) % 64
    local b5 = value % 32
    local r = math.floor(r5 * 255 / 31)
    local g = math.floor(g6 * 255 / 63)
    local b = math.floor(b5 * 255 / 31)
    return { r = r, g = g, b = b }
  end
end

local function currentColor()
  return currentColorRgb
end

local function setActiveSwatchIndex(col)
  activeSwatchIndex = nil
  if not col then return end
  for i, swatch in ipairs(COLOR_SWATCHES) do
    if swatch.r == col.r and swatch.g == col.g and swatch.b == col.b then
      activeSwatchIndex = i
      return
    end
  end
end

local function refreshActiveIndicator()
  if not ui or not ui.activeIndicator then return end
  if not activeSwatchIndex then
    ui.activeIndicator:set({ x = -1000, y = -1000 })
    return
  end
  local pos = ui.swatchPositions[activeSwatchIndex]
  if not pos then return end
  ui.activeIndicator:set({
    x = pos.x + math.floor((pos.w - pos.indicatorW) / 2),
    y = pos.y + pos.h + pos.indicatorGap
  })
end

local function ledColor(led)
  return ledColors[led] or currentColor()
end

local function applyLeds()
  if not setRGBLedColor or not applyRGBLedColors then return end
  for i = 0, 19 do
    if ledState[i] then
      local col = ledColor(i)
      if col then
        setRGBLedColor(i, col.r, col.g, col.b)
      else
        setRGBLedColor(i, 0, 0, 0)
      end
    else
      setRGBLedColor(i, 0, 0, 0)
    end
  end
  applyRGBLedColors()
end

local function ledIndex(slot)
  return currentPage * PER_PAGE + (slot - 1)
end

local function refreshButtons()
  if not ui then return end
  for i = 1, PER_PAGE do
    local led = ledIndex(i)
    local btn = ui.buttons[i]
    if btn then
      local col = ledColor(led)
      btn:set({
        text = tostring(led),
        color = ledState[led] and (col and rgbColor(col.r, col.g, col.b) or DARK) or DARK,
        textColor = WHITE
      })
    end
  end
end

local function toggleLed(slot)
  if slot == nil then return end
  local led = ledIndex(slot)
  if led == nil then return end
  ledState[led] = not ledState[led]
  if ledState[led] then
    local col = currentColor()
    if col then
      ledColors[led] = { r = col.r, g = col.g, b = col.b }
    end
  else
    ledColors[led] = nil
  end
  applyLeds()
  refreshButtons()
end

local function changePage(delta)
  if delta == nil then return end
  currentPage = (currentPage + delta + PAGE_COUNT) % PAGE_COUNT
  refreshButtons()
end

local function setCurrentColor(value)
  local col = colorFromValue(value)
  if not col then return end
  currentColorRgb = col
  currentColorValue565 = rgbTo565(col.r, col.g, col.b)
  applyLeds()
  setActiveSwatchIndex(col)
  refreshActiveIndicator()
  refreshButtons()
end

local function close()
  if not lvgl or not lvgl.confirm then
    exitTool = true
    return
  end
  lvgl.confirm({
    title = "Exit",
    message = "Really exit?",
    confirm = function() exitTool = true end
  })
end

local function buildUi()
  if not lvgl or not lvgl.clear or not lvgl.page then return end
  lvgl.clear()
  ui.page = lvgl.page({
    title = "LED Helper",
    subtitle = "Tap LED to toggle, tap color to choose",
    back = close,
    scrollable = false
  })

  local cols = 5
  local rows = 2
  local margin = 10
  local gap = 10
  local btnH = 60
  local btnW = math.floor((LCD_W - (margin * 2) - (gap * (cols - 1))) / cols)
  local startY = 60

  for i = 1, PER_PAGE do
    local r = math.floor((i - 1) / cols)
    local c = (i - 1) % cols
    local x = margin + c * (btnW + gap)
    local y = startY + r * (btnH + gap)
    ui.buttons[i] = ui.page:button({
      x = x,
      y = y,
      w = btnW,
      h = btnH,
      text = tostring(i - 1),
      font = MIDSIZE,
      color = DARK,
      textColor = WHITE,
      press = function()
        toggleLed(i)
      end
    })
  end

  local gridH = rows * btnH + (rows - 1) * gap
  local swatchY = startY + gridH + 4
  local swatchSize = 36
  local swatchGap = 8
  local swatchCount = #COLOR_SWATCHES
  local swatchRowW = swatchCount * swatchSize + (swatchCount - 1) * swatchGap
  local swatchX = math.floor((LCD_W - swatchRowW) / 2)
  for i, swatch in ipairs(COLOR_SWATCHES) do
    ui.colorButtons[i] = ui.page:button({
      x = swatchX + (i - 1) * (swatchSize + swatchGap),
      y = swatchY,
      w = swatchSize,
      h = swatchSize,
      text = "",
      color = rgbColor(swatch.r, swatch.g, swatch.b),
      textColor = WHITE,
      press = function()
        setCurrentColor(swatch)
      end
    })
    ui.swatchPositions[i] = {
      x = swatchX + (i - 1) * (swatchSize + swatchGap),
      y = swatchY,
      w = swatchSize,
      h = swatchSize,
      indicatorW = 10,
      indicatorH = 10,
      indicatorGap = 2
    }
  end
  ui.activeIndicator = ui.page:label({
    x = 0,
    y = 0,
    w = 10,
    h = 10,
    font = SMLSIZE,
    align = lvgl.ALIGN_CENTER,
    text = "v"
  })

  local navY = swatchY + swatchSize + 6
  local navH = 34
  local navW = 90

  ui.page:button({
    x = margin,
    y = navY,
    w = navW,
    h = navH,
    text = "<",
    font = MIDSIZE,
    color = DARK,
    textColor = WHITE,
    press = function() changePage(-1) end
  })

  ui.page:button({
    x = LCD_W - margin - navW,
    y = navY,
    w = navW,
    h = navH,
    text = ">",
    font = MIDSIZE,
    color = DARK,
    textColor = WHITE,
    press = function() changePage(1) end
  })

  refreshButtons()
  setActiveSwatchIndex(currentColor())
  refreshActiveIndicator()
end

local function init()
  for i = 0, 19 do
    ledState[i] = false
    ledColors[i] = nil
  end
  currentPage = 0
  currentColorValue565 = rgbTo565(currentColorRgb.r, currentColorRgb.g, currentColorRgb.b)
  applyLeds()
  buildUi()
end

local function run(event, touchState)
  if exitTool then
    return 2
  end
  return 0
end

return { init = init, run = run, useLvgl = true }
