-- TNS|Config Viewer|TNE
local cfgPath = "vtxConfig_auto.cfg"
local cfgPathFallback = "/SCRIPTS/TOOLS/vtxConfig_auto.cfg"
local values = {}
local positions = {}
local errorMsg = nil
local loaded = false
local debugLines = nil

local function loadConfig()
  values = {}
  positions = {}
  debugLines = nil
  local ok, file = pcall(io.open, cfgPath, "r")
  if not ok or not file then
    ok, file = pcall(io.open, cfgPathFallback, "r")
  end
  if not ok or not file then
    errorMsg = "vtxConfig_auto.cfg not found"
    return
  end

  local lines = {}
  local maxLines = 20
  while #lines < maxLines do
    local chunk = io.read(file, 128)
    if not chunk or #chunk == 0 then
      break
    end
    for line in string.gmatch(chunk, "([^\r\n]+)") do
      lines[#lines + 1] = line
      if #lines >= maxLines then
        break
      end
    end
  end
  io.close(file)

  local function stripPrefix(line, label)
    if not line then
      return nil
    end
    local pattern = "^%s*" .. label .. "%s*:%s*(.+)%s*$"
    return string.match(line, pattern)
  end

  values["Band"] = stripPrefix(lines[1], "Band")
  values["Channel"] = stripPrefix(lines[2], "Channel")
  values["Command"] = stripPrefix(lines[3], "Command")
  values["Switch"] = stripPrefix(lines[4], "Switch")
  values["Positions"] = stripPrefix(lines[5], "Positions")

  if #lines == 0 or (values["Band"] == nil and values["Channel"] == nil and values["Switch"] == nil) then
    errorMsg = "No data in vtxConfig_auto.cfg"
    debugLines = lines
    return
  end

  local positionsCount = tonumber(values["Positions"] or "0") or 0
  for i = 1, positionsCount do
    local pos = stripPrefix(lines[5 + i], "Pos" .. i)
    if pos and pos ~= "" then
      positions[#positions + 1] = pos
    end
  end

  loaded = true
end

local function drawTextLine(y, label, value)
  lcd.drawText(2, y, label .. (value or ""))
end

local function draw()
  lcd.clear()
  if errorMsg then
    lcd.drawText(2, 2, errorMsg, INVERS)
    if debugLines and #debugLines > 0 then
      local y = 14
      for i = 1, #debugLines do
        lcd.drawText(2, y, debugLines[i])
        y = y + 10
        if y > 54 then
          break
        end
      end
    end
    return
  end

  drawTextLine(2, "Band Command: ", values["Band"])
  drawTextLine(14, "Channel Command: ", values["Channel"])
  drawTextLine(26, "Switch Name: ", values["Switch"])
  drawTextLine(38, "Switch Positions: ", values["Positions"])
  if #positions > 0 then
    drawTextLine(50, "Positions: ", table.concat(positions, ", "))
  end
end

local function init()
  loadConfig()
end

local function run(event)
  if not loaded and not errorMsg then
    loadConfig()
  end
  draw()
  return 0
end

return { init = init, run = run }
