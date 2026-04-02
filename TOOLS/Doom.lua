-- TNS|Doom|TNE
-- Doom-style raycaster for EdgeTX 480×320
-- Left stick : turn
-- Right stick: forward/back + strafe
-- SF switch : fire

local W, H   = 480, 320
local VIEW_H = 256          -- 3D viewport height (even)
local HUD_Y  = VIEW_H
local HUD_H  = H - VIEW_H  -- 64 px
local HALF_H = VIEW_H / 2  -- 128
local COLS   = 120          -- W / COL_W
local COL_W  = 4            -- pixels per column
local MAX_D  = 16           -- DDA depth limit
local FP     = 256          -- fixed-point scale for player position

-- ── Map ───────────────────────────────────────────────────────────────────────
-- 16 × 12  (#=wall  .=floor  E=enemy)
local MAP_W, MAP_H = 16, 12
local MAP = {
  "################",
  "#..............#",   
  "#.......E......#",
  "#.#....##.....##",
  "#..............#",
  "#.......P....###",
  "#..............#",
  "#..............#",
  "#........####..#",
  "#...E....#..#..#",
  "#........#..#..#",
  "################",
}

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
local health   = 100
local ammo     = 30
local kills    = 0
local dead     = false

-- ── Enemies ───────────────────────────────────────────────────────────────────
local enemies = {}

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
local C_GUN   = lcd.RGB(90,  90,  90)
local C_GUN2  = lcd.RGB(65,  65,  65)
local C_FLASH = lcd.RGB(255, 220, 60)

-- ── Draw helper ───────────────────────────────────────────────────────────────
local function fillRect(x, y, w, h, col)
  if w <= 0 or h <= 0 then return end
  lcd.setColor(CUSTOM_COLOR, col)
  lcd.drawFilledRectangle(x, y, w, h, CUSTOM_COLOR)
end

local function wallColor(dist, side)
  local b = math.floor(210 / (dist + 0.7))
  if b > 210 then b = 210 elseif b < 20 then b = 20 end
  if side == 1 then
    return lcd.RGB(math.floor(b * 0.55), math.floor(b * 0.35), math.floor(b * 0.22))
  end
  return lcd.RGB(math.floor(b * 0.85), math.floor(b * 0.55), math.floor(b * 0.32))
end

-- ── Raycaster ─────────────────────────────────────────────────────────────────
local function renderScene()
  local pxw = fpToWorld(px)
  local pyw = fpToWorld(py)
  fillRect(0, 0,      W, HALF_H, C_SKY)
  fillRect(0, HALF_H, W, HALF_H, C_FLOOR)

  for col = 0, COLS - 1 do
    local cx  = (2 * col / COLS) - 1
    local rdx = pdx + ppx * cx
    local rdy = pdy + ppy * cx

    local mx, my = math.floor(pxw), math.floor(pyw)
    local ddx = (rdx == 0) and 1e30 or math.abs(1 / rdx)
    local ddy = (rdy == 0) and 1e30 or math.abs(1 / rdy)

    local stepx, stepy, sidex, sidey
    if rdx < 0 then stepx = -1; sidex = (pxw - mx)      * ddx
    else             stepx =  1; sidex = (mx + 1 - pxw) * ddx end
    if rdy < 0 then stepy = -1; sidey = (pyw - my)      * ddy
    else             stepy =  1; sidey = (my + 1 - pyw) * ddy end

    local hit, side = false, 0
    for _ = 1, MAX_D do
      if sidex < sidey then sidex = sidex + ddx; mx = mx + stepx; side = 0
      else                  sidey = sidey + ddy; my = my + stepy; side = 1 end
      if mapGet(mx, my) == "#" then hit = true; break end
    end

    if hit then
      local dist
      if side == 0 then dist = (mx - pxw + (1 - stepx) * 0.5) / rdx
      else              dist = (my - pyw + (1 - stepy) * 0.5) / rdy end
      if dist < 0.1 then dist = 0.1 end
      zbuf[col + 1] = dist

      local lh = math.floor(VIEW_H / dist)
      local y0 = math.max(0,          HALF_H - math.floor(lh / 2))
      local y1 = math.min(VIEW_H - 1, HALF_H + math.floor(lh / 2))
      fillRect(col * COL_W, y0, COL_W, y1 - y0 + 1, wallColor(dist, side))
    else
      zbuf[col + 1] = 999
    end
  end
end

-- ── Sprites ───────────────────────────────────────────────────────────────────
local function renderSprites()
  local pxw = fpToWorld(px)
  local pyw = fpToWorld(py)
  local inv = 1 / (ppx * pdy - pdx * ppy)
  for _, e in ipairs(enemies) do
    if e.alive then
      local sx = e.x - pxw
      local sy = e.y - pyw
      local tx = inv * (pdy * sx - pdx * sy)
      local tz = inv * (-ppy * sx + ppx * sy)

      if tz > 0.25 then
        local scrX = math.floor((W / 2) * (1 + tx / tz))
        local sprH = math.floor(VIEW_H / tz)

        if sprH > 2 then
          local x0    = scrX - math.floor(sprH / 2)
          local y0    = math.max(0,          HALF_H - math.floor(sprH / 2))
          local y1    = math.min(VIEW_H - 1, HALF_H + math.floor(sprH / 2))
          local headH = math.max(1, math.floor(sprH * 0.28))
          local bodyY = y0 + headH

          if y1 > y0 then
            for dx = x0, x0 + sprH - 1 do
              if dx >= 0 and dx < W then
                local c = math.floor(dx / COL_W) + 1
                if c >= 1 and c <= COLS and zbuf[c] >= tz then
                  local hEnd = math.min(y0 + headH, y1)
                  if hEnd > y0 then fillRect(dx, y0, 1, hEnd - y0, C_HEAD) end
                  if bodyY < y1 then fillRect(dx, bodyY, 1, y1 - bodyY, C_BODY) end
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
  local gw, gh = 60, 36
  local gx = math.floor(W / 2 - gw / 2)
  local gy = VIEW_H - gh
  fillRect(gx, gy, gw, gh, C_GUN)
  fillRect(gx + math.floor(gw / 2) - 5, gy - 18, 10, 18, C_GUN2)
  if flashT > 0 then
    fillRect(gx + math.floor(gw / 2) - 14, gy - 32, 28, 16, C_FLASH)
  end
end

-- ── HUD ───────────────────────────────────────────────────────────────────────
local function renderHUD()
  fillRect(0, HUD_Y, W, HUD_H, C_HUD)

  lcd.setColor(CUSTOM_COLOR, C_WHITE)
  lcd.drawText(10, HUD_Y + 2, "HP", SMLSIZE + CUSTOM_COLOR)
  fillRect(32, HUD_Y + 2, 120, 14, C_DKRED)
  local hw = math.floor(120 * health / 100)
  if hw > 0 then fillRect(32, HUD_Y + 5, hw, 14, C_RED) end

  lcd.setColor(CUSTOM_COLOR, C_YELL)
  lcd.drawText(170, HUD_Y + 2, string.format("AMMO %d", ammo), SMLSIZE + CUSTOM_COLOR)

  lcd.setColor(CUSTOM_COLOR, C_WHITE)
  lcd.drawText(290, HUD_Y + 2, string.format("KILLS %d", kills), SMLSIZE + CUSTOM_COLOR)

  lcd.setColor(CUSTOM_COLOR, C_GRAY)
  local pxw = fpToWorld(px)
  local pyw = fpToWorld(py)
  local cellX = math.floor(pxw)
  local cellY = math.floor(pyw)
  lcd.drawText(10, HUD_Y + 20,
    string.format(
      "x=%.2f y=%.2f cell=%d,%d dir=%.2f,%.2f len=%.3f",
      pxw, pyw, cellX, cellY, pdx, pdy, math.sqrt(pdx * pdx + pdy * pdy)
    ),
    SMLSIZE + CUSTOM_COLOR)
  lcd.drawText(10, HUD_Y + 34,
    string.format(
      "raw r/f/s=%d/%d/%d | cmd r/f/s=%d/%d/%d",
      dbgRot, dbgFwd, dbgStr, stickRot, stickFwd, stickStrafe
    ),
    SMLSIZE + CUSTOM_COLOR)
  if TEST_FORCE_PX ~= nil then
    lcd.drawText(370, HUD_Y + 34, "TEST PX", SMLSIZE + CUSTOM_COLOR)
  end
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
        e.hp = e.hp - 20
        if e.hp <= 0 then e.alive = false; kills = kills + 1 end
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
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 0.01 and d < 8 then
        local nx = e.x + (dx / d) * 0.015
        local ny = e.y + (dy / d) * 0.015
        if not isWall(nx, e.y) then e.x = nx end
        if not isWall(e.x, ny) then e.y = ny end
        if d < 0.85 then
          e.timer = e.timer + 1
          if e.timer >= 30 then
            health = math.max(0, health - 8)
            e.timer = 0
          end
        end
      end
    end
  end
end

-- ── Init ──────────────────────────────────────────────────────────────────────
local function init()
  srcRot = "ch1"
  srcFwd = "ch2"
  srcStr = "ch4"

  for y = 0, MAP_H - 1 do
    for x = 0, MAP_W - 1 do
      local c = mapGet(x, y)
      if c == "E" then
        table.insert(enemies, { x = x + 0.5, y = y + 0.5, hp = 30, alive = true, timer = 0 })
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
  if not dead then
    firing = false                          -- reset; handlers below may set it
    readHardware()
    updatePlayer(stickRot, stickFwd, stickStrafe)
    if TEST_FORCE_PX ~= nil then
      px = px + roundToInt(TEST_FORCE_PX * FP)
    end
    updateEnemies()
    if firing  then shoot() end
    if flashT > 0 then flashT = flashT - 1 end
    if health <= 0 then dead = true end
  end

  lcd.clear()
  renderScene()
  renderSprites()
  renderGun()
  renderHUD()

  if dead then
    lcd.setColor(CUSTOM_COLOR, C_RED)
    lcd.drawText(W / 2, HALF_H - 30, "GAME OVER", CENTER + DBLSIZE + CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, C_WHITE)
    lcd.drawText(W / 2, HALF_H + 10, string.format("KILLS: %d", kills), CENTER + MIDSIZE + CUSTOM_COLOR)
  end

  return 0
end

return { init = init, run = run }
