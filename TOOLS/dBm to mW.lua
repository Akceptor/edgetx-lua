-- TNS| dBm <=> mW |TNE
local function init()
    xtarget = "mW"
    xsource = "dBm"
    inputval = 0
    outval = 1.00
end

local function log10(x)
    return math.log(x) / math.log(10)
end

local function convert()
    if xsource == "dBm" then
        return 10 ^ (inputval / 10)
    else
        return 10 * log10(inputval)
    end
end

local function run(event)
    lcd.clear()
    lcd.drawText (2, 20, inputval .. " " .. xsource .. " = " .. outval .. " " .. xtarget)
    lcd.drawText (2, 50, "SCROLL or ENTER")

    -- Process key presses
    if event == EVT_EXIT_BREAK then
        -- Just exit
    elseif event == EVT_ENTER_BREAK then
        if xsource=="dBm" then
            xsource="mW"
            xtarget="dBm"
            inputval = 1.00
            outval = 0
        else
            xsource="dBm"
            xtarget="mW"
            inputval = 0
            outval = 1.00
        end
    else
        -- look for +/- events
        local inc = 0
        if event == EVT_MINUS_FIRST or event == EVT_ROT_RIGHT or event == EVT_DOWN_FIRST then
            if xsource=="dBm" then
                inc = 0.1
            else
                inc = 10
            end
        elseif event == EVT_PLUS_FIRST or event == EVT_ROT_LEFT or event == EVT_UP_FIRST then
            if xsource=="dBm" then
                inc = -0.1
            else
                inc = -10
            end
        elseif event == EVT_VIRTUAL_PREVIOUS_PAGE then
            if xsource=="dBm" then
                inc = 1
            else
                inc = 100
            end
        elseif event == EVT_VIRTUAL_NEXT_PAGE then
            if xsource=="dBm" then
                inc = -1
            else
                inc = -100
            end
        end
        inputval = math.floor((inputval+inc) * 10 +0.5)/10
        outval = math.floor(convert()* 100 + 0.5) / 100
        lcd.clear()
        if xsource=="dBm" then
            lcd.drawText (2, 0, "Signal power, dBm")
        else 
            lcd.drawText (2, 0, "Signal power, mW")
        end
        lcd.drawText (2, 20, inputval .. " " .. xsource .. " = " .. outval .. " " .. xtarget)
        lcd.drawText (2, 50, "SCROLL or ENTER")
    end

    return 0
end

return {init=init, background=background, run=run}
