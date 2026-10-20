-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Light.lua -- the one light everything is lit by, and the shadows it
  casts, so knobs, switches, buttons and fader caps all sit on the panel
  the same way.

  The light comes from the top left (LT.A, the angle a surface faces to
  catch it most). Everything standing on the panel casts two shadows away
  from it:
    contact  tight and dark, right round its foot, where it meets the panel
    drop     soft and offset down and right, further and softer the bigger
             the thing is
  `k` is the 3D effect's strength (C.METAL_K): no shadows at 0.
  LT.STRENGTH (View > Shadows, 0..2, 1 as drawn by default) scales the
  drop shadow's depth and reach on top of that, the contact shadow's only
  a little. `lift` says how far a thing
  stands off the panel: 1 as usual, more for a tall knob, 0 for one sat
  flush (only the seam where it meets the panel).
--]]

local LT = {}
local ImGui

function LT.attach(imgui) ImGui = imgui end

LT.STRENGTH = 1
local function strength(k) return (k or 0) * LT.STRENGTH end

LT.A = math.atan(-0.8, -0.6)                 -- toward the light: up and left
LT.UX, LT.UY = math.cos(LT.A), math.sin(LT.A)
local SX, SY = -LT.UX, -LT.UY                 -- the way shadows fall

-- How far, and how soft, the drop shadow of a thing of half-size `h` is:
-- a real light throws a bigger thing's shadow further and blurs it more.
local function reach(h, k, lift)
  lift = lift or 1
  local off = math.max(1.5, math.min(12.0, h * 0.22)) * k * lift
  local soft = math.max(2.0, math.min(20.0, h * 0.55)) * k * lift
  return off, soft
end

local function shade(a, k) return math.floor(a * math.min(2.0, k + 0.2)) end

-- The drop shadow as layers, from the widest and faintest to the tightest:
-- each { dx, dy, grow, alpha }. Stacked, they make a soft fall-off -- dark
-- close under the thing, thinning out a long way into the panel: the wide
-- layers carry little of the darkness, the tight ones most of it. Small
-- things get fewer. `k` already has View > Shadows in it.
local function layers(h, k, lift)
  local off, soft = reach(h, k, lift)
  -- enough layers that the steps between them don't show
  local n = math.max(3, math.min(14, math.ceil(soft / 1.3)))
  local total = math.min(0xe0, 0xa0 * math.min(2.0, k + 0.2))
  local w, sum = {}, 0
  for i = 0, n - 1 do
    local t = i / (n - 1)
    w[i] = (0.2 + t) ^ 1.2
    sum = sum + w[i]
  end
  local out = {}
  for i = 0, n - 1 do
    local t = i / (n - 1)             -- 0 the widest
    local o = off * (1 - 0.45 * t)
    out[#out + 1] = { SX * o, SY * o, soft * (1 - t) ^ 1.25, math.max(1, math.floor(total * w[i] / sum)) }
  end
  return out
end

-- The contact shadow, where it meets the panel: tight and dark, and only a
-- little deeper with View > Shadows (the slider is mostly the drop's).
local function contact_alpha(k)
  return math.floor(0x30 * math.min(1.6, (k or 0) + 0.2) * math.min(1.25, 0.6 + 0.4 * LT.STRENGTH))
end

-- A round thing of radius r at (cx, cy).
function LT.circle(dl, cx, cy, r, k, lift)
  lift = lift or 1
  local ks = strength(k)
  if ks <= 0 then return end
  if lift ~= 0 then
    for _, l in ipairs(layers(r, ks, lift)) do
      ImGui.DrawList_AddCircleFilled(dl, cx + l[1], cy + l[2], r + l[3], l[4], 0)
    end
  end
  ImGui.DrawList_AddCircle(dl, cx + SX * 0.5, cy + SY * 0.5, r + 0.4, contact_alpha(k), 0, 1.3)
end

-- A box x1..x2, y1..y2 with corner radius rr.
function LT.rect(dl, x1, y1, x2, y2, rr, k)
  local ks = strength(k)
  if ks <= 0 then return end
  rr = rr or 0
  for _, l in ipairs(layers(math.min(x2 - x1, y2 - y1) * 0.5, ks)) do
    local g = l[3]
    ImGui.DrawList_AddRectFilled(dl, x1 + l[1] - g, y1 + l[2] - g, x2 + l[1] + g, y2 + l[2] + g, l[4], rr + g)
  end
  ImGui.DrawList_AddRect(dl, x1 + SX * 0.5 - 0.4, y1 + SY * 0.5 - 0.4, x2 + SX * 0.5 + 0.4, y2 + SY * 0.5 + 0.4,
    contact_alpha(k), rr + 0.4, 0, 1.3)
end

-- For a shape drawn some other way (a polygon): the drop's layers for a
-- thing of half-size h, as above ({ dx, dy, grow, alpha } each), and the
-- contact shadow's alpha. Empty / 0 with no shadows.
function LT.drop(h, k, lift)
  lift = lift or 1
  local ks = strength(k)
  if ks <= 0 then return {}, 0 end
  return layers(h, ks, lift), contact_alpha(k)
end

-- The drop shadow's offset for a thing of half-size h: dx, dy, and how
-- much to grow it.
function LT.offset(h, k)
  local off, soft = reach(h, strength(k))
  return SX * off, SY * off, soft
end
-- a shadow layer's alpha `a` at strength k (View > Shadows applied)
function LT.shade(a, k) return shade(a, strength(k)) end

return LT
