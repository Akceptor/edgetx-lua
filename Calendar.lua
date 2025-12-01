-- TNS|Calendar|TNE

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local screenW = LCD_W
local screenH = LCD_H

local BG = lcd.RGB(240,240,240)
local TEXT_BLACK = lcd.RGB(0,0,0)
local TODAY_BG = lcd.RGB(0,180,0)
local SELECT_BG = lcd.RGB(210,210,210)
local POPUP_BG = lcd.RGB(230,230,230)
local POPUP_BORDER = lcd.RGB(50,50,50)

local HEADER_Y = 10
local HEADER_MARGIN = 8
local WEEKDAY_HEIGHT = 22
local CELL_HEIGHT = 20

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local current = getDateTime()
local viewYear = current.year
local viewMonth = current.mon
local selectedDay = current.day

local popupActive = false
local popupLines = {}
local popupScroll = 0

---------------------------------------------------------------------
-- DATE HELPERS
---------------------------------------------------------------------

local daysInMonth = { 31,28,31,30,31,30,31,31,30,31,30,31 }

local function isLeap(y)
  return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

local function getMonthDays(y,m)
  if m == 2 then return isLeap(y) and 29 or 28 end
  return daysInMonth[m]
end

-- Monday=1 … Sunday=7
local function weekday(y,m,d)
  if m < 3 then
    m = m + 12
    y = y - 1
  end
  local k = y % 100
  local j = math.floor(y / 100)
  local h = (d + math.floor((13*(m+1))/5) + k + math.floor(k/4)
          + math.floor(j/4) + 5*j) % 7
  return ((h + 5) % 7) + 1
end

local function monthName(m)
  return ({
    "January","February","March","April","May","June",
    "July","August","September","October","November","December"
  })[m]
end

---------------------------------------------------------------------
-- SELECTION / MONTH SWITCH
---------------------------------------------------------------------

local function clampSelection()
  local md = getMonthDays(viewYear, viewMonth)
  if selectedDay > md then selectedDay = md end
  if selectedDay < 1 then selectedDay = 1 end
end

local function changeMonth(d)
  viewMonth = viewMonth + d
  if viewMonth < 1 then viewMonth = 12; viewYear = viewYear - 1 end
  if viewMonth > 12 then viewMonth = 1; viewYear = viewYear + 1 end
  if viewYear < 1970 then viewYear = 1970 end
  if viewYear > 2070 then viewYear = 2070 end
  clampSelection()
end

local function moveSelection(d)
  selectedDay = selectedDay + d
  clampSelection()
end

---------------------------------------------------------------------
-- LOG FILE CHECK + READING
---------------------------------------------------------------------

local function logFilePath(day,month,year)
  return string.format("/LOGS/%02d_%02d_%04d.txt", day, month, year)
end

local function hasLog(day,month,year)
  local ok, st = pcall(fstat, logFilePath(day,month,year))
  return ok and st ~= nil
end

local function openLogFile(day,month,year)
  popupLines = {}
  popupScroll = 0

  local path = logFilePath(day,month,year)
  local ok, f = pcall(io.open, path, "r")
  if not ok or not f then
    popupLines = { "Unable to open file" }
    return
  end

  while true do
    local line = io.read(f, 128)
    if not line or #line == 0 then break end

    for l in string.gmatch(line, "([^\r\n]+)") do
      table.insert(popupLines, l)
    end
  end

  io.close(f)
end

---------------------------------------------------------------------
-- FLIGHT TIME COMPUTATION
---------------------------------------------------------------------

local function parseTime(h, m, s)
  return h*3600 + m*60 + s
end

local function fmt(n)
  return string.format("%02d", n)
end

local function diffToHMS(sec)
  if sec < 0 then sec = 0 end
  local h = math.floor(sec/3600)
  sec = sec % 3600
  local m = math.floor(sec/60)
  local s = sec % 60
  return string.format("%s:%s:%s", fmt(h), fmt(m), fmt(s))
