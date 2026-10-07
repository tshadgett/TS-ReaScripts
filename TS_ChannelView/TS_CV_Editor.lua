-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Editor.lua -- "Setup Edit Parameters".

  Two lists and an Add/Remove pair: everything the plugin exposes on
  the right, what the panel actually shows on the left, in panel order.

  Two kinds of naming, which the dialog keeps apart:

    ALIAS  -- your name for one of the plugin's parameters. Follows the
              parameter everywhere: every panel, and the lists here. This
              is the one you want for a plugin whose own parameter names
              are cryptic.
    LABEL  -- a caption for ONE slot on the panel, for when a layout is
              cramped and that particular knob needs something shorter.

  Edits a SCRATCH COPY, aliases included. Nothing reaches the layout
  library until Save, so Cancel really is a cancel. And because layouts
  are per plugin TYPE, the dialog says so plainly -- saving here changes
  this plugin's panel on every track in every project.
--]]

local C = require("TS_CV_Config")
local U = require("TS_CV_Util")
local M = require("TS_CV_Mappings")
local CP = require("TS_CV_ColourPick")
local TP = require("TS_CV_Taps")
local RQ = require("TS_CV_ReaEQ")

local E = {}
local ImGui

local TITLE = "Setup Edit Parameters"

local TYPES       = { "knob", "toggle", "combo", "stepped", "fader", "xy", "dual", "blank", "half_gap", "divider" }
local TYPE_NAMES = { knob = "Knob", toggle = "Button", combo = "Dropdown", stepped = "Stepped knob",
                     fader = "Fader", xy = "XY pad", dual = "Concentric knob", blank = "Gap",
                     half_gap = "Half gap", divider = "Divider" }
local SIZES_COMBO = ""
for _, k in ipairs(C.SIZE_LIST) do SIZES_COMBO = SIZES_COMBO .. C.SIZES[k].label .. "\0" end
local TOGGLE_SIZES_COMBO = C.SIZES.small.label .. "\0" .. C.SIZES.medium.label .. "\0"

local st = {
  open      = false,
  request   = false,     -- ask ImGui to open the popup next frame
  key       = nil,       -- plugin key being edited
  fx        = nil,       -- {addr, guid, name} snapshot
  scratch   = nil,       -- layout copy under edit
  sel_asg   = 0,         -- selected index in the assigned list (1-based, 0 = none)
  sel_avail = 0,
  filter    = "",
  learn     = false,
  drag_from = nil,       -- row being dragged in the panel list
  params    = nil,       -- cached {index, name} for this plugin
  was_saved = false,
  applied   = false,     -- Apply has pushed the scratch into the library
  original  = nil,       -- what to put back if it is then cancelled
  in_lib    = false,     -- ... or whether to take it out entirely
}

function E.attach(imgui) ImGui = imgui end

-- A "Brushed" tick beside a background or section combo: Brush<n> on the
-- control, cleared when it matches what the faceplate does anyway.
-- The colours of your own a Background or Section combo offers after the
-- faceplates: the one it has now, the recent ones (TS_CV_ColourPick), and
-- "Custom colour..." -- key "+" -- which opens the picker.
local function custom_choices(names, keys, prefix, now)
  local seen = {}
  local function add(k)
    if k and not seen[k] then
      seen[k] = true
      names[#names + 1] = prefix .. C.plate_of(k).label; keys[#keys + 1] = k
    end
  end
  add(C.custom_key(now))
  for _, rgb in ipairs(CP.recent) do add(("#%06x"):format(rgb)) end
  names[#names + 1] = "Custom colour\u{2026}"; keys[#keys + 1] = "+"
end

-- Opens the picker for control c's background (field "back") or its
-- section (a divider's style/cap), showing each colour on the panel as
-- it's chosen and putting back what was there on Cancel.
local function pick_custom(c, what)
  local function hex(rgb) return ("#%06x"):format(rgb) end
  if what == "back" then
    local before = c.back
    local pl = C.plate_of(before)
    CP.open({ title = "Background colour", rgb = C.custom_rgb(before) or (pl and pl.bg >> 8),
      preview = function(rgb) c.back = hex(rgb) end,
      apply   = function(rgb) c.back = hex(rgb) end,
      cancel  = function() c.back = before end })
  else
    local bs, bc = c.style, c.cap
    local pl = (bs == "plate") and C.plate_of(bc) or nil
    CP.open({ title = "Section colour", rgb = (pl and C.custom_rgb(bc)) or (pl and pl.bg >> 8),
      preview = function(rgb) c.style, c.cap = "plate", hex(rgb) end,
      apply   = function(rgb) c.style, c.cap = "plate", hex(rgb) end,
      cancel  = function() c.style, c.cap = bs, bc end })
  end
end

local function brush_box(ctx, c, kind, pl, id)
  if not kind then return end
  local on = M.part_brushed(kind, pl, c.brush)
  local ch, v = ImGui.Checkbox(ctx, "Brushed##" .. id, on)
  if ch then
    if v == M.part_brushed(kind, pl, nil) then c.brush = nil else c.brush = v end
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "A fine brushed grain across it.")
  end
  ImGui.SameLine(ctx)
  local mch, mv = ImGui.Checkbox(ctx, "Metallic##" .. id, M.part_metal(kind, c.metal))
  if mch then c.metal = mv or nil end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "A fine metallic flake across it, like metallic paint.")
  end
end

function E.is_open() return st.open end
function E.key() return st.key end

-- ---------------------------------------------------------------------

local function load_params(track, fx)
  local list = {}
  local n = reaper.TrackFX_GetNumParams(track, fx.addr)
  local own = U.own_param_count(track, fx.addr)
  for p = 0, n - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, fx.addr, p, "")
    list[#list + 1] = {
      index   = p,
      name    = U.trim(nm) ~= "" and U.trim(nm) or ("Param " .. p),
      builtin = (p >= own),
    }
  end
  return list
