-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_MapPanel.lua -- the EQ canvas for any plugin: an EQ layout's bands
  (TS_CV_Mappings Band<k>), drawn from what was learned about them
  (TS_CV_MapEQ) and dragged through the plugin's own controls.

  Until every band is learned for its mapping as it is now, the canvas
  is a "Set up this layout" button instead (req.canvas_setup).

  Drag a node: across moves the band's frequency control (a switch snaps
  to its positions), up and down its gain. The wheel over a node turns
  its Q control, Alt+wheel steps its shape switch. Right-click a node for
  the band's shapes, its On switch and the setup. The nodes say what the
  plugin's own controls read.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local M  = require("TS_CV_Mappings")
local ME = require("TS_CV_MapEQ")
local UN = require("TS_CV_Units")
local EQP = require("TS_CV_EQPanel")

local MP = {}
local ImGui

function MP.attach(imgui) ImGui = imgui end

local draw_dynamics, draw_dyn_box   -- a dynamic EQ's bands, below

local state = {}
local function panel_state(guid)
  local s = state[guid]
  if not s then s = {}; state[guid] = s end
  return s
end

local function ftext(track, addr, p)
  if not p then return nil end
  local _, t = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
  return U.trim(t or "")
end

-- The canvas's width for a layout's canvas kind.
function MP.width(kind)
  return (kind == "eq") and C.MAP_EQ_W or C.MAP_COMP_W
end

-- The placeholder for a layout that isn't ready.
function MP.draw_setup(ctx, dl, x, y, w, h, fx, cv, req)
  local pad = C.PANEL_PAD
  ImGui.DrawList_AddRectFilled(dl, x + pad, y + pad, x + w - pad, y + h - pad, 0x00000030, 3.0)
  local todo = M.canvas_todo(cv)
  local line1 = (cv.kind ~= "eq")
                and ("This %s layout has no roles yet."):format((M.CANVAS_NAMES[cv.kind] or "compressor"):lower())
                or "This EQ layout isn't learned yet."
  local tw = ImGui.CalcTextSize(ctx, line1)
  local cy = y + h * 0.5 - 30
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, cy, C.COL.header_dim, line1)
  local bw, bh = 150, 22
  ImGui.SetCursorScreenPos(ctx, x + (w - bw) * 0.5, cy + 22)
  if ImGui.Button(ctx, "Set up this layout\u{2026}##mpset" .. fx.guid, bw, bh) then
    req.canvas_setup = true
  end
  if todo and todo.total > 0 then
    local t2 = ("%d of %d bands learned"):format(todo.learned, todo.total)
    local w2 = ImGui.CalcTextSize(ctx, t2)
    W.push_small(ctx)
    ImGui.DrawList_AddText(dl, x + (w - w2) * 0.5, cy + 52, C.COL.header_dim, t2)
    W.pop_small(ctx)
  end
end

-- ---------------------------------------------------------------------
-- a dynamic EQ's bands
-- ---------------------------------------------------------------------
local CP_FINE = 0xe6cf79ff

local function handle(ctx, id, x, y, w, h)
  W.allow_overlap(ctx)
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, id, math.max(1, w), math.max(1, h),
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  return hov, act, act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left)
end

-- How far the mouse has gone since a drag on `id` began, Shift a quarter.
local function drag_delta(ctx, ps, id, v0)
  local d = ps.ddrag
  local mx, my = ImGui.GetMousePos(ctx)
  if not d or d.id ~= id then d = { id = id, mx = mx, my = my, v0 = v0 }; ps.ddrag = d end
  local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
  return (mx - d.mx) * fine, (my - d.my) * fine, d.v0
end

