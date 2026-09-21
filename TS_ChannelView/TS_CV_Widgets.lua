-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Widgets.lua -- the controls a panel is made of.

  Everything is drawn onto the window's draw list rather than using
  ImGui's stock widgets, so a cell can be exactly CELL_W x CELL_H and the
  knob can look like a knob. Each widget occupies one full cell
  (name on top, control in the middle, value underneath) and returns
  `changed, new_normalised_value` plus a small table of interactions the
  panel may want to act on (right-click, double-click).
--]]

local C = require("TS_CV_Config")
local U = require("TS_CV_Util")

local W   = {}
local ImGui                      -- injected by W.attach()

-- The band a cell reserves above its control for the parameter name.
-- Exposed because a caller that draws its OWN label -- the Sends panel,
-- which wants one name across a double-width cell -- has to put it in the
-- same band, and because a knob placed anywhere other than the top of its
-- cell pushes its value readout out of the bottom.
W.LABEL_H = 11

-- The vertical centre of a knob's face, given the top of its cell. The
-- Sends panel lines its buttons up on this; recomputing it there would be
-- two places to get the same three numbers right.
function W.knob_face_y(cell_top)
  return cell_top + W.LABEL_H + C.LABEL_GAP + C.KNOB_D * 0.5
end

local TAU        = math.pi * 2
local A_MIN      = math.pi * 0.75    -- sweep start: lower-left
local A_MAX      = math.pi * 2.25    -- sweep end:   lower-right
local A_SPAN     = A_MAX - A_MIN
local ARC_SEGS   = 32

function W.attach(imgui) ImGui = imgui end

-- A smaller font for meter readouts. Optional: without one the readout
-- falls back to the default size and stacks itself to fit.
local meter_font = nil
function W.set_meter_font(f) meter_font = f end

-- The smaller face, for readouts. Always a pair: when there is no font
-- attached both are no-ops, so the push and the pop stay balanced
-- whether or not one was ever set.
function W.push_small(ctx)
  if meter_font then ImGui.PushFont(ctx, meter_font, C.METER_FONT) end
end

function W.pop_small(ctx)
  if meter_font then ImGui.PopFont(ctx) end
end

-- How many channels a track's meter should show. REAPER never takes a
-- track below two, so in practice this always answers two -- which is
-- also what REAPER itself draws for a mono track, two bars, and this
-- deliberately matches it. A mono SOURCE on a stereo track has a silent
-- right channel and should look like it; do not "fix" this into
-- collapsing to one bar. The guard is only so that a track that did
-- report one channel gets one bar instead of a second pinned at -inf.
-- Two is the ceiling: at fifty pixels a third bar is a stripe.
function W.meter_channels(track)
  local n = track and reaper.GetMediaTrackInfo_Value(track, "I_NCHAN")
  n = math.floor(n or 2)
  return math.max(1, math.min(2, n))
end

-- The wheel is contested: a knob under the pointer uses it to change a
-- value, and the panel row uses it to scroll sideways. Widgets flag when
-- they've taken it, so the row can tell the difference instead of doing
-- both. Reset once per frame.
local wheel_used = false
function W.begin_frame()   wheel_used = false end
function W.wheel_taken()   return wheel_used end
function W.take_wheel()    wheel_used = true end

-- ---------------------------------------------------------------------
-- tooltips
-- ---------------------------------------------------------------------
-- ImGui's own tooltip follows the pointer and vanishes the moment the
-- item stops being hovered -- which is exactly when you are dragging a
-- knob, since the pointer has usually left the cell by then. So these are
-- drawn by hand: the box appears where the pointer was when it opened,
-- stays put, and stays up for as long as the control is being held.
--
-- Drawn on the foreground list so it is above every panel and child
-- window regardless of what order those were drawn in.

local tips = {}        -- id -> { x, y }
local tip_now = nil    -- the one to paint at the end of the frame

function W.clear_tips() tips = {} end

-- `hovered` shows it; `active` keeps it up and frozen while dragging.
function W.tip(ctx, id, text, hovered, active)
  if not text or text == "" then return end
  if not (hovered or active) then
    if not active then tips[id] = nil end
    return
  end
  local t = tips[id]
  if not t then
    local mx, my = ImGui.GetMousePos(ctx)
    t = { x = mx + 14, y = my + 18 }
    tips[id] = t
  end
  tip_now = { x = t.x, y = t.y, text = text }
end

-- Painted once, after everything else, so nothing can cover it.
function W.draw_tip(ctx)
  local t = tip_now
  tip_now = nil
  if not t then return end

  local dl = ImGui.GetForegroundDrawList(ctx)
  local pad = 5
  local tw, th = ImGui.CalcTextSize(ctx, t.text)

  local x, y = t.x, t.y

  -- Keep it inside the WINDOW, not merely on the screen.
  --
  -- The foreground draw list is clipped to the window ReaImGui is drawing
  -- into, so a tooltip that fits on the monitor but hangs past the right
  -- edge of a docked ChannelView is simply cut off -- which is exactly
  -- what happens to every tooltip in the Sends panel, since that panel IS
  -- the right edge. Clamping to the viewport did nothing about it: there
  -- was plenty of screen out there.
  --
  -- It flips to the other side of the pointer rather than merely sliding,
  -- so the box never ends up covering the control it describes.
  local bx0, by0, bx1, by1
  if ImGui.GetWindowPos then
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    bx0, by0, bx1, by1 = wx, wy, wx + ww, wy + wh
  end
  local vp = ImGui.GetMainViewport and ImGui.GetMainViewport(ctx)
  if vp then
    local vx, vy = ImGui.Viewport_GetWorkPos(vp)
    local vw, vh = ImGui.Viewport_GetWorkSize(vp)
    -- Whichever is tighter, so neither the window nor the monitor is
    -- overrun when the window is only partly on screen.
    bx0 = bx0 and math.max(bx0, vx) or vx
    by0 = by0 and math.max(by0, vy) or vy
    bx1 = bx1 and math.min(bx1, vx + vw) or (vx + vw)
    by1 = by1 and math.min(by1, vy + vh) or (vy + vh)
  end
  if bx0 then
    if x + tw + pad > bx1 then x = t.x - tw - 28 end
    if x - pad < bx0 then x = bx0 + pad end
    if y + th + pad > by1 then y = t.y - th - 26 end
    if y - pad < by0 then y = by0 + pad end
  end

  ImGui.DrawList_AddRectFilled(dl, x - pad, y - pad + 1,
    x + tw + pad, y + th + pad - 1, 0x0d1116f0, 3.0)
  ImGui.DrawList_AddRect(dl, x - pad, y - pad + 1,
    x + tw + pad, y + th + pad - 1, C.COL.knob_ring, 3.0, 0, 1.0)
  ImGui.DrawList_AddText(dl, x, y, C.COL.header_text, t.text)
end

-- ---------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------

local function centred_text(ctx, dl, cx, y, text, col, max_w)
  if not text or text == "" then return end
  local tw, th = ImGui.CalcTextSize(ctx, text)
  if max_w and tw > max_w then
    -- crude but predictable: drop characters until it fits
    local n = #text
    while n > 1 do
      n = n - 1
      local t = text:sub(1, n) .. "."
      tw = ImGui.CalcTextSize(ctx, t)
      if tw <= max_w then text = t break end
    end
  end
  ImGui.DrawList_AddText(dl, cx - tw * 0.5, y, col, text)
  return th
end

local function arc(dl, cx, cy, r, a0, a1, col, thick)
  if math.abs(a1 - a0) < 1e-4 then return end
  ImGui.DrawList_PathArcTo(dl, cx, cy, r, a0, a1, ARC_SEGS)
  ImGui.DrawList_PathStroke(dl, col, 0, thick)