end

function E.open(track, fx, key, layout)
  -- a locked layout takes no edits (unlocked from the panel's padlock)
  if M.locked(layout) then return end
  st.open      = true
  st.request   = true
  st.key       = key
  st.fx        = { addr = fx.addr, guid = fx.guid, name = fx.name }
  st.scratch   = M.copy(layout or { controls = {}, aliases = {} })
  st.scratch.aliases = st.scratch.aliases or {}
  st.sel_asg   = math.min(1, #st.scratch.controls)
  st.sel_avail = 0
  st.filter    = ""
  st.learn     = false
  st.drag_from = nil
  -- The plugin's OWN answer: a measured plugin is offered measuring, not
  -- the plain meter switch.
  st.reports_gr = require("TS_CV_FXTree").reports_gr_natively(track, fx.addr, fx.guid)
  st.track     = track
  st.params    = load_params(track, fx)
  st.was_saved = false
  -- Apply pushes the scratch copy into the LIVE mapping so the panel
  -- behind the dialog redraws while you are still editing -- which is
  -- the only way to see whether a layout works. Cancel then has
  -- something to undo, so the state it would undo TO is taken now: the
  -- layout as it stood, and whether it was in the library at all. An
  -- applied-then-cancelled layout that was only ever a generated
  -- default has to leave no trace, not be written back as if somebody
  -- had built it.
  st.applied   = false
  st.original  = M.copy(layout or { controls = {}, aliases = {} })
  st.in_lib    = M.has(key)
end

-- Put the library back the way Apply found it. Nothing here touches the
-- file: Apply never wrote one.
local function revert_applied()
  if not st.applied then return end
  if st.in_lib then M.set(st.key, st.original) else M.remove(st.key) end
  TP.invalidate()
  st.applied = false
end

local function assigned_has(param)
  for _, c in ipairs(st.scratch.controls) do
    if c.param == param then return true end
  end
  return false
end

local function add_param(track, param)
  local nm = ""
  for _, p in ipairs(st.params or {}) do
    if p.index == param then nm = p.name break end
  end
  -- Insert below whatever is selected: you build a panel by working down
  -- it, so the next thing you add almost always belongs after the last
  -- thing you touched rather than at the very bottom.
  local at = (st.sel_asg >= 1 and st.sel_asg <= #st.scratch.controls)
             and (st.sel_asg + 1) or (#st.scratch.controls + 1)
  table.insert(st.scratch.controls, at, {
    param   = param,
    type    = U.guess_control_type(track, st.fx.addr, param),
    bipolar = U.guess_bipolar(nm, track, st.fx.addr, param),
    label   = "",          -- the name shows by itself; a label would hide an alias
  })
  st.sel_asg = at
end

-- ---------------------------------------------------------------------

-- Move one entry to an arbitrary position, closing the gap behind it.
-- A straight remove-and-insert rather than a neighbour swap, so a row can
-- travel the whole list in one drag instead of one place per crossing.
local function move_control(from, to)
  local list = st.scratch.controls
  if from == to or not list[from] then return end
  to = math.max(1, math.min(#list, to))
  local item = table.remove(list, from)
  table.insert(list, to, item)
  st.sel_asg = to
end

local function draw_assigned(ctx, track, list_w, list_h)
  ImGui.Text(ctx, "Panel")
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, "\u{2014}  drag a row to reorder")

  local _, mouse_y = ImGui.GetMousePos(ctx)
  local drop_at, first_top, last_bottom = nil, nil, nil

  if ImGui.BeginListBox(ctx, "##assigned", list_w, list_h) then
    for i, c in ipairs(st.scratch.controls) do
      local pname = ""
      for _, p in ipairs(st.params or {}) do
        if p.index == c.param then pname = p.name break end
      end
      local label
      if c.type == "divider" then
        label = ("%2d  \u{2502}\u{2502}\u{2502} divider"):format(i)
      elseif c.type == "blank" then
        label = ("%2d  \u{2014} blank \u{2014}"):format(i)
      elseif c.type == "half_gap" then
        label = ("%2d  \u{2044} half gap"):format(i)
      else
        local shown = c.label
        if c.live or st.scratch.live then shown = pname end
        if not shown or shown == "" then shown = st.scratch.aliases[c.param] end
        if not shown or shown == "" then shown = pname end
        label = ("%2d  %-16s  %s"):format(i, U.truncate(shown, 16), TYPE_NAMES[c.type] or c.type)
      end

      if ImGui.Selectable(ctx, label .. "##asg" .. i, st.sel_asg == i) then
        st.sel_asg = i
      end

      -- Which row is the pointer over? Measured from each row's actual
      -- rectangle, so it doesn't depend on guessing a line height.
      local _, ry1 = ImGui.GetItemRectMin(ctx)
      local _, ry2 = ImGui.GetItemRectMax(ctx)
      if i == 1 then first_top = ry1 end
      last_bottom = ry2
      if mouse_y >= ry1 and mouse_y < ry2 then drop_at = i end

      -- Holding a row and moving starts the drag.
      if ImGui.IsItemActive(ctx)
         and ImGui.IsMouseDragging(ctx, ImGui.MouseButton_Left)
         and not st.drag_from then
        st.drag_from = i
      end
    end
    ImGui.EndListBox(ctx)
  end

  -- Dragged past either end: clamp to the nearest slot rather than
  -- dropping the drag, so overshooting still lands where you meant.
  if st.drag_from then
    if not drop_at and first_top and mouse_y < first_top then drop_at = 1 end
    if not drop_at and last_bottom and mouse_y >= last_bottom then
      drop_at = #st.scratch.controls
    end
    if not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      st.drag_from = nil
    elseif drop_at and drop_at ~= st.drag_from then
      move_control(st.drag_from, drop_at)
      st.drag_from = drop_at
    end
  end

  local n = #st.scratch.controls
  local sel = st.sel_asg

  if ImGui.Button(ctx, "Remove >>", 90) then
    if st.scratch.controls[sel] then
      table.remove(st.scratch.controls, sel)
      st.sel_asg = math.min(sel, #st.scratch.controls)
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "\u{25B2}", 30) and sel > 1 then
    move_control(sel, sel - 1)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "\u{25BC}", 30) and sel >= 1 and sel < n then
    move_control(sel, sel + 1)
  end
  if ImGui.Button(ctx, "Gap", 50) then
    local at = (sel >= 1 and sel < n) and (sel + 1) or (n + 1)
    table.insert(st.scratch.controls, at,
      { param = -1, type = "blank", bipolar = false, label = "" })
    st.sel_asg = at
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "An empty cell, for spacing a layout out like a hardware strip.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Half-gap", 70) then
    local at = (sel >= 1 and sel < n) and (sel + 1) or (n + 1)
    table.insert(st.scratch.controls, at,
      { param = -1, type = "half_gap", bipolar = false, label = "" })
    st.sel_asg = at
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "Staggers the control right after it half a row down, to mimic\n" ..
      "staggered hardware knobs. Column layouts only -- see the type's\n" ..
      "own note in TS_ChannelView_Mappings.ini.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Divider", 64) then
    local at = (sel >= 1 and sel < n) and (sel + 1) or (n + 1)
    table.insert(st.scratch.controls, at,
      { param = -1, type = "divider", bipolar = false, label = "" })
    st.sel_asg = at
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "A rule between groups of controls. Ends the current column,\n" ..
      "so it separates sections rather than taking a cell. Select it\n" ..
      "below to turn its line off and keep only the spacing.")
  end
end

local function draw_available(ctx, track, list_w, list_h)
  ImGui.Text(ctx, "Plugin parameters")
  ImGui.SetNextItemWidth(ctx, list_w)
  -- Enter adds the selected parameter if the filter still shows it, else
  -- the first one it shows, and leaves the box ready for the next
  if st.filter_refocus then ImGui.SetKeyboardFocusHere(ctx); st.filter_refocus = false end
  local _, f = ImGui.InputTextWithHint(ctx, "##filter", "filter\u{2026}", st.filter)
  local filter_enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  st.filter = f
  local first_shown, sel_shown

  local needle = st.filter:lower()
  if ImGui.BeginListBox(ctx, "##available", list_w, list_h) then
    for _, p in ipairs(st.params or {}) do
      local alias_l = (st.scratch.aliases[p.index] or ""):lower()
      local show = needle == ""
        or p.name:lower():find(needle, 1, true)
        or (alias_l ~= "" and alias_l:find(needle, 1, true))
      if show then
        first_shown = first_shown or p.index
        if p.index == st.sel_avail then sel_shown = true end
        local used = assigned_has(p.index)
        local alias = st.scratch.aliases[p.index]
        local shown = (alias and alias ~= "") and (alias .. "   \u{2190} " .. p.name)
                                              or p.name
        local label = ("%3d  %s%s"):format(p.index, shown,
          p.builtin and "   (REAPER)" or (used and "   \u{2713}" or ""))
        if ImGui.Selectable(ctx, label .. "##av" .. p.index, st.sel_avail == p.index) then
          st.sel_avail = p.index
        end
        if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
          add_param(track, p.index)
        end
      end
    end
    ImGui.EndListBox(ctx)
  end
  if filter_enter and first_shown then
    local p = sel_shown and st.sel_avail or first_shown
    st.sel_avail = p
    add_param(track, p)
    st.filter_refocus = true
  end

  if ImGui.Button(ctx, "<< Add", 90) then
    add_param(track, st.sel_avail)
  end
  ImGui.SameLine(ctx)
  local lch, lv = ImGui.Checkbox(ctx, "Learn", st.learn)
  if lch then st.learn = lv end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "While on, touching a control in the plugin's own window adds that parameter here.")
  end
