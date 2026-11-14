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
local MP = require("TS_CV_ModPat")

local ImGui
local MR = {}
function MR.attach(imgui) ImGui = imgui end

-- sizes, at 100% (Z: at the overall size, C.UI)
local SIZE = {
  GAP = 6,
  CELL_W = 80, CELL_H = 86,   -- a macro's cell
  TILE_W = 180,               -- a modulator's tile
  HEAD = 18,                  -- a tile's name row
  SUB = 13,                   -- its "drives 3" line
  KCELL_W = 56, KCELL_H = 48, -- a knob in a tile: its cell
  KR = 11,                    -- ...and its radius
  ADD_H = 22, PILL_H = 16,
  ENV_CURVE_H = 44,           -- a MIDI envelope's curve
  LANE_W = 13, LANE_H = 11,
}
local Z = setmetatable({}, { __index = function(_, k) local v = SIZE[k]; return v and C.S(v) end })
MR.SIZE = Z

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

local GROUP_W = Z.CELL_W * 2 + Z.GAP

-- Macro cells, two to a row (an XY pad takes a row), down then into the
-- next pair of columns. { src, x, y, w, h } from the grid's top-left, the
-- number of column pairs, and where the add tile goes.
local function place_macros(macros, room, with_add)
  local out, gx, y, col, groups = {}, 0, 0, 0, 1
  local function newrow() y = y + Z.CELL_H + Z.GAP; col = 0 end
  for _, src in ipairs(macros) do
    -- an XY pad: both columns and two rows, so the pad can be square
    local wide = src.kind == "xy"
    local ch = wide and (Z.CELL_H * 2 + Z.GAP) or Z.CELL_H
    if wide and col == 1 then newrow() end
    if y > 0 and y + ch > room and col == 0 then
      gx, y, groups = gx + GROUP_W + Z.GAP, 0, groups + 1
    end
    local w = wide and GROUP_W or Z.CELL_W
    out[#out + 1] = { src = src, x = gx + col * (Z.CELL_W + Z.GAP), y = y, w = w, h = ch }
    if wide then y = y + ch + Z.GAP; col = 0
    elseif col == 1 then newrow() else col = 1 end
  end
  local add
  if with_add then
    if col == 1 then newrow() end
    if y > 0 and y + Z.ADD_H > room then gx, y, groups = gx + GROUP_W + Z.GAP, 0, groups + 1 end
    add = { x = gx, y = y }
  end
  return out, groups, add
end

-- (Steps and MSEG: their bodies' heights, set where they're drawn)
local body_h = {}
-- A tile's width: a Steps or MSEG opened takes two columns
local function tile_w(track, src)
  if (src.kind == "steps" or src.kind == "mseg") and open[tostring(track) .. src.guid] then
    return Z.TILE_W * 2 + Z.GAP
  end
  return Z.TILE_W
end

local function tile_h(track, src)
  local isopen = open[tostring(track) .. src.guid]
  local h = Z.HEAD + Z.SUB
  if body_h[src.kind] then
    h = h + body_h[src.kind](track, src, isopen)
  elseif src.kind == "lfo" then
    h = h + C.S(30)
    if isopen then h = h + C.S(22) + Z.KCELL_H * 2 end
  elseif src.kind == "midi" then
    h = h + C.S(16)
    if isopen then
      local ms = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
      h = h + C.S(22) + 20 + Z.KCELL_H * 2 + (MD.trig_ok(track, src.slot) and 22 or 0)
      if MD.is_env(ms) then h = h + Z.ENV_CURVE_H + 6 + Z.KCELL_H + 22 end
    end
  else
    h = h + C.S(16)
    if isopen then
      local ms = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
      h = h + C.S(22) + 20 + (MD.is_env(ms) and (Z.ENV_CURVE_H + 6 + Z.KCELL_H * 3 + 22) or Z.KCELL_H * 2)
      if MD.field(track, src.slot, src.j, "fsrc") >= 0.5 then h = h + C.S(22) end
    end
  end
  return h + C.S(6)
end

-- Tiles down, then into another column; a column as wide as its widest
-- (an opened Steps or MSEG's two). Returns the places, the columns, the
-- add tile's place and the width they take.
local function place_mods(track, mods, room, with_add)
  local out, x, y, cols, cw = {}, 0, 0, 1, Z.TILE_W
  for _, src in ipairs(mods) do
    local h, w = tile_h(track, src), tile_w(track, src)
    if y > 0 and y + h > room then x, y, cols, cw = x + cw + Z.GAP, 0, cols + 1, Z.TILE_W end
    out[#out + 1] = { src = src, x = x, y = y, h = h }
    cw = math.max(cw, w)
    y = y + h + Z.GAP
  end
  local add
  if with_add then
    if y > 0 and y + Z.ADD_H > room then x, y, cols, cw = x + cw + Z.GAP, 0, cols + 1, Z.TILE_W end
    add = { x = x, y = y }
  end
  return out, cols, add, x + cw
end

local function macros_full(track) return MD.macros_used(track) >= MD.NM end
local function mods_full(s) return #s.mods >= MD.NO end

-- the width the cells want at this height
local function natural_w(which, track, panel_h)
  local s = MD.scan(track)
  if which == "macros" then
    local _, groups = place_macros(s.macros, room_of(panel_h), not macros_full(track))
    return groups * GROUP_W + (groups - 1) * Z.GAP + C.PANEL_PAD * 2
  end
  local _, _, _, wide = place_mods(track, s.mods, room_of(panel_h), not mods_full(s))
  return wide + C.PANEL_PAD * 2
end

function MR.width_for(which, track, panel_h)
  if not track or MR.is_collapsed(which) then return MR.STRIP_W or C.COLLAPSED_W end
  local w = natural_w(which, track, panel_h)
  return MR.STRIP_W and math.max(w, MR.STRIP_W) or w
end

-- Strip mode: the folded bar's height, and the least height at which the
-- cells fit across w (or the tallest tried, when nothing does).
function MR.bar_h() return C.HEADER_H + C.S(2) end
function MR.strip_h(which, track, w)
  if not track or MR.is_collapsed(which) then return MR.bar_h() end
  local s = MD.scan(track)
  local rows = {}
  if which == "macros" then
    local tall = Z.CELL_H
    for _, src in ipairs(s.macros) do
      if src.kind == "xy" then tall = Z.CELL_H * 2 + Z.GAP end
    end
    if #s.macros == 0 then rows[1] = Z.ADD_H end   -- just the add tile
    for n = 1, 8 do
      local room = n * (Z.CELL_H + Z.GAP) - Z.GAP
      if room >= tall then rows[#rows + 1] = room end
    end
  else
    local tall = Z.ADD_H
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
  ImGui.InvisibleButton(ctx, id, Z.KCELL_W, Z.KCELL_H)
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
  local cx, cy = x + Z.KCELL_W * 0.5, y + C.S(11) + Z.KR + 1
  W.push_small(ctx)
  if label and label ~= "" then
    local tw = ImGui.CalcTextSize(ctx, label)
    ImGui.DrawList_AddText(dl, cx - tw * 0.5, y, C.COL.label, label)
  end
  W.knob_face(dl, cx, cy, Z.KR, nv, { hot = hov or act, cap = col })
  local vw = ImGui.CalcTextSize(ctx, text or "")
  ImGui.DrawList_AddText(dl, cx - vw * 0.5, cy + Z.KR + 2, C.COL.value, text or "")
  W.pop_small(ctx)
  return changed, nv
end

-- A small push-button; returns pressed.
local function pill(ctx, dl, id, x, y, w, text, on, col, h)
  h = h or Z.PILL_H
  ImGui.SetCursorScreenPos(ctx, x, y)
  local pressed = ImGui.InvisibleButton(ctx, id, w, h)
  local hov = ImGui.IsItemHovered(ctx)
  local bg = on and (col or C.COL.accent) or (hov and C.COL.knob_body_hi or C.COL.toggle_off)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 3)
  W.push_small(ctx)
  local tw, th = ImGui.CalcTextSize(ctx, text)
  -- lit in a modulator's own colour: dark ink on a light one
  local ink = on and (U.is_light(bg) and 0x0d1116ff or C.COL.icon_on) or C.COL.label
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + (h - th) * 0.5, ink, text)
  W.pop_small(ctx)
  return pressed
end

-- The lane button: makes / shows / hides a parameter's automation lane.
-- Lit (filled in `col`) while the parameter has automation.
local function lane_button(ctx, dl, id, x, y, track, slot, param, col, what)
  ImGui.SetCursorScreenPos(ctx, x - C.S(2), y - C.S(2))
  W.allow_overlap(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, Z.LANE_W + 4, Z.LANE_H + 4,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov = ImGui.IsItemHovered(ctx)
  local rclick = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
  pressed = pressed and not rclick
  local lane = MD.lane(track, slot, param)
  local ink
  if lane and lane.auto then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + Z.LANE_W, y + Z.LANE_H, col, 2)
    ink = 0x15171aff
  else
    -- shown: its colour; there but hidden: its colour, faint; none: grey
    local edge = (lane and lane.shown) and col or (lane and U.with_alpha(col, 0x80))
                 or (hov and C.COL.label or 0x4a4f57ff)
    ink = lane and (lane.shown and C.COL.value or U.with_alpha(col, 0xa0))
          or (hov and C.COL.label or C.COL.header_dim)
    ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + Z.LANE_W - 0.5, y + Z.LANE_H - 0.5, edge, 2, 0, 1)
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
    if ImGui.InvisibleButton(ctx, ("col%d##%s"):format(i, src.guid), C.S(18), 18) then
      MD.set_colour(track, src, c)
      ImGui.CloseCurrentPopup(ctx)
    end
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + C.S(18), y + C.S(18), c, 3)
    if c == src.col then ImGui.DrawList_AddRect(dl, x - C.S(1), y - C.S(1), x + C.S(19), y + C.S(19), 0xffffffff, 3, 0, 1.5) end
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
  local kw = C.S(44)
  local kx = x + (w - kw) * 0.5
  ImGui.SetCursorScreenPos(ctx, kx, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, kw, C.S(40), ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
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
  W.knob_face(dl, x + w * 0.5, y + C.S(18), C.S(15), nv, { hot = hov or act, cap = src.col })
  W.push_small(ctx)
  local t = ("%d%%"):format(math.floor(nv * 100 + 0.5))
  local tw = ImGui.CalcTextSize(ctx, t)
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + C.S(40), C.COL.value, t)
  W.pop_small(ctx)
  return ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
end

local function macro_button(ctx, dl, track, src, x, y, w)
  local on = MD.value(track, src, 1) >= 0.5
  local bw = C.S(56)
  if pill(ctx, dl, "mb##" .. src.guid, x + (w - bw) * 0.5, y + C.S(10), bw, on and "On" or "Off", on, src.col, 22) then
    MD.set_macro(track, src, 1, on and 0 or 1)
  end
  return false
end

local function macro_fader(ctx, dl, track, src, x, y, w)
  local v = MD.value(track, src, 1)
  local fx0, fx1 = x + C.S(8), x + w - C.S(8)
  local id = "mf##" .. src.guid
  ImGui.SetCursorScreenPos(ctx, fx0 - 6, y + C.S(8))
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, fx1 - fx0 + 12, C.S(24), ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
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
  local ty = y + C.S(20)
  ImGui.DrawList_AddRectFilled(dl, fx0, ty - C.S(3), fx1, ty + C.S(3), C.COL.toggle_off, 3)
  ImGui.DrawList_AddRectFilled(dl, fx0, ty - C.S(3), fx0 + (fx1 - fx0) * nv, ty + C.S(3), U.with_alpha(src.col, 0x90), 3)
  local cx = fx0 + (fx1 - fx0) * nv
  ImGui.DrawList_AddRectFilled(dl, cx - C.S(6), ty - C.S(8), cx + C.S(6), ty + C.S(8), (hov or act) and 0xffffffff or 0xd8dbe0ff, 2)
  W.push_small(ctx)
  local t = ("%d%%"):format(math.floor(nv * 100 + 0.5))
  local tw = ImGui.CalcTextSize(ctx, t)
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + C.S(40), C.COL.value, t)
  W.pop_small(ctx)
  return ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
