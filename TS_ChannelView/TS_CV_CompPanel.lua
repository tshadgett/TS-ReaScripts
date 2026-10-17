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

-- lift: dB the input is drawn raised by (an input-driven compressor's
-- gain: its canvas is drawn after the gain)
local function draw_history(ctx, dl, gx0, gy0, gw, gh, track, fx, gr, ymap, range, lift)
  lift = lift or 0
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
    local yi = ymap(math.max(DB_BOT, lin_db(d.ip[px + 1] or 0) + lift))
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
      function() return ("Pre-comp %s (adds latency)\nDrag: left to start reducing earlier"):format(select(3, real_of(track, addr, f.pre)) or "") end,
      function()
        local fr = drag_real(ctx, ps, "rcpre##" .. guid, RC.time_frac(pre, PRE_LO, PRE_HI), -1 / PRE_W, 0)
        set_real(track, addr, f.pre, RC.frac_time(math.max(0, math.min(1, fr)), PRE_LO, PRE_HI))
      end)
  end
  node("rcatk##" .. guid, ak, peak, false,
    function() return ("Attack %s\nDrag: left or right"):format(select(3, real_of(track, addr, f.atk)) or "") end,
    function()
      local fr = drag_real(ctx, ps, "rcatk##" .. guid, RC.time_frac(atk, ATK_LO, ATK_HI), 1 / ATK_W, 0)
      set_real(track, addr, f.atk, RC.frac_time(math.max(0, math.min(1, fr)), ATK_LO, ATK_HI))
    end)
  node("rcrel##" .. guid, re, base, auto,
    function() return ("Release %s%s\nDrag: left or right"):format(select(3, real_of(track, addr, f.rel)) or "",
      auto and "\nAuto release: this is its ceiling" or "") end,
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
-- the strip beside the curve: the reduction (input and output levels,
-- when asked for, go on the panel's outside edges, as on any panel)
CP.METERS_W = 44
CP.FINE_ON = TP.FINE_ON   -- the reduction by frequency: switched off (TS_CV_Taps)

-- fine_btn: a compressor canvas's "Hz" switch at the foot, between its
-- transfer curve and its reduction by frequency (while it's tapped)
local function draw_meters(ctx, dl, x, y, w, h, track, fx, gr, enabled, peak, range, fine_btn)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, U.with_alpha(C.COL.win_bg, 0x70))
  ImGui.DrawList_AddLine(dl, x, y, x, y + h, C.COL.panel_border, 1.0)
  local ok = CP.FINE_ON and fine_btn and h > 120 and TP.fine_ok(track, fx.guid)
  if ok then
    local ps = panel_state(fx.guid)
    if ok ~= true then ps.fine = false end
    h = h - 20
    local tip = (ok ~= true) and "By frequency\nReopen the project to load the newer probe."
      or (ps.fine and "Back to the curve" or "Reduction by frequency (third-octaves)")
    if mini_toggle(ctx, dl, "rcfine##" .. fx.guid, x + 6, y + h + 2, w - 10, 15, ps.fine, "Hz", tip) and ok == true then
      ps.fine = not ps.fine
    end
  end
  W.gr_meter(ctx, dl, x + 4, y + 4, w - 8, h - 8, gr or 0, peak, range, false, false)
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "rcmet##" .. fx.guid, w, h)
  W.tip(ctx, "rcmet##" .. fx.guid,
    ("Gain reduction %.1f dB (peak %.1f)\nI/O levels: panel menu \u{25B8} Input/output meters"):format(gr or 0, peak or 0),
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
  W.tip(ctx, "rcdrw##" .. guid, ps.drawer and "Hide the detector" or "Show the detector", hov, false)
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
-- ---------------------------------------------------------------------
-- the reduction by frequency, in third-octaves (TS_TrackProbe 1.7.0+)
-- ---------------------------------------------------------------------
-- The probe compares the audio either side of a tapped plugin band by
-- band: how far each third-octave sits below where it sits with no
-- reduction (its zero, from the calibration's noise, else the music so
-- far). One plugin a track at a time, and only while a panel asks.
CP.FINE_COL = 0xe6cf79ff

-- One frame of it, smoothed for drawing: { n, f = { Hz }, g = { reduction
-- dB, positive; nil no signal }, pk = { held peak }, lv = { level going
-- in, dBFS }, cal, range = the depth to draw to }; or nil and why
-- ("old", "busy", "wait", or false when the plugin isn't tapped).
function CP.fine_frame(track, guid)
  local ps = panel_state(guid)
  -- asking lays a tap for it while the panel is open (TS_CV_Taps wants_mb)
  TP.panel_open(guid)
  TP.want_fine(guid)
  local ok = TP.fine_ok(track, guid)
  if ok ~= true then ps.fsm = nil; return nil, ok end
  if not TP.set_fine(track, guid) then ps.fsm = nil; return nil, "busy" end
  local fd = TP.fine(track, guid)
  if not fd then ps.fsm = nil; return nil, "wait" end
  local now = reaper.time_precise()
  local dt = math.max(0, math.min(0.2, now - (ps.fat or now))); ps.fat = now
  local sm, pk = ps.fsm or {}, ps.fpk or {}
  local top = 0
  -- a band with next to nothing in it (a guitar's top octave) compares
  -- near-silence with near-silence: its ratio swings by tens of dB and
  -- means nothing. Bands more than 45 dB under the loudest, or under
  -- -90 dBFS, count as no signal.
  local lvmax = -math.huge
  for k = 1, fd.n do
    local l = fd.lv[k]
    if l and l > lvmax then lvmax = l end
  end
  local floor_ = math.max(-90, lvmax - 45)
  for k = 1, 31 do
    local d = k <= fd.n and fd.d[k] or nil
    if d and (fd.lv[k] or -150) < floor_ then d = nil end
    if d then
      local g = -d
      local s0 = sm[k]
      local s = s0 and (s0 + (g - s0) * math.min(1, dt * 12)) or g
      sm[k] = s
      pk[k] = math.max(s, (pk[k] or s) - dt * 4)
      top = math.max(top, pk[k])
    else
      sm[k], pk[k] = nil, nil
    end
  end
  ps.fsm, ps.fpk = sm, pk
  -- the depth drawn steps (6, 12, 24, 48 dB) so it doesn't breathe;
  -- deeper at once, shallower after three quiet seconds
  local want = 6
  while want < top * 1.15 and want < 48 do want = want * 2 end
  if not ps.frng or want > ps.frng then ps.frng, ps.frng_t = want, now
  elseif want == ps.frng then ps.frng_t = now
  elseif now - (ps.frng_t or 0) > 3 then ps.frng, ps.frng_t = want, now end
  return { n = fd.n, f = fd.f, g = sm, pk = pk, lv = fd.lv, cal = fd.cal, range = ps.frng }
end

-- Why there's nothing to draw, in words.
function CP.fine_why(why)
  if why == "old" then return "Reopen the project to load the newer probe", "(TS_TrackProbe 1.7.0 measures this)" end
  if why == "busy" then return "Another panel on this track is measuring", "by frequency (one plugin a track at a time)" end
  if why == "wait" then return "Measured while audio plays through it", nil end
  return "Not measured yet: it needs a probe tap on this track", nil
end

-- The reduction as a curve hanging from a zero line at y0, `fr.range` dB
-- down at y1 (a lift above zero shows above it, up to a quarter of that).
-- xf(Hz) places a band. Breaks where a band has no signal.
function CP.fine_curve(dl, fr, xf, y0, y1, opts)
  opts = opts or {}
  local col = opts.col or CP.FINE_COL
  local rng = fr.range or 12
  local per = (y1 - y0) / rng
  local function y_of(g) return y0 + math.max(-rng * 0.25, math.min(rng, g)) * per end
  -- the fill, a column a band's width wide, between the zero and the curve
  local fill = U.with_alpha(col, opts.fill_a or 0x30)
  local h6 = 2 ^ (1 / 6)
  for k = 1, fr.n do
    local g = fr.g[k]
    if g and math.abs(g) > 0.15 then
      local a, b = xf(fr.f[k] / h6), xf(fr.f[k] * h6)
      local yy = y_of(g)
      ImGui.DrawList_AddRectFilled(dl, a + 0.5, math.min(y0, yy), b - 0.5, math.max(y0, yy), fill)
    end
  end
  -- the held peaks, faint ticks
  if not opts.no_peak then
    local pc = U.with_alpha(col, 0x70)
    for k = 1, fr.n do
      local p = fr.pk[k]
      if p and p > 0.3 then
        local a, b = xf(fr.f[k] / h6), xf(fr.f[k] * h6)
        local yy = y_of(p)
        ImGui.DrawList_AddLine(dl, a + 1.5, yy, b - 1.5, yy, pc, 1.0)
      end
    end
  end
  -- the curve, through the bands' centres
  local xs, ys, n = {}, {}, 0
  local function flush()
    if n >= 2 then polyline(dl, xs, ys, n, col, opts.thick or 2.0) end
    xs, ys, n = {}, {}, 0
  end
  for k = 1, fr.n do
    local g = fr.g[k]
    if g then n = n + 1; xs[n], ys[n] = xf(fr.f[k]), y_of(g)
    else flush() end
  end
  flush()
  -- its scale, at the left-hand edge: the zero and the depth (it steps
  -- 6 / 12 / 24 / 48 dB with what it has to show)
  if opts.label then
    local lx = (opts.lx or xf(20)) + 4
    local lc = U.with_alpha(C.COL.header_dim, 0xc0)
    ImGui.DrawList_AddLine(dl, lx - 4, y1, lx + 4, y1, U.with_alpha(col, 0x80), 1.0)
    small_text(opts.ctx, dl, lx, y0, lc, "0 dB")
    small_text(opts.ctx, dl, lx + 7, y1 - 12, lc, ("\u{2212}%d dB"):format(rng))
  end
end

-- The reduction by frequency in its own view (a compressor canvas's "Hz"):
-- the level going in, a third-octave a bar, and the reduction hanging
-- from the top.
local function draw_fine_view(ctx, dl, gx0, gy0, gw, gh, track, fx)
  local EQP = require("TS_CV_EQPanel")
  local function x_of(f) return EQP.util.x_of(math.max(20, math.min(20000, f)), gx0, gw) end
  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)
  ImGui.DrawList_AddRectFilled(dl, gx0, gy0, gx0 + gw, gy0 + gh, 0x00000030)
  for _, f in ipairs({ 50, 100, 200, 500, 1000, 2000, 5000, 10000 }) do
    local xx = math.floor(x_of(f)) + 0.5
    local major = (f == 100 or f == 1000 or f == 10000)
    ImGui.DrawList_AddLine(dl, xx, gy0, xx, gy0 + gh, U.with_alpha(C.COL.eq_grid, major and 0xc0 or 0x60), 1.0)
    if major then
      small_text(ctx, dl, xx + 3, gy0 + gh - 13, U.with_alpha(C.COL.header_dim, 0xa0), f >= 1000 and (f // 1000) .. "k" or tostring(f))
    end
  end
  local fr, why = CP.fine_frame(track, fx.guid)
  local y0, y1 = gy0 + math.floor(gh * 0.14), gy0 + math.floor(gh * 0.86)
  if fr then
    -- the level going in: bars from the foot, -78 to 0 dBFS up to 0.6 of the height
    local h6 = 2 ^ (1 / 6)
    local bar = U.with_alpha(C.COL.eq_spectrum, 0x48)
    for k = 1, fr.n do
      local l = fr.lv[k]
      if l and l > -78 then
        local a, b = x_of(fr.f[k] / h6), x_of(fr.f[k] * h6)
        local top = gy0 + gh - math.min(1, (l + 78) / 78) * gh * 0.6
        ImGui.DrawList_AddRectFilled(dl, a + 1, top, b - 1, gy0 + gh, bar, 1.5)
      end
    end
    -- the scale, on the right
    for _, part in ipairs({ 0, 0.5, 1 }) do
      local yy = math.floor(y0 + (y1 - y0) * part) + 0.5
      ImGui.DrawList_AddLine(dl, gx0, yy, gx0 + gw, yy, U.with_alpha(C.COL.eq_grid, part == 0 and 0xd0 or 0x70), 1.0)
      local v = fr.range * part
      small_text(ctx, dl, gx0 + gw - 4, yy - 12, U.with_alpha(C.COL.header_dim, 0xc0),
        v == 0 and "0 dB" or ("\u{2212}%g"):format(v), "right")
    end
    CP.fine_curve(dl, fr, x_of, y0, y1)
    small_text(ctx, dl, gx0 + 6, gy0 + 4, C.COL.header_dim, "Reduction by frequency")
    if not fr.cal then
      small_text(ctx, dl, gx0 + 6, gy0 + 16, U.with_alpha(C.COL.header_dim, 0x90), "zero: the music so far (calibrate for a true one)")
    end
  else
    local m1, m2 = CP.fine_why(why)
    small_text(ctx, dl, gx0 + gw * 0.5, gy0 + gh * 0.42, C.COL.header_dim, m1, "centre")
    if m2 then small_text(ctx, dl, gx0 + gw * 0.5, gy0 + gh * 0.42 + 13, C.COL.header_dim, m2, "centre") end
  end
  ImGui.DrawList_PopClipRect(dl)
  -- a hover readout: the band under the mouse
  if fr and ImGui.IsWindowHovered(ctx) then
    local mx, my = ImGui.GetMousePos(ctx)
    if mx >= gx0 and mx < gx0 + gw and my >= gy0 and my < gy0 + gh then
      local best, bd = nil, math.huge
      for k = 1, fr.n do
        local dd = math.abs(x_of(fr.f[k]) - mx)
        if dd < bd then best, bd = k, dd end
      end
      if best then
        local f = fr.f[best]
        local ft = f >= 1000 and ("%.3g kHz"):format(f / 1000) or ("%d Hz"):format(math.floor(f + 0.5))
        local g = fr.g[best]
        ImGui.SetTooltip(ctx, ("%s\n%s\nin %s dBFS"):format(ft,
          g and (g >= 0 and ("reduced %.1f dB"):format(g) or ("lifted %.1f dB"):format(-g)) or "no signal",
          fr.lv[best] and fr.lv[best] > -140 and ("%.0f"):format(fr.lv[best]) or "\u{2013}"))
      end
    end
  end
end

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
  if CP.FINE_ON and ps.fine and TP.fine_ok(track, guid) == true then
    local gr = T.gain_reduction(track, addr) or 0
    draw_fine_view(ctx, dl, gx0, gy0, gw, gh, track, fx)
    local gr_peak, gr_range = W.gr_state(guid, gr, reaper.time_precise(), 12)
    draw_meters(ctx, dl, x + w - mw, y, mw, h, track, fx, gr, enabled, gr_peak, gr_range, true)
    draw_drawer(ctx, dl, gx0, gy0 + gh, gw, dh, track, addr, f, ps, guid)
    return true
  end

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
    W.tip(ctx, id, ("Threshold %s\nDrag: up or down (Shift: fine)"):format(ttxt or ""), hov, act)
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
      W.tip(ctx, id, ("Knee %s\nDrag: away from the threshold to soften"):format(ktxt or ""), hov, act)
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
    W.tip(ctx, id, ("Ratio %s\nDrag: up or down"):format(rlabel), hov, act)
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

  draw_meters(ctx, dl, x + w - mw, y, mw, h, track, fx, gr, enabled, gr_peak, gr_range, true)
  draw_drawer(ctx, dl, gx0, gy0 + gh, gw, dh, track, addr, f, ps, guid)
  return true
end

-- ---------------------------------------------------------------------
-- any plugin as a compressor (a Compressor layout, TS_CV_Mappings Role<name>)
-- ---------------------------------------------------------------------
-- The same canvas, drawn from the roles the layout maps: each piece only
-- when its role is there. Values are the plugin's own text, taken as
-- fact (TS_CV_Units); a role whose text isn't in its unit -- a 1176's
-- attack of 1 to 7, a "Compression" amount -- runs along the control's
-- own range instead. With no threshold there's no transfer curve: the
-- history, the reduction and the envelope only.
local UN = require("TS_CV_Units")

local HOLD_LO, HOLD_HI = 1, 2000
-- the fixed threshold an input-driven compressor is drawn against, dBFS
CP.FIXED_THR = -10

local function mapped(track, addr, p)
  if not p then return nil end
  local nv = reaper.TrackFX_GetParamNormalized(track, addr, p) or 0
  local txt = RC.text(track, addr, p, nv)
  local v, unit = UN.parse(txt)
  return { p = p, n = nv, text = txt, v = v, unit = unit }
end

local pos_cache = {}
local function switch_positions(track, addr, guid, p)
  local k = guid .. ":" .. p
  local c = pos_cache[k]
  -- none (yet): asked again now and then (a plugin read by moving it --
  -- UN.formatter -- isn't read while the transport plays)
  if c == nil or (c == false and (reaper.time_precise() - (pos_cache[k .. "@"] or 0)) > 2) then
    c = UN.positions(UN.formatter(track, addr, p), 200, 12) or false
    pos_cache[k] = c
    if c == false then pos_cache[k .. "@"] = reaper.time_precise() end
  end
  return c or nil
end
-- a switched attack / hold / release, as steps along its scale
local step_cache = {}
local function time_steps(track, addr, guid, p, lo, hi, rev)
  local k = ("%s:%d:%s"):format(guid, p, rev and "r" or "")
  if step_cache[k] == nil then
    step_cache[k] = UN.time_steps(UN.formatter(track, addr, p), lo, hi, rev) or false
  end
  return step_cache[k] or nil
end
function CP.forget_mapped() pos_cache, step_cache = {}, {} end

local function set_to(track, addr, p, target)
  local n = UN.find_norm(UN.formatter(track, addr, p), target)
  if n then set_norm(track, addr, p, n) end
end

-- the envelope for a mapped compressor: attack, hold and release
-- Each time control is drawn where its time puts it on a log scale; a
-- switch snaps to its settings (one reading "Auto" sits beside the
-- others); one that doesn't read in time runs along its range, the other
-- way round when the layout says it's reversed (rev[role]).
local function draw_env_mapped(ctx, dl, px, py, pw, ph, track, addr, R, ps, guid, rev)
  ImGui.DrawList_AddRectFilled(dl, px, py, px + pw, py + ph, U.with_alpha(C.COL.win_bg, 0xc8), 5.0)
  ImGui.DrawList_AddRect(dl, px, py, px + pw, py + ph, C.COL.knob_ring, 5.0, 0, 1.0)
  rev = rev or {}
  local a, hd, r = R.Attack, R.Hold, R.Release
  if a then a.rev = rev.Attack end
  if hd then hd.rev = rev.Hold end
  if r then r.rev = rev.Release end
  local function steps_of(m, lo, hi)
    return time_steps(track, addr, guid, m.p, lo, hi, m.rev)
  end
  local function frac(m, lo, hi)
    if not m then return 0 end
    local st = steps_of(m, lo, hi)
    if st then return UN.step_at(st, m.n).f end
    if m.unit == "ms" and m.v then return RC.time_frac(m.v, lo, hi) end
    return m.rev and (1 - m.n) or m.n
  end
  local gx0, gx1 = px + 10, px + pw - 10
  local base, peak = py + ph - 24, py + 14
  local inner = gx1 - gx0
  local HOLD_W = hd and inner * 0.22 or 0
  local ATK_W = inner * (hd and 0.28 or 0.34)
  local REL_W = inner - ATK_W - HOLD_W - 4
  local on = gx0
  local ak = on + frac(a, ATK_LO, ATK_HI) * ATK_W
  local hk = ak + frac(hd, HOLD_LO, HOLD_HI) * HOLD_W
  local re = hk + frac(r, REL_LO, REL_HI) * REL_W
  ImGui.DrawList_AddLine(dl, gx0, base, gx1, base, U.with_alpha(C.COL.knob_ring, 0xc0), 1.0)
  local xs, ys = { gx0 }, { base }
  for i = 1, 20 do
    local t = i / 20
    xs[#xs + 1] = on + (ak - on) * t
    ys[#ys + 1] = base + (peak - base) * RC.rise(t, 3.2)
  end
  xs[#xs + 1], ys[#ys + 1] = hk, peak
  for i = 1, 26 do
    local t = i / 26
    xs[#xs + 1] = hk + (re - hk) * t
    ys[#ys + 1] = peak + (base - peak) * RC.rise(t, 3.5)
  end
  xs[#xs + 1], ys[#ys + 1] = gx1, base
  local fill = U.with_alpha(C.COL.accent, 0x2e)
  for i = 1, #xs - 1 do
    local y0 = math.min(ys[i], ys[i + 1])
    if xs[i + 1] > xs[i] + 0.01 and y0 < base then
      ImGui.DrawList_AddRectFilled(dl, xs[i], y0, xs[i + 1], base, fill)
    end
  end
  polyline(dl, xs, ys, #xs, C.COL.accent, 2.0)
  local NR = 5
  local function node(key, m, nx, ny, w_px, lo, hi, label)
    if not m then return end
    local id = "mc" .. key .. "##" .. guid
    local hov, act, dragging = handle(ctx, id, nx - NR - 3, ny - NR - 3, (NR + 3) * 2, (NR + 3) * 2)
    if dragging then
      local fr0 = frac(m, lo, hi)
      local fr = math.max(0, math.min(1, drag_real(ctx, ps, id, fr0, 1 / math.max(1, w_px), 0)))
      local st = steps_of(m, lo, hi)
      if st then
        local s_ = UN.step_near(st, fr)
        if s_ and math.abs(s_.norm - m.n) > 1e-6 then set_norm(track, addr, m.p, s_.norm) end
      elseif m.unit == "ms" and m.v then set_to(track, addr, m.p, RC.frac_time(fr, lo, hi))
      else set_norm(track, addr, m.p, m.rev and (1 - fr) or fr) end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    ImGui.DrawList_AddCircleFilled(dl, nx, ny, NR, C.COL.header_text)
    ImGui.DrawList_AddCircle(dl, nx, ny, NR, (hov or act) and C.COL.header_text or C.COL.accent, 0, 1.6)
    W.tip(ctx, id, ("%s %s\nDrag: left or right"):format(label, m.text or ""), hov, act)
  end
  node("atk", a, ak, peak, ATK_W, ATK_LO, ATK_HI, "Attack")
  node("hold", hd, hk, peak, HOLD_W, HOLD_LO, HOLD_HI, "Hold")
  node("rel", r, re, base, REL_W, REL_LO, REL_HI, "Release")
  local ly = py + ph - 15
  if a then small_text(ctx, dl, gx0, ly, C.COL.value, "Atk " .. (a.text or "")) end
  if hd then small_text(ctx, dl, (gx0 + gx1) * 0.5, ly, C.COL.value, "Hold " .. (hd.text or ""), "centre") end
  if r then small_text(ctx, dl, gx1, ly, C.COL.value, "Rel " .. (r.text or ""), "right") end
end

-- A role's ends, as the plugin reads them (cached per instance).
local ends_cache = {}
local function ends_of(track, addr, guid, p)
  local k = guid .. ":" .. p
  local e = ends_cache[k]
  if not e then
    local fmt = UN.formatter(track, addr, p)
    local a, ua = UN.at(fmt, 0)
    local b = UN.at(fmt, 1)
    e = { lo = a and b and math.min(a, b), hi = a and b and math.max(a, b), unit = ua }
    ends_cache[k] = e
  end
  return e
end

-- ---------------------------------------------------------------------
-- a Gate layout and a Limiter layout: the same pieces, other pictures
-- ---------------------------------------------------------------------

-- A role that reads as a plain number running below zero is in dB,
-- whatever its text leaves off (as the compressor's threshold).
local function db_ish(track, addr, guid, m)
  if m and m.unit == "" and m.v then
    local e = ends_of(track, addr, guid, m.p)
    if e.lo and e.lo < 0 then m.unit = "db" end
  end
  return m
end

-- An amount the plugin may write either way round (a range of "80 dB" or
-- "-80 dB" means the same): true when its own values run upwards from 0.
local function positive_amount(track, addr, guid, p)
  local e = ends_of(track, addr, guid, p)
  return (e.lo or 0) >= 0 and (e.hi or 0) > 0
end

-- the canvas's level grid, and the history behind it
local function role_backdrop(ctx, dl, gx0, gy0, gw, gh, track, fx, gr, y_of, guid, lift)
  ImGui.DrawList_AddRectFilled(dl, gx0, gy0, gx0 + gw, gy0 + gh, 0x00000030)
  for g = 0, -96, -12 do
    local yy = math.floor(y_of(g)) + 0.5
    if yy > gy0 + 4 and yy < gy0 + gh - 2 then
      ImGui.DrawList_AddLine(dl, gx0, yy, gx0 + gw, yy, U.with_alpha(C.COL.eq_grid, 0xc0), 1.0)
      small_text(ctx, dl, gx0 + 3, yy - 11, U.with_alpha(C.COL.header_dim, 0xa0), tostring(g))
    end
  end
  local gr_peak, gr_range = W.gr_state(guid, gr, reaper.time_precise(), 12)
  local m1, m2 = draw_history(ctx, dl, gx0, gy0, gw, gh, track, fx, gr, y_of, gr_range, lift)
  if m1 then
    small_text(ctx, dl, gx0 + gw - 4, gy0 + 3, C.COL.header_dim, m1, "right")
    if m2 then small_text(ctx, dl, gx0 + gw - 4, gy0 + 14, C.COL.header_dim, m2, "right") end
  end
  return gr_peak, gr_range
end

-- A horizontal line you drag up or down, across the canvas. `v` its level
-- (dB on the canvas's scale); `on_drag(new_v)` when dragged. Returns
-- hovered, active.
local function level_line(ctx, dl, ps, id, gx0, gw, gy0, gh, span, v, y_of, col, dashed_line, grip_x, tip, on_drag)
  local yy = y_of(v)
  local hov, act, dragging = handle(ctx, id, gx0, yy - 4, gw - 18, 8)
  if dragging then
    local nv = drag_real(ctx, ps, id, v, 0, -span / gh)
    on_drag(nv)
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  elseif hov then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  end
  if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
  if dashed_line then
    dashed(dl, gx0, yy, gx0 + gw, yy, col, 6, 4, 1.3)
  else
    ImGui.DrawList_AddLine(dl, gx0, yy, gx0 + gw, yy, col, 1.6)
  end
  local hot = hov or act
  ImGui.DrawList_AddRectFilled(dl, grip_x - 18, yy - (dashed_line and 3 or 4), grip_x + 18, yy + (dashed_line and 3 or 4),
    hot and C.COL.header_text or col, 4.0)
  W.tip(ctx, id, tip, hov, act)
  return hov, act
end

-- a value in dB from a role: as it reads, or along its range between lo
-- and hi; returns the value and whether it's along the range
local function level_of(m, lo, hi, rev)
  if not m then return nil end
  if m.unit == "db" and m.v and not rev then
    if m.v == -math.huge then return lo, false end
    return m.v, false
  end
  local n = rev and (1 - m.n) or m.n
  return lo + n * (hi - lo), true
end
-- and back: writes `v` (dB) to the role's control
local function set_level(track, addr, m, v, along, lo, hi, rev)
  if along then
    local n = (v - lo) / (hi - lo)
    set_norm(track, addr, m.p, rev and (1 - n) or n)
  else
    set_to(track, addr, m.p, v)
  end
end

-- ---------------------------------------------------------------------
-- the gate
-- ---------------------------------------------------------------------
-- The compressor's picture turned round: input across, output up, 1:1
-- above the threshold, and under it the curve drops away -- straight down
-- for a gate, at the ratio for an expander -- to the range's floor, that
-- many dB under 1:1. The thresholds are horizontal lines, as the
-- compressor's is: it opens at the solid one, and once open stays open
-- down to the dashed Close line (the dashed curve).
local GATE_FULL = -120     -- a range left out, or -inf: shut is silent

-- ---------------------------------------------------------------------
-- An input-driven compressor or limiter: no threshold control, an input
-- gain pushing the signal into a threshold that stays put (a 1176's,
-- fixed; a limiter's, its ceiling). Drawn after the gain: the threshold
-- where it is, and the gain a bar of its own -- where a signal at its
-- 0 dB (Ref0: -18 dBFS unless its layout says) lands once it's through
-- the gain. Raise the bar toward the threshold for more.
-- ---------------------------------------------------------------------
CP.GUESS_SPAN = 48     -- an input that doesn't read in dB: its range, guessed

-- m: the Input role, mapped; line: the threshold after the gain when it's
-- known (a limiter's ceiling), else nil (a compressor's: measured, or
-- guessed). { line, bar, gain, ref, measured, set(bar) }
local function drive_of(track, addr, cv, m, line, kind)
  local ref = M.ref0(cv)
  local rev = cv.rev and cv.rev.Input
  local db = (m.unit == "db" and m.v and m.v > -math.huge and m.v < math.huge and not rev)
  local span = (kind == "limit") and 30 or CP.GUESS_SPAN
  local base = (kind == "limit") and 0 or -0.5          -- along: the gain at the bottom, in spans
  local d = { ref = ref, line = line, measured = false }
  local cal = (kind ~= "limit") and M.thr_cal(cv) or nil
  if cal then
    -- measured: where the threshold falls (dBFS going in) at each input
    -- setting; after the gain, it's where it stays
    local x = cal.n and m.n or m.v
    local t = x and x > -math.huge and x < math.huge and M.thr_dbfs(cv, x)
    if t then
      if cal.n then
        d.line = M.thr_dbfs(cv, 0.5)
      else
        local s, k = 0, 0
        for _, q in ipairs(cal.pts) do s = s + q[1] + q[2]; k = k + 1 end
        d.line = s / k
      end
      d.measured = true
      d.bar = d.line - t + ref
      d.set = function(bar)
        local nx = M.thr_from_dbfs(cv, d.line - bar + ref)
        if not nx then return end
        if cal.n then set_norm(track, addr, m.p, math.max(0, math.min(1, nx)))
        else set_to(track, addr, m.p, nx) end
      end
    end
  end
  if not d.bar then
    d.line = d.line or CP.FIXED_THR
    local n = rev and (1 - m.n) or m.n
    d.bar = ref + (db and m.v or (n + base) * span)
    d.set = function(bar)
      local g = bar - ref
      if db then set_to(track, addr, m.p, g)
      else
        local nn = math.max(0, math.min(1, g / span - base))
        set_norm(track, addr, m.p, rev and (1 - nn) or nn)
      end
    end
  end
  d.gain = d.bar - d.ref
  return d
end

-- the gain's bar: drag it up for more. what: the threshold's name, for
-- its words ("threshold", "ceiling")
local function draw_gain_bar(ctx, dl, ps, id, gx0, gw, gy0, gh, lo, hi, y_of, d, m, what)
  local col = W.gr_fill_col(false, false)
  local v = math.max(lo, math.min(hi, d.bar))
  local yy = y_of(v)
  local hov, act, dragging = handle(ctx, id, gx0, yy - 5, gw - 18, 10)
  if dragging then
    d.set(drag_real(ctx, ps, id, v, 0, -(hi - lo) / gh))
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  elseif hov then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  end
  if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
  ImGui.DrawList_AddLine(dl, gx0, yy, gx0 + gw, yy, col, 1.8)
  local gx = gx0 + gw * 0.45
  ImGui.DrawList_AddRectFilled(dl, gx - 24, yy - 5, gx + 24, yy + 5, (hov or act) and C.COL.header_text or col, 5.0)
  -- its words on the side away from the threshold (whose own go on the
  -- side away from it), so the two never meet
  local over = d.bar - d.line
  local wy = (over > 0 and yy - 33 >= gy0 + 2) and (yy - 33) or (yy + 5)
  ImGui.DrawList_AddText(dl, gx0 + 8, wy, col, "Input " .. (m.text or ("%+.1f dB"):format(d.gain)))
  small_text(ctx, dl, gx0 + 8, wy + 16, U.with_alpha(col, 0xc0),
    ("%.0f dBFS in lands at %.1f  \u{00B7}  %.1f dB %s the %s"):format(d.ref, d.bar, math.abs(over),
      over > 0 and "over" or "under", what))
  W.tip(ctx, id, ("Input %s\nDrag: up for more gain (Shift: fine)\nBar: where %.0f dBFS lands after the gain"):format(m.text or "", d.ref), hov, act)
  return hov, act
end

-- The live dot: where the signal is on the curve right now -- its input
-- level across (raised by lift: drawn after an input's gain), less the
-- reduction, up -- with a short tail.
-- band: a multiband's band shown on this canvas, { lv = its input level,
-- dBFS }: the dot rides the curve at that level (each band's own reduction
-- isn't measured, only the plugin's as a whole)
local function live_dot(dl, ps, track, guid, enabled, gr, x_of, y_of, out, lo, hi, lift, band)
  lift = lift or 0
  local lv = TP.levels(track, guid)
  if band then lv = band.lv and { in_pk = band.lv } or nil end
  ps.trail = ps.trail or {}
  local tr = ps.trail
  if lv and not lv.old and enabled and lv.in_pk and lv.in_pk + lift > lo then
    local ind = math.min(hi, lv.in_pk + lift)
    tr[#tr + 1] = { ind, band and out(ind) or (ind - (gr or 0)) }
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
end

local function draw_gate(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = panel_state(guid)
  local enabled = T.get_enabled(track, addr)
  for _, k in ipairs({ "Threshold", "Close", "Hysteresis", "Range" }) do db_ish(track, addr, guid, R[k]) end
  local rev = cv.rev or {}

  local TOP, BOT = 6, -84
  if R.Threshold and R.Threshold.unit == "db" then
    local e = ends_of(track, addr, guid, R.Threshold.p)
    if e.hi and e.hi < math.huge then TOP = math.max(TOP, e.hi + 3) end
    if e.lo and e.lo > -math.huge then BOT = math.min(BOT, e.lo - 6) end
  end
  local mw = CP.METERS_W
  local gx0, gy0 = x + 1, y
  local gw, gh = w - mw - 1, h
  local span = TOP - BOT
  local function x_of(db) return gx0 + (db - BOT) / span * gw end
  local function y_of(db) return gy0 + (TOP - db) / span * gh end
  local gr = T.gain_reduction(track, addr) or 0

  -- the levels
  local thr, thr_along = level_of(R.Threshold, BOT + 6, TOP - 6, rev.Threshold)
  local close, close_along
  if thr and R.Close then
    close, close_along = level_of(R.Close, BOT + 6, TOP - 6, rev.Close)
  elseif thr and R.Hysteresis then
    local m = R.Hysteresis
    if m.unit == "db" and m.v then
      close = thr - math.abs(m.v)
    else
      close, close_along = thr - (rev.Hysteresis and (1 - m.n) or m.n) * 20, true
    end
  end
  local att, att_along = GATE_FULL, false
  if R.Range then
    local m = R.Range
    if m.unit == "db" and m.v then
      att = (m.v == -math.huge or m.v == math.huge) and GATE_FULL or -math.abs(m.v)
    else
      att, att_along = -(rev.Range and (1 - m.n) or m.n) * 80, true
    end
  end
  -- an expander's ratio reads the same written either way round ("1:4",
  -- "4:1"): the larger. One whose every setting reads under 1:1 is set
  -- that way round too (gflip).
  local function either(v) return (v and v > 0 and v < 1) and (1 / v) or v end
  local gends = R.Ratio and ends_of(track, addr, guid, R.Ratio.p) or {}
  local gflip = gends.hi and gends.hi <= 1 and gends.lo and gends.lo < 1
  local ratio = 1000
  if R.Ratio and R.Ratio.v and either(R.Ratio.v) >= 1 then ratio = either(R.Ratio.v) end
  local function out(db, t)
    if db >= t then return db end
    return math.max(t + (db - t) * ratio, db + att)
  end

  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)
  local gr_peak, gr_range = role_backdrop(ctx, dl, gx0, gy0, gw, gh, track, fx, gr, y_of, guid)
  dashed(dl, x_of(BOT), y_of(BOT), x_of(TOP), y_of(TOP), U.with_alpha(C.COL.label, 0x70), 3, 4, 1.0)
  if thr then
    local function curve(t, col, thick, dash)
      -- the corners exactly (the threshold, and where the drop meets the
      -- floor), between even steps
      local dbs = {}
      for i = 0, 200 do dbs[#dbs + 1] = BOT + span * i / 200 end
      dbs[#dbs + 1] = t
      if ratio > 1.001 then dbs[#dbs + 1] = t + att / (ratio - 1) end
      table.sort(dbs)
      local xs, ys, n = {}, {}, 0
      for _, db in ipairs(dbs) do
        if db >= BOT and db <= TOP and (not dash or db <= thr) then
          n = n + 1; xs[n], ys[n] = x_of(db), y_of(out(db, t))
        end
      end
      if dash then
        for i = 1, n - 1, 2 do ImGui.DrawList_AddLine(dl, xs[i], ys[i], xs[i + 1], ys[i + 1], col, thick) end
      else
        polyline(dl, xs, ys, n, col, thick)
      end
    end
    if close and close < thr then curve(close, U.with_alpha(C.COL.fader_cap, 0x70), 1.4, true) end
    curve(thr, C.COL.fader_cap, 2.2)
    -- the range's floor, under 1:1
    dashed(dl, x_of(BOT), y_of(BOT + att), x_of(thr), y_of(thr + att), U.with_alpha(C.COL.accent, 0x90), 2, 3, 1.0)
    live_dot(dl, ps, track, guid, enabled, gr, x_of, y_of, function(db) return out(db, thr) end, BOT, TOP)
  else
    small_text(ctx, dl, gx0 + gw * 0.5, gy0 + gh * 0.42, U.with_alpha(C.COL.header_dim, 0xa0),
      "no threshold: no curve", "centre")
  end
  ImGui.DrawList_PopClipRect(dl)

  if thr then
    -- the threshold it opens at
    local lo, hi = BOT + 6, TOP - 6
    level_line(ctx, dl, ps, "mgthr##" .. guid, gx0, gw, gy0, gh, span, thr, y_of, C.COL.accent, false,
      gx0 + gw - 40, ("Opens at %s\nDrag: up or down (Shift: fine)"):format(R.Threshold.text or ""),
      function(v) set_level(track, addr, R.Threshold, math.max(BOT, math.min(TOP, v)), thr_along, lo, hi, rev.Threshold) end)
    -- its value on the left, where the curve leaves room (as the compressor's)
    ImGui.DrawList_AddText(dl, gx0 + 8, y_of(thr) - 17, C.COL.value, R.Threshold.text or "")
    small_text(ctx, dl, gx0 + 8, y_of(thr) + 3, C.COL.header_dim, "Opens")
    -- where it closes
    if close then
      local m = R.Close or R.Hysteresis
      level_line(ctx, dl, ps, "mgcls##" .. guid, gx0, gw, gy0, gh, span, close, y_of, U.with_alpha(C.COL.accent, 0xc0), true,
        gx0 + gw - 40, ("Closes at %s\nDrag: up or down (Shift: fine)"):format(R.Close and (m.text or "")
          or (("%.1f dB (hysteresis %s)"):format(close, m.text or ""))),
        function(v)
          v = math.min(thr, v)
          if R.Close then
            set_level(track, addr, m, math.max(BOT, v), close_along, lo, hi, rev.Close)
          elseif m.unit == "db" and m.v then
            local amt = thr - v
            set_to(track, addr, m.p, positive_amount(track, addr, guid, m.p) and amt or -amt)
          else
            local n = math.max(0, math.min(1, (thr - v) / 20))
            set_norm(track, addr, m.p, rev.Hysteresis and (1 - n) or n)
          end
        end)
      small_text(ctx, dl, gx0 + 8, y_of(close) + 3, C.COL.header_dim,
        R.Close and ("Closes " .. (m.text or "")) or ("Closes  (hysteresis " .. (m.text or "") .. ")"))
    end

    -- an expander's ratio: a node on the slope
    if R.Ratio then
      -- on the slope; a gate's drop is straight down, so its node sits on
      -- that line, as far down as a steep ratio would put it
      local rd = math.min(ratio, 12)
      local d = (rd > 1.01) and math.max(1.5, math.min(8, (-att) / (rd - 1) * 0.5)) or 8
      local rx, ry = x_of(thr - d), y_of(math.max(thr - d * rd, thr - d + att))
      if ratio >= 999 then rx = x_of(thr) - 1 end
      local id = "mgrat##" .. guid
      local hov, act, dragging = handle(ctx, id, rx - 7, ry - 7, 14, 14)
      if dragging then
        local v = drag_real(ctx, ps, id, thr - d * rd, 0, -span / gh)
        local r = math.max(1, (thr - v) / d)
        local sw = switch_positions(track, addr, guid, R.Ratio.p)
        if sw then
          -- a setting that isn't a ratio ("Gate") is one step past the
          -- steepest, so it can be reached
          local top = 1
          for _, s_ in ipairs(sw) do
            local sv = either(UN.parse(s_.text))
            if sv and sv >= 1 and sv < 1000 then top = math.max(top, sv) end
          end
          local best, bd = nil, math.huge
          for _, s_ in ipairs(sw) do
            local sv = either(UN.parse(s_.text))
            if not (sv and sv >= 1) then sv = top * 2.5 end
            local dd = math.abs(math.log(sv) - math.log(r))
            if dd < bd then best, bd = s_.norm, dd end
          end
          if best and math.abs(best - R.Ratio.n) > 1e-6 then set_norm(track, addr, R.Ratio.p, best) end
        else
          set_to(track, addr, R.Ratio.p, gflip and (1 / math.min(100, r)) or math.min(100, r))
        end
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
      end
      if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
      ImGui.DrawList_AddCircleFilled(dl, rx, ry, 5, (hov or act) and C.COL.header_text or C.COL.fader_cap)
      small_text(ctx, dl, rx - 9, ry - 6, C.COL.value, "Ratio " .. (R.Ratio.text or ""), "right")
      W.tip(ctx, id, ("Ratio %s\nDrag: up or down"):format(R.Ratio.text or ""), hov, act)
    end

    -- the range: a node on the floor (at the foot when the floor is
    -- under the canvas)
    if R.Range then
      local xj = (ratio > 1.01) and (thr + att / (ratio - 1)) or thr
      local nxdb = math.max(BOT + 3, xj - 6)
      local ny = y_of(nxdb + att)
      local below = ny > gy0 + gh - 8
      if below then ny = gy0 + gh - 8 end
      local nx = x_of(nxdb)
      local id = "mgrng##" .. guid
      local hov, act, dragging = handle(ctx, id, nx - 7, ny - 7, 14, 14)
      if dragging then
        local v = math.max(GATE_FULL, math.min(0, drag_real(ctx, ps, id, att, 0, -span / gh)))
        if att_along then
          local n = math.min(1, -v / 80)
          set_norm(track, addr, R.Range.p, rev.Range and (1 - n) or n)
        else
          set_to(track, addr, R.Range.p, positive_amount(track, addr, guid, R.Range.p) and -v or v)
        end
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
      end
      if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
      ImGui.DrawList_AddCircleFilled(dl, nx, ny, 5, (hov or act) and C.COL.header_text or C.COL.fader_cap)
      ImGui.DrawList_AddCircle(dl, nx, ny, 5, C.COL.accent, 0, 1.4)
      small_text(ctx, dl, nx + 9, ny - 6, C.COL.value, "Range " .. (R.Range.text or "") .. (below and "  \u{2193}" or ""))
      W.tip(ctx, id, ("Range %s: depth when shut\nDrag: up or down"):format(R.Range.text or ""),
        hov, act)
    end

    -- open or shut, from the track's level (with the hysteresis)
    local lv = TP.levels(track, guid)
    if lv and not lv.old and lv.in_pk then
      if lv.in_pk >= thr then ps.gate_open = true
      elseif lv.in_pk < (close or thr) then ps.gate_open = false end
      local open = enabled and ps.gate_open
      local lx, ly = gx0 + gw - 52, gy0 + gh - 18
      ImGui.DrawList_AddCircleFilled(dl, lx, ly + 5, 4.5, open and C.COL.accent or U.with_alpha(C.COL.header_dim, 0x80))
      small_text(ctx, dl, lx + 9, ly, open and C.COL.value or C.COL.header_dim, open and "open" or "shut")
    end
  end

  -- the envelope, top left: above 1:1, where a gate's curve never goes
  local ph, ew = 82, 196
  if (R.Attack or R.Hold or R.Release) and gh > ph + 120 and gw > ew + 60 then
    draw_env_mapped(ctx, dl, gx0 + 8, gy0 + 8, ew, ph, track, addr, R, ps, guid, cv.rev)
  end
  draw_meters(ctx, dl, x + w - mw, y, mw, h, track, fx, gr, enabled, gr_peak, gr_range, true)
  return true
end

-- ---------------------------------------------------------------------
-- the limiter
-- ---------------------------------------------------------------------
-- No curve to speak of: a limiter is all ceiling. Its level over the
-- last few seconds instead, as the compressor's canvas has behind its
-- curve -- the input, what came out, the reduction hanging from the top
-- -- with the threshold and the ceiling across it. A limiter with a gain
-- control instead of a threshold pushes the signal into the ceiling,
-- which is the same as the threshold coming down: drawn so.
local function draw_limiter(ctx, dl, x, y, w, h, track, fx, req, cv, R)
  local addr, guid = fx.addr, fx.guid
  local ps = panel_state(guid)
  local enabled = T.get_enabled(track, addr)
  for _, k in ipairs({ "Threshold", "Input", "Ceiling" }) do db_ish(track, addr, guid, R[k]) end
  local rev = cv.rev or {}

  local ceil, ceil_along = 0, false
  if R.Ceiling then ceil, ceil_along = level_of(R.Ceiling, -12, 0, rev.Ceiling) end
  local via_in = (R.Threshold == nil) and (R.Input ~= nil)
  local thr, thr_along
  if R.Threshold then
    thr, thr_along = level_of(R.Threshold, -30, 0, rev.Threshold)
  end
  -- a gain into the ceiling (no threshold): drawn after the gain, the
  -- ceiling its threshold and the gain a bar of its own (drive_of)
  local drive = via_in and drive_of(track, addr, cv, R.Input, ceil, "limit") or nil

  local TOP = math.max(3, ceil + 3)
  local BOT = drive and math.max(-72, math.min(-30, ceil - 36))
              or math.max(-72, math.min(-30, (thr or -12) - 18))
  local mw = CP.METERS_W
  local gx0, gy0 = x + 1, y
  local gw, gh = w - mw - 1, h
  local span = TOP - BOT
  local function y_of(db) return gy0 + (TOP - db) / span * gh end
  local gr = T.gain_reduction(track, addr) or 0

  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)
  local gr_peak, gr_range = role_backdrop(ctx, dl, gx0, gy0, gw, gh, track, fx, gr, y_of, guid, drive and drive.gain)
  ImGui.DrawList_PopClipRect(dl)

  -- the ceiling
  local clip = C.COL.level_clip or C.COL.warn
  if R.Ceiling then
    level_line(ctx, dl, ps, "mlcl##" .. guid, gx0, gw, gy0, gh, span, ceil, y_of, clip, true, gx0 + gw - 40,
      ("Ceiling %s\nDrag: up or down (Shift: fine)"):format(R.Ceiling.text or ""),
      function(v) set_level(track, addr, R.Ceiling, math.min(TOP, v), ceil_along, -12, 0, rev.Ceiling) end)
  else
    dashed(dl, gx0, y_of(ceil), gx0 + gw, y_of(ceil), U.with_alpha(clip, 0x90), 6, 4, 1.0)
  end
  small_text(ctx, dl, gx0 + 8, y_of(ceil) + 3, clip, "Ceiling " .. (R.Ceiling and (R.Ceiling.text or "") or "0 dB"))

  -- the threshold; or, with none, the input's gain: its bar
  if drive then
    draw_gain_bar(ctx, dl, ps, "mlgain##" .. guid, gx0, gw, gy0, gh, BOT, TOP, y_of, drive, R.Input, "ceiling")
  elseif thr then
    local m = R.Threshold
    level_line(ctx, dl, ps, "mlth##" .. guid, gx0, gw, gy0, gh, span, thr, y_of, C.COL.accent, false, gx0 + gw - 40,
      ("Threshold %s\nDrag: up or down (Shift: fine)"):format(m.text or ""),
      function(v)
        v = math.max(BOT, math.min(ceil, v))
        set_level(track, addr, m, v, thr_along, -30, 0, rev.Threshold)
      end)
    ImGui.DrawList_AddText(dl, gx0 + 8, y_of(thr) - 17, C.COL.value, m.text or "")
    small_text(ctx, dl, gx0 + 8, y_of(thr) + 3, C.COL.header_dim,
      ("Threshold  \u{00B7}  gain %+.1f dB"):format(ceil - thr))
  end

  -- the release: a slider at the foot, on the envelope's time scale
  if R.Release then
    local m = R.Release
    m.rev = rev.Release
    local st = time_steps(track, addr, guid, m.p, REL_LO, REL_HI, m.rev)
    local function frac()
      if st then return UN.step_at(st, m.n).f end
      if m.unit == "ms" and m.v then return RC.time_frac(m.v, REL_LO, REL_HI) end
      return m.rev and (1 - m.n) or m.n
    end
    local bx, bw_, bh = gx0 + 8, 176, 44
    local by = gy0 + gh - bh - 8
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw_, by + bh, U.with_alpha(C.COL.win_bg, 0xc8), 5.0)
    ImGui.DrawList_AddRect(dl, bx, by, bx + bw_, by + bh, C.COL.knob_ring, 5.0, 0, 1.0)
    small_text(ctx, dl, bx + 8, by + 5, C.COL.header_dim, "Release")
    small_text(ctx, dl, bx + bw_ - 8, by + 5, C.COL.value, m.text or "", "right")
    local tx0, tx1, ty = bx + 10, bx + bw_ - 10, by + bh - 13
    local f = frac()
    ImGui.DrawList_AddLine(dl, tx0, ty, tx1, ty, C.COL.knob_ring, 4.0)
    ImGui.DrawList_AddLine(dl, tx0, ty, tx0 + (tx1 - tx0) * f, ty, C.COL.accent, 4.0)
    if st then
      for _, s_ in ipairs(st) do
        local sx = tx0 + (tx1 - tx0) * s_.f
        ImGui.DrawList_AddLine(dl, sx, ty + 4, sx, ty + 7, C.COL.header_dim, 1.0)
      end
    end
    local nx = tx0 + (tx1 - tx0) * f
    local id = "mlrel##" .. guid
    local hov, act, dragging = handle(ctx, id, tx0 - 6, ty - 8, tx1 - tx0 + 12, 16)
    if dragging then
      local fr = math.max(0, math.min(1, drag_real(ctx, ps, id, f, 1 / (tx1 - tx0), 0)))
      if st then
        local s_ = UN.step_near(st, fr)
        if s_ and math.abs(s_.norm - m.n) > 1e-6 then set_norm(track, addr, m.p, s_.norm) end
      elseif m.unit == "ms" and m.v then set_to(track, addr, m.p, RC.frac_time(fr, REL_LO, REL_HI))
      else set_norm(track, addr, m.p, m.rev and (1 - fr) or fr) end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    ImGui.DrawList_AddCircleFilled(dl, nx, ty, 5, C.COL.header_text)
    ImGui.DrawList_AddCircle(dl, nx, ty, 5, (hov or act) and C.COL.header_text or C.COL.accent, 0, 1.6)
    W.tip(ctx, id, ("Release %s\nDrag: left or right"):format(m.text or ""), hov, act)
  end

  draw_meters(ctx, dl, x + w - mw, y, mw, h, track, fx, gr, enabled, gr_peak, gr_range, true)
  return true
end

function CP.draw_mapped(ctx, dl, x, y, w, h, track, fx, req, cv)
  local roles = cv.roles or {}
  if not next(roles) then return false end
  local addr, guid = fx.addr, fx.guid
  local ps = panel_state(guid)
  if w < 120 or h < 80 then return true end
  local enabled = T.get_enabled(track, addr)
  if CP.FINE_ON and ps.fine and TP.fine_ok(track, guid) == true then
    local mw = CP.METERS_W
    local gr = T.gain_reduction(track, addr) or 0
    draw_fine_view(ctx, dl, x + 1, y, w - mw - 1, h, track, fx)
    local gr_peak, gr_range = W.gr_state(guid, gr, reaper.time_precise(), 12)
    draw_meters(ctx, dl, x + w - mw, y, mw, h, track, fx, gr, enabled, gr_peak, gr_range, true)
    return true
  end
  local R = {}
  for name, p in pairs(roles) do R[name] = mapped(track, addr, p) end
  if cv.kind == "gate" then return draw_gate(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  if cv.kind == "limit" then return draw_limiter(ctx, dl, x, y, w, h, track, fx, req, cv, R) end
  -- a threshold, knee or make-up that reads as a plain number running
  -- below zero is in dB, whatever its text leaves off
  for _, name in ipairs({ "Threshold", "Knee", "Makeup", "Input" }) do
    local m = R[name]
    if m and m.unit == "" and m.v then
      local e = ends_of(track, addr, guid, m.p)
      if e.lo and e.lo < 0 then m.unit = "db" end
    end
  end
  -- the level scale: wide enough for the whole of the threshold's range
  -- A compressor driven by its input (1176-style, no threshold control):
  -- drawn after its input's gain, the threshold fixed and the gain a bar
  -- of its own (drive_of)
  local via_in = (R.Threshold == nil) and (R.Input ~= nil)
  local rev = (not via_in) and (cv.rev and cv.rev.Threshold) or false
  local thr_name = via_in and "Threshold" or (rev and "Compression" or "Threshold")
  local DB_TOP, DB_BOT = DB_TOP, DB_BOT
  local tsrc = R.Threshold or R.Input
  local drive = via_in and drive_of(track, addr, cv, R.Input, nil, "comp") or nil
  -- measured: where its threshold really is, in dBFS (its own dB is often
  -- some calibrated level of its own -- an SSL's, an API's)
  local cal = M.thr_cal(cv)
  if drive then
    DB_TOP = math.max(DB_TOP, math.min(24, drive.line + 12))
    DB_BOT = math.min(DB_BOT, math.max(-96, drive.line - 50))
  elseif cal then
    local xa, xb
    if cal.n then xa, xb = 0, 1
    else local e = ends_of(track, addr, guid, tsrc.p); xa, xb = e.lo, e.hi end
    local a = xa and xa > -math.huge and M.thr_dbfs(cv, xa)
    local b = xb and xb < math.huge and M.thr_dbfs(cv, xb)
    if a and b then
      DB_TOP = math.max(DB_TOP, math.min(24, math.max(a, b) + 3))
      DB_BOT = math.min(DB_BOT, math.max(-96, math.min(a, b) - 6))
    end
  elseif tsrc and tsrc.unit == "db" and not rev then
    local e = ends_of(track, addr, guid, tsrc.p)
    local lo, hi = e.lo, e.hi
    if hi and hi > -math.huge and hi < math.huge then DB_TOP = math.max(DB_TOP, hi + 3) end
    if lo and lo > -math.huge and lo < math.huge then DB_BOT = math.min(DB_BOT, lo - 6) end
  end

  local mw = CP.METERS_W
  local gx0, gy0 = x + 1, y
  local gw, gh = w - mw - 1, h
  local gr = T.gain_reduction(track, addr) or 0

  local function x_of(db) return gx0 + (db - DB_BOT) / (DB_TOP - DB_BOT) * gw end
  local function y_of(db) return gy0 + (DB_TOP - db) / (DB_TOP - DB_BOT) * gh end

  -- the threshold in dB: as the plugin says, or along the control's range
  -- (reversed: more compression is a lower line)
  local T_ = tsrc
  local thr, thr_pos, thr_cal
  if drive then
    thr, thr_cal = drive.line, drive.measured
  elseif T_ and cal then
    local x = cal.n and T_.n or ((T_.unit == "db") and T_.v or nil)
    if x and x > -math.huge and x < math.huge then thr = M.thr_dbfs(cv, x) end
    thr_cal = thr ~= nil
  end
  if T_ and not thr then
    if T_.unit == "db" and T_.v and not rev then
      thr = (T_.v == -math.huge) and DB_BOT or T_.v
    else
      thr_pos = true
      local n = rev and (1 - T_.n) or T_.n
      thr = DB_BOT + 6 + n * (DB_TOP - DB_BOT - 12)
    end
  end
  local ratio = 4
  -- a ratio control whose every setting reads under 1:1 writes its
  -- compression the other way round ("1:4"): turned round (rflip)
  local rends = R.Ratio and ends_of(track, addr, guid, R.Ratio.p) or {}
  local rflip = R.Ratio and R.Ratio.unit == "ratio" and rends.hi and rends.hi <= 1 and rends.lo and rends.lo < 1
  local function rv_of(v) return (rflip and v and v > 0) and (1 / v) or v end
  if R.Ratio and R.Ratio.unit == "ratio" and R.Ratio.v and R.Ratio.v > 0 then ratio = rv_of(R.Ratio.v)
  elseif R.Ratio and R.Ratio.v and R.Ratio.v >= 1 then ratio = R.Ratio.v
  elseif R.Ratio and not R.Ratio.v then ratio = 1000 end
  -- the knee, dB wide: as it reads; or, a knee that reads as a share of
  -- its range (0..1, %), that share of twice the threshold's distance from
  -- 0 dBFS (all of it: from 0 dBFS down to twice the threshold, as a
  -- Weiss's)
  local knee, knee_share = 0, nil
  if R.Knee and thr then
    local m = R.Knee
    local e = ends_of(track, addr, guid, m.p)
    local as_db = m.unit == "db" or (m.unit == "" and e.hi and e.hi > 1.5 and e.hi < math.huge and m.unit ~= "pct")
    if as_db and m.v and m.v > -math.huge then
      knee = math.max(0, math.min(60, m.v))
    else
      knee_share = 2 * math.max(6, math.abs(math.min(0, thr)))
      knee = math.min(60, ((cv.rev and cv.rev.Knee) and (1 - m.n) or m.n) * knee_share)
    end
  end
  local function out(db) return RC.transfer(db, thr, ratio, knee) end

  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)
  ImGui.DrawList_AddRectFilled(dl, gx0, gy0, gx0 + gw, gy0 + gh, 0x00000030)
  for _, g in ipairs({ 0, -12, -24, -36, -48 }) do
    local yy = math.floor(y_of(g)) + 0.5
    ImGui.DrawList_AddLine(dl, gx0, yy, gx0 + gw, yy, U.with_alpha(C.COL.eq_grid, 0xc0), 1.0)
    small_text(ctx, dl, gx0 + 3, yy - 11, U.with_alpha(C.COL.header_dim, 0xa0), tostring(g))
  end
  local gr_peak, gr_range = W.gr_state(guid, gr, reaper.time_precise(), 12)
  local m1, m2 = draw_history(ctx, dl, gx0, gy0, gw, gh, track, fx, gr, y_of, gr_range, drive and drive.gain)
  if m1 then
    small_text(ctx, dl, gx0 + gw - 4, gy0 + 3, C.COL.header_dim, m1, "right")
    if m2 then small_text(ctx, dl, gx0 + gw - 4, gy0 + 14, C.COL.header_dim, m2, "right") end
  end

  if thr then
    local ty = y_of(thr)
    if knee > 0 then
      local mid, clear = U.with_alpha(C.COL.accent, 0x80), U.with_alpha(C.COL.accent, 0)
      vgrad(dl, gx0, y_of(thr + knee * 0.5), gx0 + gw, ty, clear, mid)
      vgrad(dl, gx0, ty, gx0 + gw, y_of(thr - knee * 0.5), mid, clear)
    end
    if drive then
      -- fixed: dashed, nothing to hold
      dashed(dl, gx0, ty, gx0 + gw, ty, C.COL.accent, 7, 4, 1.4)
    else
      ImGui.DrawList_AddLine(dl, gx0, ty, gx0 + gw, ty, C.COL.accent, 1.6)
    end
    local k0 = thr - knee * 0.5
    dashed(dl, x_of(k0), y_of(k0), x_of(DB_TOP), y_of(DB_TOP), U.with_alpha(C.COL.label, 0xa0), 3, 4, 1.0)
    local xs, ys, n = {}, {}, 0
    for i = 0, 160 do
      local db = DB_BOT + (DB_TOP - DB_BOT) * i / 160
      n = n + 1; xs[n], ys[n] = x_of(db), y_of(out(db))
    end
    polyline(dl, xs, ys, n, C.COL.fader_cap, 2.2)
    live_dot(dl, ps, track, guid, enabled, gr, x_of, y_of, out, DB_BOT, DB_TOP, drive and drive.gain, cv.band)
    -- a fixed threshold's words: on the side away from the gain's bar
    local wy = (drive and drive.bar > thr) and (ty + 3) or (ty - 17)
    ImGui.DrawList_AddText(dl, gx0 + 8, wy, C.COL.value,
      drive and ("%.1f dBFS"):format(thr) or (T_.text or ""))
    local sub = thr_name
    if drive then
      sub = drive.measured and "Threshold  \u{00B7}  fixed (measured), after the input's gain"
        or "Threshold  \u{00B7}  fixed, guessed: Set up \u{25B8} Measure threshold"
      small_text(ctx, dl, gx0 + gw - 8, wy + 4, C.COL.header_dim, sub, "right")
      sub = nil
    elseif thr_cal then sub = ("%s  \u{00B7}  %.1f dBFS (measured)"):format(thr_name, thr)
    elseif R.Threshold and T_.unit == "db" and not rev then
      -- a threshold that goes well over 0 dB is likely its own dB
      local e = ends_of(track, addr, guid, T_.p)
      if e.hi and e.hi > 3 and e.hi < math.huge then
        sub = thr_name .. "  \u{00B7}  its dB may not be dBFS: Set up \u{25B8} Measure threshold"
      end
    end
    if sub then small_text(ctx, dl, gx0 + 8, ty + 3, C.COL.header_dim, sub) end
  else
    small_text(ctx, dl, gx0 + gw * 0.5, gy0 + gh * 0.42, U.with_alpha(C.COL.header_dim, 0xa0),
      "no threshold: no transfer curve", "centre")
  end
  ImGui.DrawList_PopClipRect(dl)

  -- an input driving it: its gain's bar (the threshold has no handle)
  if drive then
    draw_gain_bar(ctx, dl, ps, "mcgain##" .. guid, gx0, gw, gy0, gh, DB_BOT, DB_TOP, y_of, drive, R.Input, "threshold")
  end

  -- the threshold's handle: the whole line
  if thr and not drive then
    local ty = y_of(thr)
    local id = "mcthr##" .. guid
    local hov, act, dragging = handle(ctx, id, gx0, ty - 4, gw - 18, 8)
    if dragging and thr_cal then
      local v = drag_real(ctx, ps, id, thr, 0, -(DB_TOP - DB_BOT) / gh)
      local x = M.thr_from_dbfs(cv, v)
      if x then
        if cal.n then set_norm(track, addr, T_.p, x) else set_to(track, addr, T_.p, x) end
      end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    elseif dragging then
      if thr_pos then
        local per = 1 / (gh * (DB_TOP - DB_BOT - 12) / (DB_TOP - DB_BOT))
        local v = drag_real(ctx, ps, id, T_.n, 0, rev and per or -per)
        set_norm(track, addr, T_.p, math.max(0, math.min(1, v)))
      else
        local v = drag_real(ctx, ps, id, thr, 0, -(DB_TOP - DB_BOT) / gh)
        set_to(track, addr, T_.p, v)
      end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    elseif hov then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    local kx = x_of(thr)
    ImGui.DrawList_AddRectFilled(dl, kx - 20, ty - 4, kx + 20, ty + 4,
      (hov or act) and C.COL.header_text or C.COL.accent, 4.0)
    W.tip(ctx, id, ("%s %s\nDrag: up or down (Shift: fine)"):format(thr_name, T_.text or ""), hov, act)
  end

  -- the knee: grips on the band's edges, dragged away from the threshold
  -- to soften it
  if R.Knee and thr then
    local m = R.Knee
    local dbpp = (DB_TOP - DB_BOT) / gh
    local gxk = math.max(gx0 + 70, x_of(thr) - 80)
    for s = 1, 2 do
      local edge = (s == 1) and (thr + knee * 0.5) or (thr - knee * 0.5)
      local ey_ = y_of(edge) + ((s == 1) and -3 or 3)
      local id = "mcknee" .. s .. "##" .. guid
      local hov, act, dragging = handle(ctx, id, gxk - 2, ey_ - 4, 18, 8)
      if dragging then
        local v = math.max(0, drag_real(ctx, ps, id, knee, 0, ((s == 1) and -1 or 1) * 2 * dbpp))
        if knee_share then
          local n = math.max(0, math.min(1, v / knee_share))
          set_norm(track, addr, m.p, (cv.rev and cv.rev.Knee) and (1 - n) or n)
        else
          set_to(track, addr, m.p, v)
        end
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
      elseif hov then
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
      end
      if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
      ImGui.DrawList_AddRectFilled(dl, gxk, ey_ - 2, gxk + 14, ey_ + 2,
        (hov or act) and C.COL.header_text or U.with_alpha(C.COL.accent, 0xd8), 2.0)
      W.tip(ctx, id, ("Knee %s (%.1f dB wide)\nDrag: away from the threshold to soften"):format(m.text or "", knee), hov, act)
      if s == 1 then
        small_text(ctx, dl, gxk - 5, ey_ - 6, C.COL.label, "Knee " .. (m.text or ""), "right")
      end
    end
  end

  -- the ratio: the curve's end, dragged where you want it (an expander's,
  -- under 1:1, leaves through the top: its end is where it does); a switch
  -- snaps to its positions (a position that isn't a ratio, such as a
  -- limit setting, is the far end)
  if R.Ratio and thr then
    local sw = switch_positions(track, addr, guid, R.Ratio.p)
    local ex, ey = gx0 + gw - 7, y_of(out(DB_TOP))
    if out(DB_TOP) > DB_TOP and ratio > 0 then
      -- where it leaves the top
      ex = math.max(gx0 + 7, math.min(gx0 + gw - 7, x_of(thr + (DB_TOP - thr) * ratio)))
      ey = gy0 + 7
    end
    local id = "mcratio##" .. guid
    local hov, act, dragging = handle(ctx, id, ex - 7, ey - 7, 14, 14)
    if dragging then
      -- the ratio the pointer makes with the corner: across over up
      local mx_, my_ = ImGui.GetMousePos(ctx)
      local xdb = DB_BOT + (math.min(gx0 + gw, mx_) - gx0) / gw * (DB_TOP - DB_BOT)
      local ydb = DB_TOP - (my_ - gy0) / gh * (DB_TOP - DB_BOT)
      -- the control's own range, as drawn (turned round when it's written
      -- the other way)
      local lo_, hi_ = rv_of(rends.lo), rv_of(rends.hi)
      if lo_ and hi_ and lo_ > hi_ then lo_, hi_ = hi_, lo_ end
      local rlo = (lo_ and lo_ > 0) and lo_ or 1
      local rhi = (hi_ and hi_ > rlo) and hi_ or 100
      if xdb - thr > 0.5 then
        local r = (ydb - thr > 0.05) and ((xdb - thr) / (ydb - thr)) or math.huge
        if sw then
          local best, bd = nil, math.huge
          for _, ps_ in ipairs(sw) do
            local v = rv_of(UN.parse(ps_.text))
            if not (v and v > 0) or v == math.huge then v = 1000 end
            local dd = math.abs(math.log(v) - math.log(math.max(0.05, math.min(1000, r))))
            if dd < bd then best, bd = ps_.norm, dd end
          end
          if best and math.abs(best - R.Ratio.n) > 1e-6 then set_norm(track, addr, R.Ratio.p, best) end
        elseif r >= math.min(rhi, 100) and rhi == math.huge then
          -- past what a number says: the end that reads infinite
          local fmt = UN.formatter(track, addr, R.Ratio.p)
          local top = UN.at(fmt, 1)
          set_norm(track, addr, R.Ratio.p, (rv_of(top) == math.huge) and 1 or 0)
        else
          local want = math.max(rlo, math.min(math.min(rhi, 100), r))
          set_to(track, addr, R.Ratio.p, rflip and (1 / want) or want)
        end
      end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    elseif hov then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    end
    if not act and ps.drag and ps.drag.id == id then ps.drag = nil end
    ImGui.DrawList_AddCircleFilled(dl, ex, ey, 5, (hov or act) and C.COL.header_text or C.COL.fader_cap)
    -- the plugin's own words: "4.72:1", "1:5" spaced out; a bare number
    -- gets its ": 1"
    local rl = R.Ratio.text or ""
    if rl:find(":") then rl = rl:gsub("%s*:%s*", " : ")
    elseif R.Ratio.unit == "ratio" or (R.Ratio.v and R.Ratio.v >= 1) then rl = rl .. " : 1" end
    local rw = ImGui.CalcTextSize(ctx, rl)
    -- (at the top edge, an expander's: its words below, inside)
    local ly = (ey < gy0 + 24) and (ey + 6) or (ey - 19)
    ImGui.DrawList_AddText(dl, ex - 10 - rw, ly, C.COL.value, rl)
    small_text(ctx, dl, ex - 10, ly + 25, C.COL.header_dim, "Ratio", "right")
    W.tip(ctx, id, ("Ratio %s\nDrag: up or down%s"):format(R.Ratio.text or "",
      sw and " (steps through its settings)" or ""), hov, act)
  elseif R.Ratio then
    small_text(ctx, dl, gx0 + gw - 8, gy0 + 22, C.COL.value, "Ratio " .. (R.Ratio.text or ""), "right")
  end

  -- the envelope, and make-up and mix
  local ph, ow, ew = 82, 104, 196
  local py = gy0 + gh - ph - 8
  local ox = gx0 + gw - 8 - ow
  local exl = ox - 8 - ew
  if (R.Attack or R.Hold or R.Release) and py > gy0 + 30 and exl > gx0 + 4 then
    draw_env_mapped(ctx, dl, exl, py, ew, ph, track, addr, R, ps, guid, cv.rev)
  end
  if (R.Makeup or R.Mix) and py > gy0 + 30 then
    ImGui.DrawList_AddRectFilled(dl, ox, py, ox + ow, py + ph, U.with_alpha(C.COL.win_bg, 0xc8), 5.0)
    ImGui.DrawList_AddRect(dl, ox, py, ox + ow, py + ph, C.COL.knob_ring, 5.0, 0, 1.0)
    if R.Makeup then mini_knob(ctx, dl, "mcmk##" .. guid, ox + 26, py + 22, 10, track, addr, R.Makeup.p, "Make-up", ps) end
    if R.Mix then mini_knob(ctx, dl, "mcmix##" .. guid, ox + ow - 26, py + 22, 10, track, addr, R.Mix.p, "Mix", ps) end
  end

  draw_meters(ctx, dl, x + w - mw, y, mw, h, track, fx, gr, enabled, gr_peak, gr_range, true)
  return true
end

-- The pieces, for the other role canvases (TS_CV_RolePanel: de-esser,
-- delay, reverb, envelope, modulation), so they look and handle the same.
CP.util = {
  panel_state = panel_state, polyline = polyline, dashed = dashed, vgrad = vgrad,
  small_text = small_text, handle = handle, drag_real = drag_real, set_norm = set_norm,
  mini_knob = mini_knob, mini_toggle = mini_toggle, is_on = is_on, flip = flip, lin_db = lin_db,
  draw_history = draw_history, draw_meters = draw_meters,
  mapped = mapped, set_to = set_to, ends_of = ends_of, switch_positions = switch_positions,
  time_steps = time_steps, db_ish = db_ish, positive_amount = positive_amount,
  level_line = level_line, draw_env_mapped = draw_env_mapped,
}

return CP
