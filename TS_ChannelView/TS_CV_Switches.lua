-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Switches.lua -- toggles drawn as hardware switches (C.SWITCH_STYLES):
  bat and paddle toggles, pill and lit rockers, a slide switch, a pill
  slider, lamp and round buttons, a jewel lamp and a guarded toggle.

  SW.draw lays one into a box -- the part of a toggle's cell a knob would
  take -- in the 3D look (one light, top left, shadows down and right) or,
  with the 3D effect off, in the theme's flat look, where the lever types
  draw as a pill slider and the guarded toggle as a pill slider with its
  cover. `col` is the toggle's lit colour; the rockers, lamps, buttons and
  sliders light in it. A pill rocker doesn't light: its colour (`body`,
  the toggle's own) is the colour its cap is moulded in, black without.
--]]

local C = require("TS_CV_Config")
local U = require("TS_CV_Util")
local LT = require("TS_CV_Light")

local SW = {}
local ImGui

function SW.attach(imgui) ImGui = imgui end

-- ---------------------------------------------------------------------
-- colour helpers
-- ---------------------------------------------------------------------
local function mix(a, b, t)
  t = math.max(0, math.min(1, t))
  local out = 0
  for _, sh in ipairs({ 24, 16, 8 }) do
    local x, y = (a >> sh) & 0xff, (b >> sh) & 0xff
    out = out | (math.floor(x + (y - x) * t + 0.5) << sh)
  end
  return out | (a & 0xff)
end
local function alpha(col, a) return U.with_alpha(col, a) end
local BLACK, WHITE = 0x000000ff, 0xffffffff

-- a soft shadow down and right of a box, or of a circle
-- the shadows they stand in (TS_CV_Light), at the 3D effect's strength
local function shadow_rect(dl, x1, y1, x2, y2, rr, k)
  LT.rect(dl, x1, y1, x2, y2, rr, (C.METAL_K or 0.8) * k)
end
local function shadow_circle(dl, cx, cy, r, k)
  LT.circle(dl, cx, cy, r, (C.METAL_K or 0.8) * k)
end
-- a glow round a lit part
local function glow_circle(dl, cx, cy, r, col, a0)
  for i = 4, 1, -1 do
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, r + i * 1.4, alpha(col, math.floor(a0 * (5 - i) / 10)))
  end
end
local function glow_rect(dl, x1, y1, x2, y2, rr, col, a0)
  for i = 4, 1, -1 do
    ImGui.DrawList_AddRectFilled(dl, x1 - i, y1 - i, x2 + i, y2 + i, alpha(col, math.floor(a0 * (5 - i) / 10)), rr + i)
  end
end
-- top-lit vertical shading
local function vgrad(dl, x1, y1, x2, y2, top, bot)
  ImGui.DrawList_AddRectFilledMultiColor(dl, x1, y1, x2, y2, top, top, bot, bot)
end
-- a turned-metal disc or ring: light top left, darker bottom right
local function metal_disc(dl, cx, cy, r, base)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, r, mix(base, BLACK, 0.35))
  ImGui.DrawList_AddCircleFilled(dl, cx - r * 0.06, cy - r * 0.08, r * 0.92, base)
  ImGui.DrawList_AddCircleFilled(dl, cx - r * 0.22, cy - r * 0.26, r * 0.45, alpha(WHITE, 0x30))
end
local function hexagon(dl, cx, cy, r, base)
  ImGui.DrawList_AddNgonFilled(dl, cx + 0.8, cy + 1.2, r, mix(base, BLACK, 0.55), 6)
  ImGui.DrawList_AddNgonFilled(dl, cx, cy, r, base, 6)
  ImGui.DrawList_AddNgonFilled(dl, cx - r * 0.12, cy - r * 0.15, r * 0.62, mix(base, WHITE, 0.25), 6)
  ImGui.DrawList_AddNgon(dl, cx, cy, r, mix(base, BLACK, 0.45), 6, 1.0)
end
-- the I and O printed on a rocker
local function mark_i(dl, cx, cy, s, col)
  ImGui.DrawList_AddLine(dl, cx, cy - s, cx, cy + s, col, math.max(1.0, s * 0.35))
end
local function mark_o(dl, cx, cy, s, col)
  ImGui.DrawList_AddCircle(dl, cx, cy, s, col, 0, math.max(1.0, s * 0.35))
end

-- ---------------------------------------------------------------------
-- the parts
-- ---------------------------------------------------------------------

