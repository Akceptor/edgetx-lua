-- TNS|Video Channel Calculator|TNE
-- FPV Video Channel Distribution Calculator

local ranges = { "A", "B", "E", "F", "R", "L" }
local includeXBand = false
local userSelected, calculated = {}, {}
local pilots = 2
local popupTimer, popupMsg = 0, nil

-- detect color screen (TX16S, TX15, Boxer MAX)
local COLOR = (LCD_W >= 320 and LCD_H >= 200)

----------------------------------------------------------------
-- Frequency data {ch, freq}
----------------------------------------------------------------
local channelsData = {
    A = { {1,5865},{2,5845},{3,5825},{4,5805},{5,5785},{6,5765},{7,5745},{8,5725} },
    B = { {1,5733},{2,5752},{3,5771},{4,5790},{5,5809},{6,5828},{7,5847},{8,5866} },
    E = { {1,5705},{2,5685},{3,5665},{4,5645},{5,5885},{6,5905},{7,5925},{8,5945} },
    F = { {1,5740},{2,5760},{3,5780},{4,5800},{5,5820},{6,5840},{7,5860},{8,5880} },
    R = { {1,5658},{2,5695},{3,5732},{4,5769},{5,5806},{6,5843},{7,5880},{8,5917} },
    L = { {1,5362},{2,5399},{3,5436},{4,5473},{5,5510},{6,5547},{7,5584},{8,5621} },
    X = { {1,4990},{2,5020},{3,5050},{4,5080},{5,5110},{6,5140},{7,5170},{8,5200} }
}

