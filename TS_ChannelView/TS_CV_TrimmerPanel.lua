-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_TrimmerPanel.lua -- the TS_CV Trimmer's panel: two VU meters,
  a trim under each (linkable), Auto and Listen, then the low and high
  cut, drawn over the spectrum or, with the spectrum switched off, as two
  knobs. The plugin and everything that isn't drawing is TS_CV_Trimmer.lua.

  Its height is the strip's. Tall enough, it's one column: meters, trims,
  filters. Shorter, the filters go beside the meters and trims instead.

  Right-click a meter: the 0 VU reference, the peak ceiling, Set as
  default, Auto trim and Listen. Drag a filter's node for its frequency
  (all the way out is off), wheel over it for its slope; the slopes are
  also the two lists over the canvas, the spectrum switch between them.
  Double-click the canvas to put the low cut (left of 1 kHz) or the high
  cut there. The canvas is three rows tall at most.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local TR = require("TS_CV_Trimmer")
local TP = require("TS_CV_Taps")

local ImGui
local TRP = {}
function TRP.attach(imgui) ImGui = imgui end

TRP.COL_W  = 252        -- one column
TRP.METER_H = 72
TRP.SPEC_MIN = 96       -- the spectrum's least height in one column
TRP.SPEC_MAX = 3 * C.CELL_H   -- and its most: three rows

local FACE, INK, RED = 0xe6e0d2ff, 0x2b2722ff, 0xc8453cff
local AMBER = 0xd98a2fff

-- ---------------------------------------------------------------------
-- layout (pure)
-- ---------------------------------------------------------------------

-- The body's height a column needs: meters, trims, and the filters at
-- their least (the same with the spectrum off, so switching it doesn't
-- change the panel's shape).
local function column_need()
  local pad = C.PANEL_PAD
  return pad + TRP.METER_H + 4 + C.CELL_H + 6 + 22 + math.max(TRP.SPEC_MIN, C.CELL_H) + pad
end

function TRP.one_column(body_h)
  return body_h >= column_need()
end

-- The panel's width for a strip `avail_h` tall.
function TRP.width(avail_h)
  local body = (avail_h or 0) - C.HEADER_H - C.FOOTER_H
  if TRP.one_column(body) then return TRP.COL_W end
  return TRP.COL_W * 2 + C.PANEL_PAD
end

-- The Rack view: the body's height at width w -- the two columns side by
-- side when they fit, the meters at full height; otherwise stacked.
function TRP.rack_body_h(w)
  local pad = C.PANEL_PAD
  if w >= TRP.COL_W * 2 + pad then return pad * 2 + TRP.METER_H + 4 + C.CELL_H end
  return column_need()
end

-- Where everything goes in a body at x, y, w, h: { meters = {x,y,w,h},
-- trims = {x,y,w,h}, filt = {x,y,w,h} }.
function TRP.layout(x, y, w, h)
  local pad = C.PANEL_PAD
  local L = {}
  if TRP.one_column(h) then
    local cw = w - pad * 2
    L.meters = { x + pad, y + pad, cw, TRP.METER_H }
    L.trims  = { x + pad, y + pad + TRP.METER_H + 4, cw, C.CELL_H }
    local fy = L.trims[2] + C.CELL_H + 6
    L.filt   = { x + pad, fy, cw, math.min(y + h - pad - fy, 22 + TRP.SPEC_MAX) }
  else
    local cw = TRP.COL_W - pad * 2
    local mh = math.max(34, math.min(TRP.METER_H, h - pad * 2 - 4 - C.CELL_H))
    L.meters = { x + pad, y + pad, cw, mh }
    L.trims  = { x + pad, y + pad + mh + 4, cw, C.CELL_H }
    L.filt   = { x + TRP.COL_W, y + pad, w - TRP.COL_W - pad, math.min(h - pad * 2, 22 + TRP.SPEC_MAX) }
  end
  return L
end

-- ---------------------------------------------------------------------
-- small drawing helpers
-- ---------------------------------------------------------------------

local state = {}
local function panel_state(guid)
  local s = state[guid]
  if not s then s = { pk_t = { 0, 0 } }; state[guid] = s end
  return s
end

local function small_text(ctx, dl, x, y, col, text, align)
  W.push_small(ctx)
  local tw = ImGui.CalcTextSize(ctx, text)
  local tx = (align == "right") and x - tw or (align == "centre") and x - tw * 0.5 or x
  ImGui.DrawList_AddText(dl, math.floor(tx + 0.5), math.floor(y + 0.5), col, text)
  W.pop_small(ctx)
  return tw
end

-- A small button with a label; `on` lights it. Returns pressed, hovered.
local function small_button(ctx, dl, id, x, y, w, h, label, on, tip)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local pressed = ImGui.InvisibleButton(ctx, id, w, h)
  local hov = ImGui.IsItemHovered(ctx)
  local bg = on and C.COL.accent or (hov and C.COL.knob_body_hi or U.with_alpha(C.COL.knob_ring, 0x60))
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 3.0)
  small_text(ctx, dl, x + w * 0.5, y + (h - 12) * 0.5, on and C.COL.icon_on or C.COL.value, label, "centre")
  W.tip(ctx, id, tip, hov, false)
  return pressed, hov
