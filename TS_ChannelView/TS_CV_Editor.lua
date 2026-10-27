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
local ST = require("TS_CV_Style")
local U = require("TS_CV_Util")
local M = require("TS_CV_Mappings")
local CP = require("TS_CV_ColourPick")
local TP = require("TS_CV_Taps")
local RQ = require("TS_CV_ReaEQ")
local RC = require("TS_CV_ReaComp")
local St = require("TS_CV_State")
-- (Pro: virtual controls, Show when, switching rules, other layouts,
-- canvases -- greyed or left out here without it; what a layout has of
-- them is kept)
local ED = require("TS_CV_Edition")

local E = {}
local ImGui

local TITLE = "Setup Edit Parameters"

local TYPES       = { "knob", "toggle", "combo", "stepped", "fader", "xy", "dual", "blank", "half_gap", "divider", "page" }
-- on a grid (the grid editor's sheet) a gap is empty space and a divider
-- or section is drawn on the grid: the controls only
local GRID_TYPES  = { "knob", "toggle", "combo", "stepped", "fader", "xy", "dual" }
local TYPE_NAMES = { knob = "Knob", toggle = "Button", combo = "Dropdown", stepped = "Stepped knob",
                     fader = "Fader", xy = "XY pad", dual = "Concentric knob", blank = "Gap",
                     half_gap = "Half gap", divider = "Divider", page = "Page", section = "Section" }
-- the virtual controls (TS_CV_Mappings Virt<n>): no parameter behind
-- them, drawn as the type they're kept as
local VIRT_KINDS = { "toggle", "combo", "knob" }
local VIRT_NAMES = { toggle = "Virtual button", combo = "Virtual selector", knob = "Virtual knob" }
local VIRT_DEFAULT = { toggle = "More", combo = "View", knob = "Amount" }
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

-- The colours of your own that a Background or Section combo offers
-- after the faceplates: the one it has now, the recent ones
-- (TS_CV_ColourPick), and "Custom colour..." -- key "+" -- which opens
-- the picker. Appends to `names` and `keys`, `prefix` before each name.
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

function E.open(track, fx, key, layout, focus)
  -- a locked layout takes no edits (unlocked from the panel's padlock)
  if M.locked(layout) then return end
  st.open      = true
  st.request   = true
  st.key       = key
  st.fx        = { addr = fx.addr, guid = fx.guid, name = fx.name }
  st.scratch   = M.copy(layout or { controls = {}, aliases = {} })
  st.scratch.aliases = st.scratch.aliases or {}
  st.sel_asg   = math.min(1, #st.scratch.controls)
  -- opened from a control's right-click: that control, scrolled to
  if focus and st.scratch.controls[focus] then st.sel_asg, st.scroll_sel = focus, true end
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
  table.insert(st.scratch.controls, at, M.apply_default_look({
    param   = param,
    type    = U.guess_control_type(track, st.fx.addr, param),
    bipolar = U.guess_bipolar(nm, track, st.fx.addr, param),
    label   = "",          -- the name shows by itself; a label would hide an alias
  }))
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
  ST.caption(ctx, "Panel  \u{2014}  drag a row to reorder")

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
      elseif c.type == "page" then
        label = ("%2d  \u{25A3} page%s"):format(i, (c.label and c.label ~= "") and (": " .. c.label) or "")
      elseif c.type == "blank" then
        label = ("%2d  \u{2014} blank \u{2014}"):format(i)
      elseif c.type == "half_gap" then
        label = ("%2d  \u{2044} half gap"):format(i)
      elseif M.is_virtual(c) then
        label = ("%2d  \u{25C6} %-14s  %s"):format(i, U.truncate(M.vname_of(c), 14), VIRT_NAMES[c.type] or "Virtual")
      else
        local shown = c.label
        if c.live or st.scratch.live then shown = pname end
        if not shown or shown == "" then shown = st.scratch.aliases[c.param] end
        if not shown or shown == "" then shown = pname end
        label = ("%2d  %-16s  %s"):format(i, U.truncate(shown, 16), TYPE_NAMES[c.type] or c.type)
      end
      -- a conditional control: shown only while another parameter reads a given way
      if c.show and c.type ~= "page" then label = label .. "  \u{25D0}" end

      if ImGui.Selectable(ctx, label .. "##asg" .. i, st.sel_asg == i) then
        st.sel_asg = i
      end
      if st.scroll_sel and st.sel_asg == i then ImGui.SetScrollHereY(ctx, 0.5); st.scroll_sel = nil end

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

  if ST.button(ctx, "Remove >>", "remove", 90) then
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
    ImGui.SetTooltip(ctx, "An empty cell, for spacing.")
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
      "Staggers the next control half a row down.\n" ..
      "Column layouts only.")
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
      "A rule between groups; ends the column.\n" ..
      "Select it below to hide the line.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Page", 50) then
    local at = (sel >= 1 and sel < n) and (sel + 1) or (n + 1)
    table.insert(st.scratch.controls, at,
      { param = -1, type = "page", bipolar = false, label = "" })
    st.sel_asg = at
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "A page break: what follows is a new tab.\n" ..
      "Select it below to name and colour the tab.")
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, not ED.PRO)
  local add_virt = ImGui.Button(ctx, ED.PRO and "Virtual" or "Virtual (Pro)", ED.PRO and 60 or 0)
  ImGui.EndDisabled(ctx)
  if not ED.PRO then ED.note(ImGui, ctx) end
  if add_virt then
    local at = (sel >= 1 and sel < n) and (sel + 1) or (n + 1)
    table.insert(st.scratch.controls, at, E.new_virtual("toggle", st.scratch.controls))
    st.sel_asg = at
  end
  if ED.PRO and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "A button, selector or knob with no parameter behind it.\n" ..
      "Rules can follow it; each instance keeps its own setting.")
  end
end

local function draw_available(ctx, track, list_w, list_h)
  ST.caption(ctx, "Plugin parameters")
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
  local lch, lv = ST.checkbox(ctx, "Learn", st.learn)
  if lch then st.learn = lv end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "Touch a control in the plugin's window to add it.")
  end
end

-- ---------------------------------------------------------------------
-- rules: a control's Show when, and the plugin's layout switching
-- ---------------------------------------------------------------------
-- A rule reads a source: one of the plugin's parameters, or a virtual
-- control (TS_CV_Mappings Virt<n>) by its name.

-- A parameter's choices when it has a few (a switch, a dropdown, a
-- stepped knob), else nil: it's continuous, and takes a slider. Also the
-- tolerance a rule on one of them wants. `controls`: the layout's, where
-- one placed as a button counts as a switch.
local function param_choices(tr, addr, p, controls, key)
  local P = require("TS_CV_Panel")
  local list = P.button_choices(tr, addr, p, key or st.key, nil)
  if #list >= 2 and #list <= 64 then
    local step = list[2].norm - list[1].norm
    return list, math.max(0.0005, step * 0.5 - 0.0005)
  end
  -- a two-state switch: the plugin reports a step as big as the whole
  -- range (or says it's a toggle), which reads as "no steps" above;
  -- one placed on the panel as a button counts too
  local ok, step, _, _, istog = reaper.TrackFX_GetParameterStepSizes(tr, addr, p)
  local switch = ok and (istog or (step and step >= 1))
  if not switch then
    for _, o in ipairs(controls or {}) do
      if o.param == p and o.type == "toggle" then switch = true break end
    end
  end
  if not switch then return nil end
  local function say(n, dflt)
    if reaper.TrackFX_FormatParamValueNormalized then
      local fok, sv = reaper.TrackFX_FormatParamValueNormalized(tr, addr, p, n, "")
      if fok and U.trim(sv or "") ~= "" then return U.trim(sv) end
    end
    return dflt
  end
  local off, on = say(0, "Off"), say(1, "On")
  if off == on then off, on = "Off", "On" end
  return { { norm = 0, text = off }, { norm = 1, text = on } }, 0.499
end

-- A virtual control's choices, by the control: its button states or its
-- selector's list (half a step's tolerance), nil for a knob.
local function virt_choices(vc)
  local names = vc and M.vchoices(vc)
  if not names then return nil end
  local list = {}
  for i, t in ipairs(names) do list[i] = { norm = M.vnorm(vc, i), text = t } end
  local n = #list
  return list, (n >= 2) and math.max(0.0005, 0.5 / (n - 1) - 0.0005) or 0.499
