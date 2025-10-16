local options = {
}

-- switches
local ARM_SWITCH = "sa"
local MODE_SWITCH = "sb"
local SC_SWITCH = "sc"
local SD_SWITCH = "sd"

local function drawOutlinedText(x, y, text, color, flags)
  -- outline 
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(0, 0, 0)) -- BLACK
  lcd.drawText(x - 1, y,     text, CUSTOM_COLOR + flags)
  lcd.drawText(x + 1, y,     text, CUSTOM_COLOR + flags)
  lcd.drawText(x,     y - 1, text, CUSTOM_COLOR + flags)
  lcd.drawText(x,     y + 1, text, CUSTOM_COLOR + flags)

  -- main text
  lcd.setColor(CUSTOM_COLOR, color) -- COLOR
  lcd.drawText(x, y, text, CUSTOM_COLOR + flags)
end

local function create(zone, options)
  local widget = { zone = zone, options = options }
  return widget
end

local function update(widget, options)
  widget.options = options
end

local function background(widget)
end

function refresh(widget, event, touchState)
  local x = widget.zone.x
  local y = widget.zone.y
  local w = widget.zone.w

  -- === FLIGHT MODE ===
  local sbValue = getValue(MODE_SWITCH)
  local mode1 = "ACRO"
  if sbValue < -50 then
    mode1 = "ANGL"
  elseif sbValue > 50 then
    mode1 = "AIR"
  end
  drawOutlinedText(x, y, mode1, lcd.RGB(255,255,255), DBLSIZE + BOLD)

  -- === ARM  ===
  local armValue = getValue(ARM_SWITCH)
  local armed = (armValue > 0)
  local armText = armed and "ARMED" or "DISARMED"
  local armColor = armed and lcd.RGB(255,0,0) or lcd.RGB(0,255,0)
  drawOutlinedText(x, y + 30, armText, armColor, MIDSIZE + BOLD)

  -- === SC (left) and SD (right) on same line  ===
  local scValue = getValue(SC_SWITCH)
  local scText = "-"
  if scValue < -50 then
    scText = "^"
  elseif scValue > 50 then
    scText = "_"
  end

  local sdValue = getValue(SD_SWITCH)
  local sdText = "-"
  if sdValue < -50 then
    sdText = "^"
  elseif sdValue > 50 then
    sdText = "_"
  end

  drawOutlinedText(x, y + 60, scText, lcd.RGB(255,255,255), MIDSIZE + BOLD)
  drawOutlinedText(x + 80, y + 60, sdText, lcd.RGB(255,255,255), MIDSIZE + BOLD)
end

return {
  name = "ModeWidget",
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background
}