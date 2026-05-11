chdir("/SCRIPTS/BF")

protocol = assert(loadScript("protocols.lua"))()
radio = assert(loadScript("radios.lua"))().msp
assert(loadScript(protocol.mspTransport))()
assert(loadScript("MSP/common.lua"))()

local MSP_SET_NAME = 11

local ANIMATION_TEXT = "https://www.youtube.com/@Akceptor"
local NAME_MAX_LENGTH = 16
local DISPLAY_LENGTH = 10
local SCROLL_INTERVAL = 100 -- 1 second assuming getTime() resolution is 1/100 s
local WRITE_TIMEOUT = 200   -- 2 s — abandon a stuck write so we don't deadlock

local textLength = #ANIMATION_TEXT
local scrollIndex = 1
local lastScrollTime = 0
local pendingNameWrite = false
local pendingSentAt = 0

local function getScrollSegment()
    if textLength == 0 then
        return ""
    end
    local segment = string.sub(ANIMATION_TEXT, scrollIndex, scrollIndex + DISPLAY_LENGTH - 1)
    if #segment < DISPLAY_LENGTH then
        segment = segment .. string.sub(ANIMATION_TEXT, 1, DISPLAY_LENGTH - #segment)
    end
    return segment
end

local function buildNamePayload(name)
    local payload = {}
    for i = 1, NAME_MAX_LENGTH do
        payload[i] = string.byte(name, i) or 0
    end
    return payload
end

local function resetRollingState()
    scrollIndex = 1
    lastScrollTime = 0
    pendingNameWrite = false
    pendingSentAt = 0
end

local function sendNameUpdate(name)
    pendingNameWrite = true
    pendingSentAt = getTime()
    protocol.mspWrite(MSP_SET_NAME, buildNamePayload(name))
end

local function processReplies()
    while true do
        local cmd, _, _ = mspPollReply()
        if not cmd then
            break
        end
        if cmd == MSP_SET_NAME then
            pendingNameWrite = false
        end
    end
end

local function tickAnimation()
    if textLength == 0 then
        return
    end
    local now = getTime()
    if pendingNameWrite then
        if now - pendingSentAt >= WRITE_TIMEOUT then
            pendingNameWrite = false -- give up on a missing reply and move on
        else
            return
        end
    end
    if lastScrollTime == 0 then
        scrollIndex = 1
        lastScrollTime = now
        sendNameUpdate(getScrollSegment())
        return
    end
    if now - lastScrollTime >= SCROLL_INTERVAL then
        scrollIndex = (scrollIndex % textLength) + 1
        lastScrollTime = now
        sendNameUpdate(getScrollSegment())
    end
end

local function updateLogic()
    if getRSSI() > 0 then
        mspProcessTxQ()
        processReplies()
        tickAnimation()
    else
        resetRollingState()
    end
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
    resetRollingState()
end

return { run = run, background = background, init = init }
