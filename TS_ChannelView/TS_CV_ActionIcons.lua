-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ActionIcons.lua -- ChannelView's own icons for action buttons:
  line drawings on a 24 unit grid, drawn at any size in the bars' ink
  colours (normal, hover, and on the accent when a toggle is on) instead
  of REAPER's toolbar PNGs.

  They come from one file, TS_CV_ActionIcons.json, which the web
  companion's page reads too (it sits beside the page in reaper_www_root),
  so the two draw the same thing. Each icon has a key, a name, a family,
  the REAPER action it's meant for (when it has one) and up to four kinds
  of path:
    d   lines        fi  small solid parts
    ti  a 35% tint   da  dashed lines
  in SVG path syntax (M L H V C S A Z, either case).

  A bar's item names one as its icon with "cv:<key>" where a PNG would
  be a file name. AI.match finds the icon made for an action, so a
  button picked from the Action List, or copied from a REAPER toolbar,
  gets one without being asked.
--]]

local U = require("TS_CV_Util")

local AI = {}
local ImGui

function AI.attach(imgui) ImGui = imgui end

AI.PREFIX = "cv:"
AI.FILE = "TS_CV_ActionIcons.json"

local SEP = package.config:sub(1, 1)
local HERE = (debug.getinfo(1, "S").source:match("^@?(.*[\\/])")) or ""

-- ---------------------------------------------------------------------
-- pure: paths
-- ---------------------------------------------------------------------

local sin, cos, sqrt, abs, pi = math.sin, math.cos, math.sqrt, math.abs, math.pi
local atan = math.atan

