-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_KnobParts.lua -- knobs built from parts (C.KNOB_STYLES entries with
  `parts`): a body with its profile, grip, material and top; a pointer; a
  skirt with its print; and extras (washer, nut, an inner cap).

  One light, from the top left, for everything: rings and bevels are
  shaded by the angle they face, so highlights stay put while the knob
  turns, and only the pointer, grip and print turn with it.

  A look (`parts`) is a table:
    profile  straight | slight | tapered | domed
    grip     smooth | fluted | knurled | ridged | coin | grooves ;  n (count)
    mat      plastic | gloss | matte | rubber | metal | chrome | enamel
    side     the sides' colour (nil: the body's, darker); tilt (0..0.15)
    top      flat | insert | recessed ;  insert (colour)
    face     dome (a soft rounded top) | flat (flush, evenly lit)
    rim      a ring of this colour round the top's edge
    ptr      line | dot | inset | notch | chicken | wing | skirtline | none ;  ink
    skirt    plain | printed | numbered | dial ;  scol, smat (plastic |
             matte | metal | clear), sr (its radius, of the body's),
             sgrip (knurled), sink (its print's colour)
    washer, nut   true for a turned washer, a hex nut under the knob
    inner    { r, col, mat = "bead", screws = true }: a cap set inside the
             body, with a groove round it
  Colours are 0xRRGGBBAA. The knob's chosen colour (the Style line's cap)
  is the body's.
--]]

local U = require("TS_CV_Util")
local LT = require("TS_CV_Light")

local KP = {}
local ImGui

function KP.attach(imgui) ImGui = imgui end

local TAU     = math.pi * 2
local A_MIN   = math.pi * 0.75
local A_SPAN  = math.pi * 1.5
local LIGHT_A = math.atan(-0.8, -0.6)
local BLACK, WHITE = 0x000000ff, 0xffffffff

local function mix(a, b, t)
  t = math.max(0, math.min(1, t))
  local out = 0
  for _, sh in ipairs({ 24, 16, 8 }) do
    local x, y = (a >> sh) & 0xff, (b >> sh) & 0xff
    out = out | (math.floor(x + (y - x) * t + 0.5) << sh)
  end
  return out | (a & 0xff)
end
local function alpha(c, a) return U.with_alpha(c, a) end
-- how much light a surface facing angle t catches: 0 away, 1 toward
local function lit(t) return (math.cos(t - LIGHT_A) + 1) * 0.5 end

-- View > Lighting: how strongly the light models a knob, 1 the default; 2
-- a pronounced, studio-lit fall from bright top left to deep bottom right
KP.LIGHT = 1
-- push a pair of shades apart (L > 1) or together (L < 1)
local function contrast(lo, hi)
  local L = KP.LIGHT
  if L == 1 then return lo, hi end
  if L > 1 then
    return mix(lo, BLACK, 0.40 * (L - 1)), mix(hi, WHITE, 0.40 * (L - 1))
  end
  local mid = mix(lo, hi, 0.5)
  return mix(mid, lo, L), mix(mid, hi, L)
end

-- A lit band: the part of a disc of radius R that something smaller drawn
-- over it leaves showing (a knob's side, a skirt, a washer), lit from the
-- top left -- `lo` its shaded side, `hi` its lit side. Three discs, offset
-- against and toward the light, rather than a ring segment by segment: a
-- knob is drawn every frame, so every call counts.
local function lit_ring(dl, cx, cy, R, ri, lo, hi, n, glint, fd)
  lo, hi = contrast(lo, hi)
  local d = math.max(0.6, R * 0.05)
  local ux, uy = math.cos(LIGHT_A), math.sin(LIGHT_A)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, R, fd(lo), 0)
  ImGui.DrawList_AddCircleFilled(dl, cx + ux * d, cy + uy * d, R - d, fd(hi), 0)
  ImGui.DrawList_AddCircleFilled(dl, cx - ux * d * 0.25, cy - uy * d * 0.25, R - d * 1.7, fd(mix(lo, hi, 0.5)), 0)
  if glint then
    -- polished metal shines a little on the far side too
    ImGui.DrawList_PathArcTo(dl, cx, cy, R - d * 0.8, LIGHT_A + math.pi - 0.5, LIGHT_A + math.pi + 0.5, 8)
    ImGui.DrawList_PathStroke(dl, fd(alpha(hi, math.floor(0x90 * glint))), 0, math.max(1.0, d))
  end
end

-- a disc lit from the top left: a soft gradient from a little darker at
-- the bottom right to a little lighter toward the light, drawn as discs
-- stacked toward it, each a shade lighter; `lift` how much lighter the
-- lit side gets (a satin top barely, a gloss one more)
local GRAD_STEPS = 10
local function lit_disc(dl, cx, cy, R, col, fd, lift)
  lift = lift or 0
  local L = KP.LIGHT
  local dark = mix(col, BLACK, math.min(0.80, 0.32 * L))
  local light = mix(col, WHITE, math.min(0.85, (0.06 + 0.16 * lift) * L + 0.10 * math.max(0, L - 1)))
  local ux, uy = math.cos(LIGHT_A), math.sin(LIGHT_A)
  local n = (R < 6) and 3 or ((R < 16) and 6 or GRAD_STEPS)
  for i = 0, n - 1 do
    local t = i / (n - 1)
    local r = R * (1 - 0.62 * t)
    local off = R * 0.30 * t
    -- the outer half of the steps runs dark to the colour, the inner to the light
    local c = (t < 0.35) and mix(dark, col, t / 0.35) or mix(col, light, (t - 0.35) / 0.65)
    ImGui.DrawList_AddCircleFilled(dl, cx + ux * off, cy + uy * off, r, fd(c), 40)
  end
