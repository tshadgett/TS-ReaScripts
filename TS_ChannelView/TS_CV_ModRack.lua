-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ModRack.lua -- the Macros and Modulators panels, pinned beside the
  fader panel. TS_CV_Mod.lua does the work; this draws it.

  MACROS: a cell per macro, shown as one of ChannelView's controls -- a
  knob, a button, a fader, a dropdown, or an XY pad (two macros, two
  cells wide). Its name and ◯ along the top, the lane button at its
  top-left.
  Right-click for rename, colour, control type, a dropdown's choices, what
  it drives, remove.

  MODULATORS: a tile per modulator (LFO, Follower, MIDI). Its colour,
  name, what it drives, and something live: an LFO what it's been doing,
  a Follower or MIDI its level. Click the name to open the tile for its
  settings, each with a lane button; right-click it for rename, colour,
  its automation lanes, what it drives, remove.

  The ◯ is the link: hover it and a faint line in its colour runs to
  every control it drives; drag it onto a control on a plugin's panel to
  link it (TS_CV_Panel takes the drop). Cells and tiles flow down, then
  into another column, as Sends do. Both panels start folded away.

  The lane button: click to make the parameter's automation lane and show
  it; click again to hide it. Lit while it has automation.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local MD = require("TS_CV_Mod")

local ImGui
local MR = {}
function MR.attach(imgui) ImGui = imgui end

-- sizes
local GAP     = 6
MR.CELL_W     = 80      -- a macro's cell
MR.CELL_H     = 86
MR.TILE_W     = 180     -- a modulator's tile
local HEAD    = 18      -- a tile's name row
local SUB     = 13      -- its "drives 3" line
local KCELL_W = 56      -- a knob in a tile: its cell
local KCELL_H = 48
local KR      = 11      -- ...and its radius
local ADD_H   = 22
local PILL_H  = 16
local LANE_W, LANE_H = 13, 11

local EXT = { macros = "macros_collapsed", mods = "mods_collapsed" }

-- Strip mode (the Rack view): each panel is a band STRIP_W wide, as short
-- as lets its cells fit across, and folds to a header bar rather than a
-- slim column. EXT_PFX keeps the rack's folding apart from ChannelView's.
MR.STRIP_W = nil
MR.EXT_PFX = ""

local open = {}         -- track..guid -> true: a tile opened for its settings
local hist = {}         -- track..guid -> recent outputs
local rename_buf = {}   -- guid -> text being typed
local choice_buf = {}   -- guid -> { names... } being edited
local pending_popup     -- a popup to open at panel level next frame

