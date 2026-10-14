-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_RolePanel.lua -- the role canvases that aren't a compressor's
  picture: De-esser, Delay, Reverb, Envelope and Modulation layouts, for
  any plugin. As with a Compressor layout (TS_CV_CompPanel's
  CP.draw_mapped), each maps the plugin's controls to roles
  (TS_CV_Mappings M.ROLES) and takes the plugin's own values as fact: a
  control that reads in its role's unit is drawn where its value puts it,
  one that doesn't runs along its own range (the other way round when the
  layout says it's reversed). A switch snaps to its own settings.

    De-esser    the band over the spectrum, along the top; under it the
                track's waveform scrolling, the audio being reduced lit in
                the gain-reduction colour (the faint part is what was taken
                off), with the threshold across it. Needs the probe pair.
    Delay       the echoes on a timeline: the first one's place is the
                time (drag it across), the second's height the feedback
                (drag it up or down), alternating left and right when
                ping-pong is on. A note-value switch's settings as chips.
    Reverb      the sound's energy over time: the pre-delay's gap, the
                early reflections, the tail falling 60 dB over the decay
                time; under it, how the decay changes with frequency (the
                damping's corner, the bass multiplier).
    Envelope    attack, hold, decay, sustain, release; a ◆ halfway along a
                segment bends it (its curve control).
    Modulation  the LFO as it moves, left solid and right dashed (its
                phase): drag the peak for depth, the cycle's marker for
                rate; the shape switch's settings as chips.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local T  = require("TS_CV_FXTree")
local TP = require("TS_CV_Taps")
local Tr = require("TS_CV_Trace")
local UN = require("TS_CV_Units")
local CP = require("TS_CV_CompPanel")
local EQP = require("TS_CV_EQPanel")

local RP = {}
local ImGui

function RP.attach(imgui) ImGui = imgui end

-- the kinds drawn here
RP.KINDS = { deess = true, delay = true, reverb = true, env = true, mod = true, multi = true, sat = true }

local u = CP.util

-- ---------------------------------------------------------------------
-- reading roles
-- ---------------------------------------------------------------------

-- a value in its unit, or along its range between lo and hi (log when
-- `log`); returns value, along
local function val(m, unit, lo, hi, log, rev)
  if not m then return nil end
  if m.v and m.unit == unit and m.v > -math.huge and m.v < math.huge then return m.v, false end
  local n = rev and (1 - m.n) or m.n
  if log then return lo * (hi / lo) ^ n, true end
  return lo + n * (hi - lo), true
end

-- and back: the control to `v` (in its unit), or along its range
local function set_val(track, addr, m, v, along, lo, hi, log, rev)
  if along then
    local n
    if log then n = math.log(math.max(lo, v) / lo) / math.log(hi / lo) else n = (v - lo) / (hi - lo) end
    n = math.max(0, math.min(1, n))
    u.set_norm(track, addr, m.p, rev and (1 - n) or n)
  else
    u.set_to(track, addr, m.p, v)
  end
end

-- a role's switch settings that read as `fn(text)` (a number), nearest to
-- `target` (compared in log when `log`); its norm, or nil
local function nearest_setting(track, addr, guid, m, fn, target, log)
  local sw = u.switch_positions(track, addr, guid, m.p)
  if not sw then return nil end
  local best, bd
  for _, s_ in ipairs(sw) do
    local v = fn(s_.text)
    if v then
      local d = log and math.abs(math.log(math.max(1e-6, v)) - math.log(math.max(1e-6, target))) or math.abs(v - target)
      if not bd or d < bd then best, bd = s_.norm, d end
    end
  end
  return best
end

local function on_of(track, addr, m)
  return m and (reaper.TrackFX_GetParamNormalized(track, addr, m.p) or 0) >= 0.5
end

local function frame(dl, gx0, gy0, gw, gh)
  ImGui.DrawList_AddRectFilled(dl, gx0, gy0, gx0 + gw, gy0 + gh, 0x00000030)
end

local function grid_h(dl, gx0, gw, y)
  ImGui.DrawList_AddLine(dl, gx0, math.floor(y) + 0.5, gx0 + gw, math.floor(y) + 0.5, U.with_alpha(C.COL.eq_grid, 0xc0), 1.0)
end
local function grid_v(dl, x, gy0, gh)
  ImGui.DrawList_AddLine(dl, math.floor(x) + 0.5, gy0, math.floor(x) + 0.5, gy0 + gh, U.with_alpha(C.COL.eq_grid, 0xc0), 1.0)
end

-- a node you drag; on_drag(dx_px, dy_px since the press, fine) while held
local function node(ctx, dl, ps, id, nx, ny, tip, on_drag, opts)
  opts = opts or {}
  local r = opts.r or 5
  local hov, act, dragging = u.handle(ctx, id, nx - r - 4, ny - r - 4, (r + 4) * 2, (r + 4) * 2)
  if dragging then
    local d = ps.drag
    if not d or d.id ~= id then
      local mx, my = ImGui.GetMousePos(ctx)
      d = { id = id, mx = mx, my = my }
      ps.drag = d
    end
    local mx, my = ImGui.GetMousePos(ctx)
    local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
    on_drag((mx - d.mx) * fine, (my - d.my) * fine, d)
    ImGui.SetMouseCursor(ctx, opts.cursor or ImGui.MouseCursor_ResizeAll)
  end
  if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
  local hot = hov or act
  if opts.diamond then
    local k = r + 1
    local col = opts.col or 0xe0a33aff
    local fc = hot and C.COL.header_text or col
    ImGui.DrawList_AddTriangleFilled(dl, nx, ny - k, nx + k, ny, nx - k, ny, fc)
    ImGui.DrawList_AddTriangleFilled(dl, nx - k, ny, nx + k, ny, nx, ny + k, fc)
    local ink = C.COL.header_text
    ImGui.DrawList_AddLine(dl, nx, ny - k, nx + k, ny, ink, 1.2)
    ImGui.DrawList_AddLine(dl, nx + k, ny, nx, ny + k, ink, 1.2)
    ImGui.DrawList_AddLine(dl, nx, ny + k, nx - k, ny, ink, 1.2)
    ImGui.DrawList_AddLine(dl, nx - k, ny, nx, ny - k, ink, 1.2)
  else
    ImGui.DrawList_AddCircleFilled(dl, nx, ny, r, opts.fill or C.COL.header_text)
    ImGui.DrawList_AddCircle(dl, nx, ny, r, hot and C.COL.header_text or (opts.ring or C.COL.accent), 0, 1.6)
  end
  if tip then W.tip(ctx, id, tip, hov, act) end
  return hov, act
end

-- small chips along a row: a switch's settings; returns the norm clicked
local function chips(ctx, dl, id, x, y, w_max, sw, cur_n, label_of)
  local cx = x
  local hit
  for i, s_ in ipairs(sw) do
    local t = label_of and label_of(s_.text) or s_.text
    W.push_small(ctx)
    local tw = ImGui.CalcTextSize(ctx, t)
    W.pop_small(ctx)
    local cw = tw + 12
    if cx + cw > x + w_max then break end
    local on = cur_n >= s_.lo - 1e-6 and cur_n <= s_.hi + 1e-6
    if u.mini_toggle(ctx, dl, ("%s%d"):format(id, i), cx, y, cw, 16, on, t) then hit = s_.norm end
    cx = cx + cw + 4
  end
  return hit
end

local function knob_box(ctx, dl, ps, track, addr, guid, list, x, y)
  -- a see-through box of mini knobs: { {m, name}, ... }
  local n = 0
  for _, k in ipairs(list) do if k[1] then n = n + 1 end end
  if n == 0 then return end
  local bw = n * 52 + 4
  ImGui.DrawList_AddRectFilled(dl, x - bw, y, x, y + 50, U.with_alpha(C.COL.win_bg, 0xc8), 5.0)
  ImGui.DrawList_AddRect(dl, x - bw, y, x, y + 50, C.COL.knob_ring, 5.0, 0, 1.0)
  local kx = x - bw + 28
  for _, k in ipairs(list) do
    if k[1] then
      u.mini_knob(ctx, dl, "rpk" .. k[2] .. "##" .. guid, kx, y + 16, 10, track, addr, k[1].p, k[2], ps)
      kx = kx + 52
    end
  end
end

-- ---------------------------------------------------------------------
-- the de-esser
-- ---------------------------------------------------------------------
local F_LO, F_HI = 20, 20000

-- What it's reducing, over its band: one depth (its gain reduction, as the
-- waveform has it) across the band, soft at the edges. A de-esser turns
-- one gain down over its band, so this is drawn as roughly as it's known:
-- measured band by band, the quiet bands' noise said more than the plugin
-- did. The depth swells at once and settles back over half a second; the
-- scale steps 6 / 12 / 24 dB so it doesn't breathe.
local function deess_fill(ctx, dl, ps, gx0, gw, y0, y1, a, b, gr, open_hi)
  local now = reaper.time_precise()
  local dt = math.max(0, math.min(0.2, now - (ps.dfat or now))); ps.dfat = now
  local g0 = ps.dgr or 0
  local g = (gr > g0) and (g0 + (gr - g0) * math.min(1, dt * 30)) or (g0 + (gr - g0) * math.min(1, dt * 5))
  if g < 0.05 then g = 0 end
  ps.dgr = g
  local want = 6
  while want < g * 1.15 and want < 48 do want = want * 2 end
  if not ps.drng or want > ps.drng then ps.drng, ps.drng_t = want, now
  elseif want == ps.drng then ps.drng_t = now
  elseif now - (ps.drng_t or 0) > 3 then ps.drng, ps.drng_t = want, now end
  local rng = ps.drng
  local col = CP.FINE_COL
  local lc = U.with_alpha(C.COL.header_dim, 0xc0)
  -- the scale, at the left: the zero and the depth
  local lx = gx0 + 4
  ImGui.DrawList_AddLine(dl, lx - 4, y1, lx + 4, y1, U.with_alpha(col, 0x80), 1.0)
  u.small_text(ctx, dl, lx, y0, lc, "0 dB")
  u.small_text(ctx, dl, lx + 7, y1 - 12, lc, ("\u{2212}%d dB"):format(rng))
  if g < 0.3 or not (a and b) then return end
  local yy = y0 + math.min(rng, g) * (y1 - y0) / rng
  local top, bot, none = U.with_alpha(col, 0x70), U.with_alpha(col, 0x20), U.with_alpha(col, 0x00)
  -- soft edges a third of an octave wide, either side of each edge
  local ew = math.max(6, gw / 30)
  local ia, ib = a + ew, open_hi and (gx0 + gw + 2) or (b - ew)
  if ib < ia then local m = (a + b) * 0.5; ia, ib = m, m end
  local grad = type(ImGui.DrawList_AddRectFilledMultiColor) == "function"
  local function box(x0, x1, ul, ur, br, bl)
    if x1 <= x0 then return end
    if grad then ImGui.DrawList_AddRectFilledMultiColor(dl, x0, y0, x1, yy, ul, ur, br, bl)
    else ImGui.DrawList_AddRectFilled(dl, x0, y0, x1, yy, U.with_alpha(col, 0x40)) end
  end
  box(a - ew, ia, none, top, bot, none)
  box(ia, ib, top, top, bot, bot)
  if not open_hi then box(ib, b + ew, top, none, none, bot) end
  -- its depth, a soft line
  ImGui.DrawList_AddLine(dl, a, yy, open_hi and (gx0 + gw) or b, yy, U.with_alpha(col, 0xb0), 1.6)
end

local function draw_deess(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = u.panel_state(guid)
  local enabled = T.get_enabled(track, addr)
  local rev = cv.rev or {}
  u.db_ish(track, addr, guid, R.Threshold); u.db_ish(track, addr, guid, R.Range)
  -- no reduction meter down the side: the band's fill and the waveform show it
  local gx0, gy0 = x + 1, y
  local gw, gh = w - 1, h
  local gr = T.gain_reduction(track, addr) or 0
  local grc = W.gr_fill_col(false, false)
  -- the spectrum strip and the waveform below it, half each
  local sh = math.max(64, math.floor(gh * 0.5))
  local fx_of = function(f) return EQP.util.x_of(math.max(F_LO, math.min(F_HI, f)), gx0, gw) end

  -- ---- the band, along the top
  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + sh, true)
  frame(dl, gx0, gy0, gw, sh)
  EQP.util.draw_spectrum(dl, gx0, gy0, gw, sh)
  for _, f in ipairs({ 100, 1000, 10000 }) do
    grid_v(dl, fx_of(f), gy0, sh)
    u.small_text(ctx, dl, fx_of(f) + 3, gy0 + sh - 13, U.with_alpha(C.COL.header_dim, 0xa0), f >= 1000 and (f // 1000) .. "k" or tostring(f))
  end
  local f, f_along = val(R.Frequency, "hz", 1000, 16000, true, rev.Frequency)
  local lo, lo_along = val(R.Low, "hz", 1000, 16000, true, rev.Low)
  local hi, hi_along = val(R.High, "hz", 2000, 20000, true, rev.High)
  local oct
  if not (lo and hi) and f then
    if not R.Width and cv.dshape ~= "around" then
      -- split-band: everything above its frequency
      lo, hi = f, F_HI
    elseif R.Width and R.Width.unit == "hz" and R.Width.v then
      lo, hi = math.max(F_LO, f - R.Width.v * 0.5), f + R.Width.v * 0.5
    else
      oct = 1
      if R.Width then
        if R.Width.unit == "" and R.Width.v and R.Width.v > 0 and R.Width.v < 8 then oct = R.Width.v
        else oct = 0.3 + (rev.Width and (1 - R.Width.n) or R.Width.n) * 2.7 end
      end
      lo, hi = f / 2 ^ (oct / 2), f * 2 ^ (oct / 2)
    end
  elseif lo and not hi then hi = F_HI
  elseif hi and not lo then lo = F_LO end
  if lo and hi then
    local a, b = fx_of(lo), fx_of(hi)
    ImGui.DrawList_AddRectFilled(dl, a, gy0, b, gy0 + sh, U.with_alpha(grc, 0x26))
    ImGui.DrawList_AddLine(dl, a, gy0, a, gy0 + sh, grc, 1.2)
    ImGui.DrawList_AddLine(dl, b, gy0, b, gy0 + sh, grc, 1.2)
  end
  -- what it's reducing, hanging from the top across its band
  deess_fill(ctx, dl, ps, gx0, gw, gy0 + 2, gy0 + sh - 4, lo and fx_of(lo), hi and fx_of(hi),
    enabled and gr or 0, hi and hi >= F_HI)
  ImGui.DrawList_PopClipRect(dl)
  -- the band's handles: its frequency, and each edge that's a control
  local function freq_drag(m, v0, along, flo, fhi, r)
    return function(dx)
      local nv = v0 * (F_HI / F_LO) ^ (dx / gw)
      if along then set_val(track, addr, m, nv, true, flo, fhi, true, r)
      else u.set_to(track, addr, m.p, nv) end
    end
  end
  if f then
    local nx, ny = fx_of(f), gy0 + sh * 0.38
    node(ctx, dl, ps, "rdfq##" .. guid, nx, ny, ("Frequency %s\nDrag left or right"):format(R.Frequency.text or ""),
      function(dx, _, d) d.v0 = d.v0 or f; freq_drag(R.Frequency, d.v0, f_along, 1000, 16000, rev.Frequency)(dx) end,
      { fill = grc, ring = C.COL.header_text, cursor = ImGui.MouseCursor_ResizeEW })
    u.small_text(ctx, dl, (lo and fx_of(lo) or nx) - 6, gy0 + 4, C.COL.value, R.Frequency.text or "", "right")
    if R.Width then
      u.small_text(ctx, dl, (lo and fx_of(lo) or nx) - 6, gy0 + 16, C.COL.header_dim, "width " .. (R.Width.text or ""), "right")
    end
  end
  for _, e in ipairs({ { R.Low, lo, lo_along, 1000, 16000, rev.Low, "rdlo", "Low edge" },
                       { R.High, hi, hi_along, 2000, 20000, rev.High, "rdhi", "High edge" } }) do
    local m, v = e[1], e[2]
    if m and v then
      local ex = fx_of(v)
      node(ctx, dl, ps, e[7] .. "##" .. guid, ex, gy0 + sh - 10, ("%s %s\nDrag left or right"):format(e[8], m.text or ""),
        function(dx, _, d) d.v0 = d.v0 or v; freq_drag(m, d.v0, e[3], e[4], e[5], e[6])(dx) end,
        { r = 4, fill = grc, cursor = ImGui.MouseCursor_ResizeEW })
    end
  end

  -- ---- the waveform: what's being reduced in the gain-reduction colour
  local wy0 = gy0 + sh + 4
  local wh = gh - sh - 4
  local mid, half = wy0 + wh * 0.5, wh * 0.5 - 4
  ImGui.DrawList_PushClipRect(dl, gx0, wy0, gx0 + gw, wy0 + wh, true)
  frame(dl, gx0, wy0, gw, wh)
  Tr.want(track)
  TP.panel_open(guid)
  local pw = math.max(1, math.floor(gw))
  local d, m1, m2 = Tr.columns(track, fx, { win = CP.window() }, false, gr, pw)
  local function amp(lin) return math.max(0, math.min(1, (u.lin_db(lin) + 60) / 60)) end
  if d then
    local calm = U.with_alpha(C.COL.eq_spectrum, 0xb0)
    for px = 0, pw - 1 do
      local xx = gx0 + px + 0.5
      local ai = amp(d.ip[px + 1] or 0)
      local ao = amp(math.max(-(d.mn[px + 1] or 0), d.mx[px + 1] or 0))
      local g = d.g[px + 1] or 0
      if g > 0.3 then
        local k = math.min(1, g / 8)
        if ai > ao then ImGui.DrawList_AddLine(dl, xx, mid - ai * half, xx, mid + ai * half, U.with_alpha(grc, 0x38), 1.0) end
        ImGui.DrawList_AddLine(dl, xx, mid - ao * half, xx, mid + ao * half, U.with_alpha(grc, math.floor(0x90 + 0x6f * k)), 1.0)
      elseif ao > 0 then
        ImGui.DrawList_AddLine(dl, xx, mid - ao * half, xx, mid + ao * half, calm, 1.0)
      end
    end
  else
    u.small_text(ctx, dl, gx0 + gw * 0.5, mid - 14, C.COL.header_dim, m1 or "", "centre")
    if m2 then u.small_text(ctx, dl, gx0 + gw * 0.5, mid, C.COL.header_dim, m2, "centre") end
  end
  ImGui.DrawList_AddLine(dl, gx0, mid, gx0 + gw, mid, U.with_alpha(C.COL.knob_ring, 0xa0), 1.0)
  ImGui.DrawList_PopClipRect(dl)
  -- the threshold, a pair of lines on the waveform's level scale
  if R.Threshold then
    local thr, along = val(R.Threshold, "db", -60, 0, false, rev.Threshold)
    if thr == -math.huge then thr = -60 end
    local a = math.max(0, math.min(1, (thr + 60) / 60))
    local ty, by = mid - a * half, mid + a * half
    u.dashed(dl, gx0, by, gx0 + gw, by, C.COL.accent, 5, 3, 1.2)
    local id = "rdthr##" .. guid
    local hov, act, dragging = u.handle(ctx, id, gx0, ty - 4, gw - 60, 8)
    if dragging then
      local v = u.drag_real(ctx, ps, id, thr, 0, -60 / half)
      v = math.max(-60, math.min(0, v))
      if along then set_val(track, addr, R.Threshold, v, true, -60, 0, false, rev.Threshold)
      else u.set_to(track, addr, R.Threshold.p, v) end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    elseif hov then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    u.dashed(dl, gx0, ty, gx0 + gw, ty, C.COL.accent, 5, 3, 1.2)
    ImGui.DrawList_AddRectFilled(dl, gx0 + gw - 110, ty - 4, gx0 + gw - 74, ty + 4,
      (hov or act) and C.COL.header_text or C.COL.accent, 4.0)
    u.small_text(ctx, dl, gx0 + 8, ty - 14, C.COL.value, "Threshold " .. (R.Threshold.text or ""))
    W.tip(ctx, id, ("Threshold %s\nDrag up or down (Shift: fine)"):format(R.Threshold.text or ""), hov, act)
  end
  if R.Range then
    knob_box(ctx, dl, ps, track, addr, guid, { { R.Range, "Range" } }, gx0 + gw - 6, wy0 + wh - 56)
  end
  return true
end

-- ---------------------------------------------------------------------
-- the saturator
-- ---------------------------------------------------------------------
-- Its curve and harmonics, learned on a hidden copy (TS_CV_Learn
-- LN.start_sat) at the Drive and Style it's on; the music's peak riding
-- the curve; a drive meter -- VU-like, the music's peak (the probe's input,
-- measured on its own) against where the learned curve starts to bite: 0
-- is on the knee. All on the canvas's own ground, like every other canvas:
-- no boxes, and no figures read out (the needle and the bars say it).
local M_ = require("TS_CV_Mappings")
local function db_lin(db) return 10 ^ (db / 20) end

-- the meter, VU-like: the music's peaks against where the curve starts to
-- bite, -20..+6 dB, the zone over 0 amber and filled to the needle; `hold`
-- the recent peak (a yellow tick). Centred in x .. x + w, y .. y + h; no
-- figures, the needle says it.
local function drive_meter(ctx, dl, x, y, w, h, v, hold, live, learned)
  u.small_text(ctx, dl, x + 8, y + 5, C.COL.value, "Drive")
  u.small_text(ctx, dl, x + 8, y + h - 14, U.with_alpha(C.COL.header_dim, 0xc0),
    learned and "0: where it starts to bite" or "learn it to read the knee")
  local R = math.max(20, math.min(h - 56, w * 0.4))
  -- the arc and its labels (R + 15 over the pivot) centred between the
  -- title and the caption
  local top, bot = y + 20, y + h - 18
  local pcx, pcy = x + w * 0.5, math.floor((top + bot) * 0.5 + (R + 15 - 5) * 0.5)
  local function th(val) return (-58 + 116 * M_.sat_vu_pos(val)) * math.pi / 180 end
  local function P(val, r) local t = th(val); return pcx + r * math.sin(t), pcy - r * math.cos(t) end
  local function arc(v0, v1, r, col, thick)
    ImGui.DrawList_PathClear(dl)
    ImGui.DrawList_PathArcTo(dl, pcx, pcy, r, th(v0) - math.pi / 2, th(v1) - math.pi / 2, 28)
    ImGui.DrawList_PathStroke(dl, col, 0, thick)
  end
  local amber = W.gr_fill_col(false, false)
  arc(M_.SAT_VU_LO, 0, R - 6, U.with_alpha(C.COL.knob_ring, 0xa0), 6)
  arc(0, M_.SAT_VU_HI, R - 6, U.with_alpha(amber, 0x50), 6)
  if live and v > 0.05 then arc(0, v, R - 6, U.with_alpha(amber, 0xd8), 6) end
  for _, t in ipairs({ -20, -10, -6, -3, 0, 3, 6 }) do
    local x1, y1 = P(t, R - 11); local x2, y2 = P(t, R)
    ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, U.with_alpha(C.COL.label, t == 0 and 0xe0 or 0x90), t == 0 and 1.6 or 1.0)
    local tx, ty = P(t, R + 9)
    u.small_text(ctx, dl, tx, ty - 6, U.with_alpha(C.COL.header_dim, 0xd0),
      t == 0 and "0" or (t > 0 and ("+%d"):format(t) or ("\u{2212}%d"):format(-t)), "centre")
  end
  for _, t in ipairs({ -5, -4, -2, -1, 1, 2, 4, 5 }) do
    local x1, y1 = P(t, R - 7); local x2, y2 = P(t, R)
    ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, U.with_alpha(C.COL.label, 0x60), 1.0)
  end
  if live and hold > M_.SAT_VU_LO + 0.5 then
    local x1, y1 = P(hold, R - 11); local x2, y2 = P(hold, R)
    ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, 0xe6cf79ff, 2.2)
  end
  local nx, ny = P(live and v or M_.SAT_VU_LO, R + 1)
  ImGui.DrawList_AddLine(dl, pcx, pcy, nx, ny, C.COL.header_text, 1.6)
  ImGui.DrawList_AddCircleFilled(dl, pcx, pcy, 4.5, C.COL.knob_ring)