end

-- Vertical-drag value editing shared by knob and (horizontally) combo.
-- Returns the new value, or nil when nothing moved this frame.
local function drag_value(ctx, value)
  local _, dy = ImGui.GetMouseDelta(ctx)
  if dy == 0 then return nil end
  local mods = ImGui.GetKeyMods(ctx)
  local sens = C.DRAG_SENS
  if (mods & ImGui.Mod_Shift) ~= 0 then sens = sens * C.FINE_MULT end
  local v = value - dy * sens
  return math.max(0, math.min(1, v))
end

-- ---------------------------------------------------------------------
-- knob
-- ---------------------------------------------------------------------

-- id        : unique ImGui id string for this cell
-- label     : short name drawn above the knob
-- value     : 0..1
-- formatted : the plugin's own value string, drawn below
-- opts      : { bipolar, tooltip, dim }
-- returns   : changed, value, act   (act = {right_click, double_click})
function W.knob(ctx, id, label, value, formatted, opts)
  opts = opts or {}
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local cw, ch = C.CELL_W, C.CELL_H
  local r = C.KNOB_D * 0.5

  W.allow_overlap(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, cw, ch,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hovered = ImGui.IsItemHovered(ctx)
  local active  = ImGui.IsItemActive(ctx)

  local act = {
    right_click  = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right),
    double_click = hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left),
  }

  local changed = false
  -- The cell accepts right-clicks so it can raise its context menu, which
  -- also makes IsItemActive true during a right-drag. Only a LEFT drag may
  -- move the value.
  if active and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    local nv = drag_value(ctx, value)
    if nv and nv ~= value then value, changed = nv, true end
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  elseif hovered then
    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel ~= 0 then
      local mods = ImGui.GetKeyMods(ctx)
      local step = C.WHEEL_STEP
      if (mods & ImGui.Mod_Shift) ~= 0 then step = step * C.FINE_MULT end
      value = math.max(0, math.min(1, value + wheel * step))
      changed = true
      W.take_wheel()
    end
  end

  -- geometry
  local label_h = W.LABEL_H
  local cx = x + cw * 0.5
  local cy = y + label_h + C.LABEL_GAP + r

  -- name
  centred_text(ctx, dl, cx, y, label or "", C.COL.label, cw - 2)

  -- body + track
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, r,
    (hovered or active) and C.COL.knob_body_hi or C.COL.knob_body, 32)
  arc(dl, cx, cy, r - 2, A_MIN, A_MAX, C.COL.knob_track, 3.0)

  -- fill
  local a = A_MIN + A_SPAN * math.max(0, math.min(1, value))
  local fill_col = opts.bipolar and C.COL.knob_fill_bi or C.COL.knob_fill
  if opts.dim then fill_col = U.with_alpha(fill_col, 0x66) end
  if opts.bipolar then
    local a_mid = A_MIN + A_SPAN * 0.5
    if a >= a_mid then arc(dl, cx, cy, r - 2, a_mid, a, fill_col, 3.0)
    else               arc(dl, cx, cy, r - 2, a, a_mid, fill_col, 3.0) end
    -- centre detent tick
    local mx, my = cx + math.cos(a_mid) * (r - 5), cy + math.sin(a_mid) * (r - 5)
    local mx2, my2 = cx + math.cos(a_mid) * (r + 1), cy + math.sin(a_mid) * (r + 1)
    ImGui.DrawList_AddLine(dl, mx, my, mx2, my2, C.COL.knob_ring, 1.0)
  else
    arc(dl, cx, cy, r - 2, A_MIN, a, fill_col, 3.0)
  end

  -- pointer
  local px1, py1 = cx + math.cos(a) * (r * 0.30), cy + math.sin(a) * (r * 0.30)
  local px2, py2 = cx + math.cos(a) * (r - 5),    cy + math.sin(a) * (r - 5)
  ImGui.DrawList_AddLine(dl, px1, py1, px2, py2, C.COL.knob_pointer, 2.0)
  ImGui.DrawList_AddCircle(dl, cx, cy, r, C.COL.knob_ring, 32, 1.0)

  -- value
  if C.SHOW_VALUES then
    centred_text(ctx, dl, cx, y + ch - 12, formatted or "", C.COL.value, cw - 2)
  end

  W.tip(ctx, id, opts.tooltip, hovered, active)

  return changed, value, act, pressed
end

-- ---------------------------------------------------------------------
-- toggle
-- ---------------------------------------------------------------------

function W.toggle(ctx, id, label, value, formatted, opts)
  opts = opts or {}
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local cw, ch = C.CELL_W, C.CELL_H

  W.allow_overlap(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, cw, ch,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hovered = ImGui.IsItemHovered(ctx)
  local act = {
    right_click  = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right),
    double_click = hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left),
  }

  -- `pressed` fires for either button, so flip only on a left click.
  local changed = false
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
    value = (value >= 0.5) and 0 or 1
    changed = true
  end

  local on = value >= 0.5
  local label_h = W.LABEL_H
  local bx1, by1 = x + 6, y + label_h + C.LABEL_GAP + 1
  local bx2, by2 = x + cw - 6, y + label_h + C.LABEL_GAP + 1 + C.KNOB_D - 8
  local cx = x + cw * 0.5

  centred_text(ctx, dl, cx, y, label or "", C.COL.label, cw - 2)

  local bg = on and C.COL.toggle_on or C.COL.toggle_off
  if hovered then bg = U.with_alpha(bg, 0xdd) end
  ImGui.DrawList_AddRectFilled(dl, bx1, by1, bx2, by2, bg, 3.0)
  ImGui.DrawList_AddRect(dl, bx1, by1, bx2, by2, C.COL.knob_ring, 3.0, 0, 1.0)

  local txt = on and "ON" or "OFF"
  local tw, th = ImGui.CalcTextSize(ctx, txt)
  ImGui.DrawList_AddText(dl, cx - tw * 0.5, (by1 + by2) * 0.5 - th * 0.5,
    on and 0x0d1116ff or C.COL.toggle_text, txt)

  if C.SHOW_VALUES then
    centred_text(ctx, dl, cx, y + ch - 12, formatted or "", C.COL.value, cw - 2)
  end
  W.tip(ctx, id, opts.tooltip, hovered, ImGui.IsItemActive(ctx))

  return changed, value, act, pressed
end

-- ---------------------------------------------------------------------
-- combo (stepped parameter)
-- ---------------------------------------------------------------------