end

-- the VU scale: the needle's travel (0..1) is linear in voltage, as on a
-- real meter, from -20 to +3 VU
local VU_LO, VU_HI = -20, 3
local function vu_pos(v)
  v = math.max(VU_LO, math.min(VU_HI, v))
  local a0, a1 = 10 ^ (VU_LO / 20), 10 ^ (VU_HI / 20)
  return (10 ^ (v / 20) - a0) / (a1 - a0)
end
TRP.vu_pos = vu_pos

-- One meter: `v` in VU (the reading less the 0 VU reference), `lit` the
-- peak lamp, `live` whether the plugin is running.
local function meter(ctx, dl, x, y, w, h, v, lit, live, label)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, FACE, 4.0)
  ImGui.DrawList_PushClipRect(dl, x, y, x + w, y + h, true)
  -- the arc's ends at 12% and 88% across, its top 30% down and its ends
  -- 30% under that: the radius and swing that make that shape
  local hw, drop = w * 0.38, h * 0.30
  local span = 2 * math.atan(drop / hw)
  local rs = hw / math.sin(span)
  local cx, cy = x + w * 0.5, y + h * 0.30 + rs
  local function th(val) return -span + 2 * span * vu_pos(val) end
  local function P(val, r) local t = th(val); return cx + r * math.sin(t), cy - r * math.cos(t) end
  local function arc(v0, v1, r, col, thick)
    ImGui.DrawList_PathClear(dl)
    ImGui.DrawList_PathArcTo(dl, cx, cy, r, th(v0) - math.pi / 2, th(v1) - math.pi / 2, 24)
    ImGui.DrawList_PathStroke(dl, col, 0, thick)
  end
  arc(VU_LO, 0, rs, INK, 1.1)
  arc(0, VU_HI, rs, RED, 3.5)
  for _, t in ipairs({ -20, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3 }) do
    local big = (t == -20 or t == -10 or t == -5 or t == -3 or t == 0 or t == 3)
    local x1, y1 = P(t, rs); local x2, y2 = P(t, rs - (big and 6 or 3.5))
    ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, t > 0 and RED or INK, 1.0)
    if big and h >= 44 then
      local tx, ty = P(t, rs + 7)
      small_text(ctx, dl, tx, ty - 6, t > 0 and RED or INK, tostring(math.abs(t)), "centre")
    end
  end
  small_text(ctx, dl, x + 5, y + h - 14, 0x5c554bff, label)
  local nx, ny = P(live and v or VU_LO, rs + 4)
  ImGui.DrawList_AddLine(dl, cx, cy, nx, ny, live and 0x26282bff or 0x26282b80, 1.3)
  ImGui.DrawList_PopClipRect(dl)
  -- the peak lamp
  ImGui.DrawList_AddCircleFilled(dl, x + w - 8, y + 8, 3.2, lit and 0xff4a3aff or 0x5a2a26ff)
end

