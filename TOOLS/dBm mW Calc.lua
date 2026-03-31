-- TNS|dBm / mW Calc|TNE
-- RF Power Converter: dBm / mW / W with live curve graph
-- TX15 Max (480x320), EdgeTX 2.11+

local LCD_W = LCD_W or 480
local LCD_H = LCD_H or 320
SOLID  = SOLID  or 0
DOTTED = DOTTED or 1

-- ── Math ─────────────────────────────────────────────────────────────────────
local function log10(x)
  if x <= 0 then return -100 end
  return math.log(x) / math.log(10)
end
local function dBm2mW(d) return 10 ^ (d / 10) end
local function mW2dBm(m) return 10 * log10(m) end

-- ── State ────────────────────────────────────────────────────────────────────
local inputStr  = "0"
local inputUnit = "dBm"   -- "dBm" | "mW" | "W"
local isNeg     = false
local dBmVal    = 0.0

-- limits: 0.001 mW (−30 dBm) … 1 000 000 mW / 1000 W (60 dBm)
local DBM_HARD_MIN = -150
local DBM_HARD_MAX = mW2dBm(1000000) -- = 60

local function syncDBm()
  local n = tonumber(inputStr) or 0
  if isNeg then n = -n end
  local d
  if inputUnit == "dBm" then
    d = n
  elseif inputUnit == "mW" then
    d = (n > 0) and mW2dBm(n) or DBM_HARD_MIN
  else
    d = (n > 0) and mW2dBm(n * 1000) or DBM_HARD_MIN
  end
  dBmVal = math.max(DBM_HARD_MIN, math.min(DBM_HARD_MAX, d))
end

-- ── Colors (theme-based) ─────────────────────────────────────────────────────
-- PRIMARY1 = foreground/text (white on dark themes)
-- PRIMARY2 = page background (dark on dark themes)
-- PRIMARY3 = widget/panel background (slightly different from page bg)
local GRID   = COLOR_THEME_PRIMARY3     -- subtle grid lines
local AXIS   = COLOR_THEME_PRIMARY1     -- axis lines (foreground)
local CURVE  = COLOR_THEME_SECONDARY1   -- accent color for curve
local DOTC   = COLOR_THEME_WARNING      -- current-value dot
local BTNBG  = COLOR_THEME_PRIMARY3     -- button background
local UNITON = COLOR_THEME_ACTIVE       -- selected unit button
local CLRB   = COLOR_THEME_WARNING      -- CLR button
local DELB   = COLOR_THEME_SECONDARY3   -- backspace button
local NEGB   = COLOR_THEME_SECONDARY2   -- +/- button

-- ── Layout ───────────────────────────────────────────────────────────────────
local HDR_H  = 0
local DISP_H = 30
local GY1    = HDR_H + DISP_H   -- 30

-- Graph region
local GX1, GX2 = 2,   291
local GY2       = LCD_H - 2     -- 318

-- Plot inner (axis margins: 38px left for mW labels, 18px bottom for dBm labels)
local PX1 = GX1 + 38  -- 40
local PX2 = GX2 - 3   -- 288
local PY1 = GY1 + 4   -- 56
local PY2 = GY2 - 14  -- leaves room for X-axis numbers only

local DBM_MIN = -10
local DBM_MAX =  33
local MW_MIN  =   0
local MW_MAX  = 250

-- nice round ceiling for axis max
local function niceCeil(x)
  if x <= 0 then return 1 end
  local mag = 10 ^ math.floor(log10(x))
  local n = x / mag
  if     n <= 1 then return 1 * mag
  elseif n <= 2 then return 2 * mag
  elseif n <= 5 then return 5 * mag
  else               return 10 * mag
  end
end

-- nice grid step given a span and desired number of divisions
local function niceStep(span, divs)
  local raw = span / divs
  if raw <= 0 then return 1 end
  local mag = 10 ^ math.floor(log10(raw))
  local n = raw / mag
  if     n <= 1 then return 1 * mag
  elseif n <= 2 then return 2 * mag
  elseif n <= 5 then return 5 * mag
  else               return 10 * mag
  end
end