-- A stepped parameter: a value box that opens a list of the plugin's own
-- choices. The list has to be discovered by sweeping the parameter (see
-- TS_CV_Panel.combo_steps), which the panel won't do while the transport is
-- rolling -- so when `opts.steps` isn't available this falls back to
-- clicking through the positions one at a time, which needs no sweep.
--
-- `step_norm` is one step in normalised units, from the panel's reading of
-- TrackFX_GetParameterStepSizes; nil falls back to a plain nudge.
function W.combo(ctx, id, label, value, formatted, step_norm, opts)
  opts = opts or {}
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local cw, ch = C.CELL_W, C.CELL_H

  W.allow_overlap(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, cw, ch,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hovered = ImGui.IsItemHovered(ctx)
  local act = {
    right_click  = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right),
    -- The first click of the pair has already stepped the value by then;
    -- the caller overwrites it with the default, which is the answer
    -- either way.
    double_click = hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left),
  }

  local changed = false
  local st = (step_norm and step_norm > 0) and step_norm or nil
  local steps = opts.steps

  -- `wrap` on a click, clamp on the wheel. Clicking a stepped control is
  -- "give me the next one", and stopping dead at the last position makes
  -- the control look broken -- you can't get back without the wheel.
  -- Scrolling is a scrubbing gesture, where silently rolling over from the
  -- last position to the first is a nasty surprise.
  local function bump(dir, wrap)
    if st then
      -- snap to the step grid first, so repeated bumps can't drift
      local last = math.floor(1 / st + 0.5)
      local k = math.floor(value / st + 0.5) + dir
      if wrap then
        if k > last then k = 0 elseif k < 0 then k = last end
      end
      value = math.max(0, math.min(1, k * st))
    else
      value = math.max(0, math.min(1, value + dir * C.WHEEL_STEP))
    end
    changed = true
  end

  -- steps: a table is the list; nil means "scannable, not scanned yet";
  -- false means there will never be one, so clicking steps instead.
  local have = type(steps) == "table" and #steps > 1
  local pop  = id .. "_choices"

  if opts.open_now and have then ImGui.OpenPopup(ctx, pop) end

  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
    if have then
      ImGui.OpenPopup(ctx, pop)
    elseif steps == nil then
      act.want_steps = true          -- fetch it; the panel opens it next frame
    else
      local mods = ImGui.GetKeyMods(ctx)
      bump((mods & ImGui.Mod_Shift) ~= 0 and -1 or 1, true)
    end
  elseif hovered then
    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel ~= 0 then bump(wheel > 0 and 1 or -1, false); W.take_wheel() end
  end

  if ImGui.BeginPopup(ctx, pop) then
    for i, sv in ipairs(steps or {}) do
      local sel = st and math.abs(sv.norm - value) < st * 0.5
                     or math.abs(sv.norm - value) < 1e-4
      if ImGui.Selectable(ctx, sv.text .. "##s" .. i, sel and true or false) then
        value, changed = sv.norm, true
      end
    end
    ImGui.EndPopup(ctx)
  end

  local label_h = W.LABEL_H
  local bx1, by1 = x + 4, y + label_h + C.LABEL_GAP + 1
  local bx2, by2 = x + cw - 4, y + label_h + C.LABEL_GAP + 1 + C.KNOB_D - 8
  local cx = x + cw * 0.5

  centred_text(ctx, dl, cx, y, label or "", C.COL.label, cw - 2)
  ImGui.DrawList_AddRectFilled(dl, bx1, by1, bx2, by2,
    hovered and C.COL.knob_body_hi or C.COL.knob_body, 3.0)
  ImGui.DrawList_AddRect(dl, bx1, by1, bx2, by2, C.COL.knob_ring, 3.0, 0, 1.0)

  local txt = formatted or ""
  local tw, th = ImGui.CalcTextSize(ctx, txt)
  local inner = (bx2 - bx1) - 6
  if tw > inner then
    local n = #txt
    while n > 1 do
      n = n - 1
      local t = txt:sub(1, n) .. "."
      tw = ImGui.CalcTextSize(ctx, t)
      if tw <= inner then txt = t break end
    end
  end
  ImGui.DrawList_AddText(dl, cx - tw * 0.5, (by1 + by2) * 0.5 - th * 0.5, C.COL.value, txt)

  -- a caret on anything that opens a list, including one not yet fetched
  if have or steps == nil then
    local ax, ay = bx2 - 5, (by1 + by2) * 0.5 + 1
    ImGui.DrawList_AddTriangleFilled(dl, ax - 3, ay - 2, ax + 1, ay - 2, ax - 1, ay + 2,
      hovered and C.COL.icon_hot or C.COL.header_dim)
  end

  W.tip(ctx, id, opts.tooltip, hovered, ImGui.IsItemActive(ctx))
  return changed, value, act, pressed
end

-- ---------------------------------------------------------------------
-- blank cell (deliberate gap in a layout)
-- ---------------------------------------------------------------------

function W.blank(ctx, id)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, C.CELL_W, C.CELL_H,
    ImGui.ButtonFlags_MouseButtonRight)
  return false, 0, { right_click = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) }, false
end

-- ---------------------------------------------------------------------
-- fader and level meter
-- ---------------------------------------------------------------------

-- A vertical fader. `value` is 0..1 in REAPER's own fader taper, which the
-- caller converts to and from a volume -- the taper is not linear in dB
-- and reproducing it here by hand would put this fader subtly out of step
-- with every other one in the program.
-- `unity` is the 0..1 position of the detent mark, or nil for none.
-- Returns changed, value, act -- act.double_click meaning "put it back
-- where it started", which for a fader is unity.
-- Faders that are mid-drag, keyed by id: false while the press has not
-- moved, true once it has. Only used to tell a click from a drag.
local fader_moved = {}

function W.fader(ctx, id, x, y, w, h, value, label, unity, ghost)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, id, w, h,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hovered = ImGui.IsItemHovered(ctx)
  local active  = ImGui.IsItemActive(ctx)
  local act = {
    right_click  = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right),
    double_click = hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left),
  }
  if ImGui.IsItemActivated(ctx) then fader_moved[id] = false end

  local changed = false
  if active and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    local _, dy = ImGui.GetMouseDelta(ctx)
    if dy ~= 0 then
      local mods = ImGui.GetKeyMods(ctx)
      local sens = 1 / math.max(1, h)
      if (mods & ImGui.Mod_Shift) ~= 0 then sens = sens * C.FINE_MULT end
      value = math.max(0, math.min(1, value - dy * sens))
      changed = true
      fader_moved[id] = true
    end
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  elseif hovered then
    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel ~= 0 then
      local mods = ImGui.GetKeyMods(ctx)
      local stp = 0.01 * ((mods & ImGui.Mod_Shift) ~= 0 and C.FINE_MULT or 1)
      value = math.max(0, math.min(1, value + wheel * stp))
      changed = true
      W.take_wheel()
    end
  end

  -- A press that was let go without ever moving. Reported on RELEASE,
  -- which is the whole point: the ghost fader on a collapsed strip lies
  -- over the meter, where a plain click is meant to pick the track --
  -- and selecting on mouse-DOWN would throw a gang away the instant you
  -- reached for the fader. So the fader keeps the press, and only hands
  -- back a click once it knows the press was not a drag.
  if ImGui.IsItemDeactivated(ctx) then
    act.click = (fader_moved[id] == false)
    fader_moved[id] = nil
  end

  local cx = x + w * 0.5
  local cap_h = C.FADER_CAP_H
  local trav  = h - 8 - cap_h

  -- A GHOST fader is drawn over something else -- the meter on a
  -- collapsed strip -- so it gets no slot of its own and a cap you can
  -- see through: it has to be grabbable without hiding what it sits on.
  if not ghost then
    ImGui.DrawList_AddRectFilled(dl, cx - 2, y + 4, cx + 2, y + h - 4,
      C.COL.knob_track, 2.0)
  end

  -- Unity. Ticks either side of the slot rather than a line across it:
  -- the cap sits ON unity most of the time, and a mark it covers is no
  -- mark at all.
  if unity then
    local uy = y + 4 + cap_h * 0.5 + trav * (1 - math.max(0, math.min(1, unity)))
    ImGui.DrawList_AddLine(dl, x, uy, cx - 3, uy, C.COL.header_dim, 1.0)
    ImGui.DrawList_AddLine(dl, cx + 3, uy, x + w, uy, C.COL.header_dim, 1.0)
  end

  -- cap
  local cy   = y + 4 + trav * (1 - math.max(0, math.min(1, value)))
  local lit  = (hovered or active)
  local face = lit and C.COL.knob_pointer or C.COL.fader_cap
  local a    = ghost and (lit and 0xcc or 0x70) or 0xff
  ImGui.DrawList_AddRectFilled(dl, x, cy, x + w, cy + cap_h,
    U.with_alpha(face, a), 2.5)
  ImGui.DrawList_AddRect(dl, x, cy, x + w, cy + cap_h,
    U.with_alpha(C.COL.knob_ring, ghost and 0xcc or 0xff), 2.5, 0, 1.0)
  ImGui.DrawList_AddLine(dl, x + 2, cy + cap_h * 0.5, x + w - 2, cy + cap_h * 0.5,
    U.with_alpha(C.COL.knob_body, a), 1.5)

  W.tip(ctx, id, label, hovered, active)
  return changed, value, act