end

-- A flat face, flush with the top of the knob: an even, gentle fall of
-- light across it (bands at right angles to the light, not discs stacked
-- toward it, which read as a dome), its edge catching the light on the
-- top left and dropping away on the bottom right.
local function flat_face(dl, cx, cy, R, col, fd, lift)
  local L = KP.LIGHT
  local up = math.max(0, L - 1)
  local dark = mix(col, BLACK, math.min(0.70, 0.14 * math.min(1, L) + 0.18 * up))
  local light = mix(col, WHITE, math.min(0.70, (0.05 + 0.10 * (lift or 0)) * math.min(1, L) + 0.12 * up))
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, R, fd(mix(dark, light, 0.5)), 0)
  local n = (R < 10) and 3 or ((KP.LIGHT > 1 and R >= 20) and 12 or 6)
  for i = 0, n - 1 do
    local s0, s1 = -R + 2 * R * i / n, -R + 2 * R * (i + 1) / n
    local f0 = math.acos(math.max(-1, math.min(1, s0 / R)))
    local f1 = math.acos(math.max(-1, math.min(1, s1 / R)))
    ImGui.DrawList_PathArcTo(dl, cx, cy, R, LIGHT_A + f1, LIGHT_A + f0, 10)
    ImGui.DrawList_PathArcTo(dl, cx, cy, R, LIGHT_A - f0, LIGHT_A - f1, 10)
    ImGui.DrawList_PathFillConvex(dl, fd(mix(dark, light, (i + 0.5) / n)))
  end
  local w = math.max(1.0, R * 0.05)
  ImGui.DrawList_PathArcTo(dl, cx, cy, R - w * 0.5, LIGHT_A - 1.2, LIGHT_A + 1.2, 16)
  ImGui.DrawList_PathStroke(dl, fd(alpha(WHITE, 0x38)), 0, w)
  ImGui.DrawList_PathArcTo(dl, cx, cy, R - w * 0.5, LIGHT_A + math.pi - 1.2, LIGHT_A + math.pi + 1.2, 16)
  ImGui.DrawList_PathStroke(dl, fd(alpha(BLACK, 0x30)), 0, w)
end

-- With View > Lighting above 100%: the whole knob washed with the light,
-- as in a studio photo -- bright on the top left, falling away to deep on
-- the bottom right -- in bands at right angles to the light over the
-- disc of radius R.
local function light_wash(dl, cx, cy, R, fd)
  local up = KP.LIGHT - 1
  if up <= 0 or R < 4 then return end
  local wa, ba = math.min(0x80, 0x48 * up), math.min(0x80, 0x40 * up)
  local n = (R < 12) and 4 or ((R < 20) and 8 or 14)
  for i = 0, n - 1 do
    local s0, s1 = -R + 2 * R * i / n, -R + 2 * R * (i + 1) / n
    local f0 = math.acos(math.max(-1, math.min(1, s0 / R)))
    local f1 = math.acos(math.max(-1, math.min(1, s1 / R)))
    -- i = 0 is the band nearest the light
    local t = (i + 0.5) / n
    local col = (t < 0.5) and alpha(WHITE, math.floor(wa * (0.5 - t) * 2))
                           or alpha(BLACK, math.floor(ba * (t - 0.5) * 2))
    if (col & 0xff) > 0 then
      ImGui.DrawList_PathArcTo(dl, cx, cy, R, LIGHT_A + f1, LIGHT_A + f0, 10)
      ImGui.DrawList_PathArcTo(dl, cx, cy, R, LIGHT_A - f0, LIGHT_A - f1, 10)
      ImGui.DrawList_PathFillConvex(dl, fd(col))
    end
  end
end

-- the spun-metal sheen: two narrow bright wedges across the light
local function sheen(dl, cx, cy, R, col, fd)
  local d = LIGHT_A + math.pi * 0.5
  local w = math.rad(14)
  for _, s in ipairs({ d, d + math.pi }) do
    ImGui.DrawList_AddTriangleFilled(dl, cx, cy,
      cx + math.cos(s - w) * R, cy + math.sin(s - w) * R,
      cx + math.cos(s + w) * R, cy + math.sin(s + w) * R,
      fd(U.is_light(col) and 0xffffff55 or 0xffffff26))
  end
  if R >= 7 then
    for ring = 0.35, 0.8, 0.22 do
      ImGui.DrawList_AddCircle(dl, cx, cy, R * ring, fd(0x0000000e), 24, 1.0)
    end
  end
end

-- a mirror: the sky above, the dark ground below, a crisp horizon
local function chrome_disc(dl, cx, cy, R, col, fd)
  local sky, ground = mix(col, WHITE, 0.55), mix(col, BLACK, 0.55)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, R, fd(ground), 40)
  ImGui.DrawList_PathArcTo(dl, cx, cy, R, math.pi * 1.06, math.pi * 1.94, 24)
  ImGui.DrawList_PathFillConvex(dl, fd(sky))
  ImGui.DrawList_AddCircleFilled(dl, cx - R * 0.3, cy - R * 0.45, R * 0.22, fd(alpha(WHITE, 0x70)), 16)
