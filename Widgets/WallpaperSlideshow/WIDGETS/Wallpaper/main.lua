local name = "Wallpaper"

-- Widget options
local options = {
  { "Shuffle", BOOL, 0 },
  { "Delay",   VALUE, 10, 1, 60 },
  { "Debug",   BOOL, 0 },
}

local function listWallpapers()
  local files = {}
  for fname in dir("/WALLPAPERS") do
    local lower = string.lower(fname)
    if string.match(lower, "^slide_.*%.jpg$") then -- this is because we have files like _1.jpg which are empty
      files[#files + 1] = fname
    end
  end
  table.sort(files) -- keep deterministic order when shuffle is off, otherwise the order from dir() may vary
  return files
end

local function applyOptions(widget)
  local opts = widget.options or {}

  -- Named options, with defaults. IDK if this works on older FW versions.
  widget.shuffle = opts.Shuffle or 0
  widget.delay   = opts.Delay or 10
  widget.debug   = opts.Debug or 0

  if widget.delay < 1 then widget.delay = 1 end
end

local function pickNextIndex(widget)
  if widget.shuffle == 1 then
    if widget.count <= 1 then return 1 end
    local idx = math.random(1, widget.count)
    while idx == widget.current do
      idx = math.random(1, widget.count)
    end
    return idx
  else
    local idx = widget.current + 1
    if idx > widget.count then idx = 1 end
    return idx
  end
end

local function create(zone, opts)
  local widget = {
    zone = zone,
    options = opts,
    files = listWallpapers(),
    count = 0,
    current = 1,
    lastSwitch = getTime(),
    currentImg = nil,
    nextImg = nil,
    nextIndex = 1,
    shuffle = 0,
    delay = 10,
    debug = 0
  }

  applyOptions(widget)

  widget.count = #widget.files

  if widget.count > 0 then
    widget.currentImg = bitmap.open("/WALLPAPERS/" .. widget.files[1])
    widget.nextIndex = pickNextIndex(widget)
  end

  return widget
end

local function update(widget, opts)
  widget.options = opts
  applyOptions(widget)
end

local function background(widget) end

local function refresh(widget, event, touch)
  local x = widget.zone.x
  local y = widget.zone.y

  if widget.count == 0 then
    if widget.debug == 1 then
      lcd.setColor(CUSTOM_COLOR, lcd.RGB(255,255,255))
      lcd.drawText(x + 5, y + 5, "No slide_*.jpg", CUSTOM_COLOR)
    end
    return
  end

  if widget.currentImg then
    lcd.drawBitmap(widget.currentImg, x, y)
  end

  if not widget.nextImg then
    local fname = widget.files[widget.nextIndex]
    widget.nextImg = bitmap.open("/WALLPAPERS/" .. fname)
  end

  local delaySeconds = widget.delay
  local delayTicks = delaySeconds * 100

  if widget.nextImg and (getTime() - widget.lastSwitch > delayTicks) then
    widget.lastSwitch = getTime()

    widget.currentImg = widget.nextImg
    widget.nextImg = nil

    widget.current = widget.nextIndex
    widget.nextIndex = pickNextIndex(widget)
  end

  if widget.debug == 1 then
    lcd.setColor(CUSTOM_COLOR, lcd.RGB(255,255,255))
    lcd.drawText(x + 5, y + 5,  "Delay=" .. tostring(widget.delay), CUSTOM_COLOR)
    lcd.drawText(x + 5, y + 20, "Shuffle=" .. tostring(widget.shuffle), CUSTOM_COLOR)
    lcd.drawText(x + 5, y + 35, "File=" .. tostring(widget.files[widget.current]), CUSTOM_COLOR)
  end
end

return {
  name = name,
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background
}
