-- TNS|Calendar|TNE

local screenW = LCD_W
local screenH = LCD_H

local BG = lcd.RGB(240,240,240)  -- light grey background
local TEXT_BLACK = lcd.RGB(0,0,0)
local TODAY_BG = lcd.RGB(0,180,0)
local SELECT_BG = lcd.RGB(210,210,210)

local current = getDateTime()
local viewYear = current.year
local viewMonth = current.mon
local selectedDay = current.day

local HEADER_Y = 10
local HEADER_MARGIN = 8
local WEEKDAY_HEIGHT = 22
local CELL_HEIGHT = 20

local daysInMonth = { 31,28,31,30,31,30,31,31,30,31,30,31 }

local function isLeap(y)
  return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

local function getMonthDays(y,m)
  if m == 2 then return isLeap(y) and 29 or 28 end
  return daysInMonth[m]
end

-- Monday = 1 … Sunday = 7
local function weekday(y,m,d)
  if m < 3 then
    m = m + 12
    y = y - 1
  end
  local k = y % 100
  local j = math.floor(y / 100)
  local h = (d + math.floor((13*(m+1))/5) + k + math.floor(k/4) + math.floor(j/4) + 5*j) % 7
  local dow = ((h + 5) % 7) + 1
  return dow
end

local function monthName(m)
  local t = {
    "January","February","March","April","May","June",
    "July","August","September","October","November","December"
  }
  return t[m]
end

local function clampSelection()
  local mdays = getMonthDays(viewYear, viewMonth)
  if selectedDay > mdays then selectedDay = mdays end
  if selectedDay < 1 then selectedDay = 1 end
end

local function changeMonth(delta)
  viewMonth = viewMonth + delta
  if viewMonth < 1 then viewMonth = 12; viewYear = viewYear - 1 end
  if viewMonth > 12 then viewMonth = 1; viewYear = viewYear + 1 end
  if viewYear < 1970 then viewYear = 1970 end
  if viewYear > 2070 then viewYear = 2070 end
  clampSelection()
end

local function moveSelection(delta)
  selectedDay = selectedDay + delta
  clampSelection()
end

---------------------------------------------------------------
-- DRAW CALENDAR
---------------------------------------------------------------
local function drawCalendar()
  lcd.setColor(CUSTOM_COLOR, BG)
  lcd.drawFilledRectangle(0, 0, screenW, screenH, CUSTOM_COLOR)

  -- Header: Year + Month
  local title = string.format("%s %d", monthName(viewMonth), viewYear)
  local tw, th = lcd.sizeText(title, MIDSIZE + BOLD)
  lcd.setColor(CUSTOM_COLOR, TEXT_BLACK)
  lcd.drawText((screenW - tw) // 2, HEADER_Y, title, CUSTOM_COLOR + MIDSIZE + BOLD)

  -- Weekday headers
  local weekdays = {"Mon","Tue","Wed","Thu","Fri","Sat","Sun"}
  local cellW = screenW // 7
  local yStart = HEADER_Y + th + HEADER_MARGIN

  for i=1,7 do
    local color = (i >= 6) and lcd.RGB(200,0,0) or lcd.RGB(0,0,0)
    lcd.setColor(CUSTOM_COLOR, color)
    lcd.drawText((i-1)*cellW + 4, yStart, weekdays[i], CUSTOM_COLOR + BOLD)
  end

  local y = yStart + WEEKDAY_HEIGHT
  local year = viewYear
  local month = viewMonth

  local firstDow = weekday(year, month, 1)
  local mdays = getMonthDays(year, month)

  local today = getDateTime()
  local isTodayMonth = (today.year == year and today.mon == month)

  local day = 1
  local col = firstDow
  local row = 0

  while day <= mdays do
    local x = (col-1)*cellW + 4
    local yy = y + row*CELL_HEIGHT

    local isWeekend = (col >= 6)
    local textColor = isWeekend and lcd.RGB(200,0,0) or lcd.RGB(0,0,0)
    lcd.setColor(CUSTOM_COLOR, textColor)
    local flags = BOLD

    local boxX = x - 2
    local boxY = yy - 2
    local boxW = cellW - 4
    local boxH = 18
    local isToday = isTodayMonth and day == today.day
    local isSelected = day == selectedDay

    -- TODAY highlight
    if isToday then
      lcd.setColor(CUSTOM_COLOR, TODAY_BG)
      lcd.drawFilledRectangle(boxX, boxY, boxW, boxH, CUSTOM_COLOR)
      lcd.setColor(CUSTOM_COLOR, lcd.RGB(255,255,255))
    elseif isSelected then
      lcd.setColor(CUSTOM_COLOR, SELECT_BG)
      lcd.drawFilledRectangle(boxX, boxY, boxW, boxH, CUSTOM_COLOR)
      lcd.setColor(CUSTOM_COLOR, textColor)
    end

    if isSelected then
      lcd.drawRectangle(boxX-1, boxY-1, boxW+2, boxH+2, SOLID)
    end

    -----------------------------------------------------------
    -- CHECK FOR LOG FILE: /LOGS/DD_MM_YYYY.txt
    -----------------------------------------------------------
    local logPath = string.format("/LOGS/%02d_%02d_%04d.txt", day, month, year)
    local hasLog = false
    local ok, info = pcall(fstat, logPath)
    if ok and info then
      hasLog = true
    end

    -- Day text with optional "*"
    local displayDay = hasLog and (tostring(day) .. "*") or tostring(day)

    lcd.drawText(x, yy, displayDay, CUSTOM_COLOR + flags)

    col = col + 1
    if col > 7 then
      col = 1
      row = row + 1
    end

    day = day + 1
  end
end

---------------------------------------------------------------
-- TOUCH & ROTARY HANDLING
---------------------------------------------------------------
local function handleTouch(event, touchState)
  local t = touchState or {}

  if event == EVT_TOUCH_SLIDE then
    if t.swipeLeft then changeMonth(1)
    elseif t.swipeRight then changeMonth(-1) end

  elseif event == EVT_TOUCH_TAP then
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
        local idx = row * 7 + col + 1
        local day = idx - firstDow + 1
        local mdays = getMonthDays(viewYear, viewMonth)
        if day >= 1 and day <= mdays then
          selectedDay = day
        end
      end
    end
  end
end

---------------------------------------------------------------
-- MAIN RUN FUNCTION
---------------------------------------------------------------
local function run(event, touchState)
  if event and event ~= 0 then
    if event == EVT_ROT_RIGHT then moveSelection(1)
    elseif event == EVT_ROT_LEFT then moveSelection(-1)
    elseif event == EVT_PAGEDN_FIRST or event == EVT_PAGEDN_LONG or event == EVT_PAGE_BREAK then
      changeMonth(1)
    elseif event == EVT_PAGEUP_FIRST or event == EVT_PAGEUP_LONG then
      changeMonth(-1)
    end
    handleTouch(event, touchState)
  end

  drawCalendar()
  return 0
end

return { run = run }