end

-- shared with the concentric knob (TS_CV_Widgets.dual_face) and the
-- other styles, so everything is lit alike
KP.lit_ring, KP.lit_disc, KP.flat_face, KP.light_wash = lit_ring, lit_disc, flat_face, light_wash

-- a polygon from flat {x, y, ...}, filled (concave allowed)
local function poly(dl, pts, col)
  for i = 1, #pts, 2 do ImGui.DrawList_PathLineTo(dl, pts[i], pts[i + 1]) end
  if ImGui.DrawList_PathFillConcave then ImGui.DrawList_PathFillConcave(dl, col)
  else ImGui.DrawList_PathFillConvex(dl, col) end
end

-- a convex polygon from flat {x, y, ...}, filled (cheaper than concave)
local function cpoly(dl, pts, col)
  for i = 1, #pts, 2 do ImGui.DrawList_PathLineTo(dl, pts[i], pts[i + 1]) end
  ImGui.DrawList_PathFillConvex(dl, col)
end

-- The outline round two circles (x1, y1, r1) and (x2, y2, r2): convex, a
-- pointer's footprint when one is its broad tail and the other its tip.
local function hull(x1, y1, r1, x2, y2, r2, n)
  local dx, dy = x2 - x1, y2 - y1
  local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
  local a = math.atan(dy, dx)
  local psi = math.acos(math.max(-1, math.min(1, (r1 - r2) / d)))
  n = n or 8
  local pts = {}
  for i = 0, n do
    local q = a - psi + 2 * psi * i / n
    pts[#pts + 1] = x2 + math.cos(q) * r2; pts[#pts + 1] = y2 + math.sin(q) * r2
  end
  for i = 0, n * 2 do
    local q = a + psi + (2 * math.pi - 2 * psi) * i / (n * 2)
    pts[#pts + 1] = x1 + math.cos(q) * r1; pts[#pts + 1] = y1 + math.sin(q) * r1
  end
  return pts
end

-- how much light a material's top catches (KnobParts' satin by default)
local SHINE = { gloss = 0.38, plastic = 0.20, matte = 0.08, rubber = 0.04, metal = 0.30, chrome = 0.45, enamel = 0.30 }
local STREAK = { gloss = 0x70, plastic = 0x26, matte = 0x0c, rubber = 0x06, metal = 0x40, chrome = 0x80, enamel = 0x40 }

-- A pointer knob standing on the panel -- a chicken-head, the pointer
-- style -- modelled rather than flat: its shadow in the shape of it, its
-- sides showing below its top, a bevel round the top lit on the light's
-- side, the top falling from light to shade, a long highlight along its
-- ridge (sharp on gloss, broad and faint on satin), and the line inlaid
-- along it. g: tail (the tail circle's centre, behind the centre), rt
-- (its radius), tip, rp (the tip circle's centre and radius), h (how
-- much side shows), hub (a round cap over the middle, or nil), l0, l1 (the
-- inlaid line, along the pointer), ink. o: hw, fd, lift.
function KP.pointer_body(dl, cx, cy, a, g, body, mat, o)
  local fd = o.fd or function(c) return c end
  local ca, sa = math.cos(a), math.sin(a)
  local tx, ty = cx - ca * g.tail, cy - sa * g.tail
  local px, py = cx + ca * g.tip, cy + sa * g.tip
  local function foot(grow, ox, oy, col)
    cpoly(dl, hull(tx + ox, ty + oy, math.max(0.3, g.rt + grow), px + ox, py + oy, math.max(0.3, g.rp + grow)), col)
  end
  local L = KP.LIGHT
  -- its shadow, the shape of it
  if (o.hw or 0) > 0 then
    local layers, ca_ = LT.drop((g.tail + g.tip) * 0.45, o.hw, o.lift)
    for _, l in ipairs(layers) do foot(l[3], l[1], l[2], l[4]) end
    if ca_ > 0 then foot(0.7, -LT.UX * 0.6, -LT.UY * 0.6 + g.h, ca_) end
  end
  -- its sides, below the top: darker the lower
  local n = (g.rt < 8) and 2 or 4
  for j = n, 1, -1 do
    local t = j / n
    foot(0, 0, g.h * t, fd(mix(body, BLACK, 0.30 + 0.30 * t)))
  end
  -- the bevel round the top: lit toward the light, dark away from it
  local shine = SHINE[mat or "plastic"] or 0.20
  local bv = math.max(0.6, g.rt * 0.10)
  local lo, hi = contrast(mix(body, BLACK, 0.32), mix(body, WHITE, shine))
  foot(0, -LT.UX * bv * 0.6, -LT.UY * bv * 0.6, fd(lo))
  foot(0, LT.UX * bv * 0.6, LT.UY * bv * 0.6, fd(hi))
  -- the top: light falling across it, toward the light
  local steps = (g.rt < 8) and 3 or 7
  local dark = mix(body, BLACK, math.min(0.6, 0.20 * L))
  local light = mix(body, WHITE, math.min(0.8, (0.05 + 0.5 * shine) * L))
  for i = 0, steps - 1 do
    local t = i / (steps - 1)
    local shrink = bv + g.rt * 0.50 * t
    local off = g.rt * 0.22 * t
    local c = (t < 0.3) and mix(dark, body, t / 0.3) or mix(body, light, (t - 0.3) / 0.7)
    foot(-shrink, LT.UX * off, LT.UY * off, fd(c))
  end
  -- the highlight along its ridge, on the side toward the light
  local vx, vy = -sa, ca
  if vx * LT.UX + vy * LT.UY < 0 then vx, vy = -vx, -vy end
  local sa_ = STREAK[mat or "plastic"] or 0x26
  if sa_ > 0 then
    local so = g.rt * 0.34
    local x1, y1 = tx + ca * g.rt * 0.15 + vx * so, ty + sa * g.rt * 0.15 + vy * so
    local x2, y2 = cx + ca * g.tip * 0.78 + vx * so * 0.35, cy + sa * g.tip * 0.78 + vy * so * 0.35
    cpoly(dl, hull(x1, y1, g.rt * 0.16, x2, y2, math.max(0.3, g.rp * 0.35), 6), fd(alpha(WHITE, math.floor(sa_ * 0.45))))
    if mat == "gloss" or mat == "chrome" or mat == "enamel" then
      cpoly(dl, hull(x1, y1, g.rt * 0.06, x2, y2, 0.3, 6), fd(alpha(WHITE, sa_)))
    end
  end
  -- the line inlaid along it: its groove, then the line
  if g.l1 and g.l1 > g.l0 then
    local w = math.max(1.2, g.rt * 0.16)
    local x1, y1 = cx + ca * g.l0, cy + sa * g.l0
    local x2, y2 = cx + ca * g.l1, cy + sa * g.l1
    ImGui.DrawList_AddLine(dl, x1, y1 + 0.6, x2, y2 + 0.6, fd(alpha(BLACK, 0x70)), w + 0.8)
    ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, fd(g.ink), w)
  end
  -- a round cap over the middle
  if g.hub then
    local hr = g.hub
    ImGui.DrawList_AddCircleFilled(dl, cx - LT.UX * hr * 0.05, cy - LT.UY * hr * 0.05 + g.h * 0.3, hr * 1.02, fd(alpha(BLACK, 0x38)), 0)
    lit_ring(dl, cx, cy, hr, hr * 0.86, mix(body, BLACK, 0.40), mix(body, WHITE, shine), 32, nil, fd)
    lit_disc(dl, cx, cy, hr * 0.86, body, fd, shine)
    if sa_ >= 0x40 then
      ImGui.DrawList_AddCircleFilled(dl, cx + LT.UX * hr * 0.42, cy + LT.UY * hr * 0.42, hr * 0.16, fd(alpha(WHITE, sa_)), 12)
    end
  end
end

-- A look's outer reach, in body radii: what the knob's drawn radius r has
-- to hold.
function KP.reach(p)
  local e = 1
  if p.skirt then e = math.max(e, p.sr or 1.42) end
  if p.washer then e = math.max(e, (p.skirt and (p.sr or 1.42) or 1) * 1.14) end
  if p.ptr == "chicken" then e = math.max(e, 1.18) end
  if p.ptr == "wing" then e = math.max(e, 1.40) end
  return e
end

-- the print on a skirt, turning with the knob
local function skirt_print(ctx, dl, cx, cy, R, Rs, a, v, p, fd)
  local ink = p.sink or (U.is_light(p.scol or BLACK) and 0x1a1a1aff or 0xf0efe9ff)
  local w = math.max(1.0, R * 0.05)
  if p.skirt == "printed" or p.skirt == "numbered" then
    local n = (p.skirt == "printed") and 20 or 10
    for k = 0, n do
      local t = a + A_SPAN * (k / n - v)
      local major = (p.skirt == "numbered") or (k % 5 == 0)
      local r0 = major and (R * 1.08) or (R + (Rs - R) * 0.35)
      ImGui.DrawList_AddLine(dl, cx + math.cos(t) * r0, cy + math.sin(t) * r0,
        cx + math.cos(t) * Rs * 0.95, cy + math.sin(t) * Rs * 0.95, fd(ink), w)
    end
  elseif p.skirt == "dial" then
    -- ticks every fifth of a number, numbers 0-10 rising anticlockwise,
    -- read against a fixed index at the top
    local span = math.rad(300)
    local top = -math.pi * 0.5
    -- the fifths only where there's room for them
    for k = 0, 50, (Rs >= 30) and 1 or 5 do
      local t = top - span * (k / 50 - v)
      local major = k % 5 == 0
      local r0 = Rs * (major and 0.78 or 0.86)
      ImGui.DrawList_AddLine(dl, cx + math.cos(t) * r0, cy + math.sin(t) * r0,
        cx + math.cos(t) * Rs * 0.93, cy + math.sin(t) * Rs * 0.93, fd(ink), major and w or math.max(1.0, w * 0.6))
    end
  end
  -- numbers, upright, when there's room for them
  if (p.skirt == "numbered" or p.skirt == "dial") and ctx and (Rs - R) >= 12 then
    local step = (p.skirt == "dial") and 2 or 2
    for k = 0, 10, step do
      local t
      if p.skirt == "dial" then t = -math.pi * 0.5 - math.rad(300) * (k / 10 - v)
      else t = a + A_SPAN * (k / 10 - v) end
      -- between the body's edge and the ticks, clear of both
      local rr = (p.skirt == "dial") and (R + Rs * 0.78) * 0.5 or (R + Rs) * 0.5
      local s = tostring(k)
      local tw, th = ImGui.CalcTextSize(ctx, s)
      ImGui.DrawList_AddText(dl, cx + math.cos(t) * rr - tw * 0.5, cy + math.sin(t) * rr - th * 0.5, fd(ink), s)
    end
  end
end

-- The knob `p` at (cx, cy), drawn radius r, at `value` (0..1). o: cap (the
-- body's colour, overriding the look's), hot, dim, hw (the 3D effect's
-- strength: shadows when > 0), ctx (for numbers on a skirt), shadow (a
-- function drawing a disc's shadow).
function KP.draw(dl, cx, cy, r, value, p, o)
  o = o or {}
  local v = math.max(0, math.min(1, value or 0))
  local a = A_MIN + A_SPAN * v
  local ca, sa = math.cos(a), math.sin(a)
  local function fd(col) return o.dim and U.with_alpha(col, 0x70) or col end
  local R = r / KP.reach(p)
  local body = o.cap or p.col or 0x26282bff
  if o.hot then body = U.lighten(body, 0.07) end
  local side = p.side or mix(body, BLACK, 0.40)
  local ink = p.ink or (U.is_light(body) and 0x1d1e20ff or 0xf3f3f1ff)
  local Rs = p.skirt and R * (p.sr or 1.42) or R
  local outer = p.washer and Rs * 1.14 or Rs

  -- its shadow: as usual, longer for a tall knob, only the seam for one sat flush
  -- (a bare chicken-head casts one the shape of it, drawn with it)
  if o.shadow and (o.hw or 0) > 0 and not (p.ptr == "chicken" and not p.skirt and not p.washer) then
    o.shadow(dl, cx, cy, (p.skirt == nil and p.ptr ~= "wing") and R or outer,
      (p.shadow == "tall" and 1.7) or (p.shadow == "none" and 0) or 1)
  end

  -- a turned washer, a hex nut
  if p.washer then
    lit_ring(dl, cx, cy, outer, Rs * 0.98, 0x6c7075ff, 0xe2e4e6ff, 40, 0.5, fd)
    ImGui.DrawList_AddCircle(dl, cx, cy, outer, fd(0x00000060), 40, 1.0)
  end
  if p.nut then
    ImGui.DrawList_AddNgonFilled(dl, cx, cy, Rs * 1.12, fd(0x8d9196ff), 6)
    ImGui.DrawList_AddNgon(dl, cx, cy, Rs * 1.12, fd(0x00000070), 6, 1.0)
  end

  -- the skirt
  if p.skirt then
    local scol = p.scol or mix(body, BLACK, 0.2)
    if p.smat == "clear" then
      ImGui.DrawList_AddCircleFilled(dl, cx, cy, Rs, fd(alpha(0xe8ecefff, 0x2a)), 48)
      ImGui.DrawList_AddCircle(dl, cx, cy, Rs - 0.5, fd(alpha(WHITE, 0x70)), 48, 1.2)
      ImGui.DrawList_AddCircle(dl, cx, cy, Rs * 0.86, fd(alpha(WHITE, 0x22)), 48, 1.0)
    else
      local metal = p.smat == "metal"
      local k = (p.smat == "matte") and 0.08 or (metal and 0.45 or 0.14)
      lit_ring(dl, cx, cy, Rs, R * 0.9, mix(scol, BLACK, k), mix(scol, WHITE, k), 48, metal and 0.6 or nil, fd)
      ImGui.DrawList_AddCircle(dl, cx, cy, Rs, fd(0x00000070), 48, 1.0)
    end
    if p.sgrip == "knurled" then
      local nk = math.min(90, math.floor(Rs * 2.2))
      for i = 0, nk - 1 do
        local t = a + i * TAU / nk
        ImGui.DrawList_AddLine(dl, cx + math.cos(t) * Rs * 0.95, cy + math.sin(t) * Rs * 0.95,
          cx + math.cos(t) * Rs, cy + math.sin(t) * Rs, fd(0x00000050), 1.0)
      end
    end
    skirt_print(o.ctx, dl, cx, cy, R, Rs, a, v, p, fd)
  end

  -- fins through the body (a wing knob): their sides, then their tops
  local tilt = (p.tilt or 0) * R
  if p.ptr == "wing" then
    local fl, fw = R * 1.38, R * 0.20
    local vx, vy = -sa * fw, ca * fw
    local x1, y1, x2, y2 = cx + ca * fl, cy + sa * fl, cx - ca * fl, cy - sa * fl
    ImGui.DrawList_AddQuadFilled(dl, x1 + vx, y1 + vy, x1 - vx, y1 - vy, x2 - vx, y2 - vy, x2 + vx, y2 + vy, fd(side))
    local fy = -tilt * 0.6
    ImGui.DrawList_AddQuadFilled(dl, x1 + vx * 0.85, y1 + vy * 0.85 + fy, x1 - vx * 0.85, y1 - vy * 0.85 + fy,
      x2 - vx * 0.85, y2 - vy * 0.85 + fy, x2 + vx * 0.85, y2 + vy * 0.85 + fy, fd(body))
    -- the pointer along one fin, a slit along the other
    ImGui.DrawList_AddLine(dl, cx + ca * R * 1.02, cy + sa * R * 1.02 + fy, cx + ca * (fl - R * 0.08), cy + sa * (fl - R * 0.08) + fy,
      fd(p.ink or 0xf0f0eeff), math.max(1.2, R * 0.07))
    ImGui.DrawList_AddLine(dl, cx - ca * R * 1.02, cy - sa * R * 1.02 + fy, cx - ca * (fl - R * 0.08), cy - sa * (fl - R * 0.08) + fy,
      fd(0x00000090), math.max(1.0, R * 0.04))
  end

  -- the body's outline and sides
  local top_r = p.top_r or ({ straight = 0.93, slight = 0.86, tapered = 0.78, domed = 0.90 })[p.profile or "straight"] or 0.93
  if p.grip == "fluted" then top_r = math.min(top_r, 0.80) end
  if p.ptr == "chicken" then
    -- a long tapered pointer with a broad round tail, modelled
    KP.pointer_body(dl, cx, cy, a, { tail = R * 0.42, rt = R * 0.56, tip = R * 1.04, rp = R * 0.13,
      h = R * 0.14 + tilt, l0 = R * 0.05, l1 = R * 0.96, ink = ink }, body, p.mat or "plastic",
      { hw = o.hw, fd = fd, lift = (p.shadow == "tall" and 1.7) or (p.shadow == "none" and 0) or 1 })
    return
  end

  if p.grip == "fluted" then
    -- scalloped: n rounded ridges, the dips turning with the knob
    local n = p.n or 12
    local pts = {}
    local segs = n * 6
    for i = 0, segs - 1 do
      local t = a + i * TAU / segs
      local rr = R * (1 - 0.07 * (0.5 - 0.5 * math.cos(n * (t - a) + math.pi)) ^ 0.9)
      pts[#pts + 1] = cx + math.cos(t) * rr; pts[#pts + 1] = cy + math.sin(t) * rr
    end
    poly(dl, pts, fd(mix(side, BLACK, 0.25)))
    -- the ridges' sides, lit by the way they face, inside the scallops
    lit_ring(dl, cx, cy, R * 0.92, R * top_r * 0.98, mix(side, BLACK, 0.2),
      mix(side, WHITE, (p.mat == "gloss") and 0.30 or 0.12), n * 2, nil, fd)
  else
    local shine = (p.mat == "gloss") and 0.30 or ((p.mat == "metal" or p.mat == "chrome") and 0.35 or 0.12)
    lit_ring(dl, cx, cy, R, R * top_r * 0.98, mix(side, BLACK, 0.25), mix(side, WHITE, shine), 40, nil, fd)
    ImGui.DrawList_AddCircle(dl, cx, cy, R, fd(0x00000070), 40, 1.0)
  end
  local ty = cy - tilt
  -- grip marks on the sides
  if p.grip == "knurled" then
    local nk = math.min(48, math.floor(R * 1.6))
    for i = 0, nk - 1 do
      local t = a + i * TAU / nk
      ImGui.DrawList_AddLine(dl, cx + math.cos(t) * R * top_r, cy + math.sin(t) * R * top_r,
        cx + math.cos(t) * R * 0.995, cy + math.sin(t) * R * 0.995, fd(0x00000048), 1.0)
    end
  elseif p.grip == "ridged" then
    local n = math.min(p.n or 32, math.max(8, math.floor(R * 1.6)))
    for i = 0, n - 1 do
      local t = a + i * TAU / n
      ImGui.DrawList_AddLine(dl, cx + math.cos(t) * R * top_r, cy + math.sin(t) * R * top_r,
        cx + math.cos(t) * R * 0.99, cy + math.sin(t) * R * 0.99,
        fd(lit(t) > 0.5 and 0xffffff30 or 0x00000040), 1.0)
    end
  elseif p.grip == "coin" then
    local nk = math.min(72, math.floor(R * 2))
    for i = 0, nk - 1 do
      local t = a + i * TAU / nk
      ImGui.DrawList_AddLine(dl, cx + math.cos(t) * R * 0.93, cy + math.sin(t) * R * 0.93,
        cx + math.cos(t) * R, cy + math.sin(t) * R, fd(0x00000040), 1.0)
    end
  elseif p.grip == "grooves" then
    local n = p.n or 6
    for i = 0, n - 1 do
      local t = a + (i + 0.5) * TAU / n
      local w = math.rad(5.5)
      -- from the top's edge (up a little, when tilted) down the side to the
      -- base: a slot darker than the side, its far wall catching the light
      local r0, r1 = R * top_r * 0.98, R * 1.005
      local function at(tt, rr, yy) return cx + math.cos(tt) * rr, yy + math.sin(tt) * rr end
      local ax, ay = at(t - w, r0, ty); local bx, by = at(t + w, r0, ty)
      local qx, qy = at(t + w, r1, cy); local px, py = at(t - w, r1, cy)
      ImGui.DrawList_AddQuadFilled(dl, ax, ay, bx, by, qx, qy, px, py, fd(mix(side, BLACK, 0.55)))
      local lit_side = (lit(t + math.pi * 0.5) > 0.5) and 1 or -1
      local ex0, ey0 = at(t + lit_side * w, r0, ty); local ex1, ey1 = at(t + lit_side * w, r1, cy)
      ImGui.DrawList_AddLine(dl, ex0, ey0, ex1, ey1, fd(mix(side, WHITE, 0.25)), 1.0)
    end
  end

  -- the top
  local Rt = R * top_r
  local mat = p.mat or "plastic"
  if mat == "chrome" then
    chrome_disc(dl, cx, ty, Rt, body, fd)
    -- its rim: a dark ring, lit along the top left
    local rr, rw = Rt * 0.94, math.max(1.0, Rt * 0.12)
    ImGui.DrawList_AddCircle(dl, cx, ty, rr, fd(mix(body, BLACK, 0.45)), 0, rw)
    ImGui.DrawList_PathArcTo(dl, cx, ty, rr, LIGHT_A - 1.0, LIGHT_A + 1.0, 12)
    ImGui.DrawList_PathStroke(dl, fd(mix(body, WHITE, 0.6)), 0, rw)
  elseif mat == "metal" then
    lit_disc(dl, cx, ty, Rt, body, fd, 0)
    sheen(dl, cx, ty, Rt * 0.92, body, fd)
  else
    -- only gloss shines; satin plastic barely lifts toward the light
    local lift = ({ plastic = 0.22, gloss = 0.9, matte = 0.08, rubber = 0.04, enamel = 0.45 })[mat] or 0.2
    if p.face == "flat" then flat_face(dl, cx, ty, Rt, body, fd, lift)
    else lit_disc(dl, cx, ty, Rt, body, fd, lift) end
    if p.profile == "domed" then
      for i = 1, 4 do
        ImGui.DrawList_AddCircleFilled(dl, cx - Rt * 0.06 * i, ty - Rt * 0.08 * i, Rt * (0.9 - 0.17 * i),
          fd(alpha(WHITE, 0x0c)), 32)
      end
    end
    if mat == "gloss" then
      -- a crisp highlight high on the left
      ImGui.DrawList_AddCircleFilled(dl, cx - Rt * 0.36, ty - Rt * 0.42, Rt * 0.16, fd(alpha(WHITE, 0x70)), 16)
      ImGui.DrawList_AddCircleFilled(dl, cx - Rt * 0.36, ty - Rt * 0.42, Rt * 0.08, fd(alpha(WHITE, 0x90)), 12)
    elseif mat == "enamel" then
      ImGui.DrawList_AddCircleFilled(dl, cx - Rt * 0.36, ty - Rt * 0.42, Rt * 0.12, fd(alpha(WHITE, 0x38)), 16)
    end
  end
  if p.top == "insert" then
    local ic = p.insert or 0xc9ccd0ff
    lit_disc(dl, cx, ty, Rt * 0.56, ic, fd, 0.5)
    if U.is_light(ic) then sheen(dl, cx, ty, Rt * 0.5, ic, fd) end
    ImGui.DrawList_AddCircle(dl, cx, ty, Rt * 0.56, fd(0x00000080), 32, 1.0)
  elseif p.top == "recessed" then
    ImGui.DrawList_AddCircle(dl, cx, ty, Rt * 0.82, fd(alpha(WHITE, 0x28)), 40, math.max(1.0, R * 0.05))
    ImGui.DrawList_AddCircle(dl, cx + 0.5, ty + 0.6, Rt * 0.78, fd(0x00000050), 40, 1.0)
  end
  if p.rim then
    ImGui.DrawList_AddCircle(dl, cx, ty, Rt * 0.88, fd(p.rim), 40, math.max(1.5, R * 0.12))
    ImGui.DrawList_AddCircle(dl, cx - 0.4, ty - 0.5, Rt * 0.88, fd(alpha(WHITE, 0x50)), 40, 1.0)
  end
  if p.inner then
    local ri = R * (p.inner.r or 0.62)
    ImGui.DrawList_AddCircleFilled(dl, cx, ty, ri * 1.18, fd(0x1c1d1fff), 40)
    lit_disc(dl, cx, ty, ri, p.inner.col or 0x9b9b97ff, fd, (p.inner.mat == "bead") and 0.3 or 0.6)
    if p.inner.screws then
      local sr = (ri * 1.18 + Rt) * 0.5
      for _, s in ipairs({ a + 0.7, a + 0.7 + math.pi }) do
        ImGui.DrawList_AddCircleFilled(dl, cx + math.cos(s) * sr, ty + math.sin(s) * sr, math.max(0.8, R * 0.04), fd(0x303134ff), 8)
      end
    end
  end
  if p.face ~= "flat" then ImGui.DrawList_AddCircle(dl, cx, ty, Rt, fd(0x00000050), 0, 1.0) end
  -- the light over it all (round knobs; a chicken-head or wing isn't a disc)
  if p.ptr ~= "chicken" and p.ptr ~= "wing" then light_wash(dl, cx, cy, outer, fd) end

  -- the pointer
  local function pline(r0, r1, col, w)
    ImGui.DrawList_AddLine(dl, cx + ca * r0, ty + sa * r0, cx + ca * r1, ty + sa * r1, fd(col), w)
  end
  local ptr = p.ptr or "line"
  local pw = math.max(1.5, R * (p.pw or 0.10))
  if ptr == "line" then
    pline(Rt * (p.p0 or 0.30), Rt * 0.92, ink, pw)
  elseif ptr == "dot" then
    ImGui.DrawList_AddCircleFilled(dl, cx + ca * Rt * 0.68, ty + sa * Rt * 0.68, math.max(1.5, R * 0.09), fd(ink), 12)
  elseif ptr == "inset" then
    pline(Rt * 0.24, Rt * 0.86, 0x000000a0, pw * 1.3)
    pline(Rt * 0.26, Rt * 0.84, ink, math.max(1.0, pw * 0.6))
  elseif ptr == "notch" then
    pline(Rt * 0.40, Rt * 0.95, mix(body, BLACK, 0.65), pw)
  elseif ptr == "skirtline" then
    ImGui.DrawList_AddLine(dl, cx + ca * R * 0.5, cy + sa * R * 0.5, cx + ca * Rs * 0.96, cy + sa * Rs * 0.96,
      fd(ink), math.max(1.2, R * 0.07))
  end
end

-- ---------------------------------------------------------------------
-- a look as text (Look<n>, and your recipes): k=v pairs, comma separated;
-- colours as #rrggbb, on/off as 1, the inner cap's fields as in_r, in_col,
-- in_mat, in_screws
-- ---------------------------------------------------------------------
local COLOUR_KEYS = { col = true, side = true, insert = true, rim = true, ink = true, scol = true, sink = true }
local NUM_KEYS = { n = true, tilt = true, sr = true, top_r = true, p0 = true, pw = true }
local BOOL_KEYS = { washer = true, nut = true }
local WORDS = {
  profile = { straight = 1, slight = 1, tapered = 1, domed = 1 },
  grip = { smooth = 1, fluted = 1, knurled = 1, ridged = 1, coin = 1, grooves = 1 },
  mat = { plastic = 1, gloss = 1, matte = 1, rubber = 1, metal = 1, chrome = 1, enamel = 1 },
  top = { flat = 1, insert = 1, recessed = 1 },
  face = { dome = 1, flat = 1 },
  ptr = { line = 1, dot = 1, inset = 1, notch = 1, chicken = 1, wing = 1, skirtline = 1, none = 1 },
  skirt = { plain = 1, printed = 1, numbered = 1, dial = 1 },
  smat = { plastic = 1, matte = 1, metal = 1, clear = 1 },
  sgrip = { knurled = 1 },
  scale = { ticks = 1, dots = 1 },
  shadow = { none = 1, tall = 1 },
}
KP.WORDS = WORDS

local function hexcol(v) return ("#%06x"):format((v >> 8) & 0xffffff) end

function KP.encode(p)
  if type(p) ~= "table" then return nil end
  local out = {}
  local keys = {}
  for k in pairs(p) do if k ~= "inner" then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = p[k]
    if COLOUR_KEYS[k] and type(v) == "number" then out[#out + 1] = k .. "=" .. hexcol(v)
    elseif NUM_KEYS[k] and type(v) == "number" then
      out[#out + 1] = k .. "=" .. ((v == math.floor(v)) and tostring(math.floor(v)) or ("%.3f"):format(v):gsub("0+$", ""))
    elseif BOOL_KEYS[k] and v then out[#out + 1] = k .. "=1"
    elseif WORDS[k] and WORDS[k][v] then out[#out + 1] = k .. "=" .. v end
  end
  local inn = p.inner
  if type(inn) == "table" then
    out[#out + 1] = "in_r=" .. (("%.3f"):format(inn.r or 0.62):gsub("0+$", ""))
    if inn.col then out[#out + 1] = "in_col=" .. hexcol(inn.col) end
    if inn.mat then out[#out + 1] = "in_mat=" .. inn.mat end
    if inn.screws then out[#out + 1] = "in_screws=1" end
  end
  return table.concat(out, ",")
end

-- The look a Look line describes; nil when it says nothing we know.
function KP.decode(str)
  if type(str) ~= "string" then return nil end
  local p, any = {}, false
  for pair in str:gmatch("[^,]+") do
    local k, v = pair:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k then
      if COLOUR_KEYS[k] then
        local h = v:match("^#?(%x%x%x%x%x%x)$")
        if h then p[k] = (tonumber(h, 16) << 8) | 0xff; any = true end
      elseif NUM_KEYS[k] then
        local n = tonumber(v)
        if n then p[k] = n; any = true end
      elseif BOOL_KEYS[k] then
        if v == "1" then p[k] = true; any = true end
      elseif WORDS[k] then
        if WORDS[k][v] then p[k] = v; any = true end
      elseif k == "in_r" or k == "in_col" or k == "in_mat" or k == "in_screws" then
        p.inner = p.inner or {}
        if k == "in_r" then p.inner.r = tonumber(v) or 0.62
        elseif k == "in_col" then
          local h = v:match("^#?(%x%x%x%x%x%x)$")
          if h then p.inner.col = (tonumber(h, 16) << 8) | 0xff end
        elseif k == "in_mat" then p.inner.mat = (v == "bead") and "bead" or nil
        else p.inner.screws = (v == "1") or nil end
        any = true
      end
    end
  end
  return any and p or nil
end

-- A look's own copy (its inner cap too).
function KP.copy(p)
  if type(p) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(p) do out[k] = v end
  if p.inner then out.inner = {}; for k, v in pairs(p.inner) do out.inner[k] = v end end
  return out
end

-- The colour at a look's centre (a modulation dot sits on it).
function KP.centre_col(p, cap)
  if p.inner then return p.inner.col or 0x9b9b97ff end
  if p.top == "insert" then return p.insert or 0xc9ccd0ff end
  return cap or p.col or 0x26282bff
end

return KP
