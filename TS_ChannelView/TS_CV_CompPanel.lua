-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_CompPanel.lua -- the transfer-curve canvas that replaces a panel's
  knob grid whenever its plugin is ReaComp, as the ReaEQ canvas does for
  ReaEQ. ReaComp's parameters, units and arithmetic live in
  TS_CV_ReaComp.lua; this file is ImGui only.

  WHAT'S ON IT
    behind everything   the plugin's input level over the last few beats
                        (filled up from the bottom, on the same dB scale
                        as the curve) and its gain reduction hanging from
                        the top, from its probe tap -- the trace a GR meter
                        opens out into, filling the canvas. Faded out on
                        the left, where the curve starts, and at the bottom.
    threshold           a line across the canvas; drag it up or down. A
                        knee widens it into a band that fades out at its
                        edges, knee dB thick; drag the grips on its edges.
    transfer curve      1:1 from the left up to the threshold, its corner
                        rounded by the knee, then the ratio. The dotted line
                        is where the signal would go uncompressed; the faint
                        amber wedge between is the reduction.
    ratio               the curve's right-hand end: drag it up or down and
                        the line swings about the corner.
    live dot            where the signal is on the curve right now -- its
                        input level across, input less the reduction ReaComp
                        reports up -- with a short tail. A hit lands on the
                        dotted line and sinks onto the curve at the attack
                        speed; it drifts back at the release speed.
    envelope            a see-through panel at the foot: the reduction
                        rising over the attack and falling straight into the
                        release (no hold), from the moment the signal
                        crosses the threshold (the dotted tick). Drag the top
                        node for attack, the end node for release, the start
                        node back before the tick for pre-comp. A = auto
                        release.
    output              a see-through panel beside it: Wet, Dry, auto
                        make-up and limit.
    meters              the reduction and the output level, full height on
                        the right.
    drawer              under the canvas, its width only: the detector --
                        input, RMS, its filters and preview.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local RC = require("TS_CV_ReaComp")
local T  = require("TS_CV_FXTree")
local TP = require("TS_CV_Taps")
local Tr = require("TS_CV_Trace")
local M  = require("TS_CV_Mappings")

local CP = {}
local ImGui

function CP.attach(imgui) ImGui = imgui end

-- the canvas's level scale, dBFS
local DB_TOP, DB_BOT = 6, -60   -- ReaComp's threshold goes to +6
-- the envelope's time scales, ms, each on its own share of the width
local ATK_LO, ATK_HI = 0.1, 500
local REL_LO, REL_HI = 1, 5000
local PRE_LO, PRE_HI = 0.1, 250

local state = {}
local function panel_state(guid)
  local s = state[guid]
  if not s then s = { trail = {}, drawer = false }; state[guid] = s end
  return s
end

-- ---------------------------------------------------------------------
-- small drawing helpers
-- ---------------------------------------------------------------------
local function polyline(dl, xs, ys, n, col, thick)
  for i = 1, n - 1 do
    ImGui.DrawList_AddLine(dl, xs[i], ys[i], xs[i + 1], ys[i + 1], col, thick)
  end
end

local function dashed(dl, x0, y0, x1, y1, col, on, off, thick)
  local dx, dy = x1 - x0, y1 - y0
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  local ux, uy = dx / len, dy / len
  local d = 0
  while d < len do
    local e = math.min(len, d + on)
    ImGui.DrawList_AddLine(dl, x0 + ux * d, y0 + uy * d, x0 + ux * e, y0 + uy * e, col, thick or 1.0)
    d = e + off
  end
end

-- a vertical gradient, top colour to bottom colour
local function vgrad(dl, x0, y0, x1, y1, top, bot)
  if y1 <= y0 or x1 <= x0 then return end
  ImGui.DrawList_AddRectFilledMultiColor(dl, x0, y0, x1, y1, top, top, bot, bot)
end

local function small_text(ctx, dl, x, y, col, text, align)
  W.push_small(ctx)
  local tw = ImGui.CalcTextSize(ctx, text)
  local tx = x
  if align == "right" then tx = x - tw elseif align == "centre" then tx = x - tw * 0.5 end
  ImGui.DrawList_AddText(dl, math.floor(tx + 0.5), math.floor(y + 0.5), col, text)
  W.pop_small(ctx)
  return tw
end

-- ---------------------------------------------------------------------
-- reading and writing in real units
-- ---------------------------------------------------------------------
local real_of  = RC.value
local set_real = RC.set
local range_of = RC.range

local function set_norm(track, addr, p, n)
  if not p then return end
  reaper.TrackFX_SetParamNormalized(track, addr, p, math.max(0, math.min(1, n)))
end