-- two rings, linked or not
local function link_icon(dl, cx, cy, on)
  local col = on and C.COL.accent or C.COL.header_dim
  ImGui.DrawList_AddCircle(dl, cx - 4, cy, 5, col, 0, 1.6)
  ImGui.DrawList_AddCircle(dl, cx + 4, cy, 5, col, 0, 1.6)
end

-- ---------------------------------------------------------------------
-- the right-click menu
-- ---------------------------------------------------------------------

local function ask_number(title, label, v)
  local ok, s = reaper.GetUserInputs(title, 1, label, tostring(v))
  return ok and tonumber(s) or nil
end

local function db_label(v) return (v == math.floor(v)) and ("\u{2212}%d"):format(-v) or ("%.1f"):format(v) end

local function do_auto(track)
  reaper.Undo_BeginBlock()
  local t, why = TR.auto_trim(track, function(msg)
    return reaper.MB(msg, "Auto trim", 4) == 6
  end, TP.ara_first(track))
  reaper.Undo_EndBlock("ChannelView: auto trim", -1)
  return t, why
end

local function menu(ctx, track, idx, guid, ps, vu)
  if not ImGui.BeginPopup(ctx, "trimmenu##" .. guid) then return end
  local ref, ceil = TR.get(track, idx, TR.P.REF), TR.get(track, idx, TR.P.CEIL)
  if ImGui.BeginMenu(ctx, "0 VU =") then
    for _, r in ipairs(TR.REFS) do
      if ImGui.MenuItem(ctx, db_label(r) .. " dBFS", nil, math.abs(ref - r) < 0.01) then TR.set(track, idx, TR.P.REF, r) end
    end
    if ImGui.MenuItem(ctx, "Custom\u{2026}") then
      local v = ask_number("0 VU reference", "0 VU = (dBFS, -30 to -6)", ref)
      if v then TR.set(track, idx, TR.P.REF, TR.clamp(v, -30, -6)) end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.MenuItem(ctx, "Set 0 VU to this level", nil, false, vu ~= nil) and vu then
    TR.set(track, idx, TR.P.REF, TR.clamp(math.floor(vu * 2 + 0.5) / 2, -30, -6))
  end
  if ImGui.BeginMenu(ctx, "Peak ceiling") then
    for _, c in ipairs(TR.CEILS) do
      if ImGui.MenuItem(ctx, db_label(c) .. " dBFS", nil, math.abs(ceil - c) < 0.01) then TR.set(track, idx, TR.P.CEIL, c) end
    end
    if ImGui.MenuItem(ctx, "Custom\u{2026}") then
      local v = ask_number("Peak ceiling", "Peak ceiling (dBFS, -24 to 0)", ceil)
      if v then TR.set(track, idx, TR.P.CEIL, TR.clamp(v, -24, 0)) end
    end
    ImGui.EndMenu(ctx)
  end
  local dr, dc = TR.defaults()
  if ImGui.MenuItem(ctx, ("Set as default (%s / %s dBFS)"):format(db_label(ref), db_label(ceil)), nil, false,
      math.abs(dr - ref) > 0.01 or math.abs(dc - ceil) > 0.01) then
    TR.set_defaults(ref, ceil)
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Auto trim from the items") then
    local t, why = do_auto(track)
    if not t and why ~= "cancelled" then ps.msg, ps.msg_t = why, reaper.time_precise() end
  end
  local on = TR.listening(track)
  if ImGui.MenuItem(ctx, on and "Stop listening" or "Listen", nil, on) then ps.toggle_listen = true end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Show the spectrum", nil, TR.spectrum_shown(guid)) then
    TR.set_spectrum_shown(guid, not TR.spectrum_shown(guid))
  end
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- the filters
-- ---------------------------------------------------------------------

local F_LO, F_HI = 20, 20000
local INSET = 8                 -- the nodes at the ends stay whole and reachable
local DB_RANGE = 36
local SPEC_LO, SPEC_HI = -90, -6
TRP.ROW_H = 20                  -- the slope lists and the switch, over the canvas

local function x_of(f, gx, gw)
  return gx + INSET + math.log(f / F_LO) / math.log(F_HI / F_LO) * (gw - INSET * 2)
end
local function f_of(px, gx, gw)
  return F_LO * (F_HI / F_LO) ^ ((px - gx - INSET) / (gw - INSET * 2))
