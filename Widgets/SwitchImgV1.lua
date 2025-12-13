local options = {
  { "Switch", SOURCE, 0 },
  { "Low",  FILE, "Low.jpg",  "/WIDGETS/SwitchPict/IMG/" },
  { "Mid",  FILE, "Mid.jpg",  "/WIDGETS/SwitchPict/IMG/" },
  { "High", FILE, "High.jpg", "/WIDGETS/SwitchPict/IMG/" },
}

local name = "SwitchPict"
local SWITCH_THRESH = 50
local DEFAULT_LOW = "/WIDGETS/SwitchPict/IMG/Low.jpg"
local DEFAULT_MID = "/WIDGETS/SwitchPict/IMG/Mid.jpg"
local DEFAULT_HIGH = "/WIDGETS/SwitchPict/IMG/High.jpg"

local function resolvePath(path, defaultPath)
  if not path or path == "" then
    return nil
  end
  if string.sub(path, 1, 1) == "/" then
    return path
  end

  local dir = string.match(defaultPath or "", "(.+)/[^/]+$") or "/"
  if string.sub(dir, -1) ~= "/" then
    dir = dir .. "/"
  end
  return dir .. path
end

local function setBitmap(widget, key, path)
  local current = widget.bitmaps[key]
  if current and current.path == path then
    return
  end

  local bmp = nil
  if path and path ~= "" then
    bmp = bitmap.open(path)
  end

  widget.bitmaps[key] = { path = path, bmp = bmp }
end

local function applyOptions(widget)
  local opts = widget.options or {}

  widget.switchSource = opts.Switch or "sa"
  setBitmap(widget, "low", resolvePath(opts.Low or DEFAULT_LOW, DEFAULT_LOW))
  setBitmap(widget, "mid", resolvePath(opts.Mid or DEFAULT_MID, DEFAULT_MID))
  setBitmap(widget, "high", resolvePath(opts.High or DEFAULT_HIGH, DEFAULT_HIGH))
end

local function create(zone, opts)
  local widget = {
    zone = zone,
    options = opts or {},
    switchSource = "sa",
    bitmaps = {
      low = { path = nil, bmp = nil },
      mid = { path = nil, bmp = nil },
      high = { path = nil, bmp = nil },
    },
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

local function pickSlot(value)
  if value > SWITCH_THRESH then
    return "high"
  elseif value < -SWITCH_THRESH then
    return "low"
  end
  return "mid"
end

local function refresh(widget, event, touchState)
  local x = widget.zone.x
  local y = widget.zone.y
  local h = widget.zone.h
  local value = getValue(widget.switchSource) or 0
  local slot = pickSlot(value)
  local entry = widget.bitmaps[slot] or {}
  local bmp = entry.bmp
  local path = entry.path or ""
  local filename = string.match(path, "([^/]+)$") or path or "none"

  if bmp then
    lcd.drawBitmap(bmp, x, y)
  else
    lcd.setColor(CUSTOM_COLOR, lcd.RGB(255, 255, 255))
    lcd.drawText(x + 4, y + 4, "No image: " .. slot, CUSTOM_COLOR + SMLSIZE)
  end

  -- show which file is selected
  lcd.setColor(CUSTOM_COLOR, lcd.RGB(255, 255, 255))
  local line1Y = y + h - 20
  local line2Y = line1Y + 12
  lcd.drawText(x + 4, line1Y, "File: " .. filename, CUSTOM_COLOR + SMLSIZE)
  lcd.drawText(x + 4, line2Y, "Path: " .. path, CUSTOM_COLOR + SMLSIZE)
end

return {
  name = name,
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background
}