end

local function computeInlineFlightTime(line)
  -- expecting: Armed: HH:MM:SS; Disarmed: HH:MM:SS;
  local ah, am, as, dh, dm, ds =
    string.match(line,
      "Armed:%s*(%d+):(%d+):(%d+).*Disarmed:%s*(%d+):(%d+):(%d+)")

  if not ah then
    return line -- no change
  end

  local t1 = parseTime(tonumber(ah), tonumber(am), tonumber(as))
  local t2 = parseTime(tonumber(dh), tonumber(dm), tonumber(ds))

  local diff = diffToHMS(t2 - t1)

  return string.format("%s (%s)", line, diff)
end

---------------------------------------------------------------------
-- POPUP DRAW
---------------------------------------------------------------------

local function drawPopup()
  local X, Y = 20, 20
  local W, H = screenW - 40, screenH - 40

  lcd.setColor(CUSTOM_COLOR, POPUP_BG)
  lcd.drawFilledRectangle(X, Y, W, H, CUSTOM_COLOR)

  lcd.setColor(CUSTOM_COLOR, POPUP_BORDER)
  lcd.drawRectangle(X, Y, W, H, SOLID)

  local y = Y + 6
  local maxVisible = math.floor((H - 12) / 16)

  for i = 1, maxVisible do
    local idx = popupScroll + i
    local line = popupLines[idx]
    if line then
      lcd.setColor(CUSTOM_COLOR, TEXT_BLACK)
      lcd.drawText(X + 6, y, computeInlineFlightTime(line), CUSTOM_COLOR)
    end
    y = y + 16
  end
end

---------------------------------------------------------------------
-- CALENDAR DRAW
---------------------------------------------------------------------