end

-- The plugin's virtual controls, by name: those in `controls` (the
-- layout being edited) first, then those in its other layouts. { name, c }
local function virt_sources(controls, key)
  local out, seen = {}, {}
  local function add(list)
    for _, c in ipairs(list or {}) do
      if M.is_virtual(c) then
        local nm = M.vname_of(c)
        if not seen[nm] then seen[nm] = true; out[#out + 1] = { name = nm, c = c } end
      end
    end
  end
  add(controls)
  local base = M.split_variant(key or st.key or "")
  if base then
    local l = M.get(base); add(l and l.controls)
    for _, v in ipairs(M.variants(base)) do
      local lv = M.get(M.variant_key(base, v)); add(lv and lv.controls)
    end
  end
  return out
end

-- The list a source combo offers: virtual controls (◆) then parameters;
-- each { label, param, vname }. `skip`: a virtual control not to offer
-- (the one the rule is on).
local function source_list(tr, addr, controls, skip, first)
  local out = {}
  if first then out[1] = { label = first } end
  for _, vs in ipairs(virt_sources(controls)) do
    if vs.c ~= skip then out[#out + 1] = { label = "\u{25C6} " .. vs.name, param = -1, vname = vs.name, vc = vs.c } end
  end
  local n = reaper.TrackFX_GetNumParams(tr, addr)
  for p = 0, n - 1 do
    local _, pn = reaper.TrackFX_GetParamName(tr, addr, p, "")
    out[#out + 1] = { label = ("%d  %s"):format(p, (M.display_name(st.key, p, nil, pn, false):gsub("%z", ""))), param = p }
  end
  return out
end
local function source_index(list, r)
  if not r then return 0 end
  for i, e in ipairs(list) do
    if (r.vname and e.vname == r.vname) or (not r.vname and e.param ~= nil and e.vname == nil and e.param == r.param) then
      return i - 1
    end
  end
  return 0
end
local function source_names(list)
  local t = {}
  for i, e in ipairs(list) do t[i] = (e.label or ""):gsub("%z", "") end
  return table.concat(t, "\0") .. "\0"
end
-- a rule's source's choices and tolerance
local function rule_choices(tr, addr, r, controls)
  if r.vname then
    local vc
    for _, vs in ipairs(virt_sources(controls)) do if vs.name == r.vname then vc = vs.c end end
    return virt_choices(vc)
  end
  return param_choices(tr, addr, r.param, controls)
end
-- The sources the panel's right-click offers under Show when: the
-- layout's virtual controls with choices, then the parameters placed on
-- it as a button, dropdown or stepped knob -- each with its choices
-- ({ norm, text }) and tolerance. Anything else takes the editor.
-- { label, param, vname, choices, tol }
function E.show_sources(tr, addr, key, controls, skip)
  local out, seen = {}, {}
  for _, vs in ipairs(virt_sources(controls, key)) do
    if vs.c ~= skip then
      local list, tol = virt_choices(vs.c)
      if list then out[#out + 1] = { label = "\u{25C6} " .. vs.name, param = -1, vname = vs.name, choices = list, tol = tol } end
    end
  end
  for _, o in ipairs(controls or {}) do
    local p = o.param
    if o ~= skip and p and p >= 0 and not seen[p] and not M.is_virtual(o)
       and (o.type == "toggle" or o.type == "combo" or o.type == "stepped") then
      seen[p] = true
      local list, tol = param_choices(tr, addr, p, controls, key)
      if list and #list >= 2 and #list <= 24 then
        local _, pn = reaper.TrackFX_GetParamName(tr, addr, p, "")
        out[#out + 1] = { label = M.display_name(key, p, o.label, pn, false), param = p, choices = list, tol = tol }
      end
    end
  end
  return out
end

-- A rule as it starts on a source: a switch or dropdown at "is <its last
-- choice>", a knob at "above halfway"
local function rule_start(tr, addr, e, controls)
  local r = { param = e.param, vname = e.vname }
  local list, tol = rule_choices(tr, addr, r, controls)
  if list then r.op, r.norm, r.tol = "is", list[#list].norm, tol
  else r.op, r.norm, r.tol = "above", 0.5, 0.005 end
  return r
end

local OP_LABEL = { is = "is", ["not"] = "is not", above = "is above", below = "is below", between = "is between" }
-- The rule's operator and value(s): a dropdown of the source's choices,
-- or a slider showing what it reads as there. `row(text)` starts a row
-- for the "and" value of a between. Changes r.
local function rule_value_ui(ctx, id, tr, addr, r, controls, op_w, val_w, row)
  r.op = M.show_op(r); r.inv = nil
  local list, ctol = rule_choices(tr, addr, r, controls)
  local function value_field(fid, norm, w)
    ImGui.SetNextItemWidth(ctx, w)
    if list then
      local cur, best = 0, math.huge
      for k, e in ipairs(list) do
        local d = math.abs(e.norm - (norm or 0))
        if d < best then best, cur = d, k - 1 end
      end
      local opts = {}
      for k, e in ipairs(list) do opts[k] = (e.text or tostring(k)):gsub("%z", "") end
      local ch, i = ImGui.Combo(ctx, fid, cur, table.concat(opts, "\0") .. "\0")
      if ch then return list[i + 1].norm end
      return nil
    end
    local txt = ""
    if r.vname then txt = ("%d %%"):format(math.floor((norm or 0) * 100 + 0.5))
    elseif reaper.TrackFX_FormatParamValueNormalized then
      local ok, sv = reaper.TrackFX_FormatParamValueNormalized(tr, addr, r.param, norm or 0, "")
      if ok then txt = U.trim(sv or "") end
    end
    if txt == "" then txt = ("%.0f%%"):format((norm or 0) * 100) end
    local ch, v = ST.slider_double(ctx, fid, norm or 0, 0, 1, (txt:gsub("%%", "%%%%")))
    if ch then return v end
    return nil
  end
  local labels, cur_op = {}, 0
  for i, k in ipairs(M.SHOW_OPS) do
    labels[i] = OP_LABEL[k]
    if k == r.op then cur_op = i - 1 end
  end
  ImGui.SetNextItemWidth(ctx, op_w)
  local och, oi = ImGui.Combo(ctx, id .. "op", cur_op, table.concat(labels, "\0") .. "\0")
  local changed = false
  if och then
    r.op = M.SHOW_OPS[oi + 1]; changed = true
    if r.op == "between" and not r.norm2 then r.norm2 = list and list[#list].norm or 1 end
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "is / is not: that value\n" ..
      "is above / below: past it (not including it)\n" ..
      "is between: both ends included")
  end
  ImGui.SameLine(ctx, 0, 4)
  local v = value_field(id .. "v", r.norm, val_w)
  if v then r.norm = v; changed = true end
  local tol = list and ctol or 0.005
  if r.tol ~= tol then r.tol = tol end
  if r.op == "between" then
    row("and")
    local v2 = value_field(id .. "v2", r.norm2, val_w)
    if v2 then r.norm2 = v2; changed = true end
  else
    r.norm2 = nil
  end
  return changed
end

-- The selected control's settings, as a column: each on a row of its own,
-- its name captioned above it, and only the rows that apply to its type.
local COL_W   = 330          -- the column's width
local FIELD_W = 236          -- a field's width

-- A number as typed; "20k" is 20000.
function E.parse_num(t)
  t = U.trim((t or ""):lower())
  local n, k = t:match("^([%-%+]?%d*%.?%d+)%s*(k?)")
  n = tonumber(n or "")
  if not n then return nil end
  return (k == "k") and n * 1000 or n
end
-- The parameter's own range in the layout being edited, made when it has
-- none: from what the plugin reads at its ends when that's a number,
-- else 0 to 100.
-- (also the right-click's Values > Custom range, which starts the same way)
function E.range_start(track, addr, p)
  local lo, hi = 0, 100
  local UN = require("TS_CV_Units")
  if track and addr and reaper.TrackFX_FormatParamValueNormalized then
    local _, a = reaper.TrackFX_FormatParamValueNormalized(track, addr, p, 0, "")
    local _, b = reaper.TrackFX_FormatParamValueNormalized(track, addr, p, 1, "")
    local va, vb = UN.parse(a or ""), UN.parse(b or "")
    if va and vb and va ~= vb then lo, hi = va, vb end
  end
  return { lo = lo, hi = hi, unit = "", curve = "lin" }
end
function E.ensure_range(p)
  st.scratch.ranges = st.scratch.ranges or {}
  if st.scratch.ranges[p] then return st.scratch.ranges[p] end
  st.scratch.ranges[p] = E.range_start(st.track, st.fx and st.fx.addr, p)
  return st.scratch.ranges[p]
end

-- A new virtual control of a kind (TS_CV_Mappings Virt<n>), named so it
-- doesn't clash with one already in `controls`.
function E.new_virtual(kind, controls)
  local base, nm, k = VIRT_DEFAULT[kind] or "View", nil, 1
  repeat
    nm = (k == 1) and base or (base .. " " .. k)
    local taken = false
    for _, o in ipairs(controls or {}) do if M.is_virtual(o) and M.vname_of(o) == nm then taken = true end end
    k = k + 1
  until not taken
  local c = { param = -1, type = kind, bipolar = false, label = nm,
              virtual = { start = 0, choices = (kind == "combo") and { "Main", "Second" } or {} } }
  if kind == "combo" then c.buttons, c.nbtn = "across", 2 end
  return c
end

-- A virtual control's action being picked in REAPER's Action List:
-- { ctl, i = the setting it's for }. Polled every frame the dialog draws.
local vpick = nil
local function poll_vpick()
  if not vpick then return end
  local r = reaper.PromptForAction(0, 0, 0)
  if r == 0 then return end
  reaper.PromptForAction(-1, 0, 0)
  local p = vpick
  vpick = nil
  if r > 0 and p.ctl.virtual then
    p.ctl.virtual.actions = p.ctl.virtual.actions or {}
    p.ctl.virtual.actions[p.i] = require("TS_CV_Toolbar").stored_cmd(r)
  end
end
function E.cancel_vpick()
  if vpick then reaper.PromptForAction(-1, 0, 0) end
  vpick = nil
end

local draw_entry_body
-- The selected control's fields, keyed by the control: ImGui writes a
-- text field's last edit back on the frame it's let go, and that frame
-- can already be showing the next control -- whose alias would then be
-- the one you were typing (the Enter never pressed). By its place in the
-- list, which holds while it's being edited (the control's table may not).
local function draw_entry_editor(ctx)
  ImGui.PushID(ctx, "sel" .. tostring(st.sel_asg or 0))
  draw_entry_body(ctx)
  ImGui.PopID(ctx)
end
draw_entry_body = function(ctx)
  local c = st.scratch.controls[st.sel_asg]
  if not st.grid then
    ImGui.SeparatorText(ctx, "Selected control")
    -- the column keeps its width whatever is selected
    ImGui.Dummy(ctx, COL_W, 0)
  end
  if not c then
    ImGui.TextDisabled(ctx, "Nothing selected.")
    return
  end

  -- a row: its name captioned above it (TS_CV_Style); "" just starts
  -- the next line
  local function row_name(text)
    if text ~= "" then ST.caption(ctx, text) end
  end
  local function tip(text)
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then ImGui.SetTooltip(ctx, text) end
  end

  -- your own range for a parameter (Range<p>): low to high, its unit and
  -- curve, and Clear; for a plugin that won't say what its values are
  local function range_row(p)
    local rg = st.scratch.ranges and st.scratch.ranges[p]
    if not rg then return end
    st.rng_buf = st.rng_buf or {}
    local function num_field(id, v, w)
      ImGui.SetNextItemWidth(ctx, w)
      local bk = p .. id
      local ch, t = ImGui.InputText(ctx, id, st.rng_buf[bk] or ("%g"):format(v))
      if ch then
        st.rng_buf[bk] = t
        local n = E.parse_num(t)
        if n then return n end
      end
      if ImGui.IsItemDeactivated(ctx) then st.rng_buf[bk] = nil end
      return nil
    end
    row_name("Range")
    local lo = num_field("##rglo", rg.lo, 62)
    if lo then rg.lo = lo end
    ImGui.SameLine(ctx, 0, 4); ImGui.Text(ctx, "to"); ImGui.SameLine(ctx, 0, 4)
    local hi = num_field("##rghi", rg.hi, 62)
    if hi then rg.hi = hi end
    ImGui.SameLine(ctx, 0, 4)
    local ucur = 0
    for i, u_ in ipairs(U.RANGE_UNITS) do if u_ == (rg.unit or "") then ucur = i - 1 end end
    local unames = {}
    for i, u_ in ipairs(U.RANGE_UNITS) do unames[i] = (u_ == "") and "none" or u_ end
    ImGui.SetNextItemWidth(ctx, 58)
    local uch, ui = ImGui.Combo(ctx, "##rgunit", ucur, table.concat(unames, "\0") .. "\0")
    if uch then rg.unit = U.RANGE_UNITS[ui + 1] end
    row_name("")
    local ccur = (rg.curve == "log") and 1 or (rg.curve == "sq") and 2 or 0
    ImGui.SetNextItemWidth(ctx, 92)
    local cch, ci = ImGui.Combo(ctx, "##rgcurve", ccur, "Linear\0Log\0Squared\0")
    if cch then rg.curve = U.RANGE_CURVES[ci + 1] end
    tip("How it runs between its ends.\n" ..
      "Linear: evenly. Log: frequencies, times. Squared: slow then fast.")
    ImGui.SameLine(ctx, 0, 4)
    ImGui.TextDisabled(ctx, "now " .. U.range_text(rg, (st.track and st.fx)
      and reaper.TrackFX_GetParamNormalized(st.track, st.fx.addr, p) or 0))
    ImGui.SameLine(ctx, 0, 8)
    if ST.button(ctx, "Clear##rgclr", "remove") then st.scratch.ranges[p] = nil end
    tip("Back to the plugin's own values.")
  end
  -- a control without a scale of numbers: the plugin's own values, or yours
  local function values_row(p)
    -- (not for several at once: a range is the parameter's)
    if not p or p < 0 or st.multi then return end
    row_name("Values")
    local has = st.scratch.ranges and st.scratch.ranges[p]
    ImGui.SetNextItemWidth(ctx, 100)
    local vch, vi = ImGui.Combo(ctx, "##vals", has and 1 or 0, "Plugin's\0Custom\0")
    if vch then
      if vi == 1 then E.ensure_range(p) elseif st.scratch.ranges then st.scratch.ranges[p] = nil end
    end
    tip("Custom: your own range, for a plugin that doesn't report its values.")
    range_row(p)
  end

  local pname = ""
  for _, p in ipairs(st.params or {}) do
    if p.index == c.param then pname = p.name break end
  end
  local is_param = c.type ~= "blank" and c.type ~= "divider" and c.type ~= "half_gap" and c.type ~= "page"
  local two = c.type == "xy" or c.type == "dual"
  local virt = M.is_virtual(c)

  -- what it controls (several at once, in the grid editor: what they
  -- share, so none of what makes each its own)
  if is_param and not virt and not st.multi then
    row_name((c.type == "xy") and "X parameter" or (c.type == "dual") and "Ring" or "Parameter")
    ImGui.Text(ctx, ("%s  %s"):format(tostring(c.param), pname))
  end
  -- an XY pad's Y or a concentric knob's inner knob (Dual<n>)
  if two and st.track and st.fx and not st.multi then
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
    tip((c.type == "xy") and "The pad's vertical parameter."
      or "The inner knob's parameter.")
  end

  -- what it is (on a grid: a control, and a virtual one stays virtual,
  -- having no parameter chosen to become)
  local types = st.grid and (virt and {} or GRID_TYPES) or TYPES
  local vkinds = ((st.multi or not ED.PRO) and not virt) and {} or VIRT_KINDS
  local show_type = not ((st.multi or not ED.PRO) and virt)
  -- on a grid a page break (or a line, a gap, a section) is only that:
  -- nothing to turn it into
  local structural = { page = true, divider = true, blank = true, half_gap = true, section = true }
  if st.grid and structural[c.type] then show_type = false end
  if show_type then row_name("Type") end
  local cur = 0
  for i, t in ipairs(types) do if t == c.type then cur = i - 1 break end end
  if virt then
    for i, t in ipairs(vkinds) do if t == c.type then cur = #types + i - 1 end end
  end
  local tnames = {}
  for i, t in ipairs(types) do tnames[i] = TYPE_NAMES[t] or t end
  for _, t in ipairs(vkinds) do tnames[#tnames + 1] = VIRT_NAMES[t] end
  local tch, ti = false, cur
  if show_type then
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    tch, ti = ImGui.Combo(ctx, "##type", cur, table.concat(tnames, "\0") .. "\0")
  end
  -- (picking what it is already changes nothing: a virtual one picked
  -- again would otherwise start over)
  if tch and ti == cur then tch = false end
  if tch and ti >= #types then
    -- a virtual one: its name and settings kept where they can be
    local kind = vkinds[ti - #types + 1]
    local nv = E.new_virtual(kind, st.scratch.controls)
    if virt then
      nv.label = c.label
      if kind == "combo" and c.type == "combo" then nv.virtual.choices = c.virtual.choices end
    end
    local keep = { show = c.show, back = c.back, brush = c.brush, metal = c.metal, finish = c.finish, corners = c.corners, at = c.at }
    for k in pairs(c) do c[k] = nil end
    for k, v in pairs(nv) do c[k] = v end
    for k, v in pairs(keep) do c[k] = v end
    virt, is_param, two = true, true, false
  elseif tch then
    local was = c.type
    if virt then
      -- a parameter's control again: the parameter chosen on the right
      c.virtual, c.buttons, c.nbtn = nil, nil, nil
      c.param = (st.sel_avail and st.sel_avail >= 0) and st.sel_avail or 0
      virt = false
    end
    c.type = types[ti + 1] or "knob"
    -- sizes don't carry between an XY pad and anything else; a concentric
    -- knob is never small; a second parameter starts as the next one along
    if (c.type == "xy") ~= (was == "xy") or (c.type == "dual" and c.size == "small") then c.size = nil end
    if (c.type == "xy" or c.type == "dual") and not c.param2 and c.param and st.track and st.fx then
      local n = reaper.TrackFX_GetNumParams(st.track, st.fx.addr)
      c.param2 = (c.param + 1 < n) and (c.param + 1) or c.param
    end
    is_param = c.type ~= "blank" and c.type ~= "divider" and c.type ~= "half_gap" and c.type ~= "page"
    two = c.type == "xy" or c.type == "dual"
  end

  -- its names. A live name overrides both; they stay as they are, just
  -- greyed, so turning live off again brings them back.
  local live = is_param and not virt and (c.live or st.scratch.live) or false
  if virt and not st.multi and ED.PRO then
    -- its name (what rules find it by), its settings, where it starts
    row_name("Name")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local nch, nv = ImGui.InputText(ctx, "##vname", c.label or "")
    if nch then c.label = nv end
    local nm = M.vname_of(c)
    local twice = 0
    for _, o in ipairs(st.scratch.controls) do if M.is_virtual(o) and M.vname_of(o) == nm then twice = twice + 1 end end
    tip("Rules find it by this name; same-named ones in other\n" ..
      "layouts share its setting." .. (twice > 1 and "\nTwo here share this name: rename one." or ""))
    if twice > 1 then ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.COL.warn, "!") end
    if c.type == "toggle" then
      row_name("States")
      local ch1, ch2 = c.virtual.choices[1] or "", c.virtual.choices[2] or ""
      ImGui.SetNextItemWidth(ctx, (FIELD_W - 4) * 0.5)
      local a1, v1 = ImGui.InputTextWithHint(ctx, "##vs1", "Off", ch1)
      ImGui.SameLine(ctx, 0, 4)
      ImGui.SetNextItemWidth(ctx, (FIELD_W - 4) * 0.5)
      local a2, v2 = ImGui.InputTextWithHint(ctx, "##vs2", "On", ch2)
      if a1 or a2 then
        v1, v2 = U.trim(a1 and v1 or ch1), U.trim(a2 and v2 or ch2)
        c.virtual.choices = (v1 ~= "" or v2 ~= "") and { v1 ~= "" and v1 or "Off", v2 ~= "" and v2 or "On" } or {}
      end
      tip("Its two states' names (Basic / Advanced, say).")
    elseif c.type == "combo" then
      row_name("Choices")
      ImGui.SetNextItemWidth(ctx, FIELD_W)
      st.vchoice_text = st.vchoice_text or {}
      local key = tostring(c)
      local now = st.vchoice_text[key] or table.concat(c.virtual.choices or {}, " | ")
      local cch, cv = ImGui.InputTextWithHint(ctx, "##vchoices", "Main | Sidechain | Advanced", now)
      if cch then
        st.vchoice_text[key] = cv
        local list = {}
        for part in (cv .. "|"):gmatch("([^|]*)|") do
          part = U.trim(part:gsub("[;\r\n]", " "))
          if part ~= "" then list[#list + 1] = part end
        end
        if #list >= 1 then c.virtual.choices = list end
        if c.buttons then c.nbtn = math.max(2, #M.vchoices(c)) end
      end
      if ImGui.IsItemDeactivated(ctx) then st.vchoice_text[key] = nil end
      tip("Its choices, with | between them.")
      row_name("Shown as")
      ImGui.SetNextItemWidth(ctx, FIELD_W)
      local cur_b = (c.buttons == "across") and 0 or (c.buttons == "down") and 1 or 2
      local bch, bi = ImGui.Combo(ctx, "##vshow", cur_b, "Chips across\0Chips down\0Dropdown\0")
      if bch then
        c.buttons = (bi == 0) and "across" or (bi == 1) and "down" or nil
        c.nbtn = c.buttons and math.max(2, #M.vchoices(c)) or nil
      end
    elseif c.type == "knob" then
      if not st.grid then  -- (on a grid: the size of its place)
        row_name("Size")
        local now = 1
        for i, k in ipairs(C.SIZE_LIST) do if k == (c.size or "medium") then now = i - 1 end end
        ImGui.SetNextItemWidth(ctx, FIELD_W)
        local sch, si = ImGui.Combo(ctx, "##vsize", now, SIZES_COMBO)
        if sch then
          local k = C.SIZE_LIST[si + 1]
          c.size = (k ~= "medium") and k or nil
        end
      end
    end
    row_name("Starts at")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local names = M.vchoices(c)
    if names then
      local opts = {}
      for i, t in ipairs(names) do opts[i] = t:gsub("%z", "") end
      local sch, si = ImGui.Combo(ctx, "##vstart", M.vindex(c, c.virtual.start) - 1, table.concat(opts, "\0") .. "\0")
      if sch then c.virtual.start = M.vnorm(c, si + 1) end
    else
      local sch, sv = ST.slider_double(ctx, "##vstart", c.virtual.start or 0, 0, 1,
        ("%d %%%%"):format(math.floor((c.virtual.start or 0) * 100 + 0.5)))
      if sch then c.virtual.start = sv end
    end
    tip("Its default (Double-click: back to it).")

    -- a REAPER action for each setting, run when it's picked (VAct<n>)
    local names2 = (c.type ~= "knob") and M.vchoices(c) or nil
    if names2 then
      local TB = require("TS_CV_Toolbar")
      ImGui.Spacing(ctx)
      row_name("Actions")
      ImGui.TextDisabled(ctx, "run as each is picked")
      tip("A REAPER action for any of its settings, run when you pick\n" ..
          "that setting on the panel or the web page.")
      for i, t in ipairs(names2) do
        local cmd = c.virtual.actions and c.virtual.actions[i]
        row_name(U.truncate((t:gsub("%z", "")), 12))
        local text
        if vpick and vpick.ctl == c and vpick.i == i then
          text = "Pick in the Action List\u{2026}"
        elseif cmd then
          text = TB.action_name(TB.resolve(cmd)) or ("not found: " .. cmd)
        else
          text = "None"
        end
        local bw = FIELD_W - (cmd and 26 or 0)
        if ImGui.Button(ctx, U.truncate(text, 30) .. "##vact" .. i, bw, 0) then
          if vpick then reaper.PromptForAction(-1, 0, 0) end
          vpick = { ctl = c, i = i }
          reaper.PromptForAction(1, 0, 0)
        end
        tip(cmd and (text .. "\nClick: change it") or "Click: pick an action")
        if cmd then
          ImGui.SameLine(ctx, 0, 4)
          if ST.button(ctx, "\u{00D7}##vactx" .. i, "remove", 22, 0) then
            c.virtual.actions[i] = nil
            if next(c.virtual.actions) == nil then c.virtual.actions = nil end
          end
          tip("No action")
        end
      end
    end
  end
  if is_param and not virt and not st.multi then
    if live then ImGui.BeginDisabled(ctx, true) end
    row_name("Alias")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local ach, av = ImGui.InputTextWithHint(ctx, "##alias",
      pname ~= "" and pname or "name\u{2026}", st.scratch.aliases[c.param] or "")
    if ach then
      av = U.trim(av)
      st.scratch.aliases[c.param] = (av ~= "") and av or nil
    end
    tip("Your name for this parameter, for this plugin everywhere.\n" ..
      "Clear for the plugin's own: " .. (pname ~= "" and pname or "?"))
    row_name("Label")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local ch, v = ImGui.InputTextWithHint(ctx, "##label", "this slot only", c.label or "")
    if ch then c.label = v end
    tip("Overrides the alias for this slot only.")
    if live then ImGui.EndDisabled(ctx) end
  end

  -- its size and shape
  if virt then
    if c.type == "toggle" then
      if not st.grid then  -- (on a grid: the size of its place)
        row_name("Size")
        ImGui.SetNextItemWidth(ctx, FIELD_W)
        local sch, si = ImGui.Combo(ctx, "##tsize", (c.size == "small") and 0 or 1, TOGGLE_SIZES_COMBO)
        if sch then c.size = (si == 0) and "small" or nil end
      end
    end
  elseif c.type == "knob" or c.type == "stepped" then
    if not st.grid then  -- (on a grid: the size of its place)
      row_name("Size")
      local now = 1
      for i, k in ipairs(C.SIZE_LIST) do if k == (c.size or "medium") then now = i - 1 end end
      ImGui.SetNextItemWidth(ctx, FIELD_W)
      local sch, si = ImGui.Combo(ctx, "##size", now, SIZES_COMBO)
      if sch then
        local k = C.SIZE_LIST[si + 1]
        c.size = (k ~= "medium") and k or nil
      end
      tip("Small: half height, value in the tooltip; two stack in a cell.\n" ..
        "Large: half again as big.")
    end
    -- numbers round the dial (Scale<n>; values unless it says otherwise),
    -- then what the values read as (Range<p>) -- the right-click's Values.
    -- Their colour is a look: right-click > Style.
    row_name("Scale")
    local kind = M.scale_kind(c)
    ImGui.SetNextItemWidth(ctx, 100)
    local scch, sci = ImGui.Combo(ctx, "##scale", (kind == "values") and 1 or (kind == "ten") and 2 or 0,
      "None\0Values\0" .. "0\u{2013}10\0")
    if scch then
      c.scale = (sci == 0) and "none" or (sci == 2) and "ten" or nil
      if c.scale == "none" then c.scale_ink = nil end
    end
    tip("Numbers round the dial: its values, or 0 to 10.\n" ..
      "Not on small knobs.")
    values_row(c.param)
  elseif c.type == "toggle" then
    if not st.grid then  -- (on a grid: the size of its place)
      row_name("Size")
      ImGui.SetNextItemWidth(ctx, FIELD_W)
      local sch, si = ImGui.Combo(ctx, "##tsize", (c.size == "small") and 0 or 1, TOGGLE_SIZES_COMBO)
      if sch then c.size = (si == 0) and "small" or nil end
      tip("Small: half height, all button; two stack in a cell.")
    end
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
    tip(ok and "Show the choices as buttons, the current one lit."
      or ("Only for 2 to %d choices."):format(C.BUTTONS_MAX))
  elseif c.type == "fader" then
    values_row(c.param)
    -- a fader's shape (Shape<n>): which way, how long, how thick (on a
    -- grid its place says which way and how long)
    if not st.grid then
      row_name("Direction")
      ImGui.SetNextItemWidth(ctx, FIELD_W)
      local dch, di = ImGui.Combo(ctx, "##way", c.dir == "h" and 1 or 0, "Up\0Across\0")
      if dch then c.dir = (di == 1) and "h" or nil end
      row_name("Length")
      ImGui.SetNextItemWidth(ctx, FIELD_W)
      local lch, li = ImGui.Combo(ctx, "##len", c.len and (c.len - 2) or 3, "2\0" .. "3\0" .. "4\0Full\0")
      if lch then c.len = (li < 3) and (li + 2) or nil end
      tip("In rows (across: columns), or full height (across: full width).")
    end
    if not st.grid then  -- (on a grid: the size of its place)
      row_name("Thickness")
      ImGui.SetNextItemWidth(ctx, FIELD_W)
      local tch2, ti2 = ImGui.Combo(ctx, "##thick", c.thin and 1 or 0, "Full\0Half\0")
      if tch2 then c.thin = (ti2 == 1) or nil end
      tip("A whole column (across: row), or half for faders side by side.")
    end
  elseif c.type == "xy" and not st.grid then
    row_name("Size")
    local list = { "2x2", "3x2", "2x3", "3x3" }
    local now = 0
    for i, k in ipairs(list) do if k == (c.size or "2x2") then now = i - 1 end end
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local sch, si = ImGui.Combo(ctx, "##xysize", now, "2 \u{00d7} 2\0" .. "3 \u{00d7} 2\0" .. "2 \u{00d7} 3\0" .. "3 \u{00d7} 3\0")
    if sch then c.size = (si > 0) and list[si + 1] or nil end
    tip("Columns \u{00d7} rows.")
  elseif c.type == "dual" then
    values_row(c.param)
    if not st.grid then  -- (on a grid: the size of its place)
      row_name("Size")
      ImGui.SetNextItemWidth(ctx, FIELD_W)
      local sch, si = ImGui.Combo(ctx, "##dsize", (c.size == "large") and 1 or 0, "Medium\0Large\0")
      if sch then c.size = (si == 1) and "large" or nil end
    end
  end

  -- a page break: the tab's name and its stripe's colour
  if c.type == "page" then
    row_name("Tab name")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local ch, v = ImGui.InputTextWithHint(ctx, "##pglabel", "unnamed: its number", c.label or "")
    if ch then c.label = (v ~= "") and v or nil end
    tip("The tab's name. Everything up to the next break is one page.")
    row_name("Tab colour")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local keys, names, now = { "" }, { "Theme" }, 0
    for i, ck in ipairs(C.CAPS) do
      keys[#keys + 1] = ck.key; names[#names + 1] = ck.label
      if ck.key == c.cap then now = i end
    end
    if c.cap and now == 0 then keys[#keys + 1] = c.cap; names[#names + 1] = c.cap; now = #keys - 1 end
    local cch, ci = ImGui.Combo(ctx, "##pgcap", now, table.concat(names, "\0") .. "\0")
    if cch then c.cap = (ci > 0) and keys[ci + 1] or nil end
    tip("The stripe over the tab's name.\n" ..
      "Right-click the tab on the panel: full colour picker.")
  end

  -- a divider: its line, and the section after it
  if c.type == "divider" then
    row_name("Line")
    local lch, lv = ST.checkbox(ctx, "Draw the rule", not c.no_rule)
    if lch then c.no_rule = (not lv) or nil end
    tip("A line between the groups. Off: the same gap, no line.")
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
      if k == "" then c.style, c.cap, c.brush, c.metal, c.finish, c.corners = nil, nil, nil, nil, nil, nil
      elseif k == "inset" then c.style, c.cap = "inset", nil
      elseif k == "+" then pick_custom(c, "section")
      else c.style, c.cap = "plate", k end
    end
    tip("An inset or faceplate behind the controls up to the next divider.")
    -- (its finish, flake and corners are a look: right-click > Section)
  elseif c.type ~= "page" and not st.grid then
    -- its own background (an inset or a faceplate), joined with neighbours'
    -- (a page break draws nothing of its own, so it has none; on a grid
    -- the grid editor's sheet has it in full)
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
        if not c.back then c.brush, c.metal, c.finish, c.corners = nil, nil, nil, nil end
      end
    end
    tip("This control's background. Matching neighbours join up.")
    -- (its finish is a look: right-click > Background)
  end

  -- shown only while a parameter, or one of the layout's virtual
  -- controls, reads a given way (Show<n>)
  if c.type ~= "page" and st.track and st.fx and ED.PRO then
    local tr, addr = st.track, st.fx.addr
    local list = source_list(tr, addr, st.scratch.controls, c, "Always")
    row_name("Show when")
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local sch, si = ImGui.Combo(ctx, "##showp", source_index(list, c.show), source_names(list))
    if sch then
      local e = list[si + 1]
      if not e or (e.param == nil and e.vname == nil) then c.show = nil
      else c.show = rule_start(tr, addr, e, st.scratch.controls) end
    end
    tip("Show only while a parameter (or virtual control, \u{25C6}) reads a given way.\n" ..
      "A hidden control takes no cell.")
    if c.show then
      row_name("")
      rule_value_ui(ctx, "##show", tr, addr, c.show, st.scratch.controls, 92, FIELD_W - 96,
        function(t) row_name(t) end)
    end
  end

  -- the ticks
  if is_param and not virt then
    row_name("Options")
    local any = false
    local function gap() if any then ImGui.SameLine(ctx, 0, 12) end any = true end
    if not two then
      gap()
      local bch, bv = ST.checkbox(ctx, "Centred", c.bipolar and true or false)
      if bch then c.bipolar = bv end
      tip("Fill from 12 o'clock instead of the minimum.")
    end
    -- reverse: knobs, buttons, and both halves of a two-parameter control.
    -- A dropdown's entries are positions in the plugin's own scale, so
    -- reversing one means reversing the list -- a different job.
    local rev_tip = "Flip the control: the plugin's minimum at the top.\n" ..
      "For parameters wired backwards."
    if c.type == "knob" or c.type == "toggle" or c.type == "stepped" then
      gap()
      local rch, rv = ST.checkbox(ctx, "Reverse", c.invert and true or false)
      if rch then c.invert = rv or nil end
      tip(rev_tip)
    elseif two then
      local a, b = (c.type == "xy") and "X" or "ring", (c.type == "xy") and "Y" or "inner"
      gap()
      local rch, rv = ST.checkbox(ctx, "Reverse " .. a, c.invert and true or false)
      if rch then c.invert = rv or nil end
      tip(rev_tip)
      gap()
      local r2, v2 = ST.checkbox(ctx, "Reverse " .. b, c.invert2 and true or false)
      if r2 then c.invert2 = v2 or nil end
      tip(rev_tip)
    end
    -- two reverses fill the row: live name goes under them
    if two then row_name(""); any = false end
    gap()
    if st.scratch.live then ImGui.BeginDisabled(ctx, true) end
    local vch, vv = ST.checkbox(ctx, "Live name", live, { dim = st.scratch.live and true or nil })
    if vch then c.live = vv or nil end
    if st.scratch.live then ImGui.EndDisabled(ctx) end
    tip(st.scratch.live and
      "On for every control (\"Live parameter names\" above)." or
      "Show the plugin's current name for it, not the label or alias.\n" ..
      "Currently: " .. (pname ~= "" and pname or "?"))
  end

  -- a button's own words for its two states, for this plugin everywhere
  -- (States<p>), as the right-click's Name > State names
  if is_param and not virt and c.type == "toggle" and not st.multi then
    st.scratch.states = st.scratch.states or {}
    local sn = st.scratch.states[c.param] or { "", "" }
    local function hint(v)
      if st.track and st.fx and reaper.TrackFX_FormatParamValueNormalized then
        local ok, t = reaper.TrackFX_FormatParamValueNormalized(st.track, st.fx.addr, c.param, v, "")
        if ok and t and t ~= "" then return t end
      end
      return v < 0.5 and "off" or "on"
    end
    row_name("State names")
    ImGui.SetNextItemWidth(ctx, 96)
    local c1, v1 = ImGui.InputTextWithHint(ctx, "##snoff", hint(0), sn[1] or "")
    ImGui.SameLine(ctx, 0, 6)
    ImGui.SetNextItemWidth(ctx, 96)
    local c2, v2 = ImGui.InputTextWithHint(ctx, "##snon", hint(1), sn[2] or "")
    if c1 or c2 then
      local off, on = U.trim(c1 and v1 or sn[1] or ""), U.trim(c2 and v2 or sn[2] or "")
      -- (kept untrimmed while typing, so a space can go between words)
      local raw = { c1 and v1 or sn[1] or "", c2 and v2 or sn[2] or "" }
      st.scratch.states[c.param] = (off ~= "" or on ~= "") and raw or nil
    end
    tip("Off, then on, for this plugin everywhere.\n" ..
      "Leave empty for the plugin's own text.")
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

local function edited()
  return M.signature(st.scratch) ~= M.signature(st.original)
end
local function switch_to(track, key)
  local l = M.get(key)
  if not l then
    local base = M.split_variant(key)
    l = M.get_or_default(base, track, st.fx.addr, st.fx.guid)
  end
  E.open(track, st.fx, key, l)
  st.request = false        -- already open: don't open it again
end
-- Which layout is being edited, at the top of the window: the plugin's
-- default or one of its variants (TS_CV_Mappings "<plugin> :: <name>"),
-- the one this instance shows. Switching here switches the instance;
-- Copy to new and New empty make a variant from what's in the editor
-- (unsaved edits go to the new one, the old one is left as it was).
local function draw_layout_row(ctx, track)
  local RB = require("TS_CV_ReaFX")
  if RB.own_eq(st.key) or RB.own_comp(st.key) or not ED.PRO then return end
  local base, cur = M.split_variant(st.key)
  ST.cap(ctx, "Layout")
  ImGui.SetNextItemWidth(ctx, 180)
  local dflt = M.default_variant(base)
  if ImGui.BeginCombo(ctx, "##edlayout", cur or "Standard") then
    local list = { { name = nil, label = "Standard" .. (dflt == nil and "  (default)" or "") } }
    for _, nm in ipairs(M.variants(base)) do
      list[#list + 1] = { name = nm, label = nm .. (dflt == nm and "  (default)" or "") }
    end
    for i, e in ipairs(list) do
      local k = M.variant_key(base, e.name)
      local locked = M.locked(M.get(k)) ~= nil
      if locked then ImGui.BeginDisabled(ctx, true) end
      if ImGui.Selectable(ctx, e.label .. (locked and "  (locked)" or "") .. "##edl" .. i, e.name == cur)
         and e.name ~= cur then
        if not edited() or reaper.MB("Leave this layout without saving your changes?",
                                     "ChannelView", 1) == 1 then
          revert_applied()
          St.set_variant(st.fx.guid, e.name or St.OWN)
          switch_to(track, k)
        end
      end
      if locked then ImGui.EndDisabled(ctx) end
    end
    ImGui.EndCombo(ctx)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "The layout this instance shows (and you're editing).\n" ..
      "Set the default from a panel's menu: Layout \u{25B8} Make \"\u{2026}\" the default.")
  end
  ST.done(ctx)
  ImGui.SameLine(ctx, 0, 16)
  ST.cap(ctx, "New layout")
  ImGui.SetNextItemWidth(ctx, 170)
  -- (not EnterReturnsTrue: with it ImGui only hands the text back on
  -- Enter, so the buttons would always see an empty name)
  local _, txt = ImGui.InputTextWithHint(ctx, "##ednewvar", "new layout's name", st.var_name or "")
  local ch = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
             or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
  st.var_name = txt
  ST.done(ctx)
  local nm = M.clean_variant(txt)
  local ok = nm ~= nil and not M.has(M.variant_key(base, nm))
  local function make(empty)
    local from = M.copy(st.scratch)
    local k, made = M.new_variant(base, txt, from, empty)
    if not k then return end
    revert_applied()          -- the old layout keeps what it had
    St.set_variant(st.fx.guid, made)
    st.var_name = nil
    switch_to(track, k)
  end
  if ch and ok then make(false) end
  ImGui.SameLine(ctx)
  ST.cap(ctx)
  if not ok then ImGui.BeginDisabled(ctx, true) end
  if ImGui.Button(ctx, "Copy to new layout") then make(false) end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, ok and "Save the editor's contents as a new layout for this instance.\n" ..
      "The original stays as it was."
      or "Type a name first.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "New empty layout") then make(true) end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, ok and "A new empty layout for this instance.\n" ..
      "Your parameter names come with it."
      or "Type a name first.")
  end
  if not ok then ImGui.EndDisabled(ctx) end
  ST.done(ctx)
end

-- The plugin's layout switching (TS_CV_Mappings Switch<n>): an ordered
-- list of "use <layout> when <source> <op> <value>", the first that
-- matches winning. The plugin's, not this layout's -- the same whichever
-- layout is being edited -- so it's saved as it's changed, apart from
-- the layout's own Save.
local function draw_switch_rules(ctx, track)
  local RB = require("TS_CV_ReaFX")
  if RB.own_eq(st.key) or RB.own_comp(st.key) or not (track and st.fx) or not ED.PRO then return end
  local base = M.split_variant(st.key)
  local rules = M.copy_rules(M.switch_rules(base)) or {}
  -- (in the grid editor, a window of their own: always open)
  if not st.grid then
    local label = (st.rules_open and "\u{25BE}" or "\u{25B8}") .. "  Switch layouts automatically"
      .. ((#rules > 0) and ("  (%d)"):format(#rules) or "")
    if ImGui.Button(ctx, label .. "##swr") then st.rules_open = not st.rules_open end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Show another layout while a parameter or virtual control\n" ..
        "reads a given way. First match wins.")
    end
    if not st.rules_open then return end
  end
  local addr = st.fx.addr
  local changed, drop = false, nil
  -- the layouts a rule can put up
  local names = { "Standard" }
  local lays = { false }
  for _, nm in ipairs(M.variants(base)) do names[#names + 1] = nm; lays[#lays + 1] = nm end
  local lay_combo = table.concat(names, "\0") .. "\0"
  local srcs = source_list(track, addr, st.scratch.controls, nil, nil)
  local src_combo = source_names(srcs)
  local active = St.switch_rule(st.fx.guid)
  for i, r in ipairs(rules) do
    ImGui.PushID(ctx, "swr" .. i)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, (active == i) and C.COL.accent or C.COL.header_dim, tostring(i))
    if active == i and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Active on this instance.") end
    ImGui.SameLine(ctx); ImGui.Text(ctx, "Use"); ImGui.SameLine(ctx)
    local cur = 0
    for k, nm in ipairs(lays) do if (nm or nil) == r.layout then cur = k - 1 end end
    ImGui.SetNextItemWidth(ctx, 130)
    local lch, li = ImGui.Combo(ctx, "##lay", cur, lay_combo)
    if lch then r.layout = lays[li + 1] or nil; changed = true end
    ImGui.SameLine(ctx); ImGui.Text(ctx, "when"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 150)
    local sch, si = ImGui.Combo(ctx, "##src", source_index(srcs, r), src_combo)
    if sch and srcs[si + 1] then
      local nr = rule_start(track, addr, srcs[si + 1], st.scratch.controls)
      nr.layout = r.layout
      rules[i] = nr; r = nr; changed = true
    end
    ImGui.SameLine(ctx)
    if rule_value_ui(ctx, "##rv", track, addr, r, st.scratch.controls, 84, 110,
        function(t) ImGui.SameLine(ctx); ImGui.Text(ctx, t); ImGui.SameLine(ctx) end) then changed = true end
    ImGui.SameLine(ctx)
    if ST.button(ctx, "\u{2715}", "remove") then drop = i end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Remove this rule") end
    ImGui.PopID(ctx)
  end
  if drop then table.remove(rules, drop); changed = true end
  if ImGui.Button(ctx, "+ Add a rule") and #srcs > 0 then
    local r = rule_start(track, addr, srcs[1], st.scratch.controls)
    r.layout = lays[2] or nil
    rules[#rules + 1] = r
    changed = true
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, "Otherwise: the layout the instance is set to.")
  if changed then
    M.set_switch_rules(base, rules, function()
      return M.copy(M.get_or_default(base, track, addr, st.fx.guid))
    end)
  end
end

-- Panel-level, so it sits above the lists rather than inside them: a
-- plugin has one gain reduction, not one per parameter. The three
-- choices on one line; what goes with a ticked one on the lines under.
local function draw_meters(ctx)
  local meter_on, measure_on = false, false
  local first = true
  -- (narrow, in the grid editor's sheet: one to a line)
  local function next_tick() if not first and not st.narrow then ImGui.SameLine(ctx, 0, 18) end first = false end
  if st.reports_gr then
    next_tick()
    meter_on = (st.scratch.meter ~= nil) and st.scratch.meter.on or false
    local mch, mv = ST.checkbox(ctx, "Gain reduction meter", meter_on)
    if mch then
      st.scratch.meter = st.scratch.meter or { range = C.MAX_GR_DB }
      st.scratch.meter.on = mv
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Shows the plugin's own gain reduction on the panel.")
    end
  elseif not RQ.is_eq(st.key) then
    -- Not offered for ReaEQ: an EQ has no reduction to measure.
    next_tick()
    measure_on = st.scratch.measure == true
    local mch, mv = ST.checkbox(ctx, "Measure gain reduction (estimated)", measure_on)
    if mch then
      st.scratch.measure = mv or nil
      st.scratch.meter = st.scratch.meter or { range = C.MAX_GR_DB }
      st.scratch.meter.on = mv
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Estimates gain reduction (the plugin doesn't report it)\n" ..
        "via the track's TS_TrackProbe pair. At 50% mix it reads about half.")
    end
  end
  -- Input and output meters: any plugin, reporting or not, measured by
  -- the track's probes from the same copies the reduction is.
  next_tick()
  local lch, lv = ST.checkbox(ctx, "Input/output meters", st.scratch.levels == true)
  if lch then st.scratch.levels = lv or nil end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "Input and output meters, and the level change (RMS).\n" ..
      "Measured by the track's TS_TrackProbe pair.")
  end
  -- For plugins that rename their own parameters.
  next_tick()
  local lvch, lvv = ST.checkbox(ctx, "Live parameter names", st.scratch.live and true or false)
  if lvch then st.scratch.live = lvv or nil end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "Show the plugin's current parameter names, not saved labels.\n" ..
      "For plugins that rename them (Softube Console 1, Flow).")
  end

  -- what goes with them
  if (meter_on or measure_on) and st.scratch.meter then
    ImGui.SetNextItemWidth(ctx, 120)
    local rch, rv = ST.slider_double(ctx, "Full scale##grrange",
      st.scratch.meter.range or C.MAX_GR_DB, 3, 40, "%.0f dB")
    if rch then st.scratch.meter.range = rv end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "How much reduction fills the strip.\n" ..
        "Small for a bus compressor, large for a limiter.")
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
    local zch, zv = ST.checkbox(ctx, "Measure the zero while stopped (all tracks)", TP.zero_on())
    if zch then TP.set_zero_on(zv) end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "On stop, plays a second of quiet noise to learn \"no reduction\"\n" ..
        "(needs \"Run FX when stopped\"). Can swallow a note played while stopped.")
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

end

-- Where the plugin being edited is now: its track still there, and the
-- plugin found by its GUID (it may have moved in the chain). Updates
-- st.fx.addr; false when either has gone.
local function still_there()
  local tr = st.track
  if not (tr and reaper.ValidatePtr2(0, tr, "MediaTrack*")) then return false end
  if reaper.TrackFX_GetFXGUID(tr, st.fx.addr) == st.fx.guid then return true end
  for _, fx in ipairs(require("TS_CV_FXTree").collect(tr)) do
    if fx.guid == st.fx.guid then st.fx.addr = fx.addr; return true end
  end
  return false
end

-- The editor's parts for the grid editor's sheet (TS_CV_GridEditor),
-- drawn with `env` as their state: scratch (the layout being edited),
-- sel_asg (the control), params, track, fx, key, reports_gr; grid and
-- narrow set. Its own fields (text being typed) stay in it between frames.
local function embedded(env, fn, ...)
  local saved = st
  st = env
  local ok, err = pcall(fn, ...)
  st = saved
  if not ok then error(err, 0) end
end
-- the selected control's settings
function E.entry_for(ctx, env)
  embedded(env, function() poll_vpick(); draw_entry_editor(ctx) end)
end
-- the meters and live names
function E.meters_for(ctx, env) embedded(env, draw_meters, ctx) end
-- the plugin's layout switching
function E.rules_for(ctx, env) embedded(env, draw_switch_rules, ctx, env.track) end
-- how many switching rules the plugin has
function E.rule_count(key)
  return #(M.switch_rules((M.split_variant(key))) or {})
end

-- `_selected` is the track selected now, which is not necessarily the
-- one the dialog is editing: the dialog works on the track it was opened
-- for (st.track), whatever is selected meanwhile -- and closes, putting
-- back anything applied, if that track or its plugin goes away (deleted,
-- the project closed or switched).
-- Returns "saved", "cancelled", or nil while still open.
function E.draw(ctx, _selected)
  if not st.open then return nil end
  -- gone: put back anything applied (the library, not the track, so this
  -- holds either way) and close, from inside the popup so ImGui lets go
  if not still_there() then
    revert_applied()
    st.open, st.request = false, false
    if ImGui.BeginPopupModal(ctx, TITLE, true, ImGui.WindowFlags_NoCollapse) then
      ImGui.CloseCurrentPopup(ctx)
      ImGui.EndPopup(ctx)
    end
    return "cancelled"
  end
  local track = st.track
  poll_vpick()

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
    do
      local _, var = M.split_variant(st.key)
      ImGui.TextDisabled(ctx, (var and "\u{2014}  saved as \"%s\", used by every instance set to this layout"
                                    or "\u{2014}  saved as \"%s\", used by every instance on the default layout")
        :format(st.key))
    end
    draw_layout_row(ctx, track)
    -- an EQ or Compressor layout's canvas: its own setup page
    if st.scratch and st.scratch.canvas and ED.PRO then
      ImGui.SameLine(ctx, 0, 16)
      local kind = st.scratch.canvas.kind == "eq" and "EQ"
                   or ((M.CANVAS_NAMES[st.scratch.canvas.kind] or "compressor"):lower())
      ST.cap(ctx)
      if ImGui.Button(ctx, "Set up the " .. kind .. " canvas\u{2026}") then
        local go = true
        if edited() then
          local a = reaper.MB("Save your changes to this layout first?", "ChannelView", 3)
          if a == 6 then
            M.set(st.key, st.scratch); TP.invalidate(); M.save()
            st.was_saved = true; result = "saved"
          elseif a == 7 then
            revert_applied(); result = "cancelled"
          else
            go = false
          end
        else
          revert_applied(); result = "cancelled"
        end
        if go then
          require("TS_CV_CanvasSetup").open(st.track, st.fx, st.key)
          ImGui.CloseCurrentPopup(ctx)
        end
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Choose the controls the canvas uses" ..
          (kind == "EQ" and ", and learn its bands." or "."))
      end
      ST.done(ctx)
    end
    draw_switch_rules(ctx, track)

    draw_meters(ctx)

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
    if ST.button(ctx, "Save", "main", 90) then
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
        "Preview on the panel without saving.\n" ..
        "Cancel still reverts.")
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
    if ST.button(ctx, "Clear all", "remove", 90) then
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