end

local function macro_dropdown(ctx, dl, track, src, x, y, w)
  local n = #src.choices
  local c = MD.choice_of(MD.value(track, src, 1), n)
  local bx0, bx1, by = x + C.S(6), x + w - C.S(6), y + C.S(12)
  local id = "md##" .. src.guid
  ImGui.SetCursorScreenPos(ctx, bx0, by)
  W.allow_overlap(ctx)
  local pressed = ImGui.InvisibleButton(ctx, id, bx1 - bx0, C.S(20),
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
  ImGui.DrawList_AddRectFilled(dl, bx0, by, bx1, by + C.S(20), hov and C.COL.knob_body_hi or C.COL.toggle_off, 3)
  W.push_small(ctx)
  local t = U.truncate(src.choices[c] or "", 10)
  local _, th = ImGui.CalcTextSize(ctx, t)
  ImGui.DrawList_AddText(dl, bx0 + 6, by + (20 - th) * 0.5, C.COL.value, t)
  W.pop_small(ctx)
  local ax, ay = bx1 - 10, by + C.S(8)
  ImGui.DrawList_AddTriangleFilled(dl, ax - 3, ay, ax + 3, ay, ax, ay + 4, C.COL.label)
  W.push_small(ctx)
  local cnt = ("%d of %d"):format(c, n)
  local cw = ImGui.CalcTextSize(ctx, cnt)
  ImGui.DrawList_AddText(dl, x + (w - cw) * 0.5, y + C.S(40), C.COL.header_dim, cnt)
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
  local side = math.max(20, math.min(w - C.S(12), h))
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
  ImGui.InvisibleButton(ctx, "mname##" .. src.guid, w, C.S(18), ImGui.ButtonFlags_MouseButtonRight)
  local menu = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
  W.tip(ctx, "mname##" .. src.guid, "Right-click: rename, colour, change, remove", ImGui.IsItemHovered(ctx), false)
  local nm = U.truncate(src.name, src.kind == "xy" and 18 or 8)
  local tw = ImGui.CalcTextSize(ctx, nm)
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, y + C.S(3), src.col, nm)
  local links = s.by_mod[src.guid] or {}
  if src.kind == "xy" then
    lane_button(ctx, dl, "mlx##" .. src.guid, x + C.S(5), y + C.S(5), track, src.slot, src.out[1], src.col, src.name .. " X")
    lane_button(ctx, dl, "mly##" .. src.guid, x + C.S(5) + Z.LANE_W + 3, y + C.S(5), track, src.slot, src.out[2], src.col, src.name .. " Y")
    W.push_small(ctx)
    ImGui.DrawList_AddText(dl, x + w - C.S(41), y + C.S(3), C.COL.header_dim, "X")
    ImGui.DrawList_AddText(dl, x + w - C.S(22), y + C.S(3), C.COL.header_dim, "Y")
    W.pop_small(ctx)
    link_handle(ctx, dl, src, 1, x + w - C.S(29), y + C.S(10), C.S(5), "X")
    link_handle(ctx, dl, src, 2, x + w - C.S(10), y + C.S(10), C.S(5), "Y")
  else
    lane_button(ctx, dl, "ml##" .. src.guid, x + C.S(5), y + C.S(5), track, src.slot, src.out[1], src.col, src.name)
    link_handle(ctx, dl, src, 1, x + w - C.S(10), y + C.S(10), C.S(5))
  end
  -- what it drives, small, under the name
  W.push_small(ctx)
  local sub = #links == 0 and "" or ("drives %d"):format(#links)
  local sw = ImGui.CalcTextSize(ctx, sub)
  ImGui.DrawList_AddText(dl, x + (w - sw) * 0.5, y + h - C.S(13), C.COL.header_dim, sub)
  W.pop_small(ctx)
  -- the control
  local bx, by, bw = x, y + C.S(22), w
  local rc
  if src.kind == "button" then rc = macro_button(ctx, dl, track, src, bx, by, bw)
  elseif src.kind == "fader" then rc = macro_fader(ctx, dl, track, src, bx, by, bw)
  elseif src.kind == "dropdown" then rc = macro_dropdown(ctx, dl, track, src, bx, by, bw)
  elseif src.kind == "xy" then rc = macro_xy(ctx, dl, track, src, bx, by, bw, h - C.S(22) - 16)
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
  local function px_of(t) return x + w - C.S(2) - (w - C.S(4)) * (now - t) / HIST_SEC end
  local function py_of(v) return y + h - C.S(2) - (h - C.S(4)) * math.max(0, math.min(1, v)) end
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
-- (a whole number of steps: STEPPED, for setting's turning)
local STEPPED = {}
local function steps(lo, hi)
  local fn = function(n) return math.floor(lo + n * (hi - lo) + 0.5) end
  STEPPED[fn] = true
  return function(v) return (v - lo) / (hi - lo) end, fn
end

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
  -- a MIDI envelope's, kept in the Follower's fields (MD.MIDI_SRC)
  tn, fn = lin(-80, 0)
  K.sus = { key = "floor", label = "Sustain", tn = tn, fn = fn, def = MD.floor_of(0.6),
            text = function(v) return ("%d%%"):format(math.floor(MD.sustain_of(v) * 100 + 0.5)) end }
  tn, fn = lin(-60, 12)
  K.dec = { key = "ceil", label = "Decay", tn = tn, fn = fn, def = MD.ceil_of(200),
            text = function(v) return ("%.0f ms"):format(MD.decay_of(v)) end }
  K.eatt = { key = "att", label = "Attack", tn = K.att.tn, fn = K.att.fn, def = 5, text = K.att.text }
  K.erel = { key = "rel", label = "Release", tn = K.rel.tn, fn = K.rel.fn, def = 300, text = K.rel.text }
  K.mhi = { key = "mhi", label = "High", tn = tn, fn = fn, def = 96, text = note_name }
  -- a Follower's envelope's (MD.FOLLOW_ENV): Floor its threshold, Decay
  -- and Sustain in MIDI CC and Low note
  K.thr = { key = "floor", label = "Threshold", tn = K.floor.tn, fn = K.floor.fn, def = -24, text = K.floor.text }
  tn, fn = lin(0, 127)
  K.fdec = { key = "mcc", label = "Decay", tn = tn, fn = fn, def = MD.mcc_of(200),
             text = function(v) return ("%.0f ms"):format(MD.fdecay_of(v)) end }
  K.fsus = { key = "mlo", label = "Sustain", tn = tn, fn = fn, def = MD.mlo_of(0.6),
             text = function(v) return ("%d%%"):format(math.floor(MD.fsus_of(v) * 100 + 0.5)) end }
end

-- ---------------------------------------------------------------------
-- THE MATRIX: a modulator's settings moved by a macro or another
-- modulator (TS_CV_Mod's mx_*). Drag a ◯ onto a knob (or a switch, from
-- a button or dropdown macro); the knob gets an arc in the source's
-- colour with a dot at its reach: drag the dot for the amount, Alt-click
-- it to remove.
-- ---------------------------------------------------------------------

-- A setting's name in THE MATRIX: an envelope's own, for the Follower
-- fields a MIDI envelope keeps its settings in
local ENV_LABEL = { floor = "Sustain", ceil = "Decay", gate = "Exp curve", mhold = "Legato" }
-- a Follower's envelope's: Floor its threshold, Low note its Sustain
local FENV_LABEL = { floor = "Threshold", mlo = "Sustain", gate = "Exp curve", mhold = "Legato" }
-- a Steps' own names for the fields it keeps its settings in
local STEPS_LABEL = { floor = "Swing", smooth = "Glide", ceil = "Gate", att = "Steps" }
local function tg_label(track, src, tg)
  if src.kind == "steps" and STEPS_LABEL[tg.key] then return STEPS_LABEL[tg.key] end
  if src.kind == "mseg" and tg.key == "floor" then return "Threshold" end
  local env = MD.is_env(math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5))
  if env and src.kind == "midi" and ENV_LABEL[tg.key] then return ENV_LABEL[tg.key] end
  if env and src.kind == "follower" and FENV_LABEL[tg.key] then return FENV_LABEL[tg.key] end
  return tg.label
end

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
    else ImGui.SetTooltip(ctx, ("%s moves %s %s"):format(d.mod.name, src.name, tg_label(track, src, MD.MX_TARGETS[MD.MX_CODE[key]]))) end
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
  local cx, cy = x + Z.KCELL_W * 0.5, y + C.S(11) + Z.KR + 1
  for i, m in ipairs(list) do
    local col = m.from and m.from.col or C.COL.label
    local r = Z.KR + (i - 1) * 4
    local to = math.max(0, math.min(1, m.to))
    local ends = (i == 1) and { base, to } or { to }
    local hot_end
    for ei, ev in ipairs(ends) do
      local which = (i == 1 and ei == 1) and 1 or 2       -- 1: the setting, 2: this source's reach
      local id = ("mxe%d%d##%s%s"):format(m.sl, which, src.guid, d.key)
      local hx, hy = W.ring_point(cx, cy, r, ev)
      ImGui.SetCursorScreenPos(ctx, hx - C.S(6), hy - C.S(6))
      W.allow_overlap(ctx)
      ImGui.InvisibleButton(ctx, id, C.S(12), 12)
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
    ImGui.TextDisabled(ctx, tg_label(track, src, tg):upper() .. " \u{00B7} MOVED BY")
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
    function(col, over) ImGui.DrawList_AddRect(dl, x - C.S(1), y - C.S(1), x + w + C.S(1), y + h + C.S(1), col, 3, 0, over and 2.0 or 1.0) end)
  local code = MD.MX_CODE[key]
  local n = 0
  for _, e in pairs(mx_slots(track, src)) do
    if e.tg.code == code then
      local map = MD.mx_unpack(e.amt, math.max(2, e.nch))
      for _, set in pairs(map) do
        if set == set_to then
          local from = MD.mx_source(track, e.code)
          ImGui.DrawList_AddCircleFilled(dl, x + w - C.S(3) - n * 6, y + C.S(3), 2.4, from and from.col or C.COL.label, 8)
          n = n + 1
        end
      end
    end
  end
end

