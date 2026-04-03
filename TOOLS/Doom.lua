-- TNS|Doom|TNE
-- Doom-style raycaster for EdgeTX 480×320
-- Left stick : turn
-- Right stick: forward/back + strafe
-- SF switch : fire

local W = rawget(_G, "LCD_W") or 480
local H = rawget(_G, "LCD_H") or 320
local HUD_H = 64            -- HUD height
local VIEW_H = H - HUD_H    -- 3D viewport height (even)
if VIEW_H % 2 == 1 then VIEW_H = VIEW_H - 1; HUD_H = H - VIEW_H end
local HUD_Y  = VIEW_H
local HALF_H = VIEW_H / 2
local COL_W  = 2            -- pixels per column
local COLS   = math.floor(W / COL_W)
local MAX_D  = 16           -- DDA depth limit
local FP     = 256          -- fixed-point scale for player position
local GUN_W  = 48
local GUN_H  = 26

-- ── Map ───────────────────────────────────────────────────────────────────────
-- 16 × 12  (#=wall  .=floor  E=enemy  H=health  A=ammo)
local MAP_W, MAP_H = 16, 12
local MAP = {
  "################",
  "#.......E......#", 
  "#..............#",   
  "#.......E......#",
  "#.#....##.....##",
  "#..............#",
  "#...A...P.....##",
  "#..............#",
  "#........####..#",
  "#...E....#.H#..#",
  "#........#.....#", 
  "################",
}

local FAR_Z = 1e9
local RAY_STEP_LIMIT = (MAP_W + MAP_H) * 3

local function mapGet(x, y)
  if x < 0 or y < 0 or y >= MAP_H or x >= MAP_W then return "#" end
  return string.sub(MAP[y + 1], x + 1, x + 1)
end

local function isWall(x, y)
  return mapGet(math.floor(x), math.floor(y)) == "#"
end

local function isWallFP(x, y)
  return mapGet(math.floor(x / FP), math.floor(y / FP)) == "#"
end

local function fpToWorld(v)
  return v / FP
end

local function roundToInt(v)
  if v >= 0 then
    return math.floor(v + 0.5)
  end
  return math.ceil(v - 0.5)
end

-- ── Player ────────────────────────────────────────────────────────────────────
local px, py   = math.floor(1.5 * FP), math.floor(1.5 * FP)  -- fixed-point; overwritten by 'P' in map
local pdx, pdy = 1.0, 0.0
local ppx, ppy = 0.0, 0.66  -- camera plane (≈66° FOV)
local pa       = 0.0        -- view angle in radians
local HEALTH_MAX = 30 -- Max player health
local health   = HEALTH_MAX -- Player health (initially full)
local ammo     = 30 -- Player ammo (initially full)
local kills    = 0
local dead     = false
local won      = false
local reloadT  = 0 -- Reload timer (ticks until can shoot again after ammo runs out)
local RELOAD_TICKS = 180 -- Ticks to reload after ammo runs out (at 50fps, 180 ticks = ~3.6s)
local AMMO_MAX = 30
local ENEMY_HP = 30
local RESPAWN_TICKS = 240 -- Enemy respawn time in ticks (at 50fps, 240 ticks = ~4.8s)
local ITEM_RESPAWN_TICKS = 300 -- Item respawn time in ticks (at 50fps, 240 ticks = ~4.8s)

local splashT = 0
local inSplash = true
local fpsFrameCount = 0
local fpsLastTime = getTime()
local fpsValue = 0
local hudFrame = 0
local lastFlashActive = false
local hitFlashT = 0
local shotFlashT = 0
local healFlashT = 0
local HIT_FLASH_TICKS = 25   -- ~0.5s at 50fps
local SHOT_FLASH_TICKS = 6
local HEAL_FLASH_TICKS = 10

-- ── Enemies ───────────────────────────────────────────────────────────────────
local enemies = {}
local items = {}

-- ── Input state ───────────────────────────────────────────────────────────────
local firing    = false
local flashT    = 0
local sfPrev    = false -- SF previous state for edge detection

-- ── Input sources ─────────────────────────────────────────────────────────────
local srcRot, srcFwd, srcStr  -- channel names for rotation / forward / strafe
local dbgRot, dbgFwd, dbgStr = 0, 0, 0  -- last raw values for HUD debug
local dbgRotCmd, dbgFwdCmd, dbgStrCmd = 0, 0, 0 -- mapped movement commands
local dbgDX, dbgDY, dbgDirDX, dbgDirDY = 0, 0, 0, 0 -- applied per-frame deltas
local dbgBlkX, dbgBlkY = 0, 0 -- collision block flags for current frame
local dbgNx, dbgNy = 0, 0
local dbgMoveX, dbgMoveY = 0, 0
local stickRot, stickFwd, stickStrafe = 0, 0, 0

-- ── Z-buffer ──────────────────────────────────────────────────────────────────
local zbuf = {}
for i = 1, COLS do zbuf[i] = 999 end

-- ── Colors (pre-computed at load time) ────────────────────────────────────────
local C_SKY   = lcd.RGB(12,  12,  80)
local C_FLOOR = lcd.RGB(35,  35,  35)
local C_HUD   = lcd.RGB(8,   8,   8)
local C_WHITE = lcd.RGB(255, 255, 255)
local C_RED   = lcd.RGB(210, 30,  30)
local C_DKRED = lcd.RGB(60,  0,   0)
local C_YELL  = lcd.RGB(255, 200, 0)
local C_GRAY  = lcd.RGB(100, 100, 100)
local C_HEAD  = lcd.RGB(210, 170, 100)
local C_BODY  = lcd.RGB(160, 70,  20)
local C_LEGS  = lcd.RGB(120, 50,  15)
local C_MED   = lcd.RGB(40,  200, 120)
local C_AMMO  = lcd.RGB(255, 220, 60)
local C_AMMO_BAR = lcd.RGB(140, 90, 30)
local C_BLACK = lcd.RGB(0, 0, 0)
local C_GUN   = lcd.RGB(40,  60,  80)
local C_GUN2  = lcd.RGB(25,  40,  55)
local C_FLASH = lcd.RGB(255, 220, 60)
local C_FLASH2 = lcd.RGB(255, 170, 40)
local C_FLASH3 = lcd.RGB(255, 240, 140)
local C_FLASH_HIT = lcd.RGB(220, 60, 60)
local C_FLASH_SHOT = lcd.RGB(255, 235, 120)
local C_FLASH_HEAL = lcd.RGB(120, 200, 255)
local C_MAP_BG = lcd.RGB(20, 20, 20)
local C_MAP_WALL = lcd.RGB(120, 120, 120)
local C_MAP_FLOOR = lcd.RGB(40, 40, 40)
local C_MAP_PLAYER = lcd.RGB(0, 200, 0)
local C_MAP_ENEMY = lcd.RGB(200, 0, 0)
local C_MAP_DIR = lcd.RGB(0, 160, 255)
local C_COMPASS = lcd.RGB(0, 160, 255)
local C_MAP_BORDER = lcd.RGB(180, 180, 180)
local C_FACE_GOOD = lcd.RGB(0, 200, 0)
local C_FACE_MID  = lcd.RGB(255, 200, 0)
local C_FACE_BAD  = lcd.RGB(200, 0, 0)
local MINIMAP_SCALE = 4
local MINIMAP_PAD = 6
local SKY_STEP = 8
local SKY_COLORS = {}
for i = 0, HALF_H - 1, SKY_STEP do
  local t = i / HALF_H
  local r = math.floor(10 + 25 * t)
  local g = math.floor(20 + 35 * t)
  local b = math.floor(60 + 60 * t)
  SKY_COLORS[#SKY_COLORS + 1] = lcd.RGB(r, g, b)
end
local WALL_DIST_MAX = 32
local WALL_DIST_SCALE = 16
local WALL_COLORS0 = {}
local WALL_COLORS1 = {}
for i = 0, WALL_DIST_MAX * WALL_DIST_SCALE do
  local dist = i / WALL_DIST_SCALE
  local b = math.floor(210 / (dist + 0.7))
  if b > 210 then b = 210 elseif b < 20 then b = 20 end
  WALL_COLORS0[i + 1] = lcd.RGB(math.floor(b * 0.85), math.floor(b * 0.55), math.floor(b * 0.32))
  WALL_COLORS1[i + 1] = lcd.RGB(math.floor(b * 0.55), math.floor(b * 0.35), math.floor(b * 0.22))
end

-- ── Draw helper ───────────────────────────────────────────────────────────────
local function fillRect(x, y, w, h, col)
  if w <= 0 or h <= 0 then return end
  lcd.setColor(CUSTOM_COLOR, col)
  lcd.drawFilledRectangle(x, y, w, h, CUSTOM_COLOR)
end

local function wallColor(dist, side)
  if dist < 0 then dist = 0 end
  if dist > WALL_DIST_MAX then dist = WALL_DIST_MAX end
  local idx = math.floor(dist * WALL_DIST_SCALE) + 1
  if side == 1 then
    return WALL_COLORS1[idx]
  end
  return WALL_COLORS0[idx]
end

local function drawItemSprite(kind, x0, x1, y0, y1, tz)
  local c0 = math.floor(math.max(0, x0) / COL_W) + 1
  local c1 = math.floor(math.min(W - 1, x1) / COL_W) + 1
  if c0 < 1 then c0 = 1 end
  if c1 > COLS then c1 = COLS end

  local cx = math.floor((x0 + x1) * 0.5)
  local cy = math.floor((y0 + y1) * 0.5)
  local sprW = x1 - x0 + 1
  local t = math.max(1, math.floor(sprW * 0.15))

  for c = c0, c1 do
    local dx = (c - 1) * COL_W
    local dw = COL_W
    if dx < x0 then dw = dw - (x0 - dx); dx = x0 end
    if dx + dw - 1 > x1 then dw = x1 - dx + 1 end
    if dw > 0 and tz <= zbuf[c] then
      fillRect(dx, y0, dw, y1 - y0 + 1, C_WHITE)
      if kind == "health" then
        if dx + dw - 1 >= cx - t and dx <= cx + t then
          fillRect(dx, y0, dw, y1 - y0 + 1, C_RED)
        end
        fillRect(dx, cy - t, dw, (t * 2) + 1, C_RED)
      else
        local barW = math.max(1, math.floor(sprW / 5))
        local totalW = barW * 5
        local startX = cx - math.floor(totalW * 0.5)
        local b1 = startX
        local b2 = startX + barW
        local b3 = startX + barW * 2
        local b4 = startX + barW * 3
        local b5 = startX + barW * 4
        if dx + dw - 1 >= b1 and dx <= b1 + barW - 1 then
          fillRect(dx, y0, dw, y1 - y0 + 1, C_AMMO_BAR)
        end
        if dx + dw - 1 >= b2 and dx <= b2 + barW - 1 then
          fillRect(dx, y0, dw, y1 - y0 + 1, C_BLACK)
        end
        if dx + dw - 1 >= b3 and dx <= b3 + barW - 1 then
          fillRect(dx, y0, dw, y1 - y0 + 1, C_AMMO_BAR)
        end
        if dx + dw - 1 >= b4 and dx <= b4 + barW - 1 then
          fillRect(dx, y0, dw, y1 - y0 + 1, C_BLACK)
        end
        if dx + dw - 1 >= b5 and dx <= b5 + barW - 1 then
          fillRect(dx, y0, dw, y1 - y0 + 1, C_AMMO_BAR)
        end
      end
    end
  end
end

-- ── Raycaster ─────────────────────────────────────────────────────────────────
local function renderScene()
  local pxw = fpToWorld(px)
  local pyw = fpToWorld(py)
  -- Sky gradient
  for idx = 1, #SKY_COLORS do
    local y = (idx - 1) * SKY_STEP
    fillRect(0, y, W, SKY_STEP, SKY_COLORS[idx])
  end
  fillRect(0, HALF_H, W, HALF_H, C_FLOOR)

  for col = 0, COLS - 1 do
    local camX = (2 * ((col + 0.5) / COLS)) - 1
    local rdx = pdx + ppx * camX
    local rdy = pdy + ppy * camX

    local mx, my = math.floor(pxw), math.floor(pyw)
    local ddx = (rdx == 0) and 1e30 or math.abs(1 / rdx)
    local ddy = (rdy == 0) and 1e30 or math.abs(1 / rdy)

    local stepx, stepy, sidex, sidey
    if rdx < 0 then stepx = -1; sidex = (pxw - mx)      * ddx
    else             stepx =  1; sidex = (mx + 1 - pxw) * ddx end
    if rdy < 0 then stepy = -1; sidey = (pyw - my)      * ddy
    else             stepy =  1; sidey = (my + 1 - pyw) * ddy end

    local hit, side = false, 0
    local steps = 0
    while steps < RAY_STEP_LIMIT do
      if sidex < sidey then sidex = sidex + ddx; mx = mx + stepx; side = 0
      else                  sidey = sidey + ddy; my = my + stepy; side = 1 end
      if mapGet(mx, my) == "#" then hit = true; break end
      steps = steps + 1
    end
    local dist = FAR_Z
    if hit then
      if side == 0 then dist = (mx - pxw + (1 - stepx) * 0.5) / rdx
      else              dist = (my - pyw + (1 - stepy) * 0.5) / rdy end
      if dist < 0.1 then dist = 0.1 end
    end
    zbuf[col + 1] = dist

    if dist < FAR_Z * 0.5 then
      local lh = math.floor(VIEW_H / dist)
      if lh < 1 then lh = 1 end
      local y0 = math.max(0,          HALF_H - math.floor(lh / 2))
      local y1 = math.min(VIEW_H - 1, HALF_H + math.floor(lh / 2))
      fillRect(col * COL_W, y0, COL_W, y1 - y0 + 1, wallColor(dist, side))
    end
  end
end

-- ── Sprites ───────────────────────────────────────────────────────────────────
local function renderSprites()
  local pxw = fpToWorld(px)
  local pyw = fpToWorld(py)
  local det = (ppx * pdy - pdx * ppy)
  if math.abs(det) < 1e-9 then return end
  local inv = 1 / det

  local spr = {}
  for _, e in ipairs(enemies) do
    if e.alive then
      local sx = e.x - pxw
      local sy = e.y - pyw
      local d2 = sx * sx + sy * sy
      spr[#spr + 1] = { kind = "enemy", e = e, sx = sx, sy = sy, d2 = d2 }
    end
  end
  for _, it in ipairs(items) do
    if it.alive then
      local sx = it.x - pxw
      local sy = it.y - pyw
      local d2 = sx * sx + sy * sy
      spr[#spr + 1] = { kind = "item", it = it, sx = sx, sy = sy, d2 = d2 }
    end
  end
  table.sort(spr, function(a, b) return a.d2 > b.d2 end)

  for i = 1, #spr do
    local s = spr[i]
    local tx = inv * (pdy * s.sx - pdx * s.sy)
    local tz = inv * (-ppy * s.sx + ppx * s.sy)

    if tz > 0.25 then
      local scrX = math.floor((W * 0.5) * (1 + tx / tz))
      local sprH = math.floor(VIEW_H / tz)
      if s.kind == "item" then
        sprH = math.floor(sprH * 0.25)
      end
      if sprH > 4 then
        local sprW = sprH
        local x0 = scrX - math.floor(sprW / 2)
        local x1 = x0 + sprW - 1
        local y0 = math.max(0, HALF_H - math.floor(sprH / 2))
        local y1 = math.min(VIEW_H - 1, HALF_H + math.floor(sprH / 2))

        if x1 >= 0 and x0 < W and y1 > y0 then
          if s.kind == "item" then
            drawItemSprite(s.it.kind, x0, x1, y0, y1, tz)
          else
          local headH = math.max(1, math.floor(sprH * 0.22))
          local torsoH = math.max(1, math.floor(sprH * 0.43))
          local legH = math.max(1, sprH - headH - torsoH)
          local headY = y0
          local torsoY = headY + headH
          local legY = torsoY + torsoH
          local armY = torsoY + math.floor(torsoH * 0.15)

          local bodyW = x1 - x0 + 1
          local headW = math.max(1, math.floor(bodyW * 0.35))
          local torsoW = math.max(1, math.floor(bodyW * 0.40))
          local armW = math.max(1, math.floor(bodyW * 0.20))
          local legW = math.max(1, math.floor(bodyW * 0.18))
          local cx = math.floor((x0 + x1) * 0.5)
          local headX0 = cx - math.floor(headW / 2)
          local torsoX0 = cx - math.floor(torsoW / 2)
          local leftArmX0 = torsoX0 - armW
          local rightArmX0 = torsoX0 + torsoW
          local leftLegX0 = cx - legW - 1
          local rightLegX0 = cx + 1

          local c0 = math.floor(math.max(0, x0) / COL_W) + 1
          local c1 = math.floor(math.min(W - 1, x1) / COL_W) + 1
          if c0 < 1 then c0 = 1 end
          if c1 > COLS then c1 = COLS end

          for c = c0, c1 do
            local dx = (c - 1) * COL_W
            local dw = COL_W
            if dx < x0 then dw = dw - (x0 - dx); dx = x0 end
            if dx + dw - 1 > x1 then dw = x1 - dx + 1 end

            if dw > 0 and tz <= zbuf[c] then
              if dx + dw - 1 >= headX0 and dx <= headX0 + headW - 1 then
                fillRect(dx, headY, dw, headH, C_HEAD)
              end
              if dx + dw - 1 >= torsoX0 and dx <= torsoX0 + torsoW - 1 then
                fillRect(dx, torsoY, dw, torsoH, C_BODY)
              end
              if dx + dw - 1 >= leftArmX0 and dx <= leftArmX0 + armW - 1 then
                fillRect(dx, armY, dw, torsoH, C_BODY)
              end
              if dx + dw - 1 >= rightArmX0 and dx <= rightArmX0 + armW - 1 then
                fillRect(dx, armY, dw, torsoH, C_BODY)
              end
              if dx + dw - 1 >= leftLegX0 and dx <= leftLegX0 + legW - 1 then
                fillRect(dx, legY, dw, legH, C_LEGS)
              end
              if dx + dw - 1 >= rightLegX0 and dx <= rightLegX0 + legW - 1 then
                fillRect(dx, legY, dw, legH, C_LEGS)
              end
            end
          end
          end
        end
      end
    end
  end
end

-- ── Gun ───────────────────────────────────────────────────────────────────────
local function renderGun()
  local gx = math.floor(W / 2 - GUN_W / 2)
  local gy = VIEW_H - GUN_H
  fillRect(gx, gy, GUN_W, GUN_H, C_GUN)
  fillRect(gx + math.floor(GUN_W / 2) - 5, gy - 14, 10, 14, C_GUN2)
  if flashT > 0 then
    local fx = gx + math.floor(GUN_W / 2)
    local fy = gy - 22
    -- Spark burst: cross + diagonals + glow dot
    lcd.setColor(CUSTOM_COLOR, C_FLASH)
    lcd.drawLine(fx - 10, fy, fx + 10, fy, CUSTOM_COLOR)
    lcd.drawLine(fx, fy - 8, fx, fy + 8, CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, C_FLASH2)
    lcd.drawLine(fx - 7, fy - 7, fx + 7, fy + 7, CUSTOM_COLOR)
    lcd.drawLine(fx - 7, fy + 7, fx + 7, fy - 7, CUSTOM_COLOR)
    -- removed glow dot
  end
end

local function renderDitherFlash(col, step, x0, y0, w, h)
  local x = x0 or 0
  local y = y0 or 0
  local ww = w or W
  local hh = h or H
  for yy = y, y + hh - 1, step do
    fillRect(x, yy, ww, 1, col)
  end
end

local function renderDitherDiamond(col, step, widthRatio, heightRatio, yOffset, yMin, yMax)
  local ww = math.max(3, math.floor(W * (widthRatio or 0.4)))
  local hh = math.max(3, math.floor(H * (heightRatio or 0.25)))
  local cx = math.floor(W * 0.5)
  local cy = math.floor((H * 0.5) + (yOffset or 0))
  local halfH = math.floor(hh * 0.5)
  for dy = -halfH, halfH, step do
    local yy = cy + dy
    if (not yMin or yy >= yMin) and (not yMax or yy <= yMax) then
      local t = 1 - (math.abs(dy) / (halfH + 0.0001))
      local lineW = math.max(1, math.floor(ww * t))
      local x0 = cx - math.floor(lineW * 0.5)
      fillRect(x0, yy, lineW, 1, col)
    end
  end
end

local function renderScreenFlash()
  if hitFlashT > 0 then
    renderDitherFlash(C_FLASH_HIT, 4, 0, 0, W, VIEW_H)  -- 1:3
  elseif healFlashT > 0 then
    renderDitherFlash(C_FLASH_HEAL, 4, 0, 0, W, VIEW_H) -- 1:3
  elseif shotFlashT > 0 then
    local yMax = VIEW_H - GUN_H - 1
    renderDitherDiamond(C_FLASH_SHOT, 6, 0.42, 0.28, (math.floor(H * 0.5 * 0.5)), 0, yMax) -- 1:5
  end
end

local function dirFromAngle(a)
  local TWO_PI = math.pi * 2
  local s = math.floor(((a % TWO_PI) + math.pi / 8) / (math.pi / 4)) % 8
  if s == 0 then return 1, 0 end
  if s == 1 then return 1, 1 end
  if s == 2 then return 0, 1 end
  if s == 3 then return -1, 1 end
  if s == 4 then return -1, 0 end
  if s == 5 then return -1, -1 end
  if s == 6 then return 0, -1 end
  return 1, -1
end

-- ── Splash ───────────────────────────────────────────────────────────────────
local function renderTitleScreen(title, subtitle, titleCol, showPrompt)
  lcd.clear()
  local t = splashT
  local z = 0.5 + 0.5 * math.sin(t * 0.08)
  local bob = math.floor(math.sin(t * 0.06) * 4)
  local zoomY = math.floor((z - 0.5) * 12)

  lcd.setColor(CUSTOM_COLOR, lcd.RGB(0, 0, 0))
  lcd.drawFilledRectangle(0, 0, W, H, CUSTOM_COLOR)

  local titleY = H / 2 - 46 + bob - zoomY
  local subY = H / 2 - 8 + bob - math.floor(zoomY / 2)
  local brown = lcd.RGB(120, 70, 30)
  local red = lcd.RGB(180, 20, 20)

  if titleCol then
    lcd.setColor(CUSTOM_COLOR, titleCol)
    lcd.drawText(W / 2, titleY, title, CENTER + DBLSIZE + CUSTOM_COLOR)
  else
    -- Red outline
    lcd.setColor(CUSTOM_COLOR, red)
    lcd.drawText(W / 2 - 1, titleY, title, CENTER + DBLSIZE + CUSTOM_COLOR)
    lcd.drawText(W / 2 + 1, titleY, title, CENTER + DBLSIZE + CUSTOM_COLOR)
    lcd.drawText(W / 2, titleY - 1, title, CENTER + DBLSIZE + CUSTOM_COLOR)
    lcd.drawText(W / 2, titleY + 1, title, CENTER + DBLSIZE + CUSTOM_COLOR)
    -- Brown fill
    lcd.setColor(CUSTOM_COLOR, brown)
    lcd.drawText(W / 2, titleY, title, CENTER + DBLSIZE + CUSTOM_COLOR)
  end

  if subtitle and subtitle ~= "" then
    lcd.setColor(CUSTOM_COLOR, red)
    lcd.drawText(W / 2, subY, subtitle, CENTER + MIDSIZE + CUSTOM_COLOR)
  end

  if showPrompt and (t % 40) < 24 then
    lcd.setColor(CUSTOM_COLOR, C_YELL)
    lcd.drawText(W / 2, H / 2 + 28, "MOVE STICK TO START", CENTER + SMLSIZE + CUSTOM_COLOR)
  end
end

local function renderSplash()
  renderTitleScreen("DOOM", "on EdgeTX", nil, true)
end

local function renderEndScreen(title, titleCol)
  renderTitleScreen(title, string.format("KILLS: %d", kills), titleCol, false)
end

local function updateFps()
  fpsFrameCount = fpsFrameCount + 1
  local now = getTime()
  if now - fpsLastTime >= 100 then
    fpsValue = fpsFrameCount
    fpsFrameCount = 0
    fpsLastTime = now
  end
end

-- ── Minimap ───────────────────────────────────────────────────────────────────
local function renderMinimap()
  local scale = MINIMAP_SCALE
  local mmW = MAP_W * scale
  local mmH = MAP_H * scale
  local mmX = W - mmW - MINIMAP_PAD
  local mmY = HUD_Y + 2

  fillRect(mmX - 1, mmY - 1, mmW + 2, mmH + 2, C_MAP_BG)

  for y = 0, MAP_H - 1 do
    for x = 0, MAP_W - 1 do
      local c = mapGet(x, y)
      local col = (c == "#") and C_MAP_WALL or C_MAP_FLOOR
      fillRect(mmX + x * scale, mmY + y * scale, scale, scale, col)
    end
  end

  for _, e in ipairs(enemies) do
    if e.alive then
      local ex = mmX + math.floor(e.x * scale)
      local ey = mmY + math.floor(e.y * scale)
      fillRect(ex, ey, 2, 2, C_MAP_ENEMY)
    end
  end

  local pxw = fpToWorld(px)
  local pyw = fpToWorld(py)
  local pxm = mmX + math.floor(pxw * scale)
  local pym = mmY + math.floor(pyw * scale)
  lcd.setColor(CUSTOM_COLOR, C_MAP_PLAYER)
  lcd.drawFilledCircle(pxm + 1, pym + 1, 1, CUSTOM_COLOR)
end

local function renderCompass()
  local scale = MINIMAP_SCALE
  local mmW = MAP_W * scale
  local mmH = MAP_H * scale
  local mmX = W - mmW - MINIMAP_PAD
  local mmY = HUD_Y + 2
  local cx = mmX - mmW - MINIMAP_PAD
  local cy = mmY

  local centerX = cx + math.floor(mmW / 2)
  local centerY = cy + math.floor(mmH / 2)
  lcd.setColor(CUSTOM_COLOR, C_COMPASS)
  local r = math.floor(math.min(mmW, mmH) / 2) - 2
  if r < 4 then r = 4 end
  local function fillTriangle(x1, y1, x2, y2, x3, y3, col)
    x1, y1 = roundToInt(x1), roundToInt(y1)
    x2, y2 = roundToInt(x2), roundToInt(y2)
    x3, y3 = roundToInt(x3), roundToInt(y3)
    if y2 < y1 then x1, x2 = x2, x1; y1, y2 = y2, y1 end
    if y3 < y1 then x1, x3 = x3, x1; y1, y3 = y3, y1 end
    if y3 < y2 then x2, x3 = x3, x2; y2, y3 = y3, y2 end

    local function interp(xa, ya, xb, yb, y)
      if yb == ya then return xa end
      return xa + (xb - xa) * (y - ya) / (yb - ya)
    end

    for y = y1, y3 do
      local xa, xb
      if y < y2 then
        xa = interp(x1, y1, x2, y2, y)
        xb = interp(x1, y1, x3, y3, y)
      else
        xa = interp(x2, y2, x3, y3, y)
        xb = interp(x1, y1, x3, y3, y)
      end
      if xa > xb then xa, xb = xb, xa end
      fillRect(roundToInt(xa), y, roundToInt(xb - xa) + 1, 1, col)
    end
  end

  -- Base circle
  lcd.setColor(CUSTOM_COLOR, C_COMPASS)
  lcd.drawFilledCircle(centerX, centerY, r, CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, C_WHITE)
  lcd.drawCircle(centerX, centerY, r, CUSTOM_COLOR)

  -- Dent (notch) indicating direction
  local dx, dy = dirFromAngle(pa)
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.001 then len = 1 end
  local nx, ny = dx / len, dy / len
  local notchR = math.max(3, math.floor(r * 0.35))
  local depth = notchR * (0.6 + 0.4 * math.max(math.abs(nx), math.abs(ny)))
  local tipX = centerX + nx * r
  local tipY = centerY + ny * r
  local baseX = centerX + nx * (r - depth)
  local baseY = centerY + ny * (r - depth)
  local perpX = -ny
  local perpY = nx
  local bx1 = baseX + perpX * notchR
  local by1 = baseY + perpY * notchR
  local bx2 = baseX - perpX * notchR
  local by2 = baseY - perpY * notchR
  fillTriangle(tipX, tipY, bx1, by1, bx2, by2, C_MAP_BG)
end

local function renderSmiley(x, y, r, mood)
  local col = C_FACE_MID
  if mood == "happy" then col = C_FACE_GOOD end
  if mood == "sad" then col = C_FACE_BAD end
  lcd.setColor(CUSTOM_COLOR, col)
  lcd.drawCircle(x, y, r, CUSTOM_COLOR)
  local eyeDX = math.max(3, math.floor(r * 0.45))
  local eyeY = y - math.floor(r * 0.30)
  lcd.drawFilledCircle(x - eyeDX, eyeY, 1, CUSTOM_COLOR)
  lcd.drawFilledCircle(x + eyeDX, eyeY, 1, CUSTOM_COLOR)
  local mouthY = y + math.floor(r * 0.35) - 6
  local mouthW = math.max(4, math.floor(r * 0.45))
  local mouthH = math.max(2, math.floor(r * 0.18))
  lcd.drawLine(x - mouthW, mouthY, x, mouthY + mouthH, CUSTOM_COLOR)
  lcd.drawLine(x, mouthY + mouthH, x + mouthW, mouthY, CUSTOM_COLOR)
end

-- ── HUD ───────────────────────────────────────────────────────────────────────
local function renderHUD()
  fillRect(0, HUD_Y, W, HUD_H, C_HUD)

  -- Smiley on the left (symmetric to minimap on right)
  local hpPct = health / HEALTH_MAX
  local mood = "neutral"
  if hpPct >= 0.65 then mood = "happy" end
  if hpPct <= 0.35 then mood = "sad" end
  local mmW = MAP_W * MINIMAP_SCALE
  local mmH = MAP_H * MINIMAP_SCALE
  local faceR = math.floor(math.min(mmW, mmH) / 2) - 2
  if faceR < 6 then faceR = 6 end
  local faceX = MINIMAP_PAD + math.floor(mmW / 2)
  local faceY = HUD_Y + 2 + math.floor(mmH / 2)
  renderSmiley(faceX, faceY, faceR, mood)

  -- Stats centered between smiley and minimap
  local mmW = MAP_W * MINIMAP_SCALE
  local gap = 6
  local leftEdge = MINIMAP_PAD + mmW + gap
  local rightEdge = W - MINIMAP_PAD - mmW - gap
  local centerX = math.floor((leftEdge + rightEdge) / 2)
  local line1 = HUD_Y + 4
  local line2 = HUD_Y + 22
  local line3 = HUD_Y + 40

  local barW = 120
  local barX = centerX - math.floor(barW / 2)
  local hpText = string.format("HP %d", health)
  lcd.setColor(CUSTOM_COLOR, C_WHITE)
  lcd.drawText(barX - 4, line1, hpText, RIGHT + SMLSIZE + CUSTOM_COLOR)
  fillRect(barX, line1 + 2, barW, 12, C_DKRED)
  local hw = math.floor(barW * health / HEALTH_MAX)
  if hw > 0 then fillRect(barX, line1 + 2, hw, 12, C_RED) end

  lcd.setColor(CUSTOM_COLOR, C_YELL)
  lcd.drawText(centerX, line2, string.format("AMMO %d", ammo), CENTER + SMLSIZE + CUSTOM_COLOR)

  lcd.setColor(CUSTOM_COLOR, C_WHITE)
  lcd.drawText(centerX, line3, string.format("KILLS %d", kills), CENTER + SMLSIZE + CUSTOM_COLOR)

  renderMinimap()
  renderCompass()
end

-- ── Input: sticks + SF ────────────────────────────────────────────────────────
local DEAD = 50   -- deadzone (out of 1024)
local ROT  = 0.06
local MOV  = 0.08
local INV_ROT = 1
local INV_FWD = 1
local INV_STR = -1
local TEST_FORCE_PX = nil -- set to +/- value to bypass movement math entirely

local function axisStep(v)
  if v > DEAD then return 1 end
  if v < -DEAD then return -1 end
  return 0
end

local function rebuildViewFromAngle()
  pdx, pdy = math.cos(pa), math.sin(pa)
  ppx, ppy = -pdy * 0.66, pdx * 0.66
end


local function safeGet(src)
  local ok, v = pcall(getValue, src)
  return (ok and type(v) == "number") and v or 0
end

local function readHardware()
  local lsx = safeGet(srcRot)  -- left  stick X: rotate
  local rsy = safeGet(srcFwd)  -- right stick Y: fwd / back
  local rsx = safeGet(srcStr)  -- right stick X: strafe
  local sf  = safeGet("sf")    -- SF switch

  dbgRot, dbgFwd, dbgStr = lsx, rsy, rsx  -- store for HUD

  -- Binary: any deflection past dead zone -> full speed (immune to calibration range)
  stickRot    = axisStep(lsx * INV_ROT)
  stickFwd    = axisStep(rsy * INV_FWD)
  stickStrafe = axisStep(rsx * INV_STR)
  dbgRotCmd, dbgFwdCmd, dbgStrCmd = stickRot, stickFwd, stickStrafe

  local sfNow = sf > 512
  if sfNow and not sfPrev then firing = true end
  sfPrev = sfNow

  return stickRot, stickFwd, stickStrafe
end

-- ── Player movement ───────────────────────────────────────────────────────────
local function updatePlayer(stickRot, stickFwd, stickStrafe)
  local oldPx, oldPy = px, py
  local oldPdx, oldPdy = pdx, pdy
  dbgBlkX, dbgBlkY = 0, 0
  dbgMoveX, dbgMoveY = 0, 0
  dbgNx, dbgNy = px, py

  -- Rotation: left stick X
  if stickRot ~= 0 then
    pa = pa + stickRot * ROT
  end
  rebuildViewFromAngle()

  -- Forward / backward: right stick Y
  if stickFwd ~= 0 then
    local f = stickFwd * MOV
    local dx = roundToInt(pdx * f * FP)
    local dy = roundToInt(pdy * f * FP)
    dbgNx = px + dx
    dbgNy = py + dy

    -- Test X and Y independently from the original position.
    local canMoveX = not isWallFP(px + dx, py)
    local canMoveY = not isWallFP(px, py + dy)

    if canMoveX then
      px = px + dx
      dbgMoveX = 1
    else
      dbgBlkX = 1
    end

    if canMoveY then
      py = py + dy
      dbgMoveY = 1
    else
      dbgBlkY = 1
    end
  end

  -- Strafe: right stick X  (right = positive)
  if stickStrafe ~= 0 then
    local s = stickStrafe * MOV
    local dx = roundToInt(pdy * s * FP)
    local dy = roundToInt(-pdx * s * FP)
    dbgNx = px + dx
    dbgNy = py + dy

    local canMoveX = not isWallFP(px + dx, py)
    local canMoveY = not isWallFP(px, py + dy)

    if canMoveX then
      px = px + dx
      dbgMoveX = 1
    else
      dbgBlkX = 1
    end

    if canMoveY then
      py = py + dy
      dbgMoveY = 1
    else
      dbgBlkY = 1
    end
  end

  dbgDX = fpToWorld(px - oldPx)
  dbgDY = fpToWorld(py - oldPy)
  dbgDirDX = pdx - oldPdx
  dbgDirDY = pdy - oldPdy
end

-- ── Shooting ──────────────────────────────────────────────────────────────────
local function shoot()
  if ammo <= 0 then return end
  ammo   = ammo - 1
  flashT = 4
  shotFlashT = SHOT_FLASH_TICKS

  local pxw = fpToWorld(px)
  local pyw = fpToWorld(py)
  local mx, my = math.floor(pxw), math.floor(pyw)
  local ddx = (pdx == 0) and 1e30 or math.abs(1 / pdx)
  local ddy = (pdy == 0) and 1e30 or math.abs(1 / pdy)
  local stepx, stepy, sidex, sidey
  if pdx < 0 then stepx = -1; sidex = (pxw - mx)      * ddx
  else             stepx =  1; sidex = (mx + 1 - pxw) * ddx end
  if pdy < 0 then stepy = -1; sidey = (pyw - my)      * ddy
  else             stepy =  1; sidey = (my + 1 - pyw) * ddy end

  for _ = 1, MAX_D do
    if sidex < sidey then sidex = sidex + ddx; mx = mx + stepx
    else                  sidey = sidey + ddy; my = my + stepy end
    if mapGet(mx, my) == "#" then break end
    for _, e in ipairs(enemies) do
      if e.alive and math.floor(e.x) == mx and math.floor(e.y) == my then
        e.hp = e.hp - math.random(10, 20)
        if e.hp <= 0 then
          e.alive = false
          e.respawnT = RESPAWN_TICKS
          kills = kills + 1
        end
        return
      end
    end
  end
end

-- ── Enemy AI ──────────────────────────────────────────────────────────────────
local function updateEnemies()
  local pxw = fpToWorld(px)
  local pyw = fpToWorld(py)
  for _, e in ipairs(enemies) do
    if e.alive then
      local dx, dy = pxw - e.x, pyw - e.y
      local d2 = dx * dx + dy * dy
      if d2 > 0.0001 and d2 < 64 then
        local inv = 1 / math.sqrt(d2)
        local nx = e.x + (dx * inv) * 0.015
        local ny = e.y + (dy * inv) * 0.015
        if not isWall(nx, e.y) then e.x = nx end
        if not isWall(e.x, ny) then e.y = ny end
        if d2 < (0.85 * 0.85) then
          e.timer = e.timer + 1
          if e.timer >= 30 then
            health = math.max(0, health - math.random(10, 20))
            hitFlashT = HIT_FLASH_TICKS
            e.timer = 0
          end
        end
      end
    elseif e.respawnT and e.respawnT > 0 then
      e.respawnT = e.respawnT - 1
      if e.respawnT <= 0 then
        e.alive = true
        e.hp = ENEMY_HP
        e.timer = 0
        e.x = e.sx
        e.y = e.sy
      end
    end
  end
end

local function updateItems()
  for _, it in ipairs(items) do
    if not it.alive and it.respawnT and it.respawnT > 0 then
      it.respawnT = it.respawnT - 1
      if it.respawnT <= 0 then
        it.alive = true
      end
    end
  end
end

-- ── Init ──────────────────────────────────────────────────────────────────────
local function init()
  srcRot = "ch1"
  srcFwd = "ch2"
  srcStr = "ch4"
  enemies = {}
  items = {}

  for y = 0, MAP_H - 1 do
    for x = 0, MAP_W - 1 do
      local c = mapGet(x, y)
      if c == "E" then
        local sx, sy = x + 0.5, y + 0.5
        table.insert(enemies, { x = sx, y = sy, sx = sx, sy = sy, hp = ENEMY_HP, alive = true, timer = 0, respawnT = 0 })
      elseif c == "H" then
        local sx, sy = x + 0.5, y + 0.5
        table.insert(items, { x = sx, y = sy, kind = "health", alive = true, respawnT = 0 })
      elseif c == "A" then
        local sx, sy = x + 0.5, y + 0.5
        table.insert(items, { x = sx, y = sy, kind = "ammo", alive = true, respawnT = 0 })
      elseif c == "P" then
        px = (x * FP) + math.floor(0.5 * FP)
        py = (y * FP) + math.floor(0.5 * FP)
      end
    end
  end
  pa = 0.0
  rebuildViewFromAngle()
end

-- ── Run ───────────────────────────────────────────────────────────────────────
local function run(event)
  updateFps()
  if inSplash then
    splashT = splashT + 1
    readHardware()
    -- Start on any stick movement or after timeout (~3s at 50fps)
    if math.abs(stickRot) > 0 or math.abs(stickFwd) > 0 or math.abs(stickStrafe) > 0 or splashT > 150 then
      inSplash = false
    end
    renderSplash()
    return 0
  end

  if not dead and not won then
    firing = false                          -- reset; handlers below may set it
    readHardware()
    updatePlayer(stickRot, stickFwd, stickStrafe)
    if TEST_FORCE_PX ~= nil then
      px = px + roundToInt(TEST_FORCE_PX * FP)
    end
    local pxw = fpToWorld(px)
    local pyw = fpToWorld(py)
    for _, it in ipairs(items) do
      if it.alive and math.floor(it.x) == math.floor(pxw) and math.floor(it.y) == math.floor(pyw) then
        if it.kind == "health" then
          if health < HEALTH_MAX then
            it.alive = false
            it.respawnT = ITEM_RESPAWN_TICKS
            health = math.min(HEALTH_MAX, health + 10)
            healFlashT = HEAL_FLASH_TICKS
          end
        else
          if ammo < AMMO_MAX then
            it.alive = false
            it.respawnT = ITEM_RESPAWN_TICKS
            ammo = math.min(AMMO_MAX, ammo + 10)
            shotFlashT = SHOT_FLASH_TICKS
          end
        end
      end
    end
    updateItems()
    updateEnemies()
    if ammo <= 0 then
      reloadT = reloadT + 1
      if reloadT >= RELOAD_TICKS then
        ammo = AMMO_MAX
        reloadT = 0
      end
    else
      reloadT = 0
    end
    if firing  then shoot() end
    if flashT > 0 then flashT = flashT - 1 end
    if hitFlashT > 0 then hitFlashT = hitFlashT - 1 end
    if healFlashT > 0 then healFlashT = healFlashT - 1 end
    if shotFlashT > 0 then shotFlashT = shotFlashT - 1 end
    if kills >= 10 then won = true end
    if health <= 0 then dead = true end
  end

  renderScene()
  renderSprites()
  renderGun()
  hudFrame = hudFrame + 1
  local flashActive = (hitFlashT > 0) or (healFlashT > 0) or (shotFlashT > 0)
  local forceHud = flashActive or lastFlashActive
  if forceHud or (hudFrame % 2 == 0) then
    renderHUD()
  end
  lastFlashActive = flashActive
  renderScreenFlash()

  lcd.setColor(CUSTOM_COLOR, C_WHITE)
  lcd.drawText(W - 4, 2, string.format("%d FPS", fpsValue), RIGHT + SMLSIZE + CUSTOM_COLOR)

  if won then
    renderEndScreen("CONGRATS!", C_YELL)
  elseif dead then
    renderEndScreen("GAME OVER", C_RED)
  end

  return 0
end

return { init = init, run = run }
