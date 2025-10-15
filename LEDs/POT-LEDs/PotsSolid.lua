-- Convert pot value (-1024..+1024) into LED index 0..9
local function potToIndex(value)
    if value < -1024 then value = -1024 end
    if value >  1024 then value =  1024 end

    local idx = math.floor((value + 1024) * 10 / 2048)

    if idx < 0 then idx = 0 end
    if idx > 9 then idx = 9 end

    return idx
end

local function init()
    -- NO-OP
end

local function run()
    local p1 = getValue("s1")   -- will control LEDs 10..19
    local p2 = getValue("s2")   -- will control LEDs 0..9

    -- Convert to LED index 0..9
    local idx1 = potToIndex(p1)
    local idx2 = potToIndex(p2)

    -- ===== Right: LEDs 0..9 (S2) =====
    for i = 0, 9 do
        if i == idx2 then
            setRGBLedColor(i, 0, 255, 0)  -- GREEN
        else
            setRGBLedColor(i, 0, 0, 0)    -- OFF
        end
    end

    -- ===== Left: LEDs 10..19 (S1) =====
    for i = 10, 19 do
        if (i - 10) == idx1 then
            setRGBLedColor(i, 0, 255, 0)  -- GREEN
        else
            setRGBLedColor(i, 0, 0, 0)    -- OFF
        end
    end

    applyRGBLedColors()
end

local function background()
    -- NO-OP
end

return { run=run, background=background, init=init }