end

-- a control's own name, short: its first word ("Warmth", "Softness")
local function own_name(track, addr, m, fallback)
  if not m then return fallback end
  local _, nm = reaper.TrackFX_GetParamName(track, addr, m.p, "")
  local wd = (nm or ""):match("%a[%a%-]*")
  if not wd or #wd < 3 then return fallback end
  wd = wd:sub(1, 1):upper() .. wd:sub(2):lower()
  return #wd > 9 and wd:sub(1, 8) or wd
end

local function draw_sat(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = u.panel_state(guid)
  local rev = cv.rev or {}
  local enabled = T.get_enabled(track, addr)
  TP.panel_open(guid)
  local c = cv.sat_cal
  if c and R.Drive and c.d ~= R.Drive.p then c = nil end
  local dn = R.Drive and R.Drive.n or 0
  local sn = R.Style and R.Style.n or 0
  local at = c and M_.sat_at(c, dn, sn, 0)

  -- the style's settings along the top (a list when they don't all fit)
  local gx0 = x + 1
  local top = y + 2
  if R.Style then
    local sw = u.switch_positions(track, addr, guid, R.Style.p)
    local room = w * 0.72
    local need = 0
    if sw then
      W.push_small(ctx)
      for _, s_ in ipairs(sw) do need = need + ImGui.CalcTextSize(ctx, (s_.text or ""):upper()) + 16 end
      W.pop_small(ctx)
    end
    if sw and need <= room then
      local hit = chips(ctx, dl, "sast##" .. guid, gx0 + 3, top, room, sw, R.Style.n, function(t) return (t or ""):upper() end)
      if hit then u.set_norm(track, addr, R.Style.p, hit) end
    elseif sw then
      local t = (R.Style.text or ""):upper() .. "  \u{25BE}"
      W.push_small(ctx)
      local tw = ImGui.CalcTextSize(ctx, t)
      W.pop_small(ctx)
      if u.mini_toggle(ctx, dl, "sasl##" .. guid, gx0 + 3, top, tw + 16, 16, true, t, "Its style") then
        ImGui.OpenPopup(ctx, "sasp##" .. guid)
      end
      if ImGui.BeginPopup(ctx, "sasp##" .. guid) then
        for _, s_ in ipairs(sw) do
          if ImGui.Selectable(ctx, s_.text, R.Style.n >= s_.lo - 1e-6 and R.Style.n <= s_.hi + 1e-6) then
            u.set_norm(track, addr, R.Style.p, s_.norm)
          end
        end
        ImGui.EndPopup(ctx)
      end
    else
      u.small_text(ctx, dl, gx0 + 4, top + 2, C.COL.value, "Style " .. (R.Style.text or ""))
    end
  end
  u.small_text(ctx, dl, x + w - 6, top + 2, U.with_alpha(C.COL.accent, 0xc0), at and "learned" or "not learned yet", "right")
  local cy0 = top + 22
  local avail = y + h - cy0 - 2
  local cs = math.floor(w * 0.56)        -- the curve's width; its height is all there is
  local ch = avail
  local cx0 = gx0
  frame(dl, cx0, cy0, w - 2, ch)         -- one ground for the curve, the harmonics and the meter

  -- ---- the curve, input against output, scaled to fit what comes out
  local ymax = 0.05
  if at then for i = 1, M_.SAT_CB do ymax = math.max(ymax, math.abs(at.up[i] or 0), math.abs(at.dn[i] or 0)) end end
  ymax = ymax * 1.06
  if not at then ymax = 1 end
  local function X(v) return cx0 + (v + 1) * 0.5 * cs end
  local function Y(v) return cy0 + ch - (v / ymax + 1) * 0.5 * ch end
  for _, v in ipairs({ -1, -0.5, 0, 0.5, 1 }) do
    grid_v(dl, X(v), cy0, ch)
    grid_h(dl, cx0, cs, cy0 + ch - (v + 1) * 0.5 * ch)
  end
  grid_v(dl, cx0 + cs, cy0, ch)
  -- what it would be if it stayed clean: its small-signal slope, dashed
  local g0 = 1
  if at then
    local a, b = M_.sat_curve(at, -1 / 24), M_.sat_curve(at, 1 / 24)
    if a and b then g0 = (b - a) * 12 end
  end
  do
    local xe = math.min(1, ymax / math.max(1e-6, math.abs(g0)))
    u.dashed(dl, X(-xe), Y(-xe * g0), X(xe), Y(xe * g0), U.with_alpha(C.COL.label, 0x60), 3, 4, 1.0)
  end
  u.small_text(ctx, dl, cx0 + cs - 4, cy0 + ch - 14, U.with_alpha(C.COL.header_dim, 0xa0), "in \u{2192}", "right")
  u.small_text(ctx, dl, cx0 + 4, cy0 + ch * 0.5 - 14, U.with_alpha(C.COL.header_dim, 0xa0), "out")
  local bite
  if at then
    local loop = false
    for i = 1, M_.SAT_CB do
      if at.up[i] and at.dn[i] and math.abs(at.up[i] - at.dn[i]) > 0.03 * ymax then loop = true end
    end
    local n = 96
    local function side(s)
      local xs, ys = {}, {}
      for i = 0, n do
        local xv = -1 + 2 * i / n
        local yv = M_.sat_curve(at, xv, s)
        if yv then xs[#xs + 1], ys[#ys + 1] = X(xv), Y(yv) end
      end
      return xs, ys
    end
    if loop then
      local xu, yu = side("up")
      local xd, yd = side("dn")
      for i = 1, math.min(#xu, #xd) - 1 do
        ImGui.DrawList_AddLine(dl, xu[i], yu[i], xd[i], yd[i], U.with_alpha(C.COL.accent, 0x22), 1.0)
      end
      u.polyline(dl, xu, yu, #xu, C.COL.fader_cap, 2.0)
      u.polyline(dl, xd, yd, #xd, C.COL.fader_cap, 2.0)
    else
      local xs, ys = side(nil)
      u.polyline(dl, xs, ys, #xs, C.COL.fader_cap, 2.2)
    end
    bite = M_.sat_bite(at)
    if bite then
      local bx = X(math.min(1, db_lin(bite)))
      ImGui.DrawList_AddLine(dl, bx, cy0 + ch - 10, bx, cy0 + ch, 0xe6cf79ff, 2.0)
      u.small_text(ctx, dl, bx, cy0 + ch - 24, 0xe6cf79ff, "bites", "centre")
    end
  else
    u.small_text(ctx, dl, cx0 + cs * 0.5, cy0 + ch * 0.62, C.COL.header_dim, "Learn its curve:", "centre")
    u.small_text(ctx, dl, cx0 + cs * 0.5, cy0 + ch * 0.62 + 14, C.COL.header_dim, "\u{22EE} \u{25B8} Canvas setup", "centre")
  end
  -- the drive: a pill on the curve where Drive is along its range, dragged
  -- across -- it follows the mouse
  if R.Drive then
    local f = rev.Drive and (1 - dn) or dn
    local px_ = -0.9 + 1.8 * f
    local py_ = at and M_.sat_curve(at, px_) or px_
    local hx, hy = X(px_), Y(py_)
    local id = "sadr##" .. guid
    local hov, act, dragging = u.handle(ctx, id, hx - 22, hy - 8, 44, 16)
    if dragging then
      local d = ps.drag
      local mx = ImGui.GetMousePos(ctx)
      if not d or d.id ~= id then d = { id = id, mx = mx, f0 = f }; ps.drag = d end
      local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
      local nf = math.max(0, math.min(1, d.f0 + (mx - d.mx) / (cs * 0.9) * fine))
      u.set_norm(track, addr, R.Drive.p, rev.Drive and (1 - nf) or nf)
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    elseif hov then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    ImGui.DrawList_AddRectFilled(dl, hx - 18, hy - 4, hx + 18, hy + 4, (hov or act) and C.COL.header_text or C.COL.accent, 4.0)
    u.small_text(ctx, dl, cx0 + 8, cy0 + 6, C.COL.value, "Drive " .. (R.Drive.text or ""))
    u.small_text(ctx, dl, cx0 + 8, cy0 + 19, U.with_alpha(C.COL.header_dim, 0xc0), "drag across")
    W.tip(ctx, id, ("Drive %s\nDrag left or right (Shift: fine)"):format(R.Drive.text or ""), hov, act)
  end
  -- the music: its peak riding the curve
  local lv = TP.levels(track, guid)
  local live = lv and not lv.old and enabled and lv.in_pk and lv.in_pk > -60
  if live and at then
    local xin = math.min(1, db_lin(lv.in_pk))
    local yv = M_.sat_curve(at, xin)
    if yv then
      local grc = W.gr_fill_col(false, false)
      ImGui.DrawList_AddCircleFilled(dl, X(xin), Y(yv), 8, U.with_alpha(grc, 0x30))
      ImGui.DrawList_AddCircleFilled(dl, X(xin), Y(yv), 4, 0xffd8b0ff)
      ImGui.DrawList_AddCircle(dl, X(xin), Y(yv), 4, grc, 0, 1.4)
    end
  end
  -- its tone controls, output and mix, in the curve's empty corner (bottom
  -- right: a curve runs bottom left to top right, through the middle), by
  -- their own names
  do
    local list = { { R.Tone, own_name(track, addr, R.Tone, "Tone") }, { R.Tone2, own_name(track, addr, R.Tone2, "Tone 2") },
                   { R.Output, "Output" }, { R.Mix, "Mix" } }
    -- two to a row, so they keep clear of the curve
    local have = {}
    for _, k in ipairs(list) do if k[1] then have[#have + 1] = k end end
    local rows = math.ceil(#have / 2)
    for r = 1, rows do
      local row = { have[r * 2 - 1], have[r * 2] }
      knob_box(ctx, dl, ps, track, addr, guid, row, cx0 + cs - 8, cy0 + ch - 34 - (rows - r + 1) * 54)
    end
  end

  -- ---- the harmonics, at the music's level (or -12 dBFS while it's
  -- quiet), against the fundamental, on a dB scale
  local rx, rw = cx0 + cs + 1, x + w - (cx0 + cs + 1) - 2
  local hh = math.floor((avail - 6) * 0.54)
  u.small_text(ctx, dl, rx + 8, cy0 + 5, C.COL.value, "Harmonics")
  local hl = live and math.max(c and c.L[1] or -18, lv.in_pk) or -12
  local hm = at and M_.sat_harm(c, at, hl)
  local sx0 = rx + 34
  local b0, b1 = cy0 + 24, cy0 + hh - 16
  local function hy_(db) return b1 - math.max(0, math.min(1, (db + 80) / 80)) * (b1 - b0) end
  for _, db in ipairs({ 0, -20, -40, -60 }) do
    local yy = hy_(db)
    ImGui.DrawList_AddLine(dl, sx0 - 2, math.floor(yy) + 0.5, rx + rw - 8, math.floor(yy) + 0.5, U.with_alpha(C.COL.eq_grid, 0x70), 1.0)
    u.small_text(ctx, dl, sx0 - 6, yy - 6, U.with_alpha(C.COL.header_dim, 0xc0), db == 0 and "0" or ("\u{2212}%d"):format(-db), "right")
  end
  local bw = (rx + rw - 8 - sx0) / 8
  for k = 2, 9 do
    local bx = sx0 + (k - 2) * bw
    local v = hm and hm[k]
    if v then
      local col = (k % 2 == 0) and 0xe0a33aff or C.COL.accent
      ImGui.DrawList_AddRectFilled(dl, bx + bw * 0.2, hy_(v), bx + bw * 0.8, b1, U.with_alpha(col, 0xd8), 2.0)
    end
    u.small_text(ctx, dl, bx + bw * 0.5, b1 + 2, U.with_alpha(C.COL.header_dim, 0xc0), tostring(k), "centre")
  end
  u.small_text(ctx, dl, rx + rw - 8, cy0 + 5, U.with_alpha(C.COL.header_dim, 0xc0), "dB", "right")

  -- ---- the drive meter: the music's peaks against where the curve bites
  -- (0 dBFS when it never does), moving like a VU
  local my = cy0 + hh + 4
  grid_h(dl, rx, rw, my - 2)
  local lo = M_.SAT_VU_LO
  local over = lo
  if live and at then over = lv.in_pk - (bite or 0) end
  local now = reaper.time_precise()
  local dt = math.max(0, math.min(0.2, now - (ps.sat_t or now))); ps.sat_t = now
  local sv = ps.sat_v or over
  sv = sv + (over - sv) * math.min(1, dt * ((over > sv) and 12 or 3))   -- up quickly, down like a VU
  ps.sat_v = sv
  if sv >= (ps.sat_pk or lo) then ps.sat_pk, ps.sat_pkt = sv, now
  elseif now - (ps.sat_pkt or 0) > 2 then ps.sat_pk = math.max(sv, (ps.sat_pk or lo) - dt * 6) end
  drive_meter(ctx, dl, rx, my, rw, y + h - my - 2, sv, ps.sat_pk or lo, live and enabled and at ~= nil, at ~= nil)
  return true
end

-- ---------------------------------------------------------------------
-- the delay
-- ---------------------------------------------------------------------
local DLY = require("TS_CV_Delay")
local RB = require("TS_CV_ReaFX")
local function nice_step(span_ms)
  for _, s_ in ipairs({ 50, 100, 250, 500, 1000, 2000 }) do if span_ms / s_ <= 8 then return s_ end end
  return 5000
end

-- a switch's settings as chips along a row, or a list when they don't fit
-- in `room`; returns the width it took
local function chip_row(ctx, dl, track, addr, guid, id, m, x, y, room, tip, upper)
  local sw = u.switch_positions(track, addr, guid, m.p)
  if not sw or room < 30 then return 0 end
  local function lab(t) return upper and (t or ""):upper() or (t or "") end
  W.push_small(ctx)
  local need = 0
  for _, s_ in ipairs(sw) do need = need + ImGui.CalcTextSize(ctx, lab(s_.text)) + 16 end
  W.pop_small(ctx)
  if need <= room then
    local hit = chips(ctx, dl, id .. guid .. ":", x, y, room, sw, m.n, lab)
    if hit then u.set_norm(track, addr, m.p, hit) end
    return need
  end
  local t = lab(m.text) .. "  \u{25BE}"
  W.push_small(ctx)
  local tw = ImGui.CalcTextSize(ctx, t)
  W.pop_small(ctx)
  if tw + 16 > room then return 0 end
  if u.mini_toggle(ctx, dl, id .. "l##" .. guid, x, y, tw + 16, 16, true, t, tip) then ImGui.OpenPopup(ctx, id .. "p##" .. guid) end
  if ImGui.BeginPopup(ctx, id .. "p##" .. guid) then
    for _, s_ in ipairs(sw) do
      if ImGui.Selectable(ctx, s_.text, m.n >= s_.lo - 1e-6 and m.n <= s_.hi + 1e-6) then u.set_norm(track, addr, m.p, s_.norm) end
    end
    ImGui.EndPopup(ctx)
  end
  return tw + 20
end

-- The echoes along a timeline: above the line what comes out of the left,
-- below it the right (a mono delay's even both ways), worked out by
-- TS_CV_Delay from whichever controls the plugin has -- one or two lines,
-- or a multi-tap's taps (numbered, the pattern repeating at the faint
-- yellow lines). With sync on the timeline is in note values and drags
-- snap to what the plugin can reach.
local function draw_delay(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = u.panel_state(guid)
  local gx0, gy0, gw, gh = x + 1, y, w - 2, h
  local names = {}
  if R.Mode then local _, nm = reaper.TrackFX_GetParamName(track, addr, R.Mode.p, ""); names.Mode = nm end
  local o = { bpm = reaper.Master_GetTempo(), names = names }
  local mdl = DLY.model(R, cv, o)
  local io = DLY.io(track, addr, guid, u.set_norm)
  local beat = mdl.beat

  local chip_h = 24
  local by = gy0 + gh - chip_h
  -- its filters, under the echoes: the plugin's own, or the selected tap's
  -- (else the first's) with the other taps' faint
  local tone = mdl.tone
  local focus = ps.dl_sel or (mdl.taps and mdl.taps[1] and mdl.taps[1].k)
  if not tone and mdl.tones then tone = mdl.tones[focus or 0] end
  local tone_h = (tone and gh > 260) and 58 or 0
  local tb = by - tone_h
  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, tb, true)
  frame(dl, gx0, gy0, gw, tb - gy0)
  local span = mdl.span or 2000
  local tx0, tx1 = gx0 + 16, gx0 + gw - 10
  local function x_of(t) return tx0 + t / span * (tx1 - tx0) end
  local dim = U.with_alpha(C.COL.header_dim, 0xa0)
  if mdl.beat_grid then
    local sb = M_.dl_beat_step(span / beat)
    local b = 0
    while b * beat <= span + 1e-6 do
      grid_v(dl, x_of(b * beat), gy0, tb - gy0 - 14)
      u.small_text(ctx, dl, x_of(b * beat) + 2, tb - 14, dim, b == 0 and "0" or (M_.dl_note_label(b) or ("%g"):format(b)))
      b = b + sb
    end
  else
    local step = nice_step(span)
    for t = 0, span, step do
      grid_v(dl, x_of(t), gy0, tb - gy0 - 14)
      u.small_text(ctx, dl, x_of(t) + 2, tb - 14, dim,
        t == 0 and "0" or (t >= 1000 and ("%g s"):format(t / 1000) or ("%d ms"):format(t)))
    end
  end
  local mid = gy0 + (tb - gy0 - 14) * 0.5
  local amp = (tb - gy0 - 14) * 0.5 - 14
  local scale = amp * 0.85
  ImGui.DrawList_AddLine(dl, gx0, mid, gx0 + gw, mid, U.with_alpha(C.COL.knob_ring, 0xa0), 1.0)
  if mdl.stereo then
    u.small_text(ctx, dl, gx0 + 4, gy0 + 4, C.COL.header_dim, "L")
    u.small_text(ctx, dl, gx0 + 4, tb - 30, C.COL.header_dim, "R")
  end
  -- a multi-tap's pattern repeating
  if mdl.taps and mdl.period then
    local r = 1
    while r * mdl.period <= span and r < 40 do
      local xx = x_of(r * mdl.period)
      u.dashed(dl, xx, gy0, xx, tb - 14, 0xe6cf7950, 4, 4, 1.0)
      r = r + 1
    end
  end
  -- the dry sound, then the echoes
  ImGui.DrawList_AddLine(dl, x_of(0), mid - amp, x_of(0), mid + amp, U.with_alpha(C.COL.label, 0x90), 3.0)
  for i, e in ipairs(mdl.echoes) do
    local xx = x_of(e.t)
    local fade = (e.tag and e.tag.r) and (e.tag.r == 0 and 0xff or math.max(0x50, 0xd0 - e.tag.r * 0x18))
                 or math.max(0x50, 0xff - (i - 1) * 0x14)
    local col = U.with_alpha(C.COL.accent, fade)
    if e.l * scale > 0.5 then ImGui.DrawList_AddLine(dl, xx, mid, xx, mid - e.l * scale, col, 4.0) end
    if e.r * scale > 0.5 then ImGui.DrawList_AddLine(dl, xx, mid, xx, mid + e.r * scale, col, 4.0) end
  end
  -- each side's decay, dashed through its own echoes
  for sd, pts in pairs(mdl.decay or {}) do
    local px_, py_
    for _, q in ipairs(pts) do
      local yy = sd == "L" and (mid - q[2] * scale) or (mid + q[2] * scale)
      if px_ then u.dashed(dl, px_, py_, x_of(q[1]), yy, U.with_alpha(C.COL.accent, 0x90), 3, 3, 1.0) end
      px_, py_ = x_of(q[1]), yy
    end
  end
  -- a multi-tap's: each tap through its own repeats
  for _, ch in ipairs(mdl.chains or {}) do
    for i = 2, #ch do
      u.dashed(dl, x_of(ch[i - 1][1]), mid - ch[i - 1][2] * scale, x_of(ch[i][1]), mid - ch[i][2] * scale,
        U.with_alpha(C.COL.accent, 0x90), 3, 3, 1.0)
    end
  end
  ImGui.DrawList_PopClipRect(dl)

  -- the handles: drag across for a time, up or down for a level or the
  -- feedback (a tap's dot does both, whichever way it's dragged first). A
  -- tap's dot clicked selects it (its own controls top right, its own
  -- feedback's dot); the wheel over one pans it.
  local sel = ps.dl_sel
  local any_hov = false
  for _, hd in ipairs(mdl.handles) do
    local px = x_of(hd.t)
    local py = hd.side == "top" and (gy0 + 12) or (hd.side == "L" and (mid - hd.h * scale) or (mid + hd.h * scale))
    if px <= tx1 + 4 and not (hd.only and hd.only ~= sel) and py < tb then
      if hd.num and hd.num == sel then ImGui.DrawList_AddCircle(dl, px, py, 11, 0xe6cf79ff, 0, 1.8) end
      local dirs = (hd.across and hd.updown) and "Drag across for its time, up or down for its level"
                   or hd.across and "Drag left or right" or "Drag up or down"
      local tip = ((hd.num and ("Tap %d  "):format(hd.num) or "") .. (hd.label or "")) .. "\n" .. dirs
      if hd.num then tip = tip .. "\nClick: its own controls" .. (hd.haspan and "  \u{00B7}  Wheel: its pan" or "") end
      local hov, act = node(ctx, dl, ps, "rld" .. hd.id .. "##" .. guid, px, py, tip,
        function(dx, dy, d)
          if not d.axis and (math.abs(dx) > 3 or math.abs(dy) > 3) then
            if hd.across and hd.updown then d.axis = (math.abs(dx) >= math.abs(dy)) and "x" or "y"
            else d.axis = hd.across and "x" or "y" end
            ps.dl_moved = true
          end
          if d.axis == "x" and hd.across then
            d.t0 = d.t0 or hd.tq0 or hd.t
            DLY.apply(R, cv, o, io, hd.id, "t", math.max(1, d.t0 + dx / (tx1 - tx0) * span))
          elseif d.axis == "y" and hd.updown then
            d.hd = d.hd or { k = hd.k, pow = hd.pow, v0 = hd.v0, side = hd.side }
            DLY.apply(R, cv, o, io, hd.id, "v", DLY.drag_value(d.hd, dy, scale))
          end
        end,
        { cursor = (hd.across and hd.updown) and ImGui.MouseCursor_ResizeAll
                   or (hd.across and ImGui.MouseCursor_ResizeEW or ImGui.MouseCursor_ResizeNS), r = hd.num and 7 or (hd.own and 4) or 5 })
      if hov or act then any_hov = true end
      if hd.num then
        if hov and ImGui.IsMouseClicked(ctx, 0) then ps.dl_press, ps.dl_moved = hd.num, false end
        if hov and hd.haspan then
          local wv = W.control_wheel(ctx)
          if wv ~= 0 then
            W.take_wheel()
            DLY.apply(R, cv, o, io, "p" .. hd.num, "v", math.max(-1, math.min(1, (hd.pan or 0) + (wv > 0 and 0.05 or -0.05))))
          end
        end
      end
      if hd.num then
        u.small_text(ctx, dl, px, py - 6, C.COL.win_bg, tostring(hd.num), "centre")
      elseif hd.label and not (hd.own and hd.own ~= sel and not hov) then
        u.small_text(ctx, dl, px + 9, (hd.side == "R" or hd.side == "top") and (py + 4) or (py - 16), C.COL.value, hd.label)
      end
    end
  end

  -- the filters: the pass band lit between the cuts, each cut a node to
  -- drag across
  if tone_h > 0 then
    local sy0, sy1 = tb + 6, by - 2
    frame(dl, gx0, sy0, gw, sy1 - sy0)
    local fx0, fx1 = gx0 + 10, gx0 + gw - 10
    local function fxp(f) return fx0 + math.log(math.max(20, math.min(20000, f)) / 20) / math.log(1000) * (fx1 - fx0) end
    local fy0, fy1 = sy0 + 16, sy1 - 6
    for _, g in ipairs({ 100, 1000, 10000 }) do
      grid_v(dl, fxp(g), fy0 - 2, fy1 - fy0 + 2)
      u.small_text(ctx, dl, fxp(g) + 2, sy1 - 14, U.with_alpha(C.COL.header_dim, 0x90), g >= 1000 and (g // 1000 .. "k") or tostring(g))
    end
    u.small_text(ctx, dl, gx0 + 6, sy0 + 2, C.COL.header_dim, (tone.k and ("Tap %d  "):format(tone.k) or "") .. "Filters")
    -- a response, 12 dB an octave either side, across fy0 (0 dB) .. fy1 (-24)
    local function resp_y(t, f)
      local db = 0
      if t.lc and t.lc > 21 and f < t.lc then db = db - 12 * math.log(t.lc / f, 2) end
      if t.hc and t.hc < 19900 and f > t.hc then db = db - 12 * math.log(f / t.hc, 2) end
      return fy0 + math.min(1, -db / 24) * (fy1 - fy0)
    end
    local function curve(t, col, w_)
      local xs, ys = {}, {}
      for i = 0, 90 do local f = 20 * 1000 ^ (i / 90); xs[#xs + 1] = fxp(f); ys[#ys + 1] = resp_y(t, f) end
      u.polyline(dl, xs, ys, #xs, col, w_)
    end
    if mdl.tones and not mdl.tone then
      for k, t in pairs(mdl.tones) do if k ~= tone.k then curve(t, U.with_alpha(C.COL.accent, 0x40), 1.0) end end
    end
    local a_ = tone.lc and math.max(fx0, fxp(tone.lc)) or fx0
    local b_ = tone.hc and math.min(fx1, fxp(tone.hc)) or fx1
    ImGui.DrawList_AddRectFilled(dl, a_, fy0, b_, fy1, U.with_alpha(C.COL.accent, 0x18))
    curve(tone, C.COL.accent, 1.8)
    -- the two labels: beside their nodes, inwards; turned outwards when
    -- they'd meet, the high cut's a line down when even that won't do
    local lab = {}
    W.push_small(ctx)
    for _, c in ipairs({ { "lc", tone.lc, tone.lct, "Low cut" }, { "hc", tone.hc, tone.hct, "High cut" } }) do
      if c[2] then lab[c[1]] = { t = c[4] .. " " .. (c[3] or ""), w = ImGui.CalcTextSize(ctx, c[4] .. " " .. (c[3] or "")) } end
    end
    W.pop_small(ctx)
    local lx = { lc = { a_ + 8, nil }, hc = { b_ - 8, "right" } }
    local hc_dy = 0
    if lab.lc and lab.hc and a_ + 8 + lab.lc.w + 6 > b_ - 8 - lab.hc.w then
      lx.lc, lx.hc = { a_ - 8, "right" }, { b_ + 8, nil }
      if a_ - 8 - lab.lc.w < fx0 - 6 or b_ + 8 + lab.hc.w > fx1 + 6 then
        lx.lc, lx.hc, hc_dy = { a_ + 8, nil }, { b_ - 8, "right" }, 12
        if b_ - 8 - lab.hc.w < fx0 then lx.hc = { b_ + 8, nil } end
        if a_ + 8 + lab.lc.w > fx1 then lx.lc = { a_ - 8, "right" } end
      end
    end
    for _, c in ipairs({ { "lc", tone.lc, tone.lct, "Low cut" }, { "hc", tone.hc, tone.hct, "High cut" } }) do
      if c[2] then
        local nx = (c[1] == "lc") and a_ or b_
        local ny = fy0
        local id = c[1] .. (tone.k and tostring(tone.k) or "")
        node(ctx, dl, ps, "rlf" .. id .. "##" .. guid, nx, ny, ("%s %s\nDrag left or right"):format(c[4], c[3] or ""),
          function(dx, _, d)
            d.f0 = d.f0 or math.max(20, math.min(20000, c[2]))
            DLY.apply(R, cv, o, io, id, "f", d.f0 * 1000 ^ (dx / (fx1 - fx0)))
          end, { r = 5, cursor = ImGui.MouseCursor_ResizeEW })
        local L_ = lx[c[1]]
        u.small_text(ctx, dl, L_[1], ny - 1 + ((c[1] == "hc") and hc_dy or 0), C.COL.value, lab[c[1]].t, L_[2])
      end
    end
  end

  if ImGui.IsMouseReleased(ctx, 0) and ps.dl_press then
    if not ps.dl_moved then ps.dl_sel = (ps.dl_sel == ps.dl_press) and nil or ps.dl_press end
    ps.dl_press = nil
  end

  -- the row along the foot: sync, link, ping-pong, its mode, the taps'
  -- switches, the notes
  local cx = gx0 + 4
  local fx1 = gx0 + gw - 4
  if R.Sync then
    local sw = u.switch_positions(track, addr, guid, R.Sync.p)
    if sw and #sw > 2 then
      local used = chip_row(ctx, dl, track, addr, guid, "rlsy", R.Sync, cx, by + 4, (fx1 - cx) * 0.4, "Its tempo sync", true)
      cx = cx + used + 4
    else
      if u.mini_toggle(ctx, dl, "rlsy##" .. guid, cx, by + 4, 40, 16, mdl.sync, "SYNC", "Sync to the tempo") then u.flip(track, addr, R.Sync.p) end
      cx = cx + 44
    end
  end
  if R.Link then
    if u.mini_toggle(ctx, dl, "rllk##" .. guid, cx, by + 4, 40, 16, DLY.on_of(R.Link), "LINK", "The right follows the left") then u.flip(track, addr, R.Link.p) end
    cx = cx + 44
  end
  if R.PingPong then
    if u.mini_toggle(ctx, dl, "rlpp##" .. guid, cx, by + 4, 70, 16, DLY.on_of(R.PingPong), "PING-PONG", "Echoes alternate left and right") then u.flip(track, addr, R.PingPong.p) end
    cx = cx + 74
  end
  if R.Mode then
    local used = chip_row(ctx, dl, track, addr, guid, "rlmd", R.Mode, cx + 4, by + 4, (fx1 - cx) * 0.5, "Its stereo mode", true)
    if used > 0 then cx = cx + 4 + used + 4 end
  end
  if mdl.taps then
    for _, tp in ipairs(mdl.taps) do
      local m = R["T" .. tp.k .. "On"]
      if m and cx + 26 <= fx1 then
        if u.mini_toggle(ctx, dl, "rlto" .. tp.k .. "##" .. guid, cx, by + 4, 22, 16, tp.on, tostring(tp.k), ("Tap %d on or off"):format(tp.k)) then
          u.set_norm(track, addr, m.p, tp.on and 0 or 1)
        end
        cx = cx + 26
      end
    end
    -- ReaDelay: a tap more (up to ten)
    if cv.builtin == "readelay" and #mdl.taps < M_.DL_TAPS and cx + 26 <= fx1 then
      if u.mini_toggle(ctx, dl, "rltadd##" .. guid, cx, by + 4, 22, 16, false, "+", "Add a tap") then
        if RB.add_tap(track, addr) then ps.dl_sel = #mdl.taps + 1 end
      end
      cx = cx + 26
    end
  end
  local nsrc = R.Note or (mdl.main and mdl.main.src and UN.note_beats(mdl.main.src.text or "") and mdl.main.src) or nil
  if nsrc then
    local used = chip_row(ctx, dl, track, addr, guid, "rlch", nsrc, cx + 4, by + 4, fx1 - cx - 4, "Its note value", false)
    cx = cx + 4 + used + 4
  end
  if R.Rhythm then chip_row(ctx, dl, track, addr, guid, "rlrh", R.Rhythm, cx + 4, by + 4, fx1 - cx - 4, "Straight, dotted, triplet", true) end
  -- top right: the selected tap's own controls, else cross, width and mix
  local kb_w, kb_h = 0, 0
  local st = sel and mdl.taps and mdl.taps[sel] and sel or nil
  if not st then ps.dl_sel = nil end
  if st then
    local pre = "T" .. st
    local list = { { R[pre .. "Pan"], "Pan" }, { R[pre .. "Level"], "Level" }, { R[pre .. "Feedback"], "Feedback" } }
    local n = 0
    for _, k in ipairs(list) do if k[1] then n = n + 1 end end
    local bx1 = gx0 + gw - 6
    if n > 0 then knob_box(ctx, dl, ps, track, addr, guid, list, bx1, gy0 + 6); kb_w, kb_h = n * 52 + 4, 50 end
    local tw = math.max(kb_w, 96)
    u.small_text(ctx, dl, bx1 - tw, gy0 + 6 + kb_h + 4, 0xe6cf79ff, ("Tap %d"):format(st))
    local tx = bx1
    -- ReaDelay: the tap taken away
    if cv.builtin == "readelay" then
      local okr, why = RB.can_remove(track, addr, st, #mdl.taps)
      tx = tx - 58
      ImGui.BeginDisabled(ctx, not okr)
      if u.mini_toggle(ctx, dl, "rltrm##" .. guid, tx, gy0 + 6 + kb_h + 2, 58, 16, false, "REMOVE", okr and "Take this tap away" or why) then
        if RB.remove_tap(track, addr, st) then ps.dl_sel = nil end
      end
      ImGui.EndDisabled(ctx)
      tx = tx - 4
    end
    for _, sw_ in ipairs({ { R[pre .. "On"], "ON", "The tap on or off" }, { R[pre .. "PingPong"], "PING-PONG", "The tap ping-pongs" } }) do
      if sw_[1] then
        local wdt = (sw_[2] == "ON") and 30 or 70
        tx = tx - wdt
        local is_on = DLY.on_of(sw_[1])
        if u.mini_toggle(ctx, dl, "rlts" .. sw_[2] .. "##" .. guid, tx, gy0 + 6 + kb_h + 2, wdt, 16, is_on, sw_[2], sw_[3]) then
          u.set_norm(track, addr, sw_[1].p, is_on and 0 or 1)
        end
        tx = tx - 4
      end
    end
    kb_w, kb_h = tw, kb_h + 22
  else
    local n = 0
    for _, k in ipairs({ R.Cross, R.Width, R.Mix, R.Dry }) do if k then n = n + 1 end end
    knob_box(ctx, dl, ps, track, addr, guid, { { R.Cross, "Cross" }, { R.Width, "Width" },
      { R.Mix, R.Dry and "Wet" or "Mix" }, { R.Dry, "Dry" } }, gx0 + gw - 6, gy0 + 6)
    if n > 0 then kb_w, kb_h = n * 52 + 4, 50 end
  end
  -- a click on the canvas away from the dots and that corner: nothing selected
  if ps.dl_sel and ImGui.IsMouseClicked(ctx, 0) and not any_hov and not ps.dl_press then
    local mx, my = ImGui.GetMousePos(ctx)
    local in_canvas = mx >= gx0 and mx <= gx0 + gw and my >= gy0 and my <= tb
    local in_box = mx >= gx0 + gw - 6 - kb_w and my <= gy0 + 6 + kb_h
    if in_canvas and not in_box then ps.dl_sel = nil end
  end
  return true
end

-- ---------------------------------------------------------------------
-- the reverb
-- ---------------------------------------------------------------------
-- ---------------------------------------------------------------------
-- the reverb's decay by frequency
-- ---------------------------------------------------------------------
-- Decay time's multiplier at fq Hz: the lows' (bass) below their
-- crossover lf, the highs' (dmul) above theirs hf, smoothly between.
function RP.rv_mult(fq, lf, bass, hf, dmul)
  local wl = 1 / (1 + (fq / lf) ^ 2)
  local wh = 1 / (1 + (hf / fq) ^ 2)
  return math.exp(wl * math.log(math.max(0.01, bass)) + wh * math.log(math.max(0.01, dmul)))
end

-- Its diffusion, 0..1 (nil when it has none mapped: drawn as before).
function RP.rv_diffusion(m, rv)
  if not m then return nil end
  if m.unit == "pct" and m.v then return math.max(0, math.min(1, m.v / 100)) end
  return rv and (1 - m.n) or m.n
end

-- The lows' decay multiplier: a multiplier as it reads (x1.2), a time of
-- its own against the decay, a percentage, or along its range (x0.5..x2).
function RP.rv_bass(m, rv, dec)
  if not m then return 1 end
  local v, un = m.v, m.unit
  if v and un == "" and v > 0 and v < 10 then return v end
  if v and un == "ms" and dec and dec > 0 then return math.max(0.1, math.min(4, v / dec)) end
  if v and un == "pct" and v > 0 then return v / 100 end
  local n = rv and (1 - m.n) or m.n
  return 0.5 * 4 ^ n
end
function RP.rv_set_bass(track, addr, m, rv, dec, mul)
  if not m then return end
  local v, un = m.v, m.unit
  if v and un == "" and v > 0 and v < 10 then u.set_to(track, addr, m.p, mul)
  elseif v and un == "ms" and dec and dec > 0 then u.set_to(track, addr, m.p, mul * dec)
  elseif v and un == "pct" and v > 0 then u.set_to(track, addr, m.p, mul * 100)
  else
    local n = math.max(0, math.min(1, math.log(math.max(0.5, math.min(2, mul)) / 0.5) / math.log(4)))
    u.set_norm(track, addr, m.p, rv and (1 - n) or n)
  end
end

-- The highs' decay multiplier from a damping control. A time of its own
-- (against the decay) or a multiplier (a control running within x0..x2)
-- is taken as it reads. Anything else -- dB or % of damping, a scale of
-- its own -- is how far along its range it is, the end reading more
-- damping (the larger dB or %) the most: none is x1, all of it x0.25 (the
-- foot of the strip), so the whole control is in reach. v0, v1: its
-- readings at either end.
local function damp_up(rv, v0, v1)
  local up = true
  if v0 and v1 and v0 ~= v1 then up = math.abs(v1) > math.abs(v0) end
  if rv then up = not up end
  return up
end
local function damp_mult_of(v0, v1)
  return v0 and v1 and math.min(v0, v1) >= 0 and math.max(v0, v1) <= 2 and math.max(v0, v1) > 0
end
function RP.rv_damp(m, rv, dec, v0, v1)
  if not m then return 1 end
  local v, un = m.v, m.unit
  if v and un == "ms" and dec and dec > 0 then return math.max(0.05, math.min(4, v / dec)) end
  if v and un == "" and v > 0 and damp_mult_of(v0, v1) then return v end
  local f = damp_up(rv, v0, v1) and m.n or (1 - m.n)
  return 0.25 ^ f
end
function RP.rv_set_damp(track, addr, guid, m, rv, dec, mul, v0, v1)
  if not m then return end
  local v, un = m.v, m.unit
  if v and un == "ms" and dec and dec > 0 then u.set_to(track, addr, m.p, math.max(0.05, mul) * dec) return end
  if v and un == "" and v > 0 and damp_mult_of(v0, v1) then u.set_to(track, addr, m.p, math.max(0.05, math.min(2, mul))) return end
  local f = math.max(0, math.min(1, math.log(math.max(0.25, math.min(1, mul))) / math.log(0.25)))
  u.set_norm(track, addr, m.p, damp_up(rv, v0, v1) and f or (1 - f))
end

-- an early / late balance (TS_CV_Units UN.balance_*)
RP.rv_bal_text, RP.rv_bal_along, RP.rv_bal_table = UN.balance_text, UN.balance_along, UN.balance_table
RP.rv_bal_at, RP.rv_bal_norm = UN.balance_at, UN.balance_norm
-- A tilt (a tone or brightness control, -1..1) at fq Hz: x4 brighter at
-- 20 kHz at the top of it, the lows as much the other way
function RP.rv_tilt(t, fq) return 4 ^ ((t or 0) * math.log(fq / 1000, 2) / math.log(20, 2)) end
-- A wet low / high shelf's gain at fq Hz (dB each)
function RP.rv_shelves(lo, hi, fq)
  return (lo or 0) / (1 + (fq / 150) ^ 2) + (hi or 0) / (1 + (6000 / fq) ^ 2)
end

-- A decay control reading plain numbers in a seconds-like range (0.50 ..
-- 39.40, "Infinite": SuperPlate's): seconds. Read once per control.
local function plain_secs(track, addr, ps, m)
  ps.psec = ps.psec or {}
  local c = ps.psec[m.p]
  if c == nil then
    local fm = UN.formatter(track, addr, m.p)
    local a, ua = UN.at(fm, 0)
    local b, ub = UN.at(fm, 0.9)
    c = (a and b and ua == "" and ub == "" and a >= 0.05 and b > a and b <= 200) or false
    ps.psec[m.p] = c
  end
  return c
end
RP.plain_secs = plain_secs

local function draw_reverb(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = u.panel_state(guid)
  local rev = cv.rev or {}
  local gx0, gy0, gw, gh = x + 1, y, w - 2, h
  local pre, pre_along = val(R.Predelay, "ms", 0, 250, false, rev.Predelay)
  pre = pre or 0
  local dec, dec_along = val(R.Decay, "ms", 100, 20000, true, rev.Decay)
  -- measured: a decay that reads in a scale of its own (0..100), timed
  local M_ = require("TS_CV_Mappings")
  local dec_cal = R.Decay and M_.dec_cal(cv)
  local size_n = R.Size and R.Size.n or nil
  if dec_cal then dec = M_.decay_ms(cv, R.Decay.n, size_n) or dec end
  -- held: its freeze on, or a decay reading "Infinite"
  local frozen = (R.Freeze and DLY.on_of(R.Freeze)) or false
  local dec_secs = false
  if R.Decay and not dec_cal and (R.Decay.unit == "" or R.Decay.unit == nil) then
    if (R.Decay.text or ""):lower():find("inf", 1, true) then frozen = true
    elseif R.Decay.v and plain_secs(track, addr, ps, R.Decay) then dec, dec_along, dec_secs = R.Decay.v * 1000, false, true end
  end
  dec = dec or 2000
  u.db_ish(track, addr, guid, R.Early)
  local early = -6
  local early_along = false
  if R.Early then
    if R.Early.unit == "db" and R.Early.v then early = math.max(-60, R.Early.v)
    elseif R.Early.unit == "pct" and R.Early.v then early = (R.Early.v > 0) and 20 * math.log(R.Early.v / 100, 10) or -60
    else early, early_along = -36 + (rev.Early and (1 - R.Early.n) or R.Early.n) * 36, true end
  end
  -- the late reverb's level against the early reflections' (Balance)
  local late0 = early
  local bal, btab
  if R.Balance then
    ps.btab = ps.btab or {}
    local bt = ps.btab[R.Balance.p]
    if bt == nil or (bt == false and reaper.time_precise() - (ps.btab_at or 0) > 2) then
      bt = RP.rv_bal_table(UN.formatter(track, addr, R.Balance.p)) or false
      ps.btab[R.Balance.p], ps.btab_at = bt, reaper.time_precise()
    end
    btab = bt or nil
    bal = btab and RP.rv_bal_at(btab, R.Balance.n) or RP.rv_bal_text(R.Balance.text)
    if not bal then bal = RP.rv_bal_along(rev.Balance and (1 - R.Balance.n) or R.Balance.n) end
    if not R.Early then early = math.min(0, bal) - 2 end
    late0 = math.min(0, -bal)
  end
  local size = R.Size and (rev.Size and (1 - R.Size.n) or R.Size.n) or 0.5
  local diff = RP.rv_diffusion(R.Diffusion, rev.Diffusion)

  local strip = (R.Damping or R.Bass or R.LowFreq or R.HighFreq or R.LowCut or R.HighCut or R.Tone
                 or R.LowEQ or R.HighEQ) and 116 or 0
  local top_h = gh - strip - (strip > 0 and 6 or 0)
  local span = math.max(1000, math.ceil((pre + dec) * 1.2 / 500) * 500)
  local tx0, tx1 = gx0 + 22, gx0 + gw - 12
  -- its character's chips and the freeze along the top
  local top_row = (R.Style or R.Freeze) and 22 or 0
  local ty0, ty1 = gy0 + 22 + top_row, gy0 + top_h - 18
  local function x_of(t) return tx0 + t / span * (tx1 - tx0) end
  local function y_of(db) return ty0 + (-db) / 66 * (ty1 - ty0) end
  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + top_h, true)
  frame(dl, gx0, gy0, gw, top_h)
  local step = nice_step(span)
  for t = 0, span, step do
    grid_v(dl, x_of(t), ty0 - 10, ty1 - ty0 + 10)
    u.small_text(ctx, dl, x_of(t) + 2, ty1 + 2, U.with_alpha(C.COL.header_dim, 0xa0),
      t == 0 and "0" or (t >= 1000 and ("%g s"):format(t / 1000) or ("%d ms"):format(t)))
  end
  for _, db in ipairs({ 0, -20, -40, -60 }) do
    grid_h(dl, gx0, gw, y_of(db))
    u.small_text(ctx, dl, gx0 + 3, y_of(db) - 11, U.with_alpha(C.COL.header_dim, 0xa0), tostring(db))
  end
  -- the gap before it starts
  ImGui.DrawList_AddRectFilled(dl, x_of(0) + 2, ty0 - 10, x_of(pre), ty1, U.with_alpha(C.COL.header_text, 0x0a))
  ImGui.DrawList_AddLine(dl, x_of(0), y_of(0), x_of(0), ty1, U.with_alpha(C.COL.label, 0x90), 3.0)
  -- early reflections (their spacing grows with the size)
  -- (more of them, closer together, the more diffuse it is)
  local er_col = 0xe0a33acc
  local spread = 20 + size * 90
  local ner = diff and math.floor(8 + diff * 22) or 14
  for i = 0, ner - 1 do
    local t = pre + i * spread / ner + ((i * 37) % 7) * (1 - (diff or 0) * 0.6)
    local db = early - i * 1.4 * 13 / ner - ((i * 53) % 5)
    ImGui.DrawList_AddLine(dl, x_of(t), ty1, x_of(t), y_of(db), er_col, (diff or 0) > 0.6 and 1.1 or 1.6)
  end
  -- the tail, falling 60 dB over the decay time (held, frozen)
  local t_dec = pre + dec * (52 / 60)
  local t_end = frozen and span or t_dec
  local function tail_db(t) return frozen and (late0 - 2) or math.max(-66, late0 - 2 - 60 * (t - pre) / dec) end
  local xs, ys = {}, {}
  local t0 = pre + spread * 0.5
  for i = 0, 40 do
    local t = t0 + (t_end - t0) * i / 40
    xs[#xs + 1], ys[#ys + 1] = x_of(t), y_of(tail_db(t))
  end
  for i = 1, #xs - 1 do
    ImGui.DrawList_AddRectFilled(dl, xs[i], math.min(ys[i], ys[i + 1]), xs[i + 1], ty1, U.with_alpha(C.COL.accent, 0x2e))
  end
  -- a grainy tail when it isn't diffuse: separate echoes, not a wash
  if diff and diff < 0.85 then
    local nsp = math.floor(30 + diff * 90)
    local grain = (1 - diff) * 14
    for i = 0, nsp - 1 do
      local t = t0 + (t_end - t0) * (i + 0.5) / nsp
      local db = tail_db(t) - grain * (((i * 7919) % 13) / 13)
      ImGui.DrawList_AddLine(dl, x_of(t), ty1, x_of(t), y_of(db), U.with_alpha(C.COL.accent, math.floor(0x40 + 0x60 * (1 - diff))), 1.0)
    end
  end
  u.polyline(dl, xs, ys, #xs, C.COL.accent, 2.0)
  ImGui.DrawList_PopClipRect(dl)

  -- the handles
  if R.Predelay then
    node(ctx, dl, ps, "rvpd##" .. guid, x_of(pre), y_of(-2), ("Pre-delay %s\nDrag left or right"):format(R.Predelay.text or ""),
      function(dx, _, d)
        d.v0 = d.v0 or pre
        local nv = math.max(0, d.v0 + dx / (tx1 - tx0) * span)
        local n = nearest_setting(track, addr, guid, R.Predelay, function(t) return UN.time_ms(t) end, math.max(0.1, nv), false)
        if n then u.set_norm(track, addr, R.Predelay.p, n)
        else set_val(track, addr, R.Predelay, nv, pre_along, 0, 250, false, rev.Predelay) end
      end, { cursor = ImGui.MouseCursor_ResizeEW })
    u.small_text(ctx, dl, x_of(pre) + 8, y_of(-2) - 14, C.COL.value, "Pre-delay " .. (R.Predelay.text or ""))
  end
  if R.Decay then
    local dx_, dy_ = x_of(math.min(span, t_dec)), y_of(-60)
    node(ctx, dl, ps, "rvdc##" .. guid, dx_, dy_, ("Decay %s\nDrag left or right"):format(R.Decay.text or ""),
      function(dx, _, d)
        d.v0 = d.v0 or dec
        local nv = math.max(50, d.v0 + dx / (tx1 - tx0) * span / (52 / 60))
        if dec_cal then
          local n = M_.decay_pos(cv, nv, size_n)
          if n then u.set_norm(track, addr, R.Decay.p, n) end
          return
        end
        if dec_secs then u.set_to(track, addr, R.Decay.p, nv / 1000) return end
        local n = nearest_setting(track, addr, guid, R.Decay, function(t) return UN.time_ms(t) end, nv, true)
        if n then u.set_norm(track, addr, R.Decay.p, n)
        else set_val(track, addr, R.Decay, nv, dec_along, 100, 20000, true, rev.Decay) end
      end, { cursor = ImGui.MouseCursor_ResizeEW })
    local dl_ = "Decay " .. (R.Decay.text or "")
    if dec_cal then dl_ = dl_ .. ("  \u{00B7}  %.2f s"):format(dec / 1000)
    elseif dec_secs then dl_ = dl_ .. " s"
    elseif dec_along and not frozen then dl_ = dl_ .. "  (not in seconds: Set up \u{25B8} Measure decay)" end
    if frozen then dl_ = dl_ .. "  \u{00B7}  frozen" end
    u.small_text(ctx, dl, math.min(dx_ + 8, gx0 + gw - (dec_cal and 150 or 90)), dy_ - 16, C.COL.value, dl_)
  end
  if R.Early then
    local ex, ey = x_of(pre + 6), y_of(early)
    node(ctx, dl, ps, "rver##" .. guid, ex, ey, ("Early reflections %s\nDrag up or down"):format(R.Early.text or ""),
      function(_, dy, d)
        d.v0 = d.v0 or early
        local nv = math.max(-60, math.min(0, d.v0 - dy * 66 / (ty1 - ty0)))
        if early_along then
          local n = (nv + 36) / 36
          u.set_norm(track, addr, R.Early.p, math.max(0, math.min(1, rev.Early and (1 - n) or n)))
        elseif R.Early.unit == "pct" then u.set_to(track, addr, R.Early.p, 100 * 10 ^ (nv / 20))
        else u.set_to(track, addr, R.Early.p, nv) end
      end, { r = 4, fill = er_col, ring = C.COL.header_text, cursor = ImGui.MouseCursor_ResizeNS })
    u.small_text(ctx, dl, ex + 8, ey + 4, 0xe6cf79ff, "Early " .. (R.Early.text or ""))
  elseif R.Balance then
    -- the balance: up, the early reflections over the late reverb
    local ex, ey = x_of(pre + 6), y_of(early)
    node(ctx, dl, ps, "rvbl##" .. guid, ex, ey, ("Early / late %s\nDrag up or down"):format(R.Balance.text or ""),
      function(_, dy, d)
        d.v0 = d.v0 or bal
        local nv = math.max(-60, math.min(24, d.v0 - dy * 66 / (ty1 - ty0)))
        local n
        if btab then n = RP.rv_bal_norm(btab, nv)
        else
          n = 1 / (1 + 10 ^ (nv / 20))
          if rev.Balance then n = 1 - n end
        end
        u.set_norm(track, addr, R.Balance.p, math.max(0, math.min(1, n)))
      end, { r = 4, fill = er_col, ring = C.COL.header_text, cursor = ImGui.MouseCursor_ResizeNS })
    u.small_text(ctx, dl, ex + 8, ey + 4, 0xe6cf79ff, "Early / late " .. (R.Balance.text or ""))
  end
  -- along the top: its character, and its freeze
  if top_row > 0 then
    local cx = gx0 + 4
    local room = gw - 8 - 170
    if R.Style then
      local used = chip_row(ctx, dl, track, addr, guid, "rvst", R.Style, cx, gy0 + 4, room - 70, "Its character", true)
      cx = cx + used + 8
    end
    if R.Freeze then
      local on = DLY.on_of(R.Freeze)
      if u.mini_toggle(ctx, dl, "rvfz##" .. guid, cx, gy0 + 4, 58, 16, on, "FREEZE", "Hold the reverb where it is") then
        u.set_norm(track, addr, R.Freeze.p, on and 0 or 1)
      end
    end
  end
  knob_box(ctx, dl, ps, track, addr, guid, { { R.Size, "Size" }, { R.Diffusion, "Diffusion" }, { R.Mix, "Mix" } }, gx0 + gw - 6, gy0 + 6)

  -- how the decay changes with frequency: a multiplier on the decay time,
  -- the lows' below their crossover, the highs' (damping) above theirs;
  -- the cuts on the wet signal shaded at the ends
  if strip > 0 then
    local sy0 = gy0 + top_h + 6
    frame(dl, gx0, sy0, gw, strip)
    u.small_text(ctx, dl, gx0 + 6, sy0 + 3, C.COL.header_dim, (R.LowCut or R.HighCut) and "Decay by frequency  \u{00B7}  filters" or "Decay by frequency")
    -- the cuts' own switches, at its top right
    local lc_on = (not R.LowCutOn) or DLY.on_of(R.LowCutOn)
    local hc_on = (not R.HighCutOn) or DLY.on_of(R.HighCutOn)
    do
      local bx = gx0 + gw - 8
      for _, sw_ in ipairs({ { R.HighCutOn, hc_on, "HIGH CUT", "rvhcn" }, { R.LowCutOn, lc_on, "LOW CUT", "rvlcn" } }) do
        if sw_[1] then
          bx = bx - 62
          if u.mini_toggle(ctx, dl, sw_[4] .. "##" .. guid, bx, sy0 + 2, 58, 14, sw_[2], sw_[3], "Its " .. sw_[3]:lower() .. " on or off") then
            u.set_norm(track, addr, sw_[1].p, sw_[2] and 0 or 1)
          end
          bx = bx - 4
        end
      end
    end
    local fx0, fx1 = gx0 + 10, gx0 + gw - 10
    local function fxp(f) return fx0 + math.log(math.max(F_LO, math.min(F_HI, f)) / F_LO) / math.log(F_HI / F_LO) * (fx1 - fx0) end
    local my0, my1 = sy0 + 18, sy0 + strip - 8
    local M_LO, M_HI = 0.25, 4
    local function my(mul)
      mul = math.max(M_LO, math.min(M_HI, mul))
      return my1 - math.log(mul / M_LO) / math.log(M_HI / M_LO) * (my1 - my0)
    end
    local function mul_of(py) return M_LO * (M_HI / M_LO) ^ ((my1 - py) / (my1 - my0)) end
    local lf, lf_along = val(R.LowFreq, "hz", 50, 1000, true, rev.LowFreq)
    local hf, hf_along = val(R.HighFreq, "hz", 1000, 20000, true, rev.HighFreq)
    -- a Damping that reads in Hz is where the highs start (as it was drawn before)
    local damp_hz = R.Damping and R.Damping.unit == "hz" and R.Damping.v and not R.HighFreq
    if damp_hz then hf = R.Damping.v end
    lf, hf = lf or 250, hf or 4000
    local bass = RP.rv_bass(R.Bass, rev.Bass, dec)
    -- the damping control's readings at either end (which way is more)
    local dv0, dv1
    if R.Damping and not damp_hz then
      ps.dends = ps.dends or {}
      local e = ps.dends[R.Damping.p]
      if not e then
        local fm = UN.formatter(track, addr, R.Damping.p)
        e = { UN.at(fm, 0), UN.at(fm, 1) }
        ps.dends[R.Damping.p] = e
      end
      dv0, dv1 = e[1], e[2]
    end
    local dmul = (not damp_hz) and RP.rv_damp(R.Damping, rev.Damping, dec, dv0, dv1) or 0.5
    for _, g in ipairs({ 0.5, 2 }) do
      grid_h(dl, fx0, fx1 - fx0, my(g))
      u.small_text(ctx, dl, fx1 - 2, my(g) - 11, U.with_alpha(C.COL.header_dim, 0x90), ("\u{00D7}%g"):format(g), "right")
    end
    u.dashed(dl, fx0, my(1), fx1, my(1), U.with_alpha(C.COL.knob_ring, 0xc0), 2, 3, 1.0)
    -- the cuts
    local lc, lc_along = val(R.LowCut, "hz", 20, 1000, true, rev.LowCut)
    local hc, hc_along = val(R.HighCut, "hz", 1000, 20000, true, rev.HighCut)
    local shade = U.with_alpha(C.COL.header_text, 0x10)
    if R.LowCut and lc and lc_on then ImGui.DrawList_AddRectFilled(dl, fx0, my0 - 4, fxp(lc), my1, shade) end
    if R.HighCut and hc and hc_on then ImGui.DrawList_AddRectFilled(dl, fxp(hc), my0 - 4, fx1, my1, shade) end
    -- a tone control tilts it
    local tilt = R.Tone and ((rev.Tone and (1 - R.Tone.n) or R.Tone.n) * 2 - 1) or 0
    local function tf(fq) return RP.rv_tilt(tilt, fq) end
    local pxs, pys = {}, {}
    for i = 0, 80 do
      local fq = F_LO * (F_HI / F_LO) ^ (i / 80)
      pxs[#pxs + 1], pys[#pys + 1] = fxp(fq), my(RP.rv_mult(fq, lf, bass, hf, dmul) * tf(fq))
    end
    u.polyline(dl, pxs, pys, #pxs, C.COL.accent, 1.8)
    -- shelves on the wet sound: dashed, in dB about the x1 line
    if R.LowEQ or R.HighEQ then
      local function gain(m)
        if not m then return 0 end
        if m.unit == "db" and m.v then return math.max(-36, math.min(18, m.v)) end
        return -12 + 24 * m.n
      end
      local glo, ghi = gain(R.LowEQ), gain(R.HighEQ)
      local half = (my1 - my0) * 0.5
      local ymid = my(1)
      local function gy(db) return ymid - math.max(-18, math.min(18, db)) / 18 * half end
      local qx, qy = {}, {}
      for i = 0, 60 do
        local fq = F_LO * (F_HI / F_LO) ^ (i / 60)
        qx[#qx + 1], qy[#qy + 1] = fxp(fq), gy(RP.rv_shelves(glo, ghi, fq))
      end
      for i = 1, #qx - 1, 2 do ImGui.DrawList_AddLine(dl, qx[i], qy[i], qx[i + 1], qy[i + 1], 0xe0a33ad0, 1.4) end
      for _, sh in ipairs({ { R.LowEQ, glo, 60, "rvle", "Low" }, { R.HighEQ, ghi, 14000, "rvhe", "High" } }) do
        local m = sh[1]
        if m then
          local nx, ny = fxp(sh[3]), gy(RP.rv_shelves(m == R.LowEQ and glo or 0, m == R.HighEQ and ghi or 0, sh[3]))
          node(ctx, dl, ps, sh[4] .. "##" .. guid, nx, ny, ("%s shelf %s\nDrag up or down"):format(sh[5], m.text or ""),
            function(_, dy, d)
              d.v0 = d.v0 or sh[2]
              local nv = math.max(-36, math.min(18, d.v0 - dy / half * 18))
              if m.unit == "db" and m.v then u.set_to(track, addr, m.p, nv)
              else u.set_norm(track, addr, m.p, math.max(0, math.min(1, (nv + 12) / 24))) end
            end, { r = 4, fill = 0xe0a33aff, ring = C.COL.header_text, cursor = ImGui.MouseCursor_ResizeNS })
          local right = nx > fx1 - 100
          u.small_text(ctx, dl, nx + (right and -8 or 8), ny + 3, 0xe6cf79ff, sh[5] .. " " .. (m.text or ""), right and "right" or nil)
        end
      end
    end
    -- the tone's own handle, up or down at the top end
    if R.Tone then
      local f_t = 5000
      local nx, ny = fxp(f_t), my(RP.rv_mult(f_t, lf, bass, hf, dmul) * tf(f_t))
      node(ctx, dl, ps, "rvtn##" .. guid, nx, ny, ("Tone %s\nDrag up or down"):format(R.Tone.text or ""),
        function(_, dy, d)
          d.y0 = d.y0 or ny
          local base = RP.rv_mult(f_t, lf, bass, hf, dmul)
          local t = math.log(mul_of(d.y0 + dy) / base, 4) / (math.log(f_t / 1000, 2) / math.log(20, 2))
          t = math.max(-1, math.min(1, t))
          local n = (t + 1) * 0.5
          u.set_norm(track, addr, R.Tone.p, rev.Tone and (1 - n) or n)
        end, { diamond = true, r = 4, col = C.COL.accent, cursor = ImGui.MouseCursor_ResizeNS })
      u.small_text(ctx, dl, nx - 8, ny - 16, C.COL.value, "Tone " .. (R.Tone.text or ""), "right")
    end
    -- a node a side: across its crossover, up and down its amount
    local function side(id, f, mul, Rf, f_along, flo, fhi, rf, Ra, set_amt, name, tip_f, tip_a)
      if not (Rf or Ra) then return end
      local k = tf(f)
      local nx, ny = fxp(f), my(mul * k)
      local cur = (Rf and Ra) and ImGui.MouseCursor_ResizeAll or (Rf and ImGui.MouseCursor_ResizeEW or ImGui.MouseCursor_ResizeNS)
      local tip = name
      if Rf then tip = tip .. ("\n%s %s: drag left or right"):format(tip_f, Rf.text or "") end
      if Ra then tip = tip .. ("\n%s %s: drag up or down"):format(tip_a, Ra.text or "") end
      node(ctx, dl, ps, id .. "##" .. guid, nx, ny, tip, function(dx, dy, d)
        d.f0, d.y0 = d.f0 or f, d.y0 or ny
        if Rf and math.abs(dx) > 0.5 then
          local nv = math.max(flo, math.min(fhi, d.f0 * (F_HI / F_LO) ^ (dx / (fx1 - fx0))))
          set_val(track, addr, Rf, nv, f_along, flo, fhi, true, rf)
        end
        if Ra and math.abs(dy) > 0.5 then set_amt(mul_of(d.y0 + dy) / k) end
      end, { r = 5, cursor = cur })
      local right = nx > fx1 - 130
      local label = name .. " " .. ((Ra and Ra.text) or "") .. ((Rf and Ra) and (" @ " .. (Rf.text or "")) or ((Rf and Rf.text) or ""))
      u.small_text(ctx, dl, nx + (right and -8 or 8), ny - 14, C.COL.value, label, right and "right" or nil)
    end
    side("rvlo", lf, bass, R.LowFreq, lf_along, 50, 1000, rev.LowFreq, R.Bass,
      function(m) RP.rv_set_bass(track, addr, R.Bass, rev.Bass, dec, m) end, "Lows", "Crossover", "Decay")
    side("rvhi", hf, dmul, R.HighFreq or (damp_hz and R.Damping) or nil, (damp_hz and false) or hf_along, 1000, 20000,
      rev.HighFreq, (not damp_hz) and R.Damping or nil,
      function(m) RP.rv_set_damp(track, addr, guid, R.Damping, rev.Damping, dec, m, dv0, dv1) end, "Highs", "Frequency", "Damping")
    -- the cuts' edges, across; their labels inwards beside them, turned
    -- outwards when they'd meet, the high cut's a line up when even that
    -- won't do
    local LB = {}
    W.push_small(ctx)
    for _, c in ipairs({ { R.LowCut, lc, "lc", "Low cut" }, { R.HighCut, hc, "hc", "High cut" } }) do
      if c[1] and c[2] then
        local t = c[4] .. " " .. (c[1].text or "")
        LB[c[3]] = { t = t, w = ImGui.CalcTextSize(ctx, t), x = fxp(c[2]) }
      end
    end
    W.pop_small(ctx)
    local LX = { lc = LB.lc and { LB.lc.x + 8, nil }, hc = LB.hc and { LB.hc.x - 8, "right" } }
    local hc_dy = 0
    if LB.lc and LB.hc and LB.lc.x + 8 + LB.lc.w + 6 > LB.hc.x - 8 - LB.hc.w then
      LX.lc, LX.hc = { LB.lc.x - 8, "right" }, { LB.hc.x + 8, nil }
      if LB.lc.x - 8 - LB.lc.w < fx0 - 6 or LB.hc.x + 8 + LB.hc.w > fx1 + 6 then
        -- both to one side of the pair, one over the other (the high cut's
        -- along the foot, level with the nodes)
        if LB.lc.x > (fx0 + fx1) * 0.5 then
          local ax = math.min(LB.lc.x, LB.hc.x) - 9
          LX.lc, LX.hc = { ax, "right" }, { ax, "right" }
        else
          local ax = math.max(LB.lc.x, LB.hc.x) + 9
          LX.lc, LX.hc = { ax, nil }, { ax, nil }
        end
        hc_dy = 13
      end
    end
    for _, c in ipairs({ { R.LowCut, lc, lc_along, 20, 1000, rev.LowCut, "rvlc", "Low cut" },
                         { R.HighCut, hc, hc_along, 1000, 20000, rev.HighCut, "rvhc", "High cut" } }) do
      local m, v = c[1], c[2]
      if m and v then
        local cx = fxp(v)
        local on_ = (c[7] == "rvhc") and hc_on or lc_on
        ImGui.DrawList_AddLine(dl, cx, my0 - 4, cx, my1, U.with_alpha(C.COL.accent, on_ and 0x90 or 0x30), 1.2)
        node(ctx, dl, ps, c[7] .. "##" .. guid, cx, my1 - 4, ("%s %s\nDrag left or right"):format(c[8], m.text or ""),
          function(dx, _, d)
            d.v0 = d.v0 or v
            set_val(track, addr, m, math.max(c[4], math.min(c[5], d.v0 * (F_HI / F_LO) ^ (dx / (fx1 - fx0)))), c[3], c[4], c[5], true, c[6])
          end, { r = 5, cursor = ImGui.MouseCursor_ResizeEW })
        local key = (c[7] == "rvhc") and "hc" or "lc"
        u.small_text(ctx, dl, LX[key][1], my1 - 18 + ((key == "hc") and hc_dy or 0), C.COL.value, LB[key].t, LX[key][2])
      end
    end
  end
  return true
end

-- ---------------------------------------------------------------------
-- the envelope
-- ---------------------------------------------------------------------
-- each segment's share of the width, and its time scale (ms, log)
local ENV_SEG = {
  { role = "Delay",   share = 0.10, lo = 1, hi = 5000 },
  { role = "Attack",  share = 0.18, lo = 0.5, hi = 10000 },
  { role = "Hold",    share = 0.08, lo = 1, hi = 5000 },
  { role = "Decay",   share = 0.24, lo = 1, hi = 20000 },
  { role = "Release", share = 0.26, lo = 1, hi = 20000 },
}
local function env_bend(t, c)
  -- c in -1..1: below 0 fast at the start, above slow
  local k = 4 ^ math.abs(c)
  if c >= 0 then return t ^ k end
  return 1 - (1 - t) ^ k
end

local function draw_env(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = u.panel_state(guid)
  local rev = cv.rev or {}
  local gx0, gy0, gw, gh = x + 1, y, w - 2, h
  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)
  frame(dl, gx0, gy0, gw, gh)
  local base, peak = gy0 + gh - 34, gy0 + 34
  for i = 0, 4 do grid_h(dl, gx0, gw, peak + i * (base - peak) / 4) end
  local tx0, tx1 = gx0 + 14, gx0 + gw - 14
  local inner = tx1 - tx0 - 0.14 * (tx1 - tx0)   -- the sustain's own stretch
  -- each time's fraction of its share
  local fr, along_of = {}, {}
  for _, s_ in ipairs(ENV_SEG) do
    local m = R[s_.role]
    if m then
      m.rev = rev[s_.role]
      local st = u.time_steps(track, addr, guid, m.p, s_.lo, s_.hi, m.rev)
      if st then fr[s_.role] = UN.step_at(st, m.n).f
      elseif m.unit == "ms" and m.v then fr[s_.role] = math.max(0.02, math.log(math.max(s_.lo, m.v) / s_.lo) / math.log(s_.hi / s_.lo))
      else fr[s_.role] = m.rev and (1 - m.n) or m.n; along_of[s_.role] = true end
    end
  end
  local sus = 0
  if R.Sustain then
    local m = R.Sustain
    u.db_ish(track, addr, guid, m)
    if m.unit == "db" and m.v then sus = (m.v == -math.huge) and 0 or math.min(1, 10 ^ (m.v / 20))
    elseif m.unit == "pct" and m.v then sus = math.max(0, math.min(1, m.v / 100))
    else sus = rev.Sustain and (1 - m.n) or m.n end
  end
  -- short envelopes are stretched to fill the width (the proportions
  -- between segments stay)
  local raw = 0.14 * (tx1 - tx0)
  for _, s_ in ipairs(ENV_SEG) do if R[s_.role] then raw = raw + (fr[s_.role] or 0) * s_.share * inner end end
  local stretch = math.max(1, math.min(3, (tx1 - tx0) * 0.96 / math.max(1, raw)))
  local function seg_w(role)
    for _, s_ in ipairs(ENV_SEG) do if s_.role == role then return R[role] and s_.share * inner * stretch or 0 end end
    return 0
  end
  local xd = tx0 + (fr.Delay or 0) * seg_w("Delay")
  local xa = xd + (R.Attack and math.max(0.03, fr.Attack) or 0.03) * seg_w("Attack")
  local xh = xa + (fr.Hold or 0) * seg_w("Hold")
  local xdc = xh + (R.Decay and (fr.Decay or 0) or 0) * seg_w("Decay")
  local xs_end = xdc + 0.14 * (tx1 - tx0) * stretch
  local xr = xs_end + (R.Release and (fr.Release or 0) or 0) * seg_w("Release")
  local sy = base - (base - peak) * sus
  local function curve_of(role)
    local m = R[role .. "Curve"]
    if not m then return 0 end
    return ((rev[role .. "Curve"] and (1 - m.n) or m.n) - 0.5) * 2
  end
  local ca, cd, cr = curve_of("Attack"), curve_of("Decay"), curve_of("Release")
  local xs, ys = { tx0, xd }, { base, base }
  local function seg(x0_, y0_, x1_, y1_, c, out)
    for i = 1, 24 do
      local t = i / 24
      xs[#xs + 1] = x0_ + (x1_ - x0_) * t
      ys[#ys + 1] = y0_ + (y1_ - y0_) * env_bend(t, c)
      if i == 12 and out then out[1], out[2] = xs[#xs], ys[#ys] end
    end
  end
  local ma, md, mr = {}, {}, {}
  seg(xd, base, xa, peak, ca, ma)
  xs[#xs + 1], ys[#ys + 1] = xh, peak
  if R.Decay then seg(xh, peak, xdc, sy, cd, md) else xs[#xs + 1], ys[#ys + 1] = xh, sy end
  xs[#xs + 1], ys[#ys + 1] = xs_end, sy
  if R.Release then seg(xs_end, sy, xr, base, cr, mr) else xs[#xs + 1], ys[#ys + 1] = xs_end, base end
  for i = 1, #xs - 1 do
    if xs[i + 1] > xs[i] + 0.01 then
      ImGui.DrawList_AddRectFilled(dl, xs[i], math.min(ys[i], ys[i + 1]), xs[i + 1], base, U.with_alpha(C.COL.accent, 0x2e))
    end
  end
  u.polyline(dl, xs, ys, #xs, C.COL.accent, 2.2)
  u.dashed(dl, xs_end, peak - 16, xs_end, base + 4, U.with_alpha(C.COL.header_dim, 0xa0), 3, 3, 1.0)
  u.small_text(ctx, dl, xs_end + 4, peak - 18, C.COL.header_dim, "note off")
  ImGui.DrawList_PopClipRect(dl)

  -- the time nodes: across
  local function time_node(role, nx, ny, lab_dx, lab_dy, anchor)
    local m = R[role]
    if not m then return end
    local s_
    for _, v in ipairs(ENV_SEG) do if v.role == role then s_ = v end end
    local sw = seg_w(role)
    node(ctx, dl, ps, "rne" .. role .. "##" .. guid, nx, ny, ("%s %s\nDrag left or right"):format(role, m.text or ""),
      function(dx, _, d)
        d.v0 = d.v0 or fr[role]
        local f = math.max(0, math.min(1, d.v0 + dx / math.max(1, sw)))
        local st = u.time_steps(track, addr, guid, m.p, s_.lo, s_.hi, m.rev)
        if st then
          local hit = UN.step_near(st, f)
          if hit and math.abs(hit.norm - m.n) > 1e-6 then u.set_norm(track, addr, m.p, hit.norm) end
        elseif along_of[role] then u.set_norm(track, addr, m.p, m.rev and (1 - f) or f)
        else u.set_to(track, addr, m.p, s_.lo * (s_.hi / s_.lo) ^ f) end
      end, { cursor = ImGui.MouseCursor_ResizeEW })
    u.small_text(ctx, dl, nx + lab_dx, ny + lab_dy, C.COL.value, ({ Attack = "A ", Hold = "H ", Decay = "D ", Release = "R ", Delay = "Delay " })[role] .. (m.text or ""), anchor)
  end
  time_node("Delay", xd, base, 0, 6, "centre")
  time_node("Attack", xa, peak, 0, -18, "centre")
  time_node("Hold", xh, peak, 8, -6)
  time_node("Decay", xdc, sy, 6, -16)
  time_node("Release", xr, base, 0, 6, "centre")
  -- the sustain: up or down
  if R.Sustain then
    local m = R.Sustain
    local nx = (xdc + xs_end) * 0.5
    node(ctx, dl, ps, "rnesu##" .. guid, nx, sy, ("Sustain %s\nDrag up or down"):format(m.text or ""),
      function(_, dy, d)
        d.v0 = d.v0 or sus
        local nv = math.max(0, math.min(1, d.v0 - dy / (base - peak)))
        if m.unit == "db" and m.v then u.set_to(track, addr, m.p, nv > 0.0001 and 20 * math.log(nv, 10) or -150)
        elseif m.unit == "pct" and m.v then u.set_to(track, addr, m.p, nv * 100)
        else u.set_norm(track, addr, m.p, rev.Sustain and (1 - nv) or nv) end
      end, { cursor = ImGui.MouseCursor_ResizeNS })
    u.small_text(ctx, dl, nx, sy + 8, C.COL.value, "S " .. (m.text or ""), "centre")
  end
  -- the curves: ◆ halfway along, up or down
  for _, c in ipairs({ { "Attack", ma, 1 }, { "Decay", md, 1 }, { "Release", mr, 1 } }) do
    local m = R[c[1] .. "Curve"]
    if m and c[2][1] then
      node(ctx, dl, ps, "rnec" .. c[1] .. "##" .. guid, c[2][1], c[2][2],
        ("%s curve %s\nDrag up or down"):format(c[1], m.text or ""),
        function(_, dy, d)
          d.v0 = d.v0 or m.n
          u.set_norm(track, addr, m.p, math.max(0, math.min(1, d.v0 + (rev[c[1] .. "Curve"] and dy or -dy) / 120)))
        end, { diamond = true, r = 4, cursor = ImGui.MouseCursor_ResizeNS })
      u.small_text(ctx, dl, c[2][1] + 9, c[2][2] + 2, 0xe6cf79ff, "curve " .. (m.text or ""))
    end
  end
  return true
end

-- ---------------------------------------------------------------------
-- the modulation
-- ---------------------------------------------------------------------
local function shape_of(text)
  local t = (text or ""):lower()
  if t:match("tri") then return "tri" end
  if t:match("squ") or t:match("sqr") or t:match("pulse") then return "square" end
  if t:match("saw") or t:match("ramp") then return (t:match("down") or t:match("%-")) and "sawdown" or "saw" end
  if t:match("s&h") or t:match("s/h") or t:match("sample") or t:match("rand") then return "sh" end
  return "sine"
end
local function lfo(shape, ph)
  local p = ph % 1
  if shape == "tri" then return 1 - 4 * math.abs(((p + 0.25) % 1) - 0.5) end
  if shape == "square" then return p < 0.5 and 1 or -1 end
  if shape == "saw" then return 2 * p - 1 end
  if shape == "sawdown" then return 1 - 2 * p end
  if shape == "sh" then
    local k = math.floor(ph)
    return math.sin(k * 12.9898 + 78.233) % 1 * 2 - 1
  end
  return math.sin(p * 2 * math.pi)
end

local function on_of_m(m) return DLY.on_of(m) end
-- the voices' colours: the accent, amber, violet
local VOICE_COL = { nil, 0xe0a33aff, 0x8a63e6ff }
local function voice_col(k) return VOICE_COL[k] or C.COL.accent end

-- An LFO's rate, Hz, from its rate (Hz, a note, ms, or along its range),
-- or its note value while synced; rate, whether it's along its range,
-- the control a drag sets, whether that's the note switch
local function mod_rate(bpm, mR, mN, mS, rev_r)
  local beat_hz = ((bpm and bpm > 1) and bpm or 120) / 60
  if mN and (not mS or on_of_m(mS)) and (mS or not mR) then
    local nb = UN.note_beats(mN.text or "")
    if nb then return beat_hz / nb, false, mN, true end
  end
  if mR then
    local nb = UN.note_beats(mR.text or "")
    if mR.unit == "hz" and mR.v and mR.v > 0 then return mR.v, false, mR end
    if nb then return beat_hz / nb, false, mR end
    if mR.unit == "ms" and mR.v and mR.v > 0 then return 1000 / mR.v, false, mR end
    return 0.02 * 1000 ^ (rev_r and (1 - mR.n) or mR.n), true, mR
  end
  return nil
end

-- A modulation: its LFO (or each of its voices, in their colours) over a
-- scope's timebase. Drag the depth up or down at a peak, the rate across
-- (one cycle's length), a phase across. A chorus with voices of its own:
-- pick one by its chip, the others fainter; their pans on a strip.
local function draw_mod(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = u.panel_state(guid)
  local rev = cv.rev or {}
  local gx0, gy0, gw, gh = x + 1, y, w - 2, h
  local bpm = reaper.Master_GetTempo()
  local beat_hz = ((bpm and bpm > 1) and bpm or 120) / 60
  local function depth_of(m, key)
    if not m then return nil end
    if m.unit == "pct" and m.v then return math.max(0, math.min(1, m.v / 100)) end
    return rev[key] and (1 - m.n) or m.n
  end
  local m_rate, m_along, m_src = mod_rate(bpm, R.Rate, nil, nil, rev.Rate)
  local depth0 = depth_of(R.Depth, "Depth") or 0.8
  local shape = R.Shape and shape_of(R.Shape.text) or "sine"

  -- its voices
  local V = {}
  local ks = M_.mod_voices(cv.roles)
  local any_pan, own_more = false, false
  for _, k in ipairs(ks) do
    local pre = "V" .. k
    local v = { k = k, col = voice_col(k) }
    v.rate, v.along, v.src, v.synced = mod_rate(bpm, R[pre .. "Rate"], R[pre .. "Note"], R[pre .. "Sync"], rev[pre .. "Rate"])
    v.rkey = v.src and (v.src == R[pre .. "Note"] and (pre .. "Note") or (pre .. "Rate")) or "Rate"
    if not v.rate then v.rate, v.along, v.src, v.shared = m_rate, m_along, m_src, true end
    v.rate = v.rate or 0.5
    v.dm, v.dkey = R[pre .. "Depth"], pre .. "Depth"
    if not v.dm then v.dm, v.dkey = R.Depth, "Depth" end
    v.depth = depth_of(v.dm, v.dkey) or depth0
    local pm = R[pre .. "Phase"]
    if pm then
      v.pm = pm
      if pm.v and pm.unit == "" then v.ph, v.ph_along = pm.v, false
      else v.ph, v.ph_along = (rev[pre .. "Phase"] and (1 - pm.n) or pm.n) * 360, true end
    end
    v.panm = R[pre .. "Pan"]
    if v.panm then any_pan = true; v.pan = (rev[pre .. "Pan"] and (1 - v.panm.n) or v.panm.n) * 2 - 1 end
    v.onm = R[pre .. "On"]
    v.on = (not v.onm) or on_of_m(v.onm)
    v.syncm, v.notem = R[pre .. "Sync"], R[pre .. "Note"]
    if R[pre .. "Rate"] or R[pre .. "Note"] or pm or v.panm or v.onm then own_more = true end
    V[#V + 1] = v
  end
  -- voices that only have a depth of their own (TriceraChorus's L / C / R)
  -- share the LFO, spread through its cycle, their pans set
  local depth_only = #V > 0 and not own_more
  if #V > 0 and not any_pan then
    local fixed = ({ [1] = { 0 }, [2] = { -1, 1 }, [3] = { -1, 0, 1 } })[#V]
    for i, v in ipairs(V) do v.pan, v.pan_fixed = fixed[i], true end
  end
  for i, v in ipairs(V) do if not v.ph and v.shared then v.ph, v.spread = (i - 1) / #V * 360, true end end
  -- the one picked
  local sel
  if #V > 0 and not depth_only then
    for _, v in ipairs(V) do if v.k == ps.mod_sel then sel = v end end
    if not sel then
      for _, v in ipairs(V) do if v.on and not sel then sel = v end end
      sel = sel or V[1]
      ps.mod_sel = sel.k
    end
  end
  -- what's drawn the main way: the picked voice, or the one LFO
  local rate, rate_along = (sel and sel.rate) or m_rate or 0.5, (sel and sel.along) or (not sel and m_along) or false
  local depth = sel and sel.depth or (depth_only and 0.8) or depth0
  local main_col = sel and sel.col or C.COL.accent
  local phase, phase_along = 0, false
  if not sel and #V == 0 and R.Phase then
    if R.Phase.v and R.Phase.unit == "" then phase = R.Phase.v
    else phase, phase_along = (rev.Phase and (1 - R.Phase.n) or R.Phase.n) * 180, true end
  end
  local count
  if R.Voices then
    local n_ = UN.parse(R.Voices.text or "")
    count = n_ and math.floor(n_ + 0.5) or nil
    if count and (count < 1 or count > 16) then count = nil end
  end

  -- the layout: a pan strip along the top, chips along the foot
  local strip = #V > 0
  local voice_sw = R.Voices and u.switch_positions(track, addr, guid, R.Voices.p)
  local foot = (R.Shape or (#V > 0 and not depth_only) or voice_sw) and 24 or 0
  local note_row = sel and sel.synced and sel.notem and 22 or 0
  local by = gy0 + gh - foot - note_row
  local top = gy0 + (strip and 26 or 0)
  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, by, true)
  frame(dl, gx0, gy0, gw, by - gy0)
  -- the time across: a scope's timebase, ranged to the rate (a cycle a
  -- quarter to half of it), kept while the cycle stays on screen, held
  -- while the rate's dragged
  local dragging_rate = ps.drag and ps.drag.id == "rmrt##" .. guid
  local window = ps.mod_win
  local per_s = 1 / math.max(1e-4, rate)
  if not dragging_rate and (not window or per_s > 0.95 * window or per_s < 0.1 * window) then
    window = 2 ^ math.ceil(math.log(2 * per_s, 2))
  end
  ps.mod_win = window
  local cycles = rate * window
  local tx0, tx1 = gx0 + 12, gx0 + gw - 12
  local mid = top + (by - top) * 0.5 - 8
  local amp = (by - top) * 0.5 - 30
  for i = -2, 2 do grid_h(dl, gx0, gw, mid + i * amp / 2) end
  local function draw_wave(r_hz, dep, ph_off, col, thick, dash)
    local cyc = r_hz * window
    local xs, ys = {}, {}
    local ns = math.min(1600, math.max(240, math.floor(cyc * 24)))
    for i = 0, ns do
      local t = i / ns
      xs[#xs + 1] = tx0 + (tx1 - tx0) * t
      ys[#ys + 1] = mid - amp * dep * lfo(shape, t * cyc - ph_off)
    end
    if dash then
      for i = 1, #xs - 1, 2 do ImGui.DrawList_AddLine(dl, xs[i], ys[i], xs[i + 1], ys[i + 1], col, thick) end
    else u.polyline(dl, xs, ys, #xs, col, thick) end
  end
  if #V == 0 then
    -- one LFO: its other voices faint behind it (a count of them), the
    -- right side's phase dashed
    if count and count > 1 then
      for j = 1, count - 1 do draw_wave(rate, depth, j / count, U.with_alpha(C.COL.accent, 0x50), 1.2) end
    end
    if R.Phase and phase ~= 0 then draw_wave(rate, depth, -phase / 360, 0x8a63e6d0, 1.6, true) end
    draw_wave(rate, depth, 0, C.COL.accent, 2.2)
  else
    for _, v in ipairs(V) do
      if v ~= sel then
        -- one that's off: barely there
        local col = U.with_alpha(v.col, v.on and (depth_only and 0xe0 or 0x78) or 0x38)
        draw_wave(v.rate, v.depth, (v.ph or 0) / 360, col, v.on and (depth_only and 1.8 or 1.4) or 1.0)
      end
    end
    if sel then draw_wave(sel.rate, sel.depth, (sel.ph or 0) / 360, sel.on and sel.col or U.with_alpha(sel.col, 0x70), sel.on and 2.4 or 1.6) end
  end
  u.small_text(ctx, dl, tx1, by - 14, U.with_alpha(C.COL.header_dim, 0xa0), ("%g s"):format(math.floor(window * 100 + 0.5) / 100), "right")
  ImGui.DrawList_PopClipRect(dl)

  local period_px = (tx1 - tx0) / math.max(0.0001, cycles)
  local function first_peak(ph_deg, per_px)
    local pk = (shape == "saw") and 0.999 or ((shape == "square" or shape == "sawdown") and 0.02 or 0.25)
    local f = (pk + (ph_deg or 0) / 360) % 1
    return tx0 + f * per_px, pk
  end
  local function depth_node(id, m, key, dep, ph_deg, per_px, col, label)
    local px_, pk = first_peak(ph_deg, per_px)
    local py_ = mid - amp * dep * lfo(shape, pk)
    node(ctx, dl, ps, id .. "##" .. guid, px_, py_, ("%s %s\nDrag up or down"):format(label, m.text or ""),
      function(_, dy, d)
        d.v0 = d.v0 or dep
        local nv = math.max(0, math.min(1, d.v0 - dy / amp))
        if m.unit == "pct" and m.v then u.set_to(track, addr, m.p, nv * 100)
        else u.set_norm(track, addr, m.p, rev[key] and (1 - nv) or nv) end
      end, { cursor = ImGui.MouseCursor_ResizeNS, ring = col })
    return px_, py_
  end
  -- the depth: the first peak, up or down (each voice's own, when they only
  -- have their depths)
  if depth_only then
    for i = #V, 1, -1 do if not V[i].dm then table.remove(V, i) end end
    local names_ = (#V == 3 and not any_pan) and { "L", "C", "R" } or nil
    for i, v in ipairs(V) do
      local per_v = (tx1 - tx0) / math.max(0.0001, v.rate * window)
      local px_, py_ = depth_node("rmdp" .. v.k, v.dm, v.dkey, v.depth, v.ph, per_v, v.col, "Depth")
      if v.dm then u.small_text(ctx, dl, px_ + 9, py_ - 6, C.COL.value, (names_ and (names_[i] .. " ") or (v.k .. ": ")) .. (v.dm.text or "")) end
    end
  elseif sel and sel.dm then
    local px_, py_ = depth_node("rmdp", sel.dm, sel.dkey, sel.depth, sel.ph, period_px, sel.col, "Depth")
    local t = "Depth " .. (sel.dm.text or "")
    if px_ + 9 + 90 > gx0 + gw - 190 then u.small_text(ctx, dl, px_ - 9, py_ - 6, C.COL.value, t, "right")
    else u.small_text(ctx, dl, px_ + 9, py_ - 6, C.COL.value, t) end
  elseif not sel and R.Depth then
    local px_, py_ = depth_node("rmdp", R.Depth, "Depth", depth, 0, period_px, C.COL.accent, "Depth")
    u.small_text(ctx, dl, px_ + 9, py_ - 6, C.COL.value, "Depth " .. (R.Depth.text or ""))
  end
  -- the rate: one cycle's length, across
  local rsrc = sel and sel.src or (not sel and m_src) or nil
  local rkey = sel and sel.rkey or "Rate"
  if rsrc then
    local ry = mid + amp + 14
    local rx = tx0 + math.min(tx1 - tx0, period_px)
    ImGui.DrawList_AddLine(dl, tx0, ry, rx, ry, main_col, 1.4)
    local is_note = rsrc and (sel and sel.synced)
    node(ctx, dl, ps, "rmrt##" .. guid, rx, ry, ("Rate %s\nDrag left or right"):format(rsrc.text or ""),
      function(dx, _, d)
        d.v0 = d.v0 or (rx - tx0)
        d.win = d.win or window
        -- across the screen, a cycle that long; past its right edge, the
        -- timebase opens out (twice as long each 60 px), for the slow end
        local tw = tx1 - tx0
        local px_ = math.max(4, d.v0 + dx)
        local over = math.max(0, math.min(360, px_ - tw))
        ps.mod_win = d.win * 2 ^ (over / 60)
        local nrate = 1 / (math.min(px_, tw) / tw * ps.mod_win)
        local m = rsrc
        local n = nearest_setting(track, addr, guid, m, function(t)
          local v, un = UN.parse(t)
          if un == "hz" and not is_note then return v end
          local nb = UN.note_beats(t)
          return nb and beat_hz / nb or nil
        end, nrate, true)
        if n then u.set_norm(track, addr, m.p, n)
        elseif rate_along then set_val(track, addr, m, nrate, true, 0.02, 20, true, rev[rkey])
        elseif m.unit == "ms" then u.set_to(track, addr, m.p, 1000 / nrate)
        else u.set_to(track, addr, m.p, nrate) end
      end, { cursor = ImGui.MouseCursor_ResizeEW, ring = main_col })
    u.small_text(ctx, dl, (tx0 + rx) * 0.5, ry - 15, C.COL.value, "Rate " .. (rsrc.text or ""), "centre")
  end
  -- the right side's phase: its first peak, across
  if #V == 0 and R.Phase then
    local px_ = tx0 + (0.25 - phase / 360) % 1 * period_px
    if px_ < tx0 + 4 then px_ = px_ + period_px end
    local py_ = mid - amp * depth
    node(ctx, dl, ps, "rmph##" .. guid, px_, py_, ("Phase %s (the right side)\nDrag left or right"):format(R.Phase.text or ""),
      function(dx, _, d)
        d.v0 = d.v0 or phase
        local nv = math.max(0, math.min(360, d.v0 - dx / period_px * 360))
        if phase_along then
          local nn = math.max(0, math.min(1, nv / 180))
          u.set_norm(track, addr, R.Phase.p, rev.Phase and (1 - nn) or nn)
        else u.set_to(track, addr, R.Phase.p, nv) end
      end, { r = 4, fill = 0x8a63e6ff, ring = C.COL.header_text, cursor = ImGui.MouseCursor_ResizeEW })
    u.small_text(ctx, dl, gx0 + gw - 8, top + 64, 0xb59bf2ff, "R " .. (R.Phase.text or ""), "right")
  end
  -- the picked voice's phase: where its wave starts up, across
  if sel and sel.pm then
    local ph = sel.ph or 0
    local px_ = tx0 + (ph / 360 % 1) * period_px
    local key = "V" .. sel.k .. "Phase"
    node(ctx, dl, ps, "rmvph##" .. guid, px_, mid, ("Phase %s\nDrag left or right"):format(sel.pm.text or ""),
      function(dx, _, d)
        d.v0 = d.v0 or ph
        local nv = math.max(0, math.min(360, d.v0 + dx / period_px * 360))
        if sel.ph_along then
          local nn = nv / 360
          u.set_norm(track, addr, sel.pm.p, rev[key] and (1 - nn) or nn)
        else u.set_to(track, addr, sel.pm.p, nv) end
      end, { r = 4, fill = 0x8a63e6ff, ring = C.COL.header_text, cursor = ImGui.MouseCursor_ResizeEW })
    u.small_text(ctx, dl, px_ + 8, mid + 8, 0xb59bf2ff, "Phase " .. (sel.pm.text or ""))
  end

  -- the voices' pans: a strip along the top, a dot each (dragged across
  -- when it has a pan of its own)
  if strip then
    local px0, px1 = gx0 + 30, gx0 + math.min(gw * 0.5, 340)
    local py = gy0 + 13
    u.small_text(ctx, dl, px0 - 8, py - 7, C.COL.header_dim, "L", "right")
    u.small_text(ctx, dl, px1 + 8, py - 7, C.COL.header_dim, "R")
    ImGui.DrawList_AddLine(dl, px0, py, px1, py, C.COL.knob_ring, 2.0)
    ImGui.DrawList_AddLine(dl, (px0 + px1) * 0.5, py - 4, (px0 + px1) * 0.5, py + 4, C.COL.knob_ring, 1.0)
    for _, v in ipairs(V) do
      if v.pan then
        local vx = px0 + (v.pan + 1) * 0.5 * (px1 - px0)
        if v.pan_fixed then
          ImGui.DrawList_AddRectFilled(dl, vx - 1.5, py - 6, vx + 1.5, py + 6, v.col)
        else
          local key = "V" .. v.k .. "Pan"
          local col = v.on and v.col or U.with_alpha(v.col, 0x60)
          node(ctx, dl, ps, "rmpn" .. v.k .. "##" .. guid, vx, py, ("Voice %d pan %s\nDrag left or right"):format(v.k, v.panm.text or ""),
            function(dx, _, d)
              d.v0 = d.v0 or v.pan
              local nv = math.max(-1, math.min(1, d.v0 + dx / (px1 - px0) * 2))
              local nn = (nv + 1) * 0.5
              u.set_norm(track, addr, v.panm.p, rev[key] and (1 - nn) or nn)
              ps.mod_sel = v.k
            end, { r = (v == sel) and 5 or 4, fill = col, ring = (v == sel) and C.COL.header_text or col,
                   cursor = ImGui.MouseCursor_ResizeEW })
        end
      end
    end
  end

  -- along the foot: the voices (pick one; lit when on), its shape, a count
  local cx, fx1 = gx0 + 4, gx0 + gw - 4
  local fy = gy0 + gh - foot + 4
  if #V > 0 and not depth_only then
    u.small_text(ctx, dl, cx, fy + 1, C.COL.header_dim, "VOICE")
    cx = cx + 40
    for _, v in ipairs(V) do
      local id = "rmvs" .. v.k .. "##" .. guid
      local hov = u.handle(ctx, id, cx, fy, 24, 16)
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then ps.mod_sel = v.k end
      local bg = v.on and v.col or C.COL.toggle_off
      if hov then bg = U.with_alpha(bg, 0xdd) end
      ImGui.DrawList_AddRectFilled(dl, cx, fy, cx + 24, fy + 16, bg, 3.0)
      ImGui.DrawList_AddRect(dl, cx, fy, cx + 24, fy + 16, (v == sel) and C.COL.header_text or C.COL.knob_ring, 3.0, 0,
        (v == sel) and 1.6 or 1.0)
      W.push_small(ctx)
      local t = tostring(v.k)
      local tw, th = ImGui.CalcTextSize(ctx, t)
      ImGui.DrawList_AddText(dl, math.floor(cx + (24 - tw) * 0.5 + 0.5), math.floor(fy + (16 - th) * 0.5 + 0.5),
        v.on and 0x0d1116ff or C.COL.toggle_text, t)
      W.pop_small(ctx)
      W.tip(ctx, id, ("Voice %d%s: its depth, rate and phase to drag"):format(v.k, v.on and "" or " (off)"), hov, false)
      cx = cx + 28
    end
    cx = cx + 10
  end
  if voice_sw then
    u.small_text(ctx, dl, cx, fy + 1, C.COL.header_dim, "VOICES")
    cx = cx + 48
    local used = chip_row(ctx, dl, track, addr, guid, "rmvc", R.Voices, cx, fy, fx1 - cx, "How many voices", false)
    cx = cx + used + 10
  end
  if R.Shape then
    local sw = u.switch_positions(track, addr, guid, R.Shape.p)
    if sw then
      chip_row(ctx, dl, track, addr, guid, "rmsh", R.Shape, cx, fy, fx1 - cx, "Its shape", false)
    else
      u.small_text(ctx, dl, cx + 2, fy + 2, C.COL.value, "Shape " .. (R.Shape.text or ""))
    end
  end
  -- the picked voice synced: its note values, above the foot
  if note_row > 0 then
    chip_row(ctx, dl, track, addr, guid, "rmvn" .. sel.k, sel.notem, gx0 + 4, by + 4, gw - 8, "Its note value", false)
  end

  -- top right: the picked voice's pan, then delay, feedback and mix; under
  -- them its name, on and sync
  local list = { { sel and sel.panm, "Pan" }, { R.Delay, "Delay" }, { R.Feedback, "Feedback" }, { R.Mix, "Mix" } }
  local n = 0
  for _, k in ipairs(list) do if k[1] then n = n + 1 end end
  local bx1 = gx0 + gw - 6
  knob_box(ctx, dl, ps, track, addr, guid, list, bx1, gy0 + 6)
  if sel then
    local kb_h = (n > 0) and 50 or 0
    local tw = math.max(n * 52 + 4, 120)
    u.small_text(ctx, dl, bx1 - tw, gy0 + 6 + kb_h + 4, sel.col, ("Voice %d"):format(sel.k))
    local tx = bx1
    for _, sw_ in ipairs({ { sel.syncm, "SYNC", "The voice's rate synced to the tempo" }, { sel.onm, "ON", "The voice on or off" } }) do
      if sw_[1] then
        local wdt = (sw_[2] == "ON") and 30 or 44
        tx = tx - wdt
        local is_on = on_of_m(sw_[1])
        if u.mini_toggle(ctx, dl, "rmvt" .. sw_[2] .. "##" .. guid, tx, gy0 + 6 + kb_h + 2, wdt, 16, is_on, sw_[2], sw_[3]) then
          u.set_norm(track, addr, sw_[1].p, is_on and 0 or 1)
        end
        tx = tx - 4
      end
    end
  end
  return true
end

-- ---------------------------------------------------------------------
-- the multiband compressor
-- ---------------------------------------------------------------------
-- All bands: the crossovers over the spectrum (drag them across), each
-- band tinted in its colour, and a strip per band under it -- its little
-- transfer curve (drag the threshold up or down), its settings, solo and
-- bypass. Click a band's name for the band on the full compressor canvas
-- (TS_CV_CompPanel), with tabs to switch bands or go back.

-- the band's measured reduction, dB, or nil: the post probe splits the
-- plugin's tapped audio at its crossovers (TS_CV_Taps TP.set_mb)
RP.band_gr = function(track, fx, k) return TP.band_gr(track, fx.guid, k) end

-- A band's reduction from the third-octaves (CP.fine_frame): the median
-- of those whose centres fall between lo and hi Hz (the nearest one to
-- its middle when none do), positive dB; nil without a reading.
function RP.fine_band_gr(fr, lo, hi)
  if not fr then return nil end
  local v = {}
  for k = 1, fr.n do
    local f = fr.f[k]
    if f >= lo and f < hi and fr.g[k] then v[#v + 1] = fr.g[k] end
  end
  if #v == 0 then
    local mid, best, bd = math.sqrt(lo * hi), nil, math.huge
    for k = 1, fr.n do
      local dd = math.abs(math.log(fr.f[k] / mid))
      if fr.g[k] and dd < bd then best, bd = fr.g[k], dd end
    end
    return best and math.max(0, best) or nil
  end
  table.sort(v)
  local m = (#v % 2 == 1) and v[(#v + 1) // 2] or (v[#v // 2] + v[#v // 2 + 1]) * 0.5
  return math.max(0, m)
end

local function mb_sub(cv, k)
  -- band k as a compressor layout's roles
  local r, rv = {}, {}
  local map = { Threshold = "Threshold", Ratio = "Ratio", Knee = "Knee", Attack = "Attack", Release = "Release", Gain = "Makeup" }
  for b, as in pairs(map) do
    local p = cv.roles["B" .. k .. b]
    if p then r[as] = p; if cv.rev and cv.rev["B" .. k .. b] then rv[as] = true end end
  end
  return { kind = "comp", roles = r, rev = rv }
end

-- A small slider for one of the plugin's controls, moved along its range
-- (Shift: fine; the wheel; double-click: the middle). Vertical: its name
-- above, its reading below, `h` the slot; horizontal: name and reading on
-- a line, the slot under them. `rev`: the control runs the other way.
local function mini_slider(ctx, dl, id, x, y, w, h, track, addr, m, name, horiz, tip, rev)
  local nv = reaper.TrackFX_GetParamNormalized(track, addr, m.p) or 0
  local _, txt = reaper.TrackFX_GetFormattedParamValue(track, addr, m.p, "")
  local sx0, sy0, sx1, sy1
  if horiz then sx0, sy0, sx1, sy1 = x, y + 14, x + w, y + 22
  else
    local mid = x + w * 0.5
    sx0, sy0, sx1, sy1 = mid - 3, y + 12, mid + 3, y + 12 + h
  end
  local hov, act, dragging = u.handle(ctx, id, horiz and x or (x + 2), horiz and (y + 10) or (y + 10),
    horiz and w or (w - 4), horiz and 16 or (h + 4))
  local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and C.FINE_MULT or 1
  local sgn = rev and -1 or 1
  if dragging then
    local dx, dy = ImGui.GetMouseDelta(ctx)
    local d = horiz and (dx / (sx1 - sx0)) or (-dy / (sy1 - sy0))
    if d ~= 0 then
      nv = math.max(0, math.min(1, nv + sgn * d * fine))
      u.set_norm(track, addr, m.p, nv)
    end
    ImGui.SetMouseCursor(ctx, horiz and ImGui.MouseCursor_ResizeEW or ImGui.MouseCursor_ResizeNS)
  elseif hov then
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then
      nv = math.max(0, math.min(1, nv + sgn * wheel * C.WHEEL_STEP * fine))
      u.set_norm(track, addr, m.p, nv)
      W.take_wheel()
    end
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      u.set_norm(track, addr, m.p, U.param_mid_norm(track, addr, m.p))
    end
  end
  local f = rev and (1 - nv) or nv
  local hot = hov or act
  ImGui.DrawList_AddRectFilled(dl, sx0, sy0, sx1, sy1, 0x0000005c, 2.0)
  local cap = hot and C.COL.header_text or C.COL.accent
  if horiz then
    local cxp = sx0 + f * (sx1 - sx0)
    ImGui.DrawList_AddRectFilled(dl, sx0, sy0, cxp, sy1, U.with_alpha(C.COL.accent, 0x90), 2.0)
    ImGui.DrawList_AddRectFilled(dl, cxp - 2, sy0 - 3, cxp + 2, sy1 + 3, cap, 1.5)
    u.small_text(ctx, dl, x, y, C.COL.label, name)
    u.small_text(ctx, dl, x + w, y, C.COL.value, txt or "", "right")
  else
    local cyp = sy1 - f * (sy1 - sy0)
    ImGui.DrawList_AddRectFilled(dl, sx0, cyp, sx1, sy1, U.with_alpha(C.COL.accent, 0x90), 2.0)
    ImGui.DrawList_AddRectFilled(dl, sx0 - 4, cyp - 2, sx1 + 4, cyp + 2, cap, 1.5)
    u.small_text(ctx, dl, x + w * 0.5, y, C.COL.label, name, "centre")
    -- the reading, shortened to fit its slot
    local t = txt or ""
    W.push_small(ctx)
    while #t > 2 and ImGui.CalcTextSize(ctx, t) > w - 2 do
      local s = t:gsub("%s*%a+$", "")
      if s == t then t = t:sub(1, -2) else t = s end
    end
    W.pop_small(ctx)
    u.small_text(ctx, dl, x + w * 0.5, sy1 + 3, C.COL.value, t, "centre")
  end
  W.tip(ctx, id, ("%s: %s\nDrag (Shift: fine) · double-click: middle"):format(tip or name, txt or ""), hov, act)
end

local function hz_text(f)
  if f >= 10000 then return ("%.0fk"):format(f / 1000) end
  if f >= 1000 then return ("%.1fk"):format(f / 1000) end
  return ("%.0f"):format(f)
end

-- A multiband: each band's level going in against its threshold (measured
-- on the way in only, so it holds up), and ONE reduction -- the plugin's
-- as a whole -- down the side. Each band's own reduction isn't measured:
-- comparing before with after held up for one number, not for four.
local function draw_multi(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = u.panel_state(guid)
  local rev = cv.rev or {}
  local nb = cv.nb or 3
  local col = function(k) return EQP.util.band_colour(k) end
  local enabled = T.get_enabled(track, addr)
  -- open: its tap is laid, and the probe splits the audio going in at the
  -- crossovers (or between the bands in use, when each has its own edges)
  TP.panel_open(guid)
  local plan = TP.mb_plan(track, addr, cv)
  TP.set_mb(track, guid, plan.xs)
  -- the bands shown, low to high: every band with shared crossovers; with
  -- their own edges, only those in use, numbered in frequency order (a
  -- plugin's band 1 can be anywhere)
  local order, names = {}, {}
  if plan.own then
    for k = 1, nb do if plan[k].used then order[#order + 1] = k end end
    table.sort(order, function(a, b) return plan[a].lo < plan[b].lo end)
    for i, k in ipairs(order) do names[k] = "Band " .. i end
  else
    local nm = require("TS_CV_CanvasSetup").band_names(nb)
    for k = 1, nb do order[k] = k; names[k] = nm[k] end
  end
  local shown = {}
  for _, k in ipairs(order) do shown[k] = true end
  if not shown[ps.mb_focus or 0] then ps.mb_focus = 0 end
  -- each band's level going in
  local lv, old = {}, false
  for _, k in ipairs(order) do
    local v = TP.mb_level(track, guid, plan, k)
    if v == "old" then old = true elseif v then lv[k] = v end
  end

  -- the tabs: all bands, or one
  local th = 20
  local tx = x + 4
  if u.mini_toggle(ctx, dl, "mbt0##" .. guid, tx, y + 2, 64, 16, ps.mb_focus == 0, "ALL BANDS") then ps.mb_focus = 0 end
  tx = tx + 68
  for _, k in ipairs(order) do
    W.push_small(ctx)
    local tw = ImGui.CalcTextSize(ctx, names[k]:upper())
    W.pop_small(ctx)
    if u.mini_toggle(ctx, dl, "mbt" .. k .. "##" .. guid, tx, y + 2, tw + 14, 16, ps.mb_focus == k, names[k]:upper()) then
      ps.mb_focus = k
    end
    ImGui.DrawList_AddLine(dl, tx + 2, y + 18, tx + tw + 12, y + 18, col(k), 2.0)
    tx = tx + tw + 18
  end
  -- a band slot not in use, when its "in use" control is mapped: + BAND
  -- takes the first into use (the control's "on" setting)
  local function on_norm(m)
    for _, s_ in ipairs(u.switch_positions(track, addr, guid, m.p) or {}) do
      if TP.mb_state_of(s_.text, s_.norm) == "on" then return s_.norm end
    end
    return 1
  end
  local spare
  for k = 1, nb do
    if not spare and R["B" .. k .. "Used"] and not plan[k].used then spare = k end
  end
  if spare and ps.mb_focus == 0 and tx + 60 < x + w - 4 then
    if u.mini_toggle(ctx, dl, "mbadd##" .. guid, tx, y + 2, 56, 16, false, "+ BAND",
        "Take another band slot into use (slot " .. spare .. ")") then
      u.set_norm(track, addr, R["B" .. spare .. "Used"].p, on_norm(R["B" .. spare .. "Used"]))
    end
  end
  local by = y + th + 2

  -- a band's "in use" control, right-aligned at xr: the plugin's own
  -- setting, a list of its settings on click (or a flip, for a plain
  -- switch); returns its width
  local function state_ctl(k, xr, yy, wmax)
    local um = R["B" .. k .. "Used"]
    if not um or wmax < 30 then return 0 end
    local pos = u.switch_positions(track, addr, guid, um.p)
    local t = (um.text or "") ~= "" and um.text or (plan[k].used and "On" or "Off")
    W.push_small(ctx)
    local tw = ImGui.CalcTextSize(ctx, t)
    W.pop_small(ctx)
    local bw = math.min(wmax, tw + 24)
    if u.mini_toggle(ctx, dl, "mbu" .. k .. "##" .. guid, xr - bw, yy, bw, 16, plan[k].used and not plan[k].byp,
        t .. (pos and " \u{25BE}" or ""), names[k] .. ": in use, switched off, or not used") then
      if pos then ImGui.OpenPopup(ctx, "mbup" .. k .. "##" .. guid) else u.flip(track, addr, um.p) end
    end
    if pos and ImGui.BeginPopup(ctx, "mbup" .. k .. "##" .. guid) then
      for _, s_ in ipairs(pos) do
        if ImGui.Selectable(ctx, s_.text, um.n >= s_.lo - 1e-6 and um.n <= s_.hi + 1e-6) then
          u.set_norm(track, addr, um.p, s_.norm)
        end
      end
      ImGui.EndPopup(ctx)
    end
    return bw
  end

  -- one band, on the compressor's canvas: its dot rides the curve at the
  -- band's level; the meter is the plugin's whole reduction. Its switches
  -- (in use, bypass, solo) on the tab row's right.
  if ps.mb_focus > 0 then
    local k = ps.mb_focus
    local sx = x + w - 4
    local sw_ = state_ctl(k, sx, y + 2, math.max(0, sx - tx - 90))
    if sw_ > 0 then sx = sx - sw_ - 4 end
    for _, sb in ipairs({ { "Bypass", "BYP" }, { "Solo", "S" } }) do
      local m = R["B" .. k .. sb[1]]
      if m then
        local bw = (#sb[2] * 8) + 10
        sx = sx - bw
        if u.mini_toggle(ctx, dl, "mbf" .. sb[1] .. "##" .. guid, sx, y + 2, bw, 16, on_of(track, addr, m), sb[2],
            names[k] .. " " .. sb[1]:lower()) then
          u.flip(track, addr, m.p)
        end
        sx = sx - 4
      end
    end
    local sub = mb_sub(cv, k)
    if not next(sub.roles) then
      u.small_text(ctx, dl, x + w * 0.5, by + 40, C.COL.header_dim, names[k] .. " has no controls mapped yet", "centre")
      return true
    end
    sub.band = { lv = lv[k] }
    return require("TS_CV_CompPanel").draw_mapped(ctx, dl, x, by, w, h - (by - y), track, fx, req, sub)
  end

  -- the plugin's reduction, one meter down the side
  local mw = CP.METERS_W
  local gr = T.gain_reduction(track, addr) or 0
  u.draw_meters(ctx, dl, x + w - mw, by, mw, h - (by - y), track, fx, gr, enabled,
    W.gr_state(guid, gr, reaper.time_precise(), 12))

  -- ---- all bands: each band over its range of the spectrum
  local gx0, gw = x + 1, w - mw - 2
  local sh = math.max(70, math.floor((h - th) * 0.42))
  local sy0 = by
  local fx_of = function(f) return EQP.util.x_of(math.max(F_LO, math.min(F_HI, f)), gx0, gw) end
  ImGui.DrawList_PushClipRect(dl, gx0, sy0, gx0 + gw, sy0 + sh, true)
  frame(dl, gx0, sy0, gw, sh)
  EQP.util.draw_spectrum(dl, gx0, sy0, gw, sh)
  for _, f in ipairs({ 100, 1000, 10000 }) do
    grid_v(dl, fx_of(f), sy0, sh)
    u.small_text(ctx, dl, fx_of(f) + 3, sy0 + sh - 13, U.with_alpha(C.COL.header_dim, 0xa0), f >= 1000 and (f // 1000) .. "k" or tostring(f))
  end
  for _, k in ipairs(order) do
    local b = plan[k]
    local a, bx = fx_of(b.lo), fx_of(b.hi)
    ImGui.DrawList_AddRectFilled(dl, a, sy0, bx, sy0 + sh, U.with_alpha(col(k), (b.used and not b.byp) and 0x18 or 0x08))
    if plan.own then
      -- a band with its own edges: its range outlined, and its number
      ImGui.DrawList_AddLine(dl, a + 0.5, sy0, a + 0.5, sy0 + sh, U.with_alpha(col(k), 0x90), 1.0)
      ImGui.DrawList_AddLine(dl, bx - 0.5, sy0, bx - 0.5, sy0 + sh, U.with_alpha(col(k), 0x90), 1.0)
      if bx - a > 30 then u.small_text(ctx, dl, (a + bx) * 0.5, sy0 + sh * 0.45, col(k), names[k], "centre") end
    end
  end
  if old then
    u.small_text(ctx, dl, gx0 + gw * 0.5, sy0 + sh * 0.5 - 6, U.with_alpha(C.COL.header_dim, 0xc0),
      "Reopen the project for the bands' levels (a newer probe)", "centre")
  elseif #order == 0 then
    u.small_text(ctx, dl, gx0 + gw * 0.5, sy0 + sh * 0.5 - 6, C.COL.header_dim,
      spare and "No bands in use \u{2014} + BAND adds one" or "No bands in use", "centre")
  end
  ImGui.DrawList_PopClipRect(dl)

  -- the edges you drag: the crossovers, or each band's own edges
  local function edge_handle(id, m, v, lo_, hi_, tip, label_y)
    local xx = fx_of(v)
    local hov, act, dragging = u.handle(ctx, id, xx - 5, sy0, 10, sh)
    if dragging then
      local d = ps.drag
      if not d or d.id ~= id then
        local mx = ImGui.GetMousePos(ctx)
        d = { id = id, mx = mx, v0 = v }
        ps.drag = d
      end
      local mx = ImGui.GetMousePos(ctx)
      local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
      local nv = math.max(lo_, math.min(hi_, d.v0 * (F_HI / F_LO) ^ ((mx - d.mx) * fine / gw)))
      local _, along = val(m, "hz", F_LO, F_HI, true, rev[m.role])
      set_val(track, addr, m, nv, along, F_LO, F_HI, true, rev[m.role])
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    elseif hov then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    ImGui.DrawList_AddLine(dl, xx, sy0, xx, sy0 + sh, (hov or act) and C.COL.header_text or C.COL.accent, 1.6)
    ImGui.DrawList_AddRectFilled(dl, xx - 3, sy0 + sh - 26, xx + 3, sy0 + sh - 8, (hov or act) and C.COL.header_text or C.COL.accent, 3.0)
    if label_y then u.small_text(ctx, dl, xx, label_y, C.COL.value, m.text or "", "centre") end
    W.tip(ctx, id, tip, hov, act)
  end
  if not plan.own then
    for k = 1, nb - 1 do
      local m = R["Crossover" .. k]
      local xv = plan.xs[k]
      if m then
        m.role = "Crossover" .. k
        local lo_ = (k > 1) and plan.xs[k - 1] * 1.1 or F_LO
        local hi_ = (k < nb - 1) and plan.xs[k + 1] / 1.1 or F_HI
        edge_handle("mbx" .. k .. "##" .. guid, m, xv, lo_, hi_,
          ("%s / %s crossover %s\nDrag left or right"):format(names[k], names[k + 1], m.text or ""), sy0 + sh + 2)
      else
        u.dashed(dl, fx_of(xv), sy0, fx_of(xv), sy0 + sh, U.with_alpha(C.COL.header_dim, 0xa0), 3, 3, 1.0)
      end
    end
  else
    -- each band's edges, but not a low edge sitting on another band's
    -- high one (moving that moves both, in a plugin that links them)
    for _, k in ipairs(order) do
      local b = plan[k]
      for _, e in ipairs({ { "Low", b.lo }, { "High", b.hi } }) do
        local role = "B" .. k .. e[1]
        local m = R[role]
        local shared = false
        if e[1] == "Low" then
          for _, j in ipairs(order) do
            if j ~= k and R["B" .. j .. "High"] and math.abs(math.log(plan[j].hi / b.lo)) < 0.02 then shared = true end
          end
        end
        if m and not shared then
          m.role = role
          edge_handle("mbe" .. role .. "##" .. guid, m, e[2], F_LO, F_HI,
            ("%s %s edge %s\nDrag left or right"):format(names[k], e[1]:lower(), m.text or ""), nil)
        end
      end
    end
  end
  knob_box(ctx, dl, ps, track, addr, guid, { { R.Output, "Output" }, { R.Mix, "Mix" } }, gx0 + gw - 6, sy0 + 6)

  -- ---- a strip per band: its curve (drag its threshold), the band's level
  -- riding it, its controls as small sliders, and its switches
  local ty0 = sy0 + sh + 16
  local th_ = y + h - ty0
  local n = math.max(1, #order)
  local cw = (gw - (n - 1) * 4) / n
  local grc = W.gr_fill_col(false, false)
  for i, k in ipairs(order) do
    local cx = gx0 + (i - 1) * (cw + 4)
    local function m_(r) return R["B" .. k .. r] end
    ImGui.DrawList_AddRectFilled(dl, cx, ty0, cx + cw, ty0 + th_, U.with_alpha(C.COL.win_bg, 0xc8), 4.0)
    ImGui.DrawList_AddRect(dl, cx, ty0, cx + cw, ty0 + th_, C.COL.knob_ring, 4.0, 0, 1.0)
    ImGui.DrawList_AddRectFilled(dl, cx, ty0, cx + cw, ty0 + 3, col(k), 2.0)
    -- the name: click for the full canvas
    local id = "mbn" .. k .. "##" .. guid
    local hov = u.handle(ctx, id, cx, ty0, cw, 18)
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then ps.mb_focus = k end
    u.small_text(ctx, dl, cx + 6, ty0 + 5, hov and C.COL.header_text or C.COL.value, names[k] .. (hov and "  \u{203A}" or ""))
    W.tip(ctx, id, "Open " .. names[k] .. " on the compressor canvas", hov, false)
    -- its switches along the foot: solo, bypass, and its "in use" setting
    local bx = cx + 6
    for _, sb in ipairs({ { "Solo", "S" }, { "Bypass", "BYP" } }) do
      local m = m_(sb[1])
      if m and plan[k].used then
        local bw = (#sb[2] * 8) + 10
        if u.mini_toggle(ctx, dl, "mbs" .. sb[1] .. k .. "##" .. guid, bx, ty0 + th_ - 22, bw, 16, on_of(track, addr, m), sb[2],
            names[k] .. " " .. sb[1]:lower()) then
          u.flip(track, addr, m.p)
        end
        bx = bx + bw + 4
      end
    end
    state_ctl(k, cx + cw - 6, ty0 + th_ - 22, cx + cw - 6 - bx)
    if not plan[k].used then
      u.small_text(ctx, dl, cx + cw * 0.5, ty0 + 40, C.COL.header_dim, "not in use", "centre")
      goto next_band
    end
    -- the header's right: switched off, or its range (own edges)
    if plan[k].byp then
      u.small_text(ctx, dl, cx + cw - 6, ty0 + 5, C.COL.header_dim, "switched off", "right")
    elseif plan.own then
      u.small_text(ctx, dl, cx + cw - 6, ty0 + 5, C.COL.header_dim, ("%s\u{2013}%s"):format(hz_text(plan[k].lo), hz_text(plan[k].hi)), "right")
    end
    do
      -- room: the curve as big as fits over the sliders
      local sl_list = {}
      for _, s in ipairs({ { "Ratio", "Ratio" }, { "Attack", "Atk" }, { "Release", "Rel" }, { "Gain", "Gain" } }) do
        if m_(s[1]) then sl_list[#sl_list + 1] = s end
      end
      local horiz_gain = false
      if #sl_list == 4 and (cw - 12) / 4 < 24 then horiz_gain = true; table.remove(sl_list, 4) end
      local avail = th_ - 22 - 26 - 8
      local sl_h = (#sl_list > 0) and math.max(36, math.min(90, math.floor(avail * 0.34))) or 0
      local sb_h = (#sl_list > 0) and (sl_h + 26) or 0
      if horiz_gain then sb_h = sb_h + 30 end
      local cs = math.min(cw - 12, avail - sb_h - 6)
      local py = ty0 + 22
      -- its transfer curve
      local tthr, tratio = nil, 2
      local T_ = m_("Threshold")
      if T_ then
        u.db_ish(track, addr, guid, T_)
        tthr = val(T_, "db", -60, 0, false, rev["B" .. k .. "Threshold"])
        if tthr == -math.huge then tthr = -60 end
      end
      local Ra = m_("Ratio")
      if Ra and Ra.v and Ra.v >= 1 then tratio = Ra.v elseif Ra and not Ra.v then tratio = 1000 end
      local function curve_out(db) if not tthr or db <= tthr then return db end return tthr + (db - tthr) / tratio end
      local l = enabled and lv[k] or nil
      if cs > 28 then
        local px = cx + (cw - cs) * 0.5
        ImGui.DrawList_AddRect(dl, px, py, px + cs, py + cs, C.COL.knob_ring, 0, 0, 1.0)
        local function X(db) return px + (math.max(-60, math.min(6, db)) + 60) / 66 * cs end
        local function Y(db) return py + cs - (math.max(-60, math.min(6, db)) + 60) / 66 * cs end
        u.dashed(dl, X(-60), Y(-60), X(6), Y(6), U.with_alpha(C.COL.label, 0x60), 2, 3, 1.0)
        if tthr then
          local xs, ys_ = {}, {}
          for j = 0, 40 do
            local db = -60 + 66 * j / 40
            xs[#xs + 1], ys_[#ys_ + 1] = X(db), Y(curve_out(db))
          end
          u.polyline(dl, xs, ys_, #xs, C.COL.fader_cap, 1.6)
          -- the threshold: drag up or down; its reading in the corner
          local tid = "mbth" .. k .. "##" .. guid
          local hv, ac, dg = u.handle(ctx, tid, px, Y(tthr) - 4, cs, 8)
          if dg then
            local nv = math.max(-60, math.min(0, u.drag_real(ctx, ps, tid, tthr, 0, -66 / cs)))
            if T_.unit == "db" and T_.v then u.set_to(track, addr, T_.p, nv)
            else set_val(track, addr, T_, nv, true, -60, 0, false, rev["B" .. k .. "Threshold"]) end
            ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
          elseif hv then
            ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
          end
          if not ac and ps.drag and ps.drag.id == tid then ps.drag = nil end
          ImGui.DrawList_AddLine(dl, px, Y(tthr), px + cs, Y(tthr), (hv or ac) and C.COL.header_text or C.COL.accent, 1.2)
          u.small_text(ctx, dl, px + 3, py + 2, U.with_alpha(C.COL.header_dim, 0xd0), T_.text or "")
          W.tip(ctx, tid, ("%s threshold %s\nDrag up or down"):format(names[k], T_.text or ""), hv, ac)
        end
        -- the band going in, riding its curve
        if l and l > -60 then
          local hx, hy = X(l), Y(curve_out(l))
          ImGui.DrawList_AddCircleFilled(dl, hx, hy, 7, U.with_alpha(grc, 0x30))
          ImGui.DrawList_AddCircleFilled(dl, hx, hy, 3.5, 0xffd8b0ff)
          ImGui.DrawList_AddCircle(dl, hx, hy, 3.5, grc, 0, 1.2)
        end
      else
        cs = 0
      end
      -- its controls: small sliders (gain across the foot when they'd be
      -- too narrow side by side)
      local sy = py + cs + 8
      if #sl_list > 0 then
        local sw = (cw - 12) / #sl_list
        for j, s in ipairs(sl_list) do
          local m = m_(s[1])
          mini_slider(ctx, dl, "mbsl" .. s[1] .. k .. "##" .. guid, cx + 6 + (j - 1) * sw, sy, sw, sl_h, track, addr, m,
            s[2], false, names[k] .. " " .. s[1]:lower(), rev["B" .. k .. s[1]])
        end
        sy = sy + sl_h + 26
      end
      if horiz_gain then
        local m = m_("Gain")
        mini_slider(ctx, dl, "mbslGain" .. k .. "##" .. guid, cx + 6, sy, cw - 12, 26, track, addr, m,
          "Gain", true, names[k] .. " gain", rev["B" .. k .. "Gain"])
      end
    end
    ::next_band::
  end
  return true
end

-- ---------------------------------------------------------------------

-- Draws a role canvas of one of RP.KINDS. False when it has no roles yet
-- (the caller shows the setup button instead).
function RP.draw(ctx, dl, x, y, w, h, track, fx, req, cv)
  local roles = cv.roles or {}
  if not next(roles) then return false end
  if w < 120 or h < 80 then return true end
  local R = {}
  for name, p in pairs(roles) do R[name] = u.mapped(track, fx.addr, p) end
  local k = cv.kind
  if k == "deess" then return draw_deess(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  if k == "delay" then return draw_delay(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  if k == "reverb" then return draw_reverb(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  if k == "env" then return draw_env(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  if k == "mod" then return draw_mod(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  if k == "sat" then return draw_sat(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  if k == "multi" then return draw_multi(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  return false
end

-- for the tests
RP._env_bend, RP._shape_of, RP._lfo = env_bend, shape_of, lfo

return RP
