local function init()
  swap_oldtime = getTime()
  swap_cycle = 0  -- 0 = normal, 1 = swapped
end

local function run()
  for i = 0, LED_STRIP_LENGTH - 1 do
    if swap_cycle == 0 then
      -- Normal colors
      if (i >= 1 and i <= 5) then
        setRGBLedColor(i, 0, 0, 255)    -- blue
      elseif (i >= 6 and i <= 15) then
        setRGBLedColor(i, 255, 255, 0)  -- yellow
      else
        setRGBLedColor(i, 0, 0, 255)    -- blue
      end
    else
        setRGBLedColor(i, 0, 0, 0)  -- black/off
    end
  end

  -- Toggle every 25 ticks (adjust for blink speed)
  if (getTime() - swap_oldtime) > 25 then
    swap_oldtime = getTime()
    swap_cycle = 1 - swap_cycle
  end

  applyRGBLedColors()
end

local function background()
  -- Called periodically while the Special Function switch is off
end

return { run = run, background = background, init = init }