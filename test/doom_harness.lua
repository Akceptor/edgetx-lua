-- Headless test harness for TOOLS/Doom.lua
-- Usage: lua test/doom_harness.lua [path/to/Doom.lua]
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local PATH = arg and arg[1] or (here .. "/../TOOLS/Doom.lua")

local BUDGET_MAX = 150000
local failures = 0

local function check(name, cond, detail)
  if cond then
    print("PASS  " .. name .. (detail and ("  (" .. detail .. ")") or ""))
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  (" .. detail .. ")") or ""))
  end
end

local function skip(name) print("SKIP  " .. name .. "  (no _state in this build)") end

-- ── Mocks ─────────────────────────────────────────────────────────────────────
local G  -- per-scenario environment

local function packRGB(r, g, b)
  return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
end

local function newEnv(checkBounds)
  G = { clock = 0, vals = {}, calls = 0, violations = 0, firstViolation = nil }
  LCD_W, LCD_H = 480, 320
  CUSTOM_COLOR, CENTER, RIGHT, SMLSIZE, MIDSIZE, DBLSIZE = 0x1000, 0x2000, 0x4000, 0x0100, 0x0200, 0x0400
  local function count() G.calls = G.calls + 1 end
  lcd = {
    RGB = packRGB,
    setColor = count, drawLine = count, drawText = count,
    drawCircle = count, drawFilledCircle = count, clear = count,
  }
  if checkBounds then
    lcd.drawFilledRectangle = function(x, y, w, h)
      G.calls = G.calls + 1
      if x < 0 or y < 0 or x + w > LCD_W or y + h > LCD_H then
        G.violations = G.violations + 1
        G.firstViolation = G.firstViolation or string.format("%s,%s,%s,%s", x, y, w, h)
      end
    end
  else
    lcd.drawFilledRectangle = count
  end
  getTime = function() return G.clock end
  getValue = function(src) return G.vals[src] or 0 end
end

local function load(checkBounds)
  newEnv(checkBounds)
  math.randomseed(1)
  local mod = assert(loadfile(PATH))()
  mod.init()
  return { mod = mod, instr = {}, lcdc = {} }
end

local hookCount
local function hook() hookCount = hookCount + 1 end

