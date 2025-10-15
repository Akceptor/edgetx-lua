local BLUE_R, BLUE_G, BLUE_B   = 0, 0, 255
local YELLOW_R, YELLOW_G, YELLOW_B = 255, 255, 0

-- Convert positive pot (0..+1024) → index 0..9
local function positiveIndex(value)
    if value < 0 then value = 0 end
    if value > 1024 then value = 1024 end
    -- Map to 0..9
    local idx = math.floor(value * 10 / 1025)
    if idx > 9 then idx = 9 end
    return idx
end

-- Convert negative pot (-1024..0) → index 9..0 (reverse order)
local function negativeIndex(value)
    if value > 0 then value = 0 end
    if value < -1024 then value = -1024 end
    -- Shift to 0..1024
    local pos = -value
    -- Map 0..1024 to 9..0
    local idx = math.floor(pos * 10 / 1025)
    if idx > 9 then idx = 9 end
    -- Reverse order
    return 9 - idx
end

-- Map full pot value (-1024..+1024) into (index, R, G, B)
local function mapPotToLEDandColor(value)
    if value >= 0 then
        local idx = positiveIndex(value)
        return idx, BLUE_R, BLUE_G, BLUE_B
    else
        local idx = negativeIndex(value)
        return idx, YELLOW_R, YELLOW_G, YELLOW_B
    end
end

local function init()
    -- NO-OP
end

local function run()
    -- S2 -> LEDs 0..9
    local v2 = -getValue("s2") -- MINUS FOR OPPOSITE DIRECTION
    local idx2, r2, g2, b2 = mapPotToLEDandColor(v2)
    for i = 0, 9 do
        if i == idx2 then
            setRGBLedColor(i, r2, g2, b2)
        else
            setRGBLedColor(i, 0, 0, 0)
        end
    end

    -- S1 -> LEDs 10..19
    local v1 = getValue("s1")
    local idx1, r1, g1, b1 = mapPotToLEDandColor(v1)
    for i = 10, 19 do
        if (i - 10) == idx1 then
            setRGBLedColor(i, r1, g1, b1)
        else
            setRGBLedColor(i, 0, 0, 0)
        end
    end

    applyRGBLedColors()
end

local function background()
    -- NO-OP
end

return { run=run, background=background, init=init }