-- A dynamic band's tail (to its range, dragged up or down), or the deepest
-- it has gone lately when it has no range, and the dot where it is now.
-- Before the band's own node, so the node wins where they meet. Returns
-- whether it's hovered or dragged.
function draw_dynamics(ctx, dl, ps, track, addr, fx, b, fr, nx, ny, node_db, gy0, gh, col)
  local u = EQP.util
  local dy = b.dy
  local hot = false
  local rng = C.EQ_GAIN_RANGE
  local function yd(db) return u.y_of(math.max(-rng, math.min(rng, db)), gy0, gh) end
  local dim = not dy.on
  local tcol = dim and U.with_alpha(col, 0x60) or col
  -- now: what the probe measures where the band is heard
  local now
  if fr and b.on then now = ME.dev_at(fr, ME.dyn_focus(b)) end
  if dy.range then
    local ty = yd(node_db + dy.range)
    ImGui.DrawList_AddLine(dl, nx, ny, nx, ty, tcol, 2.0)
    local id = ("mpdr##%s:%d"):format(fx.guid, b.k)
    local hov, act, dragging = handle(ctx, id, nx - 7, ty - 7, 14, 14)
    if dragging then
      local _, dyp, r0 = drag_delta(ctx, ps, id, dy.range)
      ME.set_range(track, addr, b.map, r0 - dyp / gh * (rng * 2))
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    elseif hov then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    end
    if not act and ps.ddrag and ps.ddrag.id == id then ps.ddrag = nil end
    if hov or act then hot = true end
    ImGui.DrawList_AddCircleFilled(dl, nx, ty, 4.5, C.COL.panel_bg)
    ImGui.DrawList_AddCircle(dl, nx, ty, 4.5, (hov or act) and C.COL.header_text or tcol, 0, 2.0)
    W.tip(ctx, id, ("Range %s%s\nDrag up or down (Shift: fine)"):format(dy.range_text or "",
      dy.range_along and "" or (" (%+.1f dB)"):format(dy.range)), hov, act)
  else
    -- no range: the deepest it has gone lately, held, slowly letting go
    local now_t = reaper.time_precise()
    ps.deep, ps.deep_t = ps.deep or {}, ps.deep_t or {}
    local dt = math.min(0.2, now_t - (ps.deep_t[b.k] or now_t)); ps.deep_t[b.k] = now_t
    local dp = ps.deep[b.k] or 0
    dp = (dp < 0) and math.min(0, dp + dt * 1.5) or math.max(0, dp - dt * 1.5)
    if now and math.abs(now) > math.abs(dp) then dp = now end
    ps.deep[b.k] = dp
    if math.abs(dp) > 0.3 then
      local ty = yd(node_db + dp)
      ImGui.DrawList_AddLine(dl, nx, ny, nx, ty, U.with_alpha(tcol, 0x90), 1.4)
      ImGui.DrawList_AddCircle(dl, nx, ty, 3.5, U.with_alpha(tcol, 0x90), 0, 1.4)
    end
  end
  if now and math.abs(now) > 0.1 then
    ImGui.DrawList_AddCircleFilled(dl, nx, yd(node_db + now), 3.6, CP_FINE)
  end
  return hot
end

