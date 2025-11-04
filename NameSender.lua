local toolName = "TNS|MSP Name Sender|TNE"

chdir("/SCRIPTS/BF")

apiVersion = 0

protocol = assert(loadScript("protocols.lua"))()
radio = assert(loadScript("radios.lua"))().msp
assert(loadScript(protocol.mspTransport))()
assert(loadScript("MSP/common.lua"))()

local MSP_API_VERSION = 1
local MSP_NAME = 10
local MSP_SET_NAME = 11
local MSP_EEPROM_WRITE = 250

local NAME_MAX_LENGTH = 16
local REQUEST_INTERVAL = 50
local STATUS_TIMEOUT = 400
local SCREEN_W = rawget(_G, "LCD_W") or 480
local BUTTON_WIDTH = 220
local BUTTON_HEIGHT = 44
local BUTTON_Y = 80
local BUTTON_SPACING = 12

local lastRequest = 0
local requestStage = 1

local apiVersionText
local craftNameText = ""
local pendingNameWrite
local pendingSaveWrite = false
local activeButtonId
local lastStatus
local lastStatusTime = 0

local function getRadioModelName()
    if model and model.getInfo then
        local info = model.getInfo()
        if info and info.name and info.name ~= "" then
            return info.name
        end
    end
    if model and model.getModelName then
        local name = model.getModelName()
        if name and name ~= "" then
            return name
        end
    end
end

local BUTTONS = {
    {
        id = "sendModelName",
        label = "Send Model Name",
        resolveName = function()
            return getRadioModelName()
        end,
        unavailableStatus = "Model name unavailable"
    },
    {
        id = "player1",
        label = "Player 1",
        resolveName = function()
            return "Player 1"
        end
    },
    {
        id = "player2",
        label = "Player 2",
        resolveName = function()
            return "Player 2"
        end
    }
}

for index, btn in ipairs(BUTTONS) do
    btn.w = BUTTON_WIDTH
    btn.h = BUTTON_HEIGHT
    btn.x = (SCREEN_W - BUTTON_WIDTH) // 2
    btn.y = BUTTON_Y + (index - 1) * (BUTTON_HEIGHT + BUTTON_SPACING)
end

local function setStatus(message)
    lastStatus = message
    lastStatusTime = getTime()
end

local function sendNameUpdate(name)
    local payload = {}
    for i = 1, NAME_MAX_LENGTH do
        payload[i] = string.byte(name, i) or 0
    end
    pendingNameWrite = name
    pendingSaveWrite = false
    setStatus("Updating name...")
    protocol.mspWrite(MSP_SET_NAME, payload)
    lastRequest = getTime()
end

local function scheduleRequests()
    if pendingNameWrite or pendingSaveWrite then
        return
    end
    local now = getTime()
    if lastRequest ~= 0 and now - lastRequest < REQUEST_INTERVAL then
        return
    end
    if requestStage == 1 then
        protocol.mspRead(MSP_API_VERSION)
    elseif requestStage == 2 then
        protocol.mspRead(MSP_NAME)
    else
        return
    end
    lastRequest = now
end

local function processReplies()
    while true do
        local cmd, payload, err = mspPollReply()
        if not cmd then
            break
        end
        if cmd == MSP_API_VERSION and not err and payload and #payload >= 3 then
            apiVersionText = string.format("%d.%02d", payload[2], payload[3])
            requestStage = 2
        elseif cmd == MSP_NAME and not err and payload then
            local name = {}
            for i = 1, #payload do
                local byte = payload[i]
                if byte == 0 then
                    break
                end
                name[#name + 1] = string.char(byte)
            end
            craftNameText = table.concat(name)
            requestStage = 3
        elseif cmd == MSP_SET_NAME then
            local requestedName = pendingNameWrite
            if err then
                setStatus("Name update failed")
                pendingSaveWrite = false
                activeButtonId = nil
            else
                if requestedName then
                    craftNameText = requestedName
                end
                requestStage = 2
                setStatus("Saving...")
                protocol.mspWrite(MSP_EEPROM_WRITE, {})
                pendingSaveWrite = true
                lastRequest = getTime()
            end
            pendingNameWrite = nil
        elseif cmd == MSP_EEPROM_WRITE then
            if err then
                setStatus("Save failed")
            else
                if craftNameText ~= "" then
                    setStatus("Name saved as " .. craftNameText)
                else
                    setStatus("Name saved")
                end
                requestStage = 2
            end
            pendingSaveWrite = false
            activeButtonId = nil
        end
    end
end

local function drawLine(y, label, value)
    lcd.drawText(10, y, label .. (value or "..."))
end

local function pointInButton(btn, x, y)
    return x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h)