end

local function slope_combo(ctx, id, x, y, w, track, idx, p, on)
  local s = math.floor(TR.get(track, idx, p) + 0.5)
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.push_small(ctx)
  ImGui.SetNextItemWidth(ctx, w)
  if not on then ImGui.BeginDisabled(ctx) end
  if ImGui.BeginCombo(ctx, id, TR.SLOPES[s + 1] or TR.SLOPES[2]) then
    for i, name in ipairs(TR.SLOPES) do
      if ImGui.Selectable(ctx, name, i - 1 == s) then TR.set(track, idx, p, i - 1) end
    end
    ImGui.EndCombo(ctx)
  end
  if not on then ImGui.EndDisabled(ctx) end
  W.pop_small(ctx)
end

-- the spectrum's on/off switch, a small pill at x, y
local function spec_switch(ctx, dl, x, y, guid)
  local on = TR.spectrum_shown(guid)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local w, h = 30, 13
  if ImGui.InvisibleButton(ctx, "trspec##" .. guid, w, h) then TR.set_spectrum_shown(guid, not on) end
  local hov = ImGui.IsItemHovered(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, on and C.COL.accent or U.with_alpha(C.COL.knob_ring, hov and 0xc0 or 0x80), h * 0.5)
  local kx = on and (x + w - h * 0.5) or (x + h * 0.5)
  ImGui.DrawList_AddCircleFilled(dl, kx, y + h * 0.5, h * 0.5 - 2, on and C.COL.icon_on or C.COL.header_dim)
  W.tip(ctx, "trspec##" .. guid, on and "Hide the spectrum" or "Show the spectrum", hov, false)
end

-- the row over the filters: the low cut's slope, the switch, the high cut's
local function slope_row(ctx, dl, x, y, w, track, idx, guid, lc_on, hc_on)
  local cw = math.min(84, (w - 44) * 0.5)
  slope_combo(ctx, "##trlcs" .. guid, x, y, cw, track, idx, TR.P.LC_S, lc_on)
  slope_combo(ctx, "##trhcs" .. guid, x + w - cw, y, cw, track, idx, TR.P.HC_S, hc_on)
  spec_switch(ctx, dl, x + w * 0.5 - 15, y + 3, guid)
end

-- One column per step across the canvas: a level (0..1 up the canvas)
-- read off the spectrum's bands at that column's frequency.
local function band_level(bands, lo, hi, f)
  local n = #bands
  local pos = math.log(f / lo) / math.log(hi / lo) * n + 0.5
  local i = math.max(1, math.min(n, math.floor(pos)))
  local j = math.min(n, i + 1)
  local t = math.max(0, math.min(1, pos - i))
  local db = bands[i] + (bands[j] - bands[i]) * t
  return math.max(0, math.min(1, (db - SPEC_LO) / (SPEC_HI - SPEC_LO)))
end