-- A lever on a hex nut: `kind` "bat" (a silver bat with a ball end) or
-- "paddle" (a flat black paddle). Up is on.
local function lever(dl, cx, cy, S, on, kind)
  local nut = S * 0.26
  shadow_circle(dl, cx, cy, nut, 1)
  hexagon(dl, cx, cy, nut, 0xa9adb2ff)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, nut * 0.55, 0x3a3c40ff)
  local dir = on and -1 or 1
  local len = S * 0.44
  local tx, ty = cx, cy + dir * len
  local w0, w1 = S * 0.09, (kind == "paddle") and S * 0.14 or S * 0.065
  -- its shadow, then the lever: lit on its left
  ImGui.DrawList_AddQuadFilled(dl, cx - w0 + 2, cy + 2.5, cx + w0 + 2, cy + 2.5, tx + w1 + 2, ty + 2.5, tx - w1 + 2, ty + 2.5, 0x00000040)
  if kind == "paddle" then
    ImGui.DrawList_AddQuadFilled(dl, cx - w0, cy, cx + w0, cy, tx + w1, ty, tx - w1, ty, 0x1c1d20ff)
    ImGui.DrawList_AddRectFilled(dl, tx - w1, ty - (on and 0 or S * 0.10), tx + w1, ty + (on and S * 0.10 or 0), 0x1c1d20ff, S * 0.04)
    ImGui.DrawList_AddQuadFilled(dl, cx - w0, cy, cx - w0 * 0.2, cy, tx - w1 * 0.2, ty, tx - w1, ty, 0xffffff18)
  else
    ImGui.DrawList_AddQuadFilled(dl, cx - w0, cy, cx + w0, cy, tx + w1, ty, tx - w1, ty, 0x9fa3a8ff)
    ImGui.DrawList_AddQuadFilled(dl, cx - w0, cy, cx - w0 * 0.1, cy, tx - w1 * 0.1, ty, tx - w1, ty, 0xe2e4e6ff)
    metal_disc(dl, tx, ty, S * 0.095, 0xd2d5d8ff)
  end
end

-- A rocker in a pill bezel, I above O; the pressed half is the one in.
-- `body`: an unlit rocker's colour (nil: black).
local function rocker(dl, cx, cy, S, on, lit, col, body)
  local w, h = S * 0.52, S * 0.86
  local x1, y1, x2, y2 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
  local rr = w / 2
  shadow_rect(dl, x1, y1, x2, y2, rr, 1)
  ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, 0x0e0e10ff, rr)
  local i = 2.0
  local face = lit and (on and col or mix(col, BLACK, 0.55)) or body or 0x26272bff
  if lit and on then glow_rect(dl, x1 + i, y1 + i, x2 - i, y2 - i, rr - i, col, 0x50) end
  ImGui.DrawList_AddRectFilled(dl, x1 + i, y1 + i, x2 - i, y2 - i, face, rr - i)
  -- the pressed half sits in shadow, the other catches the light
  local mid = cy
  if on then
    vgrad(dl, x1 + i + 1, y1 + i + rr * 0.3, x2 - i - 1, mid, 0x00000050, 0x00000010)
    vgrad(dl, x1 + i + 1, mid, x2 - i - 1, y2 - i - rr * 0.3, alpha(WHITE, 0x24), 0x00000000)
  else
    vgrad(dl, x1 + i + 1, y1 + i + rr * 0.3, x2 - i - 1, mid, alpha(WHITE, 0x24), 0x00000000)
    vgrad(dl, x1 + i + 1, mid, x2 - i - 1, y2 - i - rr * 0.3, 0x00000010, 0x00000050)
  end
  ImGui.DrawList_AddLine(dl, x1 + i + 1, mid, x2 - i - 1, mid, 0x00000060, 1.0)
  local ink = (lit and not on) and alpha(WHITE, 0x90) or alpha(WHITE, 0xe0)
  if not lit and body and U.is_light(body) then ink = 0x202124d8 end
  mark_i(dl, cx, cy - h * 0.24, S * 0.06, ink)
  mark_o(dl, cx, cy + h * 0.24, S * 0.055, ink)
end