end

local function activateButton(btn, telemetryReady)
    if not btn then
        return
    end
    if pendingNameWrite or pendingSaveWrite then
        setStatus("Update already in progress")
        return
    end
    if not telemetryReady then
        setStatus("Telemetry unavailable")
        return
    end
    local resolver = btn.resolveName
    local name = resolver and resolver() or btn.label
    if not name then
        if btn.unavailableStatus then
            setStatus(btn.unavailableStatus)
        else
            setStatus("Name unavailable")
        end
        return
    end
    activeButtonId = btn.id
    sendNameUpdate(name)
end

local function findButtonAt(x, y)
    for _, btn in ipairs(BUTTONS) do
        if pointInButton(btn, x, y) then
            return btn
        end
    end
end

local function handleInput(event, touchState, telemetryReady)
    if not event then
        return
    end
    if event == EVT_TOUCH_TAP then
        if touchState and touchState.x and touchState.y then
            local btn = findButtonAt(touchState.x, touchState.y)
            activateButton(btn, telemetryReady)
        end
    elseif event == EVT_ENTER_BREAK then
        activateButton(BUTTONS[1], telemetryReady)
    end
end

local function drawButton(btn, enabled, activeLabel)
    local label = activeLabel or btn.label
    lcd.drawRectangle(btn.x, btn.y, btn.w, btn.h)
    local flags = CENTER + MIDSIZE
    if not enabled then
        flags = flags + INVERS
    end
    lcd.drawText(btn.x + btn.w // 2, btn.y + (btn.h // 2) - 8, label, flags)
end

local function drawButtons(telemetryReady)
    local busy = pendingNameWrite or pendingSaveWrite
    local buttonsEnabled = telemetryReady and not busy
    for _, btn in ipairs(BUTTONS) do
        local label = btn.label
        if busy and activeButtonId == btn.id then
            label = pendingSaveWrite and "Saving..." or "Updating..."
        end
        local enabled = buttonsEnabled
        if not enabled and busy and activeButtonId == btn.id then
            enabled = true
        end
        drawButton(btn, enabled, label)
    end
end

local function run(event, touchState)
    local telemetryReady = getRSSI() > 0

    if event and event ~= 0 then
        handleInput(event, touchState, telemetryReady)
    end

    if not telemetryReady then
        apiVersionText = nil
        craftNameText = ""
        requestStage = 1
        lastRequest = 0
        pendingNameWrite = nil
        pendingSaveWrite = false
        activeButtonId = nil
    else
        scheduleRequests()
        mspProcessTxQ()
        processReplies()
    end

    lcd.clear()
    local title = "MSP Name Sender"
    if apiVersionText and apiVersionText ~= "" then
        title = title .. " " .. apiVersionText
    end
    lcd.drawText(1, 8, title, MIDSIZE)

    drawLine(26, "Name: ", craftNameText ~= "" and craftNameText or nil)

    drawButtons(telemetryReady)

    if lastStatus and lastStatusTime ~= 0 and getTime() - lastStatusTime < STATUS_TIMEOUT then
        lcd.drawText(10, 50, lastStatus, SMLSIZE)
    end

    return 0
end

return { run = run }