-- A drag in real units: the value it started from plus how far the mouse
-- has gone since, `per_px` units a pixel (a quarter of that with Shift).
-- Returns the new value while the item is being dragged.
local function drag_real(ctx, ps, id, start_v, per_px_x, per_px_y)
  local d = ps.drag
  if not d or d.id ~= id then
    local mx, my = ImGui.GetMousePos(ctx)
    d = { id = id, v = start_v, mx = mx, my = my }
    ps.drag = d
  end
  local mx, my = ImGui.GetMousePos(ctx)
  local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
  return d.v + ((mx - d.mx) * (per_px_x or 0) + (my - d.my) * (per_px_y or 0)) * fine
end

local function handle(ctx, id, x, y, w, h)
  W.allow_overlap(ctx)
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, id, math.max(1, w), math.max(1, h),
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local dragging = act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left)
  return hov, act, dragging
end

-- a mini knob for the see-through panels and the drawer: the dial, its
-- name under it and its value under that
local function mini_knob(ctx, dl, id, cx, cy, r, track, addr, p, name, ps)
  local nv = reaper.TrackFX_GetParamNormalized(track, addr, p)
  local txt = RC.text(track, addr, p, nv)
  local hov, act, dragging = handle(ctx, id, cx - r - 4, cy - r - 4, r * 2 + 8, r * 2 + 30)
  if dragging then
    local _, dy = ImGui.GetMouseDelta(ctx)
    if dy ~= 0 then
      local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and C.FINE_MULT or 1
      nv = math.max(0, math.min(1, nv - dy * C.DRAG_SENS * fine))
      set_norm(track, addr, p, nv)
    end
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  elseif hov then
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then
      local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and C.FINE_MULT or 1
      nv = math.max(0, math.min(1, nv + wheel * C.WHEEL_STEP * fine))
      set_norm(track, addr, p, nv)
      W.take_wheel()
    end
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      set_norm(track, addr, p, U.param_mid_norm(track, addr, p))
    end
  end
  W.knob_face(dl, cx, cy, r, nv, { hot = hov or act })
  small_text(ctx, dl, cx, cy + r + 2, C.COL.label, name, "centre")
  small_text(ctx, dl, cx, cy + r + 12, C.COL.value, txt or "", "centre")
  W.tip(ctx, id, name .. ": " .. (txt or ""), hov, act)
end

-- a small switch: lit in the accent when on
local function mini_toggle(ctx, dl, id, x, y, w, h, on, text, tip)
  local hov = handle(ctx, id, x, y, w, h)
  local clicked = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left)
  local bg = on and C.COL.toggle_on or C.COL.toggle_off
  if hov then bg = U.with_alpha(bg, 0xdd) end
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 3.0)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, on and C.COL.toggle_on or C.COL.knob_ring, 3.0, 0, 1.0)
  W.push_small(ctx)
  local tw, th = ImGui.CalcTextSize(ctx, text)
  local ink = on and 0x0d1116ff or C.COL.toggle_text
  ImGui.DrawList_AddText(dl, math.floor(x + (w - tw) * 0.5 + 0.5), math.floor(y + (h - th) * 0.5 + 0.5), ink, text)
  W.pop_small(ctx)
  if tip then W.tip(ctx, id, tip, hov, false) end
  return clicked
end

local function is_on(track, addr, p)
  return p and reaper.TrackFX_GetParamNormalized(track, addr, p) >= 0.5
end
local function flip(track, addr, p)
  if p then set_norm(track, addr, p, is_on(track, addr, p) and 0 or 1) end
end

-- ---------------------------------------------------------------------
-- the level history and the reduction, behind everything
-- ---------------------------------------------------------------------
local function lin_db(a)
  if not a or a <= 0.000001 then return -120 end
  return 20 * math.log(a, 10)
end