local function draw_canvas(ctx, dl, gx, gy, gw, gh, track, idx, fx, ps, sr)
  ImGui.DrawList_AddRectFilled(dl, gx, gy, gx + gw, gy + gh, U.with_alpha(C.COL.win_bg, 0xd0), 3.0)
  ImGui.DrawList_PushClipRect(dl, gx, gy, gx + gw, gy + gh, true)
  for _, f in ipairs({ 50, 100, 200, 500, 1000, 2000, 5000, 10000 }) do
    local x = x_of(f, gx, gw)
    ImGui.DrawList_AddLine(dl, x, gy, x, gy + gh, C.COL.eq_grid, 1.0)
    local lbl = (f == 100 and "100") or (f == 1000 and "1k") or (f == 10000 and "10k")
    if lbl then small_text(ctx, dl, x + 2, gy + gh - 12, C.COL.header_dim, lbl) end
  end

  local lc_f = TR.clamp(TR.get(track, idx, TR.P.LC_F) or TR.LC_LO, TR.LC_LO, TR.LC_HI)
  local hc_f = TR.clamp(TR.get(track, idx, TR.P.HC_F) or TR.HC_HI, TR.HC_LO, TR.HC_HI)
  local lc_on, hc_on = TR.lc_on(lc_f), TR.hc_on(hc_f)
  local lc_n = TR.order(lc_on, TR.get(track, idx, TR.P.LC_S))
  local hc_n = TR.order(hc_on, TR.get(track, idx, TR.P.HC_S))
  local top = gy + 10
  local function y_of(db) return top + math.min(DB_RANGE, -db) / DB_RANGE * (gh - 14) end
  local y0 = y_of(0)
  local step = 2
  local cols = math.floor(gw / step)

  -- the spectrum, before the filters: a column every two pixels
  TR.spectrum_beat(track)
  local bands, lo, hi = TR.bands(track, ps.bands)
  ps.bands = bands
  if bands and #bands > 1 and lo and hi and hi > lo then
    local col = U.with_alpha(C.COL.eq_spectrum, 0x48)
    local line = U.with_alpha(C.COL.eq_spectrum, 0xa0)
    local px, py
    for c = 0, cols do
      local x = gx + c * step
      local yy = gy + gh - band_level(bands, lo, hi, f_of(x + step * 0.5, gx, gw)) * gh
      ImGui.DrawList_AddRectFilled(dl, x, yy, x + step, gy + gh, col)
      if px then ImGui.DrawList_AddLine(dl, px, py, x + step * 0.5, yy, line, 1.0) end
      px, py = x + step * 0.5, yy
    end
  end

  -- what the filters take away, shaded down to their curve, and the curve
  local fill = U.with_alpha(AMBER, 0x30)
  ImGui.DrawList_AddLine(dl, gx, y0, gx + gw, y0, C.COL.eq_grid_0db, 1.0)
  ImGui.DrawList_PathClear(dl)
  for c = 0, cols do
    local x = gx + c * step
    local yy = y_of(TR.response_db(f_of(x + step * 0.5, gx, gw), lc_f, lc_n, hc_f, hc_n, sr))
    if yy > y0 + 0.5 then ImGui.DrawList_AddRectFilled(dl, x, y0, x + step, yy, fill) end
    ImGui.DrawList_PathLineTo(dl, x + step * 0.5, yy)
  end
  ImGui.DrawList_PathStroke(dl, (lc_on or hc_on) and AMBER or U.with_alpha(AMBER, 0x80), 0, 1.8)

  -- the two nodes: drag for the frequency (to the end of the range is
  -- off), wheel for the slope
  local function node(id, f, on, n, pf, ps_, lo_, hi_, tip)
    local nx = x_of(f, gx, gw)
    local ny = on and y_of(TR.response_db(f, lc_f, lc_n, hc_f, hc_n, sr)) or y0
    ImGui.SetCursorScreenPos(ctx, nx - 8, ny - 8)
    ImGui.InvisibleButton(ctx, id, 16, 16)
    local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    if act then
      local mx = ImGui.GetMousePos(ctx)
      TR.set(track, idx, pf, TR.clamp(f_of(mx, gx, gw), lo_, hi_))
    end
    if hov then
      local wv = ImGui.GetMouseWheel(ctx)
      if wv and wv ~= 0 then
        local s = math.floor(TR.get(track, idx, ps_) + 0.5)
        TR.set(track, idx, ps_, TR.clamp(s + (wv > 0 and 1 or -1), 0, #TR.SLOPES - 1))
      end
    end
    W.tip(ctx, id, tip, hov and not act, false)
    local col = on and AMBER or C.COL.header_dim
    ImGui.DrawList_AddCircleFilled(dl, nx, ny, 5.5, U.with_alpha(C.COL.win_bg, 0xff))
    ImGui.DrawList_AddCircle(dl, nx, ny, 5.5, col, 0, (hov or act) and 2.4 or 1.8)
  end
  ImGui.DrawList_PopClipRect(dl)
  -- double-click the canvas: the low cut (under 1 kHz) or the high cut there
  do
    local mx, my = ImGui.GetMousePos(ctx)
    local inside = mx >= gx and mx <= gx + gw and my >= gy and my <= gy + gh
    if inside and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left)
       and ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows) then
      local f = f_of(mx, gx, gw)
      if f < 1000 then TR.set(track, idx, TR.P.LC_F, TR.clamp(f, 25, TR.LC_HI))
      else TR.set(track, idx, TR.P.HC_F, TR.clamp(f, TR.HC_LO, 19000)) end
    end
  end
  node("trlc##" .. fx.guid, lc_f, lc_on, lc_n, TR.P.LC_F, TR.P.LC_S, TR.LC_LO, TR.LC_HI,
    lc_on and "Low cut: drag, wheel for the slope (all the way left: off)" or "Low cut, off: drag it in (or double-click the canvas)")
  node("trhc##" .. fx.guid, hc_f, hc_on, hc_n, TR.P.HC_F, TR.P.HC_S, TR.HC_LO, TR.HC_HI,
    hc_on and "High cut: drag, wheel for the slope (all the way right: off)" or "High cut, off: drag it in (or double-click the canvas)")
  return lc_on, hc_on
