local options = {
  { "Arm", SOURCE, 0 },
  { "Mode", SOURCE, 0 },
  { "Color", COLOR, lcd.RGB(255, 255, 255) },
  { "Picture", SLIDER, 0, 0, 3 },
}
-- ADJUSTMENT COLORS
local MODEL_NAME_COLOR = LIGHTGREY
local ARMED_COLOR = RED
local DISARMED_COLOR = GREEN

local function drawOutlinedText(widget, x, y, text, color, flags)
  -- outline
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(0, 0, 0)) -- BLACK
  lcd.drawText(x - 1, y,     text, CUSTOM_COLOR + flags)
  lcd.drawText(x + 1, y,     text, CUSTOM_COLOR + flags)
  lcd.drawText(x,     y - 1, text, CUSTOM_COLOR + flags)
  lcd.drawText(x,     y + 1, text, CUSTOM_COLOR + flags)

  -- main text
  local mainColor = color or widget.textColor or lcd.RGB(255, 255, 255)
  lcd.setColor(CUSTOM_COLOR, mainColor) -- COLOR
  lcd.drawText(x, y, text, CUSTOM_COLOR + flags)
end

local function applyOptions(widget)
  local opts = widget.options or {}
  -- fallback to defaults if options are missing
  widget.armSwitch = opts.Arm or "sa"
  widget.modeSwitch = opts.Mode or "sb"
  widget.textColor = opts.Color or lcd.RGB(255, 255, 255)
  widget.pictureMode = opts.Picture or 0
end

local function create(zone, opts)
  local widget = {
    zone = zone,
    options = opts or {},
    bgBitmap = nil,
    bgBitmapPath = nil,
  }
  applyOptions(widget)
  return widget
end

local function update(widget, opts)
  widget.options = opts or {}
  applyOptions(widget)
end

local function background(widget)
end

function refresh(widget, event, touchState)
  local x = widget.zone.x
  local y = widget.zone.y
  local w = widget.zone.w
  local h = widget.zone.h
  local textX = x
  local info = model.getInfo() or {}

  local showName = (widget.pictureMode == 1 or widget.pictureMode == 3)
  local showPicture = (widget.pictureMode == 2 or widget.pictureMode == 3)
  local lineGap = 6
  local mainLineH = 30
  local subLineH = 24

  if showPicture then
    local bmpPath = info and info.bitmap
    -- model bitmap is usually stored relative to /IMAGES
    if bmpPath and bmpPath ~= "" then
      if string.sub(bmpPath, 1, 1) ~= "/" then
        bmpPath = "/IMAGES/" .. bmpPath
      end
    end
    if bmpPath and bmpPath ~= "" then
      if widget.bgBitmapPath ~= bmpPath or not widget.bgBitmap then
        widget.bgBitmap = bitmap.open(bmpPath)
        widget.bgBitmapPath = bmpPath
      end
      if widget.bgBitmap then
        local bw, bh = bitmap.getSize(widget.bgBitmap)
        if not bw then bw = 0 end
        if not bh then bh = 0 end
        local imgX = x + w - bw
        if imgX < x then imgX = x end
        lcd.drawBitmap(widget.bgBitmap, imgX, y)
      end
    end
  end

  -- === FLIGHT MODE ===
  local sbValue = getValue(widget.modeSwitch)
  local mode1 = "ACRO"
  if sbValue < -50 then
    mode1 = "ANGL"
  elseif sbValue > 50 then
    mode1 = "AIR"
  end
  if showName and info.name and info.name ~= "" then
    local nameX = x + w
    drawOutlinedText(widget, nameX, y, info.name, MODEL_NAME_COLOR, MIDSIZE + BOLD + RIGHT)
  end

  local armValue = getValue(widget.armSwitch)
  local armed = (armValue > 0)
  local armText = armed and "ARMED" or "DISARMED"
  local armColor = armed and ARMED_COLOR or DISARMED_COLOR

  if showName then
    local armY = y + h - subLineH - 20
    local modeY = armY - lineGap - mainLineH
    drawOutlinedText(widget, textX, modeY, mode1, widget.textColor, DBLSIZE + BOLD)
    drawOutlinedText(widget, textX, armY, armText, armColor, MIDSIZE + BOLD)
  else
    local modeY = y
    local armY = modeY + mainLineH + lineGap
    drawOutlinedText(widget, textX, modeY, mode1, widget.textColor, DBLSIZE + BOLD)
    drawOutlinedText(widget, textX, armY, armText, armColor, MIDSIZE + BOLD)
  end
end

return {
  name = "ModeWidget",
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background
}