-- The picked dynamic band's box: its threshold against the band's level
-- going in, its dynamics switch, ratio, range, attack and release (drag a
-- value across to change it). On the side away from the band.
-- lvl: the band's level going in, dBFS (the probe split around it), or nil
function draw_dyn_box(ctx, dl, ps, track, addr, fx, b, lvl, gx0, gy0, gw, gh)
  local u = EQP.util
  local dy, d = b.dy, b.map.dyn
  local bw, bh = 236, 92
  if gw < bw + 40 or gh < bh + 40 then return end
  local bx = (u.x_of(b.f, gx0, gw) < gx0 + gw * 0.45) and (gx0 + gw - bw - 8) or (gx0 + 8)
  local by = gy0 + 8
  local col = u.band_colour(b.k)
  ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + bh, U.with_alpha(C.COL.win_bg, 0xd8), 5.0)
  ImGui.DrawList_AddRect(dl, bx, by, bx + bw, by + bh, C.COL.knob_ring, 5.0, 0, 1.0)
  ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + 3, col, 2.0)
  local name = (b.map.name ~= "" and b.map.name) or ("Band " .. b.k)
  local ftxt = b.f >= 1000 and ("%.3g kHz"):format(b.f / 1000) or ("%d Hz"):format(math.floor(b.f + 0.5))
  ImGui.DrawList_AddText(dl, bx + 8, by + 7, C.COL.value, name .. "  \u{00B7}  " .. ftxt)
  W.push_small(ctx)
  -- its dynamics switch
  if d.on then
    local tx, tw_ = bx + bw - 44, 36
    local hov = handle(ctx, ("mpdo##%s:%d"):format(fx.guid, b.k), tx, by + 7, tw_, 15)
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
      local cur = reaper.TrackFX_GetParamNormalized(track, addr, d.on)
      reaper.TrackFX_SetParamNormalized(track, addr, d.on, cur >= 0.5 and 0 or 1)
    end
    local bg = dy.on and C.COL.toggle_on or C.COL.toggle_off
    ImGui.DrawList_AddRectFilled(dl, tx, by + 7, tx + tw_, by + 22, hov and U.with_alpha(bg, 0xdd) or bg, 3.0)
    local t = "DYN"
    local w_ = ImGui.CalcTextSize(ctx, t)
    ImGui.DrawList_AddText(dl, tx + (tw_ - w_) * 0.5, by + 9, dy.on and 0x0d1116ff or C.COL.toggle_text, t)
  end
  -- the threshold, against the band's level going in
  local mx0, mx1, my = bx + 10, bx + bw - 10, by + 34
  ImGui.DrawList_AddRectFilled(dl, mx0, my - 5, mx1, my + 5, 0x15171bff, 2.0)
  ImGui.DrawList_AddRect(dl, mx0, my - 5, mx1, my + 5, C.COL.knob_ring, 2.0, 0, 1.0)
  local lo, hi = ME.thr_span(track, addr, b.map)
  local function xo(db) return mx0 + math.max(0, math.min(1, (db - lo) / (hi - lo))) * (mx1 - mx0) end
  if not b.on then lvl = nil end
  if lvl then
    local lx = xo(lvl)
    ImGui.DrawList_AddRectFilled(dl, mx0 + 1, my - 4, lx, my + 4, U.with_alpha(C.COL.eq_spectrum, 0xa0))
    if dy.thr and lvl > dy.thr then
      ImGui.DrawList_AddRectFilled(dl, xo(dy.thr), my - 4, lx, my + 4, U.with_alpha(CP_FINE, 0xc0))
    end
  end
  if dy.thr then
    local tx = xo(dy.thr)
    local id = ("mpdt##%s:%d"):format(fx.guid, b.k)
    local hov, act, dragging = handle(ctx, id, mx0 - 4, my - 9, mx1 - mx0 + 8, 18)
    if dragging then
      local dx, _, t0 = drag_delta(ctx, ps, id, dy.thr)
      ME.set_thr(track, addr, b.map, math.max(lo, math.min(hi, t0 + dx / (mx1 - mx0) * (hi - lo))))
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    elseif hov then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    end
    if not act and ps.ddrag and ps.ddrag.id == id then ps.ddrag = nil end
    ImGui.DrawList_AddLine(dl, tx, my - 8, tx, my + 8, (hov or act) and C.COL.header_text or C.COL.accent, 2.4)
    W.tip(ctx, id, ("Threshold %s\nDrag left or right (Shift: fine)\nBar: the band's input level (probe estimate)"):format(dy.thr_text or ""), hov, act)
    ImGui.DrawList_AddText(dl, mx0, my + 8, C.COL.value, "Threshold " .. (dy.thr_text or ""))
  end
  if lvl then
    local t = ("in %.0f dB"):format(lvl)
    local w_ = ImGui.CalcTextSize(ctx, t)
    ImGui.DrawList_AddText(dl, mx1 - w_, my + 8, C.COL.header_dim, t)
  end
  -- ratio, range, attack, release: drag a value across
  local cells = {
    { "ratio", "Ratio ", dy.ratio_text }, { "range", "Range ", dy.range_text },
    { "atk", "Atk ", dy.atk_text }, { "rel", "Rel ", dy.rel_text },
  }
  local cx, cy = bx + 10, by + 58
  local i = 0
  for _, c in ipairs(cells) do
    local p = d[c[1]]
    if p and c[3] then
      local x_ = cx + (i % 2) * 112
      local y_ = cy + (i // 2) * 15
      local txt = c[2] .. c[3]
      local tw_ = ImGui.CalcTextSize(ctx, txt)
      local w_ = math.max(30, tw_)
      local id = ("mpdc%s##%s:%d"):format(c[1], fx.guid, b.k)
      local hov, act, dragging = handle(ctx, id, x_ - 2, y_ - 1, w_ + 4, 14)
      if dragging then
        local dx, _, n0 = drag_delta(ctx, ps, id, reaper.TrackFX_GetParamNormalized(track, addr, p))
        local v = math.max(0, math.min(1, n0 + dx * 0.004))
        if math.abs(v - reaper.TrackFX_GetParamNormalized(track, addr, p)) > 1e-6 then
          reaper.TrackFX_SetParamNormalized(track, addr, p, v)
        end
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
      elseif hov then
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
      end
      if not act and ps.ddrag and ps.ddrag.id == id then ps.ddrag = nil end
      ImGui.DrawList_AddText(dl, x_, y_, (hov or act) and C.COL.header_text or C.COL.value, txt)
      W.tip(ctx, id, M.DYN_NAMES[c[1]] .. " " .. c[3] .. "\nDrag left or right (Shift: fine)", hov, act)
      i = i + 1
    end
  end
  W.pop_small(ctx)
end

-- ---------------------------------------------------------------------
-- the EQ canvas
-- ---------------------------------------------------------------------
function MP.draw_eq(ctx, dl, x, y, w, h, track, fx, layout, req)
  local cv = layout.canvas
  if M.canvas_todo(cv) then return MP.draw_setup(ctx, dl, x, y, w, h, fx, cv, req) end
  local u = EQP.util
  local addr = fx.addr
  local ps = panel_state(fx.guid)
  local pad = C.PANEL_PAD
  local gx0, gy0 = x + pad, y + pad
  local gw, gh = w - pad * 2, h - pad * 2
  if gw < 20 or gh < 20 then return end

  local bands = {}
  local any_dyn = false
  for k, b in ipairs(cv.bands) do
    local rb = ME.read_band(track, addr, b, cv.all_on)
    if rb then
      rb.k, rb.map = k, b
      if M.band_dynamic(b) then rb.dy = ME.read_dyn(track, addr, b); any_dyn = true end
      bands[#bands + 1] = rb
    end
  end
  -- a dynamic EQ: what it's doing now comes from the probe's third-octaves
  -- only while CP.FINE_ON is set; otherwise the curve is the knobs', and the
  -- picked band's box shows its level going in against its threshold
  local fr, fwhy
  if any_dyn then
    if require("TS_CV_CompPanel").FINE_ON then fr, fwhy = require("TS_CV_CompPanel").fine_frame(track, fx.guid) end
    local playing = (reaper.GetPlayState() & 1) == 1
    if not playing or not ps.snap then
      ps.snap = {}
      for _, b in ipairs(bands) do
        ps.snap[b.k] = { type = b.type, order = b.order, f = b.f, g = b.g, q = b.q, on = b.on }
      end
    end
  else
    ps.snap = nil
  end

  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)
  u.draw_spectrum(dl, gx0, gy0, gw, gh)
  u.draw_grid(ctx, dl, gx0, gy0, gw, gh)

  local n = C.EQ_CURVE_SEGS
  local xs = u.sample_xs(gx0, gw, n)
  local y0db = u.y_of(0, gy0, gh)
  local fr_ = {}
  for i = 1, n do fr_[i] = u.freq_of_x(xs[i], gx0, gw) end
  local lim = C.EQ_GAIN_RANGE * 1.5
  local total = {}
  for i = 1, n do total[i] = 0 end
  for _, b in ipairs(bands) do
    if b.on then
      local col = u.band_colour(b.k)
      local ys = {}
      for i = 1, n do
        local db = ME.band_db(b, fr_[i])
        total[i] = total[i] + db
        ys[i] = u.y_of(math.max(-lim, math.min(lim, db)), gy0, gh)
      end
      for i = 1, n - 1 do u.fill_to_zero(dl, xs[i], xs[i + 1], ys[i], y0db, col, 0x38) end
      u.polyline(dl, xs, ys, n, U.with_alpha(col, 0xb0), 1.1)
    end
  end
  local function yc(db) return u.y_of(math.max(-lim, math.min(lim, db)), gy0, gh) end
  local ty = {}
  for i = 1, n do ty[i] = yc(total[i]) end
  if any_dyn then
    -- every dynamic band at its range: dotted, with the reach shaded
    local full, has_range = {}, false
    for i = 1, n do full[i] = total[i] end
    for _, b in ipairs(bands) do
      if b.on and b.dy and b.dy.range and b.dy.on and (b.type == "bell" or b.type == "ls" or b.type == "hs") then
        has_range = true
        local moved = { type = b.type, order = b.order, f = b.f, q = b.q, g = (b.g or 0) + b.dy.range }
        for i = 1, n do full[i] = full[i] + ME.band_db(moved, fr_[i]) - ME.band_db(b, fr_[i]) end
      end
    end
    if has_range then
      local fy = {}
      for i = 1, n do fy[i] = yc(full[i]) end
      local reach = U.with_alpha(C.COL.eq_curve, 0x14)
      for i = 1, n - 1 do
        local a, c = math.min(ty[i], fy[i]), math.max(ty[i], fy[i])
        if c - a > 0.5 then ImGui.DrawList_AddRectFilled(dl, xs[i], a, xs[i + 1], c, reach) end
        if i % 3 ~= 0 then
          ImGui.DrawList_AddLine(dl, xs[i], fy[i], xs[i + 1], fy[i + 1], U.with_alpha(C.COL.header_dim, 0xc0), 1.0)
        end
      end
    end
  end
  if fr then
    -- now: the plugin as the probe last measured it, plus what it's doing
    local base = total
    if fr.cal and ps.snap then
      base = {}
      for i = 1, n do
        local t = 0
        for _, sb in pairs(ps.snap) do if sb.on then t = t + ME.band_db(sb, fr_[i]) end end
        base[i] = t
      end
    end
    local ny_ = {}
    for i = 1, n do ny_[i] = yc(base[i] + ME.dev_at(fr, fr_[i])) end
    local amber = U.with_alpha(CP_FINE, 0x40)
    for i = 1, n - 1 do
      local a, c = math.min(ty[i], ny_[i]), math.max(ty[i], ny_[i])
      if c - a > 0.5 then ImGui.DrawList_AddRectFilled(dl, xs[i], a, xs[i + 1], c, amber) end
    end
    u.polyline(dl, xs, ty, n, U.with_alpha(C.COL.eq_curve, 0x90), 1.2)
    u.polyline(dl, xs, ny_, n, C.COL.header_text, 2.2)
  else
    u.polyline(dl, xs, ty, n, C.COL.eq_curve, 2.0)
  end

  -- the selected (hovered or dragged) band's switch positions along the foot
  local sel = ps.sel
  if sel then
    local b = cv.bands[sel]
    local L = b and ME.decode(b.learn)
    local rb
    for _, v in ipairs(bands) do if v.k == sel then rb = v end end
    if L and L.S and rb then
      local e = L.shapes[rb.s] or L.shapes[1]
      for _, pn in ipairs(L.S) do
        local f
        if L.D then
          local fmt = UN.formatter(track, addr, b.freq)
          f = UN.at(fmt, pn); if f and e and e.K then f = f * (e.K[1] or 1) end
        elseif e and #e.F > 0 then f = UN.interp(e.F, pn, true) end
        if f and f > 0 then
          local tx = u.x_of(f, gx0, gw)
          ImGui.DrawList_AddLine(dl, tx, gy0 + gh - 6, tx, gy0 + gh, u.band_colour(sel), 2.0)
        end
      end
    end
  end

  W.push_small(ctx)
  ImGui.DrawList_AddText(dl, gx0 + 4, gy0 + gh - 26, U.with_alpha(C.COL.accent, 0xc0), "learned")
  if any_dyn and not fr and require("TS_CV_CompPanel").FINE_ON then
    local msg = (fwhy == "old") and "Reopen the project to see it working (a newer probe)"
      or (fwhy == false) and "Not measured yet: it needs a probe tap on this track"
      or (fwhy == "busy") and "Another panel on this track is measuring"
      or nil
    if msg then
      local tw = ImGui.CalcTextSize(ctx, msg)
      ImGui.DrawList_AddText(dl, gx0 + (gw - tw) * 0.5, gy0 + gh - 26, U.with_alpha(C.COL.header_dim, 0xc0), msg)
    end
  end
  W.pop_small(ctx)
  ImGui.DrawList_PopClipRect(dl)

  -- nodes
  local hot
  for _, b in ipairs(bands) do
    local col = u.band_colour(b.k)
    -- the node sits on the curve: at the band's gain for a bell, shelf or
    -- flat top; on the 0 dB line where a tilt pivots and for the shapes
    -- with no gain (cuts, notch, band pass, all pass) -- up and down on
    -- those turns Q
    local has_gain = b.map.gain ~= nil and not ME.GAINLESS[b.type]
    local at_gain = has_gain and (b.type == "bell" or b.type == "ls" or b.type == "hs"
      or b.type == "sword" or b.type == "flattop")
    local q_drag = not has_gain and b.map.q ~= nil and not ME.q_positions(track, addr, b.map)
    local node_db = at_gain and math.max(-C.EQ_GAIN_RANGE, math.min(C.EQ_GAIN_RANGE, b.g or 0)) or 0
    local nx = math.max(gx0, math.min(gx0 + gw, u.x_of(b.f, gx0, gw)))
    local ny = u.y_of(node_db, gy0, gh)
    if b.dy then
      local t = draw_dynamics(ctx, dl, ps, track, addr, fx, b, fr, nx, ny, node_db, gy0, gh, col)
      if t then hot = b.k end
    end
    local id = ("mpn##%s:%d"):format(fx.guid, b.k)
    local r = C.EQ_NODE_R + 3
    W.allow_overlap(ctx)
    ImGui.SetCursorScreenPos(ctx, nx - r, ny - r)
    ImGui.InvisibleButton(ctx, id, r * 2, r * 2,
      ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
    local hovered = ImGui.IsItemHovered(ctx)
    local active = ImGui.IsItemActive(ctx)
    if hovered or active then hot = b.k end
    if hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      -- double-click: the band out of the sound (flat, or off)
      ME.reset(track, addr, b.map)
      ps.drag, ps.dblk = nil, b.k
    elseif active and ps.dblk == b.k then
      -- the rest of that double-click's press moves nothing
    elseif active and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      local d = ps.drag
      if not d or d.k ~= b.k then
        local mx, my = ImGui.GetMousePos(ctx)
        d = { k = b.k, f = b.f, g = b.g or 0, mx = mx, my = my,
              qn = b.map.q and reaper.TrackFX_GetParamNormalized(track, addr, b.map.q) }
        ps.drag = d
      end
      local mx, my = ImGui.GetMousePos(ctx)
      local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
      local dx, dy = (mx - d.mx) * fine, (my - d.my) * fine
      if b.map.freq and math.abs(dx) > 0.5 then
        local tf = d.f * (C.EQ_FREQ_HI / C.EQ_FREQ_LO) ^ (dx / gw)
        ME.set_freq(track, addr, b.map, tf)
      end
      if has_gain and math.abs(dy) > 0.5 then
        local tg = d.g - dy / gh * (C.EQ_GAIN_RANGE * 2)
        ME.set_gain(track, addr, b.map, tg)
      elseif q_drag and d.qn and math.abs(dy) > 0.5 then
        -- up: narrower / more resonant
        local v = math.max(0, math.min(1, d.qn - dy / gh))
        reaper.TrackFX_SetParamNormalized(track, addr, b.map.q, v)
      end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeAll)
    elseif ps.drag and ps.drag.k == b.k and not active then
      ps.drag = nil
    elseif hovered then
      local wheel = W.control_wheel(ctx)
      local alt = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Alt) ~= 0
      if wheel ~= 0 and alt and b.map.shape then
        -- Alt+wheel: the next or previous shape
        local shs = ME.shapes(track, addr, b.map)
        if shs then
          local cur = ME.shape_now(track, addr, b.map) or 1
          local to = math.max(1, math.min(#shs, cur + (wheel > 0 and 1 or -1)))
          if to ~= cur then ME.set_shape(track, addr, b.map, to) end
        end
        W.take_wheel()
      elseif wheel ~= 0 and b.map.q then
        local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
        ME.nudge_q(track, addr, b.map, wheel * 0.02 * fine)
        W.take_wheel()
      end
    end
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
      ps.menu = b.k
      ImGui.OpenPopup(ctx, "mpctx##" .. fx.guid)
    end
    if hovered or active then
      local name = (b.map.name ~= "" and b.map.name) or ("Band " .. b.k)
      local parts = {}
      for _, f in ipairs({ "freq", "gain", "q" }) do
        local t = ftext(track, addr, b.map[f])
        if t and t ~= "" then parts[#parts + 1] = t end
      end
      local sl = ME.find_slope(track, addr, b.map)
      local st = sl and ftext(track, addr, sl)
      if st and st ~= "" then parts[#parts + 1] = st end
      local tip = ("%s  (%s)\n%s"):format(name, ME.TYPES[b.type] or b.type,
        table.concat(parts, "   "))
      if q_drag then tip = tip .. "\nDrag up or down: Q" end
      if b.map.q then
        tip = tip .. (ME.q_positions(track, addr, b.map) and "\nWheel or right-click: Q" or "\nWheel: Q")
      end
      if b.map.shape then tip = tip .. "\nAlt+wheel or right-click: shape" end
      tip = tip .. "\nDouble-click: " .. (b.map.gain and "flat" or "off")
      W.tip(ctx, id, tip, hovered, active)
    end
    local ring = (hovered or active) and C.COL.header_text or col
    local fill = b.on and col or U.with_alpha(col, 0x50)
    ImGui.DrawList_AddCircleFilled(dl, nx, ny, C.EQ_NODE_R, fill)
    ImGui.DrawList_AddCircle(dl, nx, ny, C.EQ_NODE_R, ring, 0, 1.5)
  end
  if hot then ps.sel = hot elseif not ps.drag then ps.sel = nil end
  if ps.dblk and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then ps.dblk = nil end
  -- the dynamic band last pointed at (the first, to start with): its box
  if any_dyn then
    local pick
    for _, b in ipairs(bands) do
      if b.dy and (b.k == hot or (not hot and b.k == ps.dsel)) then pick = b end
    end
    if not pick then for _, b in ipairs(bands) do if b.dy and not pick then pick = b end end end
    if pick then
      ps.dsel = pick.k
      -- its level going in: the probe splits the audio either side of it
      -- (as a multiband's bands), measured on the way in only
      local TP = require("TS_CV_Taps")
      local slo, shi = ME.dyn_span(pick)
      local lvl
      if slo and shi and shi > slo then
        TP.panel_open(fx.guid)
        TP.set_mb(track, fx.guid, { slo, shi })
        lvl = TP.mb_level(track, fx.guid, { [2] = { lo = slo, hi = shi, used = true }, at = { [2] = 2 } }, 2)
        if lvl == "old" then lvl = nil end
      end
      draw_dyn_box(ctx, dl, ps, track, addr, fx, pick, lvl, gx0, gy0, gw, gh)
    end
  end

  -- right-click menu
  local pop = "mpctx##" .. fx.guid
  if ImGui.BeginPopup(ctx, pop) then
    local b = cv.bands[ps.menu or 0]
    if b then
      local rb
      for _, v in ipairs(bands) do if v.k == ps.menu then rb = v end end
      ImGui.TextDisabled(ctx, ((b.name ~= "" and b.name) or ("Band " .. ps.menu))
        .. (rb and ("  \u{00B7} " .. (ME.TYPES[rb.type] or rb.type)) or ""))
      -- the band's shape switch, setting by setting
      local shs = rb and ME.shapes(track, addr, b)
      if shs then
        local cur = ME.shape_now(track, addr, b) or 1
        for _, sh in ipairs(shs) do
          if ImGui.MenuItem(ctx, ME.shape_label(sh) .. "##shp" .. sh.s, nil, cur == sh.s) then
            ME.set_shape(track, addr, b, sh.s)
          end
        end
        ImGui.Separator(ctx)
      end
      -- its slope, by the plugin's own names (24 dB/oct, Brickwall)
      local sls, si, sp = ME.slopes(track, addr, b)
      if sls and ImGui.BeginMenu(ctx, "Slope  \u{00B7}  " .. tostring(sls[si] and sls[si].text or "")) then
        for i, r in ipairs(sls) do
          if ImGui.MenuItem(ctx, tostring(r.text) .. "##slp" .. i, nil, i == si) then
            reaper.TrackFX_SetParamNormalized(track, addr, sp, r.norm)
          end
        end
        ImGui.EndMenu(ctx)
      end
      if sls then ImGui.Separator(ctx) end
      -- a Q that's a switch (Narrow / Wide): its settings, by name
      local qp = ME.q_positions(track, addr, b)
      if qp then
        local qi = ME.q_index(track, addr, b, qp)
        ImGui.TextDisabled(ctx, "Q")
        for i, ps in ipairs(qp) do
          if ImGui.MenuItem(ctx, "   " .. tostring(ps.text) .. "##qp" .. i, nil, qi == i) then
            ME.set_q_pos(track, addr, b, i)
          end
        end
        ImGui.Separator(ctx)
      end
      if b.on then
        local on = ME.switch_on(track, addr, b.on)
        if ImGui.MenuItem(ctx, "On", nil, on) then
          local cur = reaper.TrackFX_GetParamNormalized(track, addr, b.on)
          reaper.TrackFX_SetParamNormalized(track, addr, b.on, cur >= 0.5 and 0 or 1)
        end
      end
      ImGui.Separator(ctx)
    end
    if ImGui.MenuItem(ctx, "Set up this layout\u{2026}") then req.canvas_setup = true end
    ImGui.EndPopup(ctx)
  end
end

return MP