end

-- Peak hold for level meters, in dB. Separate store from the gain-reduction
-- one: these fall from a different direction and at a different rate.
local levels = {}
function W.clear_levels() levels = {} end

function W.level_peak(key, db, now)
  local p = levels[key]
  if not p then p = { v = -150, t = now }; levels[key] = p end
  if db >= p.v then
    p.v, p.t = db, now
  elseif now - p.t > C.LEVEL_HOLD then
    p.v = math.max(db, p.v - C.LEVEL_FALL * (now - p.t - C.LEVEL_HOLD))
    p.t = now - C.LEVEL_HOLD
  end
  return p.v
end

-- An RMS reading, kept beside the peak one.
--
-- REAPER exposes no sample-level RMS -- Track_GetPeakInfo is a peak and
-- nothing else -- so this is the RMS of the per-frame PEAK envelope,
-- integrated over RMS_WINDOW. That makes it a fast VU rather than a true
-- programme RMS: it sits a few dB under one on dense material and tracks
-- it closely on sparse. Worth knowing before you mix to it.
local rmss = {}
function W.clear_rms() rmss = {} end

function W.level_rms(key, db, now)
  local v = U.db2val(db)                     -- back to linear to square it
  local p = rmss[key]
  if not p then p = { sq = v * v, t = now }; rmss[key] = p end
  local dt = math.max(0, now - p.t)
  p.t = now
  -- One-pole towards the new square. At dt >= the window the old value is
  -- gone entirely, which is what makes a stalled transport settle rather
  -- than freeze mid-decay.
  local a = (C.RMS_WINDOW > 0) and math.min(1, dt / C.RMS_WINDOW) or 1
  p.sq = p.sq + (v * v - p.sq) * a
  return U.val2db(math.sqrt(p.sq))
end

-- dB to a 0..1 height on the meter scale.
function W.level_frac(db)
  if db <= C.METER_FLOOR then return 0 end
  if db >= 0 then return 1 end
  return 1 - (db / C.METER_FLOOR)
end

-- `chans` is a list of dB values, one per channel, drawn side by side.
-- `chans` is a list of per-channel dB. `rms_db` draws a second, inset bar
-- inside each channel; `opts_scale` puts a labelled ladder down the RIGHT
-- of the meter, which is where a console puts it and where it doesn't sit
-- between you and the bars.
-- The ink for one mark of the dB ladder, given the level of the bar it
-- is about to be drawn on: dark over a lit bar, light over an unlit one.
-- A file local rather than a closure inside the meter -- thirty strips
-- at sixty frames a second is not the place to allocate one per frame.
local function scale_ink(db, mark)
  return (db >= mark) and C.COL.meter_ink_lit or C.COL.meter_ink
end