local function draw_history(ctx, dl, gx0, gy0, gw, gh, track, fx, gr, ymap, range)
  Tr.want(track)
  TP.panel_open(fx.guid)
  local pw = math.max(1, math.floor(gw))
  local d, m1, m2 = Tr.columns(track, fx, { win = CP.window() }, false, gr, pw)
  if not d then return m1, m2 end
  -- the output filled up from the foot, the input a fainter wash above
  -- it: the gap between them is what the compressor took off
  -- in the ReaEQ canvas's spectrum tint, so the two read as the same
  -- thing: what the audio is doing behind the curve
  local in_fill  = U.with_alpha(C.COL.eq_spectrum, 0x70)
  local out_fill = U.with_alpha(C.COL.eq_spectrum, 0xd8)
  local grc = W.gr_fill_col(false, false)
  local gr_fill = U.with_alpha(grc, 0x22)
  -- the reduction hangs from the top on the METER's scale, so it reads
  -- against the bar beside it: the same range, stepping up when a hit
  -- pulls down harder than it
  local per_db = gh / range
  local bot = gy0 + gh
  local gx, gy, n = {}, {}, 0
  for px = 0, pw - 1 do
    local xx = gx0 + px + 0.5
    local yi = ymap(math.max(DB_BOT, lin_db(d.ip[px + 1] or 0)))
    local op = math.max(-(d.mn[px + 1] or 0), d.mx[px + 1] or 0)
    local yo = ymap(math.max(DB_BOT, lin_db(op)))
    if yo < bot then ImGui.DrawList_AddLine(dl, xx, yo, xx, bot, out_fill, 1.0) end
    if yi < yo - 0.5 then ImGui.DrawList_AddLine(dl, xx, yi, xx, yo, in_fill, 1.0) end
    local g = d.g[px + 1]
    if g then
      local yy = gy0 + math.min(gh, math.max(0, g) * per_db)
      if yy > gy0 + 0.5 then ImGui.DrawList_AddLine(dl, xx, gy0, xx, yy, gr_fill, 1.0) end
      n = n + 1; gx[n], gy[n] = xx, yy
    end
  end
  polyline(dl, gx, gy, n, grc, 1.5)
  return nil
end

-- The history's window. A beat window is locked to the beat, so it only
-- steps once a beat -- right for a trace you read against the bar, wrong
-- for a canvas you watch: the default is seconds, and it scrolls every
-- frame. Saved in ReaComp's layout, as a trace's window is.
CP.WINDOW_DEFAULT = "4s"
function CP.window()
  local layout = M.get("ReaComp")
  local m = layout and layout.meter
  return (m and m.win) or CP.WINDOW_DEFAULT
end

