-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Editor.lua -- "Setup Edit Parameters".

  Two lists and an Add/Remove pair, same shape as the dialog in the
  reference screenshot: everything the plugin exposes on the right,
  what the panel actually shows on the left, in panel order.

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

local E = {}
local ImGui

local TITLE = "Setup Edit Parameters"

local TYPES       = { "knob", "toggle", "combo", "blank", "divider" }
local TYPES_COMBO = "knob\0toggle\0combo\0blank\0divider\0"

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
}

function E.attach(imgui) ImGui = imgui end
function E.is_open() return st.open end

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
  st.reports_gr = require("TS_CV_FXTree").reports_gr(track, fx.addr, fx.guid)
  st.params    = load_params(track, fx)
  st.was_saved = false
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
    label   = nm,
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
      else
        local shown = c.label
        if not shown or shown == "" then shown = st.scratch.aliases[c.param] end
        if not shown or shown == "" then shown = pname end
        label = ("%2d  %-14s  %-6s  %s"):format(i,
          U.truncate(shown, 14), c.type, pname)
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
  if ImGui.Button(ctx, "\u{25B2} Up", 52) and sel > 1 then
    move_control(sel, sel - 1)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "\u{25BC} Down", 62) and sel >= 1 and sel < n then
    move_control(sel, sel + 1)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Add gap", 60) then
    local at = (sel >= 1 and sel < n) and (sel + 1) or (n + 1)
    table.insert(st.scratch.controls, at,
      { param = -1, type = "blank", bipolar = false, label = "" })
    st.sel_asg = at
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "An empty cell, for spacing a layout out like a hardware strip.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Add divider", 78) then
    local at = (sel >= 1 and sel < n) and (sel + 1) or (n + 1)
    table.insert(st.scratch.controls, at,
      { param = -1, type = "divider", bipolar = false, label = "" })
    st.sel_asg = at
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "A rule between groups of controls. Ends the current column,\n" ..
      "so it separates sections rather than taking a cell.")
  end
end

local function draw_available(ctx, track, list_w, list_h)
  ImGui.Text(ctx, "Plugin parameters")
  ImGui.SetNextItemWidth(ctx, list_w)
  local ch, f = ImGui.InputTextWithHint(ctx, "##filter", "filter\u{2026}", st.filter)
  if ch then st.filter = f end

  local needle = st.filter:lower()
  if ImGui.BeginListBox(ctx, "##available", list_w, list_h) then
    for _, p in ipairs(st.params or {}) do
      local alias_l = (st.scratch.aliases[p.index] or ""):lower()
      local show = needle == ""
        or p.name:lower():find(needle, 1, true)
        or (alias_l ~= "" and alias_l:find(needle, 1, true))
      if show then
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

local function draw_entry_editor(ctx)
  local c = st.scratch.controls[st.sel_asg]
  ImGui.SeparatorText(ctx, "Selected control")
  if not c then
    ImGui.TextDisabled(ctx, "Nothing selected.")
    return
  end

  local pname = ""
  for _, p in ipairs(st.params or {}) do
    if p.index == c.param then pname = p.name break end
  end

  if c.type ~= "blank" and c.type ~= "divider" then
    ImGui.SetNextItemWidth(ctx, 170)
    local ach, av = ImGui.InputTextWithHint(ctx, "Alias",
      pname ~= "" and pname or "name\u{2026}", st.scratch.aliases[c.param] or "")
    if ach then
      av = U.trim(av)
      st.scratch.aliases[c.param] = (av ~= "") and av or nil
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Your name for this parameter. Applies to this plugin everywhere,\n" ..
        "whether or not the parameter is on a panel. Clear it to go back to\n" ..
        "what the plugin calls it: " .. (pname ~= "" and pname or "?"))
    end

    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 130)
    local ch, v = ImGui.InputTextWithHint(ctx, "Label", "this slot only", c.label or "")
    if ch then c.label = v end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Overrides the alias for THIS slot only. Leave empty unless a\n" ..
        "cramped layout needs a shorter caption here.")
    end

    ImGui.SameLine(ctx)
  end

  local cur = 0
  for i, t in ipairs(TYPES) do if t == c.type then cur = i - 1 break end end
  ImGui.SetNextItemWidth(ctx, 100)
  local tch, ti = ImGui.Combo(ctx, "Type", cur, TYPES_COMBO)
  if tch then c.type = TYPES[ti + 1] or "knob" end

  if c.type ~= "blank" and c.type ~= "divider" then
    ImGui.SameLine(ctx)
    local bch, bv = ImGui.Checkbox(ctx, "Centred", c.bipolar and true or false)
    if bch then c.bipolar = bv end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Fill the knob outward from 12 o'clock instead of from the minimum.")
    end
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
  local visible, open = ImGui.BeginPopupModal(ctx, TITLE, true,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_AlwaysAutoResize)
  local result = nil

  if visible then
    poll_learn(track)

    ImGui.Text(ctx, U.clean_fx_name(st.fx.name))
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, ("\u{2014}  saved as \"%s\", used by every instance of this plugin")
      :format(st.key))

    -- Panel-level, so it sits above the two lists rather than inside them:
    -- a plugin has one gain reduction, not one per parameter.
    if st.reports_gr then
      local on = (st.scratch.meter ~= nil) and st.scratch.meter.on or false
      local mch, mv = ImGui.Checkbox(ctx, "Gain reduction meter", on)
      if mch then
        st.scratch.meter = st.scratch.meter or { range = C.MAX_GR_DB }
        st.scratch.meter.on = mv
      end
      if on then
        ImGui.SameLine(ctx)
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
    else
      ImGui.TextDisabled(ctx, "This plugin doesn't report gain reduction.")
    end

    ImGui.Separator(ctx)

    local list_w, list_h = 330, 280
    ImGui.BeginGroup(ctx)
    draw_assigned(ctx, track, list_w, list_h)
    ImGui.EndGroup(ctx)

    ImGui.SameLine(ctx, 0, 16)

    ImGui.BeginGroup(ctx)
    draw_available(ctx, track, list_w, list_h)
    ImGui.EndGroup(ctx)

    draw_entry_editor(ctx)

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Save", 90) then
      M.set(st.key, st.scratch)
      M.save()
      st.was_saved = true
      result = "saved"
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 90) then
      result = "cancelled"
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx, 0, 24)
    if ImGui.Button(ctx, "Auto-fill", 90) then
      local aliases = st.scratch.aliases          -- names you've set are kept
      local meter   = st.scratch.meter
      st.scratch = M.build_default(track, st.fx.addr)
      st.scratch.aliases = aliases
      st.scratch.meter   = meter
      st.sel_asg = math.min(1, #st.scratch.controls)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, ("Replace with the plugin's first %d parameters.")
        :format(C.AUTO_DEFAULT_N))
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Clear all", 90) then
      st.scratch = { controls = {}, aliases = st.scratch.aliases,
                     meter = st.scratch.meter }
      st.sel_asg = 0
    end
    ImGui.SameLine(ctx, 0, 24)
    ImGui.TextDisabled(ctx, ("%d controls"):format(#st.scratch.controls))

    ImGui.EndPopup(ctx)
  end

  if not open then
    result = result or "cancelled"
  end
  if result then st.open = false end
  return result
end

return E