end

local function freq_label(f, on)
  if not on then return "Off" end
  if f >= 10000 then return ("%.1fk"):format(f / 1000) end
  return f >= 1000 and ("%.2fk"):format(f / 1000) or ("%d Hz"):format(math.floor(f + 0.5))
end

local function draw_knobs(ctx, dl, fx0, fy, fw, track, idx, fx)
  local function one(cx, label, p, lo, hi, is_on)
    local f = TR.clamp(TR.get(track, idx, p) or lo, lo, hi)
    local on = is_on(f)
    local norm = math.log(f / lo) / math.log(hi / lo)
    ImGui.SetCursorScreenPos(ctx, cx - C.CELL_W * 0.5, fy)
    local ch, v, act = W.knob(ctx, "trk" .. p .. "##" .. fx.guid, label, norm, freq_label(f, on), { dim = not on })
    if ch then TR.set(track, idx, p, lo * (hi / lo) ^ math.max(0, math.min(1, v))) end
    if act and act.double_click then TR.set(track, idx, p, (p == TR.P.LC_F) and lo or hi) end
  end
  one(fx0 + fw * 0.25, "Low cut", TR.P.LC_F, TR.LC_LO, TR.LC_HI, TR.lc_on)
  one(fx0 + fw * 0.75, "High cut", TR.P.HC_F, TR.HC_LO, TR.HC_HI, TR.hc_on)
end

-- ---------------------------------------------------------------------
-- the panel's body
-- ---------------------------------------------------------------------