function W.level_meter(ctx, dl, x, y, w, h, chans, peak_db, opts_scale, rms_db)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.knob_body, 2.0)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.COL.knob_ring, 2.0, 0, 1.0)

  -- The ladder is printed OVER the bars, the way REAPER's own meters do
  -- it, so the bars get the whole width instead of giving a third of it
  -- to a gutter of numbers. "Unreadable the moment there is signal" was
  -- the reason for the gutter, and it is a real problem with one fixed
  -- ink -- but each figure knows whether the bar behind it is lit at
  -- that level, so it can take a dark ink over a lit bar and a light one
  -- over an unlit one, and be readable either way. See below.
  --
  -- C.METER_SCALE_OVER false puts the gutter back.
  local gut = 0
  if opts_scale and not C.METER_SCALE_OVER then
    for _, mark in ipairs(C.METER_MARKS) do
      -- Bound to a name, NOT splatted into math.max: ReaImGui hands
      -- optional parameters back as extra return values, so
      -- CalcTextSize(ctx, s) returns w, h, nil, nil -- and the last
      -- argument position passes all of them on.
      local lw = ImGui.CalcTextSize(ctx, tostring(mark))
      if lw > gut then gut = lw end
    end
    gut = math.min(gut + 5, w * 0.5)
  end

  local bar_l, bar_r = x + 1.5, x + w - 1.5 - gut
  local n  = math.max(1, #chans)
  local bw = (bar_r - bar_l - (n - 1)) / n
  -- The RMS hairline's width, worked out once: the bars draw it and the
  -- peak-hold lines stop short of it, and those two had better agree
  -- about how wide it is.
  local rms_w = math.min(C.RMS_STRIP_W, math.max(2, bw * 0.4))
  for i = 1, n do
    local db = chans[i] or -150
    local f  = W.level_frac(db)
    local bx = bar_l + (i - 1) * (bw + 1)
    local top = y + 2 + (h - 4) * (1 - f)
    if f > 0 then
      ImGui.DrawList_AddRectFilled(dl, bx, top, bx + bw, y + h - 2,
        W.level_bar_colour(db), 1.0)
    end
    -- RMS: a narrow strip down the OUTER edge of each channel's bar --
    -- left of the left bar, right of the right one. Peak stays the wide
    -- bar and the thing you read first; the RMS sits beside it without
    -- ever being mistaken for a channel of its own.
    --
    -- A FIXED few pixels, not a fraction of the bar. It used to be 28%
    -- of the bar width, which was fine while the bars were narrow and
    -- became a second meter once they were not -- the whole point of the
    -- strip is that it is a hairline beside the bar, and a proportion
    -- does not keep a hairline a hairline.
    local rdb = rms_db
    if type(rdb) == "table" then rdb = rdb[i] end
    if rdb then
      local rf = W.level_frac(rdb)
      if rf > 0 then
        local rw = rms_w
        local rl = (i == n and n > 1) and (bx + bw - rw) or bx
        local rtop = y + 2 + (h - 4) * (1 - rf)
        ImGui.DrawList_AddRectFilled(dl, rl, rtop, rl + rw, y + h - 2,
          C.COL.level_rms, 1.0)
      end
    end
  end

  if opts_scale and C.METER_SCALE_OVER then
    -- Over the bars: the figure in the middle, a dash reaching in from
    -- each edge. Centring it is what makes it read as a scale rather
    -- than as a column of numbers stuck down one side, and the dashes
    -- carry the eye out to the bars the figure belongs to.
    --
    -- Ink switching: every mark asks whether the bar behind it is lit at
    -- its own level and takes dark ink if it is, light ink if it isn't.
    -- No plate punched through the bars, no halo, no outlined text.
    --
    -- A centred figure straddles both channels, and the two are not
    -- always lit to the same height -- so it is drawn TWICE, each half
    -- clipped to its own channel and inked from that channel. Two draws
    -- and two clip rects per mark, which is cheap next to getting it
    -- wrong: with one ink taken from the louder channel, half the glyph
    -- would vanish into the quieter one's unlit bar every time the two
    -- sat either side of a mark.
    --
    -- The dashes sit squarely on one bar each, so they just ask it.
    local mid   = (bar_l + bar_r) * 0.5
    local first = chans[1] or -150
    local last  = chans[n] or -150
    for _, mark in ipairs(C.METER_MARKS) do
      local my = y + 2 + (h - 4) * (1 - W.level_frac(mark))
      if my > y + 6 and my < y + h - 4 then
        local lbl = tostring(mark)
        local lw, lh = ImGui.CalcTextSize(ctx, lbl)
        local half = lw * 0.5 + 2
        ImGui.DrawList_AddLine(dl, bar_l, my, mid - half - 1, my,
          scale_ink(first, mark), 1.0)
        ImGui.DrawList_AddLine(dl, mid + half + 1, my, bar_r, my,
          scale_ink(last, mark), 1.0)

        local tx, ty = mid - lw * 0.5, my - lh * 0.5
        if n > 1 then
          ImGui.DrawList_PushClipRect(dl, tx - 1, ty, mid, ty + lh, true)
          ImGui.DrawList_AddText(dl, tx, ty, scale_ink(first, mark), lbl)
          ImGui.DrawList_PopClipRect(dl)
          ImGui.DrawList_PushClipRect(dl, mid, ty, tx + lw + 1, ty + lh, true)
          ImGui.DrawList_AddText(dl, tx, ty, scale_ink(last, mark), lbl)
          ImGui.DrawList_PopClipRect(dl)
        else
          ImGui.DrawList_AddText(dl, tx, ty, scale_ink(first, mark), lbl)
        end
      end
    end
  elseif opts_scale then
    for _, mark in ipairs(C.METER_MARKS) do
      local my = y + 2 + (h - 4) * (1 - W.level_frac(mark))
      if my > y + 6 and my < y + h - 4 then
        ImGui.DrawList_AddLine(dl, bar_l, my, bar_r, my,
          U.with_alpha(C.COL.knob_ring, 0x80), 1.0)
        local lbl = tostring(mark)
        local lw, lh = ImGui.CalcTextSize(ctx, lbl)
        ImGui.DrawList_AddText(dl, x + w - 2 - lw, my - lh * 0.5,
          C.COL.header_dim, lbl)
      end
    end
  else
    for _, mark in ipairs({ -6, -18 }) do
      local my = y + 2 + (h - 4) * (1 - W.level_frac(mark))
      ImGui.DrawList_AddLine(dl, x + w - 4, my, x + w - 1, my, C.COL.knob_ring, 1.0)
    end
  end

  -- Peak hold, ONE LINE PER CHANNEL, each only as wide as its own bar.
  -- It used to be a single line the width of the whole meter, which said
  -- that both channels had peaked at the same place -- they had not; it
  -- was the louder one's figure drawn across the quieter one's bar.
  -- `peak_db` takes a table of per-channel holds, or a single number for
  -- a meter that has only one to give.
  if peak_db then
    for i = 1, n do
      local pd = (type(peak_db) == "table") and peak_db[i] or peak_db
      if pd and pd > C.METER_FLOOR then
        local bx = bar_l + (i - 1) * (bw + 1)
        local py = y + 2 + (h - 4) * (1 - W.level_frac(pd))
        -- Stop at the RMS hairline rather than running over it. They are
        -- two different readings of the same channel, and a hold line
        -- laid across the RMS strip hides whichever of them you were
        -- looking at -- so each gets its own lane down the bar.
        local pl, pr = bx, bx + bw
        local rdb = rms_db
        if type(rdb) == "table" then rdb = rdb[i] end
        if rdb and W.level_frac(rdb) > 0 then
          if i == n and n > 1 then pr = pr - rms_w else pl = pl + rms_w end
        end
        -- The hold line takes the colour the BAR would be at that level,
        -- so the line and the bar under it never say different things.
        ImGui.DrawList_AddLine(dl, pl, py, pr, py,
          W.level_bar_colour(pd), 2.0)
      end
    end
  end
end

-- What a dB figure should be printed in: the same steps the bars use, so
-- a red readout and a red bar always mean the same thing. `under` is what
-- to use below the hot band -- the bars want their own green there, a
-- readout wants the surrounding text colour.
function W.level_colour(db, under)
  if not db then return under end
  if db >= C.LEVEL_CLIP then return C.COL.level_over end
  if db >= C.LEVEL_HOT  then return C.COL.level_clip end
  return under
end

-- The bar's own colour at a given level.
--
-- Green, then red, then a harder red over zero. There used to be an
-- amber band from -6 up, and it was noise: -6 dBFS is not a warning
-- about anything, so a colour change there is a colour change that
-- means nothing, thirty times a second, on every strip at once. The two
-- reds are kept because they DO mean something different -- approaching
-- full scale, and past it.
function W.level_bar_colour(db)
  return W.level_colour(db, C.COL.level_lo)
end

-- A small x in the bottom-left corner of a cell: "take this out".
--
-- Sends only. A parameter comes off a panel from the setup dialog or its
-- own right-click menu, so an x on every knob would be clutter buying
-- nothing; a send has nowhere else to be removed from.
--
-- Only submitted while the pointer is over the cell, so it costs nothing
-- and hides nothing the rest of the time -- but that means the cell's own
-- button has to allow being overlapped, or ImGui keeps the hover for
-- itself and the corner never responds. W.allow_overlap() is called by
-- every widget that fills a cell, just before its button.
W.BADGE = 12

function W.allow_overlap(ctx)
  if ImGui.SetNextItemAllowOverlap then ImGui.SetNextItemAllowOverlap(ctx) end
end

-- x, y are the cell's top-left; cw, ch its size (a send's cell is double
-- width, so neither can be assumed); `inset` moves the badge clear of
-- anything living down the left edge. Returns true when clicked.
function W.remove_badge(ctx, id, x, y, cw, ch, tooltip, inset)
  local sz = W.BADGE
  cw, ch = cw or C.CELL_W, ch or C.CELL_H
  local bx, by = x + 2 + (inset or 0), y + ch - sz - 2
  if not ImGui.IsMouseHoveringRect(ctx, x, y, x + cw, y + ch) then
    return false
  end

  local dl = ImGui.GetWindowDrawList(ctx)
  local keep_x, keep_y = ImGui.GetCursorScreenPos(ctx)
  ImGui.SetCursorScreenPos(ctx, bx, by)
  local pressed = ImGui.InvisibleButton(ctx, "rm##" .. id, sz, sz)
  local hot = ImGui.IsItemHovered(ctx)
  -- Put the cursor back, then submit something at it. A SetCursorScreenPos
  -- that leaves the cursor past the content the window knows about, with
  -- no item after it, is an assertion at EndChild -- ImGui has no way to
  -- tell "I moved the cursor and changed my mind" from "I drew something
  -- you should have grown for". The zero Dummy is that item.
  ImGui.SetCursorScreenPos(ctx, keep_x, keep_y)
  ImGui.Dummy(ctx, 0, 0)

  local col = hot and C.COL.warn or C.COL.header_dim
  ImGui.DrawList_AddRectFilled(dl, bx, by, bx + sz, by + sz,
    U.with_alpha(C.COL.knob_body, hot and 0xff or 0xaa), 2.5)
  local p = 3.5
  ImGui.DrawList_AddLine(dl, bx + p, by + p, bx + sz - p, by + sz - p, col, 1.4)
  ImGui.DrawList_AddLine(dl, bx + sz - p, by + p, bx + p, by + sz - p, col, 1.4)

  W.tip(ctx, "rm##" .. id, tooltip, hot, false)
  return pressed
end

-- Swiping a state across tracks.
--
-- Press on one track's mute and drag along the row: every mute you cross
-- goes the same way as the first, which is how a console with a row of
-- them works and how REAPER's own mixer behaves. The FIRST button decides
-- the direction -- pressing a lit one turns the whole swipe into an
-- unmute -- so a half-lit row resolves rather than inverting.
--
-- `seen` stops a button being set twice by the same gesture: the pointer
-- can leave and re-enter one while the button is still down, and without
-- this that would toggle it back.
local paint = nil