-- The tokens of a path: command letters and numbers ("1.5-2" is two
-- numbers, ".5.5" too).
local function tokens(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("[MLHVCSAZmlhvcsaz]") then
      out[#out + 1] = c; i = i + 1
    elseif c:match("[%s,]") then
      i = i + 1
    else
      local lit = s:match("^[-+]?%d*%.?%d+[eE][-+]?%d+", i) or s:match("^[-+]?%d*%.?%d+", i)
      if not lit then return out end      -- anything else: stop here
      out[#out + 1] = tonumber(lit); i = i + #lit
    end
  end
  return out
end

-- An SVG arc as points (the start point not included).
local function arc_to(pts, x1, y1, rx, ry, phi, fa, fs, x2, y2)
  if rx == 0 or ry == 0 then pts[#pts + 1] = x2; pts[#pts + 1] = y2 return end
  rx, ry = abs(rx), abs(ry)
  phi = phi * pi / 180
  local cp, sp = cos(phi), sin(phi)
  local dx, dy = (x1 - x2) * 0.5, (y1 - y2) * 0.5
  local x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
  local lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
  if lam > 1 then local s = sqrt(lam); rx, ry = rx * s, ry * s end
  local num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
  local den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
  local co = (den > 0) and sqrt(math.max(0, num / den)) or 0
  if (fa ~= 0) == (fs ~= 0) then co = -co end
  local cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
  local cx = cp * cxp - sp * cyp + (x1 + x2) * 0.5
  local cy = sp * cxp + cp * cyp + (y1 + y2) * 0.5
  local t1 = atan((y1p - cyp) / ry, (x1p - cxp) / rx)
  local dt = atan((-y1p - cyp) / ry, (-x1p - cxp) / rx) - t1
  if fs == 0 and dt > 0 then dt = dt - 2 * pi
  elseif fs ~= 0 and dt < 0 then dt = dt + 2 * pi end
  local steps = math.max(2, math.ceil(abs(dt) / (pi / 8)))
  for k = 1, steps do
    local t = t1 + dt * k / steps
    local ex, ey = rx * cos(t), ry * sin(t)
    pts[#pts + 1] = cx + ex * cp - ey * sp
    pts[#pts + 1] = cy + ex * sp + ey * cp
  end
end

local function cubic_to(pts, x0, y0, x1, y1, x2, y2, x3, y3)
  local steps = 8
  for k = 1, steps do
    local t = k / steps
    local u = 1 - t
    local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
    pts[#pts + 1] = a * x0 + b * x1 + c * x2 + d * x3
    pts[#pts + 1] = a * y0 + b * y1 + c * y2 + d * y3
  end
end

-- A path as subpaths: { { pts = { x1, y1, x2, y2, ... }, closed = bool } }
-- in the icon's 24 unit space.
function AI.flatten(s)
  local t = tokens(s or "")
  local subs, cur = {}, nil
  local x, y, sx, sy = 0, 0, 0, 0
  local lcx, lcy = nil, nil            -- the last cubic's second control point
  local i, cmd = 1, nil
  local function num() local v = t[i]; i = i + 1; return v end
  local function start(nx, ny)
    cur = { pts = { nx, ny }, closed = false }
    subs[#subs + 1] = cur
    sx, sy = nx, ny
  end
  local function line(nx, ny)
    if not cur then start(x, y) end
    cur.pts[#cur.pts + 1] = nx; cur.pts[#cur.pts + 1] = ny
  end
  local function have(k)               -- k numbers waiting?
    for j = i, i + k - 1 do if type(t[j]) ~= "number" then return false end end
    return true
  end
  while i <= #t do
    if type(t[i]) == "string" then cmd = t[i]; i = i + 1
    elseif not cmd then return subs end
    local rel = cmd:match("%l") ~= nil
    local up = cmd:upper()
    local ox, oy = rel and x or 0, rel and y or 0
    if up == "Z" then
      if cur then cur.closed = true end
      x, y = sx, sy
      cur, lcx = nil, nil
      cmd = nil
    elseif up == "M" and have(2) then
      local nx, ny = num() + ox, num() + oy
      start(nx, ny); x, y = nx, ny
      cmd = rel and "l" or "L"           -- more pairs after M are lines
      lcx = nil
    elseif up == "L" and have(2) then
      local nx, ny = num() + ox, num() + oy
      line(nx, ny); x, y = nx, ny; lcx = nil
    elseif up == "H" and have(1) then
      local nx = num() + ox
      line(nx, y); x = nx; lcx = nil
    elseif up == "V" and have(1) then
      local ny = num() + (rel and y or 0)
      line(x, ny); y = ny; lcx = nil
    elseif up == "C" and have(6) then
      local x1, y1 = num() + ox, num() + oy
      local x2, y2 = num() + ox, num() + oy
      local x3, y3 = num() + ox, num() + oy
      if not cur then start(x, y) end
      cubic_to(cur.pts, x, y, x1, y1, x2, y2, x3, y3)
      x, y, lcx, lcy = x3, y3, x2, y2
    elseif up == "S" and have(4) then
      local x1, y1 = lcx and (2 * x - lcx) or x, lcx and (2 * y - lcy) or y
      local x2, y2 = num() + ox, num() + oy
      local x3, y3 = num() + ox, num() + oy
      if not cur then start(x, y) end
      cubic_to(cur.pts, x, y, x1, y1, x2, y2, x3, y3)
      x, y, lcx, lcy = x3, y3, x2, y2
    elseif up == "A" and have(7) then
      local rx, ry, phi, fa, fs = num(), num(), num(), num(), num()
      local nx, ny = num() + ox, num() + oy
      if not cur then start(x, y) end
      arc_to(cur.pts, x, y, rx, ry, phi, fa, fs, nx, ny)
      x, y = nx, ny; lcx = nil
    else
      return subs                       -- a command without its numbers
    end
  end
  return subs
end

-- ---------------------------------------------------------------------
-- the set
-- ---------------------------------------------------------------------

local set = nil           -- { list, by_key, by_cmd, by_script, families }
local cache = {}          -- key -> flattened shapes

-- Reads the icons from text (tests), or from the file: beside the
-- scripts, else beside the web page.
function AI.load(text)
  if not text then
    local tries = { AI.path, HERE .. AI.FILE }
    if reaper and reaper.GetResourcePath then
      tries[#tries + 1] = reaper.GetResourcePath() .. SEP .. "reaper_www_root" .. SEP .. AI.FILE
    end
    for k = 1, 3 do
      local p = tries[k]
      if p then
        local fh = io.open(p, "rb")
        if fh then text = fh:read("a"); fh:close(); break end
      end
    end
  end
  local data = U.json_decode(text or "")
  set = { list = {}, by_key = {}, by_cmd = {}, by_script = {}, families = {} }
  cache = {}
  local fam_of = {}
  for _, e in ipairs(type(data) == "table" and type(data.icons) == "table" and data.icons or {}) do
    if type(e) == "table" and type(e.k) == "string" then
      local ic = { key = e.k, name = e.n or e.k, family = e.f or "", cmd = e.c or "",
                   section = e.s or "main", toggle = e.t == 1, script = e.sc,
                   d = e.d or {}, fi = e.fi or {}, ti = e.ti or {}, da = e.da or {} }
      set.list[#set.list + 1] = ic
      set.by_key[ic.key] = ic
      if ic.cmd ~= "" and ic.section == "main" and not set.by_cmd[ic.cmd] then set.by_cmd[ic.cmd] = ic end
      if type(ic.script) == "string" then set.by_script[ic.script:lower()] = ic end
      local f = fam_of[ic.family]
      if not f then
        f = { name = ic.family, icons = {} }
        fam_of[ic.family] = f
        set.families[#set.families + 1] = f
      end
      f.icons[#f.icons + 1] = ic
    end
  end
  return #set.list
end

local function ensure() if not set then AI.load() end return set end

function AI.count() return #ensure().list end
function AI.families() return ensure().families end

-- Is this item's icon one of ours?
function AI.is(icon)
  return type(icon) == "string" and icon:sub(1, 3) == AI.PREFIX
end

function AI.get(icon)
  if not AI.is(icon) then return nil end
  return ensure().by_key[icon:sub(4)]
end

-- The icon made for an action: "cv:<key>", or nil. `cmd` is the stored
-- form ("40029", "_SWS_..."); `name_of` (optional) gives an action's
-- name, so a script is found by its file whatever its id here.
function AI.match(cmd, name_of)
  if type(cmd) ~= "string" or cmd == "" then return nil end
  local s = ensure()
  local ic = s.by_cmd[cmd]
  if not ic and cmd:sub(1, 3) == "_RS" and name_of then
    local name = name_of(cmd)
    local file = type(name) == "string" and name:match("([^/\\:]+%.%a+)%s*$")
    if file then ic = s.by_script[(file:gsub("^%s+", "")):lower()] end
  end
  return ic and (AI.PREFIX .. ic.key) or nil
end

-- ---------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------

local function shapes(ic)
  local c = cache[ic.key]
  if c then return c end
  c = {}
  for _, k in ipairs({ "d", "fi", "ti", "da" }) do
    local subs = {}
    for _, p in ipairs(ic[k]) do
      for _, sp in ipairs(AI.flatten(p)) do
        if #sp.pts >= 4 then subs[#subs + 1] = sp end
      end
    end
    c[k] = subs
  end
  cache[ic.key] = c
  return c
end
AI.shapes = shapes

local function with_alpha(col, f)
  local a = col & 0xFF
  return (col & 0xFFFFFF00) | math.floor(a * f + 0.5)
end

-- The dashes of a subpath placed at x, y, scale s: { { x, y, x, y ... } }
-- in screen space, on_px drawn then off_px left out, along its length.
local function dashes(sp, x, y, s, on_px, off_px)
  local out = {}
  local p = sp.pts
  local pts = {}
  for k = 1, #p, 2 do pts[#pts + 1] = { x + p[k] * s, y + p[k + 1] * s } end
  if sp.closed then pts[#pts + 1] = pts[1] end
  local drawing, left = true, on_px
  local seg = nil
  for k = 1, #pts - 1 do
    local ax, ay = pts[k][1], pts[k][2]
    local bx, by = pts[k + 1][1], pts[k + 1][2]
    local len = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local pos = 0
    while len - pos > 1e-6 do
      local step = math.min(left, len - pos)
      local t1 = (pos + step) / len
      if drawing then
        if not seg then
          local t0 = pos / len
          seg = { ax + (bx - ax) * t0, ay + (by - ay) * t0 }
          out[#out + 1] = seg
        end
        seg[#seg + 1] = ax + (bx - ax) * t1
        seg[#seg + 1] = ay + (by - ay) * t1
      end
      pos = pos + step
      left = left - step
      if left <= 1e-6 then
        drawing = not drawing
        left = drawing and on_px or off_px
        seg = nil
      end
    end
  end
  return out
end
AI.dashes = dashes

-- Draws icon `icon` ("cv:<key>") into the square at x, y, `size` px, in
-- `col`. Returns true when there was such an icon.
function AI.draw(dl, icon, x, y, size, col)
  local ic = AI.get(icon)
  if not ic then return false end
  local sh = shapes(ic)
  local s = size / 24
  local th = math.max(1.0, math.min(2.2, 1.5 * size / 18))
  local closed = ImGui.DrawFlags_Closed
  local fill = ImGui.DrawList_PathFillConcave or ImGui.DrawList_PathFillConvex
  local function path(sp)
    ImGui.DrawList_PathClear(dl)
    local p = sp.pts
    for k = 1, #p, 2 do ImGui.DrawList_PathLineTo(dl, x + p[k] * s, y + p[k + 1] * s) end
  end
  if #sh.ti > 0 then
    local tcol = with_alpha(col, 0.35)
    for _, sp in ipairs(sh.ti) do
      if #sp.pts >= 6 then path(sp); fill(dl, tcol) end
    end
  end
  for _, sp in ipairs(sh.d) do
    path(sp)
    ImGui.DrawList_PathStroke(dl, col, sp.closed and closed or 0, th)
  end
  for _, sp in ipairs(sh.da) do
    for _, seg in ipairs(dashes(sp, x, y, s, 3.4 * size / 18, 3.0 * size / 18)) do
      ImGui.DrawList_PathClear(dl)
      for k = 1, #seg, 2 do ImGui.DrawList_PathLineTo(dl, seg[k], seg[k + 1]) end
      ImGui.DrawList_PathStroke(dl, col, 0, th)
    end
  end
  for _, sp in ipairs(sh.fi) do
    if #sp.pts >= 6 then
      path(sp); fill(dl, col)
      path(sp); ImGui.DrawList_PathStroke(dl, col, closed, th * 0.5)
    end
  end
  return true
end

return AI