----------------------------------------------------------------
-- Helpers (no table.* API for compatibility with BnW radios)
----------------------------------------------------------------
local function add(t, v) t[#t + 1] = v end
local function removeAt(t, i)
    for k = i, #t - 1 do t[k] = t[k + 1] end
    t[#t] = nil
end

local function populateRanges()
    local active = { "A", "B", "E", "F", "R", "L" }
    if includeXBand then active[#active + 1] = "X" end
    return active
end

local function calcDistance(a, b)
    local d = a[3] - b[3]
    return d < 0 and -d or d
end

local function findBestNext(all, current)
    local best, maxMin = nil, -1
    for i = 1, #all do
        local c = all[i]
        local minD = 99999
        for j = 1, #current do
            local d = calcDistance(c, current[j])
            if d < minD then minD = d end
        end
        if minD > maxMin then best, maxMin = c, minD end
    end
    return best
end

local function calculate()
    local activeRanges = populateRanges()
    local all = {}
    for i = 1, #activeRanges do
        local r = activeRanges[i]
        for j = 1, #channelsData[r] do
            local ch = channelsData[r][j]
            add(all, { r, ch[1], ch[2] })
        end
    end

    -- remove selected from pool
    for i = #all, 1, -1 do
        local a = all[i]
        for j = 1, #userSelected do
            local u = userSelected[j]
            if a[1] == u[1] and a[2] == u[2] then removeAt(all, i) break end
        end
    end

    calculated = {}
    for i = 1, #userSelected do calculated[i] = userSelected[i] end

    local maxPilots = math.min(6, math.max(pilots, #userSelected))
    while #calculated < maxPilots do
        local nxt = findBestNext(all, calculated)
        if not nxt then break end
        add(calculated, nxt)
        for k = 1, #all do
            if all[k] == nxt then removeAt(all, k) break end
        end
    end
end

----------------------------------------------------------------
-- Visualization (for color radios)
----------------------------------------------------------------
local function drawVisualization(list)
    if not COLOR or #list == 0 then return end

    local cx, cy = LCD_W // 2, (LCD_H // 2) + 45
    local radius = 85
    local vertexCount = 5
    local angleStep = (2 * math.pi) / vertexCount

    local verts = {}
    for i = 1, vertexCount do
        local angle = -math.pi / 2 + (i - 1) * angleStep
        verts[i] = {
            x = cx + math.cos(angle) * radius,
            y = cy + math.sin(angle) * radius,
            data = list[i + 1]
        }
    end

    -- center point
    if list[1] then
        lcd.setColor(CUSTOM_COLOR, lcd.RGB(0, 200, 100))
        lcd.drawFilledCircle(cx, cy, 9, CUSTOM_COLOR)
        lcd.drawText(cx - 10, cy - 26, string.format("%s%d", list[1][1], list[1][2]), SMLSIZE + INVERS)
    end

    -- draw edges between vertices
    for i = 1, vertexCount do
        local v1, v2 = verts[i], verts[(i % vertexCount) + 1]
        local c1, c2 = v1.data, v2.data
        local color = (c1 and c2) and lcd.RGB(255, 180, 0) or lcd.RGB(80, 80, 80)
        lcd.setColor(CUSTOM_COLOR, color)
        lcd.drawLine(v1.x, v1.y, v2.x, v2.y, SOLID, CUSTOM_COLOR)
        if c1 and c2 then
            local midx, midy = (v1.x + v2.x) / 2, (v1.y + v2.y) / 2
            local df = math.abs(c1[3] - c2[3])
            lcd.drawText(midx - 16, midy - 5, string.format("%d MHz", df), SMLSIZE)
        end
    end

    -- draw center connections
    for i = 1, vertexCount do
        local v = verts[i]
        local c = v.data
        local color = c and lcd.RGB(255, 150, 0) or lcd.RGB(100, 100, 100)
        lcd.setColor(CUSTOM_COLOR, color)
        lcd.drawLine(cx, cy, v.x, v.y, SOLID, CUSTOM_COLOR)
        if c and list[1] then
            local df = math.abs(c[3] - list[1][3])
            lcd.drawText((cx + v.x) / 2 - 16, (cy + v.y) / 2 - 5, string.format("%d MHz", df), SMLSIZE)
        end
    end

    -- draw vertex points
    for i = 1, vertexCount do
        local v = verts[i]
        if v.data then
            lcd.setColor(CUSTOM_COLOR, lcd.RGB(0, 120, 255))
            lcd.drawFilledCircle(v.x, v.y, 7, CUSTOM_COLOR)
            lcd.drawText(v.x - 8, v.y - 18, string.format("%s%d", v.data[1], v.data[2]), SMLSIZE)
        else
            lcd.setColor(CUSTOM_COLOR, lcd.RGB(100, 100, 100))
            lcd.drawFilledCircle(v.x, v.y, 6, CUSTOM_COLOR)
        end
    end
end

----------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------
local page, selRangeIdx, selChanIdx, editIndex = 1, 1, 1, 1
local editLabels = {"Band:", "Channel:", "Pilots:", "Include X:", "[Calculate]", "[Info]"}
local infoPage = false

local function drawChannels(list, y0)
    local colW = LCD_W // 2
    local x1, x2 = 5, colW + 5
    local rowH = COLOR and 14 or 10
    for i = 1, #list do
        local c = list[i]
        local col = (i - 1) % 2
        local row = (i - 1) // 2
        local x = (col == 0) and x1 or x2
        local y = y0 + row * rowH
        lcd.drawText(x, y, string.format("%s%d", c[1], c[2]))
        lcd.drawText(x + 40, y, string.format("%d", c[3]))
    end
end

local function drawFooter()
    local yFooter = LCD_H - (COLOR and 22 or 14)
    lcd.drawText(4, yFooter, "[PAGE>] [<] field  [SCROLL] val", SMLSIZE)
    lcd.drawText(4, yFooter + (COLOR and 10 or 8), "[ENT] add/remove  [RTN] back", SMLSIZE)
end

local function drawPopup()
    if popupMsg and getTime() < popupTimer then
        local boxW, boxH = 160, 80
        local x = (LCD_W - boxW) // 2
        local y = (LCD_H - boxH) // 2
        lcd.drawFilledRectangle(x, y, boxW, boxH, SOLID)
        lcd.drawRectangle(x, y, boxW, boxH, SOLID)
        lcd.drawText(x + 20, y + 25, popupMsg, INVERS)
    end
end

local function drawInfoPage()
    lcd.clear()
    lcd.drawFilledRectangle(0, 0, LCD_W, 40, SOLID)
    lcd.drawText((LCD_W - 160) // 2, 8, "Information", MIDSIZE + INVERS)

    if COLOR then
        local margin = 20
        local textY = 60
        lcd.drawText(margin, textY, "Utility that helps 'split'", MIDSIZE)
        lcd.drawText(margin, textY + 26, "video channels between", MIDSIZE)
        lcd.drawText(margin, textY + 52, "several pilots flying", MIDSIZE)
        lcd.drawText(margin, textY + 78, "simultaneously.", MIDSIZE)
        lcd.drawText(margin, textY + 110, "Finds most distant", MIDSIZE)
        lcd.drawText(margin, textY + 136, "channels by frequency", MIDSIZE)
        lcd.drawText(margin, textY + 162, "and maximizes spacing.", MIDSIZE)
        lcd.drawText(margin, textY + 200, "Based on vtx.in.ua/ch/", MIDSIZE)
        lcd.drawText(40, LCD_H - 26, "[ENTER] or [BACK] to close", SMLSIZE)
    else
        local margin = 10
        local textY = 50
        lcd.drawText(margin, textY, "Utility that helps 'split' channels", SMLSIZE)
        lcd.drawText(margin, textY + 12, "between several pilots flying", SMLSIZE)
        lcd.drawText(margin, textY + 24, "simultaneously. It finds channels", SMLSIZE)
        lcd.drawText(margin, textY + 36, "most distant by frequency, and", SMLSIZE)
        lcd.drawText(margin, textY + 48, "tries to space them apart evenly.", SMLSIZE)
        lcd.drawText(margin, textY + 64, "Based on https://vtx.in.ua/ch/", SMLSIZE)
        lcd.drawText(10, LCD_H - 18, "[ENTER] or [BACK] to close", SMLSIZE)
    end
end

----------------------------------------------------------------
-- DRAW
----------------------------------------------------------------
local function draw()
    lcd.clear()

    local headerH = 40
    lcd.drawFilledRectangle(0, 0, LCD_W, headerH, SOLID)
    lcd.drawText((LCD_W - 310) // 2, 5, " Channel Distribution Calculator ", MIDSIZE + INVERS)

    local x1, x2 = 5, LCD_W // 2 + 5
    local y = headerH + 10
    local lh, gap = 14, 6

    if page == 1 then
        lcd.drawText(x1, y, CHAR_INPUT .. " Band:", editIndex == 1 and INVERS or 0)
        lcd.drawText(x1 + 65, y, ranges[selRangeIdx], editIndex == 1 and INVERS or 0)
        lcd.drawText(x2, y, CHAR_INPUT .. " Channel:", editIndex == 2 and INVERS or 0)
        lcd.drawText(x2 + 85, y, tostring(selChanIdx), editIndex == 2 and INVERS or 0)

        y = y + lh + gap
        lcd.drawText(x1, y, CHAR_INPUT .. " Pilots:", editIndex == 3 and INVERS or 0)
        lcd.drawText(x1 + 70, y, tostring(pilots), editIndex == 3 and INVERS or 0)
        lcd.drawText(x2, y, CHAR_INPUT .. " Include X:", editIndex == 4 and INVERS or 0)
        lcd.drawText(x2 + 95, y, includeXBand and "Yes" or "No", editIndex == 4 and INVERS or 0)

        y = y + lh + 10
        lcd.drawText(5, y, CHAR_FUNCTION .. " Calculate", MIDSIZE + (editIndex == 5 and INVERS or 0))
        lcd.drawText(LCD_W - 90, y, CHAR_LUA .. " Info", MIDSIZE + (editIndex == 6 and INVERS or 0))

        drawChannels(userSelected, y + 24)
    else
        if COLOR then
            drawChannels(calculated, headerH + 10)
            drawVisualization(calculated)
        else
            drawChannels(calculated, headerH + 10)
        end
    end

    drawFooter()
    drawPopup()
end

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------
local function run(event)
    -- Handle Info Page
    if infoPage then
        if event == EVT_ENTER_BREAK or event == EVT_EXIT_BREAK or event == EVT_RTN_BREAK then
            infoPage = false
            page = 1
            draw()
            return 0
        else
            drawInfoPage()
            return 0
        end
    end

    if event == EVT_EXIT_BREAK then
        if page == 2 then page = 1 else return 2 end
    elseif event == EVT_VIRTUAL_NEXT_PAGE then
        if editIndex < #editLabels then editIndex = editIndex + 1 end
    elseif event == EVT_VIRTUAL_PREV_PAGE then
        if editIndex > 1 then editIndex = editIndex - 1 end
    elseif event == EVT_ROT_RIGHT then
        if editIndex == 1 and selRangeIdx < #ranges then selRangeIdx = selRangeIdx + 1
        elseif editIndex == 2 and selChanIdx < #channelsData[ranges[selRangeIdx]] then selChanIdx = selChanIdx + 1
        elseif editIndex == 3 and pilots < 6 then pilots = pilots + 1
        elseif editIndex == 4 then includeXBand = true end
    elseif event == EVT_ROT_LEFT then
        if editIndex == 1 and selRangeIdx > 1 then selRangeIdx = selRangeIdx - 1
        elseif editIndex == 2 and selChanIdx > 1 then selChanIdx = selChanIdx - 1
        elseif editIndex == 3 and pilots > 2 then pilots = pilots - 1
        elseif editIndex == 4 then includeXBand = false end
    elseif event == EVT_ENTER_BREAK then
        if page == 1 then
            if editIndex == 5 then
                calculate()
                page = 2
            elseif editIndex == 6 then
                infoPage = true
            else
                local r = ranges[selRangeIdx]
                local ch = channelsData[r][selChanIdx]
                local foundIndex
                for i = 1, #userSelected do
                    local u = userSelected[i]
                    if u[1] == r and u[2] == ch[1] then foundIndex = i break end
                end
                if foundIndex then
                    removeAt(userSelected, foundIndex)
                else
                    if #userSelected >= 5 then
                        popupMsg, popupTimer = "Max 5 channels!", getTime() + 200
                    else
                        add(userSelected, { r, ch[1], ch[2] })
                        local n = #userSelected
                        pilots = math.min(6, n + 1)
                    end
                end
            end
        end
    elseif event == EVT_RTN_BREAK then
        if page == 2 then page = 1 elseif editIndex == 5 then calculate() page = 2 end
    end

    draw()
    return 0
end

return { run = run }