function W.end_paint() paint = nil end

-- Returns the value this button should take because of a swipe, or nil.
--
-- The hover test is by RECTANGLE, not by item, and that is the whole
-- trick. The moment you press a button it becomes ImGui's active item,
-- and from then until you let go ImGui reports every OTHER item as not
-- hovered -- correctly, since a click belongs to the thing you pressed.
-- A swipe is the one gesture where that is exactly wrong: the buttons
-- it is about are the ones you cross with the mouse still down. So we
-- ask the only question that still has a true answer: is the pointer
-- inside this button's rectangle? (Clipped, so a strip scrolled out of
-- view is not painted by a drag going past where it would have been.)
local function paint_value(ctx, id, kind, on, x, y, w, h)
  if not kind then return nil end
  if not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    paint = nil
    return nil
  end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
    paint = { kind = kind, val = not on, seen = {} }
  end
  if not paint or paint.kind ~= kind or paint.seen[id] then return nil end
  if not ImGui.IsMouseHoveringRect(ctx, x, y, x + w, y + h) then return nil end
  paint.seen[id] = true
  if on == paint.val then return nil end
  return paint.val
end

-- A compact labelled button for channel states (M, S, rec, phase...).
-- `paint_kind` opts this button into swipe painting ("mute", "solo",
-- "rec"...). Returns pressed, double_clicked, want -- where `want` is the
-- value a click or a swipe asks for, or nil for neither.
function W.state_button(ctx, id, text, x, y, w, h, on, on_col, tooltip, paint_kind)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local pressed = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)

  local bg = on and (on_col or C.COL.accent)
                or (hovered and C.COL.knob_body_hi or C.COL.toggle_off)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 2.5)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.COL.knob_ring, 2.5, 0, 1.0)

  local tw, th = ImGui.CalcTextSize(ctx, text)
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + (h - th) * 0.5,
    on and C.COL.icon_on or C.COL.label, text)

  W.tip(ctx, id, tooltip, hovered, false)
  -- Second return: a double-click. On a two-state button that is the same
  -- as two clicks, but on a three-state one (monitoring) it is the only
  -- way back to off without cycling, and the caller decides what its
  -- default is.
  -- The guard is here rather than inside paint_value so that the
  -- argument reads as optional where it is used -- to anyone looking,
  -- and to the arity checker, which decides what is optional from how a
  -- function treats its own parameters.
  local want
  if paint_kind then want = paint_value(ctx, id, paint_kind, on, x, y, w, h) end

  return pressed,
         hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left),
         want
end

-- The same button drawn with an icon instead of a label, for states that
-- have a symbol everyone already knows (record).
function W.state_icon(ctx, id, icon, x, y, w, h, on, on_col, tooltip, paint_kind)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local pressed = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)

  local bg = on and (on_col or C.COL.accent)
                or (hovered and C.COL.knob_body_hi or C.COL.toggle_off)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 2.5)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.COL.knob_ring, 2.5, 0, 1.0)

  local draw = W.ICONS[icon]
  if draw then
    local sz = math.min(w, h)
    draw(dl, x + (w - sz) * 0.5, y + (h - sz) * 0.5, sz,
      on and C.COL.icon_on or (hovered and C.COL.icon_hot or C.COL.icon))
  end

  W.tip(ctx, id, tooltip, hovered, false)
  -- The guard is here rather than inside paint_value so that the
  -- argument reads as optional where it is used -- to anyone looking,
  -- and to the arity checker, which decides what is optional from how a
  -- function treats its own parameters.
  local want
  if paint_kind then want = paint_value(ctx, id, paint_kind, on, x, y, w, h) end

  return pressed,
         hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left),
         want
end

-- ---------------------------------------------------------------------
-- gain reduction meter
-- ---------------------------------------------------------------------

-- A full-height strip, growing DOWNWARD from zero, which is the direction
-- gain reduction actually goes. Drawn in the contrast colour rather than
-- the accent: the accent means "a value you set", and this is neither
-- something you set nor something wrong, so it should read as neither.
--
-- The peak line is what makes it legible. At 30fps a transient reduction
-- is a single frame and effectively invisible, so the peak holds for a
-- moment and then falls at a fixed rate, the way a hardware meter's
-- needle does.
-- `col_w` is the width the meter may use in total; the bar is drawn
-- C.METER_W wide and centred in it, leaving the rest for the readout.
function W.gr_meter(ctx, dl, x, y, col_w, h, gr_db, peak_db, max_db)
  max_db = (max_db and max_db > 0) and max_db or 12

  local pushed = false
  if meter_font then
    ImGui.PushFont(ctx, meter_font, C.METER_FONT)
    pushed = true
  end

  -- Reserve the readout first: one line if "6.4 dB" fits the column,
  -- otherwise the value and the unit stacked -- which is what happens in
  -- a collapsed panel, where the whole bar is only 26px wide.
  local v     = peak_db or 0
  local val   = (v >= 0.05) and string.format("%.1f", v) or "\u{2013}"
  local one   = val .. " dB"
  local one_w = ImGui.CalcTextSize(ctx, one)
  local _, line_h = ImGui.CalcTextSize(ctx, "0")
  local stacked = one_w > col_w - 1
  local text_h  = (stacked and line_h * 2 or line_h) + 2

  local bar_h = h - text_h
  local bw    = math.min(C.METER_W, col_w)
  local bx    = x + (col_w - bw) * 0.5
  local w     = bw

  ImGui.DrawList_AddRectFilled(dl, bx, y, bx + w, y + bar_h, C.COL.knob_body, 2.0)
  ImGui.DrawList_AddRect(dl, bx, y, bx + w, y + bar_h, C.COL.knob_ring, 2.0, 0, 1.0)

  x = bx
  local inner_y, inner_h = y + 2, bar_h - 4

  -- the bar
  local frac = math.max(0, math.min(1, (gr_db or 0) / max_db))
  if frac > 0.001 then
    ImGui.DrawList_AddRectFilled(dl, x + 2, inner_y,
      x + w - 2, inner_y + inner_h * frac, C.COL.knob_fill_bi, 1.0)
  end

  -- scale marks: quarters of the range, so the ticks mean something
  -- whatever the range is set to
  for i = 1, 4 do
    local ty = inner_y + inner_h * (i / 4)
    local wide = (i == 4)
    ImGui.DrawList_AddLine(dl, x + (wide and 1 or w - 6), ty,
      x + w - 1, ty, C.COL.knob_ring, 1.0)
  end

  -- peak hold
  if peak_db and peak_db > 0.05 then
    local py = inner_y + inner_h * math.max(0, math.min(1, peak_db / max_db))
    ImGui.DrawList_AddLine(dl, x + 1, py, x + w - 1, py, C.COL.knob_pointer, 1.5)
  end

  -- The held peak under the bar. More use than printing the scale: the
  -- scale is inferable from the ticks, whereas "how much did that just
  -- pull down" is the number you actually want.
  local col = (v >= 0.05) and C.COL.value or C.COL.header_dim
  local cx  = bx - (col_w - w) * 0.5 + col_w * 0.5   -- centre of the column
  if stacked then
    local vw = ImGui.CalcTextSize(ctx, val)
    ImGui.DrawList_AddText(dl, cx - vw * 0.5, y + bar_h + 1, col, val)
    local uw = ImGui.CalcTextSize(ctx, "dB")
    ImGui.DrawList_AddText(dl, cx - uw * 0.5, y + bar_h + 1 + line_h,
      C.COL.header_dim, "dB")
  else
    ImGui.DrawList_AddText(dl, cx - one_w * 0.5, y + bar_h + 1, col, one)
  end

  if pushed then ImGui.PopFont(ctx) end