local function frame(S, dt)
  G.clock = G.clock + dt
  local c0 = G.calls
  hookCount = 0
  debug.sethook(hook, "", 1000)
  local ok, err = pcall(S.mod.run, 0)
  debug.sethook()
  if not ok then error("run() failed: " .. tostring(err), 0) end
  S.instr[#S.instr + 1] = hookCount * 1000
  S.lcdc[#S.lcdc + 1] = G.calls - c0
end

local function setSticks(rot, fwd, str, sf)
  G.vals.ch1, G.vals.ch2, G.vals.ch4, G.vals.sf = rot, fwd, str, sf or -1024
end

local function leaveSplash(S, dt)
  setSticks(0, 1024, 0)
  frame(S, dt)
  setSticks(0, 0, 0)
end

local function stats(S, from)
  local sum, max, lsum, lmax = 0, 0, 0, 0
  local n = #S.instr - from + 1
  for i = from, #S.instr do
    sum = sum + S.instr[i]; if S.instr[i] > max then max = S.instr[i] end
    lsum = lsum + S.lcdc[i]; if S.lcdc[i] > lmax then lmax = S.lcdc[i] end
  end
  return sum / n, max, lsum / n, lmax
end

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
local function wallAt(x, y)
  local cx, cy = math.floor(x), math.floor(y)
  if cx < 0 or cy < 0 or cx >= 16 or cy >= 12 then return true end
  return MAP[cy + 1]:sub(cx + 1, cx + 1) == "#"
end

local function scriptedInput(i)
  local rot = math.floor(1024 * math.sin(i / 20))
  local fwd = (i % 200 < 150) and 1024 or -700
  local m = i % 90
  local str = (m < 30) and 800 or ((m < 60) and -800 or 0)
  local sf = ((i // 20) % 2 == 0) and 1024 or -1024
  setSticks(rot, fwd, str, sf)
end

print("Doom harness: " .. PATH)

-- ── a. idle ───────────────────────────────────────────────────────────────────
do
  local S = load(true)
  for _ = 1, 5 do setSticks(0, 0, 0); frame(S, 2) end
  leaveSplash(S, 2)
  local ok, err = pcall(function() for _ = 1, 600 do frame(S, 2) end end)
  check("a. idle 600 frames no error", ok, err)
  check("a. idle no out-of-bounds rects", G.violations == 0, G.firstViolation)
end

-- ── b. scripted run ───────────────────────────────────────────────────────────
do
  local S = load(true)
  leaveSplash(S, 2)
  local ok, err = pcall(function()
    for i = 1, 600 do
      scriptedInput(i)
      frame(S, 2)
      if S.mod._state then
        local x, y = S.mod._state()
        if wallAt(x, y) then error(string.format("player in wall at frame %d (%.3f, %.3f)", i, x, y), 0) end
      end
    end
  end)
  check("b. scripted run: no error, player never in wall", ok, err)
  check("b. scripted run: no out-of-bounds rects", G.violations == 0, G.firstViolation)
  if not S.mod._state then skip("b. wall check") end
end

-- ── c. low fps equivalence ────────────────────────────────────────────────────
local function walkDistance(dt, frames, fwdVal)
  local S = load(true)
  if not S.mod._state then return nil end
  leaveSplash(S, dt)
  local x0, y0 = S.mod._state()
  setSticks(0, fwdVal, 0)
  for _ = 1, frames do frame(S, dt) end
  local x1, y1 = S.mod._state()
  return math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
end

-- 1 s simulated, start (8.5,6.5) heading east: the wall at x=14 is 5.5 away, full speed covers ~4
do
  local d50 = walkDistance(2, 50, 1024)
  if d50 then
    local d10 = walkDistance(10, 10, 1024)
    check("c. 50fps walks ~4 cells in 1s", d50 > 3.5 and d50 < 4.5, string.format("%.3f", d50))
    check("c. low-fps distance within 30% of 50fps", math.abs(d10 - d50) <= 0.3 * d50,
      string.format("50fps=%.3f 5fps=%.3f", d50, d10))
  else
    skip("c. low-fps equivalence")
  end
end

-- ── d. adaptive resolution ────────────────────────────────────────────────────
do
  local S = load(true)
  if S.mod._state then
    leaveSplash(S, 10)
    local peak = 0
    for _ = 1, 40 do
      frame(S, 10)
      local _, _, _, _, _, cw = S.mod._state(); if cw > peak then peak = cw end
    end
    check("d. colW rises above 2 at ~10fps", peak > 2, "peak colW=" .. peak)
    for _ = 1, 400 do frame(S, 2) end
    local _, _, _, _, _, cw = S.mod._state()
    check("d. colW returns to 2 at ~50fps", cw == 2, "colW=" .. cw)
    check("d. no out-of-bounds rects at any colW", G.violations == 0, G.firstViolation)
  else
    skip("d. adaptive resolution")
  end
end

-- ── e. proportional stick ─────────────────────────────────────────────────────
do
  local full = walkDistance(2, 50, 1024)
  if full then
    local half = walkDistance(2, 50, 537)  -- (537-50)/(1024-50) = 0.5
    check("e. half deflection ~ half distance", math.abs(half / full - 0.5) < 0.08,
      string.format("full=%.3f half=%.3f ratio=%.3f", full, half, half / full))
  else
    skip("e. proportional stick")
  end
end

-- ── Budget ────────────────────────────────────────────────────────────────────
do
  local S = load(false)
  leaveSplash(S, 2)
  local from = #S.instr + 1
  for i = 1, 600 do scriptedInput(i); frame(S, 2) end
  local avg, max, lavg, lmax = stats(S, from)
  print(string.format("BUDGET gameplay (600 frames, 50fps clock, colW=2): instr avg=%.0f max=%.0f  lcd calls avg=%.1f max=%d",
    avg, max, lavg, lmax))
  check("budget: max instructions/frame <= " .. BUDGET_MAX, max <= BUDGET_MAX, string.format("%.0f", max))
end

if failures > 0 then
  print(failures .. " check(s) FAILED")
  os.exit(1)
end
print("All checks passed")