function TRP.draw(ctx, dl, x, y, w, h, track, fx, req)
  local idx = fx.addr
  local guid = fx.guid
  local ps = panel_state(guid)
  local spec = TR.spectrum_shown(guid)
  local L = TRP.layout(x, y, w, h)
  local now = reaper.time_precise()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if not sr or sr < 1000 then sr = 48000 end

  -- meters
  local ref, ceil = TR.get(track, idx, TR.P.REF), TR.get(track, idx, TR.P.CEIL)
  local vul, vur, pkl, pkr, live = TR.meters(track)
  local mx, my, mw, mh = table.unpack(L.meters)
  local half = (mw - 6) * 0.5
  local lit = {}
  for k, pk in ipairs({ pkl, pkr }) do
    if live and pk and pk >= ceil then ps.pk_t[k] = now end
    lit[k] = now - (ps.pk_t[k] or 0) < 1.0
  end
  meter(ctx, dl, mx, my, half, mh, (vul or -100) - ref, lit[1], live, "L")
  meter(ctx, dl, mx + half + 6, my, half, mh, (vur or -100) - ref, lit[2], live, "R")
  ImGui.SetCursorScreenPos(ctx, mx, my)
  ImGui.InvisibleButton(ctx, "trmeters##" .. guid, mw, mh, ImGui.ButtonFlags_MouseButtonRight)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then ImGui.OpenPopup(ctx, "trimmenu##" .. guid) end
  W.tip(ctx, "trmeters##" .. guid, ("0 VU = %s dBFS \u{00B7} peak lamp over %s dBFS\nRight-click: settings"):format(
    db_label(ref), db_label(ceil)), ImGui.IsItemHovered(ctx), false)
  local vu_now = (live and vul and vur) and math.max(vul, vur) or nil
  menu(ctx, track, idx, guid, ps, vu_now)

  -- trims, with link, Auto and Listen between them
  local tx, ty, tw = L.trims[1], L.trims[2], L.trims[3]
  local link = TR.get(track, idx, TR.P.LINK) >= 0.5
  local function trim_knob(cx, label, p)
    local v = TR.get(track, idx, p)
    ImGui.SetCursorScreenPos(ctx, cx - C.CELL_W * 0.5, ty)
    local ch, nv, act = W.knob(ctx, "trt" .. p .. "##" .. guid, label, (v + TR.TRIM_MAX) / (TR.TRIM_MAX * 2),
      ("%+.1f dB"):format(v), { bipolar = true })
    if ch then TR.set(track, idx, p, math.floor((nv * TR.TRIM_MAX * 2 - TR.TRIM_MAX) * 10 + 0.5) / 10) end
    if act and act.double_click then TR.set(track, idx, p, 0) end
  end
  trim_knob(tx + half * 0.5, "Trim L", TR.P.TRIM_L)
  trim_knob(tx + half + 6 + half * 0.5, "Trim R", TR.P.TRIM_R)
  local mid = tx + tw * 0.5
  ImGui.SetCursorScreenPos(ctx, mid - 11, ty + 2)
  if ImGui.InvisibleButton(ctx, "trlink##" .. guid, 22, 14) then TR.set(track, idx, TR.P.LINK, link and 0 or 1) end
  W.tip(ctx, "trlink##" .. guid, link and "Trims linked: click to unlink" or "Link the trims", ImGui.IsItemHovered(ctx), false)
  link_icon(dl, mid, ty + 9, link)
  local bw = 46
  if small_button(ctx, dl, "trauto##" .. guid, mid - bw * 0.5, ty + 20, bw, 16, "Auto", false,
      "Set the trim from the track's items: average on 0 VU, peaks under the ceiling\n(inside the time selection, when there is one)") then
    local t, why = do_auto(track)
    if not t and why ~= "cancelled" then ps.msg, ps.msg_t = why, now end
  end
  local listening = TR.listening(track)
  local blink = listening and (math.floor(now * 2) % 2 == 0)
  if small_button(ctx, dl, "trlisten##" .. guid, mid - bw * 0.5, ty + 40, bw, 16, listening and "Stop" or "Listen", blink,
      listening and "Stop, and set the trim from what was heard"
                or "Listen: play the loudest part, then Stop to set the trim") then
    ps.toggle_listen = true
  end
  if ps.toggle_listen then
    ps.toggle_listen = nil
    if TR.listening(track) then
      local rms, pk, secs = TR.listen_stop(track)
      if rms and secs and secs >= 0.3 and rms > -90 then
        reaper.Undo_BeginBlock()
        TR.trim_from_listen(track, rms, pk)
        reaper.Undo_EndBlock("ChannelView: trim from Listen", -1)
      else
        ps.msg, ps.msg_t = "nothing heard", now
      end
    elseif not TR.listen_start(track) then
      ps.msg, ps.msg_t = "can't listen on this track", now
    end
  end
  if ps.msg and now - (ps.msg_t or 0) < 3 then
    small_text(ctx, dl, mid, ty + C.CELL_H - 4, C.COL.header_dim, ps.msg, "centre")
  end

  -- filters: the slope lists and the switch, then the canvas (four rows
  -- at most) or the two knobs
  local fx0, fy, fw, fh = table.unpack(L.filt)
  if fw > 40 and fh > TRP.ROW_H + 30 then
    local lc_on = TR.lc_on(TR.get(track, idx, TR.P.LC_F))
    local hc_on = TR.hc_on(TR.get(track, idx, TR.P.HC_F))
    local cy = fy + TRP.ROW_H + 2
    if spec then
      draw_canvas(ctx, dl, fx0, cy, fw, math.min(fh - TRP.ROW_H - 2, TRP.SPEC_MAX), track, idx, fx, ps, sr)
    else
      draw_knobs(ctx, dl, fx0, cy, fw, track, idx, fx)
    end
    slope_row(ctx, dl, fx0, fy, fw, track, idx, guid, lc_on, hc_on)
  end
end

return TRP