end

-- Per-FX peak state. Kept here rather than in the panel because it is
-- purely a property of the meter's behaviour over time.
local peaks = {}

function W.clear_peaks() peaks = {} end

-- The smallest rung of the ladder that covers both the configured minimum
-- and whatever the meter is actually seeing.
local function pick_range(min_range, peak)
  local need = math.max(min_range or 0, peak or 0)
  for _, r in ipairs(C.GR_LADDER) do
    if r >= need then return r end
  end
  return C.GR_LADDER[#C.GR_LADDER]
end
W.pick_range = pick_range

-- Feeds a new reading and returns the held peak.
function W.gr_peak(key, gr_db, now)
  local p = peaks[key]
  if not p then
    p = { v = 0, t = now }
    peaks[key] = p
  end
  if gr_db >= p.v then
    p.v, p.t = gr_db, now
  elseif now - p.t > C.GR_HOLD then
    p.v = math.max(gr_db, p.v - C.GR_FALL * (now - p.t - C.GR_HOLD))
    p.t = now - C.GR_HOLD
  end
  return p.v
end

-- Peak plus an auto-ranging scale. Expands the moment it's needed and
-- contracts only after the peak has sat below the smaller rung for
-- GR_RANGE_RELAX, so a scale change is a considered event, not a flicker.
function W.gr_state(key, gr_db, now, min_range)
  local peak = W.gr_peak(key, gr_db, now)
  local p = peaks[key]
  p.range  = p.range or pick_range(min_range, peak)
  p.rangeT = p.rangeT or now

  local want = pick_range(min_range, peak)
  if want > p.range then
    p.range, p.rangeT = want, now
  elseif want < p.range then
    if now - p.rangeT > C.GR_RANGE_RELAX then p.range, p.rangeT = want, now end
  else
    p.rangeT = now
  end
  return peak, p.range
end

-- ---------------------------------------------------------------------
-- header widgets
-- ---------------------------------------------------------------------

-- Icons are drawn as geometry, not set as text: no dependency on the
-- font carrying the glyph, and they stay sharp at any size.
-- Each takes the icon's bounding box and paints inside it.

local function icon_power(dl, x, y, sz, col)
  -- the standard power mark: a ring broken at the top, with a stem
  local cx, cy = x + sz * 0.5, y + sz * 0.55
  local r = sz * 0.36
  ImGui.DrawList_PathArcTo(dl, cx, cy, r, math.pi * -0.30, math.pi * 1.30, 20)
  ImGui.DrawList_PathStroke(dl, col, 0, 1.6)
  ImGui.DrawList_AddLine(dl, cx, y + sz * 0.10, cx, cy - r * 0.55, col, 1.6)
end

local function icon_float(dl, x, y, sz, col)
  -- a window with an arrow leaving its top-right corner
  local pad = sz * 0.18
  local x1, y1 = x + pad, y + pad * 1.9
  local x2, y2 = x + sz - pad * 1.9, y + sz - pad
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, col, 1.5, 0, 1.4)
  local ax, ay = x + sz - pad * 0.6, y + pad * 0.6
  ImGui.DrawList_AddLine(dl, x2 - sz * 0.10, y1 + sz * 0.10, ax, ay, col, 1.4)
  ImGui.DrawList_AddLine(dl, ax - sz * 0.26, ay, ax, ay, col, 1.4)
  ImGui.DrawList_AddLine(dl, ax, ay, ax, ay + sz * 0.26, col, 1.4)
end

local function icon_chevron(dl, x, y, sz, col, dir)
  -- dir: -1 points left (collapse), 1 points right (expand)
  local cx, cy = x + sz * 0.5, y + sz * 0.5
  local w, h = sz * 0.20, sz * 0.26
  ImGui.DrawList_AddLine(dl, cx + w * dir, cy - h, cx - w * dir, cy, col, 1.7)
  ImGui.DrawList_AddLine(dl, cx - w * dir, cy, cx + w * dir, cy + h, col, 1.7)
end

local function icon_menu(dl, x, y, sz, col)
  local cx = x + sz * 0.5
  local r = math.max(1.0, sz * 0.075)
  for _, f in ipairs({ 0.28, 0.5, 0.72 }) do
    ImGui.DrawList_AddCircleFilled(dl, cx, y + sz * f, r, col, 8)
  end
end

local function icon_plus(dl, x, y, sz, col)
  local cx, cy = x + sz * 0.5, y + sz * 0.5
  local r = sz * 0.28
  ImGui.DrawList_AddLine(dl, cx - r, cy, cx + r, cy, col, 1.8)
  ImGui.DrawList_AddLine(dl, cx, cy - r, cx, cy + r, col, 1.8)
end

local function icon_record(dl, x, y, sz, col)
  ImGui.DrawList_AddCircleFilled(dl, x + sz * 0.5, y + sz * 0.5, sz * 0.30, col, 16)
end

-- Two views, two icons. The mixer is a row of faders; the channel is one
-- strip with its plugins beside it. Each icon shows the view you would
-- GET, not the one you are in -- a button says what it does.
local function icon_mixer(dl, x, y, sz, col)
  local n, gap = 4, sz / 4
  for i = 0, n - 1 do
    local bx = x + 1 + i * gap
    local h  = sz * (0.45 + 0.13 * ((i % 2 == 0) and 1 or 0))
    ImGui.DrawList_AddRectFilled(dl, bx, y + sz - h - 2, bx + gap - 2,
      y + sz - 2, col, 0.5)
  end
end

local function icon_channel(dl, x, y, sz, col)
  -- one tall strip, then the panels it opens onto
  ImGui.DrawList_AddRectFilled(dl, x + 1, y + 2, x + sz * 0.3, y + sz - 2, col, 0.5)
  local bx = x + sz * 0.42
  for i = 0, 1 do
    local by = y + 2 + i * (sz * 0.5)
    ImGui.DrawList_AddRectFilled(dl, bx, by, x + sz - 1, by + sz * 0.38, col, 0.5)
  end
end

W.ICONS = {
  mixer    = icon_mixer,
  channel  = icon_channel,
  plus     = icon_plus,
  record   = icon_record,
  power    = icon_power,
  float    = icon_float,
  menu     = icon_menu,
  collapse = function(dl, x, y, sz, col) icon_chevron(dl, x, y, sz, col, -1) end,
  expand   = function(dl, x, y, sz, col) icon_chevron(dl, x, y, sz, col,  1) end,
}

-- A small icon button for the panel header. `on_col`, when the button is
-- lit, tints the background -- bypass goes amber, float goes blue -- so
-- the two states read differently at a glance without needing a label.
function W.icon_button(ctx, id, icon, size, active, tooltip, on_col)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, size, size)
  local hovered = ImGui.IsItemHovered(ctx)

  local bg = active and (on_col or C.COL.accent)
                    or (hovered and C.COL.knob_body_hi or nil)
  if bg then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + size, y + size, bg, 2.5)
  end

  local draw = W.ICONS[icon]
  if draw then
    local col = active and C.COL.icon_on
                       or (hovered and C.COL.icon_hot or C.COL.icon)
    draw(dl, x, y, size, col)
  end

  W.tip(ctx, id, tooltip, hovered, false)
  return pressed
end