-- expand axes so the current dBmVal is always visible
-- initial scale: 0 dBm = 1 mW up to ~24 dBm = 250 mW
local function updateAxisRanges()
  local dMin = math.min(0,  math.floor(dBmVal) - 3)
  local dMax = math.max(24, math.ceil(dBmVal)  + 3)
  DBM_MIN = math.floor(dMin / 5) * 5
  DBM_MAX = math.ceil( dMax / 5) * 5
  MW_MAX  = niceCeil(dBm2mW(DBM_MAX))
end

local function dBm2px(d)
  return math.floor(PX1 + (d - DBM_MIN) / (DBM_MAX - DBM_MIN) * (PX2 - PX1) + 0.5)
end
local function mW2py(m)
  m = math.max(MW_MIN, math.min(MW_MAX, m))
  return math.floor(PY2 - (m - MW_MIN) / (MW_MAX - MW_MIN) * (PY2 - PY1) + 0.5)
end

-- Keypad region (right side)
local KX1 = 295
local KX2 = LCD_W - 3   -- 477
local KW  = KX2 - KX1   -- 182

-- ── Button layout ────────────────────────────────────────────────────────────
local BTNS = {}

local function buildLayout()
  BTNS = {}
  local bw = math.floor((KW - 8) / 3)   -- ~58px per column
  local bh = 36
  local bg = 3

  -- Unit buttons  (start after 36px input display + 2px gap = GY1+38)
  local y = GY1 + 38
  local unitLabels = {"dBm", "mW", "W"}
  for i, u in ipairs(unitLabels) do
    local bx = KX1 + (i - 1) * (bw + 4)
    table.insert(BTNS, {label=u, key="U_"..u, x=bx, y=y, w=bw, h=28, isUnit=true})
  end
  y = y + 28 + 3   -- 119

  -- Numpad rows
  local rows = {{"7","8","9"},{"4","5","6"},{"1","2","3"},{"+/-","0","."}}
  for ri, row in ipairs(rows) do
    for ci, k in ipairs(row) do
      local bx = KX1 + (ci - 1) * (bw + 4)
      local by = y + (ri - 1) * (bh + bg)
      local col = BTNBG
      if k == "+/-" then col = NEGB end
      table.insert(BTNS, {label=k, key=k, x=bx, y=by, w=bw, h=bh, color=col})
    end
  end
  y = y + 4 * (bh + bg)   -- 275

  -- Bottom row: backspace + clear
  local hw = math.floor((KW - 4) / 2)   -- ~89
  table.insert(BTNS, {label="<-",  key="BS",  x=KX1,      y=y, w=hw,        h=bh, color=DELB})
  table.insert(BTNS, {label="CLR", key="CLR", x=KX1+hw+4, y=y, w=KW-hw-4,  h=bh, color=CLRB})
end

local function hitTest(x, y)
  for _, b in ipairs(BTNS) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return b.key
    end
  end
  return nil
end

-- ── Key handler ──────────────────────────────────────────────────────────────
local function numToInputStr(n, unit)
  local neg = n < 0
  n = math.abs(n)
  local s
  if unit == "dBm" then
    s = string.format("%.1f", n)
  elseif unit == "mW" then
    if     n >= 100 then s = string.format("%.1f", n)
    elseif n >= 1   then s = string.format("%.2f", n)
    else                 s = string.format("%.4f", n)
    end
  else
    if     n >= 1   then s = string.format("%.3f", n)
    else                 s = string.format("%.5f", n)
    end
  end
  if string.find(s, "%.") then
    s = string.gsub(s, "0+$", "")
    s = string.gsub(s, "%.$", "")
    if s == "" then s = "0" end
  end
  return s, neg
end

local function onKey(key)
  if key == "CLR" then
    inputStr, isNeg = "0", false

  elseif key == "BS" then
    if #inputStr > 1 then
      inputStr = string.sub(inputStr, 1, -2)
    else
      inputStr, isNeg = "0", false
    end

  elseif key == "+/-" then
    isNeg = not isNeg

  elseif string.sub(key, 1, 2) == "U_" then
    local newUnit = string.sub(key, 3)
    if newUnit ~= inputUnit then
      syncDBm()
      local newN
      if     newUnit == "dBm" then newN = dBmVal
      elseif newUnit == "mW"  then newN = dBm2mW(dBmVal)
      else                         newN = dBm2mW(dBmVal) / 1000
      end
      inputUnit = newUnit
      inputStr, isNeg = numToInputStr(newN, newUnit)
    end

  elseif key == "." then
    if not string.find(inputStr, ".", 1, true) then
      inputStr = inputStr .. "."
    end

  else  -- digit
    if inputStr == "0" then
      inputStr = key
    elseif #inputStr < 11 then
      inputStr = inputStr .. key
    end
  end

  syncDBm()
