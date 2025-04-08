-- Get screen dimensions
local screenWidth = LCD_W
local screenHeight = LCD_H
local colWidth = 20  -- Width per column for frequency display

-- Channel data
local channels = {
    { name = "A1", freq = 5865 },
    { name = "A2", freq = 5845 },
    { name = "A3", freq = 5825 },
    { name = "A4", freq = 5805 },
    { name = "A5", freq = 5785 },
    { name = "A6", freq = 5765 },
    { name = "A7", freq = 5745 },
    { name = "A8", freq = 5725 },

    { name = "B1", freq = 5733 },
    { name = "B2", freq = 5752 },
    { name = "B3", freq = 5771 },
    { name = "B4", freq = 5790 },
    { name = "B5", freq = 5809 },
    { name = "B6", freq = 5828 },
    { name = "B7", freq = 5847 },
    { name = "B8", freq = 5866 },

    { name = "E1", freq = 5705 },
    { name = "E2", freq = 5685 },
    { name = "E3", freq = 5665 },
    { name = "E4", freq = 5645 },
    { name = "E5", freq = 5885 },
    { name = "E6", freq = 5905 },
    { name = "E7", freq = 5925 },
    { name = "E8", freq = 5945 },

    { name = "F1", freq = 5740 },
    { name = "F2", freq = 5760 },
    { name = "F3", freq = 5780 },
    { name = "F4", freq = 5800 },
    { name = "F5", freq = 5820 },
    { name = "F6", freq = 5840 },
    { name = "F7", freq = 5860 },
    { name = "F8", freq = 5880 },

    { name = "R1", freq = 5658 },
    { name = "R2", freq = 5695 },
    { name = "R3", freq = 5732 },
    { name = "R4", freq = 5769 },
    { name = "R5", freq = 5806 },
    { name = "R6", freq = 5843 },
    { name = "R7", freq = 5880 },
    { name = "R8", freq = 5917 },

    { name = "L1", freq = 5362 },
    { name = "L2", freq = 5399 },
    { name = "L3", freq = 5436 },
    { name = "L4", freq = 5473 },
    { name = "L5", freq = 5510 },
    { name = "L6", freq = 5547 },
    { name = "L7", freq = 5584 },
    { name = "L8", freq = 5621 },

    { name = "X1", freq = 4990 },
    { name = "X2", freq = 5020 },
    { name = "X3", freq = 5050 },
    { name = "X4", freq = 5080 },
    { name = "X5", freq = 5110 },
    { name = "X6", freq = 5140 },
    { name = "X7", freq = 5170 },
    { name = "X8", freq = 5200 },

    { name = "3.3 GHz A1", freq = 3330 },
    { name = "3.3 GHz A2", freq = 3350 },
    { name = "3.3 GHz A3", freq = 3370 },
    { name = "3.3 GHz A4", freq = 3390 },
    { name = "3.3 GHz A5", freq = 3410 },
    { name = "3.3 GHz A6", freq = 3430 },
    { name = "3.3 GHz A7", freq = 3450 },
    { name = "3.3 GHz A8", freq = 3470 },

    { name = "3.3 GHz B1", freq = 3170 },
    { name = "3.3 GHz B2", freq = 3190 },
    { name = "3.3 GHz B3", freq = 3210 },
    { name = "3.3 GHz B4", freq = 3230 },
    { name = "3.3 GHz B5", freq = 3250 },
    { name = "3.3 GHz B6", freq = 3270 },
    { name = "3.3 GHz B7", freq = 3290 },
    { name = "3.3 GHz B8", freq = 3310 },

    { name = "1.2 GHz A1", freq = 1080 },
    { name = "1.2 GHz A2", freq = 1120 },
    { name = "1.2 GHz A3", freq = 1160 },
    { name = "1.2 GHz A4", freq = 1200 },
    { name = "1.2 GHz A5", freq = 1240 },
    { name = "1.2 GHz A6", freq = 1280 },
    { name = "1.2 GHz A7", freq = 1320 },
    { name = "1.2 GHz A8", freq = 1360 },

    { name = "1.2 GHz B1", freq = 1200 },
    { name = "1.2 GHz B2", freq = 1220 },
    { name = "1.2 GHz B3", freq = 1240 },
    { name = "1.2 GHz B4", freq = 1258 },
    { name = "1.2 GHz B5", freq = 1280 },
    { name = "1.2 GHz B6", freq = 1300 },
    { name = "1.2 GHz B7", freq = 1320 },
    { name = "1.2 GHz B8", freq = 1340 }
}

-- Menu options
local menuOptions = {
    "FPV 5.8 GHz",
    "FPV 3.3 GHz",
    "FPV 1.2 GHz"
}

-- Menu state
local selectedBand = 1
local showChannels = false  -- New state variable to track if we're showing channels
local scrollPosition = 0    -- Track horizontal scroll position in table view

-- Function to clean channel name
local function cleanChannelName(name)
    -- Extract the letter and number from the channel name
    local letter, number = string.match(name, "([A-Z])(%d+)")
    if letter and number then
        return letter .. number
    end
    return name
end