-- ---------------------------------------------------------------------
-- the envelope panel
-- ---------------------------------------------------------------------
local function draw_envelope(ctx, dl, px, py, pw, ph, track, addr, f, ps, guid)
  ImGui.DrawList_AddRectFilled(dl, px, py, px + pw, py + ph, U.with_alpha(C.COL.win_bg, 0xc8), 5.0)
  ImGui.DrawList_AddRect(dl, px, py, px + pw, py + ph, C.COL.knob_ring, 5.0, 0, 1.0)

  local atk = real_of(track, addr, f.atk) or 0
  local rel = real_of(track, addr, f.rel) or 0
  local pre = f.pre and (real_of(track, addr, f.pre) or 0) or 0
  local auto = f.autorel and is_on(track, addr, f.autorel)

  local gx0, gx1 = px + 10, px + pw - 10
  local base, peak = py + ph - 24, py + 14
  local PRE_W = f.pre and 24 or 0
  local inner = gx1 - gx0 - PRE_W
  local ATK_W, REL_W = inner * 0.34, inner * 0.62
  local on = gx0 + PRE_W
  local st = on - RC.time_frac(pre, PRE_LO, PRE_HI) * PRE_W
  local ak = on + RC.time_frac(atk, ATK_LO, ATK_HI) * ATK_W
  local re = ak + RC.time_frac(rel, REL_LO, REL_HI) * REL_W

  -- the moment the signal crosses the threshold
  dashed(dl, on, peak - 2, on, base + 2, U.with_alpha(C.COL.header_dim, 0x90), 2, 3, 1.0)
  ImGui.DrawList_AddLine(dl, gx0, base, gx1, base, U.with_alpha(C.COL.knob_ring, 0xc0), 1.0)

  local xs, ys = { gx0, st }, { base, base }
  local N = 20
  for i = 1, N do
    local t = i / N
    xs[#xs + 1] = st + (ak - st) * t
    ys[#ys + 1] = base + (peak - base) * RC.rise(t, 3.2)
  end
  local rx, ry = { ak }, { peak }
  for i = 1, 26 do
    local t = i / 26
    rx[#rx + 1] = ak + (re - ak) * t
    ry[#ry + 1] = peak + (base - peak) * RC.rise(t, 3.5)
  end
  rx[#rx + 1], ry[#ry + 1] = gx1, base

  -- the fill under it
  local fill = U.with_alpha(C.COL.accent, 0x2e)
  local function fill_under(xa, ya)
    for i = 1, #xa - 1 do
      local x0, x1 = xa[i], xa[i + 1]
      local y0 = math.min(ya[i], ya[i + 1])
      if x1 > x0 + 0.01 and y0 < base then
        ImGui.DrawList_AddRectFilled(dl, x0, y0, x1, base, fill)
      end
    end
  end
  fill_under(xs, ys); fill_under(rx, ry)
  polyline(dl, xs, ys, #xs, C.COL.accent, 2.0)
  if auto then
    for i = 1, #rx - 1, 2 do
      ImGui.DrawList_AddLine(dl, rx[i], ry[i], rx[i + 1], ry[i + 1], C.COL.accent, 2.0)
    end
  else
    polyline(dl, rx, ry, #rx, C.COL.accent, 2.0)
  end

  -- the nodes
  local R = 5
  local function node(id, nx, ny, hollow, tip, on_drag)
    local hov, act, dragging = handle(ctx, id, nx - R - 3, ny - R - 3, (R + 3) * 2, (R + 3) * 2)
    if dragging then on_drag(); ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW) end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    local fillc = hollow and C.COL.win_bg or C.COL.header_text
    ImGui.DrawList_AddCircleFilled(dl, nx, ny, R, fillc)
    ImGui.DrawList_AddCircle(dl, nx, ny, R, (hov or act) and C.COL.header_text or C.COL.accent, 0, 1.6)
    W.tip(ctx, id, tip(), hov, act)
  end
  if f.pre then
    node("rcpre##" .. guid, st, base, false,
      function() return ("Pre-comp %s\nDrag left: start reducing before the signal arrives\n(adds that much latency)"):format(select(3, real_of(track, addr, f.pre)) or "") end,
      function()
        local fr = drag_real(ctx, ps, "rcpre##" .. guid, RC.time_frac(pre, PRE_LO, PRE_HI), -1 / PRE_W, 0)
        set_real(track, addr, f.pre, RC.frac_time(math.max(0, math.min(1, fr)), PRE_LO, PRE_HI))
      end)
  end
  node("rcatk##" .. guid, ak, peak, false,
    function() return ("Attack %s\nDrag left or right"):format(select(3, real_of(track, addr, f.atk)) or "") end,
    function()
      local fr = drag_real(ctx, ps, "rcatk##" .. guid, RC.time_frac(atk, ATK_LO, ATK_HI), 1 / ATK_W, 0)
      set_real(track, addr, f.atk, RC.frac_time(math.max(0, math.min(1, fr)), ATK_LO, ATK_HI))
    end)
  node("rcrel##" .. guid, re, base, auto,
    function() return ("Release %s%s\nDrag left or right"):format(select(3, real_of(track, addr, f.rel)) or "",
      auto and "\n(auto release is on: this is its ceiling)" or "") end,
    function()
      local fr = drag_real(ctx, ps, "rcrel##" .. guid, RC.time_frac(rel, REL_LO, REL_HI), 1 / REL_W, 0)
      set_real(track, addr, f.rel, RC.frac_time(math.max(0, math.min(1, fr)), REL_LO, REL_HI))
    end)

  -- the readouts
  local ly = py + ph - 15
  local _, _, atxt = real_of(track, addr, f.atk)
  local _, _, rtxt = real_of(track, addr, f.rel)
  small_text(ctx, dl, gx0, ly, C.COL.value, "Atk " .. (atxt or ""))
  small_text(ctx, dl, gx1, ly, C.COL.value, "Rel " .. (auto and "auto" or (rtxt or "")), "right")
  if f.pre then
    local _, _, ptxt = real_of(track, addr, f.pre)
    if pre > 0 then small_text(ctx, dl, gx1 - (f.autorel and 22 or 0), py + 6, C.COL.label, "Pre " .. (ptxt or ""), "right") end
  end
  if f.autorel then
    if mini_toggle(ctx, dl, "rcar##" .. guid, gx1 - 14, py + 5, 16, 14, auto, "A",
                   "Auto release: the release follows the music, up to the time set") then
      flip(track, addr, f.autorel)
    end
  end
end

-- ---------------------------------------------------------------------
-- the output panel
-- ---------------------------------------------------------------------
local function draw_output(ctx, dl, px, py, pw, ph, track, addr, f, ps, guid)
  ImGui.DrawList_AddRectFilled(dl, px, py, px + pw, py + ph, U.with_alpha(C.COL.win_bg, 0xc8), 5.0)
  ImGui.DrawList_AddRect(dl, px, py, px + pw, py + ph, C.COL.knob_ring, 5.0, 0, 1.0)
  local r = 10
  if f.wet then mini_knob(ctx, dl, "rcwet##" .. guid, px + 26, py + 17, r, track, addr, f.wet, "Wet", ps) end
  if f.dry then mini_knob(ctx, dl, "rcdry##" .. guid, px + pw - 26, py + 17, r, track, addr, f.dry, "Dry", ps) end
  local bw = f.limit and (pw - 16) * 0.5 or (pw - 12)
  local by = py + ph - 20
  if f.makeup and mini_toggle(ctx, dl, "rcmk##" .. guid, px + 6, by, bw, 15,
                              is_on(track, addr, f.makeup), "MAKE-UP", "Auto make-up gain") then
    flip(track, addr, f.makeup)
  end
  if f.limit and mini_toggle(ctx, dl, "rclim##" .. guid, px + 10 + bw, by, bw, 15,
                             is_on(track, addr, f.limit), "LIMIT", "Limit the output to 0 dBFS") then
    flip(track, addr, f.limit)
  end
end

-- ---------------------------------------------------------------------
-- the meters column
-- ---------------------------------------------------------------------
CP.METERS_W = 72

local function draw_meters(ctx, dl, x, y, w, h, track, fx, gr, enabled, peak, range)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, U.with_alpha(C.COL.win_bg, 0x70))
  ImGui.DrawList_AddLine(dl, x, y, x, y + h, C.COL.panel_border, 1.0)
  local now = reaper.time_precise()
  local gw = 36
  W.gr_meter(ctx, dl, x + 2, y + 4, gw, h - 8, gr or 0, peak, range, false, false)
  local lv = TP.levels(track, fx.guid)
  local ox = x + 2 + gw + 2
  local ow = w - gw - 6
  if lv and not lv.old then
    local pk = enabled and lv.out_pk or -150
    local hold = W.level_peak("rcout" .. fx.guid, pk, now)
    local txt = (hold and hold > -149) and ("%.1f"):format(hold) or "\u{2013}"
    W.io_bar(ctx, dl, ox, y + 4, ow, h - 8, "rcout" .. fx.guid, pk, enabled and lv.out_rms or -150, txt, C.COL.value)
  else
    W.io_bar(ctx, dl, ox, y + 4, ow, h - 8, "rcout" .. fx.guid, -150, nil, "\u{2013}", C.COL.header_dim)
  end
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "rcmet##" .. fx.guid, w, h)
  W.tip(ctx, "rcmet##" .. fx.guid,
    ("Gain reduction %.1f dB (peak %.1f)\nOutput level, dBFS"):format(gr or 0, peak or 0),
    ImGui.IsItemHovered(ctx), false)
end

-- ---------------------------------------------------------------------
-- the drawer
-- ---------------------------------------------------------------------
CP.DRAWER_SHUT, CP.DRAWER_OPEN = 13, 76

local function draw_drawer(ctx, dl, x, y, w, h, track, addr, f, ps, guid)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, U.with_alpha(C.COL.win_bg, 0x90))
  ImGui.DrawList_AddLine(dl, x, y, x + w, y, C.COL.panel_border, 1.0)
  -- the tab
  local tw = 84
  local tx = x + (w - tw) * 0.5
  local hov = handle(ctx, "rcdrw##" .. guid, tx, y - 1, tw, 13)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then ps.drawer = not ps.drawer end
  ImGui.DrawList_AddRectFilled(dl, tx, y - 1, tx + tw, y + 12,
    hov and C.COL.knob_body_hi or C.COL.knob_body, 3.0)
  small_text(ctx, dl, tx + tw * 0.5, y, C.COL.label,
    (ps.drawer and "\u{25be} " or "\u{25b4} ") .. "Detector", "centre")
  W.tip(ctx, "rcdrw##" .. guid, ps.drawer and "Hide the detector" or "Show the detector settings", hov, false)
  if not ps.drawer then return end

  local cy = y + 30
  -- the detector's input: a list of its choices
  if f.det then
    local cur = reaper.TrackFX_GetParamNormalized(track, addr, f.det)
    local txt = RC.det_text(cur)
    small_text(ctx, dl, x + 8, y + 15, C.COL.header_dim, "Detector")
    if W.dropdown(ctx, "rcdet##" .. guid, txt, x + 8, y + 28, 112, 17, "What the detector listens to") then
      ImGui.OpenPopup(ctx, "rcdetp##" .. guid)
    end
    if ImGui.BeginPopup(ctx, "rcdetp##" .. guid) then
      for _, ch in ipairs(RC.DET_CHOICES) do
        if ImGui.MenuItem(ctx, ch[2], nil, ch[2] == txt) then
          set_norm(track, addr, f.det, ch[1] / RC.DET_MAX)
        end
      end
      ImGui.EndPopup(ctx)
    end
  end
  local kx = x + 152
  for _, k in ipairs({ { "rms", "RMS" }, { "lp", "Low-pass" }, { "hp", "High-pass" } }) do
    if f[k[1]] then
      mini_knob(ctx, dl, "rc" .. k[1] .. "##" .. guid, kx, cy, 10, track, addr, f[k[1]], k[2], ps)
      kx = kx + 58
    end
  end
  if f.audio then
    local on = is_on(track, addr, f.audio)
    if mini_toggle(ctx, dl, "rcaud##" .. guid, x + w - 94, y + 28, 86, 17, on, "PREVIEW FILTER",
                   "Listen to what the detector hears") then
      flip(track, addr, f.audio)
    end
  end
end

-- ---------------------------------------------------------------------
-- the canvas
-- ---------------------------------------------------------------------
function CP.draw(ctx, dl, x, y, w, h, track, fx, req)
  local addr, guid = fx.addr, fx.guid
  local ps = panel_state(guid)
  local f = RC.params(track, addr, guid)
  if not RC.usable(f) then return false end
  if w < 120 or h < 80 then return true end
  local enabled = T.get_enabled(track, addr)

  local mw = CP.METERS_W
  local dh = ps.drawer and CP.DRAWER_OPEN or CP.DRAWER_SHUT
  local gx0, gy0 = x + 1, y
  local gw, gh = w - mw - 1, h - dh
  if gh < 40 then dh = CP.DRAWER_SHUT; gh = h - dh end

  local thr, _, _, mthr = real_of(track, addr, f.thr)
  local ratio, _, rtxt, mratio = real_of(track, addr, f.ratio)
  local knee = f.knee and real_of(track, addr, f.knee) or 0
  thr = thr or -20
  if thr == -math.huge then thr = DB_BOT end
  ratio = ratio or 1
  knee = (knee and knee > 0 and knee < math.huge) and knee or 0
  local gr = T.gain_reduction(track, addr) or 0

  local function x_of(db) return gx0 + (db - DB_BOT) / (DB_TOP - DB_BOT) * gw end
  local function y_of(db) return gy0 + (DB_TOP - db) / (DB_TOP - DB_BOT) * gh end
  local function db_of_y(py) return DB_TOP - (py - gy0) / gh * (DB_TOP - DB_BOT) end
  local function out(db) return RC.transfer(db, thr, ratio, knee) end

  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)
  ImGui.DrawList_AddRectFilled(dl, gx0, gy0, gx0 + gw, gy0 + gh, 0x00000030)

  -- grid
  for _, g in ipairs({ 0, -12, -24, -36, -48 }) do
    local yy = math.floor(y_of(g)) + 0.5
    ImGui.DrawList_AddLine(dl, gx0, yy, gx0 + gw, yy, U.with_alpha(C.COL.eq_grid, 0xc0), 1.0)
    small_text(ctx, dl, gx0 + 3, yy - 11, U.with_alpha(C.COL.header_dim, 0xa0), tostring(g))
  end

  -- the level history and the reduction
  -- the meter's range (its minimum 12 dB, stepping up as a hit needs),
  -- shared with the reduction drawn behind the curve
  local gr_peak, gr_range = W.gr_state(guid, gr, reaper.time_precise(), 12)
  local m1, m2 = draw_history(ctx, dl, gx0, gy0, gw, gh, track, fx, gr, y_of, gr_range)

  -- faded on the left, where the curve starts, and at the foot
  local bg = C.COL.panel_bg
  local a0 = U.with_alpha(bg, 0)
  W.hgrad4(dl, gx0, gy0, gx0 + gw * 0.45, gy0 + gh, U.with_alpha(bg, 0xb0), U.with_alpha(bg, 0x40), U.with_alpha(bg, 0x40), U.with_alpha(bg, 0xb0))
  W.hgrad4(dl, gx0 + gw * 0.45, gy0, gx0 + gw * 0.7, gy0 + gh, U.with_alpha(bg, 0x40), a0, a0, U.with_alpha(bg, 0x40))
  -- only a little at the foot: the level history lives there, and the
  -- see-through panels carry their own backgrounds
  vgrad(dl, gx0, gy0 + gh * 0.6, gx0 + gw, gy0 + gh, a0, U.with_alpha(bg, 0x60))
  if m1 then
    small_text(ctx, dl, gx0 + gw - 4, gy0 + 3, C.COL.header_dim, m1, "right")
    if m2 then small_text(ctx, dl, gx0 + gw - 4, gy0 + 14, C.COL.header_dim, m2, "right") end
  end

  -- right-click the canvas for the history's window (as a trace has)
  do
    local hov = handle(ctx, "rcbg##" .. guid, gx0, gy0, gw, gh)
    local pop = "rcwin##" .. guid
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then ImGui.OpenPopup(ctx, pop) end
    if ImGui.BeginPopup(ctx, pop) then
      ImGui.TextDisabled(ctx, "History")
      local cur = CP.window()
      for _, wv in ipairs(C.GRV_WINDOWS) do
        if ImGui.MenuItem(ctx, Tr.label(wv), nil, wv == cur) then req.grv_window = wv end
      end
      ImGui.EndPopup(ctx)
    end
    local _ = hov
  end

  -- the threshold, widened by the knee into a band that fades at its edges
  local ty = y_of(thr)
  if knee > 0 then
    local ta, tb = y_of(thr + knee * 0.5), y_of(thr - knee * 0.5)
    local mid = U.with_alpha(C.COL.accent, 0x80)
    local clear = U.with_alpha(C.COL.accent, 0)
    vgrad(dl, gx0, ta, gx0 + gw, ty, clear, mid)
    vgrad(dl, gx0, ty, gx0 + gw, tb, mid, clear)
  end
  ImGui.DrawList_AddLine(dl, gx0, ty, gx0 + gw, ty, C.COL.accent, 1.6)

  -- the reduction wedge, and the dotted no-compression line
  local k0 = thr - knee * 0.5
  local wedge = U.with_alpha(W.gr_fill_col(false, false), 0x1c)
  local xa, xb = math.max(gx0, math.floor(x_of(k0))), gx0 + gw
  for px = xa, xb, 1 do
    local db = DB_BOT + (px - gx0) / gw * (DB_TOP - DB_BOT)
    local y1, y2 = y_of(db), y_of(out(db))
    if y2 - y1 > 0.5 then ImGui.DrawList_AddLine(dl, px + 0.5, y1, px + 0.5, y2, wedge, 1.0) end
  end
  dashed(dl, x_of(k0), y_of(k0), x_of(DB_TOP), y_of(DB_TOP), U.with_alpha(C.COL.label, 0xa0), 3, 4, 1.0)

  -- the transfer curve
  local xs, ys, n = {}, {}, 0
  local SEG = 160
  for i = 0, SEG do
    local db = DB_BOT + (DB_TOP - DB_BOT) * i / SEG
    n = n + 1; xs[n], ys[n] = x_of(db), y_of(out(db))
  end
  polyline(dl, xs, ys, n, C.COL.fader_cap, 2.2)

  -- the live dot
  local lv = TP.levels(track, guid)
  local tr = ps.trail
  if lv and not lv.old and enabled and lv.in_pk and lv.in_pk > DB_BOT then
    local ind = math.min(DB_TOP + 6, lv.in_pk)
    tr[#tr + 1] = { ind, ind - gr }
  else
    tr[#tr + 1] = false
  end
  while #tr > 14 do table.remove(tr, 1) end
  local grc = W.gr_fill_col(false, false)
  for i = 1, #tr - 1 do
    local p = tr[i]
    if p then
      ImGui.DrawList_AddCircleFilled(dl, x_of(p[1]), y_of(p[2]), 1.4 + i * 0.18,
        U.with_alpha(grc, math.floor(0x20 + i * 0x0c)))
    end
  end
  local head = tr[#tr]
  if head then
    local hx, hy = x_of(head[1]), y_of(head[2])
    local cy_ = y_of(out(head[1]))
    if cy_ - hy > 2 then dashed(dl, hx, hy + 5, hx, cy_ - 1, U.with_alpha(grc, 0xb0), 2, 2, 1.0) end
    ImGui.DrawList_AddCircleFilled(dl, hx, hy, 9, U.with_alpha(grc, 0x30))
    ImGui.DrawList_AddCircleFilled(dl, hx, hy, 4.5, 0xffd8b0ff)
    ImGui.DrawList_AddCircle(dl, hx, hy, 4.5, grc, 0, 1.5)
  end

  -- the readouts
  local _, _, ttxt = real_of(track, addr, f.thr)
  ImGui.DrawList_AddText(dl, gx0 + 8, ty - 17, C.COL.value, ttxt or "")
  small_text(ctx, dl, gx0 + 8, ty + 3, C.COL.header_dim, "Threshold")

  -- ratio, at the curve's right-hand end
  local ex, ey = gx0 + gw - 7, y_of(out(DB_TOP))
  local rlabel = (ratio == math.huge) and "\u{221e} : 1"
                 or (((rtxt or ""):gsub("%s*:%s*1%s*$", "")) .. " : 1")
  local rw = ImGui.CalcTextSize(ctx, rlabel)
  ImGui.DrawList_AddText(dl, ex - 10 - rw, ey - 19, C.COL.value, rlabel)
  small_text(ctx, dl, ex - 10, ey + 6, C.COL.header_dim, "Ratio", "right")

  ImGui.DrawList_PopClipRect(dl)

  -- ---------------------------------------------------------------
  -- the handles: drawn last so they win the hover
  -- ---------------------------------------------------------------
  local per_db_y = (DB_TOP - DB_BOT) / gh
  local thr_lo, thr_hi = range_of(mthr)
  thr_lo, thr_hi = thr_lo or DB_BOT, thr_hi or DB_TOP

  -- threshold: the whole line is a handle, the pill on the corner marks it
  do
    local id = "rcthr##" .. guid
    local hov, act, dragging = handle(ctx, id, gx0, ty - 4, gw - 18, 8)
    if dragging then
      local v = drag_real(ctx, ps, id, thr, 0, -per_db_y)
      set_real(track, addr, f.thr, math.max(thr_lo, math.min(thr_hi, v)))
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    elseif hov then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
      local wheel = W.control_wheel(ctx)
      if wheel ~= 0 then
        local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.1 or 0.5
        set_real(track, addr, f.thr, math.max(thr_lo, math.min(thr_hi, thr + wheel * fine)))
        W.take_wheel()
      end
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    local kx = x_of(thr)
    local pill = (hov or act) and C.COL.header_text or C.COL.accent
    ImGui.DrawList_AddRectFilled(dl, kx - 20, ty - 4, kx + 20, ty + 4, pill, 4.0)
    W.tip(ctx, id, ("Threshold %s\nDrag up or down (Shift: fine)"):format(ttxt or ""), hov, act)
  end

  -- knee grips, on the band's edges
  if f.knee then
    local _, _, ktxt, mknee = real_of(track, addr, f.knee)
    local klo, khi = range_of(mknee)
    klo, khi = klo or 0, khi or 24
    local gxk = math.max(gx0 + 70, x_of(thr) - 80)
    for s = 1, 2 do
      local edge = (s == 1) and (thr + knee * 0.5) or (thr - knee * 0.5)
      local ey_ = y_of(edge) + ((s == 1) and -3 or 3)
      local id = "rcknee" .. s .. "##" .. guid
      local hov, act, dragging = handle(ctx, id, gxk - 2, ey_ - 4, 18, 8)
      if dragging then
        local sign = (s == 1) and -1 or 1
        local v = drag_real(ctx, ps, id, knee, 0, sign * 2 * per_db_y)
        set_real(track, addr, f.knee, math.max(klo, math.min(khi, v)))
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
      end
      if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
      ImGui.DrawList_AddRectFilled(dl, gxk, ey_ - 2, gxk + 14, ey_ + 2,
        (hov or act) and C.COL.header_text or U.with_alpha(C.COL.accent, 0xd8), 2.0)
      W.tip(ctx, id, ("Knee %s\nDrag away from the threshold to soften it"):format(ktxt or ""), hov, act)
      if s == 1 then
        small_text(ctx, dl, gxk - 5, ey_ - 6, C.COL.label, "Knee " .. (ktxt or ""), "right")
      end
    end
  end

  -- ratio: the line's end swings about the corner
  do
    local id = "rcratio##" .. guid
    local hov, act, dragging = handle(ctx, id, ex - 7, ey - 7, 14, 14)
    if dragging then
      local d = ps.drag
      if not d or d.id ~= id then
        local _, my = ImGui.GetMousePos(ctx)
        ps.drag = { id = id, my = my, y0 = ey }
        d = ps.drag
      end
      local _, my = ImGui.GetMousePos(ctx)
      local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
      local end_db = db_of_y(d.y0 + (my - d.my) * fine)
      local rise = DB_TOP - thr
      local lo, hi = range_of(mratio)
      lo, hi = lo or 1, hi or 100
      -- flat at the top of the range: infinite (ReaComp's last position)
      if rise > 0.01 and end_db - thr <= rise / hi then
        set_norm(track, addr, f.ratio, 1)
      else
        local r = (rise <= 0.01) and ratio or rise / math.max(0.0001, end_db - thr)
        if r == math.huge then r = hi end
        set_real(track, addr, f.ratio, math.max(lo, math.min(hi, r)))
      end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    ImGui.DrawList_AddCircleFilled(dl, ex, ey, 5, (hov or act) and C.COL.header_text or C.COL.fader_cap)
    W.tip(ctx, id, ("Ratio %s\nDrag up or down"):format(rlabel), hov, act)
  end

  -- the see-through panels, anchored to the canvas's foot
  local ph, ow, ew = 82, 104, 176
  local py = gy0 + gh - ph - 8
  local ox = gx0 + gw - 8 - ow
  local exl = ox - 8 - ew
  if py > gy0 + 30 and exl > gx0 + 40 then
    draw_envelope(ctx, dl, exl, py, ew, ph, track, addr, f, ps, guid)
    draw_output(ctx, dl, ox, py, ow, ph, track, addr, f, ps, guid)
  end

  draw_meters(ctx, dl, x + w - mw, y, mw, h, track, fx, gr, enabled, gr_peak, gr_range)
  draw_drawer(ctx, dl, gx0, gy0 + gh, gw, dh, track, addr, f, ps, guid)
  return true
end

return CP