-- A slide switch on a screwed plate; the knob up is on.
local function slide(dl, cx, cy, S, on)
  local w, h = S * 0.44, S * 0.86
  local x1, y1, x2, y2 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
  shadow_rect(dl, x1, y1, x2, y2, 2, 1)
  vgrad(dl, x1, y1, x2, y2, 0xc9ccd0ff, 0x8d9195ff)
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, 0x505357ff, 2, 0, 1.0)
  for _, sy in ipairs({ y1 + S * 0.06, y2 - S * 0.06 }) do
    ImGui.DrawList_AddCircleFilled(dl, cx, sy, S * 0.025, 0x55585cff)
  end
  local sx1, sy1, sx2, sy2 = cx - S * 0.065, y1 + S * 0.14, cx + S * 0.065, y2 - S * 0.14
  ImGui.DrawList_AddRectFilled(dl, sx1, sy1, sx2, sy2, 0x141416ff, 1.5)
  local kh = (sy2 - sy1) * 0.45
  local ky = on and sy1 or (sy2 - kh)
  ImGui.DrawList_AddRectFilled(dl, cx - S * 0.10 + 1, ky + 1.5, cx + S * 0.10 + 1, ky + kh + 1.5, 0x00000060, 2)
  vgrad(dl, cx - S * 0.10, ky, cx + S * 0.10, ky + kh, 0x3a3c40ff, 0x151618ff)
  ImGui.DrawList_AddRect(dl, cx - S * 0.10, ky, cx + S * 0.10, ky + kh, 0x000000ff, 2, 0, 1.0)
  for k = 1, 3 do
    local gy = ky + kh * (0.25 + 0.25 * (k - 1))
    ImGui.DrawList_AddLine(dl, cx - S * 0.07, gy, cx + S * 0.07, gy, alpha(WHITE, 0x22), 1.0)
  end
end

-- A pill slider: the knob right and the track lit is on.
local function pill_slider(dl, cx, cy, S, on, col, flat)
  local w, h = S * 0.80, S * 0.42
  local x1, y1, x2, y2 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
  local rr = h / 2
  if not flat then shadow_rect(dl, x1, y1, x2, y2, rr, 0.7) end
  local track = on and col or (flat and 0x3a3d42ff or 0x1b1c1fff)
  ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, track, rr)
  if not flat then
    vgrad(dl, x1 + rr * 0.6, y1 + 1, x2 - rr * 0.6, y1 + h * 0.5, 0x00000040, 0x00000000)
    ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, 0x000000a0, rr, 0, 1.0)
  end
  local kr = h * 0.40
  local kx = on and (x2 - rr) or (x1 + rr)
  if flat then
    ImGui.DrawList_AddCircleFilled(dl, kx, cy, kr, on and 0xf2f2f2ff or 0x8a8d92ff)
  else
    shadow_circle(dl, kx, cy, kr, 0.8)
    metal_disc(dl, kx, cy, kr, 0xe4e6e8ff)
  end
end

-- A lamp button: a square cap that lights, its text on it.
local function lamp(ctx, dl, cx, cy, S, on, col, text, flat)
  local s = S * 0.72
  local x1, y1, x2, y2 = cx - s / 2, cy - s / 2, cx + s / 2, cy + s / 2
  local ink
  if flat then
    if on then
      ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, col, 2)
      ink = U.is_light(col) and 0x101010ff or 0xf6f6f4ff
    else
      ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, 0x8a8d92ff, 2, 0, 1.5)
      ink = 0xa8abb0ff
    end
  else
    shadow_rect(dl, x1, y1, x2, y2, 3, 1)
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, 0x0e0e10ff, 3)
    local i = 2.0
    if on then
      glow_rect(dl, x1 + i, y1 + i, x2 - i, y2 - i, 2, col, 0x40)
      ImGui.DrawList_AddRectFilled(dl, x1 + i, y1 + i, x2 - i, y2 - i, U.lighten(col, 0.15), 2)
      ImGui.DrawList_AddRectFilled(dl, x1 + i + s * 0.12, y1 + i + s * 0.12, x2 - i - s * 0.12, y2 - i - s * 0.12,
        alpha(U.lighten(col, 0.45), 0x80), 4)
      ink = U.is_light(col) and 0x141414ff or 0xffffffff
    else
      ImGui.DrawList_AddRectFilled(dl, x1 + i, y1 + i, x2 - i, y2 - i, mix(col, BLACK, 0.70), 2)
      ink = alpha(mix(col, BLACK, 0.25), 0xb0)
    end
    vgrad(dl, x1 + i, y1 + i, x2 - i, y1 + s * 0.45, alpha(WHITE, 0x30), alpha(WHITE, 0x00))
  end
  if text and text ~= "" then
    local tw, th = ImGui.CalcTextSize(ctx, text)
    if tw > s - 4 then
      -- too long: as many letters as fit
      while #text > 1 and tw > s - 4 do text = text:sub(1, -2); tw, th = ImGui.CalcTextSize(ctx, text) end
    end
    ImGui.DrawList_AddText(dl, cx - tw / 2, cy - th / 2, ink, text)
  end
