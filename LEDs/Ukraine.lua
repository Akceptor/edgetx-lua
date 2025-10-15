local function init()
  -- Called once when the script is loaded
end

local function run()
  for i = 0, LED_STRIP_LENGTH - 1 do
    if (i >= 1 and i <=5) then
      setRGBLedColor(i, 0, 0, 255)    -- blue
    elseif (i >= 6 and i <= 10) then
      setRGBLedColor(i, 255, 255, 0)  -- yellow
    elseif (i >= 11 and i <= 15) then
      setRGBLedColor(i, 255, 255, 0) -- yellow
    else
      setRGBLedColor(i, 0, 0, 255)  -- blue
    end
  end

  applyRGBLedColors()
end

local function background()
  -- Called periodically while the Special Function switch is off
end

return { run = run, background = background, init = init }