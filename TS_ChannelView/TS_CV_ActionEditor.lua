-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ActionEditor.lua -- the Organise actions window: every action bar
  ChannelView has, in one place.

  Lists the drawers (TS_CV_Drawers), the TCP's two toolbars and the web
  companion's Actions bar. For the one picked, its buttons as a tree:
  drag a row to move it, drop it ON a menu to put it inside; add actions
  (REAPER's Action List), menus, separators and gaps; import a REAPER
  toolbar or menu; and set a button's label and icon.

  The TCP's toolbars are edited through toolbar instances of their own
  (TS_CV_Toolbar.make with the TCP's keys); the TCP script, running beside
  this, sees the revision move and reloads.

  The web companion's bar is the page's own list, a JSON array in
  ExtState TS_CV_WEB/macros: { l = label, a = action, c = colour },
  { sp = 1 } a spacer, and { m = 1, l, c, i = [ ... ] } a menu. It goes
  through a toolbar instance with its own store, so the tree, the picker
  and the import work on it the same way. The web has no icons, and its
  separators and gaps are both spacers.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local TB = require("TS_CV_Toolbar")
local DR = require("TS_CV_Drawers")
local FB = require("TS_CV_FXButtons")
local B  = require("TS_CV_Browser")
local CN = require("TS_CV_Chains")
-- (vendor looks: Pro)
local ED = require("TS_CV_Edition")
local VN = ED.module("TS_CV_Vendors")
local CPk = require("TS_CV_ColourPick")

local AE = {}
local ImGui
function AE.attach(imgui) ImGui = imgui; B.attach(imgui); CN.attach(imgui) end

-- the web page's button colours (CAPS in TS_ChannelView.html)
AE.CAPS = TB.COLOURS

-- The web list's JSON lives with the bars (TS_CV_Drawers); these
-- aliases are for the tests.
AE.json_decode = DR.json_decode
AE.json_encode_list = DR.json_encode_list
AE.from_web, AE.to_web = DR.from_web, DR.to_web

-- ---------------------------------------------------------------------
-- the bars
-- ---------------------------------------------------------------------

-- Every bar, in the order of their places (drawers, windows, the TCP's,
-- the web's, nowhere), each { d, name, tb }.
local ORDER = {}
for i, p in ipairs(DR.PLACES) do ORDER[p] = i end
local function all_bars()
  local out = {}
  for _, d in ipairs(DR.list) do
    out[#out + 1] = { d = d, name = (d.name ~= "" and d.name or ("Bar " .. d.id)), tb = d.tb }
  end
  table.sort(out, function(a, b)
    local oa, ob = ORDER[a.d.side] or 99, ORDER[b.d.side] or 99
    if oa ~= ob then return oa < ob end
    return a.d.id < b.d.id
  end)
  return out
end

-- ---------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------

local st = {
  open = false,
  bar_id = nil,         -- the bar being edited (its id: instances come and go)
  sel = nil,            -- the selected item
  expanded = setmetatable({}, { __mode = "k" }),
  rows = {},            -- this frame's rows: { it, list, k, y0, y1, depth }
  drag = nil,           -- { it, list, k }
  label_for = nil, label_buf = "",
  name_for = nil, name_buf = "",
  focus = false,
}

-- Opens the window, on a drawer (and an item in it) when given.
function AE.open(d, item)
  st.open = true
  st.focus = true
  if d then st.bar_id = d.id end
  if item then
    st.sel = item
    if item.menu then st.expanded[item] = true end
  end
end

function AE.is_open() return st.open end

function AE.cancel_picks() DR.cancel_picks() end

-- Where an item is: its list and index, searching the bar's tree.
local function locate(items, target)
  for k, it in ipairs(items) do
    if it == target then return items, k end
    if it.menu then
      local l, i = locate(it.items or {}, target)
      if l then return l, i end
    end
  end
  return nil
end
AE.locate = locate

-- Where something new goes: into the selected menu when it's open, else
-- after the selection, else at the end.
local function insert_point(tb)
  local sel = st.sel
  if sel then
    if sel.menu and st.expanded[sel] then return sel.items, #sel.items + 1 end
    local l, k = locate(tb.items, sel)
    if l then return l, k + 1 end
  end
  return tb.items, #tb.items + 1
end

local function insert(tb, it)
  local l, k = insert_point(tb)
  table.insert(l, k, it)
  st.sel = it
  if it.menu then st.expanded[it] = true end
  tb.save()
end

-- ---------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------

local ROW_H, INDENT = 22, 18

local function meta_of(it, web)
  if it.menu then return ("menu \u{00B7} %d"):format(#(it.items or {})) end
  if it.gap then return web and "spacer" or "gap" end
  if it.sep then return web and "spacer" or "separator" end
  local sw = TB.switch_of(it)
  if sw == "menu" then return "toolbar switch \u{00B7} menu of bars" end
  if sw then return "toolbar switch" end
  local fk, fw = FB.kind(it)
  if fk then return (fk == "fx" and "plugin \u{00B7} " or "FX chain \u{00B7} ") .. FB.short(fk, fw) end
  local id = TB.resolve(it.cmd)
  return TB.action_name(id) or ("not found: " .. tostring(it.cmd))
end

local function draw_rows(ctx, tb, list, depth, x, w, web)
  local dl = ImGui.GetWindowDrawList(ctx)
  for k, it in ipairs(list) do
    local _, y = ImGui.GetCursorScreenPos(ctx)
    ImGui.SetCursorScreenPos(ctx, x, y)
    ImGui.InvisibleButton(ctx, ("aer%s.%d"):format(tostring(it):sub(-8), k), math.max(1, w), ROW_H)
    local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    local ix = x + 6 + depth * INDENT
    if ImGui.IsItemClicked(ctx, 0) then
      local mx = ImGui.GetMousePos(ctx)
      if it.menu and mx >= ix + 8 and mx < ix + 22 then
        st.expanded[it] = not st.expanded[it]
      end
      st.sel = it
    end
    if it.menu and hov and ImGui.IsMouseDoubleClicked(ctx, 0) then st.expanded[it] = not st.expanded[it] end
    if act and not st.drag and ImGui.IsMouseDragging(ctx, 0, 5) then
      st.drag = { it = it, list = list, k = k }
    end
    local dragged = st.drag and st.drag.it == it
    if st.sel == it then
      ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + ROW_H, U.with_alpha(C.COL.accent, 0x77), 2)
    elseif hov and not st.drag then
      ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + ROW_H, C.COL.knob_body_hi, 2)
    end
    local ink = dragged and C.COL.header_dim or C.COL.label
    local cy = y + ROW_H * 0.5
    -- the grip
    for gy = -3, 3, 3 do
      ImGui.DrawList_AddCircleFilled(dl, ix + 1, cy + gy, 1.0, C.COL.header_dim)
      ImGui.DrawList_AddCircleFilled(dl, ix + 4, cy + gy, 1.0, C.COL.header_dim)
    end
    -- the open/closed triangle of a menu
    local tx = ix + 15
    if it.menu then
      if st.expanded[it] then
        ImGui.DrawList_AddTriangleFilled(dl, tx - 3.5, cy - 2, tx + 3.5, cy - 2, tx, cy + 2.5, C.COL.icon)
      else
        ImGui.DrawList_AddTriangleFilled(dl, tx - 2, cy - 3.5, tx - 2, cy + 3.5, tx + 2.5, cy, C.COL.icon)
      end
    end
    local lx = ix + 26
    local _, th = ImGui.CalcTextSize(ctx, "X")
    if it.sep and not it.menu then
      local meta = meta_of(it, web)
      if it.gap or web then
        ImGui.DrawList_AddRect(dl, lx, cy - 4, lx + 40, cy + 4, C.COL.panel_border, 2, 0, 1.0)
      else
        ImGui.DrawList_AddLine(dl, lx, cy, lx + 160, cy, C.COL.panel_border, 1.0)
      end
      local mw = ImGui.CalcTextSize(ctx, meta)
      ImGui.DrawList_AddText(dl, x + w - mw - 8, cy - th * 0.5, C.COL.header_dim, meta)
    else
      if it.color and it.color ~= "" then
        local hex = it.color:match("^#(%x%x%x%x%x%x)$")
        if hex then
          ImGui.DrawList_AddRectFilled(dl, lx, cy + 5, lx + 14, cy + 7, (tonumber(hex, 16) << 8) | 0xff)
        end
      end
      if it.icon and it.icon ~= "" then
        TB.allow_loads(4)
        local ok = TB.draw_icon(ctx, dl, it.icon, lx, cy - 8, 16, 1)
        if ok then lx = lx + 22 end
      end
      local label = TB.text_of(it)
      if not it.menu and (it.label or "") == "" then label = TB.label_of(it) end
      ImGui.DrawList_AddText(dl, lx, cy - th * 0.5, ink, label)
      local meta = meta_of(it, web)
      local room = x + w - 8 - (lx + ImGui.CalcTextSize(ctx, label) + 20)
      if room > 30 then
        meta = U.truncate(meta, math.max(4, math.floor(room / 6.5)))
        local mw = ImGui.CalcTextSize(ctx, meta)
        ImGui.DrawList_AddText(dl, x + w - mw - 8, cy - th * 0.5, C.COL.header_dim, meta)
      end
    end
    st.rows[#st.rows + 1] = { it = it, list = list, k = k, y0 = y, y1 = y + ROW_H, depth = depth }
    ImGui.SetCursorScreenPos(ctx, x, y + ROW_H)
    if it.menu and st.expanded[it] then
      draw_rows(ctx, tb, it.items, depth + 1, x, w, web)
      if #it.items == 0 then
        local _, ey = ImGui.GetCursorScreenPos(ctx)
        ImGui.DrawList_AddText(dl, x + 6 + (depth + 1) * INDENT + 26, ey + 3, C.COL.header_dim, "empty: drop something here")
        st.rows[#st.rows + 1] = { it = it, list = it.items, k = 1, y0 = ey, y1 = ey + ROW_H, depth = depth + 1, empty = true }
        ImGui.SetCursorScreenPos(ctx, x, ey + ROW_H)
      end
    end
  end
end

-- While a row is being dragged: where it would land, marked, and moved
-- there on release.
local function drop(ctx, tb, x, w)
  local d = st.drag
  if not d then return end
  local dl = ImGui.GetWindowDrawList(ctx)
  local _, my = ImGui.GetMousePos(ctx)
  local tgt
  local R = st.rows
  for _, r in ipairs(R) do
    if my >= r.y0 and my < r.y1 then
      local f = (my - r.y0) / (r.y1 - r.y0)
      if r.empty then
        tgt = { list = r.list, k = 1, y = r.y0 + 2, depth = r.depth }
      elseif r.it.menu and f >= 0.3 and r.it ~= d.it then
        tgt = { list = r.it.items, k = #r.it.items + 1, into = r.it, y0 = r.y0, y1 = r.y1 }
      elseif f < 0.5 then
        tgt = { list = r.list, k = r.k, y = r.y0, depth = r.depth }
      else
        tgt = { list = r.list, k = r.k + 1, y = r.y1, depth = r.depth }
      end
      break
    end
  end
  if not tgt and #R > 0 then
    if my < R[1].y0 then tgt = { list = tb.items, k = 1, y = R[1].y0, depth = 0 }
    else tgt = { list = tb.items, k = #tb.items + 1, y = R[#R].y1, depth = 0 } end
  end
  local ok = tgt and not (d.it.menu and TB.inside(d.it, tgt.list))
  if tgt and ok then
    if tgt.into then
      ImGui.DrawList_AddRect(dl, x + 1, tgt.y0 + 1, x + w - 1, tgt.y1 - 1, C.COL.accent, 2, 0, 2.0)
    else
      local lx = x + 6 + tgt.depth * INDENT
      ImGui.DrawList_AddLine(dl, lx, tgt.y, x + w - 6, tgt.y, C.COL.accent, 2.0)
    end
  end
  -- what's being carried, by the pointer
  local mx = ImGui.GetMousePos(ctx)
  local fg = ImGui.GetForegroundDrawList(ctx)
  local label = TB.label_of(d.it)
  local tw, th = ImGui.CalcTextSize(ctx, label)
  ImGui.DrawList_AddRectFilled(fg, mx + 12, my - th * 0.5 - 4, mx + 24 + tw, my + th * 0.5 + 4, C.COL.knob_body)
  ImGui.DrawList_AddRect(fg, mx + 12, my - th * 0.5 - 4, mx + 24 + tw, my + th * 0.5 + 4, ok and C.COL.accent or C.COL.warn, 2, 0, 1.0)
  ImGui.DrawList_AddText(fg, mx + 18, my - th * 0.5, C.COL.label, label)

  if not ImGui.IsMouseDown(ctx, 0) then
    st.drag = nil
    if tgt and ok then
      local from_list, from_k = locate(tb.items, d.it)
      if from_list then
        if TB.move_item(from_list, from_k, tgt.list, tgt.k) then
          if tgt.into then st.expanded[tgt.into] = true end
          st.sel = d.it
          tb.save()
        end
      end
    end
  end
end

-- An import submenu: REAPER toolbars and menus, each to replace the bar
-- or to go in as a menu of its own.
local function import_menu(ctx, tb)
  local function one(section, k)
    if ImGui.BeginMenu(ctx, section .. "##aeimp" .. k) then
      if ImGui.MenuItem(ctx, "Add it as a menu##aeimpm" .. k) then
        local items, title = TB.read_reaper(section)
        insert(tb, { menu = true, icon = "", label = title or section, items = items })
      end
      if ImGui.MenuItem(ctx, "Replace this bar with it##aeimpr" .. k) then
        local items = TB.read_reaper(section)
        if #items > 0 and reaper.MB("Replace every button on this bar?", "ChannelView", 4) == 6 then
          tb.items = items; st.sel = nil; tb.save()
        end
      end
      ImGui.EndMenu(ctx)
    end
  end
  ImGui.TextDisabled(ctx, "REAPER toolbars")
  local list = TB.reaper_toolbars()
  if #list == 0 then ImGui.TextDisabled(ctx, "  none customised") end
  for k, name in ipairs(list) do one(name, "t" .. k) end
  ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, "REAPER menus")
  local menus = TB.reaper_menus()
  if #menus == 0 then ImGui.TextDisabled(ctx, "  none customised") end
  for k, name in ipairs(menus) do one(name, "m" .. k) end
end

-- Rows of controls that wrap to the next line when the panel is too
-- narrow for them: flow(key) before each control (or group), measure(key)
-- after it. Widths are last frame's, so a wrap settles in one frame.
local widths, flow_first = {}, true
local function flow_begin() flow_first = true end
local function flow(ctx, key, gap)
  if flow_first then flow_first = false return end
  ImGui.SameLine(ctx, 0, gap or 8)
  local avail = ImGui.GetContentRegionAvail(ctx)
  if (widths[key] or 0) > avail then ImGui.NewLine(ctx) end
end
local function measure(ctx, key)
  widths[key] = ImGui.GetItemRectSize(ctx)
end

-- The selected bar's own settings, above its tree: its name, its place
-- (one each; the TCP's and the web's places swap), and for a drawer or
-- window whether it's open and how its buttons look.
local function bar_settings(ctx, bar)
  local d = bar.d
  flow_begin()
  if st.name_for ~= d then st.name_for, st.name_buf = d, d.name or "" end
  flow(ctx, "name")
  ImGui.BeginGroup(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Name")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 150)
  local changed, v = ImGui.InputText(ctx, "##aedrname", st.name_buf)
  if changed then st.name_buf = v end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then d.name = TB.clean(st.name_buf); DR.save() end
  ImGui.EndGroup(ctx)
  measure(ctx, "name")

  flow(ctx, "place", 14)
  ImGui.BeginGroup(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Place")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 190)
  if ImGui.BeginCombo(ctx, "##aeplace", DR.SIDE_NAME[d.side]) then
    for _, p in ipairs(DR.PLACES) do
      local label = DR.SIDE_NAME[p]
      local e = DR.SINGLE[p] and DR.at(p)
      if e and e ~= d then label = label .. "  (swaps)" end
      if ImGui.Selectable(ctx, label .. "##aepl" .. p, d.side == p) then DR.set_place(d, p) end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.EndGroup(ctx)
  measure(ctx, "place")

  local shown = DR.DRAWER[d.side] or d.side == "window"
  if shown then
    flow(ctx, "open", 14)
    local c1, open = ImGui.Checkbox(ctx, "Open##aedropen", d.open)
    measure(ctx, "open")
    if c1 then
      d.open = open; DR.save()
      if open and d.side == "window" then DR.ensure_host() end
    end
  end
  if d.side ~= "web" then
    flow(ctx, "style", 14)
    ImGui.BeginGroup(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Buttons")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Icons and labels##aest", d.style == "both") then d.style = "both"; DR.save() end
    ImGui.SameLine(ctx, 0, 6)
    if ImGui.RadioButton(ctx, "Icons##aest", d.style == "icons") then d.style = "icons"; DR.save() end
    ImGui.EndGroup(ctx)
    measure(ctx, "style")

    flow(ctx, "size", 14)
    ImGui.BeginGroup(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Size")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 110)
    local cur = d.size or DR.SIZE_DEF
    local cur_name = cur .. " px"
    for _, z in ipairs(DR.SIZES) do if z[2] == cur then cur_name = z[1] end end
    if ImGui.BeginCombo(ctx, "##aesize", cur_name) then
      for _, z in ipairs(DR.SIZES) do
        if ImGui.Selectable(ctx, z[1] .. "##aesz" .. z[2], cur == z[2]) then d.size = z[2]; DR.save() end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.EndGroup(ctx)
    measure(ctx, "size")
  end
  local across, updown = DR.aligns(d)
  if across or updown then
    flow(ctx, "align", 14)
    ImGui.BeginGroup(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Align")
    local function combo(id, list, cur, usual, set)
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 84)
      local name = usual
      for _, a in ipairs(list) do if a[2] == cur then name = a[1] end end
      if ImGui.BeginCombo(ctx, id, name) then
        for _, a in ipairs(list) do
          if ImGui.Selectable(ctx, a[1] .. id .. a[2], cur == a[2]) then set(a[2]); DR.save() end
        end
        ImGui.EndCombo(ctx)
      end
    end
    if across then combo("##aeha", DR.HALIGN, d.halign or "-", "Left", function(v) d.halign = v end) end
    if updown then
      local column = d.side == "left" or d.side == "right"
      combo("##aeva", DR.VALIGN, d.valign or "-", column and "Top" or "Centre", function(v) d.valign = v end)
    end
    ImGui.EndGroup(ctx)
    measure(ctx, "align")
  end
  flow(ctx, "cstyle", 14)
  ImGui.BeginGroup(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Colours")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 120)
  if ImGui.BeginCombo(ctx, "##aecs", d.cstyle == "i" and "Coloured icons" or "Underlines") then
    if ImGui.Selectable(ctx, "Underlines##aecsu", d.cstyle ~= "i") then d.cstyle = "u"; DR.save() end
    if ImGui.Selectable(ctx, "Coloured icons##aecsi", d.cstyle == "i") then d.cstyle = "i"; DR.save() end
    ImGui.EndCombo(ctx)
  end
  ImGui.EndGroup(ctx)
  measure(ctx, "cstyle")
  if d.side == "window" then
    flow(ctx, "dock", 14)
    ImGui.BeginGroup(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Dock")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 110)
    local cur_name = "Floating"
    for _, k in ipairs(DR.DOCKS) do if k[2] == (d.dock or 0) then cur_name = k[1] end end
    if ImGui.BeginCombo(ctx, "##aedock", cur_name) then
      for _, k in ipairs(DR.DOCKS) do
        if ImGui.Selectable(ctx, k[1] .. "##aedk" .. k[2], (d.dock or 0) == k[2]) then d.dock, d.dock_req = k[2], k[2]; DR.save() end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.EndGroup(ctx)
    measure(ctx, "dock")
    -- on a line of its own: its swatches wrap to the panel's width
    ImGui.BeginGroup(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Background")
    ImGui.SameLine(ctx)
    DR.bg_items(ctx, d, true)
    ImGui.EndGroup(ctx)
    measure(ctx, "bg")
  end
  if not DR.SINGLE[d.side] then
    flow(ctx, "remove", 14)
    local rm = ImGui.SmallButton(ctx, "Remove the bar\u{2026}")
    measure(ctx, "remove")
    if rm then
      if reaper.MB(("Remove \"%s\" and its buttons?"):format(d.name or ""), "ChannelView", 4) == 6 then
        DR.remove(d)
        st.bar_id, st.sel = nil, nil
      end
    end
  end
  if d.side == "web" then
    ImGui.PushTextWrapPos(ctx, 0)
    ImGui.TextDisabled(ctx, "On the web companion's Actions bar: ChannelView's own icons show there, PNGs don't; separators and gaps are spacers.")
    ImGui.PopTextWrapPos(ctx)
  end
end

-- The selected item's properties.
local function item_props(ctx, tb, web)
  local it = st.sel
  if not it or not locate(tb.items, it) then
    st.sel = nil
    ImGui.TextDisabled(ctx, "Pick a row to set its label and icon.")
    return
  end
  if it.sep and not it.menu then
    ImGui.Text(ctx, it.gap and (web and "Spacer" or "Gap") or (web and "Spacer" or "Separator"))
  else
    local sw = TB.switch_of(it)
    if it.menu then
      ImGui.Text(ctx, "Menu")
      ImGui.TextDisabled(ctx, ("%d inside. Clicking it opens it."):format(#it.items))
      if not web then
        local chg, v = ImGui.Checkbox(ctx, "Large submenus##aelarge", it.large == true)
        if chg then it.large = v or nil; tb.save() end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Its submenus shown as buttons, like the bar's.") end
      end
    elseif sw then
      ImGui.Text(ctx, "Toolbar switch")
      ImGui.PushTextWrapPos(ctx, 0)
      ImGui.TextDisabled(ctx, sw == "menu"
        and "Opens a menu of every bar: the one picked takes this bar's place."
        or "Puts that bar in this bar's place. Lit while it's the one showing.")
      ImGui.PopTextWrapPos(ctx)
      ImGui.SetNextItemWidth(ctx, -1)
      local cur = "A menu of every bar"
      if sw ~= "menu" then
        local b = DR.by_id(sw)
        cur = b and DR.name_of(b) or ("Bar " .. sw .. " (removed)")
      end
      if ImGui.BeginCombo(ctx, "##aeswitch", cur) then
        if ImGui.Selectable(ctx, "A menu of every bar##aeswm", sw == "menu") then
          it.cmd = TB.switch_cmd(nil); tb.save()
        end
        for _, e in ipairs(DR.switch_list()) do
          if ImGui.Selectable(ctx, e.name .. "  \u{00B7}  " .. e.where .. "##aesw" .. e.id, sw == e.id) then
            it.cmd = TB.switch_cmd(e.id); tb.save()
          end
        end
        ImGui.EndCombo(ctx)
      end
    elseif FB.kind(it) then
      local fk, fw = FB.kind(it)
      ImGui.Text(ctx, fk == "fx" and "Plugin" or "FX chain")
      ImGui.PushTextWrapPos(ctx, 0)
      ImGui.TextDisabled(ctx, fw)
      ImGui.TextDisabled(ctx, "Adds it to the selected tracks: after the plugin selected in " ..
        "ChannelView, else at the end of the chain.")
      ImGui.PopTextWrapPos(ctx)
      if ImGui.Button(ctx, "Change\u{2026}##aefxchg") then
        if fk == "chain" then st.chains = CN.list() end
        ImGui.OpenPopup(ctx, "aefxchg")
      end
      if ImGui.BeginPopup(ctx, "aefxchg") then
        local function swap(new)
          if (it.label or "") == FB.short(fk, fw) then it.label = new.label end
          if (it.icon or "") == "" or it.icon == (FB.icon_for(fk, fw) or "") or it.icon == "cv:fx_chain" then it.icon = new.icon end
          it.cmd = new.cmd
          st.label_for = nil
          tb.save()
        end
        if fk == "fx" then
          B.menu_items(ctx, nil, { pick = function(e) swap(FB.fx_item(e)) end, single = true })
        elseif CN.has_chains(st.chains) then
          CN.items(ctx, st.chains, function(f) swap(FB.chain_item(f)) end)
        else
          ImGui.TextDisabled(ctx, "No FX chains found")
        end
        ImGui.EndPopup(ctx)
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Add it now##aerun") then FB.run(it, (it.cm == "ask") and "add" or nil) end
    else
      ImGui.Text(ctx, "Action")
      local name = TB.action_name(TB.resolve(it.cmd))
      ImGui.PushTextWrapPos(ctx, 0)
      if name then ImGui.TextDisabled(ctx, name)
      else ImGui.TextColored(ctx, C.COL.warn, "Not found: " .. tostring(it.cmd)) end
      ImGui.PopTextWrapPos(ctx)
      if ImGui.Button(ctx, "Change\u{2026}##aechg") then tb.pick_replace(it) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Run it##aerun") then TB.run(it) end
    end
    ImGui.Spacing(ctx)
    if st.label_for ~= it then st.label_for, st.label_buf = it, it.label or "" end
    ImGui.Text(ctx, "Label")
    ImGui.SetNextItemWidth(ctx, -1)
    local hint = it.menu and "Menu" or ((TB.switch_of(it) or FB.kind(it)) and tb.text_of({ cmd = it.cmd, label = "" }))
                 or (TB.action_name(TB.resolve(it.cmd)) or "")
    local changed, v = ImGui.InputTextWithHint(ctx, "##aelabel", hint, st.label_buf)
    if changed then st.label_buf = v end
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then it.label = TB.clean(st.label_buf); tb.save() end
    ImGui.Spacing(ctx)
    do
      ImGui.Text(ctx, "Colour")
      tb.colour_row(ctx, it, "aecap", true)
      ImGui.Spacing(ctx)
    end
    -- a plugin's own look, over its vendor's (TS_CV_Vendors)
    if FB.kind(it) == "fx" then
      ImGui.Text(ctx, "Vendor look")
      tb.vendor_look(ctx, it, "aevo")
      ImGui.Spacing(ctx)
    end
    -- an FX chain: added, in place of the plugins, or asked each time
    if FB.kind(it) == "chain" then
      ImGui.Text(ctx, "When clicked")
      tb.chain_mode(ctx, it, "aecm")
      ImGui.Spacing(ctx)
    end
    do
      ImGui.Text(ctx, web and "Icon (the web shows ChannelView's own)" or "Icon")
      local dl = ImGui.GetWindowDrawList(ctx)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      ImGui.Dummy(ctx, 28, 24)
      ImGui.DrawList_AddRect(dl, x, y, x + 28, y + 24, C.COL.panel_border, 2, 0, 1.0)
      if it.icon ~= "" then
        TB.allow_loads(2)
        TB.draw_icon(ctx, dl, it.icon, x + 2, y + 2, 20, 1)
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Choose\u{2026}##aeicon") then tb.open_icons(it, "ae") end
      ImGui.SameLine(ctx)
      ImGui.BeginDisabled(ctx, it.icon == "")
      if ImGui.Button(ctx, "None##aeicon") then it.icon = ""; tb.save() end
      ImGui.EndDisabled(ctx)
    end
  end
  ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
  -- copy to another bar
  if ImGui.Button(ctx, "Copy to\u{2026}##aecopy") then ImGui.OpenPopup(ctx, "aecopyto") end
  if ImGui.BeginPopup(ctx, "aecopyto") then
    for k, b in ipairs(all_bars()) do
      if b.tb ~= tb and ImGui.MenuItem(ctx, b.name .. "##aecp" .. k) then
        local c = TB.copy_items({ it })[1]
        if c then
          b.tb.items[#b.tb.items + 1] = c
          b.tb.save()
        end
      end
    end
    ImGui.EndPopup(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Remove##aerm") then
    local l, k = locate(tb.items, it)
    if l then
      local ok = not (it.menu and #it.items > 0)
          or reaper.MB(("Remove the menu \"%s\" and everything in it?"):format(TB.text_of(it)), "ChannelView", 4) == 6
      if ok then table.remove(l, k); st.sel = nil; tb.save() end
    end
  end
end

-- ---------------------------------------------------------------------
-- import / export (as layouts are shared: TS_CV_Share)
-- ---------------------------------------------------------------------

local SHARE_DIR = "bars_share_dir"
local FILTER = "ChannelView action bars (*.ini)\0*.ini\0All files (*.*)\0*.*\0\0"
local function last_dir()
  local d = reaper.GetExtState(C.EXT_SECT, SHARE_DIR)
  return (d ~= "" and d) or reaper.GetResourcePath()
end
local function remember_dir(file)
  local d = file:match("^(.*)[\\/]")
  if d then reaper.SetExtState(C.EXT_SECT, SHARE_DIR, d, true) end
end
local function ask_save(default_name)
  local file
  if reaper.JS_Dialog_BrowseForSaveFile then
    local rv, f = reaper.JS_Dialog_BrowseForSaveFile("Export ChannelView action bars", last_dir(), default_name, FILTER)
    if rv ~= 1 or not f or f == "" then return nil end
    file = f
  else
    local ok, f = reaper.GetUserInputs("Export ChannelView action bars", 1,
      "Save as (full path):,extrawidth=320", last_dir() .. package.config:sub(1, 1) .. default_name)
    if not ok or U.trim(f) == "" then return nil end
    file = U.trim(f)
  end
  if not file:lower():match("%.ini$") then file = file .. ".ini" end
  return file
end
local function ask_open()
  local rv, f
  if reaper.JS_Dialog_BrowseForOpenFiles then
    rv, f = reaper.JS_Dialog_BrowseForOpenFiles("Import ChannelView action bars", last_dir(), "", FILTER, false)
    if rv ~= 1 then return nil end
  else
    rv, f = reaper.GetUserFileNameForRead("", "Import ChannelView action bars", "ini")
    if not rv then return nil end
  end
  if not f or f == "" then return nil end
  return f
end
local function msg(text) reaper.MB(text, "ChannelView", 0) end
local function name_of(cmd) return TB.action_name(TB.resolve(cmd)) end

-- An import entry against your bars: "new", "differs" (replaces yours,
-- found by name) or "same"; and which of its actions this REAPER lacks.
function AE.import_status(e, list)
  local mine
  for _, d in ipairs(list or DR.list) do
    if (d.name or ""):lower() == (e.name or ""):lower() and e.name ~= "" then mine = d break end
  end
  e.replace = mine
  if not mine then e.status = "new"
  elseif TB.serialize(mine.tb.items) == TB.serialize(e.items) then e.status = "same"
  else e.status = "differs" end
  return e.status
end

local share = nil
-- ---------------------------------------------------------------------
-- vendors (TS_CV_Vendors): a colour, initials and a look per plugin
-- vendor, which every plugin button of that vendor picks up
-- ---------------------------------------------------------------------

local vend = { open = false }

-- A row's colour, initials and look.
local function vendor_settings(ctx, k, v)
  local changed = false
  ImGui.TableNextColumn(ctx)
  local col = TB.colour_of(v.color) or 0x808080ff
  if ImGui.ColorButton(ctx, "##aevc" .. k, col, ImGui.ColorEditFlags_NoTooltip, 40, 20) then
    ImGui.OpenPopup(ctx, "aevcpop" .. k)
  end
  if ImGui.BeginPopup(ctx, "aevcpop" .. k) then
    for j, hex in ipairs(VN.SUGGEST) do
      if j > 1 and (j - 1) % 8 ~= 0 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.ColorButton(ctx, "##aevs" .. k .. "." .. j, TB.colour_of(hex), ImGui.ColorEditFlags_NoTooltip, 20, 20) then
        v.color = hex; changed = true
        ImGui.CloseCurrentPopup(ctx)
      end
    end
    if ImGui.Button(ctx, "Any colour\u{2026}##aevany" .. k) then
      vend.pick = { v = v, s = CPk.new_state(col >> 8) }
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end
  ImGui.TableNextColumn(ctx)
  ImGui.SetNextItemWidth(ctx, -1)
  local ch, txt = ImGui.InputText(ctx, "##aevi" .. k, v.init or "")
  if ch then v.init = (txt:gsub("[;|]", "")):sub(1, 5); changed = true end
  ImGui.TableNextColumn(ctx)
  ImGui.SetNextItemWidth(ctx, -1)
  if ImGui.BeginCombo(ctx, "##aevl" .. k, VN.LOOK_NAMES[v.look] or VN.LOOK_NAMES.none) then
    for _, l in ipairs(VN.LOOKS) do
      if ImGui.Selectable(ctx, VN.LOOK_NAMES[l], v.look == l) then v.look = l; changed = true end
    end
    ImGui.EndCombo(ctx)
  end
  return changed
end

-- "Same as…": the vendors set up with a look of their own, to take one's.
local function same_as_menu(ctx, k, name, owns)
  if ImGui.SmallButton(ctx, "Same as\u{2026}##aevsm" .. k) then ImGui.OpenPopup(ctx, "aevsame" .. k) end
  W.tip(ctx, "aevsm" .. k, "Use another vendor's look for this one's plugins", ImGui.IsItemHovered(ctx), false)
  if ImGui.BeginPopup(ctx, "aevsame" .. k) then
    local any = false
    for _, o in ipairs(VN.list()) do
      if not o.same and VN.clean(o.name):lower() ~= VN.clean(name):lower() then
        any = true
        if ImGui.Selectable(ctx, o.name .. "##aevso" .. k) then VN.same_as(name, o.name) end
      end
    end
    if not any then ImGui.TextDisabled(ctx, "Set up the other vendor first.") end
    if owns then
      ImGui.Separator(ctx)
      ImGui.TextDisabled(ctx, "Its own colour and look are dropped.")
    end
    ImGui.EndPopup(ctx)
  end
end

-- "Any colour…": ChannelView's colour tool (palettes, recent colours, the
-- picker and its eyedropper) in the Vendors window itself, in place of the
-- list until it's applied or cancelled. Drawn here rather than as a dialog
-- of its own: a modal opened from inside this one doesn't show.
local function vendor_colour(ctx)
  local p = vend.pick
  local done = false
  local function keep(rgb)
    p.v.color = ("#%06x"):format(rgb & 0xffffff)
    VN.save()
    CPk.remember(rgb)
    done = true
  end
  ImGui.SeparatorText(ctx, "Colour for " .. p.v.name)
  ImGui.BeginGroup(ctx)
  local c = CPk.palette(ctx, p.s, "aevp")
  if c then keep(c) end
  if not done and #CPk.recent > 0 then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Recent")
    local r = CPk.recent_row(ctx, "aevp")
    if r then keep(r) end
  end
  ImGui.EndGroup(ctx)
  if not done then
    ImGui.SameLine(ctx, 0, 24)
    ImGui.BeginGroup(ctx)
    CPk.any_colour(ctx, p.s, "aevp")
    ImGui.EndGroup(ctx)
    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "Apply##aevp") then keep(p.s.rgb) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel##aevp") then done = true end
  end
  if done then
    CPk.release(p.s)
    vend.pick = nil
  end
end

local function vendors_body(ctx)
  if vend.pick then vendor_colour(ctx) return end
  ImGui.PushTextWrapPos(ctx, 0)
  ImGui.TextDisabled(ctx, "Plugin buttons take their vendor's colour, and its look. A colour, or a " ..
    "PNG icon, set on a button itself still wins.")
  ImGui.PopTextWrapPos(ctx)
  ImGui.Spacing(ctx)

  -- the vendors set up; then the ones on your bars that aren't yet; then,
  -- after a scan, every other vendor among your plugins
  local rows, seen = {}, {}
  local found = vend.found or {}
  for _, v in ipairs(VN.list()) do
    rows[#rows + 1] = { name = v.name, v = v }
    seen[VN.clean(v.name):lower()] = true
  end
  local function more(names, kind)
    table.sort(names, function(a, b) return a.name:lower() < b.name:lower() end)
    for _, e in ipairs(names) do
      local key = VN.clean(e.name):lower()
      if not seen[key] then
        seen[key] = true
        rows[#rows + 1] = { name = e.name, kind = kind, n = e.n }
      end
    end
  end
  do
    local on_bars = {}
    for name, n in pairs(found) do on_bars[#on_bars + 1] = { name = name, n = n } end
    more(on_bars, "bars")
  end
  if vend.scanned then more(VN.installed(), "installed") end
  local unset = {}
  for _, r in ipairs(rows) do if not r.v then unset[#unset + 1] = r.name end end
  if #rows == 0 then
    ImGui.TextDisabled(ctx, "No plugin buttons on your bars yet: + Plugin adds them, or Scan plugins lists every vendor.")
  end

  local changed = false
  if ImGui.BeginTable(ctx, "aevt", 5, ImGui.TableFlags_RowBg | ImGui.TableFlags_ScrollY, 0, -30) then
    ImGui.TableSetupScrollFreeze(ctx, 0, 1)
    ImGui.TableSetupColumn(ctx, "Vendor", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "Colour", ImGui.TableColumnFlags_WidthFixed, 50)
    ImGui.TableSetupColumn(ctx, "Initials", ImGui.TableColumnFlags_WidthFixed, 60)
    ImGui.TableSetupColumn(ctx, "Look", ImGui.TableColumnFlags_WidthFixed, 120)
    ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed, 132)
    ImGui.TableHeadersRow(ctx)
    for k, r in ipairs(rows) do
      local v = r.v
      local n = found[r.name] or 0
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      local count = (r.kind == "installed") and ("  (" .. r.n .. " installed)") or (n > 0 and ("  (" .. n .. ")") or "")
      if v then ImGui.Text(ctx, r.name .. count) else ImGui.TextDisabled(ctx, r.name .. count) end
      if v and v.same then
        -- the same as another: that one's look
        ImGui.TableNextColumn(ctx)
        local o = VN.get(v.name)
        if o then ImGui.ColorButton(ctx, "##aevc" .. k, TB.colour_of(o.color) or 0x808080ff, ImGui.ColorEditFlags_NoTooltip, 40, 20) end
        ImGui.TableNextColumn(ctx); ImGui.TableNextColumn(ctx)
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.TextDisabled(ctx, "as " .. v.same)
        ImGui.TableNextColumn(ctx)
        if ImGui.SmallButton(ctx, "Own look##aevown" .. k) then VN.same_as(v.name, nil) end
        ImGui.SameLine(ctx, 0, 4)
        if ImGui.SmallButton(ctx, "Forget##aevf" .. k) then VN.remove(v.name) end
      elseif v then
        if vendor_settings(ctx, k, v) then changed = true end
        ImGui.TableNextColumn(ctx)
        same_as_menu(ctx, k, v.name, true)
        ImGui.SameLine(ctx, 0, 4)
        if ImGui.SmallButton(ctx, "Forget##aevf" .. k) then VN.remove(v.name) end
      else
        ImGui.TableNextColumn(ctx); ImGui.TableNextColumn(ctx); ImGui.TableNextColumn(ctx)
        ImGui.TableNextColumn(ctx)
        same_as_menu(ctx, k, r.name, false)
        ImGui.SameLine(ctx, 0, 4)
        if ImGui.SmallButton(ctx, "Set up##aevn" .. k) then VN.ensure(r.name) end
      end
    end
    ImGui.EndTable(ctx)
  end
  if changed then VN.save() end
  if ImGui.Button(ctx, "Close") then ImGui.CloseCurrentPopup(ctx) end
  ImGui.SameLine(ctx, 0, 12)
  if ImGui.Button(ctx, vend.scanned and "Scan again" or "Scan plugins") then
    VN.rescan()
    vend.scanned = true
  end
  W.tip(ctx, "aevscan", "List every vendor among your installed plugins", ImGui.IsItemHovered(ctx), false)
  if #unset > 0 then
    ImGui.SameLine(ctx, 0, 8)
    if ImGui.Button(ctx, ("Set up all (%d)"):format(#unset)) then VN.ensure_all(unset) end
    W.tip(ctx, "aevall", "A colour and initials for each vendor listed that isn't set up", ImGui.IsItemHovered(ctx), false)
  end
end

local function draw_vendors(ctx)
  if not VN then return end
  if vend.open then
    vend.open = false
    ImGui.OpenPopup(ctx, "Vendors###aevendors")
    if vend.pick then CPk.release(vend.pick.s) end
    vend.pick = nil
    vend.found = {}
    for _, b in ipairs(all_bars()) do
      if b.tb then VN.collect(b.tb.items, vend.found, FB.kind) end
    end
  end
  ImGui.SetNextWindowSize(ctx, 640, 480, ImGui.Cond_Appearing)
  if ImGui.BeginPopupModal(ctx, "Vendors###aevendors", true, 0) then
    vendors_body(ctx)
    ImGui.EndPopup(ctx)
  end
end

local draw_share
function AE.share(mode)
  -- the window, brought forward only when it isn't open already (focusing
  -- it closes the dialog this opens)
  if not st.open then st.open, st.focus = true, true end
  if mode == "export" then
    local list = {}
    for _, b in ipairs(all_bars()) do list[#list + 1] = { d = b.d, pick = true } end
    if #list == 0 then msg("There are no action bars to export yet.") return end
    share = { mode = "export", list = list, open = true }
  else
    local file = ask_open()
    if not file then return end
    remember_dir(file)
    local fh = io.open(file, "rb")
    local text = fh and fh:read("*a")
    if fh then fh:close() end
    local list, err = DR.parse_export(text)
    if not list then msg(err) return end
    for _, e in ipairs(list) do
      AE.import_status(e)
      e.pick = (e.status == "new")
      e.missing = {}
      for _, it in ipairs(TB.flatten(e.items)) do
        if not TB.resolve(it.cmd) and not TB.switch_of(it) and not FB.kind(it) then e.missing[#e.missing + 1] = e.names[it.cmd] ~= "" and e.names[it.cmd] or it.cmd end
      end
    end
    share = { mode = "import", list = list, open = true, file = file, use_places = false }
  end
end

local STATUS = { new = "new", differs = "replaces yours", same = "same as yours" }

draw_share = function(ctx)
  if not share then return end
  local title = share.mode == "import" and "Import action bars###cvaeshare" or "Export action bars###cvaeshare"
  -- opened once the window has taken the focus it asked for (AE.share)
  if share.open and not st.focus then ImGui.OpenPopup(ctx, title); share.open = false end
  ImGui.SetNextWindowSize(ctx, 420, 0, ImGui.Cond_Appearing)
  local visible, open = ImGui.BeginPopupModal(ctx, title, true, ImGui.WindowFlags_AlwaysAutoResize)
  if not visible then
    if not open then share = nil
    -- closed before it was ever shown (a change of focus closes popups):
    -- opened again
    elseif not share.shown then share.open = true end
    return
  end
  share.shown = true
  local d = share
  local function close() share = nil; ImGui.CloseCurrentPopup(ctx) end
  if d.mode == "import" then
    ImGui.TextDisabled(ctx, U.truncate(d.file:match("[^\\/]+$") or d.file, 60))
    ImGui.TextWrapped(ctx, "Tick the bars to bring in. One with the name of one of yours replaces its buttons; " ..
      "the others come in as new bars, where they were.")
  else
    ImGui.TextWrapped(ctx, "Tick the bars to export: their buttons, menus and where they sit.")
  end
  ImGui.Spacing(ctx)
  local function can(e) return not (d.mode == "import" and e.status == "same") end
  if ImGui.SmallButton(ctx, "All##aeshall") then for _, e in ipairs(d.list) do if can(e) then e.pick = true end end end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "None##aeshnone") then for _, e in ipairs(d.list) do e.pick = false end end
  local _, line_h = ImGui.CalcTextSize(ctx, "Ag")
  if ImGui.BeginChild(ctx, "##aesharelist", 400, math.min(#d.list, 12) * (line_h + 8) + 8, ImGui.ChildFlags_Borders) then
    for i, e in ipairs(d.list) do
      local name = d.mode == "export" and ((e.d.name ~= "" and e.d.name) or ("Bar " .. e.d.id)) or (e.name ~= "" and e.name or "Bar")
      ImGui.BeginDisabled(ctx, not can(e))
      local ch, v = ImGui.Checkbox(ctx, name .. "##aesh" .. i, e.pick)
      if ch then e.pick = v end
      ImGui.EndDisabled(ctx)
      ImGui.SameLine(ctx)
      local place = d.mode == "export" and e.d.side or e.place
      local items = d.mode == "export" and e.d.tb.items or e.items
      local note = ("%s  \u{00B7}  %d"):format(DR.SIDE_NAME[place] or place, #TB.flatten(items))
      if d.mode == "import" then
        note = STATUS[e.status] .. "  \u{00B7}  " .. note
        if #e.missing > 0 then note = note .. ("  \u{00B7}  %d not found here"):format(#e.missing) end
      end
      ImGui.TextDisabled(ctx, note)
      if d.mode == "import" and #e.missing > 0 and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Not in this REAPER (they'll show as missing):\n" .. table.concat(e.missing, "\n", 1, math.min(#e.missing, 12)))
      end
    end
    ImGui.EndChild(ctx)
  end
  if d.mode == "import" then
    local ch, v = ImGui.Checkbox(ctx, "Use their places (the TCP's and web bars swap in)##aeshpl", d.use_places)
    if ch then d.use_places = v end
  end
  local picked = {}
  for _, e in ipairs(d.list) do if e.pick and can(e) then picked[#picked + 1] = e end end
  ImGui.Spacing(ctx)
  ImGui.BeginDisabled(ctx, #picked == 0)
  local label = (d.mode == "import") and ("Import %d###aeshgo") or ("Export %d\u{2026}###aeshgo")
  if ImGui.Button(ctx, label:format(#picked), 120) then
    if d.mode == "export" then
      local bars = {}
      for _, e in ipairs(picked) do bars[#bars + 1] = e.d end
      local nm = (#bars == 1) and (((bars[1].name ~= "" and bars[1].name) or "Bar"):gsub('[\\/:*?"<>|]', "_") .. " bar.ini")
                 or "ChannelView action bars.ini"
      local file = ask_save(nm)
      if file then
        remember_dir(file)
        local fh, err = io.open(file, "wb")
        if fh then
          fh:write(DR.export_text(bars, name_of)); fh:close()
          msg(("Exported %d bar%s to\n%s"):format(#bars, #bars == 1 and "" or "s", file))
          close()
        else
          msg("Couldn't write the file:\n" .. tostring(err))
        end
      end
    else
      local replacing = 0
      for _, e in ipairs(picked) do if e.status == "differs" then replacing = replacing + 1 end end
      if replacing == 0 or reaper.MB(("Replace the buttons on %d of your bars with the ones from this file?"):format(replacing),
          "ChannelView", 1) == 1 then
        DR.import(picked, d.use_places)
        close()
      end
    end
  end
  ImGui.EndDisabled(ctx)
  ImGui.SameLine(ctx)
  if share and ImGui.Button(ctx, "Cancel##aeshcancel", 90) then close() end
  ImGui.EndPopup(ctx)
end

function AE.draw(ctx)
  if not st.open then return end
  ImGui.SetNextWindowSize(ctx, 920, 500, ImGui.Cond_FirstUseEver)
  if st.focus then ImGui.SetNextWindowFocus(ctx); st.focus = false end
  local vis, open = ImGui.Begin(ctx, "Organise actions##cvae", true, ImGui.WindowFlags_NoCollapse)
  if vis then
    local bars = all_bars()
    -- keep the selection on a bar that still exists
    local cur
    for _, b in ipairs(bars) do if b.d.id == st.bar_id then cur = b end end
    if not cur then cur = bars[1]; st.bar_id = cur and cur.d.id end
    local tb = cur and cur.tb
    if tb then tb.sync(); tb.poll() end

    local _, avail_h = ImGui.GetContentRegionAvail(ctx)
    -- the bars
    if ImGui.BeginChild(ctx, "aebars", 220, avail_h, ImGui.ChildFlags_Borders) then
      ImGui.TextDisabled(ctx, "ACTION BARS")
      ImGui.Spacing(ctx)
      local group
      for k, b in ipairs(bars) do
        local p = b.d.side
        local g = DR.DRAWER[p] and "drawers" or p
        if group and g ~= group then ImGui.Separator(ctx) end
        group = g
        local shown = DR.DRAWER[p] or p == "window"
        local tag = DR.SIDE_NAME[p] .. ((shown and not b.d.open) and ", closed" or "")
        if ImGui.Selectable(ctx, b.name .. "##aebar" .. k, b == cur) then
          if st.bar_id ~= b.d.id then st.sel = nil end
          st.bar_id = b.d.id
        end
        ImGui.SameLine(ctx)
        ImGui.TextDisabled(ctx, tag)
      end
      ImGui.Spacing(ctx)
      if ImGui.Button(ctx, "+ New bar") then ImGui.OpenPopup(ctx, "aenewdr") end
      if ImGui.BeginPopup(ctx, "aenewdr") then
        for _, s in ipairs({ "top", "left", "right", "bottom", "window", "none" }) do
          -- this window's own sides (the rack's when it is the rack)
          local p = (s == "window" or s == "none") and s or (DR.PFX .. s)
          local label = (s == "window") and "Toolbar in its own window"
                        or (s == "none") and "Nowhere yet" or ((DR.SIDE_NAME[p] or s) .. " drawer")
          if ImGui.MenuItem(ctx, label .. "##aenew" .. s) then
            local d = DR.new(p)
            st.bar_id, st.sel = d.id, nil
            if s == "window" then DR.ensure_host() end
          end
        end
        ImGui.EndPopup(ctx)
      end
      ImGui.Spacing(ctx)
      if ImGui.Button(ctx, "Import\u{2026}##aebarsimp") then AE.share("import") end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Export\u{2026}##aebarsexp") then AE.share("export") end
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)

    local aw = ImGui.GetContentRegionAvail(ctx)
    local web = cur and cur.d.side == "web"
    if ImGui.BeginChild(ctx, "aetree", math.max(200, aw - 300), avail_h, ImGui.ChildFlags_Borders) then
      if cur then
        bar_settings(ctx, cur)
        ImGui.Separator(ctx)
        -- the buttons under the tree wrap: last frame's height of them
        local foot_h = (st.foot_h or ImGui.GetFrameHeightWithSpacing(ctx)) + 6
        local _, th = ImGui.GetContentRegionAvail(ctx)
        if ImGui.BeginChild(ctx, "aerows", 0, math.max(40, th - foot_h)) then
          st.rows = {}
          local x = ImGui.GetCursorScreenPos(ctx)
          local w = ImGui.GetContentRegionAvail(ctx)
          if tb and #tb.items == 0 then
            ImGui.TextDisabled(ctx, "Nothing on this bar yet. Add something below.")
          end
          if tb then
            draw_rows(ctx, tb, tb.items, 0, x, w, web)
            drop(ctx, tb, x, w)
          end
          ImGui.Dummy(ctx, 0, 4)
          ImGui.EndChild(ctx)
        end
        if tb then
          local y0 = ImGui.GetCursorPosY(ctx)
          flow_begin()
          flow(ctx, "f_act")
          if ImGui.Button(ctx, "+ Action\u{2026}") then
            local l, k = insert_point(tb)
            tb.pick_into(l, k)
          end
          measure(ctx, "f_act")
          flow(ctx, "f_menu")
          if ImGui.Button(ctx, "+ Menu") then insert(tb, TB.new_menu()) end
          measure(ctx, "f_menu")
          flow(ctx, "f_sw")
          if ImGui.Button(ctx, "+ Switch") then ImGui.OpenPopup(ctx, "aeswitchnew") end
          measure(ctx, "f_sw")
          if ImGui.BeginPopup(ctx, "aeswitchnew") then
            tb.switch_targets(ctx, function(target)
              insert(tb, { cmd = TB.switch_cmd(target), icon = "", label = "" })
            end, nil)
            ImGui.EndPopup(ctx)
          end
          -- a plugin or an FX chain to add with one click (TS_CV_FXButtons)
          flow(ctx, "f_fx")
          if ImGui.Button(ctx, "+ Plugin") then st.picked = {}; ImGui.OpenPopup(ctx, "aefxnew") end
          measure(ctx, "f_fx")
          if ImGui.BeginPopup(ctx, "aefxnew") then
            -- several in a row: the menu stays open, each click a button,
            -- a second click on one takes its button off again
            B.menu_items(ctx, nil, {
              pick = function(e, add)
                local had = st.picked[e.ident]
                if had and not add then
                  local l, k = locate(tb.items, had)
                  if l then table.remove(l, k); tb.save() end
                  st.picked[e.ident] = nil
                  if st.sel == had then st.sel = nil end
                else
                  local it = FB.fx_item(e)
                  insert(tb, it)
                  st.picked[e.ident] = it
                end
              end,
              picked = function(e) return st.picked[e.ident] ~= nil end,
            })
            ImGui.EndPopup(ctx)
          end
          flow(ctx, "f_chain")
          if ImGui.Button(ctx, "+ FX chain") then st.chains, st.cpicked = CN.list(), {}; ImGui.OpenPopup(ctx, "aechnew") end
          measure(ctx, "f_chain")
          if ImGui.BeginPopup(ctx, "aechnew") then
            if CN.has_chains(st.chains) then
              -- as "+ Plugin": stays open, a second click takes one off
              ImGui.TextDisabled(ctx, "Click to add a button, again to take it off")
              ImGui.Separator(ctx)
              ImGui.PushItemFlag(ctx, ImGui.ItemFlags_AutoClosePopups, false)
              local function add_chain(f)
                local had = st.cpicked[f.rel]
                if had then
                  local l, k = locate(tb.items, had)
                  if l then table.remove(l, k); tb.save() end
                  st.cpicked[f.rel] = nil
                  if st.sel == had then st.sel = nil end
                else
                  local it = FB.chain_item(f)
                  insert(tb, it)
                  st.cpicked[f.rel] = it
                end
              end
              local function chain_added(f) return st.cpicked[f.rel] ~= nil end
              CN.items_ticked(ctx, st.chains, add_chain, chain_added)
              ImGui.PopItemFlag(ctx)
            else
              ImGui.TextDisabled(ctx, "No FX chains found in")
              ImGui.TextDisabled(ctx, (CN.dir()))
            end
            ImGui.EndPopup(ctx)
          end
          if not web then
            flow(ctx, "f_sep")
            if ImGui.Button(ctx, "+ Separator") then insert(tb, { sep = true }) end
            measure(ctx, "f_sep")
          end
          flow(ctx, "f_gap")
          if ImGui.Button(ctx, web and "+ Spacer" or "+ Gap") then insert(tb, { sep = true, gap = true }) end
          measure(ctx, "f_gap")
          flow(ctx, "f_imp", 14)
          if ImGui.Button(ctx, "Import\u{2026}") then ImGui.OpenPopup(ctx, "aeimport") end
          measure(ctx, "f_imp")
          if ImGui.BeginPopup(ctx, "aeimport") then
            import_menu(ctx, tb)
            ImGui.EndPopup(ctx)
          end
          flow(ctx, "f_vend")
          ImGui.BeginDisabled(ctx, not VN)
          if ImGui.Button(ctx, VN and "Vendors\u{2026}" or "Vendors\u{2026}  (Pro)") then vend.open = true end
          ImGui.EndDisabled(ctx)
          if not VN then ED.note(ImGui, ctx) end
          measure(ctx, "f_vend")
          W.tip(ctx, "aevend", "A colour and a look per plugin vendor, for the plugin buttons", ImGui.IsItemHovered(ctx), false)
          flow(ctx, "f_cvi")
          if ImGui.Button(ctx, "ChannelView icons") then
            if tb.use_cv_icons() > 0 then tb.save() end
          end
          measure(ctx, "f_cvi")
          W.tip(ctx, "aecvicons", "Gives every button the icon made for its action", ImGui.IsItemHovered(ctx), false)
          if tb.picking() then
            flow(ctx, "f_pick", 14)
            ImGui.TextColored(ctx, C.COL.accent, "Pick an action, then Select\u{2026}")
            measure(ctx, "f_pick")
          end
          st.foot_h = ImGui.GetCursorPosY(ctx) - y0
        end
      end
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)

    if ImGui.BeginChild(ctx, "aeprops", 0, avail_h, ImGui.ChildFlags_Borders) then
      if tb then item_props(ctx, tb, web) end
      ImGui.EndChild(ctx)
    end

    -- the icon picker (and anything else the bar opens) belongs to this
    -- window
    if tb then tb.draw_menus(ctx, "ae") end
    draw_share(ctx)
    draw_vendors(ctx)
    B.draw(ctx, nil, true)   -- the plugin search, from "+ Plugin" > Search...
    ImGui.End(ctx)
  end
  if not open then
    st.open = false
    AE.cancel_picks()
  end
end

-- for tests
AE._st = st

return AE