end

-- A round push button in a metal bezel; on, a ring round its cap lights.
local function round_button(dl, cx, cy, S, on, col, flat)
  local R = S * 0.38
  if flat then
    if on then
      ImGui.DrawList_AddCircle(dl, cx, cy, R, col, 0, 2.5)
      ImGui.DrawList_AddCircleFilled(dl, cx, cy, R * 0.70, col)
    else
      ImGui.DrawList_AddCircle(dl, cx, cy, R, 0x3a3d42ff, 0, 2.5)
      ImGui.DrawList_AddCircleFilled(dl, cx, cy, R * 0.70, 0x8a8d92ff)
    end
    return
  end
  shadow_circle(dl, cx, cy, R, 1)
  metal_disc(dl, cx, cy, R, 0xb9bcc0ff)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, R * 0.78, 0x151618ff)
  if on then
    ImGui.DrawList_AddCircle(dl, cx, cy, R * 0.72, U.lighten(col, 0.25), 0, 2.2)
    for i = 3, 1, -1 do ImGui.DrawList_AddCircle(dl, cx, cy, R * 0.72, alpha(col, 0x22 * (4 - i)), 0, 2 + i * 1.5) end
  end
  local cap = on and col or mix(col, BLACK, 0.30)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, R * 0.60, mix(cap, BLACK, 0.35))
  ImGui.DrawList_AddCircleFilled(dl, cx - R * 0.04, cy - R * 0.05, R * 0.55, cap)
  ImGui.DrawList_AddCircleFilled(dl, cx - R * 0.18, cy - R * 0.22, R * 0.22, alpha(WHITE, 0x40))
end

-- A jewel lamp: a faceted dome in a chrome bezel, lit or dark.
local function jewel(dl, cx, cy, S, on, col, flat)
  local R = S * 0.36
  if flat then
    if on then glow_circle(dl, cx, cy, R * 0.6, col, 0x50) end
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, R * 0.6, on and col or mix(col, BLACK, 0.55))
    if not on then ImGui.DrawList_AddCircle(dl, cx, cy, R * 0.6, 0x8a8d9280, 0, 1.0) end
    return
  end
  shadow_circle(dl, cx, cy, R, 1)
  metal_disc(dl, cx, cy, R, 0xc4c7cbff)
  if on then glow_circle(dl, cx, cy, R * 0.72, col, 0x60) end
  local dome = on and U.lighten(col, 0.10) or mix(col, BLACK, 0.72)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, R * 0.72, dome)
  -- facets: a ring of lighter wedges
  ImGui.DrawList_AddNgon(dl, cx, cy, R * 0.50, alpha(on and WHITE or col, on and 0x50 or 0x40), 8, 1.0)
  if on then ImGui.DrawList_AddCircleFilled(dl, cx, cy, R * 0.32, alpha(U.lighten(col, 0.6), 0xc0)) end
  ImGui.DrawList_AddCircleFilled(dl, cx - R * 0.25, cy - R * 0.28, R * 0.16, alpha(WHITE, on and 0xd0 or 0x80))
end

-- A guarded toggle: a bat toggle under a red cover that flips up to use it.
local function guarded(dl, cx, cy, S, on, col, flat)
  local red = 0xb3201eff
  if flat then
    if on then
      pill_slider(dl, cx, cy, S, true, col, true)
      ImGui.DrawList_AddRectFilled(dl, cx - S * 0.40, cy - S * 0.36, cx + S * 0.40, cy - S * 0.30, 0xd23a32ff, 1.5)
    else
      local w, h = S * 0.80, S * 0.40
      ImGui.DrawList_AddRectFilled(dl, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, 0x6a222260, h / 2)
      ImGui.DrawList_AddRect(dl, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, 0xd23a32ff, h / 2, 0, 1.5)
    end
    return
  end
  lever(dl, cx, cy + S * 0.05, S * 0.9, on, "bat")
  local w = S * 0.42
  if on then
    -- the cover flipped up: its sides, and its edge along the top
    ImGui.DrawList_AddRectFilled(dl, cx - w / 2, cy - S * 0.44, cx - w / 2 + 2.5, cy + S * 0.40, red, 1)
    ImGui.DrawList_AddRectFilled(dl, cx + w / 2 - 2.5, cy - S * 0.44, cx + w / 2, cy + S * 0.40, red, 1)
    ImGui.DrawList_AddRectFilled(dl, cx - w / 2, cy - S * 0.47, cx + w / 2, cy - S * 0.42, U.lighten(red, 0.15), 1)
    ImGui.DrawList_AddRectFilled(dl, cx - w / 2, cy + S * 0.38, cx + w / 2, cy + S * 0.42, mix(red, BLACK, 0.3), 1)
  else
    -- closed: a red see-through box over it
    local x1, y1, x2, y2 = cx - w / 2, cy - S * 0.44, cx + w / 2, cy + S * 0.40
    shadow_rect(dl, x1, y1, x2, y2, 2, 1)
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, alpha(red, 0xd8), 2)
    vgrad(dl, x1 + 2, y1 + 2, x2 - 2, y1 + (y2 - y1) * 0.35, alpha(WHITE, 0x38), alpha(WHITE, 0x00))
    ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, mix(red, BLACK, 0.4), 2, 0, 1.0)
  end