-- The settings knob with its lane button. A moved setting's knob sits
-- where its sources put it; turning it moves the setting under them
-- (both ends with it), as a linked plugin control does.
-- A stepped setting (the synced Rate) is turned through the places between
-- its steps: kept while it's being turned, as what it's set to rounds.
local turning = {}
local function setting(ctx, dl, track, src, d, x, y)
  local v = MD.field(track, src.slot, src.j, d.key)
  local base = d.tn(v)
  local hk = d.key .. src.guid
  local h = turning[hk]
  if h and (reaper.time_precise() - h.t > 0.5 or d.fn(h.n) ~= v) then turning[hk], h = nil, nil end
  if h then base = h.n end
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
    if STEPPED[d.fn] then turning[hk] = { n = base, t = reaper.time_precise() } end
    for _, m in ipairs(list) do m.to = m.to + delta end
  end
  if mxd then
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
      ImGui.OpenPopup(ctx, "mxk##" .. src.guid .. d.key)
    end
    local cx, cy = x + Z.KCELL_W * 0.5, y + C.S(11) + Z.KR + 1
    mx_drop(ctx, dl, track, src, d.key, nil,
      function(mx, my) return (mx - cx) ^ 2 + (my - cy) ^ 2 <= (Z.KR + 10) ^ 2 end,
      function(col, over) ImGui.DrawList_AddCircle(dl, cx, cy, Z.KR + 8, U.with_alpha(col, over and 0xff or 0x48), 24, over and 2.0 or 1.0) end)
    if #list > 0 then mx_rings(ctx, dl, track, src, d, base, list, live, x, y) end
    mx_knob_menu(ctx, track, src, d)
  end
  lane_button(ctx, dl, "lane" .. d.key .. "##" .. src.guid, x + Z.KCELL_W - Z.LANE_W - 1, y + C.S(13),
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
  fenv = { { "msrc", "Envelope" }, { "att", "Attack" }, { "mcc", "Decay" }, { "mlo", "Sustain" }, { "rel", "Release" },
           { "floor", "Threshold" }, { "ceil", "Ceiling" }, { "mhold", "Legato" }, { "gate", "Exp curve" },
           { "fsrc", "Source" }, { "depth", "Depth" }, { "smooth", "Smooth" } },
  steps = { { "rsync", "Step length" }, { "rhz", "Rate (Hz)" }, { "depth", "Depth" }, { "smooth", "Glide" },
            { "floor", "Swing" }, { "phase", "Phase" }, { "att", "Steps" }, { "shape", "Direction" } },
  mseg = { { "rsync", "Length" }, { "rhz", "Rate (Hz)" }, { "depth", "Depth" }, { "phase", "Phase" },
           { "smooth", "Smooth" }, { "mhold", "Loop" } },
  env = { { "msrc", "Source" }, { "att", "Attack" }, { "ceil", "Decay" }, { "floor", "Sustain" }, { "rel", "Release" },
          { "mhold", "Legato" }, { "gate", "Exp curve" }, { "mch", "Channel" }, { "mlo", "Low note" },
          { "mhi", "High note" }, { "depth", "Depth" }, { "smooth", "Smooth" } },
}
local function lanes_of(track, src)
  local env = MD.is_env(math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5))
  if src.kind == "midi" and env then return LANES.env end
  if src.kind == "follower" and env then return LANES.fenv end
  return LANES[src.kind]
end

local function sub_text(track, src, nlinks)
  local d = nlinks == 0 and "drag \u{25EF} onto a control" or ("drives %d"):format(nlinks)
  local f = function(k) return live_field(track, src, k) end
  if src.kind == "lfo" then
    local rate = f("sync") >= 0.5 and (MD.SYNC[math.floor(f("rsync") + 0.5) + 1] or "?")
                 or ("%.2f Hz"):format(f("rhz"))
    return d .. " \u{00B7} " .. rate .. " \u{00B7} " .. (MD.SHAPES[math.floor(f("shape") + 0.5) + 1] or ""):lower()
  elseif src.kind == "steps" then
    local rate = f("sync") >= 0.5 and (MD.SYNC[math.floor(f("rsync") + 0.5) + 1] or "?")
                 or ("%.2f Hz"):format(f("rhz"))
    local out = math.floor(f("msrc") + 0.5)
    return d .. " \u{00B7} " .. rate .. " \u{00B7} " .. math.floor(f("att") + 0.5) .. " steps"
      .. ((out == 1) and " \u{00B7} CC" or (out == 2) and " \u{00B7} notes" or "")
  elseif src.kind == "mseg" then
    local len = f("sync") >= 0.5 and (MD.SYNC[math.floor(f("rsync") + 0.5) + 1] or "?")
                or ("%.2f Hz"):format(f("rhz"))
    return d .. " \u{00B7} " .. len .. " \u{00B7} " .. (({ "song", "free", "note", "audio" })[math.floor(f("msrc") + 0.5) + 1] or "")
  elseif src.kind == "follower" then
    local ms = math.floor(f("msrc") + 0.5)
    local how = MD.is_env(ms) and (" " .. (MD.FOLLOW_ENV[ms - MD.ENV_FIRST + 1] or ""):lower())
      or (f("gate") >= 0.5 and " gate" or "")
    return (f("fsrc") >= 0.5 and "sidechain" or "track") .. how .. " \u{00B7} " .. d
  end
  local ms = math.floor(f("msrc") + 0.5)
  local what = MD.MIDI_SRC[ms + 1] or "MIDI"
  if ms == 2 then what = ("CC %d"):format(math.floor(f("mcc") + 0.5)) end
  if MD.trigger(track, src.j) then what = what .. " \u{00B7} another track" end
  return what .. " \u{00B7} " .. d
end

local function lfo_body(ctx, dl, track, src, key, x, y, w, isopen)
  draw_history(dl, key, src.col, x, y, w, 26)
  if not isopen then return end
  y = y + C.S(30)
  local shape = math.floor(live_field(track, src, "shape") + 0.5)
  local bw = (w - 5 * 2) / 6
  for i = 1, 6 do
    local bx = x + (i - 1) * (bw + C.S(2))
    ImGui.SetCursorScreenPos(ctx, bx, y)
    if ImGui.InvisibleButton(ctx, ("shape%d##%s"):format(i, src.guid), bw, 18) then
      MD.set_field(track, src.slot, src.j, "shape", i - 1)
    end
    local hov = ImGui.IsItemHovered(ctx)
    W.tip(ctx, ("shape%d##%s"):format(i, src.guid), MD.SHAPES[i], hov, false)
    mx_switch(ctx, dl, track, src, "shape", i - 1, bx, y, bw, 18)
    local on = (shape == i - 1)
    ImGui.DrawList_AddRectFilled(dl, bx, y, bx + bw, y + C.S(18),
      on and C.COL.accent or (hov and C.COL.knob_body_hi or C.COL.toggle_off), 3)
    local f, px, py = SHAPE_FN[i], nil, nil
    for st = 0, 12 do
      local t = st / 12
      local xx, yy = bx + C.S(3) + (bw - C.S(6)) * t, y + C.S(9) - f(t) * 5.5
      if px then ImGui.DrawList_AddLine(dl, px, py, xx, yy, on and C.COL.icon_on or C.COL.label, 1.2) end
      px, py = xx, yy
    end
  end
  y = y + C.S(22)
  local sync = live_field(track, src, "sync") >= 0.5
  setting(ctx, dl, track, src, sync and K.rsync or K.rhz, x, y)
  setting(ctx, dl, track, src, K.depth, x + Z.KCELL_W, y)
  setting(ctx, dl, track, src, K.phase, x + Z.KCELL_W * 2, y)
  y = y + Z.KCELL_H
  setting(ctx, dl, track, src, K.smooth, x, y)
  local px = x + Z.KCELL_W + 8
  if pill(ctx, dl, "sync##" .. src.guid, px, y + C.S(8), 46, "Sync", sync, src.col) and not sync then
    MD.set_field(track, src.slot, src.j, "sync", 1)
  end
  mx_switch(ctx, dl, track, src, "sync", 1, px, y + C.S(8), C.S(46), Z.PILL_H)
  if pill(ctx, dl, "free##" .. src.guid, px + C.S(50), y + C.S(8), 46, "Free", not sync, src.col) and sync then
    MD.set_field(track, src.slot, src.j, "sync", 0)
  end
  mx_switch(ctx, dl, track, src, "sync", 0, px + C.S(50), y + C.S(8), C.S(46), Z.PILL_H)
end

local function level_bar(dl, src, v, x, y, w)
  ImGui.DrawList_AddRectFilled(dl, x, y + C.S(2), x + w, y + C.S(10), 0x121416ff, 2)
  ImGui.DrawList_AddRectFilled(dl, x, y + C.S(2), x + w * math.max(0, math.min(1, v)), y + C.S(10), src.col, 2)
end

local MIDI_PILL = { "Vel", "Note", "CC", "Bend", "AT" }
local ENV_PILL = { "Envelope", "Env \u{00D7} vel", "Duck" }

