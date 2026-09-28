-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Toolbar.lua -- the TCP's toolbar: a row of buttons, each one a
  REAPER action, in the space above the first track.

  That space is exactly as tall as the ruler and the marker/region lanes
  beside it, because it is whatever lies between the top of the window
  and the top of the arrange view -- measured, not configured. Buttons
  wrap onto a second row when the ruler is tall enough to have one.

  An action is picked with REAPER's own Action List (PromptForAction),
  so anything with a command id works: native actions, SWS, your own
  scripts. It is stored by NAME when it has one ("_RS3f2a..."), because
  a script's numeric id is only valid for this session -- the name is
  what survives a restart.

  Icons are REAPER's toolbar PNGs from Data/toolbar_icons, the same
  files its own toolbars use. Those are usually three frames side by
  side -- normal, hover, pressed -- and are drawn that way, with the
  pressed frame standing in for "on" on a toggle action. A single-frame
  PNG is drawn as it is, with the button's own highlight behind it.

  The list lives in ExtState as one line: items split by ";", fields by
  "|". A label can't contain either -- they are simply dropped on the way
  in, which is the whole of the escaping.
--]]

local C = require("TS_CV_Config")
local U = require("TS_CV_Util")
local W = require("TS_CV_Widgets")

local ImGui

-- Enough to show what the thing is for on a fresh install. Labels, not
-- icons: stock icon filenames differ between REAPER versions and themes,
-- and a missing icon would be a blank button.
local TOP_DEFAULTS = {
  { cmd = "40001", icon = "", label = "+ Track" },   -- Track: Insert new track
  { cmd = "40029", icon = "", label = "Undo" },      -- Edit: Undo
  { cmd = "40030", icon = "", label = "Redo" },      -- Edit: Redo
  { sep = true },
  { cmd = "40364", icon = "", label = "Click" },     -- Options: Toggle metronome
  { cmd = "1157",  icon = "", label = "Snap" },      -- Options: Toggle snapping
}

-- One toolbar per call: `key` is its ExtState key, `tag` prefixes every
-- ImGui id so two bars in one window don't share buttons or popups, and
-- `defaults` is what it holds before anything is saved. The TCP has two:
-- one beside the ruler, one under the tracks beside the transport.
local function make(key, tag, defaults)
local KEY, ID = key, tag
local DEFAULTS = defaults or {}
local TB = {}
TB.DEFAULTS = DEFAULTS

TB.items = {}

-- ---------------------------------------------------------------------
-- pure: storage
-- ---------------------------------------------------------------------

local function clean(s) return ((s or ""):gsub("[;|]", "")) end