end

-- ── Format helpers ───────────────────────────────────────────────────────────
local function fmtMW(m)
  if     m >= 1000 then return string.format("%.0f",  m)
  elseif m >= 100  then return string.format("%.1f",  m)
  elseif m >= 10   then return string.format("%.2f",  m)
  elseif m >= 1    then return string.format("%.3f",  m)
  elseif m >= 0.1  then return string.format("%.4f",  m)
  else                  return string.format("%.5f",  m)
  end
end

-- ── Draw routines ────────────────────────────────────────────────────────────
local function drawHeader() end  -- removed

local function drawConvDisplay()
  lcd.drawFilledRectangle(0, 0, LCD_W, DISP_H, COLOR_THEME_PRIMARY3)
  local m = dBm2mW(dBmVal)
  local txt
  if m >= 1000 then
    txt = string.format("%.2f dBm  =  %.4f W", dBmVal, m / 1000)
  else
    txt = string.format("%.2f dBm  =  %s mW", dBmVal, fmtMW(m))
  end
  lcd.drawText(6, 2, txt, MIDSIZE)
end

local function drawGraph()
  lcd.drawFilledRectangle(GX1, GY1, GX2 - GX1, GY2 - GY1, COLOR_THEME_PRIMARY2)

  -- dynamic grid steps based on current axis ranges
  local dStep = niceStep(DBM_MAX - DBM_MIN, 8)
  local mStep = niceStep(MW_MAX, 5)

  -- Grid: vertical (dBm)
  local dStart = math.ceil(DBM_MIN / dStep) * dStep
  for d = dStart, DBM_MAX, dStep do
    local px = dBm2px(d)
    if px >= PX1 and px <= PX2 then
      lcd.drawLine(px, PY1, px, PY2, SOLID, GRID)
    end
  end
  -- Grid: horizontal (mW)
  for m = mStep, MW_MAX, mStep do
    local py = mW2py(m)
    if py >= PY1 and py <= PY2 then
      lcd.drawLine(PX1, py, PX2, py, SOLID, GRID)
    end
  end

  -- Axes
  lcd.drawLine(PX1, PY1, PX1, PY2, SOLID, AXIS)
  lcd.drawLine(PX1, PY2, PX2, PY2, SOLID, AXIS)

  -- X-axis labels (every label step = 2x grid step to avoid crowding)
  local dLblStep = niceStep(DBM_MAX - DBM_MIN, 4)
  local dLblStart = math.ceil(DBM_MIN / dLblStep) * dLblStep
  for d = dLblStart, DBM_MAX, dLblStep do
    local px = dBm2px(d)
    local lbl = tostring(d)
    lcd.drawText(px - #lbl * 3, PY2 + 3, lbl, SMLSIZE)
  end
  -- Y-axis labels (mW below 1000, W at 1000+)
  for m = mStep, MW_MAX, mStep do
    local py = mW2py(m)
    local lbl
    if m >= 1000 then
      lbl = string.format("%gW", m / 1000)
    else
      lbl = tostring(m)
    end
    lcd.drawText(GX1 + 1, py - 4, lbl, SMLSIZE)
  end

  -- Draw the curve pixel by pixel
  local prevPx, prevPy
  for px = PX1, PX2 do
    local d  = DBM_MIN + (px - PX1) / (PX2 - PX1) * (DBM_MAX - DBM_MIN)
    local py = mW2py(dBm2mW(d))
    if prevPx then
      lcd.drawLine(prevPx, prevPy, px, py, SOLID, CURVE)
    end
    prevPx, prevPy = px, py
  end


  -- Current value indicator
  local curMW = dBm2mW(dBmVal)
  if dBmVal >= DBM_MIN and dBmVal <= DBM_MAX then
    local dotX = dBm2px(dBmVal)
    local dotY = mW2py(curMW)
    -- Crosshairs
    lcd.drawLine(PX1, dotY, PX2, dotY, DOTTED, COLOR_THEME_WARNING)
    lcd.drawLine(dotX, PY1, dotX, PY2, DOTTED, COLOR_THEME_WARNING)
    -- Dot
    lcd.drawFilledRectangle(dotX - 4, dotY - 4, 9, 9, DOTC)
    lcd.drawRectangle(dotX - 5, dotY - 5, 11, 11, WHITE)
    -- Value label near dot
    local vlbl = string.format("%.1fdBm", dBmVal)
    local lx = dotX + 8
    if lx + #vlbl * 5 > PX2 then lx = dotX - #vlbl * 5 - 10 end
    local ly = dotY - 10
    if ly < PY1 + 2 then ly = dotY + 6 end
    lcd.drawText(lx, ly, vlbl, SMLSIZE)
  end

  -- Border
  lcd.drawRectangle(GX1, GY1, GX2 - GX1, GY2 - GY1, COLOR_THEME_PRIMARY1)
end

local function drawKeypad()
  lcd.drawFilledRectangle(KX1, GY1, KW, GY2 - GY1, COLOR_THEME_PRIMARY2)

  -- Input display box
  lcd.drawFilledRectangle(KX1, GY1, KW, 34, COLOR_THEME_PRIMARY3)
  lcd.drawRectangle(KX1, GY1, KW, 34, COLOR_THEME_PRIMARY1)
  local dispStr = (isNeg and "-" or "") .. inputStr .. " " .. inputUnit
  lcd.drawText(KX1 + 5, GY1 + 7, dispStr, MIDSIZE)

  -- Buttons
  for _, b in ipairs(BTNS) do
    local col = b.color or BTNBG
    if b.isUnit and b.label == inputUnit then col = UNITON end
    lcd.drawFilledRectangle(b.x, b.y, b.w, b.h, col)
    lcd.drawRectangle(b.x, b.y, b.w, b.h, COLOR_THEME_PRIMARY1)
    local cw = #b.label * 6
    local tx = b.x + math.floor((b.w - cw) / 2)
    local ty = b.y + math.floor((b.h - 10) / 2)
    lcd.drawText(tx, ty, b.label, SMLSIZE)
  end
end

-- ── Init / Run ───────────────────────────────────────────────────────────────
local function init()
  inputStr, inputUnit, isNeg, dBmVal = "0", "dBm", false, 0.0
  buildLayout()
end

local function run(event, touchState)
  -- Touch: tap on a button
  if event == EVT_TOUCH_TAP and touchState then
    local k = hitTest(touchState.x, touchState.y)
    if k then onKey(k) end
  end

  -- Hardware encoder nudges value in the current unit
  local rotUp   = (event == EVT_ROT_RIGHT or event == EVT_PLUS_FIRST  or event == EVT_DOWN_FIRST)
  local rotDown = (event == EVT_ROT_LEFT  or event == EVT_MINUS_FIRST or event == EVT_UP_FIRST)
  if rotUp or rotDown then
    local dir = rotUp and 1 or -1
    local n = (tonumber(inputStr) or 0)
    if isNeg then n = -n end
    if inputUnit == "dBm" then
      n = n + dir
    elseif inputUnit == "mW" then
      n = n + dir
      if n < 0 then n = 0 end
    else  -- W
      local step = 0.001
      if math.abs(n) >= 1 then step = 0.1
      elseif math.abs(n) >= 0.1 then step = 0.01
      end
      n = n + dir * step
      if n < 0 then n = 0 end
      n = math.floor(n * 10000 + 0.5) / 10000  -- avoid float drift
    end
    isNeg = n < 0
    inputStr, _ = numToInputStr(math.abs(n), inputUnit)
    syncDBm()
  end

  if event == EVT_EXIT_BREAK then return 2 end

  -- Draw
  updateAxisRanges()
  lcd.clear(COLOR_THEME_PRIMARY2)
  drawHeader()
  drawConvDisplay()
  drawGraph()
  drawKeypad()

  return 0
end

return { init = init, run = run }