local function drawCalendar()
  lcd.setColor(CUSTOM_COLOR, BG)
  lcd.drawFilledRectangle(0, 0, screenW, screenH, CUSTOM_COLOR)

  -- Header
  local title = string.format("%s %d", monthName(viewMonth), viewYear)
  local tw, th = lcd.sizeText(title, MIDSIZE + BOLD)
  lcd.setColor(CUSTOM_COLOR, TEXT_BLACK)
  lcd.drawText((screenW - tw) // 2, HEADER_Y, title, CUSTOM_COLOR + MIDSIZE + BOLD)

  -- Weekday names
  local weekdays = {"Mon","Tue","Wed","Thu","Fri","Sat","Sun"}
  local cellW = screenW // 7
  local yStart = HEADER_Y + th + HEADER_MARGIN

  for i=1,7 do
    local color = (i >= 6) and lcd.RGB(200,0,0) or TEXT_BLACK
    lcd.setColor(CUSTOM_COLOR, color)
    lcd.drawText((i-1)*cellW + 4, yStart, weekdays[i], CUSTOM_COLOR + BOLD)
  end

  local y = yStart + WEEKDAY_HEIGHT
  local firstDow = weekday(viewYear, viewMonth, 1)
  local mdays = getMonthDays(viewYear, viewMonth)
  local today = getDateTime()
  local isTodayMonth = (today.year == viewYear and today.mon == viewMonth)

  local day = 1
  local col = firstDow
  local row = 0

  while day <= mdays do
    local x = (col - 1)*cellW + 4
    local yy = y + row*CELL_HEIGHT

    local isWeekend = (col >= 6)
    local txtColor = isWeekend and lcd.RGB(200,0,0) or TEXT_BLACK
    lcd.setColor(CUSTOM_COLOR, txtColor)
    local flags = BOLD

    local boxX = x - 2
    local boxY = yy - 2
    local boxW = cellW - 4
    local boxH = 18

    local isToday = isTodayMonth and day == today.day
    local isSelected = day == selectedDay

    if isToday then
      lcd.setColor(CUSTOM_COLOR, TODAY_BG)
      lcd.drawFilledRectangle(boxX, boxY, boxW, boxH, CUSTOM_COLOR)
      lcd.setColor(CUSTOM_COLOR, lcd.RGB(255,255,255))
    elseif isSelected then
      lcd.setColor(CUSTOM_COLOR, SELECT_BG)
      lcd.drawFilledRectangle(boxX, boxY, boxW, boxH, CUSTOM_COLOR)
      lcd.setColor(CUSTOM_COLOR, txtColor)
    end

    if isSelected then
      lcd.drawRectangle(boxX-1, boxY-1, boxW+2, boxH+2, SOLID)
    end

    -- check log file
    local logfile = hasLog(day, viewMonth, viewYear)
    local dayText = logfile and (tostring(day) .. "*") or tostring(day)

    lcd.drawText(x, yy, dayText, CUSTOM_COLOR + flags)

    col = col + 1
    if col > 7 then
      col = 1
      row = row + 1
    end
    day = day + 1
  end
end

---------------------------------------------------------------------
-- TOUCH HANDLING
---------------------------------------------------------------------

local function handleTouch(event, t)
  t = t or {}

  if event == EVT_TOUCH_SLIDE then
    if t.swipeLeft then changeMonth(1)
    elseif t.swipeRight then changeMonth(-1) end
    return
  end

  if event == EVT_TOUCH_TAP then
    local x = t.x or -1
    local y = t.y or -1
    local cellW = screenW // 7

    local title = string.format("%s %d", monthName(viewMonth), viewYear)
    local _, th = lcd.sizeText(title, MIDSIZE + BOLD)
    local yStart = HEADER_Y + th + HEADER_MARGIN + WEEKDAY_HEIGHT

    if y >= yStart - 4 then
      local row = math.floor((y - yStart) / CELL_HEIGHT)
      local col = math.floor(x / cellW)
      if row >= 0 and row < 6 and col >= 0 and col < 7 then
        local firstDow = weekday(viewYear, viewMonth, 1)
        local idx = row*7 + col + 1
        local d = idx - firstDow + 1
        if d >= 1 and d <= getMonthDays(viewYear, viewMonth) then
          selectedDay = d
        end
      end
    end
  end
end

---------------------------------------------------------------------
-- BUTTON / ROTARY HANDLING
---------------------------------------------------------------------

local function handlePopupInput(event)
  if event == EVT_EXIT_BREAK or event == EVT_ENTER_BREAK then
    popupActive = false
    return
  end

  if event == EVT_ROT_RIGHT then popupScroll = popupScroll + 1 end
  if event == EVT_ROT_LEFT then popupScroll = popupScroll - 1 end
  if popupScroll < 0 then popupScroll = 0 end
end

local function handleCalendarInput(event)
  if event == EVT_ROT_RIGHT then moveSelection(1)
  elseif event == EVT_ROT_LEFT then moveSelection(-1)
  elseif event == EVT_PAGEDN_FIRST or event == EVT_PAGEDN_LONG or event == EVT_PAGE_BREAK then
    changeMonth(1)
  elseif event == EVT_PAGEUP_FIRST or event == EVT_PAGEUP_LONG then
    changeMonth(-1)
  elseif event == EVT_ENTER_FIRST or event == EVT_ENTER_BREAK then
    if hasLog(selectedDay, viewMonth, viewYear) then
      openLogFile(selectedDay, viewMonth, viewYear)
      popupActive = true
    end
  end
end

---------------------------------------------------------------------
-- MAIN RUN FUNCTION
---------------------------------------------------------------------

local function run(event, touchState)
  if popupActive then
    handlePopupInput(event)
    drawCalendar()
    drawPopup()
    return 0
  end

  handleCalendarInput(event)

  if event ~= 0 then
    handleTouch(event, touchState)
  end

  drawCalendar()
  return 0
end

return { run = run }