-- Function to filter channels by band
local function getChannelsForBand(band)
    local filtered = {}
    local prefix = ""
    
    if band == 1 then
        prefix = ""  -- 5GHz channels don't have a prefix
    elseif band == 2 then
        prefix = "3.3 GHz"  -- 3.3 GHz prefix
    elseif band == 3 then
        prefix = "1.2 GHz"  -- 1.2 GHz prefix
    end
    
    for i = 1, #channels do
        local channel = channels[i]
        if type(channel) == "table" then
            local name = channel.name
            if name then
                if band == 1 then
                    -- For 5GHz, exclude channels with prefixes
                    if not string.find(name, "GHz") then
                        filtered[#filtered + 1] = channel
                    end
                else
                    -- For other bands, include only channels with matching prefix
                    if string.find(name, prefix) then
                        -- Extract the band letter (A or B) from the channel name
                        local letter = string.match(name, prefix .. " ([AB])")
                        if letter then
                            -- Create a new channel entry with just the letter and number
                            filtered[#filtered + 1] = {
                                name = letter .. string.match(name, "(%d+)$"),
                                freq = channel.freq
                            }
                        end
                    end
                end
            end
        end
    end
    
    return filtered
end

-- Main function
local function run(event)
    -- Clear screen
    lcd.clear()
    
    -- Handle menu navigation and confirmation
    if event == EVT_ENTER_BREAK then
        showChannels = not showChannels  -- Toggle between menu and channel view
        scrollPosition = 0  -- Reset scroll position when toggling views
    elseif event == EVT_EXIT_BREAK then
        showChannels = false  -- Always go back to menu view
        scrollPosition = 0  -- Reset scroll position when going back to menu
    elseif showChannels then  -- Handle scrolling in table view
        -- Calculate maximum scroll position
        local maxFreqs = math.floor((screenWidth - 10) / colWidth)
        local maxScroll = math.max(0, math.ceil(8 / maxFreqs) - 1)  -- Calculate pages needed and subtract 1 for zero-based index
        
        if event == EVT_ROT_RIGHT or event == EVT_DOWN_FIRST then
            scrollPosition = scrollPosition + 1
            if scrollPosition > maxScroll then
                scrollPosition = maxScroll
            end
        elseif event == EVT_ROT_LEFT or event == EVT_UP_FIRST then
            scrollPosition = scrollPosition - 1
            if scrollPosition < 0 then
                scrollPosition = 0
            end
        end
    elseif not showChannels then  -- Handle navigation in menu mode
        if event == EVT_MINUS_FIRST or event == EVT_ROT_RIGHT or event == EVT_DOWN_FIRST then
            selectedBand = selectedBand + 1
            if selectedBand > #menuOptions then
                selectedBand = 1
            end
        elseif event == EVT_PLUS_FIRST or event == EVT_ROT_LEFT or event == EVT_UP_FIRST then
            selectedBand = selectedBand - 1
            if selectedBand < 1 then
                selectedBand = #menuOptions
            end
        end
    end
    
    if showChannels then
        -- Get channels for selected band
        local bandChannels = getChannelsForBand(selectedBand)
        
        -- Group channels by band letter
        local channelGroups = {}
        local letters = {}  -- Keep track of letters in order they appear
        for i = 1, #bandChannels do
            local channel = bandChannels[i]
            local letter = string.match(channel.name, "([A-Z])")
            if letter then
                if not channelGroups[letter] then
                    channelGroups[letter] = {}
                    letters[#letters + 1] = letter  -- Add letter to ordered list
                end
                channelGroups[letter][#channelGroups[letter] + 1] = channel
            end
        end
        
        -- Display channels in table format
        local y = 0  -- Start at top
        local x = 0  -- Start at left edge
        local rowHeight = 8  -- Minimum possible height
        
        -- Calculate how many frequencies can fit on one line
        local maxFreqs = math.floor((screenWidth - 10) / colWidth)
        local startFreq = scrollPosition * maxFreqs + 1
        local endFreq = math.min(startFreq + maxFreqs - 1, 8)  -- Max 8 channels
        
        -- Show channel numbers at the top
        local headerLine = ""  -- Start with two spaces for the band letter column
        for i = startFreq, endFreq do
            headerLine = headerLine .. string.format("%7d", i)  -- Increased width to 6 to better align with frequencies
        end
        lcd.drawText(x, y, headerLine, SMLSIZE)
        y = y + rowHeight
        
        -- Display each band's channels in the order they appear
        for i = 1, #letters do
            local letter = letters[i]
            local channels = channelGroups[letter]
            local line = letter .. " "  -- Single space after letter
            
            -- Add frequencies to the line with minimal spacing
            for j = startFreq, endFreq do
                line = line .. string.format("%5d", channels[j].freq)  -- Keep frequency width at 5
            end
            
            lcd.drawText(x, y, line, SMLSIZE)
            y = y + rowHeight
        end
    else
        -- Draw menu options
        local y = 5
        for i = 1, #menuOptions do
            local option = menuOptions[i]
            if i == selectedBand then
                lcd.drawText(5, y, ">" .. option, MIDSIZE)
            else
                lcd.drawText(5, y, " " .. option, MIDSIZE)
            end
            y = y + 20
        end
    end
    
    return 0
end

-- Return the run function to EdgeTX
return { run=run } 