function TB.serialize(items)
  if #items == 0 then return "none" end
  local out = {}
  for _, it in ipairs(items) do
    if it.sep then out[#out + 1] = "-"
    else out[#out + 1] = clean(it.cmd) .. "|" .. clean(it.icon) .. "|" .. clean(it.label) end
  end
  return table.concat(out, ";")
end

-- "" (never saved) gives the defaults; "none" is a toolbar emptied on
-- purpose and stays empty.
function TB.parse(s)
  if s == nil or s == "" then
    local out = {}
    for i, it in ipairs(DEFAULTS) do
      out[i] = { sep = it.sep, cmd = it.cmd, icon = it.icon, label = it.label }
    end
    return out
  end
  local out = {}
  if s == "none" then return out end
  for part in (s .. ";"):gmatch("([^;]*);") do
    if part == "-" then
      out[#out + 1] = { sep = true }
    elseif part ~= "" then
      local cmd, icon, label = part:match("^([^|]*)|?([^|]*)|?(.*)$")
      if cmd and cmd ~= "" then
        out[#out + 1] = { cmd = cmd, icon = icon or "", label = label or "" }
      end
    end
  end
  return out
end

-- The stored form of a command id: "_NAME" when REAPER knows it by one,
-- the number otherwise.
function TB.stored_cmd(id)
  local name = reaper.ReverseNamedCommandLookup(id)
  if name and name ~= "" then return "_" .. name end
  return tostring(id)
end

-- And back. 0 or nil when it no longer resolves (a script since removed).
function TB.resolve(cmd)
  if not cmd or cmd == "" then return nil end
  if cmd:sub(1, 1) == "_" then
    local id = reaper.NamedCommandLookup(cmd)
    return (id and id ~= 0) and id or nil
  end
  local id = tonumber(cmd)
  return (id and id > 0) and id or nil
end

function TB.action_name(id)
  if not id then return nil end
  if reaper.CF_GetCommandText then
    local t = reaper.CF_GetCommandText(0, id)
    if type(t) == "string" and t ~= "" then return t end
  end
  local ok, t = pcall(reaper.kbd_getTextFromCmd, id, nil)
  if ok and type(t) == "string" and t ~= "" then return t end
  return nil
end

-- A label to draw when a button has neither icon nor label of its own:
-- the action's name after its category ("Edit: Undo" -> "Undo"), cut
-- down to something a button can carry.
function TB.short_name(text)
  if not text or text == "" then return "?" end
  local s = text:match(":%s*(.+)$") or text
  s = s:gsub("^Toggle%s+", "")
  if #s > 12 then s = s:sub(1, 11) .. "." end
  return s
end

-- ---------------------------------------------------------------------
-- load / save
-- ---------------------------------------------------------------------

function TB.load()
  TB.items = TB.parse(reaper.GetExtState(C.TCP_EXT_SECT, KEY))
end

function TB.save()
  reaper.SetExtState(C.TCP_EXT_SECT, KEY, TB.serialize(TB.items), true)
end

-- ---------------------------------------------------------------------
-- icons
-- ---------------------------------------------------------------------

local sep = package.config:sub(1, 1)
function TB.icon_dir()
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "toolbar_icons"
end

local images = {}          -- file name -> image, or false once it has failed
local loads_left = 0       -- per-frame load budget, see TB.draw / the picker

local function image(ctx, file)
  if not file or file == "" then return nil end
  local img = images[file]
  if img == nil then
    -- Loading is the one expensive thing here. The picker can put a few
    -- hundred icons on screen at once, and loading all of them in one
    -- frame is a visible stall -- so a handful per frame, the rest next
    -- frame. A button drawn before its icon arrives shows its label.
    if loads_left <= 0 then return nil end
    loads_left = loads_left - 1
    local ok, res = pcall(ImGui.CreateImage, TB.icon_dir() .. sep .. file)
    if ok and res then
      pcall(ImGui.Attach, ctx, res)
      img = res
    else
      img = false
    end
    images[file] = img
  end
  return img or nil
end

-- Draws a toolbar PNG into the box, frame `state` (1 normal, 2 hover, 3
-- pressed) when it has three. Returns the width it took, or nil when
-- there is no image to draw.
local function draw_icon(ctx, dl, file, x, y, h, state)
  local img = image(ctx, file)
  if not img then return nil end
  local iw, ih = ImGui.Image_GetSize(img)
  if not iw or iw <= 0 or not ih or ih <= 0 then return nil end
  local frames = (iw >= ih * 2.5) and 3 or 1
  local fw = iw / frames
  local dw = h * fw / ih
  local f = (frames == 3) and (state - 1) or 0
  ImGui.DrawList_AddImage(dl, img, x, y, x + dw, y + h,
    f / frames, 0, (f + 1) / frames, 1)
  return dw, frames
end

local function icon_width(ctx, file, h)
  local img = image(ctx, file)
  if not img then return nil end
  local iw, ih = ImGui.Image_GetSize(img)
  if not iw or iw <= 0 or not ih or ih <= 0 then return nil end
  local frames = (iw >= ih * 2.5) and 3 or 1
  return h * (iw / frames) / ih
end

-- ---------------------------------------------------------------------
-- picking an action
-- ---------------------------------------------------------------------

-- While REAPER's Action List is open for us: where the result goes.
-- { at = index to insert before, replace = index to overwrite }.
local pick = nil

function TB.picking() return pick ~= nil end

function TB.pick_start(at, replace)
  if pick then reaper.PromptForAction(-1, 0, 0) end
  pick = { at = at, replace = replace }
  reaper.PromptForAction(1, 0, 0)
end

-- Polled once a frame. PromptForAction answers 0 until something is
-- chosen, -1 once the Action List has been closed.
function TB.poll()
  if not pick then return end
  local r = reaper.PromptForAction(0, 0, 0)
  if r == 0 then return end
  reaper.PromptForAction(-1, 0, 0)
  local p = pick
  pick = nil
  if r < 0 then return end
  local cmd = TB.stored_cmd(r)
  if p.replace and TB.items[p.replace] and not TB.items[p.replace].sep then
    TB.items[p.replace].cmd = cmd
  else
    local at = math.max(1, math.min(#TB.items + 1, p.at or (#TB.items + 1)))
    table.insert(TB.items, at, { cmd = cmd, icon = "", label = "" })
  end
  TB.save()
end

function TB.cancel_pick()
  if pick then reaper.PromptForAction(-1, 0, 0) end
  pick = nil
end

-- ---------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------

local st = {
  item_menu = nil, open_item = false, open_bg = false,
  label_buf = "",
  icons_for = nil, open_icons = false, icon_list = nil, icon_filter = "",
}

-- The width a button will take: its icon's, or its label's.
local function item_width(ctx, it, bh)
  if it.sep then return 7 end
  if it.icon ~= "" then
    local iw = icon_width(ctx, it.icon, bh)
    if iw then return iw end
  end
  local text = (it.label ~= "" and it.label)
               or TB.short_name(TB.action_name(TB.resolve(it.cmd)))
  return math.max(bh, ImGui.CalcTextSize(ctx, text) + 12), text
end

local function draw_item(ctx, dl, i, it, x, y, bw, bh)
  if it.sep then
    ImGui.SetCursorScreenPos(ctx, x, y)
    ImGui.InvisibleButton(ctx, ID .. "sep" .. i, bw, bh)
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
      st.item_menu, st.open_item = i, true
    end
    local cx = math.floor(x + bw * 0.5) + 0.5
    ImGui.DrawList_AddLine(dl, cx, y + 4, cx, y + bh - 4, C.COL.panel_border, 1.0)
    return
  end

  local id = TB.resolve(it.cmd)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local pressed = ImGui.InvisibleButton(ctx, ID .. i, bw, bh)
  local hovered = ImGui.IsItemHovered(ctx)
  local held    = ImGui.IsItemActive(ctx)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    st.item_menu, st.open_item = i, true
    st.label_buf = it.label or ""
  end
  local on = id and reaper.GetToggleCommandStateEx(0, id) == 1

  local state = (held or on) and 3 or (hovered and 2 or 1)
  local drawn, frames = nil, nil
  if it.icon ~= "" then
    -- A single-frame icon has no hover or pressed look of its own, so
    -- the button supplies one behind it.
    local img = image(ctx, it.icon)
    if img then
      local iw, ih = ImGui.Image_GetSize(img)
      if iw and ih and ih > 0 and iw < ih * 2.5 and (hovered or on or held) then
        ImGui.DrawList_AddRectFilled(dl, x, y, x + bw, y + bh,
          on and U.with_alpha(C.COL.accent, 0x99) or C.COL.knob_body_hi, 2.5)
      end
    end
    drawn, frames = draw_icon(ctx, dl, it.icon, x, y, bh, state)
    -- A three-frame icon whose "pressed" frame looks like its normal one
    -- would leave an "on" toggle unmarked; a thin accent underline is
    -- cheap insurance.
    if drawn and on and frames == 3 then
      ImGui.DrawList_AddLine(dl, x + 3, y + bh - 1, x + bw - 3, y + bh - 1,
        C.COL.accent, 2.0)
    end
  end
  if not drawn then
    local text = (it.label ~= "" and it.label)
                 or TB.short_name(TB.action_name(id))
    local bg = on and C.COL.accent
               or ((hovered or held) and C.COL.knob_body_hi or C.COL.toggle_off)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + bw, y + bh, bg, 2.5)
    ImGui.DrawList_AddRect(dl, x, y, x + bw, y + bh, C.COL.knob_ring, 2.5, 0, 1.0)
    local tw, th = ImGui.CalcTextSize(ctx, text)
    ImGui.DrawList_AddText(dl, x + (bw - tw) * 0.5, y + (bh - th) * 0.5,
      on and C.COL.icon_on or (id and C.COL.label or C.COL.warn), text)
  end

  local name = TB.action_name(id)
  W.tip(ctx, ID .. i,
    name and (it.label ~= "" and (it.label .. "\n" .. name) or name)
         or ("Action not found: " .. tostring(it.cmd)),
    hovered, false)
  if pressed and id then reaper.Main_OnCommand(id, 0) end
end

-- Draws the toolbar into the box x, y, w, h and handles its own menus.
-- Returns:
--   menu      true when the settings button was clicked
--   overflow  the items that didn't fit, for the settings menu to list
-- `no_menu` leaves out the settings button: only the top toolbar has it.
function TB.draw(ctx, x, y, w, h, no_menu)
  loads_left = 8
  TB.poll()
  local dl = ImGui.GetWindowDrawList(ctx)
  local bh = C.TB_BTN
  local res = { menu = false, overflow = {} }
  if h < C.TB_MIN_H then return res end
  bh = math.min(bh, h - 4)

  -- Settings, hard right.
  local mb = C.ICON_SIZE + 4
  local mx = x + w - mb - 4
  local rows = math.max(1, math.floor((h - 4 + C.TB_GAP) / (bh + C.TB_GAP)))
  local top = y + math.max(2, (h - (rows * bh + (rows - 1) * C.TB_GAP)) * 0.5)

  -- The empty space is the toolbar's own right-click target, submitted
  -- first so every button sits on top of it.
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, ID .. "bg", math.max(1, w), math.max(1, h))
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then st.open_bg = true end

  if no_menu then
    mx = x + w - 2
  else
    ImGui.SetCursorScreenPos(ctx, mx, top + (bh - mb) * 0.5)
    if W.icon_button(ctx, ID .. "menu", "menu", mb, false, "Settings") then
      res.menu = true
    end
  end

  local cx, row = x + 4, 0
  local right = mx - 6
  if #TB.items == 0 and not pick then
    local hint = "Right-click to add actions"
    local tw, th = ImGui.CalcTextSize(ctx, hint)
    if tw < right - cx then
      ImGui.DrawList_AddText(dl, cx + 2, y + (h - th) * 0.5, C.COL.header_dim, hint)
    end
  end
  for i, it in ipairs(TB.items) do
    local bw = item_width(ctx, it, bh)
    if cx + bw > right and cx > x + 4 then
      row, cx = row + 1, x + 4
    end
    if row >= rows then
      if not it.sep then res.overflow[#res.overflow + 1] = it end
    else
      draw_item(ctx, dl, i, it, cx, top + row * (bh + C.TB_GAP), bw, bh)
      cx = cx + bw + C.TB_GAP
    end
  end

  if pick then
    local note = "Pick an action, then Select\u{2026}"
    local tw, th = ImGui.CalcTextSize(ctx, note)
    if cx + tw < right then
      ImGui.DrawList_AddText(dl, cx + 4, top + (bh - th) * 0.5, C.COL.accent, note)
    end
  end

  -- Keep the promise the cursor moves made. See W.child_skipped.
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.Dummy(ctx, 0, 0)
  return res
end

-- Runs a stored item, for the settings menu's overflow list.
function TB.run(it)
  local id = it and TB.resolve(it.cmd)
  if id then reaper.Main_OnCommand(id, 0) end
end

function TB.label_of(it)
  local id = TB.resolve(it.cmd)
  return (it.label ~= "" and it.label) or TB.action_name(id) or tostring(it.cmd)
end

-- ---------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------

local function move(i, d)
  local j = i + d
  if j < 1 or j > #TB.items then return end
  TB.items[i], TB.items[j] = TB.items[j], TB.items[i]
  TB.save()
end

local function item_menu(ctx)
  if st.open_item then ImGui.OpenPopup(ctx, ID .. "_item"); st.open_item = false end
  if not ImGui.BeginPopup(ctx, ID .. "_item") then return end
  local i  = st.item_menu
  local it = i and TB.items[i]
  if not it then ImGui.EndPopup(ctx) return end

  if it.sep then
    ImGui.TextDisabled(ctx, "Separator")
  else
    ImGui.TextDisabled(ctx, U.truncate(TB.action_name(TB.resolve(it.cmd))
                                       or ("not found: " .. it.cmd), 40))
  end
  ImGui.Separator(ctx)

  if not it.sep then
    if ImGui.MenuItem(ctx, "Change action\u{2026}") then TB.pick_start(nil, i) end
    if ImGui.MenuItem(ctx, "Icon\u{2026}") then
      st.icons_for, st.open_icons = i, true
    end
    if ImGui.MenuItem(ctx, "No icon", nil, false, it.icon ~= "") then
      it.icon = ""; TB.save()
    end
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, "Label (blank: the action's name)")
    ImGui.SetNextItemWidth(ctx, 150)
    local ch, v = ImGui.InputText(ctx, "##" .. ID .. "label", st.label_buf)
    if ch then st.label_buf = v end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Set") then
      it.label = clean(st.label_buf); TB.save()
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.Separator(ctx)
  end
  if ImGui.MenuItem(ctx, "Move left", nil, false, i > 1) then move(i, -1) end
  if ImGui.MenuItem(ctx, "Move right", nil, false, i < #TB.items) then move(i, 1) end
  if ImGui.MenuItem(ctx, "Insert action before\u{2026}") then TB.pick_start(i) end
  if ImGui.MenuItem(ctx, "Insert separator before") then
    table.insert(TB.items, i, { sep = true }); TB.save()
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Remove") then
    table.remove(TB.items, i); TB.save()
  end
  ImGui.EndPopup(ctx)
end

local function bg_menu(ctx)
  if st.open_bg then ImGui.OpenPopup(ctx, ID .. "_bg"); st.open_bg = false end
  if not ImGui.BeginPopup(ctx, ID .. "_bg") then return end
  if ImGui.MenuItem(ctx, "Add action\u{2026}") then TB.pick_start(nil) end
  if ImGui.MenuItem(ctx, "Add separator") then
    TB.items[#TB.items + 1] = { sep = true }; TB.save()
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Reset to the default buttons") then
    TB.items = TB.parse(""); TB.save()
  end
  ImGui.EndPopup(ctx)
end

-- The icon picker: every PNG in Data/toolbar_icons, filterable by name.
local function list_icons()
  local out, dir = {}, TB.icon_dir()
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    if f:lower():match("%.png$") then out[#out + 1] = f end
    i = i + 1
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

local ICON_CELL = 34

local function icon_picker(ctx)
  if st.open_icons then
    st.open_icons = false
    st.icon_list = list_icons()
    ImGui.OpenPopup(ctx, ID .. "_icons")
  end
  if not ImGui.BeginPopup(ctx, ID .. "_icons") then return end
  local it = st.icons_for and TB.items[st.icons_for]
  if not it or it.sep then ImGui.EndPopup(ctx) return end

  loads_left = 24
  ImGui.SetNextItemWidth(ctx, 200)
  local ch, v = ImGui.InputTextWithHint(ctx, "##" .. ID .. "iconflt", "filter\u{2026}", st.icon_filter)
  if ch then st.icon_filter = v end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, U.truncate(TB.icon_dir(), 40))

  local list = st.icon_list or {}
  if #list == 0 then
    ImGui.TextDisabled(ctx, "No PNG files in that folder.")
    ImGui.EndPopup(ctx)
    return
  end

  local cols = 12
  if ImGui.BeginChild(ctx, ID .. "iconsgrid", cols * (ICON_CELL + 4) + 12, 300) then
    local dl = ImGui.GetWindowDrawList(ctx)
    local flt = st.icon_filter:lower()
    local n = 0
    for _, f in ipairs(list) do
      if flt == "" or f:lower():find(flt, 1, true) then
        if n % cols ~= 0 then ImGui.SameLine(ctx, 0, 4) end
        n = n + 1
        local x, y = ImGui.GetCursorScreenPos(ctx)
        if ImGui.InvisibleButton(ctx, "ic" .. f, ICON_CELL, ICON_CELL) then
          it.icon = f; TB.save()
          ImGui.CloseCurrentPopup(ctx)
        end
        local hov = ImGui.IsItemHovered(ctx)
        if hov or f == it.icon then
          ImGui.DrawList_AddRectFilled(dl, x, y, x + ICON_CELL, y + ICON_CELL,
            f == it.icon and U.with_alpha(C.COL.accent, 0x88) or C.COL.knob_body_hi, 2.5)
        end
        -- Only what's on screen is loaded: everything above and below the
        -- scroll is a rectangle ImGui already knows it will clip.
        if ImGui.IsItemVisible(ctx) then
          local iw = icon_width(ctx, f, ICON_CELL - 6)
          if iw then
            local dw = math.min(iw, ICON_CELL - 2)
            draw_icon(ctx, dl, f, x + (ICON_CELL - dw) * 0.5, y + 3, ICON_CELL - 6, hov and 2 or 1)
          end
        end
        if hov then ImGui.SetTooltip(ctx, f) end
      end
    end
    if n == 0 then ImGui.TextDisabled(ctx, "Nothing matches.") end
    ImGui.EndChild(ctx)
  end
  ImGui.EndPopup(ctx)
end

-- Draws whichever toolbar popup is open. Call once a frame from the
-- window TB.draw was called in, outside any child.
function TB.draw_menus(ctx)
  item_menu(ctx)
  bg_menu(ctx)
  icon_picker(ctx)
end

return TB
end   -- make

local TB = make("toolbar", "tb", TOP_DEFAULTS)
TB.make = make
function TB.attach(imgui) ImGui = imgui end
return TB
