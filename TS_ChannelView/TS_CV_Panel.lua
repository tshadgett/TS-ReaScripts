--[[
  TS_CV_Panel.lua -- one plugin's panel.

  Panels are a FIXED HEIGHT (they fill the window) and GROW IN COLUMNS:
  the number of rows falls out of the available height, controls flow down
  a column and wrap into a new one, and the panel gets wider. So a plugin
  with four assigned controls is a narrow strip and one with twenty is a
  wide block, and neither ever scrolls vertically -- the row of panels
  scrolls sideways instead.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local T  = require("TS_CV_FXTree")
local M  = require("TS_CV_Mappings")
local SC = require("TS_CV_Steps")
local St = require("TS_CV_State")

local P   = {}
local ImGui

function P.attach(imgui) ImGui = imgui end

-- ---------------------------------------------------------------------
-- geometry
-- ---------------------------------------------------------------------
-- One layout pass, used by BOTH the width calculation and the draw. They
-- used to compute columns separately and disagreed once already, which
-- put controls outside their own panel border; dividers make that far
-- easier to get wrong, so there is now exactly one place that decides.

-- How many rows fit in a panel of `panel_h`.
function P.rows_for(panel_h)
  -- Top and bottom are no longer the same: the grid starts tight under
  -- the header so a cell's name line isn't pushed down, and keeps the
  -- full pad at the bottom.
  local body_h = panel_h - C.HEADER_H - C.GRID_TOP_PAD - C.PANEL_PAD
  return math.max(C.MIN_ROWS, math.floor(body_h / C.CELL_H))
end

-- Places every control, returning:
--   rows     how many rows the grid has
--   items    { ctl, x, y } offsets from the grid origin
--   rules    x offsets of vertical dividers, in the same space
--   width    total width of the grid, dividers included
--   height   how far down the grid actually reaches, for the rules
--
-- A DIVIDER SPLITS THE PANEL INTO SECTIONS. Each section is laid out
-- independently in its own block of columns, so whatever follows a divider
-- always begins a new column -- no matter how the previous section ended,
-- whether it filled its last column or left gaps in it. That's the whole
-- point of a divider: "this group is finished, a new one starts here."
--
-- The rule is vertical in either flow, because it separates groups, and
-- that reads as a vertical break whichever way the controls run.
function P.layout(controls, panel_h)
  local rows  = P.rows_for(panel_h)
  local items, rules = {}, {}

  -- split the control list at dividers; a leading, trailing or doubled
  -- divider simply yields an empty section, which costs a rule and no
  -- columns
  local sections, cur = {}, {}
  for _, ctl in ipairs(controls) do
    if ctl.type == "divider" then
      sections[#sections + 1] = cur
      cur = {}
    else
      cur[#cur + 1] = ctl
    end
  end
  sections[#sections + 1] = cur

  local x, deepest = 0, 0
  for si, sec in ipairs(sections) do
    if si > 1 then
      rules[#rules + 1] = x + C.DIVIDER_W * 0.5
      x = x + C.DIVIDER_W
    end

    local n    = #sec
    local cols = math.ceil(n / rows)
    for i, ctl in ipairs(sec) do
      local idx = i - 1
      local col, row
      if C.FLOW == "row" then
        col = idx % cols
        row = math.floor(idx / cols)
      else
        col = math.floor(idx / rows)
        row = idx % rows
      end
      items[#items + 1] = { ctl = ctl, x = x + col * C.CELL_W, y = row * C.CELL_H }
      if row + 1 > deepest then deepest = row + 1 end
    end
    x = x + cols * C.CELL_W
  end

  return { rows = rows, items = items, rules = rules, width = x,
           height = math.max(1, math.min(rows, deepest)) * C.CELL_H }
end

function P.width(n_or_controls, avail_h, collapsed, has_meter)
  if collapsed then return C.COLLAPSED_W end
  local controls = n_or_controls
  if type(controls) == "number" then
    -- callers that only know the count get a plain grid, no dividers
    local n = controls
    controls = {}
    for i = 1, n do controls[i] = { type = "knob" } end
  end
  local lay = P.layout(controls, avail_h)
  local w = math.max(C.PANEL_MIN_W, lay.width + C.PANEL_PAD * 2)
  -- The meter is a strip, not a column: it adds its own narrow width
  -- rather than pushing the panel out by a whole CELL_W.
  if has_meter then w = w + C.METER_COL_W + C.PANEL_PAD end
  return w
end

-- ---------------------------------------------------------------------
-- per-parameter step size, cached: TrackFX_GetParameterStepSizes is cheap
-- but not free, and it never changes for a given plugin instance.
-- ---------------------------------------------------------------------

local step_cache  = {}
local steps_cache = {}

function P.clear_caches() step_cache = {}; steps_cache = {} end

local function step_norm(track, addr, param, key)
  local ck = key .. ":" .. param
  local v = step_cache[ck]
  if v ~= nil then return v end
  local ok, step = reaper.TrackFX_GetParameterStepSizes(track, addr, param)
  -- GetParamEx returns the VALUE first, then min/max/mid. Getting this
  -- wrong here made every stepped parameter look like it had no step at
  -- all, which is why clicking one appeared to do nothing.
  local _, minv, maxv = reaper.TrackFX_GetParamEx(track, addr, param)
  local out = false
  if ok and step and step > 0 and minv and maxv and maxv > minv then
    out = step / (maxv - minv)
    if out <= 0 or out >= 1 then out = false end
  end
  step_cache[ck] = out
  return out
end
P.step_norm = step_norm      -- exposed for TS_CV_Test.lua

-- ---------------------------------------------------------------------
-- stepped-parameter choices
-- ---------------------------------------------------------------------

-- The only way to learn a plugin's step LABELS through the ReaScript API
-- is to write each value into it and read back the formatted result. There
-- is no read-only enumeration. So this sweeps the parameter once, restores
-- it, and caches the answer for the session.
--
-- It will NOT sweep while the transport is rolling. Each write is queued
-- to the audio thread, and a frame is comparable to a buffer, so a sweep
-- during playback can genuinely be heard. Stopped, it is inaudible and
-- instant; playing, the control falls back to stepping up and down, which
-- needs no sweep.
local MAX_STEPS = 64

-- Sweeps allowed this frame; reset by P.begin_frame.
local scan_budget = 0

-- Controls whose list was just fetched on demand and should open next
-- frame, keyed by the control's ImGui id.
local pending_open = {}

function P.begin_frame() scan_budget = C.SCAN_BUDGET end

-- Returns a list of choices, or:
--   nil    not scanned yet, but scannable -- ask again, or force it
--   false  never scannable (continuous, or too many positions to sweep)
--
-- `force` means the user just clicked the control asking for the list.
-- That is a deliberate action, no different from them turning the knob,
-- so it scans whatever the transport is doing. Only the automation guard
-- still applies, because that one is about not writing a lane full of
-- garbage rather than about audibility.
local function combo_steps(track, addr, param, key, force)
  local ck = key .. ":" .. param
  local c = steps_cache[ck]
  if c ~= nil then return c end

  local st = step_norm(track, addr, param, key)
  if not st then steps_cache[ck] = false; return false end

  local n = math.floor(1 / st + 0.5) + 1
  if n < 2 or n > MAX_STEPS then steps_cache[ck] = false; return false end

  -- Scanned on a previous run? Then there is nothing to sweep at all.
  local saved_list = SC.get(key, param, st)
  if saved_list then
    steps_cache[ck] = saved_list
    return saved_list
  end

  -- Nothing is cached when a scan is refused, so it's retried every frame
  -- and the list appears by itself the moment it becomes safe.
  local rolling = (reaper.GetPlayState() & 1) == 1
  if rolling then
    -- Never while automation is being written, whatever anyone asked for.
    -- A sweep under write/touch/latch doesn't just move the parameter, it
    -- records the entire sweep into the lane -- damage to the project
    -- rather than a click.
    local mode = reaper.GetMediaTrackInfo_Value(track, "I_AUTOMODE") or 0
    if mode >= 2 then return nil end
    -- Otherwise the transport only holds back BACKGROUND scanning. An
    -- explicit click goes ahead.
    if not force and not C.SCAN_WHILE_PLAYING then return nil end
  end

  -- Spread background sweeping over frames; returning nil here just means
  -- "not yet", and this is retried until the budget comes round. A click
  -- isn't rationed -- the user is waiting for it.
  if not force then
    if scan_budget <= 0 then return nil end
    scan_budget = scan_budget - 1
  end

  local saved = reaper.TrackFX_GetParamNormalized(track, addr, param)
  local out, seen = {}, {}
  for i = 0, n - 1 do
    local v = math.min(1, i * st)
    reaper.TrackFX_SetParamNormalized(track, addr, param, v)
    local ok, txt = reaper.TrackFX_GetFormattedParamValue(track, addr, param, "")
    txt = (ok and txt ~= "") and txt or string.format("%d", i)
    -- Some plugins format several positions identically; keeping the
    -- duplicates would make the list longer than it is meaningful.
    if not seen[txt] then
      seen[txt] = true
      out[#out + 1] = { norm = v, text = txt }
    end
  end
  reaper.TrackFX_SetParamNormalized(track, addr, param, saved)

  steps_cache[ck] = (#out >= 2) and out or false
  if steps_cache[ck] then SC.set(key, param, out) end
  return steps_cache[ck]
end
P.combo_steps = combo_steps  -- exposed for TS_CV_Test.lua

-- Drops both caches for one parameter so it is swept again -- the fix for
-- a plugin that has been updated and renamed its positions.
function P.rescan_choices(key, param)
  steps_cache[key .. ":" .. param] = nil
  step_cache[key .. ":" .. param]  = nil
  SC.forget(key, param)
  SC.save()
end

-- ---------------------------------------------------------------------
-- header
-- ---------------------------------------------------------------------

-- Draws the gain-reduction strip and returns the width it consumed,
-- including its gap, so the control grid can start beside it.
local function draw_meter(ctx, dl, x, y, w, h, track, fx, meter)
  local gr = T.gain_reduction(track, fx.addr)
  if not gr then return 0 end
  local now = reaper.time_precise()
  -- meter.range is the MINIMUM: the scale steps up a ladder if the plugin
  -- pulls down harder than that, so a meter set for gentle bus compression
  -- still reads truthfully when something slams.
  local peak, range = W.gr_state(fx.guid, gr, now, meter.range)
  W.gr_meter(ctx, dl, x, y, w, h, gr, peak, range)

  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "gr##" .. fx.guid, w, h,
    ImGui.ButtonFlags_MouseButtonRight)
  W.tip(ctx, "gr##" .. fx.guid,
    ("Gain reduction\n%.2f dB now, peak %.2f\nscale 0 to %g dB%s")
    :format(gr, peak, range,
            (range > (meter.range or 0)) and "  (expanded)" or ""),
    ImGui.IsItemHovered(ctx), false)
  return w
end


local function draw_header(ctx, dl, x, y, w, track, fx, index, enabled, req)
  local h = C.HEADER_H
  local dragging = req.is_drag_source
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h,
    dragging and C.COL.header_drag
      or (enabled and C.COL.header_bg or C.COL.header_bg_byp), 0)
  ImGui.DrawList_AddLine(dl, x, y + h, x + w, y + h, C.COL.panel_border, 1.0)

  local btn = C.ICON_SIZE
  local gap = 2
  -- collapse, bypass, float, menu
  local n_btn = 4
  local btn_x = x + w - (btn + gap) * n_btn - 2

  -- index chip
  local chip = tostring(index)
  local tw, th = ImGui.CalcTextSize(ctx, chip)
  ImGui.DrawList_AddText(dl, x + 5, y + (h - th) * 0.5, C.COL.header_dim, chip)

  -- The name area is the drag handle. It sits under the text so the whole
  -- label is grabbable, and it is only a handle for top-level FX: moving
  -- something into or out of a REAPER container isn't addressable through
  -- the documented API, so those panels stay put.
  local name_x = x + 5 + tw + 6
  local name_w = math.max(8, btn_x - name_x - 4)
  ImGui.SetCursorScreenPos(ctx, name_x, y)
  ImGui.InvisibleButton(ctx, "hdr##" .. fx.guid, name_w, h,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hdr_hovered = ImGui.IsItemHovered(ctx)

  if fx.is_top_level then
    if ImGui.IsItemActive(ctx) and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      -- x and y are output slots in the Lua API and must be passed as
      -- nil; the button is the FOURTH argument, not the second.
      local dx = ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left)
      if math.abs(dx) >= C.DRAG_THRESHOLD then req.begin_drag = true end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    end
  end

  -- Hovering the header gives you the name in full. Panel headers are
  -- narrow and a long plugin name loses its tail exactly where the
  -- version number lives, which is the part you were squinting at. The
  -- container warning still has to get through, so it goes underneath
  -- rather than instead.
  if hdr_hovered then
    local full = U.clean_fx_name(fx.name)
    local fmt  = U.fx_format(fx.name)
    local ven  = U.fx_vendor(fx.name)
    if ven and ven ~= "" then full = full .. "\n" .. ven end
    if fmt and fmt ~= "" then
      full = full .. ((ven and ven ~= "") and "   \u{00B7} " or "\n") .. fmt
    end
    if not fx.is_top_level then
      full = full ..
        "\n\nInside an FX container \u{2014} reorder it in REAPER's FX chain window."
    end
    W.tip(ctx, "hdr##" .. fx.guid, full, true, false)
  end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then req.open_menu = true end
  if hdr_hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    req.toggle_collapse = true
  end

  local name = U.clean_fx_name(fx.name)
  if fx.depth and fx.depth > 0 then name = "\u{00BB} " .. name end
  local nw, nh = ImGui.CalcTextSize(ctx, name)
  if nw > name_w then
    local k = #name
    while k > 1 do
      k = k - 1
      local t = name:sub(1, k) .. "."
      nw = ImGui.CalcTextSize(ctx, t)
      if nw <= name_w then name = t break end
    end
  end
  ImGui.DrawList_AddText(dl, name_x, y + (h - nh) * 0.5,
    enabled and C.COL.header_text or C.COL.header_dim, name)

  local function at(i) ImGui.SetCursorScreenPos(ctx, btn_x + (btn + gap) * i, y + 3) end

  at(0)
  if W.icon_button(ctx, "col##" .. fx.guid, "collapse", btn, false,
      "Collapse to a bar (or double-click the name)") then
    req.toggle_collapse = true
  end

  at(1)
  if W.icon_button(ctx, "byp##" .. fx.guid, "power", btn, not enabled,
      enabled and "Bypass" or "Bypassed \u{2014} click to enable",
      C.COL.bypass_on) then
    req.toggle_bypass = true
  end

  at(2)
  local floating = T.is_floating(track, fx.addr)
  if W.icon_button(ctx, "flt##" .. fx.guid, "float", btn, floating,
      floating and "Close the plugin's window" or "Open the plugin's window",
      C.COL.float_on) then
    req.toggle_float = true
  end

  at(3)
  if W.icon_button(ctx, "mnu##" .. fx.guid, "menu", btn, false, "Panel menu") then
    req.open_menu = true
  end
end

-- A collapsed panel: a narrow bar with the name running down it, plus the
-- two controls worth reaching without expanding -- bypass and float.
local function draw_collapsed(ctx, dl, x, y, w, h, track, fx, enabled, req, meter)
  local btn = C.ICON_SIZE
  local cx = x + w * 0.5

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4)
  if W.icon_button(ctx, "xcol##" .. fx.guid, "expand", btn, false, "Expand") then
    req.toggle_collapse = true
  end

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4 + btn + 3)
  if W.icon_button(ctx, "xbyp##" .. fx.guid, "power", btn, not enabled,
      enabled and "Bypass" or "Bypassed \u{2014} click to enable",
      C.COL.bypass_on) then
    req.toggle_bypass = true
  end

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4 + (btn + 3) * 2)
  local floating = T.is_floating(track, fx.addr)
  if W.icon_button(ctx, "xflt##" .. fx.guid, "float", btn, floating,
      floating and "Close the plugin's window" or "Open the plugin's window",
      C.COL.float_on) then
    req.toggle_float = true
  end

  local text_y = y + 4 + (btn + 3) * 3 + 4
  local avail = h - (text_y - y) - 4
  local name = U.clean_fx_name(fx.name)

  -- Collapsed, the meter is the whole point: a folded-down chain still
  -- shows which compressor is working. It takes the lower half and the
  -- name takes what's left.
  if meter then
    local m_h = math.max(40, math.floor(avail * 0.55))
    local m_y = y + h - 4 - m_h
    draw_meter(ctx, dl, x + 4, m_y, w - 8, m_h, track, fx, meter)
    avail = (m_y - text_y) - 4
  end

  W.vertical_text(ctx, dl, cx, text_y, name,
    enabled and C.COL.header_text or C.COL.header_dim, math.max(0, avail))

  -- the whole bar is a grab handle and a right-click target
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "cbar##" .. fx.guid, w, h,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  W.tip(ctx, "cbar##" .. fx.guid, name, ImGui.IsItemHovered(ctx), false)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then req.open_menu = true end
  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    req.toggle_collapse = true
  end
  if fx.is_top_level and ImGui.IsItemActive(ctx)
     and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    -- x and y are output slots in the Lua API and must be passed as
    -- nil; the button is the FOURTH argument, not the second.
    local dx = ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left)
    if math.abs(dx) >= C.DRAG_THRESHOLD then req.begin_drag = true end
  end
end

-- ---------------------------------------------------------------------
-- body
-- ---------------------------------------------------------------------

-- `panel_h` is the panel's FULL height, header included -- the same value
-- P.width() was given, so the column count here can't disagree with the
-- width the panel was allotted.
local function draw_controls(ctx, dl, x, y, w, panel_h, track, fx, layout, key, req, meter)
  local controls = layout.controls or {}
  local lay = P.layout(controls, panel_h)
  local h = panel_h - C.HEADER_H

  local grid_x0 = x + C.PANEL_PAD
  local grid_w  = w - C.PANEL_PAD * 2
  if meter then
    local mx = (C.METER_SIDE == "right")
      and (x + w - C.PANEL_PAD - C.METER_COL_W)
      or  (x + C.PANEL_PAD)
    local used = draw_meter(ctx, dl, mx, y + C.PANEL_PAD, C.METER_COL_W,
                            h - C.PANEL_PAD * 2, track, fx, meter)
    if used > 0 then
      grid_w = grid_w - used - C.PANEL_PAD
      if C.METER_SIDE ~= "right" then grid_x0 = grid_x0 + used + C.PANEL_PAD end
    end
  end

  -- A grid narrower than the room it has is CENTRED in it. The panel has
  -- a minimum width, so a plugin with a single column of parameters would
  -- otherwise sit hard against the left edge with all the empty air on the
  -- right, which reads as a layout that went wrong rather than as a small
  -- plugin.
  if lay.width < grid_w then
    grid_x0 = grid_x0 + (grid_w - lay.width) * 0.5
  end

  if #lay.items == 0 and #lay.rules == 0 then
    local msg = "no layout"
    local tw, th = ImGui.CalcTextSize(ctx, msg)
    ImGui.DrawList_AddText(dl, x + w * 0.5 - tw * 0.5, y + h * 0.5 - th - 6,
      C.COL.empty_text, msg)
    local msg2 = "click to set up"
    local tw2 = ImGui.CalcTextSize(ctx, msg2)
    ImGui.DrawList_AddText(dl, x + w * 0.5 - tw2 * 0.5, y + h * 0.5 + 2,
      C.COL.empty_text, msg2)
    ImGui.SetCursorScreenPos(ctx, x, y)
    if ImGui.InvisibleButton(ctx, "empty##" .. fx.guid, w, h) then
      req.open_editor = true
    end
    return
  end

  local gx0 = grid_x0
  local gy0 = y + C.GRID_TOP_PAD
  local nparams = reaper.TrackFX_GetNumParams(track, fx.addr)

  -- Dividers first, so a control's hit area is never shadowed by a rule.
  for _, rx in ipairs(lay.rules) do
    ImGui.DrawList_AddLine(dl, gx0 + rx, gy0 + 2,
      gx0 + rx, gy0 + lay.height - 2, C.COL.knob_ring, 1.0)
  end

  -- The layout pass placed everything; this only has to draw it. Note the
  -- index into `controls` is tracked separately, because dividers take a
  -- place in the list but not in the grid.
  local ci = 0
  for _, item in ipairs(lay.items) do
    local ctl = item.ctl
    -- find this control's index in the source list for the context menu
    repeat ci = ci + 1 until controls[ci] == ctl or ci > #controls
    local i = ci

    ImGui.SetCursorScreenPos(ctx, gx0 + item.x, gy0 + item.y)

    local id = ("c%d##%s_%d"):format(i, fx.guid, i)

    if ctl.type == "blank" then
      local _, _, act = W.blank(ctx, id)
      if act.right_click then req.ctx_control = i end

    elseif not ctl.param or ctl.param < 0 or ctl.param >= nparams then
      -- The layout refers to a parameter this instance doesn't have --
      -- a plugin updated, or two different plugins sharing a name.
      ImGui.SetCursorScreenPos(ctx, gx0 + col * C.CELL_W, gy0 + row * C.CELL_H)
      local px, py = ImGui.GetCursorScreenPos(ctx)
      ImGui.InvisibleButton(ctx, id, C.CELL_W, C.CELL_H)
      W.tip(ctx, "oob" .. id, ("parameter %s is out of range for this plugin")
        :format(tostring(ctl.param)), ImGui.IsItemHovered(ctx), false)
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then req.ctx_control = i end
      local tw = ImGui.CalcTextSize(ctx, "!")
      ImGui.DrawList_AddText(dl, px + C.CELL_W * 0.5 - tw * 0.5,
        py + C.CELL_H * 0.5 - 6, C.COL.warn, "!")

    else
      local p        = ctl.param
      local value    = reaper.TrackFX_GetParamNormalized(track, fx.addr, p) or 0
      local shown    = U.fmt_value(track, fx.addr, p)
      local _, pname = reaper.TrackFX_GetParamName(track, fx.addr, p, "")
      local label    = M.display_name(key, p, ctl.label, pname)
      -- Just the value. The plugin's name is on the header two
      -- centimetres away and the parameter index is an implementation
      -- detail -- neither is what you're hovering to find out.
      local tip      = shown

      local changed, nv, act
      if ctl.type == "toggle" then
        changed, nv, act = W.toggle(ctx, id, label, value, shown, { tooltip = tip })
      elseif ctl.type == "combo" then
        changed, nv, act = W.combo(ctx, id, label, value, shown,
          step_norm(track, fx.addr, p, key),
          { tooltip     = tip,
            steps       = combo_steps(track, fx.addr, p, key),
            open_now    = pending_open[id] })
        pending_open[id] = nil
        if act and act.want_steps then
          -- scan right now, and open the list on the next frame once it
          -- has something to show
          if combo_steps(track, fx.addr, p, key, true) then
            pending_open[id] = true
          end
        end
      else
        changed, nv, act = W.knob(ctx, id, label, value, shown,
          { bipolar = ctl.bipolar, tooltip = tip, dim = not T.get_enabled(track, fx.addr) })
      end

      if act and act.double_click then
        nv, changed = U.param_mid_norm(track, fx.addr, p), true
      end
      if changed then
        reaper.TrackFX_SetParamNormalized(track, fx.addr, p, nv)
      end
      if act and act.right_click then req.ctx_control = i end
    end

    -- No remove badge on a parameter cell. A control is taken off a panel
    -- from the setup dialog or the cell's own right-click menu, and a
    -- permanent x over every knob buys nothing for that -- unlike a send,
    -- which has nowhere else to be removed from.
  end
end

-- ---------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------

-- Draws one panel at the current cursor position and advances past it.
-- Returns a `req` table of things the caller should act on this frame:
--   toggle_bypass, toggle_float, open_menu, open_editor, ctx_control
function P.draw(ctx, track, fx, layout, key, avail_h, index, is_drag_source)
  local req = { is_drag_source = is_drag_source }
  local collapsed = St.is_collapsed(fx.guid)
  local meter = M.meter_of(layout)
  if meter and not T.reports_gr(track, fx.addr, fx.guid) then meter = nil end
  local w = P.width(layout.controls or {}, avail_h, collapsed, meter ~= nil)

  local ok = ImGui.BeginChild(ctx, "pnl##" .. fx.guid, w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    local enabled = T.get_enabled(track, fx.addr)

    local bg = is_drag_source and C.COL.header_drag or C.COL.panel_bg
    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, bg, 3.0)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh,
      is_drag_source and C.COL.drop_marker or C.COL.panel_border, 3.0, 0,
      is_drag_source and 2.0 or 1.0)

    if collapsed then
      draw_collapsed(ctx, dl, x, y, ww, wh, track, fx, enabled, req, meter)
    else
      draw_header(ctx, dl, x, y, ww, track, fx, index, enabled, req)
      draw_controls(ctx, dl, x, y + C.HEADER_H, ww, wh, track, fx, layout,
                    key, req, meter)
    end
    -- ReaImGui: EndChild only when BeginChild returned true.
    ImGui.EndChild(ctx)
  end

  return w, req, collapsed
end

return P