end

-- ---------------------------------------------------------------------
-- drawing one
-- ---------------------------------------------------------------------

-- Whether `style` is one of the switches (else it's a button face).
function SW.is(style) return style ~= nil and C.SWITCH[style] ~= nil end

-- The switch `style` in the box x1..x2, y1..y2, on or off, lit in `col`;
-- `flat` the theme's look; `text` what a lamp button says; `hot` hovered;
-- `body` a pill rocker's own colour (nil: black).
function SW.draw(ctx, dl, style, x1, y1, x2, y2, on, col, flat, text, hot, body)
  local cx, cy = (x1 + x2) * 0.5, (y1 + y2) * 0.5
  local bw, bh = x2 - x1, y2 - y1
  local S = math.min(bw, bh)
  -- the upright ones fill the box's height, the pill slider its width
  local SL = math.min(bh * 1.15, bw * 1.3)
  local SP = math.min(bw * 1.2, bh * 2.4)
  if hot then col = U.lighten(col, 0.08) end
  if hot and body then body = U.lighten(body, 0.08) end
  if style == "bat" or style == "paddle" then
    if flat then pill_slider(dl, cx, cy, SP, on, col, true) else lever(dl, cx, cy, SL, on, style) end
  elseif style == "rocker" or style == "litrocker" then
    if flat then
      -- a portrait pill, its top half lit when on, I above O
      local w, h = SL * 0.52, SL * 0.86
      local bx1, by1, bx2, by2 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
      local rr = w / 2
      ImGui.DrawList_AddRectFilled(dl, bx1, by1, bx2, by2, 0x3a3d42ff, rr)
      local top, bot = on and col or 0x5a5d62ff, on and 0x3a3d42ff or 0x8a8d92ff
      local ink = 0xf2f2f2ff
      if style == "rocker" and body then
        -- its own colour, the pressed half in shadow
        local dim = mix(body, BLACK, 0.35)
        top, bot = on and dim or body, on and body or dim
        if U.is_light(body) then ink = 0x202124ff end
      end
      ImGui.DrawList_AddRectFilled(dl, bx1, by1, bx2, cy, top, rr, ImGui.DrawFlags_RoundCornersTop)
      ImGui.DrawList_AddRectFilled(dl, bx1, cy, bx2, by2, bot, rr, ImGui.DrawFlags_RoundCornersBottom)
      mark_i(dl, cx, cy - h * 0.24, SL * 0.06, ink)
      mark_o(dl, cx, cy + h * 0.24, SL * 0.05, ink)
    else
      rocker(dl, cx, cy, SL, on, style == "litrocker", col, style == "rocker" and body or nil)
    end
  elseif style == "slide" then
    if flat then
      ImGui.DrawList_AddRectFilled(dl, cx - SL * 0.07, cy - SL * 0.42, cx + SL * 0.07, cy + SL * 0.42, 0x3a3d42ff, SL * 0.07)
      local kh = SL * 0.30
      local ky = on and (cy - SL * 0.42) or (cy + SL * 0.42 - kh)
      ImGui.DrawList_AddRectFilled(dl, cx - SL * 0.18, ky, cx + SL * 0.18, ky + kh, on and col or 0x8a8d92ff, 2)
    else
      slide(dl, cx, cy, SL, on)
    end
  elseif style == "pill" then
    pill_slider(dl, cx, cy, SP, on, col, flat)
  elseif style == "lamp" then
    lamp(ctx, dl, cx, cy, S, on, col, text, flat)
  elseif style == "roundbtn" then
    round_button(dl, cx, cy, S, on, col, flat)
  elseif style == "jewel" then
    jewel(dl, cx, cy, S, on, col, flat)
  elseif style == "guarded" then
    guarded(dl, cx, cy, flat and SP or SL, on, col, flat)
  end
end

return SW