-- A MIDI envelope's curve: attack, decay, sustain held, release; Duck's
-- upside down. Its three corners drag (attack's time; decay's time and
-- the sustain; release's time); the line across is where it is now.
local ENV_W = { 0.22, 0.28, 0.18, 0.32 }    -- each stage's share at its longest
-- where an envelope keeps its Decay and Sustain: a MIDI one's in Ceiling
-- and Floor, a Follower's in MIDI CC and Low note (MD.FOLLOW_ENV)
local ENV_IO = {
  midi = { dk = "ceil", sk = "floor", dec = MD.decay_of, dec_to = MD.ceil_of, sus = MD.sustain_of, sus_to = MD.floor_of },
  follower = { dk = "mcc", sk = "mlo", dec = MD.fdecay_of, dec_to = MD.mcc_of, sus = MD.fsus_of, sus_to = MD.mlo_of },
}
local function env_curve(ctx, dl, track, src, ms, x, y, w, h)
  local f = function(k) return MD.field(track, src.slot, src.j, k) end
  local io = ENV_IO[src.kind] or ENV_IO.midi
  local att, dec, sus, rel = f("att"), io.dec(f(io.dk)), io.sus(f(io.sk)), f("rel")
  local ex, duck = f("gate") >= 0.5, ms == 7
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x121416ff, 3)
  local top, bot = y + C.S(4), y + h - C.S(4)
  local function py(l) if duck then l = 1 - l end return bot - l * (bot - top) end
  local wa, wd, ws, wr = w * ENV_W[1], w * ENV_W[2], w * ENV_W[3], w * ENV_W[4]
  local xa = x + wa * math.sqrt(att / 500)
  local xd = xa + wd * math.sqrt(dec / 2000)
  local xs = xd + ws
  local xr = xs + wr * math.sqrt(rel / 2000)
  local pts = { { x, py(0) }, { xa, py(1) } }
  for k = 1, 12 do
    local t = k / 12
    local l = ex and (sus + (1 - sus) * math.exp(-6.9 * t)) or (1 - (1 - sus) * t)
    pts[#pts + 1] = { xa + (xd - xa) * t, py(k == 12 and sus or l) }
  end
  pts[#pts + 1] = { xs, py(sus) }
  for k = 1, 12 do
    local t = k / 12
    local l = ex and (sus * math.exp(-6.9 * t)) or (sus * (1 - t))
    pts[#pts + 1] = { xs + (xr - xs) * t, py(k == 12 and 0 or l) }
  end
  for k = 2, #pts do
    ImGui.DrawList_AddLine(dl, pts[k - 1][1], pts[k - 1][2], pts[k][1], pts[k][2], src.col, 1.6)
  end
  -- where it is now: the modulator's level before its depth
  local depth = f("depth")
  if depth > 0.001 then
    local l = math.max(0, math.min(1, MD.value(track, src) / depth))
    local ly = bot - l * (bot - top)
    ImGui.DrawList_AddLine(dl, x + C.S(2), ly, x + w - C.S(2), ly, U.with_alpha(src.col, 0x50), 1.0)
  end
  -- the corners
  local nodes = {
    { "a", xa, py(1), "Attack" }, { "d", xd, py(sus), "Decay and sustain" }, { "r", xr, py(0), "Release" } }
  for _, n in ipairs(nodes) do
    local id = ("env%s##%s"):format(n[1], src.guid)
    ImGui.SetCursorScreenPos(ctx, n[2] - 6, n[3] - 6)
    W.allow_overlap(ctx)
    ImGui.InvisibleButton(ctx, id, C.S(12), 12)
    local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    if act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      local mx, my = ImGui.GetMousePos(ctx)
      local function frac(v) return math.max(0, math.min(1, v)) end
      if n[1] == "a" then
        MD.set_field(track, src.slot, src.j, "att", 500 * frac((mx - x) / wa) ^ 2)
      elseif n[1] == "d" then
        MD.set_field(track, src.slot, src.j, io.dk, io.dec_to(2000 * frac((mx - xa) / wd) ^ 2))
        local l = frac((bot - my) / (bot - top))
        MD.set_field(track, src.slot, src.j, io.sk, io.sus_to(duck and 1 - l or l))
      else
        MD.set_field(track, src.slot, src.j, "rel", 2000 * frac((mx - xs) / wr) ^ 2)
      end
    end
    ImGui.DrawList_AddCircleFilled(dl, n[2], n[3], (hov or act) and 4 or 3, (hov or act) and C.COL.value or src.col, 12)
    W.tip(ctx, id, n[4], hov, act)
  end
end

-- A MIDI modulator's trigger track: another track's notes instead of this
-- one's (MD.set_trigger)
local function trigger_row(ctx, dl, track, src, x, y, w)
  local from = MD.trigger(track, src.j)
  local name = "This track's own"
  if from then
    local _, nm = reaper.GetSetMediaTrackInfo_String(from, "P_NAME", "", false)
    local num = math.floor(reaper.GetMediaTrackInfo_Value(from, "IP_TRACKNUMBER") or 0)
    name = ("%d %s"):format(num, U.trim(nm or ""))
  end
  local id = "trig##" .. src.guid
  if pill(ctx, dl, id, x, y, w, "Notes from: " .. U.truncate(name, 20), from ~= nil, src.col) then
    ImGui.OpenPopup(ctx, "trigpop##" .. src.guid)
  end
  W.tip(ctx, id, "Another track's MIDI, sent here for this modulator alone", ImGui.IsItemHovered(ctx), false)
  if ImGui.BeginPopup(ctx, "trigpop##" .. src.guid) then
    if ImGui.MenuItem(ctx, "   This track's own", nil, from == nil) then MD.set_trigger(track, src.slot, src.j, nil) end
    ImGui.Separator(ctx)
    -- the tracks as the Receives panel's add menu lists them
    require("TS_CV_Sends").track_menu_items(ctx, track, from, "trig" .. src.guid,
      function(tr) MD.set_trigger(track, src.slot, src.j, tr) end)
    ImGui.EndPopup(ctx)
  end
end

local FENV_PILL = { "Envelope", "Env \u{00D7} level", "Duck" }
local FENV_TIP = { "An envelope, set off when the level rises above the threshold",
                   "An envelope, its peak how loud the hit is",
                   "Dips on each hit, back over the release" }

-- A Follower's sidechain from another track (MD.set_sc_from), shown on
-- Sidechain only
local function sc_row(ctx, dl, track, src, x, y, w)
  local from = MD.sc_from(track)
  local name = "this track's 3/4"
  if from then
    local _, nm = reaper.GetSetMediaTrackInfo_String(from, "P_NAME", "", false)
    local num = math.floor(reaper.GetMediaTrackInfo_Value(from, "IP_TRACKNUMBER") or 0)
    name = ("%d %s"):format(num, U.trim(nm or ""))
  end
  local id = "scfrom##" .. src.guid
  if pill(ctx, dl, id, x, y, w, "Audio from: " .. U.truncate(name, 20), from ~= nil, src.col) then
    ImGui.OpenPopup(ctx, "scpop##" .. src.guid)
  end
  W.tip(ctx, id, "Which track feeds the sidechain", ImGui.IsItemHovered(ctx), false)
  if ImGui.BeginPopup(ctx, "scpop##" .. src.guid) then
    if ImGui.MenuItem(ctx, "   This track's sidechain (3/4)", nil, from == nil) then MD.set_sc_from(track, nil) end
    ImGui.Separator(ctx)
    -- the tracks as the Receives panel's add menu lists them
    require("TS_CV_Sends").track_menu_items(ctx, track, from, "scf" .. src.guid,
      function(tr) MD.set_sc_from(track, tr) end)
    ImGui.EndPopup(ctx)
  end
end

local function follower_body(ctx, dl, track, src, x, y, w, isopen)
  level_bar(dl, src, MD.value(track, src), x, y, w)
  if not isopen then return end
  y = y + C.S(16)
  local side = live_field(track, src, "fsrc") >= 0.5
  local gate = live_field(track, src, "gate") >= 0.5
  local ms = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
  local env = MD.is_env(ms)
  if pill(ctx, dl, "main##" .. src.guid, x, y, 52, "Track", not side, src.col) and side then
    MD.set_field(track, src.slot, src.j, "fsrc", 0)
  end
  mx_switch(ctx, dl, track, src, "fsrc", 0, x, y, C.S(52), Z.PILL_H)
  if pill(ctx, dl, "side##" .. src.guid, x + C.S(55), y, 64, "Sidechain", side, src.col) and not side then
    MD.set_field(track, src.slot, src.j, "fsrc", 1)
    MD.need_sidechain(track)
  end
  mx_switch(ctx, dl, track, src, "fsrc", 1, x + C.S(55), y, C.S(64), Z.PILL_H)
  if not env then
    if pill(ctx, dl, "gate##" .. src.guid, x + w - C.S(44), y, 44, "Gate", gate, src.col) then
      MD.set_field(track, src.slot, src.j, "gate", gate and 0 or 1)
    end
    mx_switch(ctx, dl, track, src, "gate", gate and 0 or 1, x + w - C.S(44), y, C.S(44), Z.PILL_H)
    W.tip(ctx, "gate##" .. src.guid, "All or nothing at the Floor", ImGui.IsItemHovered(ctx), false)
  end
  y = y + C.S(22)
  -- its envelopes: click one, or the lit one again to follow the level
  local ew = (w - 2 * 2) / 3
  for i = 1, 3 do
    local v = MD.ENV_FIRST + i - 1
    local id = ("fenv%d##%s"):format(i, src.guid)
    if pill(ctx, dl, id, x + (i - 1) * (ew + 2), y, ew, FENV_PILL[i], ms == v, src.col) then
      MD.set_msrc(track, src.slot, src.j, ms == v and 0 or v)
    end
    W.tip(ctx, id, FENV_TIP[i], ImGui.IsItemHovered(ctx), false)
  end
  y = y + C.S(20)
  if not env then
    setting(ctx, dl, track, src, K.att, x, y)
    setting(ctx, dl, track, src, K.rel, x + Z.KCELL_W, y)
    setting(ctx, dl, track, src, K.depth, x + Z.KCELL_W * 2, y)
    y = y + Z.KCELL_H
    setting(ctx, dl, track, src, K.floor, x, y)
    if not gate then setting(ctx, dl, track, src, K.ceil, x + Z.KCELL_W, y) end
    setting(ctx, dl, track, src, K.smooth, x + Z.KCELL_W * 2, y)
    if side then sc_row(ctx, dl, track, src, x, y + Z.KCELL_H + 2, w) end
    return
  end
  env_curve(ctx, dl, track, src, ms, x, y, w, Z.ENV_CURVE_H)
  y = y + Z.ENV_CURVE_H + 6
  setting(ctx, dl, track, src, K.eatt, x, y)
  setting(ctx, dl, track, src, K.fdec, x + Z.KCELL_W, y)
  setting(ctx, dl, track, src, K.fsus, x + Z.KCELL_W * 2, y)
  y = y + Z.KCELL_H
  setting(ctx, dl, track, src, K.erel, x, y)
  setting(ctx, dl, track, src, K.depth, x + Z.KCELL_W, y)
  setting(ctx, dl, track, src, K.smooth, x + Z.KCELL_W * 2, y)
  y = y + Z.KCELL_H
  setting(ctx, dl, track, src, K.thr, x, y)
  W.tip(ctx, "floor##" .. src.guid, "It starts when the level rises above this, and lets go when it falls back below",
    ImGui.IsItemHovered(ctx), false)
  if ms == MD.ENV_FIRST + 1 then setting(ctx, dl, track, src, K.ceil, x + Z.KCELL_W, y) end
  y = y + Z.KCELL_H
  local legato = live_field(track, src, "mhold") >= 0.5
  local ex = live_field(track, src, "gate") >= 0.5
  local bw3 = (w - 2 * 2) / 3
  if pill(ctx, dl, "fretrig##" .. src.guid, x, y, bw3, "Retrigger", not legato, src.col) and legato then
    MD.set_field(track, src.slot, src.j, "mhold", 0)
  end
  mx_switch(ctx, dl, track, src, "mhold", 0, x, y, bw3, Z.PILL_H)
  W.tip(ctx, "fretrig##" .. src.guid, "Every rise starts it again from nothing", ImGui.IsItemHovered(ctx), false)
  if pill(ctx, dl, "flegato##" .. src.guid, x + bw3 + 2, y, bw3, "Legato", legato, src.col) and not legato then
    MD.set_field(track, src.slot, src.j, "mhold", 1)
  end
  mx_switch(ctx, dl, track, src, "mhold", 1, x + bw3 + 2, y, bw3, Z.PILL_H)
  W.tip(ctx, "flegato##" .. src.guid, "A rise while it's letting go carries on from where it is", ImGui.IsItemHovered(ctx), false)
  if pill(ctx, dl, "fexpc##" .. src.guid, x + (bw3 + 2) * 2, y, bw3, "Exp curve", ex, src.col) then
    MD.set_field(track, src.slot, src.j, "gate", ex and 0 or 1)
  end
  mx_switch(ctx, dl, track, src, "gate", ex and 0 or 1, x + (bw3 + 2) * 2, y, bw3, Z.PILL_H)
  W.tip(ctx, "fexpc##" .. src.guid, "Decay and release fall away exponentially", ImGui.IsItemHovered(ctx), false)
  if side then sc_row(ctx, dl, track, src, x, y + C.S(22), w) end
end

local function midi_body(ctx, dl, track, src, x, y, w, isopen)
  level_bar(dl, src, MD.value(track, src), x, y, w)
  if not isopen then return end
  y = y + C.S(16)
  local ms = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
  local pw = (w - 4 * 2) / 5
  for i = 1, 5 do
    if pill(ctx, dl, ("msrc%d##%s"):format(i, src.guid), x + (i - 1) * (pw + 2), y, pw, MIDI_PILL[i], ms == i - 1, src.col) then
      MD.set_msrc(track, src.slot, src.j, i - 1)
    end
    W.tip(ctx, ("msrc%d##%s"):format(i, src.guid), MD.MIDI_SRC[i], ImGui.IsItemHovered(ctx), false)
  end
  y = y + C.S(20)
  local ew = (w - 2 * 2) / 3
  for i = 1, 3 do
    local v = MD.ENV_FIRST + i - 1
    if pill(ctx, dl, ("msrc%d##%s"):format(v + 1, src.guid), x + (i - 1) * (ew + 2), y, ew, ENV_PILL[i], ms == v, src.col) then
      MD.set_msrc(track, src.slot, src.j, v)
    end
    W.tip(ctx, ("msrc%d##%s"):format(v + 1, src.guid), MD.MIDI_SRC[v + 1], ImGui.IsItemHovered(ctx), false)
  end
  y = y + C.S(22)
  if MD.is_env(ms) then
    env_curve(ctx, dl, track, src, ms, x, y, w, Z.ENV_CURVE_H)
    y = y + Z.ENV_CURVE_H + 6
    setting(ctx, dl, track, src, K.eatt, x, y)
    setting(ctx, dl, track, src, K.dec, x + Z.KCELL_W, y)
    setting(ctx, dl, track, src, K.sus, x + Z.KCELL_W * 2, y)
    y = y + Z.KCELL_H
    setting(ctx, dl, track, src, K.erel, x, y)
    setting(ctx, dl, track, src, K.depth, x + Z.KCELL_W, y)
    setting(ctx, dl, track, src, K.smooth, x + Z.KCELL_W * 2, y)
    y = y + Z.KCELL_H
    local legato = live_field(track, src, "mhold") >= 0.5
    local ex = live_field(track, src, "gate") >= 0.5
    local bw3 = (w - 2 * 2) / 3
    if pill(ctx, dl, "retrig##" .. src.guid, x, y, bw3, "Retrigger", not legato, src.col) and legato then
      MD.set_field(track, src.slot, src.j, "mhold", 0)
    end
    mx_switch(ctx, dl, track, src, "mhold", 0, x, y, bw3, Z.PILL_H)
    W.tip(ctx, "retrig##" .. src.guid, "Every note starts it again", ImGui.IsItemHovered(ctx), false)
    if pill(ctx, dl, "legato##" .. src.guid, x + bw3 + 2, y, bw3, "Legato", legato, src.col) and not legato then
      MD.set_field(track, src.slot, src.j, "mhold", 1)
    end
    mx_switch(ctx, dl, track, src, "mhold", 1, x + bw3 + 2, y, bw3, Z.PILL_H)
    W.tip(ctx, "legato##" .. src.guid, "Only a note after silence starts it again", ImGui.IsItemHovered(ctx), false)
    if pill(ctx, dl, "expc##" .. src.guid, x + (bw3 + 2) * 2, y, bw3, "Exp curve", ex, src.col) then
      MD.set_field(track, src.slot, src.j, "gate", ex and 0 or 1)
    end
    mx_switch(ctx, dl, track, src, "gate", ex and 0 or 1, x + (bw3 + 2) * 2, y, bw3, Z.PILL_H)
    W.tip(ctx, "expc##" .. src.guid, "Decay and release fall away exponentially", ImGui.IsItemHovered(ctx), false)
    y = y + C.S(22)
    setting(ctx, dl, track, src, K.mch, x, y)
    setting(ctx, dl, track, src, K.mlo, x + Z.KCELL_W, y)
    setting(ctx, dl, track, src, K.mhi, x + Z.KCELL_W * 2, y)
    y = y + Z.KCELL_H
  else
    setting(ctx, dl, track, src, K.mch, x, y)
    if ms == 1 then
      setting(ctx, dl, track, src, K.mlo, x + Z.KCELL_W, y)
      setting(ctx, dl, track, src, K.mhi, x + Z.KCELL_W * 2, y)
    elseif ms == 2 then
      setting(ctx, dl, track, src, K.mcc, x + Z.KCELL_W, y)
    elseif ms == 0 then
      local hold = live_field(track, src, "mhold") >= 0.5
      if pill(ctx, dl, "hold##" .. src.guid, x + Z.KCELL_W + 6, y + C.S(14), 46, "Hold", hold, src.col) then
        MD.set_field(track, src.slot, src.j, "mhold", hold and 0 or 1)
      end
      mx_switch(ctx, dl, track, src, "mhold", hold and 0 or 1, x + Z.KCELL_W + 6, y + C.S(14), C.S(46), Z.PILL_H)
      W.tip(ctx, "hold##" .. src.guid, "Keep the last velocity after note-off",
        ImGui.IsItemHovered(ctx), false)
    end
    y = y + Z.KCELL_H
    setting(ctx, dl, track, src, K.depth, x, y)
    setting(ctx, dl, track, src, K.smooth, x + Z.KCELL_W, y)
    y = y + Z.KCELL_H
  end
  if MD.trig_ok(track, src.slot) then trigger_row(ctx, dl, track, src, x, y + C.S(2), w) end
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
    for _, f in ipairs(lanes_of(track, src) or {}) do item(f[1], f[2]) end
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
        if ImGui.BeginMenu(ctx, ("%s \u{2192} %s%s##mxt%d"):format(name, tg_label(track, src, e.tg), amt, sl)) then
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

-- ---------------------------------------------------------------------
-- STEPS AND MSEG: their patterns (TS_CV_ModPat), drawn and drawn on.
-- Mouse only (the keyboard stays with REAPER): Draw / Line pills, a dot
-- between each pair of steps to join them, the wheel to nudge, a
-- double-click to put one back; Shift while dragging as everywhere.
-- Opened, the tile takes two columns.
-- ---------------------------------------------------------------------
local SM = {}
SM.draw = {}            -- guid -> "draw" / "line"
SM.grab = {}            -- guid -> what a press on the pattern is doing
SM.clip = nil           -- a pattern copied, { kind, p }

-- A dropdown as a pill: its items' names; returns the one picked (1-based)
local function choice_pill(ctx, dl, id, x, y, w, text, items, cur, col, tip)
  if pill(ctx, dl, id, x, y, w, text .. " \u{25BE}", false, col) then ImGui.OpenPopup(ctx, "cp" .. id) end
  if tip then W.tip(ctx, id, tip, ImGui.IsItemHovered(ctx), false) end
  local got
  if ImGui.BeginPopup(ctx, "cp" .. id) then
    for i, t in ipairs(items) do
      if ImGui.Selectable(ctx, t .. "##" .. i, i == cur) then got = i end
    end
    ImGui.EndPopup(ctx)
  end
  return got
end
SM.choice_pill = choice_pill

local function copy_steps(p)
  local o = { kind = "steps", vals = {}, joins = {} }
  for i = 1, MP.STEPS do o.vals[i] = p.vals[i] or 0; o.joins[i] = p.joins[i] or false end
  return o
end
local function copy_pts(p)
  local o = { kind = "mseg", pts = {} }
  for k, q in ipairs(p.pts) do o.pts[k] = { q[1], q[2], q[3] or 0 } end
  return o
end
SM.copy_steps, SM.copy_pts = copy_steps, copy_pts

local CC_NAMES = { [1] = "Mod wheel", [2] = "Breath", [4] = "Foot", [7] = "Volume", [10] = "Pan", [11] = "Expression",
                   [64] = "Sustain", [71] = "Resonance", [72] = "Release", [73] = "Attack", [74] = "Cutoff",
                   [91] = "Reverb", [93] = "Chorus" }
local KEYS = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

-- The steps: bars (one per run of joined steps), the one playing lit.
-- Opened: drawn on (Draw: drag across; Line: press and drag; the wheel
-- nudges; double-click puts one back).
local function steps_graph(ctx, dl, track, src, p, n, x, y, w, h, edit)
  local bip = MD.field(track, src.slot, src.j, "gate") >= 0.5
  local notes = edit and math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5) == 2
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x121416ff, 3)
  local sw = w / n
  local function vy(v) return y + h - 1 - (h - 2) * math.max(0, math.min(1, v)) end
  local base = bip and vy(0.5) or (y + h - 1)
  if bip then ImGui.DrawList_AddLine(dl, x, base, x + w, base, 0x2c2e33ff, 1) end
  for k = 1, n - 1 do
    if edit and k % 4 == 0 then ImGui.DrawList_AddLine(dl, x + k * sw, y, x + k * sw, y + h, 0x2c2e33ff, 1) end
  end
  local at = MP.where(track, src.slot, src.j, "steps")
  local cur = at and MP.first(p, math.max(1, math.min(n, at)))
  local lo_n, hi_n, scale, key
  if notes then
    lo_n, hi_n = MD.field(track, src.slot, src.j, "mlo"), MD.field(track, src.slot, src.j, "mhi")
    local sk = math.floor(MD.field(track, src.slot, src.j, "rel") + 0.5)
    scale, key = sk // 12, sk % 12
  end
  W.push_small(ctx)
  for _, r in ipairs(MP.runs(p, n)) do
    local v = p.vals[r[1]] or 0
    local x1, x2 = x + (r[1] - 1) * sw + 1, x + r[2] * sw - 1
    local top = vy(v)
    local lit = cur == r[1]
    local col = lit and src.col or U.with_alpha(src.col, 0x8c)
    if bip then
      ImGui.DrawList_AddRectFilled(dl, x1, math.min(top, base), x2, math.max(top, base), col, 1)
    else
      ImGui.DrawList_AddRectFilled(dl, x1, top, x2, y + h - 1, col, 1)
    end
    if notes and x2 - x1 >= C.S(13) then
      local nt = MP.note_of(v, lo_n, hi_n, scale, key)
      local t = nt and note_name(nt) or "rest"
      local tw, th = ImGui.CalcTextSize(ctx, t)
      if tw <= x2 - x1 + 2 then
        local ty = nt and math.min(y + h - th - 2, top + 2) or (y + h - th - 2)
        ImGui.DrawList_AddText(dl, (x1 + x2 - tw) * 0.5, ty, nt and (lit and 0x111111ff or C.COL.value) or C.COL.header_dim, t)
      end
    end
  end
  W.pop_small(ctx)
  if not edit then return end
  -- drawn on
  local id = "stg##" .. src.guid
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, w, h)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local mx, my = ImGui.GetMousePos(ctx)
  local function step_at(px) return math.max(1, math.min(n, math.floor((px - x) / sw) + 1)) end
  local function val_at(py) return math.max(0, math.min(1, (y + h - 1 - py) / (h - 2))) end
  local g = SM.grab[src.guid]
  local changed = false
  if ImGui.IsItemActivated(ctx) then
    local straight = SM.draw[src.guid] == "line" or (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0
    g = { straight = straight, i0 = step_at(mx), v0 = val_at(my), from = copy_steps(p) }
    SM.grab[src.guid] = g
  end
  if act and g and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    local i, v = step_at(mx), val_at(my)
    if g.straight then
      -- from where it was pressed to here, straight; the rest as they were
      for k = 1, n do p.vals[k] = g.from.vals[k] end
      local a, b = math.min(g.i0, i), math.max(g.i0, i)
      for k = a, b do
        local t = (b > a) and (k - a) / (b - a) or 0
        local va, vb = (g.i0 <= i) and g.v0 or v, (g.i0 <= i) and v or g.v0
        p.vals[MP.first(p, k)] = va + (vb - va) * t
      end
    else
      -- painted: every step passed over since the last frame
      local last = g.last or i
      for k = math.min(last, i), math.max(last, i) do p.vals[MP.first(p, k)] = v end
      g.last = i
    end
    changed = true
  elseif not act and g then
    SM.grab[src.guid] = nil
  end
  if hov and not act then
    local i = MP.first(p, step_at(mx))
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then
      local step = 0.02 * (((ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0) and C.FINE_MULT or 1)
      p.vals[i] = math.max(0, math.min(1, (p.vals[i] or 0) + wheel * step))
      W.take_wheel()
      changed = true
    end
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      p.vals[i] = bip and 0.5 or 0
      changed = true
    end
    W.tip(ctx, id, ("Step %d  %d%%"):format(i, math.floor((p.vals[i] or 0) * 100 + 0.5)), true, false)
  end
  if changed then MP.put(track, src.slot, src.j, "steps", p) end
end

-- The dots between the steps: click one to join the two either side of
-- it (or split them); drag along to do a run
local function steps_joints(ctx, dl, track, src, p, n, x, y, w)
  local sw = w / n
  local id = "stj##" .. src.guid
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, w, C.S(12))
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local mx = ImGui.GetMousePos(ctx)
  local near = math.floor((mx - x) / sw + 0.5) + 1      -- the dot before step `near`
  local g = SM.grab["j" .. src.guid]
  local changed = false
  if ImGui.IsItemActivated(ctx) and near >= 2 and near <= n then
    g = { to = not p.joins[near] }
    SM.grab["j" .. src.guid] = g
  end
  if act and g and near >= 2 and near <= n and (p.joins[near] or false) ~= g.to then
    p.joins[near] = g.to
    changed = true
  elseif not act then
    SM.grab["j" .. src.guid] = nil
  end
  local cy = y + C.S(6)
  for k = 2, n do
    local cx = x + (k - 1) * sw
    local on = p.joins[k]
    if on then
      ImGui.DrawList_AddLine(dl, cx - sw * 0.5, cy, cx + sw * 0.5, cy, src.col, 2)
      ImGui.DrawList_AddCircleFilled(dl, cx, cy, 3.2, src.col, 10)
    else
      local hot = hov and near == k
      ImGui.DrawList_AddCircle(dl, cx, cy, 3, hot and C.COL.value or 0x4a4d54ff, 10, 1.2)
    end
  end
  if hov then
    W.tip(ctx, id, "Click a dot: join the steps either side (again: split)\nDrag along: a run", true, act)
  end
  if changed then MP.put(track, src.slot, src.j, "steps", p) end
end

local K_SWING = { key = "floor", label = "Swing", def = 0,
                  tn = function(v) return MD.swing_of(v) / 80 end,
                  fn = function(n) return -80 * n end,
                  text = function(v) return ("%d%%"):format(math.floor(MD.swing_of(v) + 0.5)) end }
local K_GLIDE = { key = "smooth", label = "Glide", tn = K.smooth.tn, fn = K.smooth.fn, def = 0, text = K.smooth.text }
local K_STEP = { key = "rsync", label = "Step", tn = K.rsync.tn, fn = K.rsync.fn, def = 0, text = K.rsync.text }
local K_GATE = { key = "ceil", label = "Gate", def = MD.ceil_of_gate(0.75),
                 tn = function(v) return MD.gate_of(v) end, fn = function(n) return MD.ceil_of_gate(n) end,
                 text = function(v) return ("%d%%"):format(math.floor(MD.gate_of(v) * 100 + 0.5)) end }
local K_VEL = { key = "mcc", label = "Velocity", def = 100,
                tn = function(v) return (v - 1) / 126 end, fn = function(n) return math.floor(1 + n * 126 + 0.5) end,
                text = function(v) return ("%d"):format(math.floor(v + 0.5)) end }
STEPPED[K_VEL.fn] = true

-- how tall a Steps tile's body is
local function steps_h(track, src, isopen)
  if not isopen then return C.S(58) end
  local out = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
  return C.S(112) + C.S(16) + C.S(22) * 3 + Z.KCELL_H + C.S(22) + ((out == 2) and (C.S(22) + Z.KCELL_H) or 0)
end
body_h.steps = steps_h

local function steps_body(ctx, dl, track, src, x, y, w, isopen)
  local p = MP.get(track, src.slot, src.j, "steps")
  local n = math.max(2, math.min(MP.STEPS, math.floor(MD.field(track, src.slot, src.j, "att") + 0.5)))
  if not p then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + C.S(54), 0x121416ff, 3)
    return
  end
  if not isopen then
    steps_graph(ctx, dl, track, src, p, n, x, y, w, C.S(54), false)
    return
  end
  steps_graph(ctx, dl, track, src, p, n, x, y, w, C.S(108), true)
  y = y + C.S(110)
  steps_joints(ctx, dl, track, src, p, n, x, y, w)
  y = y + C.S(16)
  -- how many, direction, Draw / Line, bipolar
  local cw = C.S(70)
  local counts = {}
  for k = 2, MP.STEPS do counts[k - 1] = ("%d steps"):format(k) end
  local c = choice_pill(ctx, dl, "stn##" .. src.guid, x, y, cw, ("%d steps"):format(n), counts, n - 1, src.col)
  if c then MD.set_field(track, src.slot, src.j, "att", c + 1) end
  local dir = math.floor(MD.field(track, src.slot, src.j, "shape") + 0.5)
  local d = choice_pill(ctx, dl, "std##" .. src.guid, x + cw + C.S(4), y, C.S(78),
    MD.STEP_DIRS[dir + 1] or "Forward", MD.STEP_DIRS, dir + 1, src.col)
  if d then MD.set_field(track, src.slot, src.j, "shape", d - 1) end
  local mode = SM.draw[src.guid] or "draw"
  local px = x + cw + C.S(86)
  if pill(ctx, dl, "stdr##" .. src.guid, px, y, C.S(42), "Draw", mode == "draw", src.col) then SM.draw[src.guid] = "draw" end
  W.tip(ctx, "stdr##" .. src.guid, "Drag across the bars to paint them", ImGui.IsItemHovered(ctx), false)
  if pill(ctx, dl, "stln##" .. src.guid, px + C.S(44), y, C.S(42), "Line", mode == "line", src.col) then SM.draw[src.guid] = "line" end
  W.tip(ctx, "stln##" .. src.guid, "Press and drag: a straight line across them", ImGui.IsItemHovered(ctx), false)
  local bip = MD.field(track, src.slot, src.j, "gate") >= 0.5
  if pill(ctx, dl, "stbp##" .. src.guid, px + C.S(92), y, C.S(54), "Bipolar", bip, src.col) then
    MD.set_field(track, src.slot, src.j, "gate", bip and 0 or 1)
  end
  W.tip(ctx, "stbp##" .. src.guid, "Steps up and down from the middle", ImGui.IsItemHovered(ctx), false)
  y = y + C.S(22)
  -- shift, randomise, clear; sync / free
  local function shift(by)
    local o = copy_steps(p)
    for k = 1, n do
      local from = (k - 1 - by) % n + 1
      p.vals[k], p.joins[k] = o.vals[from], o.joins[from]
    end
    p.joins[1] = false
    MP.put(track, src.slot, src.j, "steps", p)
  end
  if pill(ctx, dl, "stl##" .. src.guid, x, y, C.S(22), "\u{25C0}", false, src.col) then shift(-1) end
  W.tip(ctx, "stl##" .. src.guid, "Shift the pattern a step left", ImGui.IsItemHovered(ctx), false)
  if pill(ctx, dl, "str##" .. src.guid, x + C.S(24), y, C.S(22), "\u{25B6}", false, src.col) then shift(1) end
  W.tip(ctx, "str##" .. src.guid, "Shift the pattern a step right", ImGui.IsItemHovered(ctx), false)
  if pill(ctx, dl, "strn##" .. src.guid, x + C.S(50), y, C.S(70), "Randomise", false, src.col) then
    for k = 1, n do p.vals[k] = math.random() end
    MP.put(track, src.slot, src.j, "steps", p)
  end
  if pill(ctx, dl, "stcl##" .. src.guid, x + C.S(122), y, C.S(44), "Clear", false, src.col) then
    for k = 1, MP.STEPS do p.vals[k] = bip and 0.5 or 0; p.joins[k] = false end
    MP.put(track, src.slot, src.j, "steps", p)
  end
  local sync = live_field(track, src, "sync") >= 0.5
  local sx = x + w - C.S(94)
  if pill(ctx, dl, "stsy##" .. src.guid, sx, y, C.S(46), "Sync", sync, src.col) and not sync then
    MD.set_field(track, src.slot, src.j, "sync", 1)
  end
  mx_switch(ctx, dl, track, src, "sync", 1, sx, y, C.S(46), Z.PILL_H)
  if pill(ctx, dl, "stfr##" .. src.guid, sx + C.S(48), y, C.S(46), "Free", not sync, src.col) and sync then
    MD.set_field(track, src.slot, src.j, "sync", 0)
  end
  mx_switch(ctx, dl, track, src, "sync", 0, sx + C.S(48), y, C.S(46), Z.PILL_H)
  y = y + C.S(22)
  -- the knobs
  setting(ctx, dl, track, src, sync and K_STEP or K.rhz, x, y)
  setting(ctx, dl, track, src, K.depth, x + Z.KCELL_W, y)
  setting(ctx, dl, track, src, K_GLIDE, x + Z.KCELL_W * 2, y)
  setting(ctx, dl, track, src, K_SWING, x + Z.KCELL_W * 3, y)
  setting(ctx, dl, track, src, K.phase, x + Z.KCELL_W * 4, y)
  y = y + Z.KCELL_H
  -- MIDI out
  local out = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
  W.push_small(ctx)
  ImGui.DrawList_AddText(dl, x, y + C.S(2), C.COL.label, "MIDI out")
  W.pop_small(ctx)
  local ox = x + C.S(50)
  for i, t in ipairs(MD.STEP_OUT) do
    local oid = ("sto%d##%s"):format(i, src.guid)
    if pill(ctx, dl, oid, ox + (i - 1) * C.S(46), y, C.S(44), t, out == i - 1, src.col) and out ~= i - 1 then
      MD.set_msrc(track, src.slot, src.j, i - 1)
    end
    W.tip(ctx, oid, ({ "No MIDI", "A controller, from the steps", "Each run of joined steps a note; the bottom a rest" })[i],
      ImGui.IsItemHovered(ctx), false)
  end
  if out > 0 then
    local chn = math.max(1, math.floor(MD.field(track, src.slot, src.j, "mch") + 0.5))
    local chs = {}
    for k = 1, 16 do chs[k] = ("Ch %d"):format(k) end
    local cx = ox + C.S(142)
    local pick = choice_pill(ctx, dl, "stch##" .. src.guid, cx, y, C.S(50), ("Ch %d"):format(chn), chs, chn, src.col)
    if pick then MD.set_field(track, src.slot, src.j, "mch", pick) end
    if out == 1 then
      local cc = math.floor(MD.field(track, src.slot, src.j, "mcc") + 0.5)
      local list = {}
      for k = 0, 127 do list[k + 1] = ("CC %d%s"):format(k, CC_NAMES[k] and ("  " .. CC_NAMES[k]) or "") end
      local got = choice_pill(ctx, dl, "stcc##" .. src.guid, cx + C.S(54), y, C.S(96),
        ("CC %d%s"):format(cc, CC_NAMES[cc] and (" " .. CC_NAMES[cc]) or ""), list, cc + 1, src.col)
      if got then MD.set_field(track, src.slot, src.j, "mcc", got - 1) end
    end
  end
  y = y + C.S(22)
  if out == 2 then
    local names = {}
    for k = 0, 127 do names[k + 1] = note_name(k) end
    local lo = math.floor(MD.field(track, src.slot, src.j, "mlo") + 0.5)
    local hi = math.floor(MD.field(track, src.slot, src.j, "mhi") + 0.5)
    W.push_small(ctx)
    ImGui.DrawList_AddText(dl, x, y + C.S(2), C.COL.label, "From")
    W.pop_small(ctx)
    local a = choice_pill(ctx, dl, "stlo##" .. src.guid, x + C.S(32), y, C.S(44), note_name(lo), names, lo + 1, src.col)
    if a then MD.set_field(track, src.slot, src.j, "mlo", a - 1) end
    W.push_small(ctx)
    ImGui.DrawList_AddText(dl, x + C.S(80), y + C.S(2), C.COL.label, "to")
    W.pop_small(ctx)
    local b = choice_pill(ctx, dl, "sthi##" .. src.guid, x + C.S(96), y, C.S(44), note_name(hi), names, hi + 1, src.col)
    if b then MD.set_field(track, src.slot, src.j, "mhi", b - 1) end
    local sk = math.floor(MD.field(track, src.slot, src.j, "rel") + 0.5)
    local scales = {}
    for k, s in ipairs(MP.SCALES) do scales[k] = s[1] end
    local sc = choice_pill(ctx, dl, "stsc##" .. src.guid, x + C.S(146), y, C.S(110),
      scales[sk // 12 + 1] or "Major", scales, sk // 12 + 1, src.col)
    if sc then MD.set_field(track, src.slot, src.j, "rel", (sc - 1) * 12 + sk % 12) end
    local keys = {}
    for k, t in ipairs(KEYS) do keys[k] = "Key " .. t end
    local kk = choice_pill(ctx, dl, "stky##" .. src.guid, x + C.S(260), y, C.S(62), keys[sk % 12 + 1], keys, sk % 12 + 1, src.col)
    if kk then MD.set_field(track, src.slot, src.j, "rel", (sk // 12) * 12 + kk - 1) end
    y = y + C.S(22)
    setting(ctx, dl, track, src, K_GATE, x, y)
    setting(ctx, dl, track, src, K_VEL, x + Z.KCELL_W, y)
  end
end

-- ---- MSEG

local MSEG_PRESETS = {
  { "Ramp up", { { 0, 0, 0 }, { 1, 1, 0 } } },
  { "Ramp down", { { 0, 1, 0 }, { 1, 0, 0 } } },
  { "Triangle", { { 0, 0, 0 }, { 0.5, 1, 0 }, { 1, 0, 0 } } },
  { "Pump", { { 0, 0, -0.6 }, { 0.6, 1, 0 }, { 1, 1, 0 } } },
  { "Half sine", { { 0, 0, -0.35 }, { 0.5, 1, 0.35 }, { 1, 0, 0 } } },
  { "Steps down", { { 0, 1, 0 }, { 0.249, 1, 0 }, { 0.25, 0.66, 0 }, { 0.499, 0.66, 0 }, { 0.5, 0.33, 0 },
                    { 0.749, 0.33, 0 }, { 0.75, 0, 0 }, { 1, 0, 0 } } },
}
local function saved_presets()
  local out = {}
  local raw = reaper.GetExtState(C.EXT_SECT, "mseg_presets") or ""
  for item in raw:gmatch("[^|]+") do
    local name, pts = item:match("^(.-)=(.*)$")
    if name then
      local list = {}
      for a, b, c in pts:gmatch("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)") do list[#list + 1] = { tonumber(a), tonumber(b), tonumber(c) } end
      if #list >= 2 then out[#out + 1] = { name, list } end
    end
  end
  return out
end
local function save_presets(list)
  local t = {}
  for _, e in ipairs(list) do
    local pts = {}
    for _, q in ipairs(e[2]) do pts[#pts + 1] = ("%.4f,%.4f,%.3f"):format(q[1], q[2], q[3] or 0) end
    t[#t + 1] = e[1]:gsub("[|=;\r\n]", " ") .. "=" .. table.concat(pts, ";")
  end
  reaper.SetExtState(C.EXT_SECT, "mseg_presets", table.concat(t, "|"), true)
end
SM.saved_presets = saved_presets

local function snap_on() return reaper.GetExtState(C.EXT_SECT, "mseg_snap") ~= "0" end
local function grid_n() return math.max(2, tonumber(reaper.GetExtState(C.EXT_SECT, "mseg_grid")) or 8) end

-- The curve, its points and the dot riding it; opened, the points drag,
-- a double-click adds one (on empty space) or takes one away, and the
-- handle half way along each segment bends it.
local function mseg_graph(ctx, dl, track, src, p, x, y, w, h, edit)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x121416ff, 3)
  local pad = C.S(4)
  local x0, x1, y0, y1 = x + pad, x + w - pad, y + pad, y + h - pad
  local function sx(f) return x0 + (x1 - x0) * f end
  local function sy(v) return y1 - (y1 - y0) * v end
  local gn = grid_n()
  if edit then
    for k = 1, gn - 1 do ImGui.DrawList_AddLine(dl, sx(k / gn), y, sx(k / gn), y + h, 0x2c2e33ff, 1) end
    ImGui.DrawList_AddLine(dl, x, sy(0.5), x + w, sy(0.5), 0x2c2e33ff, 1)
  end
  -- the curve
  local steps = math.max(40, math.floor(w / 2))
  local px, py
  for k = 0, steps do
    local f = k / steps
    local xx, yy = sx(f), sy(MP.level(p, f))
    if px then
      ImGui.DrawList_AddQuadFilled(dl, px, py, xx, yy, xx, y1, px, y1, U.with_alpha(src.col, 0x2c))
      ImGui.DrawList_AddLine(dl, px, py, xx, yy, src.col, edit and 2 or 1.6)
    end
    px, py = xx, yy
  end
  local at = MP.where(track, src.slot, src.j, "mseg")
  if at then
    local ax = sx(math.max(0, math.min(1, at)))
    ImGui.DrawList_AddLine(dl, ax, y + 2, ax, y + h - 2, 0xe8eaed40, 1)
    ImGui.DrawList_AddCircleFilled(dl, ax, sy(MP.level(p, at)), 3, C.COL.value, 10)
  end
  local pts = p.pts
  if not edit then return end
  local mx, my = ImGui.GetMousePos(ctx)
  local function fx(px_) return math.max(0, math.min(1, (px_ - x0) / (x1 - x0))) end
  local function fv(py_) return math.max(0, math.min(1, (y1 - py_) / (y1 - y0))) end
  local function snapx(f) if snap_on() then return math.floor(f * gn + 0.5) / gn end return f end
  local function snapv(v) if snap_on() then return math.floor(v * 8 + 0.5) / 8 end return v end
  local changed = false
  local g = SM.grab["m" .. src.guid]
  -- the points and the bend handles, hit-tested first
  local hit_pt, hit_bend
  for k, q in ipairs(pts) do
    if (mx - sx(q[1])) ^ 2 + (my - sy(q[2])) ^ 2 <= C.S(7) ^ 2 then hit_pt = k end
  end
  if not hit_pt then
    for k = 1, #pts - 1 do
      local fm = (pts[k][1] + pts[k + 1][1]) * 0.5
      if pts[k + 1][1] - pts[k][1] > 0.02 and (mx - sx(fm)) ^ 2 + (my - sy(MP.level(p, fm))) ^ 2 <= C.S(6) ^ 2 then hit_bend = k end
    end
  end
  local id = "msg##" .. src.guid
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, id, w, h)
  local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    if hit_pt and hit_pt > 1 and hit_pt < #pts then
      table.remove(pts, hit_pt); changed = true
    elseif not hit_pt and #pts < MP.POINTS then
      local f, v = snapx(fx(mx)), snapv(fv(my))
      local at_k = #pts
      for k = 2, #pts do if f < pts[k][1] then at_k = k break end end
      if f > pts[at_k - 1][1] and f < pts[at_k][1] then table.insert(pts, at_k, { f, v, 0 }); changed = true end
    end
    SM.grab["m" .. src.guid] = nil
    g = nil
  elseif ImGui.IsItemActivated(ctx) then
    if hit_pt then g = { pt = hit_pt }
    elseif hit_bend then g = { bend = hit_bend, my = my, b0 = pts[hit_bend][3] or 0 } end
    SM.grab["m" .. src.guid] = g
  end
  if act and g and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    if g.pt and pts[g.pt] then
      local k = g.pt
      local f = (k == 1) and 0 or (k == #pts) and 1
                or math.max(pts[k - 1][1] + 0.001, math.min(pts[k + 1][1] - 0.001, snapx(fx(mx))))
      pts[k][1], pts[k][2] = f, snapv(fv(my))
      changed = true
    elseif g.bend and pts[g.bend] then
      -- up bows it up, down down (as the segment runs)
      local up = (pts[g.bend + 1][2] >= pts[g.bend][2]) and 1 or -1
      local fine = ((ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0) and C.FINE_MULT or 1
      pts[g.bend][3] = math.max(-1, math.min(1, g.b0 - up * (my - g.my) / (y1 - y0) * 2 * fine))
      changed = true
    end
  elseif not act and g then
    SM.grab["m" .. src.guid] = nil
  end
  -- drawn over the curve
  for k = 1, #pts - 1 do
    local fm = (pts[k][1] + pts[k + 1][1]) * 0.5
    if pts[k + 1][1] - pts[k][1] > 0.02 then
      local hot = hit_bend == k or (g and g.bend == k)
      ImGui.DrawList_AddCircle(dl, sx(fm), sy(MP.level(p, fm)), hot and 4.5 or 3.5, hot and C.COL.value or src.col, 12, 1.5)
    end
  end
  for k, q in ipairs(pts) do
    local hot = hit_pt == k or (g and g.pt == k)
    ImGui.DrawList_AddCircleFilled(dl, sx(q[1]), sy(q[2]), hot and 5 or 4, hot and C.COL.value or 0xe8eaedff, 12)
  end
  if hov then
    W.tip(ctx, id, hit_pt and "Drag: move it\nDouble-click: take it away"
      or hit_bend and "Drag up or down: bend it"
      or "Double-click: add a point", true, act)
  end
  if changed then MP.put(track, src.slot, src.j, "mseg", p) end
end

local function mseg_h(track, src, isopen)
  if not isopen then return C.S(58) end
  local trg = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
  return C.S(122) + C.S(22) * 2 + ((trg >= 2) and (trg == 3 and Z.KCELL_H or C.S(22)) or 0) + Z.KCELL_H
end
body_h.mseg = mseg_h

local MSEG_TRIG_TIP = { "With the song: where it is in the bar", "Running on its own", "Each note starts it again",
                        "Starts again when the audio goes over the threshold" }
local K_LEN = { key = "rsync", label = "Length", tn = K.rsync.tn, fn = K.rsync.fn, def = 11, text = K.rsync.text }

local function mseg_body(ctx, dl, track, src, x, y, w, isopen)
  local p = MP.get(track, src.slot, src.j, "mseg")
  if not p then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + C.S(54), 0x121416ff, 3)
    return
  end
  if not isopen then
    mseg_graph(ctx, dl, track, src, p, x, y, w, C.S(54), false)
    return
  end
  mseg_graph(ctx, dl, track, src, p, x, y, w, C.S(118), true)
  y = y + C.S(122)
  -- length (sync / Hz), loop, snap and grid, presets
  local sync = live_field(track, src, "sync") >= 0.5
  if pill(ctx, dl, "mssy##" .. src.guid, x, y, C.S(42), "Sync", sync, src.col) and not sync then
    MD.set_field(track, src.slot, src.j, "sync", 1)
  end
  mx_switch(ctx, dl, track, src, "sync", 1, x, y, C.S(42), Z.PILL_H)
  if pill(ctx, dl, "mshz##" .. src.guid, x + C.S(44), y, C.S(42), "Hz", not sync, src.col) and sync then
    MD.set_field(track, src.slot, src.j, "sync", 0)
  end
  mx_switch(ctx, dl, track, src, "sync", 0, x + C.S(44), y, C.S(42), Z.PILL_H)
  local lp = MD.field(track, src.slot, src.j, "mhold") >= 0.5
  if pill(ctx, dl, "mslp##" .. src.guid, x + C.S(94), y, C.S(44), "Loop", lp, src.col) then
    MD.set_field(track, src.slot, src.j, "mhold", lp and 0 or 1)
  end
  W.tip(ctx, "mslp##" .. src.guid, "Off: a trigger runs it once, then it holds at its end", ImGui.IsItemHovered(ctx), false)
  local sn = snap_on()
  if pill(ctx, dl, "mssn##" .. src.guid, x + C.S(146), y, C.S(44), "Snap", sn, src.col) then
    reaper.SetExtState(C.EXT_SECT, "mseg_snap", sn and "0" or "1", true)
  end
  W.tip(ctx, "mssn##" .. src.guid, "Points land on the grid", ImGui.IsItemHovered(ctx), false)
  local grids = { 4, 8, 12, 16, 32 }
  local gnames, gcur = {}, 2
  for k, v in ipairs(grids) do gnames[k] = ("Grid %d"):format(v); if v == grid_n() then gcur = k end end
  local gp = choice_pill(ctx, dl, "msgr##" .. src.guid, x + C.S(192), y, C.S(62), gnames[gcur], gnames, gcur, src.col)
  if gp then reaper.SetExtState(C.EXT_SECT, "mseg_grid", tostring(grids[gp]), true) end
  -- presets: the built-in shapes, your own, save this one
  local pid = "mspr##" .. src.guid
  if pill(ctx, dl, pid, x + w - C.S(76), y, C.S(76), "Presets \u{25BE}", false, src.col) then ImGui.OpenPopup(ctx, "pp" .. pid) end
  if ImGui.BeginPopup(ctx, "pp" .. pid) then
    local function use(list)
      p.pts = {}
      for k, q in ipairs(list) do p.pts[k] = { q[1], q[2], q[3] or 0 } end
      MP.put(track, src.slot, src.j, "mseg", p)
    end
    for _, e in ipairs(MSEG_PRESETS) do if ImGui.MenuItem(ctx, e[1]) then use(e[2]) end end
    local mine = saved_presets()
    if #mine > 0 then ImGui.Separator(ctx) end
    for k, e in ipairs(mine) do
      if ImGui.MenuItem(ctx, e[1] .. "##own" .. k) then use(e[2]) end
    end
    ImGui.Separator(ctx)
    if ImGui.BeginMenu(ctx, "Save this as\u{2026}") then
      SM.preset_name = SM.preset_name or ""
      ImGui.SetNextItemWidth(ctx, 160)
      local _, v = ImGui.InputTextWithHint(ctx, "##msname", "name", SM.preset_name)
      SM.preset_name = v
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Save##mssave") and U.trim(v) ~= "" then
        local list = saved_presets()
        list[#list + 1] = { U.trim(v), copy_pts(p).pts }
        save_presets(list)
        SM.preset_name = ""
        ImGui.CloseCurrentPopup(ctx)
      end
      ImGui.EndMenu(ctx)
    end
    if #mine > 0 and ImGui.BeginMenu(ctx, "Delete") then
      for k, e in ipairs(mine) do
        if ImGui.MenuItem(ctx, e[1] .. "##del" .. k) then table.remove(mine, k); save_presets(mine) break end
      end
      ImGui.EndMenu(ctx)
    end
    ImGui.EndPopup(ctx)
  end
  y = y + C.S(22)
  -- its trigger
  local trg = math.floor(MD.field(track, src.slot, src.j, "msrc") + 0.5)
  local tnames = { "Song", "Free", "Note", "Audio" }
  for i, t in ipairs(tnames) do
    local tid = ("mstr%d##%s"):format(i, src.guid)
    if pill(ctx, dl, tid, x + (i - 1) * C.S(52), y, C.S(50), t, trg == i - 1, src.col) and trg ~= i - 1 then
      MD.set_field(track, src.slot, src.j, "msrc", i - 1)
    end
    W.tip(ctx, tid, MSEG_TRIG_TIP[i], ImGui.IsItemHovered(ctx), false)
  end
  y = y + C.S(22)
  if trg == 2 then
    local chn = math.floor(MD.field(track, src.slot, src.j, "mch") + 0.5)
    local chs = { "Omni" }
    for k = 1, 16 do chs[k + 1] = ("Ch %d"):format(k) end
    local c = choice_pill(ctx, dl, "msch##" .. src.guid, x, y, C.S(54), chs[chn + 1] or "Omni", chs, chn + 1, src.col)
    if c then MD.set_field(track, src.slot, src.j, "mch", c - 1) end
    local names = {}
    for k = 0, 127 do names[k + 1] = note_name(k) end
    local lo = math.floor(MD.field(track, src.slot, src.j, "mlo") + 0.5)
    local hi = math.floor(MD.field(track, src.slot, src.j, "mhi") + 0.5)
    W.push_small(ctx)
    ImGui.DrawList_AddText(dl, x + C.S(60), y + C.S(2), C.COL.label, "Notes")
    W.pop_small(ctx)
    local a = choice_pill(ctx, dl, "mslo##" .. src.guid, x + C.S(96), y, C.S(44), note_name(lo), names, lo + 1, src.col)
    if a then MD.set_field(track, src.slot, src.j, "mlo", a - 1) end
    local b = choice_pill(ctx, dl, "mshi##" .. src.guid, x + C.S(144), y, C.S(44), note_name(hi), names, hi + 1, src.col)
    if b then MD.set_field(track, src.slot, src.j, "mhi", b - 1) end
    y = y + C.S(22)
  elseif trg == 3 then
    setting(ctx, dl, track, src, K.thr, x, y)
    local side = MD.field(track, src.slot, src.j, "fsrc") >= 0.5
    local sx = x + Z.KCELL_W + C.S(6)
    if pill(ctx, dl, "mstk##" .. src.guid, sx, y + C.S(8), C.S(50), "Track", not side, src.col) and side then
      MD.set_field(track, src.slot, src.j, "fsrc", 0)
    end
    if pill(ctx, dl, "mssc##" .. src.guid, sx + C.S(52), y + C.S(8), C.S(66), "Sidechain", side, src.col) and not side then
      MD.set_field(track, src.slot, src.j, "fsrc", 1)
      MD.need_sidechain(track)
    end
    y = y + Z.KCELL_H
  end
  setting(ctx, dl, track, src, sync and K_LEN or K.rhz, x, y)
  setting(ctx, dl, track, src, K.depth, x + Z.KCELL_W, y)
  setting(ctx, dl, track, src, K.phase, x + Z.KCELL_W * 2, y)
  setting(ctx, dl, track, src, K.smooth, x + Z.KCELL_W * 3, y)
end

local function draw_tile(ctx, dl, track, src, s, x, y, h, req)
  local w = tile_w(track, src)
  local key = tostring(track) .. src.guid
  local isopen = open[key]
  sample(key, MD.value(track, src))
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.panel_bg, 4)
  local lit = MR.ctl_hover_prev and MR.ctl_hover_prev.guid == src.guid
  ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5,
    (isopen or lit) and src.col or C.COL.panel_border, 4, 0, lit and 2.0 or 1.0)
  ImGui.DrawList_AddRectFilled(dl, x + C.S(6), y + C.S(6), x + C.S(14), y + C.S(14), src.col, 2)
  -- held at rest: this one bypassed, or all of them
  local own_byp = MD.bypassed(track, src.slot, src.j)
  local held = own_byp or MD.bypassed(track, src.slot)
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, "name##" .. src.guid, w - C.S(42), Z.HEAD,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then open[key] = not isopen or nil end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    rename_buf[src.guid] = src.name
    ImGui.OpenPopup(ctx, "modtile##" .. src.guid)
  end
  W.tip(ctx, "name##" .. src.guid, isopen and "Click: close\nRight-click: more"
    or "Click: settings\nRight-click: lanes, rename, colour, remove", ImGui.IsItemHovered(ctx), false)
  local nm = U.truncate(src.name, 18)
  ImGui.DrawList_AddText(dl, x + C.S(19), y + C.S(3), held and C.COL.header_dim or C.COL.header_text, nm)
  if MD.bypass_ok(track, src.slot) then
    ImGui.SetCursorScreenPos(ctx, x + w - C.S(38), y + C.S(2))
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
    local dx = x + C.S(19) + ImGui.CalcTextSize(ctx, nm) + 7
    local names = {}
    for sl = 1, MD.MX_SLOTS do
      local e = slots[sl]
      if e then
        local from = MD.mx_source(track, e.code)
        ImGui.DrawList_AddCircleFilled(dl, dx, y + C.S(10), 3, from and from.col or C.COL.label, 10)
        names[#names + 1] = (from and from.name or "?") .. " \u{2192} " .. tg_label(track, src, e.tg)
        dx = dx + 8
      end
    end
    if #names > 0 then
      local mx, my = ImGui.GetMousePos(ctx)
      if mx >= dx - 8 * #names - 4 and mx < dx and my >= y + C.S(4) and my < y + C.S(16) then
        ImGui.SetTooltip(ctx, "Moved by\n" .. table.concat(names, "\n"))
      end
    end
  end
  local links = s.by_mod[src.guid] or {}
  W.push_small(ctx)
  local sub = held and ("bypassed \u{00B7} " .. sub_text(track, src, #links)) or sub_text(track, src, #links)
  ImGui.DrawList_AddText(dl, x + C.S(8), y + Z.HEAD - 1, held and C.COL.bypass_on or C.COL.header_dim, U.truncate(sub, 34))
  W.pop_small(ctx)
  link_handle(ctx, dl, src, 1, x + w - C.S(12), y + C.S(9), C.S(5.5))
  local bx, by, bw = x + C.S(6), y + Z.HEAD + Z.SUB + 2, w - C.S(12)
  if src.kind == "lfo" then lfo_body(ctx, dl, track, src, key, bx, by, bw, isopen)
  elseif src.kind == "follower" then follower_body(ctx, dl, track, src, bx, by, bw, isopen)
  elseif src.kind == "steps" then steps_body(ctx, dl, track, src, bx, by, bw, isopen)
  elseif src.kind == "mseg" then mseg_body(ctx, dl, track, src, bx, by, bw, isopen)
  else midi_body(ctx, dl, track, src, bx, by, bw, isopen) end
  mod_menu(ctx, track, src, s, req)
end

local function mod_add_menu(ctx, req)
  if not ImGui.BeginPopup(ctx, "modadd") then return end
  ImGui.TextDisabled(ctx, "Add a modulator")
  ImGui.Separator(ctx)
  local notes = { lfo = "tempo-synced or free", follower = "a signal's level", midi = "velocity, note, CC, bend",
                  steps = "a sequence you draw", mseg = "a shape you draw" }
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
    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.header_bg, C.PANEL_RR)
    local label = TITLE[which] .. (n > 0 and (" · " .. n) or "")
    local _, th = ImGui.CalcTextSize(ctx, label)
    ImGui.DrawList_AddText(dl, x + C.S(6), y + (wh - th) * 0.5, C.COL.header_dim, label)
    ImGui.SetCursorScreenPos(ctx, x + ww - btn - 3, y + (wh - btn) * 0.5)
    if W.icon_button(ctx, which .. "exp", "expand", btn, false, "Show the " .. TITLE[which]:lower()) then
      set_collapsed(which, false)
    end
    MR.bar_at[which] = { x + C.S(12), y + wh * 0.5 }
    return
  end
  ImGui.SetCursorScreenPos(ctx, x + (ww - btn) * 0.5, y + C.S(4))
  if W.icon_button(ctx, which .. "exp", "expand", btn, false, "Show the " .. TITLE[which]:lower()) then
    set_collapsed(which, false)
  end
  local label = TITLE[which]:upper() .. (n > 0 and (" " .. n) or "")
  W.vertical_text(ctx, dl, x + ww * 0.5, y + C.S(4) + btn + 6, label, C.COL.header_dim, wh - btn - 16)
  MR.bar_at[which] = { x + ww * 0.5, y + wh * 0.4 }
end

-- `extra(bx, by)`, when given, draws a button left of the fold button.
local function frame_of(ctx, dl, which, x, y, ww, wh, foot, extra)
  local btn = C.ICON_SIZE
  ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + C.HEADER_H, C.COL.header_bg, C.PANEL_RR,
    ImGui.DrawFlags_RoundCornersTop)
  ImGui.DrawList_AddLine(dl, x, y + C.HEADER_H, x + ww, y + C.HEADER_H, C.COL.panel_border, 1.0)
  ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, C.PANEL_RR, 0, 1.0)  -- (its edge over the header)
  local _, th = ImGui.CalcTextSize(ctx, TITLE[which])
  ImGui.DrawList_AddText(dl, x + C.S(6), y + (C.HEADER_H - th) * 0.5, C.COL.header_text, TITLE[which])
  ImGui.SetCursorScreenPos(ctx, x + ww - btn - 3, y + C.S(3))
  if W.icon_button(ctx, which .. "col", "collapse", btn, false, "Fold the " .. TITLE[which]:lower() .. " away") then
    set_collapsed(which, true)
  end
  if extra then extra(x + ww - 2 * btn - 7, y + C.S(3)) end
  -- the foot, as every panel's: how many are in use, centred
  local fh = C.FOOTER_H
  local fy = y + wh - fh
  ImGui.DrawList_AddRectFilled(dl, x + C.S(1), fy, x + ww - 1, y + wh - 1, C.COL.header_bg, C.PANEL_RR,
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
    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, C.PANEL_RR)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, C.PANEL_RR, 0, 1.0)
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
      if W.dashed_plus(ctx, "macroadd_foot", GROUP_W, Z.ADD_H, "Add a macro") then
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
    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, C.PANEL_RR)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, C.PANEL_RR, 0, 1.0)
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
      if W.dashed_plus(ctx, "modadd_foot", Z.TILE_W, Z.ADD_H, "Add a modulator") then
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

-- (tests: a tile opened)
function MR._open(track, guid, on) open[tostring(track) .. guid] = on or nil end

return MR