end

-- The selected control's settings, as a column: each on a row of its own,
-- its name on the left, and only the rows that apply to its type.
local COL_W   = 330          -- the column's width
local KEY_W   = 86           -- the names' width
local FIELD_W = COL_W - KEY_W - 8

local function draw_entry_editor(ctx)
  local c = st.scratch.controls[st.sel_asg]
  ImGui.SeparatorText(ctx, "Selected control")
  -- the column keeps its width whatever is selected
  ImGui.Dummy(ctx, COL_W, 0)
  if not c then
    ImGui.TextDisabled(ctx, "Nothing selected.")
    return
  end

  -- a row: its name right-aligned in the names' column, the field after
  local function row_name(text)
    local tw = ImGui.CalcTextSize(ctx, text)
    local x0 = ImGui.GetCursorPosX(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.SetCursorPosX(ctx, x0 + KEY_W - tw)
    ImGui.Text(ctx, text)
    ImGui.SameLine(ctx, 0, 8)
  end
  local function tip(text)
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then ImGui.SetTooltip(ctx, text) end
  end

  local pname = ""
  for _, p in ipairs(st.params or {}) do
    if p.index == c.param then pname = p.name break end
  end
  local is_param = c.type ~= "blank" and c.type ~= "divider" and c.type ~= "half_gap"
  local two = c.type == "xy" or c.type == "dual"

  -- what it controls
  if is_param then
    row_name((c.type == "xy") and "X parameter" or (c.type == "dual") and "Ring" or "Parameter")
    ImGui.Text(ctx, ("%s  %s"):format(tostring(c.param), pname))
  end
  -- an XY pad's Y or a concentric knob's inner knob (Dual<n>)
  if two and st.track and st.fx then
    local n = reaper.TrackFX_GetNumParams(st.track, st.fx.addr)
    local names = {}
    for p = 0, n - 1 do
      local _, pn = reaper.TrackFX_GetParamName(st.track, st.fx.addr, p, "")
      names[#names + 1] = ("%d  %s"):format(p, (M.display_name(st.key, p, nil, pn, false):gsub("%z", "")))
    end
    row_name((c.type == "xy") and "Y parameter" or "Inner knob")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local pch, pi = ImGui.Combo(ctx, "##p2", c.param2 or 0, table.concat(names, "\0") .. "\0")
    if pch then c.param2 = pi end
    tip((c.type == "xy") and "The parameter the pad moves up and down (X is across)."
      or "The parameter the inner knob turns (the ring turns the one above).")
  end

  -- what it is
  row_name("Type")
  local cur = 0
  for i, t in ipairs(TYPES) do if t == c.type then cur = i - 1 break end end
  local tnames = {}
  for i, t in ipairs(TYPES) do tnames[i] = TYPE_NAMES[t] or t end
  ImGui.SetNextItemWidth(ctx, FIELD_W)
  local tch, ti = ImGui.Combo(ctx, "##type", cur, table.concat(tnames, "\0") .. "\0")
  if tch then
    local was = c.type
    c.type = TYPES[ti + 1] or "knob"
    -- sizes don't carry between an XY pad and anything else; a concentric
    -- knob is never small; a second parameter starts as the next one along
    if (c.type == "xy") ~= (was == "xy") or (c.type == "dual" and c.size == "small") then c.size = nil end
    if (c.type == "xy" or c.type == "dual") and not c.param2 and c.param and st.track and st.fx then
      local n = reaper.TrackFX_GetNumParams(st.track, st.fx.addr)
      c.param2 = (c.param + 1 < n) and (c.param + 1) or c.param
    end
    is_param = c.type ~= "blank" and c.type ~= "divider" and c.type ~= "half_gap"
    two = c.type == "xy" or c.type == "dual"
  end

  -- its names. A live name overrides both; they stay as they are, just
  -- greyed, so turning live off again brings them back.
  local live = is_param and (c.live or st.scratch.live) or false
  if is_param then
    if live then ImGui.BeginDisabled(ctx, true) end
    row_name("Alias")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local ach, av = ImGui.InputTextWithHint(ctx, "##alias",
      pname ~= "" and pname or "name\u{2026}", st.scratch.aliases[c.param] or "")
    if ach then
      av = U.trim(av)
      st.scratch.aliases[c.param] = (av ~= "") and av or nil
    end
    tip("Your name for this parameter. Applies to this plugin everywhere,\n" ..
      "whether or not the parameter is on a panel. Clear it to go back to\n" ..
      "what the plugin calls it: " .. (pname ~= "" and pname or "?"))
    row_name("Label")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local ch, v = ImGui.InputTextWithHint(ctx, "##label", "this slot only", c.label or "")
    if ch then c.label = v end
    tip("Overrides the alias for THIS slot only. Leave empty unless a\n" ..
      "cramped layout needs a shorter caption here.")
    if live then ImGui.EndDisabled(ctx) end
  end

  -- its size and shape
  if c.type == "knob" or c.type == "stepped" then
    row_name("Size")
    local now = 1
    for i, k in ipairs(C.SIZE_LIST) do if k == (c.size or "medium") then now = i - 1 end end
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local sch, si = ImGui.Combo(ctx, "##size", now, SIZES_COMBO)
    if sch then
      local k = C.SIZE_LIST[si + 1]
      c.size = (k ~= "medium") and k or nil
    end
    tip("Small: half height, a small dial under its name in small type --\n" ..
      "its value moves to the tooltip, and two stack in one ordinary cell.\n" ..
      "Large: half again as big, name and value kept.")
    -- numbers round the dial (Scale<n>); values unless it says otherwise
    row_name("Scale")
    local kind = M.scale_kind(c)
    local snow = (kind == "values") and 1 or (kind == "ten") and 2 or 0
    ImGui.SetNextItemWidth(ctx, 100)
    local scch, sci = ImGui.Combo(ctx, "##scale", snow, "None\0Values\0" .. "0\u{2013}10\0")
    if scch then
      c.scale = (sci == 0) and "none" or (sci == 2) and "ten" or nil
      if c.scale == "none" then c.scale_ink = nil end
    end
    tip("Numbers round the dial: the plugin's own values (units left\n" ..
      "off, thousands as k), or 0 to 10. A medium knob with numbers\n" ..
      "shows its value in the tooltip; a small one has no room for them.")
    if M.scale_kind(c) then
      ImGui.SameLine(ctx)
      local ich, iv = ImGui.Checkbox(ctx, "in cap colour", c.scale_ink == "cap")
      if ich then c.scale_ink = iv and "cap" or nil end
    end
  elseif c.type == "toggle" then
    row_name("Size")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local sch, si = ImGui.Combo(ctx, "##tsize", (c.size == "small") and 0 or 1, TOGGLE_SIZES_COMBO)
    if sch then c.size = (si == 0) and "small" or nil end
    tip("Small: half height and all button, with its name on it when the\n" ..
      "state has no name of its own. Two stack in one cell.")
  elseif c.type == "combo" and c.param and st.track and st.fx then
    -- a dropdown can show its choices as buttons instead (2 to C.BUTTONS_MAX)
    local P = require("TS_CV_Panel")
    local n
    local list = P.combo_steps(st.track, st.fx.addr, c.param, st.key)
    if type(list) == "table" then n = #list
    else
      local sn = P.step_norm(st.track, st.fx.addr, c.param, st.key)
      n = sn and (math.floor(1 / sn + 0.5) + 1) or nil
    end
    local ok = n and n >= 2 and n <= C.BUTTONS_MAX
    row_name("Show as")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    if not ok then ImGui.BeginDisabled(ctx, true) end
    local cur_b = (c.buttons == "across") and 1 or (c.buttons == "down") and 2 or 0
    local bch, bi = ImGui.Combo(ctx, "##show", cur_b, "Dropdown\0Buttons across\0Buttons down\0")
    if bch then
      c.buttons = (bi == 1) and "across" or (bi == 2) and "down" or nil
      c.nbtn = c.buttons and n or nil
    end
    if not ok then ImGui.EndDisabled(ctx) end
    tip(ok and "Show the choices as a row, or a column, of buttons, the current one lit."
      or ("Buttons are only for a parameter with 2 to %d choices."):format(C.BUTTONS_MAX))
  elseif c.type == "fader" then
    -- a fader's shape (Shape<n>): which way, how long, how thick
    row_name("Direction")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local dch, di = ImGui.Combo(ctx, "##way", c.dir == "h" and 1 or 0, "Up\0Across\0")
    if dch then c.dir = (di == 1) and "h" or nil end
    row_name("Length")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local lch, li = ImGui.Combo(ctx, "##len", c.len and (c.len - 2) or 3, "2\0" .. "3\0" .. "4\0Full\0")
    if lch then c.len = (li < 3) and (li + 2) or nil end
    tip("In rows (across: columns), or the full height (across: to the\npanel's right edge).")
    row_name("Thickness")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local tch2, ti2 = ImGui.Combo(ctx, "##thick", c.thin and 1 or 0, "Full\0Half\0")
    if tch2 then c.thin = (ti2 == 1) or nil end
    tip("A whole column (across: row) or half of one -- half for a row of\n" ..
      "faders side by side, a graphic EQ's bands say.")
  elseif c.type == "xy" then
    row_name("Size")
    local list = { "2x2", "3x2", "2x3", "3x3" }
    local now = 0
    for i, k in ipairs(list) do if k == (c.size or "2x2") then now = i - 1 end end
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local sch, si = ImGui.Combo(ctx, "##xysize", now, "2 \u{00d7} 2\0" .. "3 \u{00d7} 2\0" .. "2 \u{00d7} 3\0" .. "3 \u{00d7} 3\0")
    if sch then c.size = (si > 0) and list[si + 1] or nil end
    tip("Columns \u{00d7} rows.")
  elseif c.type == "dual" then
    row_name("Size")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local sch, si = ImGui.Combo(ctx, "##dsize", (c.size == "large") and 1 or 0, "Medium\0Large\0")
    if sch then c.size = (si == 1) and "large" or nil end
  end

  -- a divider: its line, and the section after it
  if c.type == "divider" then
    row_name("Line")
    local lch, lv = ImGui.Checkbox(ctx, "Draw the rule", not c.no_rule)
    if lch then c.no_rule = (not lv) or nil end
    tip("On: the usual rule between the two groups. Off: still ends\n" ..
      "the column and opens the same gap, just without the line --\n" ..
      "pure spacing, for groups that don't need a line between them.")
    local names, keys = { "None", "Inset" }, { "", "inset" }
    for _, pl in ipairs(C.PLATES) do
      if pl.bg then names[#names + 1] = "Plate: " .. pl.label; keys[#keys + 1] = pl.key end
    end
    custom_choices(names, keys, "Plate: ", (c.style == "plate") and c.cap or nil)
    local cur_s = 0
    for i, k in ipairs(keys) do
      if (k == "inset" and c.style == "inset") or (c.style == "plate" and k == c.cap) then cur_s = i - 1 end
    end
    row_name("Section")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local sch, si = ImGui.Combo(ctx, "##section", cur_s, table.concat(names, "\0") .. "\0")
    if sch then
      local k = keys[si + 1]
      if k == "" then c.style, c.cap, c.brush, c.metal = nil, nil, nil, nil
      elseif k == "inset" then c.style, c.cap = "inset", nil
      elseif k == "+" then pick_custom(c, "section")
      else c.style, c.cap = "plate", k end
    end
    tip("An inset, or a faceplate of their own, behind the\n" ..
      "controls after this divider, up to the next one.")
    local spl = (c.style == "plate") and C.plate_of(c.cap) or nil
    local skind = (c.style == "inset" and "inset") or (spl and "plate") or nil
    if skind then row_name("Finish"); brush_box(ctx, c, skind, spl, "sec_brush") end
  else
    -- its own background (an inset or a faceplate), joined with neighbours'
    local names, keys = { "None", "Inset" }, { "", "inset" }
    for _, pl in ipairs(C.PLATES) do
      if pl.bg then names[#names + 1] = pl.label; keys[#keys + 1] = pl.key end
    end
    custom_choices(names, keys, "", c.back)
    local cur_b = 0
    for i, k in ipairs(keys) do if k ~= "" and k == c.back then cur_b = i - 1 end end
    row_name("Background")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local bch, bi = ImGui.Combo(ctx, "##back", cur_b, table.concat(names, "\0") .. "\0")
    if bch then
      local k = keys[bi + 1]
      if k == "+" then pick_custom(c, "back")
      else
        c.back = (k ~= "") and k or nil
        if not c.back then c.brush, c.metal = nil, nil end
      end
    end
    tip("This control's own background. Neighbours with the same one\n" ..
      "join into one shape, across a divider too.")
    local bpl = (c.back and c.back ~= "inset") and C.plate_of(c.back) or nil
    local bkind = (c.back == "inset" and "inset") or (bpl and "plate") or nil
    if bkind then row_name("Finish"); brush_box(ctx, c, bkind, bpl, "back_brush") end
  end

  -- the ticks
  if is_param then
    row_name("Options")
    local any = false
    local function gap() if any then ImGui.SameLine(ctx, 0, 12) end any = true end
    if not two then
      gap()
      local bch, bv = ImGui.Checkbox(ctx, "Centred", c.bipolar and true or false)
      if bch then c.bipolar = bv end
      tip("Fill the knob outward from 12 o'clock instead of from the minimum.")
    end
    -- reverse: knobs, buttons, and both halves of a two-parameter control.
    -- A dropdown's entries are positions in the plugin's own scale, so
    -- reversing one means reversing the list -- a different job.
    local rev_tip = "Turn it the other way: what the plugin calls minimum sits\n" ..
      "at the top. For parameters wired backwards -- a \"threshold\" that\n" ..
      "opens as it falls, a mix control labelled dry. The plugin still\n" ..
      "sees its own value; only the control is flipped."
    if c.type == "knob" or c.type == "toggle" or c.type == "stepped" then
      gap()
      local rch, rv = ImGui.Checkbox(ctx, "Reverse", c.invert and true or false)
      if rch then c.invert = rv or nil end
      tip(rev_tip)
    elseif two then
      local a, b = (c.type == "xy") and "X" or "ring", (c.type == "xy") and "Y" or "inner"
      gap()
      local rch, rv = ImGui.Checkbox(ctx, "Reverse " .. a, c.invert and true or false)
      if rch then c.invert = rv or nil end
      tip(rev_tip)
      gap()
      local r2, v2 = ImGui.Checkbox(ctx, "Reverse " .. b, c.invert2 and true or false)
      if r2 then c.invert2 = v2 or nil end
      tip(rev_tip)
    end
    -- two reverses fill the row: live name goes under them
    if two then row_name(""); any = false end
    gap()
    if st.scratch.live then ImGui.BeginDisabled(ctx, true) end
    local vch, vv = ImGui.Checkbox(ctx, "Live name", live)
    if vch then c.live = vv or nil end
    if st.scratch.live then ImGui.EndDisabled(ctx) end
    tip(st.scratch.live and
      "On for every control: \"Live parameter names\" is ticked above." or
      "Show whatever the plugin calls this parameter right now, instead\n" ..
      "of the label or alias -- for plugins that rename their parameters\n" ..
      "as you use them. Currently: " .. (pname ~= "" and pname or "?"))
  end
end

local function refresh_names(track)
  local now = reaper.time_precise()
  if st.names_at and now - st.names_at < 0.5 then return end
  st.names_at = now
  for _, p in ipairs(st.params or {}) do
    local _, nm = reaper.TrackFX_GetParamName(track, st.fx.addr, p.index, "")
    nm = U.trim(nm or "")
    p.name = (nm ~= "") and nm or ("Param " .. p.index)
  end
end

local function poll_learn(track)
  if not st.learn then return end
  local ok, trnum, fxnum, param = reaper.GetLastTouchedFX()
  if not ok then return end
  local tr = (trnum == 0) and reaper.GetMasterTrack(0)
                          or reaper.GetTrack(0, trnum - 1)
  if tr ~= track then return end
  if fxnum ~= st.fx.addr then return end
  if param < 0 then return end
  if assigned_has(param) then return end
  add_param(track, param)
end

-- ---------------------------------------------------------------------

-- Returns "saved", "cancelled", or nil while still open.
function E.draw(ctx, track)
  if not st.open then return nil end

  if st.request then
    ImGui.OpenPopup(ctx, TITLE)
    st.request = false
  end

  -- Auto-size rather than a fixed guess: the dialog then always fits its
  -- contents exactly, and stays right if the list height or the button row
  -- ever changes.
  -- Barely dim the window behind. This dialog has an Apply button whose
  -- whole job is to let you look at the panel while you edit, and the
  -- default modal scrim puts a heavy wash over the thing you are trying
  -- to look at. Pushed and popped either side of Begin, which is where
  -- the scrim is drawn, so the pair balances whether or not the popup is
  -- visible this frame.
  ImGui.PushStyleColor(ctx, ImGui.Col_ModalWindowDimBg, 0x0a0d1233)
  local visible, open = ImGui.BeginPopupModal(ctx, TITLE, true,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_AlwaysAutoResize)
  ImGui.PopStyleColor(ctx)
  local result = nil

  if visible then
    poll_learn(track)
    refresh_names(track)

    ImGui.Text(ctx, U.clean_fx_name(st.fx.name) .. (st.fx.alias and ("  (" .. st.fx.alias .. ")") or ""))
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, ("\u{2014}  saved as \"%s\", used by every instance of this plugin")
      :format(st.key))

    -- Panel-level, so it sits above the lists rather than inside them: a
    -- plugin has one gain reduction, not one per parameter. The three
    -- choices on one line; what goes with a ticked one on the lines under.
    local meter_on, measure_on = false, false
    local first = true
    local function next_tick() if not first then ImGui.SameLine(ctx, 0, 18) end first = false end
    if st.reports_gr then
      next_tick()
      meter_on = (st.scratch.meter ~= nil) and st.scratch.meter.on or false
      local mch, mv = ImGui.Checkbox(ctx, "Gain reduction meter", meter_on)
      if mch then
        st.scratch.meter = st.scratch.meter or { range = C.MAX_GR_DB }
        st.scratch.meter.on = mv
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "A strip on the panel showing the plugin's own gain reduction.")
      end
    elseif not RQ.is_eq(st.key) then
      -- Not offered for ReaEQ: an EQ has no reduction to measure.
      next_tick()
      measure_on = st.scratch.measure == true
      local mch, mv = ImGui.Checkbox(ctx, "Measure gain reduction (estimated)", measure_on)
      if mch then
        st.scratch.measure = mv or nil
        st.scratch.meter = st.scratch.meter or { range = C.MAX_GR_DB }
        st.scratch.meter.on = mv
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx,
          "This plugin doesn't report gain reduction to REAPER, so it's\n" ..
          "measured instead: a copy of the audio going in and coming out is\n" ..
          "routed on spare channels (5/6 up) to the track's post TS_TrackProbe.\n" ..
          "Every instance between a probe pair is measured.\n\n" ..
          "An estimate. Its zero -- what \"no reduction\" looks like -- is\n" ..
          "measured each time playback stops, with a second of quiet test\n" ..
          "noise that you don't hear. A plugin at 50% mix reads about half.")
      end
    end
    -- Input and output meters: any plugin, reporting or not, measured by
    -- the track's probes from the same copies the reduction is.
    next_tick()
    local lch, lv = ImGui.Checkbox(ctx, "Input/output meters", st.scratch.levels == true)
    if lch then st.scratch.levels = lv or nil end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Two slim meters on the panel -- what goes into the plugin and what\n" ..
        "comes out -- and under them how much it changes the level (output\n" ..
        "RMS minus input RMS). Measured by the track's TS_TrackProbe pair,\n" ..
        "for every instance between the probes, up to four per track\n" ..
        "together with plugins measured for gain reduction.")
    end
    -- For plugins that rename their own parameters.
    next_tick()
    local lvch, lvv = ImGui.Checkbox(ctx, "Live parameter names", st.scratch.live and true or false)
    if lvch then st.scratch.live = lvv or nil end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Every control shows what the plugin calls its parameter right now,\n" ..
        "instead of a saved label or alias. For plugins that rename their\n" ..
        "parameters as you use them, like Softube Console 1 and Flow, whose\n" ..
        "macros take the names of whatever is loaded into them.")
    end

    -- what goes with them
    if (meter_on or measure_on) and st.scratch.meter then
      ImGui.SetNextItemWidth(ctx, 120)
      local rch, rv = ImGui.SliderDouble(ctx, "full scale",
        st.scratch.meter.range or C.MAX_GR_DB, 3, 40, "%.0f dB")
      if rch then st.scratch.meter.range = rv end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx,
          "How much reduction fills the strip. A bus compressor wants a\n" ..
          "small range; a limiter wants a large one.")
      end
    end
    if measure_on then
      -- Where this instance stands.
      local status = st.track and TP.status(st.track, st.fx.guid) or "ok"
      if status == "no_probes" then
        ImGui.TextDisabled(ctx, "This track has no TS_TrackProbe pair to measure with.")
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Add probes") then
          local ok, why = TP.insert_probes(st.track)
          if not ok then reaper.MB(why, "ChannelView", 0) end
        end
      elseif status == "outside" then
        ImGui.TextDisabled(ctx, "Not between this track's probes, so not measured here.")
      elseif status == "parallel" then
        ImGui.TextDisabled(ctx, "Not measured while it runs in parallel.")
      end
      -- The zero: global, since it's how the probes behave on every track.
      local zch, zv = ImGui.Checkbox(ctx, "Measure the zero while stopped (all tracks)", TP.zero_on())
      if zch then TP.set_zero_on(zv) end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx,
          "Each time playback stops, the pre probe plays a second of quiet\n" ..
          "pink noise (-60 and -50 dBFS) through the chain while the post probe\n" ..
          "stays silent, and that is taken as \"no reduction\". Without it the\n" ..
          "zero is learnt from the music, and a compressor that never lets go\n" ..
          "reads low.\n\n" ..
          "Needs REAPER's \"Run FX when stopped\". Waits for a second of\n" ..
          "silence and gives way the moment you play or anything arrives --\n" ..
          "but on an instrument track played while stopped, the first note\n" ..
          "after a stop can be swallowed. Turn it off if that bothers you.")
      end
      if st.track and st.fx then
        local cs = TP.cal_status(st.track, st.fx.guid)
        if cs then ImGui.TextDisabled(ctx, TP.cal_text(cs)) end
      end
    end
    if st.scratch.levels and st.track and st.fx then
      local status = TP.status(st.track, st.fx.guid)
      if status == "no_probes" then
        ImGui.TextDisabled(ctx, "Input/output meters need a TS_TrackProbe pair:")
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Add probes##lv") then
          local ok, why = TP.insert_probes(st.track)
          if not ok then reaper.MB(why, "ChannelView", 0) end
        end
      elseif status == "outside" then
        ImGui.TextDisabled(ctx, "Input/output meters: not between this track's probes.")
      elseif status == "parallel" then
        ImGui.TextDisabled(ctx, "Input/output meters: not measured while it runs in parallel.")
      end
    end

    ImGui.Separator(ctx)

    -- three columns: the panel's controls, the plugin's parameters, and
    -- the selected control's settings -- so the window grows down, not
    -- out to the right
    local list_w, list_h = 300, 280
    ImGui.BeginGroup(ctx)
    draw_assigned(ctx, track, list_w, list_h)
    ImGui.EndGroup(ctx)

    ImGui.SameLine(ctx, 0, 16)

    ImGui.BeginGroup(ctx)
    draw_available(ctx, track, list_w, list_h)
    ImGui.EndGroup(ctx)

    ImGui.SameLine(ctx, 0, 18)

    ImGui.BeginGroup(ctx)
    draw_entry_editor(ctx)
    ImGui.EndGroup(ctx)

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Save", 90) then
      M.set(st.key, st.scratch)
      TP.invalidate()
      M.save()
      st.was_saved = true
      result = "saved"
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    -- Live, not saved. The panel behind the dialog picks it up on the
    -- next frame because it reads the mapping every frame, so you can
    -- watch a layout take shape instead of saving, looking, reopening
    -- and guessing again.
    if ImGui.Button(ctx, "Apply", 90) then
      M.set(st.key, M.copy(st.scratch))
      TP.invalidate()
      st.applied = true
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Show it on the panel now, without writing to the library.\n" ..
        "Cancel still puts everything back.")
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 90) then
      revert_applied()
      result = "cancelled"
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx, 0, 24)
    if ImGui.Button(ctx, "Auto-fill", 90) then
      local aliases = st.scratch.aliases          -- names you've set are kept
      local meter   = st.scratch.meter
      local live    = st.scratch.live
      st.scratch = M.build_default(track, st.fx.addr)
      st.scratch.aliases = aliases
      st.scratch.meter   = meter
      st.scratch.live    = live
      st.sel_asg = math.min(1, #st.scratch.controls)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, ("Replace with the plugin's first %d parameters.")
        :format(C.AUTO_DEFAULT_N))
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Clear all", 90) then
      st.scratch = { controls = {}, aliases = st.scratch.aliases,
                     meter = st.scratch.meter, live = st.scratch.live }
      st.sel_asg = 0
    end
    ImGui.SameLine(ctx, 0, 24)
    ImGui.TextDisabled(ctx, ("%d controls"):format(#st.scratch.controls))

    ImGui.EndPopup(ctx)
  end

  if not open then
    -- Closed with the title-bar X or Escape rather than the button.
    -- Same meaning, so the same undo.
    revert_applied()
    result = result or "cancelled"
  end
  if result then st.open = false end
  return result
end

return E
