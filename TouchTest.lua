-- TouchTest.lua — event-driven PRESS/TAP indicators for TOOLS context

local pressActive = false
local tapUntil = 0
local lastEvent = 0
local lastEventAt = 0

local function evt2str(e)
  if e == EVT_TOUCH_FIRST then return "EVT_TOUCH_FIRST"
  elseif e == EVT_TOUCH_BREAK then return "EVT_TOUCH_BREAK"
  elseif e == EVT_TOUCH_TAP   then return "EVT_TOUCH_TAP"
  elseif e == EVT_TOUCH_SLIDE then return "EVT_TOUCH_SLIDE"
  elseif e == 0               then return "EVT_NONE"
  else return tostring(e)
  end
end

local function run(event, touchState)
  -- Read touch (if FW provides it)
  local touch = touchState
  if lcd and lcd.getTouchState then
    touch = touch or lcd.getTouchState()
  end

  -- Event-driven state machine
  if event ~= nil then
    if event ~= 0 then
      lastEvent   = event
      lastEventAt = getTime()

      if event == EVT_TOUCH_FIRST then
        pressActive = true                      -- finger down
      elseif event == EVT_TOUCH_BREAK then
        pressActive = false                     -- finger up (no slide)
      elseif event == EVT_TOUCH_TAP then
        -- short tap detected; show TAP=YES for 400 ms
        tapUntil = getTime() + 40               -- ~400 ms (10 ms per tick)
      end
    end
  end

  -- Derived indicators
  local now = getTime()
  local tapOn  = (now < tapUntil)
  local pressOn = pressActive                   -- stays true while finger held

  -- UI
  lcd.clear()
  lcd.drawText(10, 10, "Touch Test (TOOLS)", MIDSIZE)
  lcd.drawText(10, 34, "Tap screen / hold / swipe", SMLSIZE)

  -- Show coordinates if available
  if touch then
    local x = touch.x or -1
    local y = touch.y or -1
    local swipeL = touch.swipeLeft and "YES" or "NO"
    local swipeR = touch.swipeRight and "YES" or "NO"
    lcd.drawText(10, 64, string.format("x=%d  y=%d", x, y), SMLSIZE)
    lcd.drawText(10, 84, "Swipe L: "..swipeL.."   Swipe R: "..swipeR, SMLSIZE)
  else
    lcd.drawText(10, 64, "no touchState (ok in TOOLS)", SMLSIZE)
  end

  -- Event & indicators (from event codes)
  lcd.drawText(10, 108, "Last event: "..evt2str(lastEvent), SMLSIZE)
  if now - lastEventAt < 200 then
    lcd.drawText(220, 108, string.format("@%d", lastEventAt), SMLSIZE)
  end

  lcd.drawText(10, 132, "PRESS: "..(pressOn and "YES" or "NO"), MIDSIZE)
  lcd.drawText(10, 156, "TAP  : "..(tapOn  and "YES" or "NO"), MIDSIZE)

  return 0
end

return { run = run }