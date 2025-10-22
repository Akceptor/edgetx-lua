protocol = assert(loadScript("protocols.lua"))()
radio = assert(loadScript("radios.lua"))().msp
assert(loadScript(protocol.mspTransport))()
assert(loadScript("MSP/common.lua"))()

local DEFAULT_TEXT = "https://www.youtube.com/@Akceptor"
local MSP_SET_NAME = 11

local SET_NAME_SWITCH = "se"
local SWITCH_THRESHOLD = 0
local NAME_MAX_LENGTH = 16
local DISPLAY_LENGTH = 16
local SCROLL_INTERVAL = 100 -- 1 second assuming getTime() resolution is 1/100 s

local switchWasOn = false
local scrollIndex = 1
local lastScrollTime = 0
local configuredText = DEFAULT_TEXT
local textLength = #configuredText

local function getScrollSegment()
    if textLength == 0 then
        return ""
    end
    local segment = string.sub(configuredText, scrollIndex, scrollIndex + DISPLAY_LENGTH - 1)
    if #segment < DISPLAY_LENGTH then
        segment = segment .. string.sub(configuredText, 1, DISPLAY_LENGTH - #segment)
    end
    return segment
end

local function sendNameUpdate(name)
    local payload = {}
    for i = 1, NAME_MAX_LENGTH do
        payload[i] = string.byte(name, i) or 0
    end
    protocol.mspWrite(MSP_SET_NAME, payload)
end

-- TODO: FOR SOME REASON IT DOESN'T WORK
local function readCraftName() 
    local FILE = "/SCRIPTS/DATA/craftName.txt"

    local f, err = io.open(FILE, "r")
    if not f then
        return "ERR: No file"
    end

    local content = f:read("*a")
    f:close()

    if not content then
        return "ERR: No data"
    end

    content = content:gsub("[\r\n]+", "")
    if #content == 0 then
        return "ERR: Empty file"
    end

    return content
end


local function handleSwitch(telemetryReady)
    if textLength == 0 then
        switchWasOn = false
        return
    end
    local switchValue = getValue(SET_NAME_SWITCH)
    local switchOn = switchValue and (switchValue > SWITCH_THRESHOLD)
    local now = getTime()
    if telemetryReady and switchOn then
        if not switchWasOn then
            scrollIndex = 1
            lastScrollTime = now
            sendNameUpdate(getScrollSegment())
        elseif now - lastScrollTime >= SCROLL_INTERVAL then
            scrollIndex = (scrollIndex % textLength) + 1
            lastScrollTime = now
            sendNameUpdate(getScrollSegment())
        end
    elseif not telemetryReady then
        scrollIndex = 1
        lastScrollTime = 0
    end
    switchWasOn = telemetryReady and switchOn
end

local function updateLogic()
    local telemetryReady = getRSSI() > 0
    if telemetryReady then
        mspProcessTxQ()
    else
        switchWasOn = false
    end
    handleSwitch(telemetryReady)
end

local function run(event)
    updateLogic()
    return 0
end

local function background()
    updateLogic()
    return 0
end

local function init()
    switchWasOn = false
    scrollIndex = 1
    lastScrollTime = 0
end

return { run = run, background = background, init = init}
