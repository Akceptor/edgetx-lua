local function init()
  swap_oldtime = getTime()
  swap_cycle = 0  -- 0 = normal, 1 = swapped
end

local function run()
  for i = 0, LED_STRIP_LENGTH - 1, 1 do
    if (i % 2 == swap_cycle) then
      -- Normal: first half blue, second half yellow
      if i <= 9 then
        setRGBLedColor(i, 0, 0, 255)    -- blue
      else
        setRGBLedColor(i, 255, 255, 0)  -- yellow
      end
    else
      -- Swapped: first half yellow, second half blue
      if i <= 9 then
        setRGBLedColor(i, 255, 255, 0)  -- yellow
      else
        setRGBLedColor(i, 0, 0, 255)    -- blue
      end
    end
  end

  if ((getTime() - swap_oldtime) > 20) then
    swap_oldtime = getTime()
    swap_cycle = 1 - swap_cycle
  end

  applyRGBLedColors()
end

local function background()
  -- Called periodically while the Special Function switch is off
end

return { run = run, background = background, init = init }