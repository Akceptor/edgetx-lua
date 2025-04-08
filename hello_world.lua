-- Get screen dimensions
local screenWidth = LCD_W
local screenHeight = LCD_H

-- Function to run the script
local function run(event)
    -- Clear the screen
    lcd.clear()
    
    -- Calculate center position for the text
    local x = screenWidth / 2
    local y = screenHeight / 2
    
    -- Draw centered text
    lcd.drawText(x, y, "Hello World", CENTER + MIDSIZE)
    
    -- Return 0 to keep the script running
    return 0
end

-- Return the run function to EdgeTX
return { run=run } 
