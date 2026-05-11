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

local ANIMATION_TEXT = "https://www.youtube.com/@Akceptor"
local ANIMATION_DISPLAY_LENGTH = 10
local ANIMATION_SCROLL_INTERVAL = 100 -- 1 second at getTime() resolution of 1/100s

local lastRequest = 0
local requestStage = 1

local apiVersionText
local craftNameText = ""
local pendingNameWrite
local pendingSaveWrite = false
local pendingRefreshWrite = false
local pendingAnimationWrite = false
local animationActive = false
local animationScrollIndex = 1
local animationLastScrollTime = 0
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
        action = "sendName",
        resolveName = function()
            return getRadioModelName()
        end,
        unavailableStatus = "Model name unavailable"
    },
    {
        id = "player1",
        label = "Player 1",
        action = "sendName",
        resolveName = function()
            return "Player 1"
        end
    },
    {
        id = "player2",
        label = "Player 2",
        action = "sendName",
        resolveName = function()
            return "Player 2"
        end
    },
    {
        id = "animation",
        label = "Animation",
        action = "toggleAnimation"
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

local function buildNamePayload(name)
    local payload = {}
    for i = 1, NAME_MAX_LENGTH do
        payload[i] = string.byte(name, i) or 0
    end
    return payload
end

local function getAnimationSegment()
    local textLen = #ANIMATION_TEXT
    if textLen == 0 then
        return ""
    end
    local segment = string.sub(ANIMATION_TEXT, animationScrollIndex, animationScrollIndex + ANIMATION_DISPLAY_LENGTH - 1)
    if #segment < ANIMATION_DISPLAY_LENGTH then
        segment = segment .. string.sub(ANIMATION_TEXT, 1, ANIMATION_DISPLAY_LENGTH - #segment)
    end
    return segment
end

local function sendAnimationFrame()
    local segment = getAnimationSegment()
    pendingAnimationWrite = true
    craftNameText = segment
    protocol.mspWrite(MSP_SET_NAME, buildNamePayload(segment))
    lastRequest = getTime()
end

local function startAnimation()
    animationActive = true
    animationScrollIndex = 1
    animationLastScrollTime = getTime()
    setStatus("Animation running")
    sendAnimationFrame()
end

local function stopAnimation()
    animationActive = false
    pendingAnimationWrite = false
    setStatus("Animation stopped")
end

local function tickAnimation()
    if not animationActive or pendingAnimationWrite then
        return
    end
    local now = getTime()
    if now - animationLastScrollTime >= ANIMATION_SCROLL_INTERVAL then
        animationScrollIndex = (animationScrollIndex % #ANIMATION_TEXT) + 1
        animationLastScrollTime = now
        sendAnimationFrame()
    end
end

local function sendNameUpdate(name)
    pendingNameWrite = name
    pendingSaveWrite = false
    pendingRefreshWrite = false
    setStatus("Updating name...")
    protocol.mspWrite(MSP_SET_NAME, buildNamePayload(name))
    lastRequest = getTime()
end

local function sendNameRefresh(name)
    if not name or name == "" then
        return
    end
    pendingRefreshWrite = true
    protocol.mspWrite(MSP_SET_NAME, buildNamePayload(name))
    lastRequest = getTime()
end

local function scheduleRequests()
    if pendingNameWrite or pendingSaveWrite or pendingRefreshWrite or animationActive then
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
            if pendingAnimationWrite then
                pendingAnimationWrite = false
            elseif pendingRefreshWrite then
                -- Second SET_NAME after EEPROM_WRITE; sole purpose is to
                -- force osdAnalyzeActiveElements() so the OSD repaints.
                pendingRefreshWrite = false
                activeButtonId = nil
                requestStage = 2
            else
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
            end
        elseif cmd == MSP_EEPROM_WRITE then
            if err then
                setStatus("Save failed")
                pendingSaveWrite = false
                activeButtonId = nil
            else
                if craftNameText ~= "" then
                    setStatus("Name saved as " .. craftNameText)
                else
                    setStatus("Name saved")
                end
                requestStage = 2
                pendingSaveWrite = false
                sendNameRefresh(craftNameText)
            end
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
    if not telemetryReady then
        setStatus("Telemetry unavailable")
        return
    end
    if btn.action == "toggleAnimation" then
        if pendingNameWrite or pendingSaveWrite or pendingRefreshWrite then
            setStatus("Update already in progress")
            return
        end
        if animationActive then
            stopAnimation()
            activeButtonId = nil
        else
            activeButtonId = btn.id
            startAnimation()
        end
        return
    end
    if animationActive then
        stopAnimation()
    end
    if pendingNameWrite or pendingSaveWrite or pendingRefreshWrite then
        setStatus("Update already in progress")
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
    local busy = pendingNameWrite or pendingSaveWrite or pendingRefreshWrite
    for _, btn in ipairs(BUTTONS) do
        local label = btn.label
        local enabled = telemetryReady and not busy
        if btn.action == "toggleAnimation" then
            if animationActive then
                label = "Stop Animation"
                enabled = telemetryReady
            end
        elseif busy and activeButtonId == btn.id then
            if pendingSaveWrite then
                label = "Saving..."
            elseif pendingRefreshWrite then
                label = "Refreshing..."
            else
                label = "Updating..."
            end
        end
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
        pendingRefreshWrite = false
        pendingAnimationWrite = false
        animationActive = false
        activeButtonId = nil
    else
        scheduleRequests()
        tickAnimation()
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