-- The routing button.
--
-- Three lamps stacked in a column, the way REAPER's own routing button
-- carries them: parent/master send at the top, sends out in the middle,
-- receives in at the bottom. Drawn rather than iconified because each
-- line needs its own colour, which an icon glyph cannot give.
--
-- `leds` is { parent, sends, receives }. Returns true when clicked.
function W.route_button(ctx, id, w, h, leds, tooltip)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)

  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h,
    hovered and C.COL.knob_body_hi or C.COL.knob_body, 2.5)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.COL.knob_ring, 2.5, 0, 1.0)

  local cols = { C.COL.route_parent, C.COL.route_send, C.COL.route_recv }
  local lw   = w - 7
  local lh   = 2
  local gap  = 2
  local top  = y + (h - (lh * 3 + gap * 2)) * 0.5
  for i = 1, 3 do
    local ly = top + (i - 1) * (lh + gap)
    -- An unlit lamp is drawn, not omitted: three slots that are always
    -- there say which one is missing, where two lines and a space only
    -- say "two of something".
    local col = leds[i] and cols[i] or C.COL.route_off
    ImGui.DrawList_AddRectFilled(dl, x + 3.5, ly, x + 3.5 + lw, ly + lh, col, 1.0)
  end

  W.tip(ctx, id, tooltip, hovered, false)
  return pressed
end

-- Text running down a narrow bar, one character per line -- what a console
-- does with a collapsed strip. ImGui can't rotate text, and stacked
-- capitals stay readable in a way a rotated bitmap font would not.
-- Returns the height used.
-- Rotated labels.
--
-- ImGui has no way to rotate text: the draw list takes glyphs at a
-- position and that is that. It CAN place an arbitrary image on an
-- arbitrary quad, though, so the label is rendered once into a LICE
-- bitmap, copied into an ImGui image, and drawn on a quad whose corners
-- are turned a quarter turn.
--
-- That needs js_ReaScriptAPI for the LICE and GDI calls. Without it, or
-- if any part of it raises, the stacked-letter version below still runs
-- and nothing here is tried again.
local rot_img, rot_ok = {}, nil

function W.clear_rot() rot_img = {} end

local function rot_usable()
  if rot_ok == nil then
    rot_ok = C.ROT_TEXT
      and reaper.JS_LICE_CreateBitmap  ~= nil
      and reaper.JS_LICE_CreateFont    ~= nil
      and reaper.JS_LICE_SetFontFromGDI ~= nil
      and reaper.JS_LICE_DrawText      ~= nil
      and reaper.JS_GDI_CreateFont     ~= nil
      and ImGui.CreateImageFromLICE    ~= nil
      and ImGui.DrawList_AddImageQuad  ~= nil
  end
  return rot_ok
end

-- One image per (text, colour, size). Building one costs a bitmap, a
-- font and a texture upload, so doing it per frame would be absurd.
local function rot_build(ctx, text, col, px, w, h)
  local gdi = reaper.JS_GDI_CreateFont(px, 400, 0, 0, 0, 0, C.ROT_FONT)
  if not gdi then return nil end
  local font = reaper.JS_LICE_CreateFont()
  reaper.JS_LICE_SetFontFromGDI(font, gdi, "")
  reaper.JS_GDI_DeleteObject(gdi)

  -- Ours are 0xRRGGBBAA, LICE wants 0xAARRGGBB.
  local a = col & 0xff
  reaper.JS_LICE_SetFontColor(font, ((a << 24) | (col >> 8)) & 0xffffffff)

  local bm = reaper.JS_LICE_CreateBitmap(true, w, h)
  reaper.JS_LICE_Clear(bm, 0x00000000)
  reaper.JS_LICE_DrawText(bm, font, text, #text, 0, 0, w, h)

  -- CreateImageFromLICE copies the pixels, so the bitmap is ours to
  -- destroy immediately; the image is attached to the context so it
  -- survives until the cache drops it.
  local img = ImGui.CreateImageFromLICE(bm)
  reaper.JS_LICE_DestroyBitmap(bm)
  if reaper.JS_LICE_DestroyFont then reaper.JS_LICE_DestroyFont(font) end
  if img then ImGui.Attach(ctx, img) end
  return img
end

local function rot_get(ctx, text, col, px, w, h)
  local key = ("%s|%08x|%d|%d"):format(text, col & 0xffffffff, px, w)
  local hit = rot_img[key]
  if hit ~= nil then return hit.img end

  local ok, img = pcall(rot_build, ctx, text, col, px, w, h)
  if not ok then
    -- One failure is enough: whatever is missing will still be missing
    -- next frame, and retrying sixty times a second to find that out
    -- would be its own bug.
    rot_ok = false
    return nil
  end
  rot_img[key] = { img = img }
  return img
end

-- Text running down a narrow bar -- what a console does with a collapsed
-- strip. Returns the height used.
function W.vertical_text(ctx, dl, cx, y, text, col, max_h)
  text = (text or ""):upper():gsub("%s+", " ")
  if text == "" or max_h <= 4 then return 0 end

  if rot_usable() then
    -- Trimmed against the room down the bar, which for rotated text is
    -- measured along its WIDTH.
    local tw, th = ImGui.CalcTextSize(ctx, text)
    while tw > max_h and #text > 1 do
      text = text:sub(1, #text - 1)
      tw = ImGui.CalcTextSize(ctx, text .. "\u{2026}")
      if tw <= max_h then text = text .. "\u{2026}" break end
    end

    local px = math.max(6, math.floor(ImGui.GetFontSize(ctx) + 0.5))
    -- Generous: GDI's Arial is not ImGui's font, and a bitmap a little
    -- too wide costs transparent pixels while one too narrow clips.
    local bw = math.max(8, math.ceil(tw) + px)
    local bh = math.max(8, math.ceil(th) + 4)

    local img = rot_get(ctx, text, col, px, bw, bh)
    if img then
      -- A quarter turn. The image's top-left goes to the bottom-left of
      -- the destination and the rest follows round, which reads bottom
      -- to top; C.ROT_UP false sends it the other way.
      local x0, y0 = cx - bh * 0.5, y
      local x1, y1 = x0 + bh, y + bw
      if C.ROT_UP then
        ImGui.DrawList_AddImageQuad(dl, img,
          x0, y1,  x0, y0,  x1, y0,  x1, y1)
      else
        ImGui.DrawList_AddImageQuad(dl, img,
          x1, y0,  x1, y1,  x0, y1,  x0, y0)
      end
      return bw
    end
  end

  -- Stacked capitals: no rotation anywhere, but legible in a way a
  -- rotated bitmap font would not be if we had to fake one.
  local _, line_h = ImGui.CalcTextSize(ctx, "X")
  line_h = line_h - 2
  local n = math.max(0, math.floor(max_h / line_h))
  local used = 0
  for i = 1, math.min(#text, n) do
    local ch = text:sub(i, i)
    if i == n and #text > n then ch = "\u{2026}" end
    if ch ~= " " then
      local w = ImGui.CalcTextSize(ctx, ch)
      ImGui.DrawList_AddText(dl, cx - w * 0.5, y + used, col, ch)
    end
    used = used + line_h
  end
  return used
end

-- A child that BeginChild declined to draw.
--
-- ReaImGui keeps Dear ImGui's PRE-1.90 convention: EndChild is called
-- only when BeginChild returned true. The catch is that a culled child
-- then submits NO ITEM at all, so the parent's content bounds never grow
-- past it -- which breaks the SameLine after it, and, if the cursor was
-- moved by hand beforehand, ends the frame with
--
--   "Code uses SetCursorPos()/SetCursorScreenPos() to extend
--    window/parent boundaries. Please submit an item e.g. Dummy()"
--
-- ...raised from End, hundreds of lines from the child that caused it.
-- So a skipped child still occupies its space.
function W.child_skipped(ctx, w, h)
  ImGui.Dummy(ctx, math.max(0, w or 0), math.max(0, h or 0))
end

return W