-- linking, shared with TS_CV_Panel for the frame
MR.hover = nil          -- guid of the source whose ◯ is hovered
MR.drag = nil           -- { mod, k, x, y } while a ◯ is being dragged
MR.handles = {}         -- guid[#k] -> x, y of its ◯ this frame
local seen = {}         -- guid -> { {x,y,key}, ... } its controls drawn this frame
local hover_next

MR.ctl_hover = nil      -- { guid, k, x, y }: a linked control under the pointer
MR.ctl_hover_prev = nil -- ...last frame's, for lighting its source (drawn first)
MR.bar_at = {}          -- "macros"/"mods" -> the slim bar's middle, when folded

function MR.begin_frame()
  MR.hover, hover_next = hover_next, nil
  MR.ctl_hover_prev, MR.ctl_hover = MR.ctl_hover, nil
  seen = {}
  MR.handles = {}
  MR.bar_at = {}
end

function MR.note_ctl_hover(guid, k, x, y)
  MR.ctl_hover = { guid = guid, k = k or 1, x = x, y = y }
end

function MR.note_target(guid, tguid, tparam, x, y)
  local t = seen[guid]
  if not t then t = {}; seen[guid] = t end
  t[#t + 1] = { x, y, key = tguid .. ":" .. tparam }
end

-- ---------------------------------------------------------------------
-- folded away (the default)
-- ---------------------------------------------------------------------

function MR.is_collapsed(which)
  return reaper.GetExtState(C.EXT_SECT, MR.EXT_PFX .. EXT[which]) ~= "0"
end
local function set_collapsed(which, on)
  reaper.SetExtState(C.EXT_SECT, MR.EXT_PFX .. EXT[which], on and "1" or "0", true)
end

-- ---------------------------------------------------------------------
-- placing
-- ---------------------------------------------------------------------

local function room_of(panel_h)
  return math.max(60, panel_h - C.HEADER_H - C.FOOTER_H - C.PANEL_PAD * 2)
end

local GROUP_W = MR.CELL_W * 2 + GAP

-- Macro cells, two to a row (an XY pad takes a row), down then into the
-- next pair of columns. { src, x, y, w, h } from the grid's top-left, the
-- number of column pairs, and where the add tile goes.
local function place_macros(macros, room, with_add)
  local out, gx, y, col, groups = {}, 0, 0, 0, 1
  local function newrow() y = y + MR.CELL_H + GAP; col = 0 end
  for _, src in ipairs(macros) do
    -- an XY pad: both columns and two rows, so the pad can be square
    local wide = src.kind == "xy"
    local ch = wide and (MR.CELL_H * 2 + GAP) or MR.CELL_H
    if wide and col == 1 then newrow() end
    if y > 0 and y + ch > room and col == 0 then
      gx, y, groups = gx + GROUP_W + GAP, 0, groups + 1
    end
    local w = wide and GROUP_W or MR.CELL_W
    out[#out + 1] = { src = src, x = gx + col * (MR.CELL_W + GAP), y = y, w = w, h = ch }
    if wide then y = y + ch + GAP; col = 0
    elseif col == 1 then newrow() else col = 1 end
  end
  local add
  if with_add then
    if col == 1 then newrow() end
    if y > 0 and y + ADD_H > room then gx, y, groups = gx + GROUP_W + GAP, 0, groups + 1 end
    add = { x = gx, y = y }
  end
  return out, groups, add
end

local function tile_h(track, src)
  local isopen = open[tostring(track) .. src.guid]
  local h = HEAD + SUB
  if src.kind == "lfo" then
    h = h + 30
    if isopen then h = h + 22 + KCELL_H * 2 end
  else
    h = h + 16
    if isopen then h = h + 22 + KCELL_H * 2 end
  end
  return h + 6
end

local function place_mods(track, mods, room, with_add)
  local out, x, y, cols = {}, 0, 0, 1
  for _, src in ipairs(mods) do
    local h = tile_h(track, src)
    if y > 0 and y + h > room then x, y, cols = x + MR.TILE_W + GAP, 0, cols + 1 end
    out[#out + 1] = { src = src, x = x, y = y, h = h }
    y = y + h + GAP
  end
  local add
  if with_add then
    if y > 0 and y + ADD_H > room then x, y, cols = x + MR.TILE_W + GAP, 0, cols + 1 end
    add = { x = x, y = y }
  end
  return out, cols, add
end

local function macros_full(track) return MD.macros_used(track) >= MD.NM end
local function mods_full(s) return #s.mods >= MD.NO end

-- the width the cells want at this height
local function natural_w(which, track, panel_h)
  local s = MD.scan(track)
  if which == "macros" then
    local _, groups = place_macros(s.macros, room_of(panel_h), not macros_full(track))
    return groups * GROUP_W + (groups - 1) * GAP + C.PANEL_PAD * 2
  end
  local _, cols = place_mods(track, s.mods, room_of(panel_h), not mods_full(s))
  return cols * MR.TILE_W + (cols - 1) * GAP + C.PANEL_PAD * 2
end

function MR.width_for(which, track, panel_h)
  if not track or MR.is_collapsed(which) then return MR.STRIP_W or C.COLLAPSED_W end
  local w = natural_w(which, track, panel_h)
  return MR.STRIP_W and math.max(w, MR.STRIP_W) or w
end

-- Strip mode: the folded bar's height, and the least height at which the
-- cells fit across w (or the tallest tried, when nothing does).
function MR.bar_h() return C.HEADER_H + 2 end
function MR.strip_h(which, track, w)
  if not track or MR.is_collapsed(which) then return MR.bar_h() end
  local s = MD.scan(track)
  local rows = {}
  if which == "macros" then
    local tall = MR.CELL_H
    for _, src in ipairs(s.macros) do
      if src.kind == "xy" then tall = MR.CELL_H * 2 + GAP end
    end
    if #s.macros == 0 then rows[1] = ADD_H end   -- just the add tile
    for n = 1, 8 do
      local room = n * (MR.CELL_H + GAP) - GAP
      if room >= tall then rows[#rows + 1] = room end
    end
  else
    local tall = ADD_H
    for _, src in ipairs(s.mods) do tall = math.max(tall, tile_h(track, src)) end
    for k = 0, 40 do rows[#rows + 1] = tall + k * 20 end
  end
  local extra = C.HEADER_H + C.FOOTER_H + C.PANEL_PAD * 2
  local h
  for _, room in ipairs(rows) do
    h = math.max(room, 60) + extra
    if natural_w(which, track, h) <= w then return h end
  end
  return h
end

-- ---------------------------------------------------------------------
-- small parts
-- ---------------------------------------------------------------------

-- A knob in a tile: returns changed, new value (0..1). `def` is the
-- double-click value.
local function tknob(ctx, dl, id, x, y, v, label, text, def, col)
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, KCELL_W, KCELL_H)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local changed, nv = false, v
  if act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    local d = W.drag_value(ctx, v)
    if d and d ~= v then nv, changed = d, true end
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  elseif hov then
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then
      local step = C.WHEEL_STEP
      if (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 then step = step * C.FINE_MULT end
      nv, changed = math.max(0, math.min(1, v + wheel * step)), true
      W.take_wheel()
    end
    if def and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then nv, changed = def, true end
  end
  local cx, cy = x + KCELL_W * 0.5, y + 11 + KR + 1
  W.push_small(ctx)
  if label and label ~= "" then
    local tw = ImGui.CalcTextSize(ctx, label)
    ImGui.DrawList_AddText(dl, cx - tw * 0.5, y, C.COL.label, label)
  end
  W.knob_face(dl, cx, cy, KR, nv, { hot = hov or act, cap = col })
  local vw = ImGui.CalcTextSize(ctx, text or "")
  ImGui.DrawList_AddText(dl, cx - vw * 0.5, cy + KR + 2, C.COL.value, text or "")
  W.pop_small(ctx)
  return changed, nv
end

-- A small push-button; returns pressed.
local function pill(ctx, dl, id, x, y, w, text, on, col, h)
  h = h or PILL_H
  ImGui.SetCursorScreenPos(ctx, x, y)
  local pressed = ImGui.InvisibleButton(ctx, id, w, h)
  local hov = ImGui.IsItemHovered(ctx)
  local bg = on and (col or C.COL.accent) or (hov and C.COL.knob_body_hi or C.COL.toggle_off)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 3)
  W.push_small(ctx)
  local tw, th = ImGui.CalcTextSize(ctx, text)
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + (h - th) * 0.5,
    on and C.COL.icon_on or C.COL.label, text)
  W.pop_small(ctx)
  return pressed
end

-- The lane button: makes / shows / hides a parameter's automation lane.
-- Lit (filled in `col`) while the parameter has automation.
local function lane_button(ctx, dl, id, x, y, track, slot, param, col, what)
  ImGui.SetCursorScreenPos(ctx, x - 2, y - 2)
  W.allow_overlap(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, LANE_W + 4, LANE_H + 4,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov = ImGui.IsItemHovered(ctx)
  local rclick = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
  pressed = pressed and not rclick
  local lane = MD.lane(track, slot, param)
  local ink
  if lane and lane.auto then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + LANE_W, y + LANE_H, col, 2)
    ink = 0x15171aff
  else
    -- shown: its colour; there but hidden: its colour, faint; none: grey
    local edge = (lane and lane.shown) and col or (lane and U.with_alpha(col, 0x80))
                 or (hov and C.COL.label or 0x4a4f57ff)
    ink = lane and (lane.shown and C.COL.value or U.with_alpha(col, 0xa0))
          or (hov and C.COL.label or C.COL.header_dim)
    ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + LANE_W - 0.5, y + LANE_H - 0.5, edge, 2, 0, 1)
  end
  -- a little envelope
  local px = { 2, 8, 5, 4, 8, 7, 11, 3 }
  for i = 1, #px - 2, 2 do
    ImGui.DrawList_AddLine(dl, x + px[i], y + px[i + 1], x + px[i + 2], y + px[i + 3], ink, 1.2)
  end
  local tip
  if not lane then tip = "Automation lane for " .. what .. "\nClick: show"
  elseif lane.shown then tip = what .. (lane.auto and " has automation" or "") .. "\nClick: hide lane"
  else tip = what .. (lane.auto and " has automation" or " has a lane") .. " (hidden)\nClick: show lane" end
  W.tip(ctx, id, tip .. (lane and "\nRight-click: remove" or ""), hov, false)
  if pressed then MD.toggle_lane(track, slot, param) end
  -- right-click: show / hide, or take the lane away with its automation
  if rclick and lane then ImGui.OpenPopup(ctx, "lanemenu" .. id) end
  if ImGui.BeginPopup(ctx, "lanemenu" .. id) then
    local l = MD.lane(track, slot, param)
    ImGui.TextDisabled(ctx, "Automation lane: " .. what)
    ImGui.Separator(ctx)
    if l then
      if ImGui.MenuItem(ctx, l.shown and "Hide the lane" or "Show the lane") then MD.toggle_lane(track, slot, param) end
      if ImGui.MenuItem(ctx, "Remove the lane" .. (l.auto and " and its automation" or "")) then
        local n = reaper.CountEnvelopePoints(l.env) or 0
        if not l.auto or reaper.MB(("Remove the lane for %s and its automation (%d points)?"):format(what, n),
                                   "ChannelView", 4) == 6 then
          if not MD.remove_lane(track, slot, param) then
            reaper.MB("ChannelView couldn't find that lane in the track to remove it.", "ChannelView", 0)
          end
        end
      end
    end
    ImGui.EndPopup(ctx)
  end
end

-- A link handle (◯): hover shows its lines, drag links. `k` is which
-- output it links (an XY pad's X or Y).
local function link_handle(ctx, dl, src, k, hx, hy, r, label)
  local id = ("link%d##%s"):format(k, src.guid)
  if k == 1 then MR.handles[src.guid] = { hx, hy } end
  MR.handles[src.guid .. "#" .. k] = { hx, hy }
  ImGui.SetCursorScreenPos(ctx, hx - r - 3, hy - r - 3)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, (r + 3) * 2, (r + 3) * 2)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hov then hover_next = src.guid; ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand) end
  if act and ImGui.IsMouseDragging(ctx, ImGui.MouseButton_Left, 2) then
    MR.drag = { mod = src, k = k, x = hx, y = hy }
  end
  W.tip(ctx, id, "Drag onto a control to link " .. (label or "it"), hov and not MR.drag, false)
  local hot = hov or act or (MR.ctl_hover_prev and MR.ctl_hover_prev.guid == src.guid
                             and MR.ctl_hover_prev.k == k)
  ImGui.DrawList_AddCircle(dl, hx, hy, r, src.col, 16, hot and 2.6 or 1.8)
  if hot then ImGui.DrawList_AddCircleFilled(dl, hx, hy, r * 0.45, src.col, 10) end
end

local function colour_menu(ctx, track, src)
  if not ImGui.BeginMenu(ctx, "Colour") then return end
  for i, c in ipairs(MD.COLOURS) do
    if i > 1 and (i - 1) % 6 ~= 0 then ImGui.SameLine(ctx, 0, 3) end
    local x, y = ImGui.GetCursorScreenPos(ctx)
    if ImGui.InvisibleButton(ctx, ("col%d##%s"):format(i, src.guid), 18, 18) then
      MD.set_colour(track, src, c)
      ImGui.CloseCurrentPopup(ctx)
    end
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + 18, y + 18, c, 3)
    if c == src.col then ImGui.DrawList_AddRect(dl, x - 1, y - 1, x + 19, y + 19, 0xffffffff, 3, 0, 1.5) end
  end
  ImGui.EndMenu(ctx)
end

local function rename_row(ctx, track, src)
  rename_buf[src.guid] = rename_buf[src.guid] or src.name
  ImGui.SetNextItemWidth(ctx, 150)
  local _, txt = ImGui.InputTextWithHint(ctx, "##ren" .. src.guid, src.name, rename_buf[src.guid])
  local enter = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
  rename_buf[src.guid] = txt
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Rename##" .. src.guid) or enter then
    MD.rename(track, src, txt)
    rename_buf[src.guid] = nil
    ImGui.CloseCurrentPopup(ctx)
  end
end

local function drives_menu(ctx, track, src, s, req)
  local links = s.by_mod[src.guid] or {}
  if ImGui.BeginMenu(ctx, ("Drives  (%d)"):format(#links), #links > 0) then
    for i, l in ipairs(links) do
      local taddr = require("TS_CV_FXTree").addr_of(track, l.path)
      local fname, pname = "?", "?"
      if taddr then
        local ok1, f = reaper.TrackFX_GetFXName(track, taddr, "")
        if ok1 then fname = U.clean_fx_name(f) end
        local ok2, pn = reaper.TrackFX_GetParamName(track, taddr, l.tparam, "")
        if ok2 then pname = pn end
      end
      local extra = (src.labels and src.labels[l.out]) and (" (" .. src.labels[l.out] .. ")") or ""
      if ImGui.MenuItem(ctx, ("%s \u{2192} %s%s##t%d"):format(fname, pname, extra, i)) then
        req.show_fx = l.tguid
      end
    end
    ImGui.EndMenu(ctx)
  end
  return #links
end

local function remove_item(ctx, track, src, n, req)
  if ImGui.MenuItem(ctx, n > 0 and ("Remove (and its %d link%s)"):format(n, n == 1 and "" or "s")
                     or "Remove") then
    MD.remove(track, src)
    req.changed = true
    ImGui.CloseCurrentPopup(ctx)
  end
end

-- ---------------------------------------------------------------------
-- MACROS
-- ---------------------------------------------------------------------

local function macro_menu(ctx, track, src, s, req)
  if not ImGui.BeginPopup(ctx, "macro##" .. src.guid) then return end
  ImGui.TextDisabled(ctx, src.name .. "  \u{00B7}  Macro " .. src.i
    .. (src.kind == "xy" and (" + " .. (src.i + 1)) or ""))
  ImGui.Separator(ctx)
  rename_row(ctx, track, src)
  colour_menu(ctx, track, src)
  if ImGui.BeginMenu(ctx, "Show as") then
    local meta = MD.read_macros(track)
    for _, c in ipairs(MD.CTLS) do
      local ok = true
      if c.key == "xy" and src.kind ~= "xy" then ok = src.i < MD.NM and not meta[src.i + 1] end
      if ImGui.MenuItem(ctx, c.name .. "##ctl" .. c.key, nil, src.kind == c.key, ok) then
        if src.kind == "xy" and c.key ~= "xy" then
          local n = 0
          for _, l in ipairs(s.by_mod[src.guid] or {}) do if l.out == 2 then n = n + 1 end end
          if n == 0 or reaper.MB(("Y drives %d control%s. Its link%s will go.\n\nShow %s as a %s?"):format(
                n, n == 1 and "" or "s", n == 1 and "" or "s", src.name, c.name:lower()), "ChannelView", 4) == 6 then
            MD.set_ctl(track, src, c.key)
          end
        else
          MD.set_ctl(track, src, c.key)
        end
        req.changed = true
      end
      if c.key == "xy" and not ok and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, "XY pad needs two macros; the next one is in use")
      end
    end
    ImGui.EndMenu(ctx)
  end
  if src.kind == "dropdown" and ImGui.MenuItem(ctx, "Choices\u{2026}") then
    choice_buf[src.guid] = nil
    pending_popup = "mchoices##" .. src.guid
  end
  ImGui.Separator(ctx)
  if src.kind == "xy" then
    if ImGui.MenuItem(ctx, "Automation lane: X") then MD.toggle_lane(track, src.slot, src.out[1]) end
    if ImGui.MenuItem(ctx, "Automation lane: Y") then MD.toggle_lane(track, src.slot, src.out[2]) end
  elseif ImGui.MenuItem(ctx, "Automation lane") then
    MD.toggle_lane(track, src.slot, src.out[1])
  end
  local n = drives_menu(ctx, track, src, s, req)
  ImGui.Separator(ctx)
  remove_item(ctx, track, src, n, req)
  ImGui.EndPopup(ctx)
end

-- A dropdown's choices: how many (2-8) and their names.
local function choices_popup(ctx, track, src)
  if not ImGui.BeginPopup(ctx, "mchoices##" .. src.guid) then return end
  local buf = choice_buf[src.guid]
  if not buf then
    buf = {}
    for k, c in ipairs(src.choices or {}) do buf[k] = c end
    choice_buf[src.guid] = buf
  end
  ImGui.TextDisabled(ctx, "Choices for " .. src.name)
  ImGui.Separator(ctx)
  local dirty = false
  for k = 1, #buf do
    ImGui.SetNextItemWidth(ctx, 150)
    local _, t = ImGui.InputText(ctx, ("%d##ch%d%s"):format(k, k, src.guid), buf[k])
    buf[k] = t
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then dirty = true end
  end
  if #buf < 8 then
    if ImGui.Button(ctx, "Add a choice##" .. src.guid) then buf[#buf + 1] = tostring(#buf + 1); dirty = true end
    if #buf > 2 then ImGui.SameLine(ctx) end
  end
  if #buf > 2 and ImGui.Button(ctx, "Remove the last##" .. src.guid) then buf[#buf] = nil; dirty = true end
  if dirty then
    -- the macro stays on the choice it was on, or the last there is
    local n0 = #(src.choices or {})
    local c = n0 >= 2 and MD.choice_of(MD.value(track, src, 1), n0) or 1
    MD.set_choices(track, src, buf)
    c = math.min(c, #buf)
    MD.set_macro(track, src, 1, MD.choice_value(c, #buf))
  end
  ImGui.EndPopup(ctx)
end

local function macro_knob(ctx, dl, track, src, x, y, w)
  local v = MD.value(track, src, 1)
  local id = "mk##" .. src.guid
  local kw = 44
  local kx = x + (w - kw) * 0.5
  ImGui.SetCursorScreenPos(ctx, kx, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, kw, 40, ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local nv = v
  if act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    nv = W.drag_value(ctx, v) or v
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  elseif hov then
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then
      local step = C.WHEEL_STEP
      if (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 then step = step * C.FINE_MULT end
      nv = math.max(0, math.min(1, v + wheel * step))
      W.take_wheel()
    end
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then nv = 0 end
  end
  if nv ~= v then MD.set_macro(track, src, 1, nv) end
  W.knob_face(dl, x + w * 0.5, y + 18, 15, nv, { hot = hov or act, cap = src.col })
  W.push_small(ctx)
  local t = ("%d%%"):format(math.floor(nv * 100 + 0.5))
  local tw = ImGui.CalcTextSize(ctx, t)
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + 40, C.COL.value, t)
  W.pop_small(ctx)
  return ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
end

local function macro_button(ctx, dl, track, src, x, y, w)
  local on = MD.value(track, src, 1) >= 0.5
  local bw = 56
  if pill(ctx, dl, "mb##" .. src.guid, x + (w - bw) * 0.5, y + 10, bw, on and "On" or "Off", on, src.col, 22) then
    MD.set_macro(track, src, 1, on and 0 or 1)
  end
  return false
end

local function macro_fader(ctx, dl, track, src, x, y, w)
  local v = MD.value(track, src, 1)
  local fx0, fx1 = x + 8, x + w - 8
  local id = "mf##" .. src.guid
  ImGui.SetCursorScreenPos(ctx, fx0 - 6, y + 8)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, fx1 - fx0 + 12, 24, ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local nv = v
  if act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    local dx = ImGui.GetMouseDelta(ctx)
    if dx ~= 0 then
      local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and C.FINE_MULT or 1
      nv = math.max(0, math.min(1, v + dx / (fx1 - fx0) * fine))
    end
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
  elseif hov then
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then
      nv = math.max(0, math.min(1, v + wheel * C.WHEEL_STEP))
      W.take_wheel()
    end
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then nv = 0 end
  end
  if nv ~= v then MD.set_macro(track, src, 1, nv) end
  local ty = y + 20
  ImGui.DrawList_AddRectFilled(dl, fx0, ty - 3, fx1, ty + 3, C.COL.toggle_off, 3)
  ImGui.DrawList_AddRectFilled(dl, fx0, ty - 3, fx0 + (fx1 - fx0) * nv, ty + 3, U.with_alpha(src.col, 0x90), 3)
  local cx = fx0 + (fx1 - fx0) * nv
  ImGui.DrawList_AddRectFilled(dl, cx - 6, ty - 8, cx + 6, ty + 8, (hov or act) and 0xffffffff or 0xd8dbe0ff, 2)
  W.push_small(ctx)
  local t = ("%d%%"):format(math.floor(nv * 100 + 0.5))
  local tw = ImGui.CalcTextSize(ctx, t)
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + 40, C.COL.value, t)
  W.pop_small(ctx)
  return ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
end

local function macro_dropdown(ctx, dl, track, src, x, y, w)
  local n = #src.choices
  local c = MD.choice_of(MD.value(track, src, 1), n)
  local bx0, bx1, by = x + 6, x + w - 6, y + 12
  local id = "md##" .. src.guid
  ImGui.SetCursorScreenPos(ctx, bx0, by)
  W.allow_overlap(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, bx1 - bx0, 20,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov = ImGui.IsItemHovered(ctx)
  local rc = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
  if hov then
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then
      local nc = math.max(1, math.min(n, c - (wheel > 0 and 1 or -1)))
      MD.set_macro(track, src, 1, MD.choice_value(nc, n))
      c = nc
      W.take_wheel()
    end
  end
  if pressed then ImGui.OpenPopup(ctx, "mddl##" .. src.guid) end
  ImGui.DrawList_AddRectFilled(dl, bx0, by, bx1, by + 20, hov and C.COL.knob_body_hi or C.COL.toggle_off, 3)
  W.push_small(ctx)
  local t = U.truncate(src.choices[c] or "", 10)
  local _, th = ImGui.CalcTextSize(ctx, t)
  ImGui.DrawList_AddText(dl, bx0 + 6, by + (20 - th) * 0.5, C.COL.value, t)
  W.pop_small(ctx)
  local ax, ay = bx1 - 10, by + 8
  ImGui.DrawList_AddTriangleFilled(dl, ax - 3, ay, ax + 3, ay, ax, ay + 4, C.COL.label)
  W.push_small(ctx)
  local cnt = ("%d of %d"):format(c, n)
  local cw = ImGui.CalcTextSize(ctx, cnt)
  ImGui.DrawList_AddText(dl, x + (w - cw) * 0.5, y + 40, C.COL.header_dim, cnt)
  W.pop_small(ctx)
  if ImGui.BeginPopup(ctx, "mddl##" .. src.guid) then
    for k, name in ipairs(src.choices) do
      if ImGui.Selectable(ctx, name .. "##dc" .. k, k == c) then
        MD.set_macro(track, src, 1, MD.choice_value(k, n))
      end
    end
    ImGui.EndPopup(ctx)
  end
  return rc
end

local function macro_xy(ctx, dl, track, src, x, y, w, h)
  local vx, vy = MD.value(track, src, 1), MD.value(track, src, 2)
  -- square: the same distance for both axes
  local side = math.max(20, math.min(w - 12, h))
  local px0, py0 = x + (w - side) * 0.5, y + (h - side) * 0.5
  local px1, py1 = px0 + side, py0 + side
  local id = "mxy##" .. src.guid
  ImGui.SetCursorScreenPos(ctx, px0, py0)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, px1 - px0, py1 - py0, ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    local mx, my = ImGui.GetMousePos(ctx)
    local nx = math.max(0, math.min(1, (mx - px0) / (px1 - px0)))
    local ny = math.max(0, math.min(1, 1 - (my - py0) / (py1 - py0)))
    if nx ~= vx then MD.set_macro(track, src, 1, nx); vx = nx end
    if ny ~= vy then MD.set_macro(track, src, 2, ny); vy = ny end
  end
  ImGui.DrawList_AddRectFilled(dl, px0, py0, px1, py1, 0x121416ff, 3)
  ImGui.DrawList_AddRect(dl, px0, py0, px1, py1, (hov or act) and C.COL.label or C.COL.panel_border, 3, 0, 1)
  ImGui.DrawList_AddLine(dl, (px0 + px1) * 0.5, py0, (px0 + px1) * 0.5, py1, 0x2a2e33ff, 1)
  ImGui.DrawList_AddLine(dl, px0, (py0 + py1) * 0.5, px1, (py0 + py1) * 0.5, 0x2a2e33ff, 1)
  local dx, dy = px0 + (px1 - px0) * vx, py1 - (py1 - py0) * vy
  ImGui.DrawList_AddCircleFilled(dl, dx, dy, 5, src.col, 12)
  if hov or act then
    W.push_small(ctx)
    ImGui.DrawList_AddText(dl, px0 + 4, py1 - 13, C.COL.header_dim,
      ("X %d%%  Y %d%%"):format(math.floor(vx * 100 + 0.5), math.floor(vy * 100 + 0.5)))
    W.pop_small(ctx)
  end
  return ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
end

local function draw_macro(ctx, dl, track, src, s, x, y, w, h, req)
  local lit = MR.ctl_hover_prev and MR.ctl_hover_prev.guid == src.guid
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.panel_bg, 4)
  ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5,
    lit and src.col or C.COL.panel_border, 4, 0, lit and 2.0 or 1.0)
  -- the top: name (right-click for the menu), lane button, ◯
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, "mname##" .. src.guid, w, 18, ImGui.ButtonFlags_MouseButtonRight)
  local menu = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
  W.tip(ctx, "mname##" .. src.guid, "Right-click: rename, colour, change, remove", ImGui.IsItemHovered(ctx), false)
  local nm = U.truncate(src.name, src.kind == "xy" and 18 or 8)
  local tw = ImGui.CalcTextSize(ctx, nm)
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + 3, src.col, nm)
  local links = s.by_mod[src.guid] or {}
  if src.kind == "xy" then
    lane_button(ctx, dl, "mlx##" .. src.guid, x + 5, y + 5, track, src.slot, src.out[1], src.col, src.name .. " X")
    lane_button(ctx, dl, "mly##" .. src.guid, x + 5 + LANE_W + 3, y + 5, track, src.slot, src.out[2], src.col, src.name .. " Y")
    W.push_small(ctx)
    ImGui.DrawList_AddText(dl, x + w - 41, y + 3, C.COL.header_dim, "X")
    ImGui.DrawList_AddText(dl, x + w - 22, y + 3, C.COL.header_dim, "Y")
    W.pop_small(ctx)
    link_handle(ctx, dl, src, 1, x + w - 29, y + 10, 5, "X")
    link_handle(ctx, dl, src, 2, x + w - 10, y + 10, 5, "Y")
  else
    lane_button(ctx, dl, "ml##" .. src.guid, x + 5, y + 5, track, src.slot, src.out[1], src.col, src.name)
    link_handle(ctx, dl, src, 1, x + w - 10, y + 10, 5)
  end
  -- what it drives, small, under the name
  W.push_small(ctx)
  local sub = #links == 0 and "" or ("drives %d"):format(#links)
  local sw = ImGui.CalcTextSize(ctx, sub)
  ImGui.DrawList_AddText(dl, x + (w - sw) * 0.5, y + h - 13, C.COL.header_dim, sub)
  W.pop_small(ctx)
  -- the control
  local bx, by, bw = x, y + 22, w
  local rc
  if src.kind == "button" then rc = macro_button(ctx, dl, track, src, bx, by, bw)
  elseif src.kind == "fader" then rc = macro_fader(ctx, dl, track, src, bx, by, bw)
  elseif src.kind == "dropdown" then rc = macro_dropdown(ctx, dl, track, src, bx, by, bw)
  elseif src.kind == "xy" then rc = macro_xy(ctx, dl, track, src, bx, by, bw, h - 22 - 16)
  else rc = macro_knob(ctx, dl, track, src, bx, by, bw) end
  if menu or rc then
    rename_buf[src.guid] = src.name
    ImGui.OpenPopup(ctx, "macro##" .. src.guid)
  end
  macro_menu(ctx, track, src, s, req)
  if src.kind == "dropdown" then choices_popup(ctx, track, src) end
end

local function macro_add_menu(ctx, track, req)
  if not ImGui.BeginPopup(ctx, "macroadd") then return end
  ImGui.TextDisabled(ctx, "Add a macro as")
  ImGui.Separator(ctx)
  local meta = MD.read_macros(track)
  local two = false
  local used = {}
  for i, m in pairs(meta) do used[i] = true; if m.ctl == "xy" then used[i + 1] = true end end
  for i = 1, MD.NM - 1 do if not used[i] and not used[i + 1] then two = true end end
  for _, c in ipairs(MD.CTLS) do
    local ok = c.key ~= "xy" or two
    if ImGui.MenuItem(ctx, c.name .. "##madd" .. c.key, c.note, false, ok) then req.add_macro = c.key end
  end
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- MODULATORS
-- ---------------------------------------------------------------------

-- A modulator's recent outputs, against time. Sampled each frame but kept
-- only when the value has moved (the plugin updates it once per audio
-- block) or a while has passed, and drawn by WHEN they came, not one step
-- per frame: ChannelView's frames aren't evenly spaced and the plugin's
-- blocks don't line up with them, so plotting a point per frame would
-- draw a smooth LFO as a wobbly, stepped one.
local HIST_SEC = 2.5
local function sample(key, v)
  local now = reaper.time_precise()
  local h = hist[key]
  if not h then h = {}; hist[key] = h end
  local last = h[#h]
  if last and last[2] == v and now - last[1] < 0.1 then
    last.now = now                       -- still there: the trace runs on to now
    return
  end
  if last and last.now then h[#h + 1] = { last.now, last[2] } end   -- held until just now
  h[#h + 1] = { now, v }
  while #h > 2 and now - h[2][1] > HIST_SEC do table.remove(h, 1) end
end

local function draw_history(dl, key, col, x, y, w, h)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x121416ff, 3)
  local hs = hist[key]
  if not hs or #hs < 2 then return end
  local now = reaper.time_precise()
  local function px_of(t) return x + w - 2 - (w - 4) * (now - t) / HIST_SEC end
  local function py_of(v) return y + h - 2 - (h - 4) * math.max(0, math.min(1, v)) end
  ImGui.DrawList_PushClipRect(dl, x, y, x + w, y + h, true)
  local px, py
  for i = 1, #hs do
    local xx, yy = px_of(hs[i][1]), py_of(hs[i][2])
    if px then ImGui.DrawList_AddLine(dl, px, py, xx, yy, col, 1.5) end
    px, py = xx, yy
  end
  local lastp = hs[#hs]
  local ex = px_of(lastp.now or lastp[1])
  if ex > px then ImGui.DrawList_AddLine(dl, px, py, ex, py, col, 1.5); px = ex end
  ImGui.DrawList_PopClipRect(dl)
  ImGui.DrawList_AddCircleFilled(dl, px, py, 2.6, col, 8)
end

local SHAPE_FN = {
  function(t) return math.sin(t * 2 * math.pi) end,
  function(t) return 1 - 4 * math.abs(t - 0.5) end,
  function(t) return t < 0.5 and 1 or -1 end,
  function(t) return 2 * t - 1 end,
  function(t) return 1 - 2 * t end,
  function(t) return ({ 0.3, -0.7, 0.9, -0.2, 0.5, -0.9 })[math.floor(t * 6) % 6 + 1] end,
}

local function note_name(n)
  local names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
  n = math.floor(n + 0.5)
  return names[n % 12 + 1] .. (n // 12 - 1)
end

-- The knobs a modulator's settings are, by kind: { key, label, to 0..1,
-- from 0..1, text, default (real) }.
local function lin(lo, hi) return function(v) return (v - lo) / (hi - lo) end, function(n) return lo + n * (hi - lo) end end
local function sq(hi) return function(v) return math.sqrt(math.max(0, v) / hi) end, function(n) return hi * n * n end end
local function steps(lo, hi) return function(v) return (v - lo) / (hi - lo) end,
  function(n) return math.floor(lo + n * (hi - lo) + 0.5) end end

local K = {}
do
  local tn, fn
  tn, fn = lin(0, 1)
  K.depth = { key = "depth", label = "Depth", tn = tn, fn = fn, def = 1,
              text = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end }
  K.phase = { key = "phase", label = "Phase", tn = tn, fn = fn, def = 0,
              text = function(v) return ("%d\u{00B0}"):format(math.floor(v * 360 + 0.5)) end }
  K.smooth = { key = "smooth", label = "Smooth", tn = tn, fn = fn, def = 0,
               text = function(v) return v <= 0 and "Off" or ("%d ms"):format(math.floor(v * v * 500 + 0.5)) end }
  tn, fn = steps(0, 15)
  K.rsync = { key = "rsync", label = "Rate", tn = tn, fn = fn, def = 5,
              text = function(v) return MD.SYNC[math.floor(v + 0.5) + 1] or "?" end }
  K.rhz = { key = "rhz", label = "Rate", def = 1,
            tn = function(v) return math.log(math.max(0.01, v) / 0.01) / math.log(2000) end,
            fn = function(n) return 0.01 * 2000 ^ n end,
            text = function(v) return (v >= 1 and "%.2f Hz" or "%.3f Hz"):format(v) end }
  tn, fn = sq(500)
  K.att = { key = "att", label = "Attack", tn = tn, fn = fn, def = 10,
            text = function(v) return ("%.0f ms"):format(v) end }
  tn, fn = sq(2000)
  K.rel = { key = "rel", label = "Release", tn = tn, fn = fn, def = 200,
            text = function(v) return ("%.0f ms"):format(v) end }
  tn, fn = lin(-80, 0)
  K.floor = { key = "floor", label = "Floor", tn = tn, fn = fn, def = -48,
              text = function(v) return ("%.0f dB"):format(v) end }
  tn, fn = lin(-60, 12)
  K.ceil = { key = "ceil", label = "Ceiling", tn = tn, fn = fn, def = 0,
             text = function(v) return ("%.0f dB"):format(v) end }
  tn, fn = steps(0, 16)
  K.mch = { key = "mch", label = "Channel", tn = tn, fn = fn, def = 0,
            text = function(v) v = math.floor(v + 0.5) return v == 0 and "Omni" or ("Ch %d"):format(v) end }
  tn, fn = steps(0, 127)
  K.mcc = { key = "mcc", label = "CC", tn = tn, fn = fn, def = 1,
            text = function(v) return ("CC %d"):format(math.floor(v + 0.5)) end }
  K.mlo = { key = "mlo", label = "Low", tn = tn, fn = fn, def = 36, text = note_name }
  K.mhi = { key = "mhi", label = "High", tn = tn, fn = fn, def = 96, text = note_name }
end

-- ---------------------------------------------------------------------
-- THE MATRIX: a modulator's settings moved by a macro or another
-- modulator (TS_CV_Mod's mx_*). Drag a ◯ onto a knob (or a switch, from
-- a button or dropdown macro); the knob gets an arc in the source's
-- colour with a dot at its reach: drag the dot for the amount, Alt-click
-- it to remove.
-- ---------------------------------------------------------------------

local mx_cache = {}     -- track..j -> { t, slots }
local mx_slot_items     -- a source's menu items (below, with the tile's menu)
local function mx_slots(track, src)
  local key = tostring(track) .. ":" .. src.j
  local c = mx_cache[key]
  local now = reaper.time_precise()
  if not c or now - c.t > 0.2 then
    c = { t = now, slots = MD.mx_get(track, src.slot, src.j) }
    mx_cache[key] = c
  end
  return c.slots
end
local function mx_dirty() mx_cache = {} end
MR.mx_dirty = mx_dirty

-- A setting as the plugin is using it: a switch moved by a button or
-- dropdown macro shows the setting the macro picks (as the plugin works
-- it out, THE MATRIX in TS_CV_Modulators.jsfx); anything else its own.
local function live_field(track, src, key)
  local v = MD.field(track, src.slot, src.j, key)
  local code = MD.MX_CODE[key]
  local tg = code and MD.MX_TARGETS[code]
  if not (tg and tg.n and MD.mx_ok(track, src.slot)) then return v end
  for sl = 1, MD.MX_SLOTS do
    local e = mx_slots(track, src)[sl]
    if e and e.tg == tg then
      local from, k = MD.mx_source(track, e.code)
      if from then
        local n = math.max(2, e.nch)
        local i = math.min(MD.MX_MAX_CHOICES - 1, math.floor(MD.value(track, from, k) * (n - 1) + 0.5))
        local set = MD.mx_unpack(e.amt, n)[i + 1]
        if set then v = set end
      end
    end
  end
  return v
end

-- A drag over a target (a knob's circle, or a switch's rectangle): ring
-- it, say why not when it can't, link on release.
local function mx_drop(ctx, dl, track, src, key, set_to, hit, draw)
  local d = MR.drag
  if not (d and MD.mx_ok(track, src.slot)) then return end
  local ok, why = MD.mx_can(track, src, key, d.mod, d.k)
  if not ok and why == "Can't be moved" then return end
  local mx, my = ImGui.GetMousePos(ctx)
  local over = hit(mx, my)
  if not ok and not over then return end
  draw(ok and d.mod.col or (C.COL.warn or 0xe0a040ff), over)
  if over then
    if not ok then ImGui.SetTooltip(ctx, why)
    else ImGui.SetTooltip(ctx, ("%s moves %s %s"):format(d.mod.name, src.name, MD.MX_TARGETS[MD.MX_CODE[key]].label)) end
    if ok and ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) then
      local tg = MD.MX_TARGETS[MD.MX_CODE[key]]
      if MD.mx_link(track, src, key, d.mod, d.k, set_to) and tg.n and d.mod.kind == "dropdown" then
        -- a dropdown on a switch: its choices become the switch's, one for
        -- one (asked first, unless they already are)
        local names = MD.mx_names(key)
        local same = table.concat(names, "\0") == table.concat(d.mod.choices or {}, "\0")
        if same or reaper.MB(("Use %s's settings as %s's choices?\n\n%s"):format(
             tg.label, d.mod.name, table.concat(names, ", ")), "ChannelView", 4) == 6 then
          if not same then
            local n0 = #(d.mod.choices or {})
            local c = n0 >= 2 and MD.choice_of(MD.value(track, d.mod, 1), n0) or 1
            MD.set_choices(track, d.mod, names)
            MD.invalidate(track)
            MD.set_macro(track, MD.find(track, d.mod.guid) or d.mod, 1, MD.choice_value(math.min(c, #names), #names))
          end
          MD.mx_direct(track, src, key, d.mod, d.k)
        end
      end
      mx_dirty()
    end
  end
end

-- The amount, as text: a share of the knob, or whole steps.
local function mx_amount_text(key, amt)
  if key == "rsync" then return ("%+d steps"):format(math.floor(amt * 15 + (amt >= 0 and 0.5 or -0.5))) end
  if key == "mlo" or key == "mhi" then return ("%+d notes"):format(math.floor(amt * 127 + (amt >= 0 and 0.5 or -0.5))) end
  return ("%+d%%"):format(math.floor(amt * 100 + (amt >= 0 and 0.5 or -0.5)))
end

-- What moves a setting, as the knob shows it -- the same as a plugin
-- control linked to a macro or a modulator (TS_CV_Panel's range_ends):
--   from a macro: the knob sits where the macro puts it, and the ring's
--     two ends are where it is at the macro's 0% (the knob's own setting)
--     and at 100% (+ the amount)
--   from a modulator: the knob moves with it, and the ends are where it
--     is at rest (its own setting) and at full (+ the amount x that
--     modulator's Depth)
-- In the knob's own 0..1. The first end is the setting itself, shared by
-- both sources; each source has its own second end.
local function mx_view(track, src, key, base)
  local code = MD.MX_CODE[key]
  local list, live = {}, base
  if not code then return list, live end
  for sl = 1, MD.MX_SLOTS do
    local e = mx_slots(track, src)[sl]
    if e and e.tg.code == code then
      local from, k = MD.mx_source(track, e.code)
      local D = (from and from.src == "mod") and MD.field(track, from.slot, from.j, "depth") or 1
      local sv = from and MD.value(track, from, k) or 0
      live = live + e.amt * sv
      list[#list + 1] = { sl = sl, e = e, from = from, D = math.max(0.001, D),
                          to = base + e.amt * D }
    end
  end
  return list, math.max(0, math.min(1, live))
end

-- The rings and their handles on a moved knob.
local function mx_rings(ctx, dl, track, src, d, base, list, live, x, y)
  local cx, cy = x + KCELL_W * 0.5, y + 11 + KR + 1
  for i, m in ipairs(list) do
    local col = m.from and m.from.col or C.COL.label
    local r = KR + (i - 1) * 4
    local to = math.max(0, math.min(1, m.to))
    local ends = (i == 1) and { base, to } or { to }
    local hot_end
    for ei, ev in ipairs(ends) do
      local which = (i == 1 and ei == 1) and 1 or 2       -- 1: the setting, 2: this source's reach
      local id = ("mxe%d%d##%s%s"):format(m.sl, which, src.guid, d.key)
      local hx, hy = W.ring_point(cx, cy, r, ev)
      ImGui.SetCursorScreenPos(ctx, hx - 6, hy - 6)
      W.allow_overlap(ctx)
      ImGui.InvisibleButton(ctx, id, 12, 12)
      local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
      if hov or act then hot_end = ei; ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand) end
      if hov and which == 2 and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left)
         and (ImGui.GetKeyMods(ctx) & ImGui.Mod_Alt) ~= 0 then
        MD.mx_unlink(track, src, m.sl)
        mx_dirty()
      elseif act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
        local mx, my = ImGui.GetMousePos(ctx)
        local nv = W.ring_value(cx, cy, mx, my)
        if which == 1 then
          -- the setting moves; every source's reach stays where it is
          for _, o in ipairs(list) do
            o.e.amt = math.max(-1, math.min(1, (math.max(0, math.min(1, o.to)) - nv) / o.D))
            MD.mx_set_amount(track, src, o.sl, o.e.amt)
          end
          MD.set_field(track, src.slot, src.j, d.key, d.fn(nv))
        else
          m.e.amt = math.max(-1, math.min(1, (nv - base) / m.D))
          MD.mx_set_amount(track, src, m.sl, m.e.amt)
        end
      end
      local nm = m.from and m.from.name or "?"
      local tip
      if m.from and m.from.src == "macro" then
        tip = ("Value at %s of %s\nDrag: set"):format(which == 1 and "0%" or "100%", nm)
      else
        tip = ("%s swing, %s\nDrag: set"):format(nm, which == 1 and "at rest" or "at full")
      end
      if which == 2 then tip = tip .. "\nAlt-click: remove" end
      W.tip(ctx, id, tip, hov and not act, false)
    end
    W.mod_ring(dl, cx, cy, r, { col = col, lo = math.min(base, to), hi = math.max(base, to),
      ends = (i == 1) and { base, to } or { to }, hot_end = hot_end and ((i == 1) and hot_end or 1),
      live = live, hot = hot_end ~= nil or (m.from and MR.hover == m.from.guid) })
    if m.from then MR.note_target(m.from.guid, "mx" .. src.guid, d.key .. m.sl, cx, cy) end
  end
end

-- A knob's right-click: what moves it.
local function mx_knob_menu(ctx, track, src, d)
  local pid = "mxk##" .. src.guid .. d.key
  if not ImGui.BeginPopup(ctx, pid) then return end
  local code = MD.MX_CODE[d.key]
  ImGui.TextDisabled(ctx, d.label:upper() .. " \u{00B7} MOVED BY")
  local any = false
  for sl, e in pairs(mx_slots(track, src)) do
    if e.tg.code == code then
      any = true
      local from = MD.mx_source(track, e.code)
      if ImGui.BeginMenu(ctx, ("%s   %s##mxk%d"):format(from and from.name or "?", mx_amount_text(d.key, e.amt), sl)) then
        if ImGui.MenuItem(ctx, "Reverse the direction") then MD.mx_set_amount(track, src, sl, -e.amt); mx_dirty() end
        if ImGui.MenuItem(ctx, "Remove") then MD.mx_unlink(track, src, sl); mx_dirty() end
        ImGui.EndMenu(ctx)
      end
    end
  end
  if not any then ImGui.TextDisabled(ctx, "nothing: drag a \u{25EF} here") end
  ImGui.EndPopup(ctx)
end

-- A switch (a pill, or one of the LFO's shapes) as a drop target, with a
-- dot in each source's colour on the setting it picks.
local function mx_switch(ctx, dl, track, src, key, set_to, x, y, w, h)
  -- right-click: what moves this switch
  local pid = ("mxs%s%d##%s"):format(key, set_to, src.guid)
  if MD.mx_ok(track, src.slot) and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then ImGui.OpenPopup(ctx, pid) end
  if ImGui.BeginPopup(ctx, pid) then
    local tg = MD.MX_TARGETS[MD.MX_CODE[key]]
    ImGui.TextDisabled(ctx, tg.label:upper() .. " \u{00B7} MOVED BY")
    local any = false
    for sl = 1, MD.MX_SLOTS do
      local e = mx_slots(track, src)[sl]
      if e and e.tg.code == tg.code then
        any = true
        local from = MD.mx_source(track, e.code)
        if ImGui.BeginMenu(ctx, ("%s##mxs%d"):format(from and from.name or "?", sl)) then
          mx_slot_items(ctx, track, src, sl, e, from)
          ImGui.EndMenu(ctx)
        end
      end
    end
    if not any then ImGui.TextDisabled(ctx, "nothing: drag a button or dropdown macro's \u{25EF} here") end
    ImGui.EndPopup(ctx)
  end
  mx_drop(ctx, dl, track, src, key, set_to,
    function(mx, my) return mx >= x and mx < x + w and my >= y and my < y + h end,
    function(col, over) ImGui.DrawList_AddRect(dl, x - 1, y - 1, x + w + 1, y + h + 1, col, 3, 0, over and 2.0 or 1.0) end)
  local code = MD.MX_CODE[key]
  local n = 0
  for _, e in pairs(mx_slots(track, src)) do
    if e.tg.code == code then
      local map = MD.mx_unpack(e.amt, math.max(2, e.nch))
      for _, set in pairs(map) do
        if set == set_to then
          local from = MD.mx_source(track, e.code)
          ImGui.DrawList_AddCircleFilled(dl, x + w - 3 - n * 6, y + 3, 2.4, from and from.col or C.COL.label, 8)
          n = n + 1
        end
      end
    end
  end
end

-- The settings knob with its lane button. A moved setting's knob sits
-- where its sources put it; turning it moves the setting under them
-- (both ends with it), as a linked plugin control does.
local function setting(ctx, dl, track, src, d, x, y)
  local v = MD.field(track, src.slot, src.j, d.key)
  local base = d.tn(v)
  local mxd = MD.MX_CODE[d.key] and MD.mx_ok(track, src.slot)
  local list, live = {}, base
  if mxd then list, live = mx_view(track, src, d.key, base) end
  local shown = (#list > 0) and live or base
  local ch, nv = tknob(ctx, dl, d.key .. "##" .. src.guid, x, y, shown, d.label, d.text(d.fn(shown)),
    d.tn(d.def), src.col)
  if ch then
    local delta = nv - shown
    if #list > 0 then
      -- keep every end inside 0..1
      local lo, hi = base, base
      for _, m in ipairs(list) do lo = math.min(lo, m.to); hi = math.max(hi, m.to) end
      delta = math.max(-lo, math.min(1 - hi, delta))
    end
    base = math.max(0, math.min(1, base + delta))
    MD.set_field(track, src.slot, src.j, d.key, d.fn(base))
    for _, m in ipairs(list) do m.to = m.to + delta end
  end
  if mxd then
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
      ImGui.OpenPopup(ctx, "mxk##" .. src.guid .. d.key)
    end
    local cx, cy = x + KCELL_W * 0.5, y + 11 + KR + 1
    mx_drop(ctx, dl, track, src, d.key, nil,
      function(mx, my) return (mx - cx) ^ 2 + (my - cy) ^ 2 <= (KR + 10) ^ 2 end,
      function(col, over) ImGui.DrawList_AddCircle(dl, cx, cy, KR + 8, U.with_alpha(col, over and 0xff or 0x48), 24, over and 2.0 or 1.0) end)
    if #list > 0 then mx_rings(ctx, dl, track, src, d, base, list, live, x, y) end
    mx_knob_menu(ctx, track, src, d)
  end
  lane_button(ctx, dl, "lane" .. d.key .. "##" .. src.guid, x + KCELL_W - LANE_W - 1, y + 13,
    track, src.slot, MD.param(src.j, d.key), src.col, src.name .. " " .. d.label)
end

-- The fields a modulator's lanes menu offers, by kind.
local LANES = {
  lfo = { { "rsync", "Rate (synced)" }, { "rhz", "Rate (Hz)" }, { "depth", "Depth" }, { "phase", "Phase" },
          { "shape", "Shape" }, { "sync", "Sync / Free" }, { "smooth", "Smooth" } },
  follower = { { "att", "Attack" }, { "rel", "Release" }, { "floor", "Floor" }, { "ceil", "Ceiling" },
               { "gate", "Gate" }, { "fsrc", "Source" }, { "depth", "Depth" }, { "smooth", "Smooth" } },
  midi = { { "msrc", "Source" }, { "mch", "Channel" }, { "mcc", "CC" }, { "mlo", "Low note" }, { "mhi", "High note" },
           { "mhold", "Hold" }, { "depth", "Depth" }, { "smooth", "Smooth" } },
}

local function sub_text(track, src, nlinks)
  local d = nlinks == 0 and "drag \u{25EF} onto a control" or ("drives %d"):format(nlinks)
  local f = function(k) return live_field(track, src, k) end
  if src.kind == "lfo" then
    local rate = f("sync") >= 0.5 and (MD.SYNC[math.floor(f("rsync") + 0.5) + 1] or "?")
                 or ("%.2f Hz"):format(f("rhz"))
    return d .. " \u{00B7} " .. rate .. " \u{00B7} " .. (MD.SHAPES[math.floor(f("shape") + 0.5) + 1] or ""):lower()
  elseif src.kind == "follower" then
    return (f("fsrc") >= 0.5 and "sidechain" or "track") .. (f("gate") >= 0.5 and " gate" or "") .. " \u{00B7} " .. d
  end
  local ms = math.floor(f("msrc") + 0.5)
  local what = MD.MIDI_SRC[ms + 1] or "MIDI"
  if ms == 2 then what = ("CC %d"):format(math.floor(f("mcc") + 0.5)) end
  return what .. " \u{00B7} " .. d
end

local function lfo_body(ctx, dl, track, src, key, x, y, w, isopen)
  draw_history(dl, key, src.col, x, y, w, 26)
  if not isopen then return end
  y = y + 30
  local shape = math.floor(live_field(track, src, "shape") + 0.5)
  local bw = (w - 5 * 2) / 6
  for i = 1, 6 do
    local bx = x + (i - 1) * (bw + 2)
    ImGui.SetCursorScreenPos(ctx, bx, y)
    if ImGui.InvisibleButton(ctx, ("shape%d##%s"):format(i, src.guid), bw, 18) then
      MD.set_field(track, src.slot, src.j, "shape", i - 1)
    end
    local hov = ImGui.IsItemHovered(ctx)
    W.tip(ctx, ("shape%d##%s"):format(i, src.guid), MD.SHAPES[i], hov, false)
    mx_switch(ctx, dl, track, src, "shape", i - 1, bx, y, bw, 18)
    local on = (shape == i - 1)
    ImGui.DrawList_AddRectFilled(dl, bx, y, bx + bw, y + 18,
      on and C.COL.accent or (hov and C.COL.knob_body_hi or C.COL.toggle_off), 3)
    local f, px, py = SHAPE_FN[i], nil, nil
    for st = 0, 12 do
      local t = st / 12
      local xx, yy = bx + 3 + (bw - 6) * t, y + 9 - f(t) * 5.5
      if px then ImGui.DrawList_AddLine(dl, px, py, xx, yy, on and C.COL.icon_on or C.COL.label, 1.2) end
      px, py = xx, yy
    end
  end
  y = y + 22
  local sync = live_field(track, src, "sync") >= 0.5
  setting(ctx, dl, track, src, sync and K.rsync or K.rhz, x, y)
  setting(ctx, dl, track, src, K.depth, x + KCELL_W, y)
  setting(ctx, dl, track, src, K.phase, x + KCELL_W * 2, y)
  y = y + KCELL_H
  setting(ctx, dl, track, src, K.smooth, x, y)
  local px = x + KCELL_W + 8
  if pill(ctx, dl, "sync##" .. src.guid, px, y + 8, 46, "Sync", sync) and not sync then
    MD.set_field(track, src.slot, src.j, "sync", 1)
  end
  mx_switch(ctx, dl, track, src, "sync", 1, px, y + 8, 46, PILL_H)
  if pill(ctx, dl, "free##" .. src.guid, px + 50, y + 8, 46, "Free", not sync) and sync then
    MD.set_field(track, src.slot, src.j, "sync", 0)
  end
  mx_switch(ctx, dl, track, src, "sync", 0, px + 50, y + 8, 46, PILL_H)
end

local function level_bar(dl, src, v, x, y, w)
  ImGui.DrawList_AddRectFilled(dl, x, y + 2, x + w, y + 10, 0x121416ff, 2)
  ImGui.DrawList_AddRectFilled(dl, x, y + 2, x + w * math.max(0, math.min(1, v)), y + 10, src.col, 2)
end

local function follower_body(ctx, dl, track, src, x, y, w, isopen)
  level_bar(dl, src, MD.value(track, src), x, y, w)
  if not isopen then return end
  y = y + 16
  local side = live_field(track, src, "fsrc") >= 0.5
  local gate = live_field(track, src, "gate") >= 0.5
  if pill(ctx, dl, "main##" .. src.guid, x, y, 52, "Track", not side) and side then
    MD.set_field(track, src.slot, src.j, "fsrc", 0)
  end
  mx_switch(ctx, dl, track, src, "fsrc", 0, x, y, 52, PILL_H)
  if pill(ctx, dl, "side##" .. src.guid, x + 55, y, 64, "Sidechain", side) and not side then
    MD.set_field(track, src.slot, src.j, "fsrc", 1)
    MD.need_sidechain(track)
  end
  mx_switch(ctx, dl, track, src, "fsrc", 1, x + 55, y, 64, PILL_H)
  if pill(ctx, dl, "gate##" .. src.guid, x + w - 44, y, 44, "Gate", gate) then
    MD.set_field(track, src.slot, src.j, "gate", gate and 0 or 1)
  end
  mx_switch(ctx, dl, track, src, "gate", gate and 0 or 1, x + w - 44, y, 44, PILL_H)
  W.tip(ctx, "gate##" .. src.guid, "All or nothing at the Floor", ImGui.IsItemHovered(ctx), false)
  y = y + 22
  setting(ctx, dl, track, src, K.att, x, y)
  setting(ctx, dl, track, src, K.rel, x + KCELL_W, y)
  setting(ctx, dl, track, src, K.depth, x + KCELL_W * 2, y)
  y = y + KCELL_H
  setting(ctx, dl, track, src, K.floor, x, y)
  if not gate then setting(ctx, dl, track, src, K.ceil, x + KCELL_W, y) end
  setting(ctx, dl, track, src, K.smooth, x + KCELL_W * 2, y)
end

local MIDI_PILL = { "Vel", "Note", "CC", "Bend", "AT" }

local function midi_body(ctx, dl, track, src, x, y, w, isopen)
  level_bar(dl, src, MD.value(track, src), x, y, w)
  if not isopen then return end
  y = y + 16
  local ms = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
  local pw = (w - 4 * 2) / 5
  for i = 1, 5 do
    if pill(ctx, dl, ("msrc%d##%s"):format(i, src.guid), x + (i - 1) * (pw + 2), y, pw, MIDI_PILL[i], ms == i - 1) then
      MD.set_field(track, src.slot, src.j, "msrc", i - 1)
    end
    W.tip(ctx, ("msrc%d##%s"):format(i, src.guid), MD.MIDI_SRC[i], ImGui.IsItemHovered(ctx), false)
  end
  y = y + 22
  setting(ctx, dl, track, src, K.mch, x, y)
  if ms == 1 then
    setting(ctx, dl, track, src, K.mlo, x + KCELL_W, y)
    setting(ctx, dl, track, src, K.mhi, x + KCELL_W * 2, y)
  elseif ms == 2 then
    setting(ctx, dl, track, src, K.mcc, x + KCELL_W, y)
  elseif ms == 0 then
    local hold = live_field(track, src, "mhold") >= 0.5
    if pill(ctx, dl, "hold##" .. src.guid, x + KCELL_W + 6, y + 14, 46, "Hold", hold) then
      MD.set_field(track, src.slot, src.j, "mhold", hold and 0 or 1)
    end
    mx_switch(ctx, dl, track, src, "mhold", hold and 0 or 1, x + KCELL_W + 6, y + 14, 46, PILL_H)
    W.tip(ctx, "hold##" .. src.guid, "Keep the last velocity after note-off",
      ImGui.IsItemHovered(ctx), false)
  end
  y = y + KCELL_H
  setting(ctx, dl, track, src, K.depth, x, y)
  setting(ctx, dl, track, src, K.smooth, x + KCELL_W, y)
end

-- One source's items (in the tile's menu, or a switch's): a switch's
-- setting for each of the macro's choices, or Reverse; and Remove.
mx_slot_items = function(ctx, track, src, sl, e, from)
  if e.tg.n then
    -- a switch: its setting for each of the macro's choices
    local nch = math.max(2, e.nch)
    local map = MD.mx_unpack(e.amt, nch)
    local names = MD.mx_names(e.tg.key)
    for c = 1, nch do
      local label = (from and from.kind == "button") and (c == 1 and "Off" or "On")
        or (from and from.choices and from.choices[c]) or ("Choice " .. c)
      if ImGui.BeginMenu(ctx, ("%s:  %s##mxc%d"):format(label, map[c] and names[map[c] + 1] or "its own", c)) then
        if ImGui.MenuItem(ctx, "Its own setting", nil, map[c] == nil) then
          map[c] = nil; MD.mx_set_amount(track, src, sl, MD.mx_pack(map, nch)); mx_dirty()
        end
        for v = 0, e.tg.n - 1 do
          if ImGui.MenuItem(ctx, names[v + 1] .. "##mxv" .. v, nil, map[c] == v) then
            map[c] = v; MD.mx_set_amount(track, src, sl, MD.mx_pack(map, nch)); mx_dirty()
          end
        end
        ImGui.EndMenu(ctx)
      end
    end
    ImGui.Separator(ctx)
  else
    if ImGui.MenuItem(ctx, "Reverse the direction") then MD.mx_set_amount(track, src, sl, -e.amt); mx_dirty() end
  end
  if ImGui.MenuItem(ctx, "Remove") then MD.mx_unlink(track, src, sl); mx_dirty() end
end

local function mod_menu(ctx, track, src, s, req)
  if not ImGui.BeginPopup(ctx, "modtile##" .. src.guid) then return end
  ImGui.TextDisabled(ctx, src.name .. "  \u{00B7}  " .. MD.KIND_NAME[src.kind] .. "  \u{00B7}  Mod " .. src.j)
  ImGui.Separator(ctx)
  rename_row(ctx, track, src)
  colour_menu(ctx, track, src)
  if ImGui.BeginMenu(ctx, "Automation lanes") then
    local function item(key, label)
      local l = MD.lane(track, src.slot, MD.param(src.j, key))
      local note = l and (l.auto and "has automation" or (l.shown and "shown" or "hidden")) or nil
      if ImGui.MenuItem(ctx, label .. "##lane" .. key, note, l ~= nil and l.shown) then
        MD.toggle_lane(track, src.slot, MD.param(src.j, key))
      end
    end
    for _, f in ipairs(LANES[src.kind] or {}) do item(f[1], f[2]) end
    ImGui.Separator(ctx)
    item("out", "Output")
    item("outb", "Output bipolar")
    ImGui.EndMenu(ctx)
  end
  local n = drives_menu(ctx, track, src, s, req)
  -- what moves it (THE MATRIX)
  local slots = MD.mx_ok(track, src.slot) and mx_slots(track, src) or {}
  if next(slots) then
    ImGui.Separator(ctx)
    local cnt = 0
    for _ in pairs(slots) do cnt = cnt + 1 end
    ImGui.TextDisabled(ctx, ("MOVED BY (%d of %d)"):format(cnt, MD.MX_SLOTS))
    for sl = 1, MD.MX_SLOTS do
      local e = slots[sl]
      if e then
        local from = MD.mx_source(track, e.code)
        local name = from and from.name or "?"
        local amt = e.tg.n and "" or ("   " .. mx_amount_text(e.tg.key == "rate"
          and (live_field(track, src, "sync") >= 0.5 and "rsync" or "rhz") or e.tg.key, e.amt))
        if ImGui.BeginMenu(ctx, ("%s \u{2192} %s%s##mxt%d"):format(name, e.tg.label, amt, sl)) then
          mx_slot_items(ctx, track, src, sl, e, from)
          ImGui.EndMenu(ctx)
        end
      end
    end
  end
  ImGui.Separator(ctx)
  remove_item(ctx, track, src, n, req)
  ImGui.EndPopup(ctx)
end

local function draw_tile(ctx, dl, track, src, s, x, y, h, req)
  local w = MR.TILE_W
  local key = tostring(track) .. src.guid
  local isopen = open[key]
  sample(key, MD.value(track, src))
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.panel_bg, 4)
  local lit = MR.ctl_hover_prev and MR.ctl_hover_prev.guid == src.guid
  ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5,
    (isopen or lit) and src.col or C.COL.panel_border, 4, 0, lit and 2.0 or 1.0)
  ImGui.DrawList_AddRectFilled(dl, x + 6, y + 6, x + 14, y + 14, src.col, 2)
  -- held at rest: this one bypassed, or all of them
  local own_byp = MD.bypassed(track, src.slot, src.j)
  local held = own_byp or MD.bypassed(track, src.slot)
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, "name##" .. src.guid, w - 42, HEAD,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then open[key] = not isopen or nil end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    rename_buf[src.guid] = src.name
    ImGui.OpenPopup(ctx, "modtile##" .. src.guid)
  end
  W.tip(ctx, "name##" .. src.guid, isopen and "Click: close\nRight-click: more"
    or "Click: settings\nRight-click: lanes, rename, colour, remove", ImGui.IsItemHovered(ctx), false)
  local nm = U.truncate(src.name, 18)
  ImGui.DrawList_AddText(dl, x + 19, y + 3, held and C.COL.header_dim or C.COL.header_text, nm)
  if MD.bypass_ok(track, src.slot) then
    ImGui.SetCursorScreenPos(ctx, x + w - 38, y + 2)
    if W.icon_button(ctx, "byp##" .. src.guid, "power", C.ICON_SIZE, own_byp,
        own_byp and "Bypassed: the controls it drives sit where they're set\nClick: move them again"
        or (held and "All the modulators are bypassed (the panel's header)"
            or "Bypass: hold it still, to hear the track without it"),
        C.COL.bypass_on) then
      MD.set_bypass(track, src.slot, src.j, not own_byp)
    end
  end
  -- a dot for each source moving it (THE MATRIX)
  do
    local slots = MD.mx_ok(track, src.slot) and mx_slots(track, src) or {}
    local dx = x + 19 + ImGui.CalcTextSize(ctx, nm) + 7
    local names = {}
    for sl = 1, MD.MX_SLOTS do
      local e = slots[sl]
      if e then
        local from = MD.mx_source(track, e.code)
        ImGui.DrawList_AddCircleFilled(dl, dx, y + 10, 3, from and from.col or C.COL.label, 10)
        names[#names + 1] = (from and from.name or "?") .. " \u{2192} " .. e.tg.label
        dx = dx + 8
      end
    end
    if #names > 0 then
      local mx, my = ImGui.GetMousePos(ctx)
      if mx >= dx - 8 * #names - 4 and mx < dx and my >= y + 4 and my < y + 16 then
        ImGui.SetTooltip(ctx, "Moved by\n" .. table.concat(names, "\n"))
      end
    end
  end
  local links = s.by_mod[src.guid] or {}
  W.push_small(ctx)
  local sub = held and ("bypassed \u{00B7} " .. sub_text(track, src, #links)) or sub_text(track, src, #links)
  ImGui.DrawList_AddText(dl, x + 8, y + HEAD - 1, held and C.COL.bypass_on or C.COL.header_dim, U.truncate(sub, 34))
  W.pop_small(ctx)
  link_handle(ctx, dl, src, 1, x + w - 12, y + 9, 5.5)
  local bx, by, bw = x + 6, y + HEAD + SUB + 2, w - 12
  if src.kind == "lfo" then lfo_body(ctx, dl, track, src, key, bx, by, bw, isopen)
  elseif src.kind == "follower" then follower_body(ctx, dl, track, src, bx, by, bw, isopen)
  else midi_body(ctx, dl, track, src, bx, by, bw, isopen) end
  mod_menu(ctx, track, src, s, req)
end

local function mod_add_menu(ctx, req)
  if not ImGui.BeginPopup(ctx, "modadd") then return end
  ImGui.TextDisabled(ctx, "Add a modulator")
  ImGui.Separator(ctx)
  local notes = { lfo = "tempo-synced or free", follower = "a signal's level", midi = "velocity, note, CC, bend" }
  for _, k in ipairs(MD.KINDS) do
    if ImGui.MenuItem(ctx, MD.KIND_NAME[k] .. "##madd" .. k, notes[k]) then req.add_mod = k end
  end
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- the panels
-- ---------------------------------------------------------------------

local TITLE = { macros = "Macros", mods = "Modulators" }
local function btn_size() return C.ICON_SIZE end

-- A toolbar button for the Bypass modulation action
-- (TS_ChannelView_BypassModulation.lua) lit while this track's modulators
-- are bypassed: the action says which command it is.
local lit_was = nil
local function light_action(on)
  if on == lit_was then return end
  lit_was = on
  local sec, cmd = reaper.GetExtState(C.EXT_SECT, "bypass_mods_cmd"):match("^(%-?%d+):(%d+)$")
  if sec and tonumber(cmd) > 0 then
    reaper.SetToggleCommandState(tonumber(sec), tonumber(cmd), on and 1 or 0)
    reaper.RefreshToolbar2(tonumber(sec), tonumber(cmd))
  end
end

local function slim(ctx, dl, which, x, y, ww, wh, n)
  local btn = C.ICON_SIZE
  if MR.STRIP_W then
    -- folded in a strip: a header bar, the title left and the unfold right
    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.header_bg, 3.0)
    local label = TITLE[which] .. (n > 0 and (" · " .. n) or "")
    local _, th = ImGui.CalcTextSize(ctx, label)
    ImGui.DrawList_AddText(dl, x + 6, y + (wh - th) * 0.5, C.COL.header_dim, label)
    ImGui.SetCursorScreenPos(ctx, x + ww - btn - 3, y + (wh - btn) * 0.5)
    if W.icon_button(ctx, which .. "exp", "expand", btn, false, "Show the " .. TITLE[which]:lower()) then
      set_collapsed(which, false)
    end
    MR.bar_at[which] = { x + 12, y + wh * 0.5 }
    return
  end
  ImGui.SetCursorScreenPos(ctx, x + (ww - btn) * 0.5, y + 4)
  if W.icon_button(ctx, which .. "exp", "expand", btn, false, "Show the " .. TITLE[which]:lower()) then
    set_collapsed(which, false)
  end
  local label = TITLE[which]:upper() .. (n > 0 and (" " .. n) or "")
  W.vertical_text(ctx, dl, x + ww * 0.5, y + 4 + btn + 6, label, C.COL.header_dim, wh - btn - 16)
  MR.bar_at[which] = { x + ww * 0.5, y + wh * 0.4 }
end

-- `extra(bx, by)`, when given, draws a button left of the fold button.
local function frame_of(ctx, dl, which, x, y, ww, wh, foot, extra)
  local btn = C.ICON_SIZE
  ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + C.HEADER_H, C.COL.header_bg, 0)
  ImGui.DrawList_AddLine(dl, x, y + C.HEADER_H, x + ww, y + C.HEADER_H, C.COL.panel_border, 1.0)
  local _, th = ImGui.CalcTextSize(ctx, TITLE[which])
  ImGui.DrawList_AddText(dl, x + 6, y + (C.HEADER_H - th) * 0.5, C.COL.header_text, TITLE[which])
  ImGui.SetCursorScreenPos(ctx, x + ww - btn - 3, y + 3)
  if W.icon_button(ctx, which .. "col", "collapse", btn, false, "Fold the " .. TITLE[which]:lower() .. " away") then
    set_collapsed(which, true)
  end
  if extra then extra(x + ww - 2 * btn - 7, y + 3) end
  -- the foot, as every panel's: how many are in use, centred
  local fh = C.FOOTER_H
  local fy = y + wh - fh
  ImGui.DrawList_AddRectFilled(dl, x + 1, fy, x + ww - 1, y + wh - 1, C.COL.header_bg, 2.5,
    ImGui.DrawFlags_RoundCornersBottom)
  ImGui.DrawList_AddLine(dl, x, fy, x + ww, fy, C.COL.panel_border, 1.0)
  W.push_small(ctx)
  local tw, fth = ImGui.CalcTextSize(ctx, foot)
  ImGui.DrawList_AddText(dl, x + (ww - tw) * 0.5, fy + (fh - fth) * 0.5, C.COL.header_dim, foot)
  W.pop_small(ctx)
end

local function draw_child(ctx, which, track, avail_h, inside)
  local w = MR.width_for(which, track, avail_h)
  local req = {}
  local sp_x, sp_y = ImGui.GetCursorPos(ctx)
  local ok = ImGui.BeginChild(ctx, "##" .. which .. "panel", w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    inside(req)
    ImGui.EndChild(ctx)
  else
    W.child_skipped(ctx, w, avail_h, sp_x, sp_y)
  end
  return w, req
end

-- The Macros panel at the cursor. Returns its width and a req:
-- { add_macro = ctl, changed, show_fx = guid }.
function MR.draw_macros(ctx, track, avail_h)
  return draw_child(ctx, "macros", track, avail_h, function(req)
    local s = MD.scan(track)
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, 3.0)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, 3.0, 0, 1.0)
    if pending_popup and pending_popup:find("^mchoices") then
      ImGui.OpenPopup(ctx, pending_popup)
      pending_popup = nil
    end
    local used = track and MD.macros_used(track) or 0
    if not track or MR.is_collapsed("macros") or ww <= C.COLLAPSED_W + 0.5 then
      slim(ctx, dl, "macros", x, y, ww, wh, #s.macros)
      return
    end
    frame_of(ctx, dl, "macros", x, y, ww, wh, ("%d of %d used"):format(used, MD.NM))
    local gx, gy = x + C.PANEL_PAD, y + C.HEADER_H + C.PANEL_PAD
    local placed, _, add = place_macros(s.macros, room_of(wh + 0), used < MD.NM)
    for _, p in ipairs(placed) do
      draw_macro(ctx, dl, track, p.src, s, gx + p.x, gy + p.y, p.w, p.h, req)
    end
    if add then
      ImGui.SetCursorScreenPos(ctx, gx + add.x, gy + add.y)
      if W.dashed_plus(ctx, "macroadd_foot", GROUP_W, ADD_H, "Add a macro") then
        ImGui.OpenPopup(ctx, "macroadd")
      end
    end
    macro_add_menu(ctx, track, req)
  end)
end

-- The Modulators panel at the cursor. Returns its width and a req:
-- { add_mod = kind, changed, show_fx = guid }.
function MR.draw_mods(ctx, track, avail_h)
  return draw_child(ctx, "mods", track, avail_h, function(req)
    local s = MD.scan(track)
    if track then light_action(MD.bypassed(track, s.mods[1] and s.mods[1].slot)) end
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, 3.0)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, 3.0, 0, 1.0)
    if not track or MR.is_collapsed("mods") or ww <= C.COLLAPSED_W + 0.5 then
      slim(ctx, dl, "mods", x, y, ww, wh, #s.mods)
      return
    end
    local slot = s.mods[1] and s.mods[1].slot
    frame_of(ctx, dl, "mods", x, y, ww, wh, ("%d of %d used"):format(#s.mods, MD.NO),
      MD.bypass_ok(track, slot) and function(bx, by)
        local on = MD.bypassed(track, slot)
        ImGui.SetCursorScreenPos(ctx, bx, by)
        if W.icon_button(ctx, "modsbyp", "power", btn_size(), on,
            on and "All bypassed: every control they drive sits where it's set\nClick: move them again"
            or "Bypass all: hold every modulator still, to hear the track without them",
            C.COL.bypass_on) then
          MD.set_bypass(track, slot, nil, not on)
        end
      end or nil)
    local gx, gy = x + C.PANEL_PAD, y + C.HEADER_H + C.PANEL_PAD
    local placed, _, add = place_mods(track, s.mods, room_of(wh), not mods_full(s))
    for _, p in ipairs(placed) do
      draw_tile(ctx, dl, track, p.src, s, gx + p.x, gy + p.y, p.h, req)
    end
    if add then
      ImGui.SetCursorScreenPos(ctx, gx + add.x, gy + add.y)
      if W.dashed_plus(ctx, "modadd_foot", MR.TILE_W, ADD_H, "Add a modulator") then
        ImGui.OpenPopup(ctx, "modadd")
      end
    end
    mod_add_menu(ctx, req)
  end)
end

-- ---------------------------------------------------------------------
-- on top of everything: the lines to a source's controls, and the one
-- following a drag. Call last in the frame.
-- ---------------------------------------------------------------------
function MR.overlay(ctx, track, panel_at)
  local dl = ImGui.GetForegroundDrawList(ctx)
  local function line(x1, y1, x2, y2, col, a)
    local mx = (x1 + x2) * 0.5
    ImGui.DrawList_AddBezierCubic(dl, x1, y1, mx, y1, mx, y2, x2, y2, U.with_alpha(col, a), 1.6, 0)
  end
  if MR.drag then
    local mx, my = ImGui.GetMousePos(ctx)
    line(MR.drag.x, MR.drag.y, mx, my, MR.drag.mod.col, 0xc0)
    ImGui.DrawList_AddCircle(dl, mx, my, 6, MR.drag.mod.col, 16, 2)
    if not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then MR.drag = nil end
    return
  end
  -- a linked control under the pointer: its line back to its source (its
  -- ◯, or the folded panel)
  local ch = MR.ctl_hover
  if ch and track then
    local src = MD.find(track, ch.guid)
    local which = src and (src.src == "macro" and "macros" or "mods")
    local h0 = MR.handles[ch.guid .. "#" .. ch.k] or MR.handles[ch.guid] or (which and MR.bar_at[which])
    if src and h0 then
      line(h0[1], h0[2], ch.x, ch.y, src.col, 0x90)
      ImGui.DrawList_AddCircle(dl, ch.x, ch.y, 4, U.with_alpha(src.col, 0xc0), 12, 1.5)
    end
  end
  local g = MR.hover
  if not (g and track) then return end
  local h = MR.handles[g]
  if not h then return end
  local src = MD.find(track, g)
  if not src then return end
  local s = MD.scan(track)
  local here = {}
  for _, pt in ipairs(seen[g] or {}) do
    here[pt.key] = true
    line(h[1], h[2], pt[1], pt[2], src.col, 0x80)
    ImGui.DrawList_AddCircle(dl, pt[1], pt[2], 4, U.with_alpha(src.col, 0xb0), 12, 1.5)
  end
  -- controls not on screen: the line goes to their plugin's panel, once
  if panel_at then
    local done = {}
    for _, l in ipairs(s.by_mod[g] or {}) do
      if not here[l.tguid .. ":" .. l.tparam] and not done[l.tguid] then
        done[l.tguid] = true
        local r = panel_at(l.tguid)
        if r then line(h[1], h[2], r[1], r[2], src.col, 0x50) end
      end
    end
  end
end

return MR
