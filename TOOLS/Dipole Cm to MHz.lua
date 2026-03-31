-- TNS| Dipole mm <=> MHz |TNE

local function dipole_antenna_length_cm(frequency_mhz)
    -- Calculate the dipole length in centimeters
    local length_cm = 143000 / frequency_mhz
    return length_cm/2
end

local function frequency_from_length_cm(length_cm)
    -- Calculate the frequency in megahertz
    local frequency_mhz = 143000 / (length_cm * 2)
    return frequency_mhz
end

local function convert()
    if xtarget == "MHz" then 
        return frequency_from_length_cm(inputval)
    else
        return dipole_antenna_length_cm(inputval)
    end
end

local function init()
    xtarget = "mm"
    xsource = "MHz"
    inputval = 915 -- common case
    outval = convert()
end

local function run(event)
    lcd.clear()
    lcd.drawText (2, 20, inputval .. " " .. xsource .. " => " .. outval .. " " .. xtarget)
        if xsource=="mm" then
            lcd.drawText (2, 0, "Antenna half length, mm")
        else 
            lcd.drawText (2, 0, "Receiver frequency, MHz")
        end
        lcd.drawText (2, 50, "SCROLL or ENTER")

    -- Process key presses
    if event == EVT_EXIT_BREAK then
        -- Just exit
    elseif event == EVT_ENTER_BREAK then
        if xsource=="mm" then
            xsource="MHz"
            xtarget="mm"
            inputval = 915 -- common case
            outval = convert()
        else
            xsource="mm"
            xtarget="MHz"
            inputval = 102 -- common case
            outval = convert()
        end
    else
        -- look for +/- events
        local inc = 0
        if event == EVT_MINUS_FIRST or event == EVT_ROT_RIGHT or event == EVT_DOWN_FIRST then
                inc = 1
        elseif event == EVT_PLUS_FIRST or event == EVT_ROT_LEFT or event == EVT_UP_FIRST then
                inc = -1
        elseif event == EVT_VIRTUAL_NEXT_PAGE then
            inc = 10
        elseif event == EVT_VIRTUAL_PREVIOUS_PAGE then
            inc = -10
        end
        inputval = inputval+inc
        outval = math.floor(convert())
        lcd.clear()
        lcd.drawText (2, 20, inputval .. " " .. xsource .. " => " .. outval .. " " .. xtarget)
        if xsource=="mm" then
            lcd.drawText (2, 0, "Antenna half length, mm")
        else 
            lcd.drawText (2, 0, "Receiver frequency, MHz")
        end
        lcd.drawText (2, 50, "SCROLL or ENTER")
    end

    return 0
end

return {init=init, background=background, run=run}
