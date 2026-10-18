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

  Icons are ChannelView's own ("cv:<key>", TS_CV_ActionIcons: drawn,
  sharp at any size, in the bar's colours) or REAPER's toolbar PNGs from
  Data/toolbar_icons, the same
  files its own toolbars use. Those are usually three frames side by
  side -- normal, hover, pressed -- and are drawn that way, with the
  pressed frame standing in for "on" on a toggle action. A single-frame
  PNG is drawn as it is, with the button's own highlight behind it.

  The list lives in ExtState as one line: items split by ";", fields by
  "|". A label can't contain either -- they are simply dropped on the way
  in, which is the whole of the escaping.

  MENUS. An item can be a menu: a button that opens a menu of actions,
  separators and further menus, nested as deep as you like. Stored in the
  same line, as "[|icon|label" ... "]" around its contents. Every action
  bar has them: the TCP's two toolbars, ChannelView's drawers
  (TS_CV_Drawers) and, through a store of its own, the web companion's
  Actions bar (TS_CV_ActionEditor).

  SWITCHES. An item whose action is "_TSCV_BAR:<id>" swaps the bar it's
  on for bar <id> (TS_CV_Drawers puts that bar where this one was);
  "_TSCV_BAR" alone is a menu of every bar to swap to. Lit when the bar
  it names is the one showing, so a row of them copied onto each bar of
  a set reads as tabs.

  Each bar is one make() instance. Two instances can hold the same bar --
  ChannelView's Organise actions window edits the TCP's toolbars, which
  the TCP script is showing at the same time -- so every save also bumps
  a revision ("<key>#rev"), and an instance that sees it move reloads.
--]]

local C = require("TS_CV_Config")
local U = require("TS_CV_Util")
local W = require("TS_CV_Widgets")
local AI = require("TS_CV_ActionIcons")
local FB = require("TS_CV_FXButtons")

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
-- `store` (optional) keeps the bar somewhere other than ExtState: a table
-- of load() -> items, save(items) and stamp() -> anything that changes
-- when the stored bar does.
local function make(key, tag, defaults, store)
local KEY, ID = key, tag
local DEFAULTS = defaults or {}
local TB = {}
TB.DEFAULTS = DEFAULTS
TB.key, TB.tag = key, tag
-- The button size (height; an icon button is square). A bar can ask for
-- its own (TS_CV_Drawers' Size).
TB.btn = C.TB_BTN
-- Where the buttons sit: across "l", "c" or "r", up and down "t", "c" or
-- "b"; "-" is the usual place (left; a row centred, a column at the top).
TB.halign, TB.valign = "-", "-"

-- How a button's colour shows: "u" an underline, "i" its icon (and
-- label) drawn in it, filling with it while on. A PNG icon keeps the
-- underline either way.
TB.cstyle = "u"

-- "icons": a button is its icon, or its label when it has none (the TCP's
-- look). "both": an icon and a label side by side (a drawer can ask).
TB.style = "icons"
-- Optional hooks, set by whoever shows the bar: extra entries for the
-- bar's own right-click menu (fn(ctx)), and "Organise actions..." (fn()).
TB.extra_bg, TB.organise = nil, nil

TB.items = {}

-- ---------------------------------------------------------------------
-- pure: storage
-- ---------------------------------------------------------------------

local function clean(s) return ((s or ""):gsub("[;|]", "")) end
TB.clean = clean

-- A button's colour, one of these (the web page's too), stored "#rrggbb".
TB.COLOURS = { "#4aa3df", "#c8453c", "#d98a2f", "#d9be45", "#4f9c62", "#3f74b8", "#8a5cc2", "#8d9298", "#e6e0d2", "#26282b" }
local function colour_of(hex)
  local h = type(hex) == "string" and hex:match("^#(%x%x%x%x%x%x)$")
  return h and ((tonumber(h, 16) << 8) | 0xff) or nil
end
TB.colour_of = colour_of
-- A button can show its colour its own way, whatever the bar does: it.cs
-- "u" (underline), "i" (icon and label in it), "ui" (both), "" (neither),
-- nil (as the bar). Stored after the colour: "#rrggbb/ui", "/n" for "".
local function cs_field(it)
  if it.cs == nil then return "" end
  return "/" .. ((it.cs == "") and "n" or it.cs)
end
local function cs_parse(f)
  if not f or f == "" then return nil end
  f = f:sub(2)
  if f == "n" then return "" end
  local u, i = f:find("u", 1, true) ~= nil, f:find("i", 1, true) ~= nil
  return (u and "u" or "") .. (i and "i" or "")
end
TB.cs_parse = cs_parse
local function colour_field(it)
  return colour_of(it.color) and ("|" .. it.color:lower() .. cs_field(it)) or ""
end

local function ser(items, out)
  for _, it in ipairs(items) do
    if it.menu then
      out[#out + 1] = "[|" .. clean(it.icon) .. "|" .. clean(it.label) .. colour_field(it)
      ser(it.items or {}, out)
      out[#out + 1] = "]"
    elseif it.gap then out[#out + 1] = "_"
    elseif it.sep then out[#out + 1] = "-"
    else out[#out + 1] = clean(it.cmd) .. "|" .. clean(it.icon) .. "|" .. clean(it.label) .. colour_field(it) end
  end
end

function TB.serialize(items)
  if #items == 0 then return "none" end
  local out = {}
  ser(items, out)
  return table.concat(out, ";")
end

local function copy_items(src)
  local out = {}
  for i, it in ipairs(src) do
    out[i] = { sep = it.sep, gap = it.gap, cmd = it.cmd, icon = it.icon or "", label = it.label or "",
               color = it.color, cs = it.cs, menu = it.menu, items = it.menu and copy_items(it.items or {}) or nil }
  end
  return out
end
TB.copy_items = copy_items

-- "" (never saved) gives the defaults; "none" is a toolbar emptied on
-- purpose and stays empty.
function TB.parse(s)
  if s == nil or s == "" then
    local out = {}
    for i, it in ipairs(DEFAULTS) do
      out[i] = { sep = it.sep, gap = it.gap, cmd = it.cmd, icon = it.icon, label = it.label }
    end
    return out
  end
  local root = {}
  if s == "none" then return root end
  local out, stack = root, {}
  for part in (s .. ";"):gmatch("([^;]*);") do
    if part == "-" then
      out[#out + 1] = { sep = true }
    elseif part == "_" then
      out[#out + 1] = { sep = true, gap = true }
    elseif part == "]" then
      -- a stray close (no menu open) is dropped
      if #stack > 0 then out = table.remove(stack) end
    elseif part:sub(1, 1) == "[" then
      local icon, label = part:match("^%[|?([^|]*)|?(.*)$")
      local l2, col, cs = (label or ""):match("^(.*)|(#%x%x%x%x%x%x)(/?%a*)$")
      if l2 then label = l2 end
      local m = { menu = true, icon = icon or "", label = label or "", color = col, cs = cs_parse(cs), items = {} }
      out[#out + 1] = m
      stack[#stack + 1] = out
      out = m.items
    elseif part ~= "" then
      local cmd, icon, label = part:match("^([^|]*)|?([^|]*)|?(.*)$")
      local l2, col, cs = (label or ""):match("^(.*)|(#%x%x%x%x%x%x)(/?%a*)$")
      if l2 then label = l2 end
      if cmd and cmd ~= "" then
        out[#out + 1] = { cmd = cmd, icon = icon or "", label = label or "", color = col, cs = cs_parse(cs) }
      end
    end
  end
  return root
end

-- Every action in a bar, menus opened out (for the web page's toggle
-- states, and tests).
function TB.flatten(items, out)
  out = out or {}
  for _, it in ipairs(items or {}) do
    if it.menu then TB.flatten(it.items, out)
    elseif not it.sep then out[#out + 1] = it end
  end
  return out
end

-- Is `list` the contents of `menu`, or of a menu somewhere inside it?
function TB.inside(menu, list)
  if not (menu and menu.menu) then return false end
  if menu.items == list then return true end
  for _, it in ipairs(menu.items or {}) do
    if it.menu and TB.inside(it, list) then return true end
  end
  return false
end

-- Moves list_a[ia] to list_b, before position ib (#list_b + 1: the end).
-- Refused (false) when that would put a menu inside itself. Returns the
-- index it landed at.
function TB.move_item(list_a, ia, list_b, ib)
  local it = list_a[ia]
  if not it then return false end
  if it.menu and TB.inside(it, list_b) then return false end
  table.remove(list_a, ia)
  if list_a == list_b and ib > ia then ib = ib - 1 end
  ib = math.max(1, math.min(#list_b + 1, ib))
  table.insert(list_b, ib, it)
  return ib
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

-- "toolbar_metro_off.png" -> "toolbar_metro_on.png"; nil for any other.
function TB.on_icon(file)
  local base = file and file:match("^(.*)_off%.png$")
  return base and (base .. "_on.png") or nil
end

-- A toolbar switch: "menu" for the menu of bars, a bar id for a button
-- that swaps to that bar, nil for anything else.
TB.SWITCH = "_TSCV_BAR"
function TB.switch_of(it)
  if not it or it.menu or it.sep or type(it.cmd) ~= "string" then return nil end
  if it.cmd == TB.SWITCH then return "menu" end
  local id = it.cmd:match("^_TSCV_BAR:(%d+)$")
  return id and tonumber(id) or nil
end
function TB.switch_cmd(target) return target and (TB.SWITCH .. ":" .. target) or TB.SWITCH end

-- The ChannelView icon made for a stored command, or nil. A script is
-- found by its file name, so it matches whatever its id is here.
local function name_of_cmd(cmd)
  if not (reaper and reaper.NamedCommandLookup) then return nil end
  return TB.action_name(TB.resolve(cmd))
end
function TB.match_icon(cmd)
  return AI.match(cmd, name_of_cmd)
end

-- ---------------------------------------------------------------------
-- copying one of REAPER's toolbars
-- ---------------------------------------------------------------------

-- The icon REAPER draws for an action whose toolbar entry names none:
-- its built-in default. Only the ones that come up; an action not here
-- copies as a text button, and can be given an icon afterwards.
TB.DEFAULT_ICONS = {
  ["40023"] = "toolbar_new.png",        -- New project
  ["40025"] = "toolbar_load.png",       -- Open project
  ["40026"] = "toolbar_save.png",       -- Save project
  ["40021"] = "toolbar_projprop.png",   -- Project settings
  ["40029"] = "toolbar_undo.png",       -- Undo
  ["40030"] = "toolbar_redo.png",       -- Redo
  ["40364"] = "toolbar_metro_off.png",  -- Metronome
  ["42616"] = "toolbar_marquee_cursor_selection_off.png", -- Marquee selection
  ["40041"] = "toolbar_xfade_off.png",  -- Auto-crossfade
  ["1156"]  = "toolbar_group_off.png",  -- Item/track grouping
  ["1162"]  = "toolbar_ripple_off.png", -- Ripple editing
  ["40070"] = "toolbar_envitem_off.png",-- Envelope points move with items
  ["40145"] = "toolbar_grid_off.png",   -- Grid
  ["1157"]  = "toolbar_snap_off.png",   -- Snapping
  ["1135"]  = "toolbar_lock_off.png",   -- Locking
  ["42618"] = "toolbar_razor_off.png",  -- Razor editing
}

local function menu_ini()
  return reaper.GetResourcePath() .. package.config:sub(1, 1) .. "reaper-menu.ini"
end

-- The toolbar sections in reaper-menu.ini, in file order. REAPER writes
-- one there for every toolbar you've customised.
function TB.reaper_toolbars(text)
  if not text then
    local fh = io.open(menu_ini(), "r")
    if not fh then return {} end
    text = fh:read("a"); fh:close()
  end
  local out = {}
  for name in text:gmatch("%[([^%]\n]+)%]") do
    if name:lower():find("toolbar", 1, true) then out[#out + 1] = name end
  end
  return out
end

-- One section's buttons, as this toolbar's items. Pure: `text` is the
-- whole ini. `name_of` (optional) gives an action's full name, so a
-- label that only repeats it is left blank.
function TB.parse_reaper_toolbar(text, section)
  local body, inside = {}, false
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local head = line:match("^%[(.*)%]%s*$")
    if head then
      if inside then break end
      inside = (head == section)
    elseif inside then
      local k, n, v = line:match("^(%a+)_(%d+)=(.*)$")
      if k then
        n = tonumber(n)
        body[n] = body[n] or {}
        body[n][k] = v
      end
    end
  end
  local idx = {}
  for n, e in pairs(body) do if e.item then idx[#idx + 1] = n end end
  table.sort(idx)
  local root = {}
  local out, stack = root, {}
  for _, n in ipairs(idx) do
    local e = body[n]
    local cmd, desc = e.item:match("^(%S+)%s*(.*)$")
    -- REAPER's own menus: -2 opens a submenu (its name after it), -3
    -- closes it, any other negative number is a separator.
    if cmd == "-2" then
      local m = { menu = true, icon = "", label = clean(desc or ""), items = {} }
      out[#out + 1] = m
      stack[#stack + 1] = out
      out = m.items
    elseif cmd == "-3" then
      if #stack > 0 then out = table.remove(stack) end
    elseif cmd and cmd:match("^%-%d+$") then
      out[#out + 1] = { sep = true }
    elseif cmd and cmd ~= "" then
      if cmd:match("^[%a_]") and cmd:sub(1, 1) ~= "_" then cmd = "_" .. cmd end
      local icon = e.icon or ""
      if not icon:lower():match("%.png$") then icon = "" end
      if icon == "" then icon = TB.DEFAULT_ICONS[cmd] or "" end
      -- ChannelView's own icon for it, when there is one
      icon = TB.match_icon(cmd) or icon
      out[#out + 1] = { cmd = cmd, icon = clean(icon), label = clean(desc or "") }
    end
  end
  return root
end

-- The other sections in reaper-menu.ini: menus you've customised.
function TB.reaper_menus(text)
  if not text then
    local fh = io.open(menu_ini(), "r")
    if not fh then return {} end
    text = fh:read("a"); fh:close()
  end
  local out = {}
  for name in text:gmatch("%[([^%]\n]+)%]") do
    if not name:lower():find("toolbar", 1, true) then out[#out + 1] = name end
  end
  return out
end

-- A section's items (toolbar or menu), and its title when it has one.
function TB.read_reaper(section)
  local fh = io.open(menu_ini(), "r")
  if not fh then return {}, nil end
  local text = fh:read("a"); fh:close()
  local title
  local inside = false
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local head = line:match("^%[(.*)%]%s*$")
    if head then
      if inside then break end
      inside = (head == section)
    elseif inside then
      title = title or line:match("^title=(.*)$")
    end
  end
  return TB.parse_reaper_toolbar(text, section), title and clean(title) or nil
end

function TB.import(section)
  local items = TB.read_reaper(section)
  if #items == 0 then return false end
  TB.items = items
  TB.save()
  return true
end

-- ---------------------------------------------------------------------
-- load / save
-- ---------------------------------------------------------------------

local REV = KEY .. "#rev"
local function stamp()
  if store then return store.stamp() end
  return reaper.GetExtState(C.TCP_EXT_SECT, REV)
end

function TB.load()
  if store then TB.items = store.load()
  else TB.items = TB.parse(reaper.GetExtState(C.TCP_EXT_SECT, KEY)) end
  TB.stamp = stamp()
end

local revs = 0
function TB.save()
  if store then
    store.save(TB.items)
  else
    reaper.SetExtState(C.TCP_EXT_SECT, KEY, TB.serialize(TB.items), true)
    revs = revs + 1
    reaper.SetExtState(C.TCP_EXT_SECT, REV, ("%.3f.%d"):format(reaper.time_precise(), revs), false)
  end
  TB.stamp = stamp()
end

-- Reloads when another instance (or the web page) saved this bar.
function TB.sync()
  if TB.stamp == nil or stamp() ~= TB.stamp then TB.load() end
end

-- Wipes the stored bar (a drawer being removed).
function TB.forget()
  if store then return end
  reaper.DeleteExtState(C.TCP_EXT_SECT, KEY, true)
  reaper.DeleteExtState(C.TCP_EXT_SECT, REV, false)
end

-- ---------------------------------------------------------------------
-- icons
-- ---------------------------------------------------------------------

local sep = package.config:sub(1, 1)
function TB.icon_dir()
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "toolbar_icons"
end

-- The active theme's resource folder ("Foo.ReaperTheme" -> "Foo"), where
-- REAPER's own default toolbar icons live (toolbar_new.png and so on).
-- nil for a zipped theme: nothing in it can be loaded from here.
function TB.theme_dir()
  local f = reaper.GetLastColorThemeFile and reaper.GetLastColorThemeFile()
  if type(f) ~= "string" then return nil end
  return f:match("^(.*)%.[Rr][Ee][Aa][Pp][Ee][Rr][Tt][Hh][Ee][Mm][Ee]$")
end

local images = {}          -- file name -> image, or false once it has failed
local loads_left = 0       -- per-frame load budget, see TB.draw / the picker

-- Images aren't attached to the context: a context takes only so many,
-- and the picker shows every PNG in the folder. ReaImGui frees one that
-- nothing has used for a while, so each is checked before use and loaded
-- again when it's gone.
local function image(ctx, file)
  if not file or file == "" or AI.is(file) then return nil end
  local img = images[file]
  if img and not ImGui.ValidatePtr(img, "ImGui_Image*") then img = nil; images[file] = nil end
  if img == nil then
    -- Loading is the one expensive thing here. The picker can put a few
    -- hundred icons on screen at once, and loading all of them in one
    -- frame is a visible stall -- so a handful per frame, the rest next
    -- frame. A button drawn before its icon arrives shows its label.
    if loads_left <= 0 then return nil end
    loads_left = loads_left - 1
    -- Data/toolbar_icons first (your own icons), then the theme's
    -- folder -- the same two places REAPER's toolbars look.
    img = false
    -- Checked with io.open first: a CreateImage on a missing file is
    -- caught by the pcall but still reported in REAPER's error window.
    for _, dir in ipairs({ TB.icon_dir(), TB.theme_dir() }) do
      local path = dir .. sep .. file
      local fh = io.open(path, "rb")
      if fh then fh:close() end
      local ok, res = false, nil
      if fh then ok, res = pcall(ImGui.CreateImage, path) end
      if ok and res then
        img = res
        break
      end
    end
    images[file] = img
  end
  return img or nil
end

-- Draws a toolbar PNG into the box, frame `state` (1 normal, 2 hover, 3
-- pressed) when it has three. Returns the width it took, or nil when
-- there is no image to draw.
local function draw_icon(ctx, dl, file, x, y, h, state)
  if AI.is(file) then
    local ink = (state == 3 and C.COL.icon_on) or (state == 2 and C.COL.icon_hot) or C.COL.icon
    if AI.draw(dl, file, x, y, h, ink) then return h, 1 end
    return nil
  end
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

TB.draw_icon = function(ctx, dl, file, x, y, h, state) return draw_icon(ctx, dl, file, x, y, h, state or 1) end

local function icon_width(ctx, file, h)
  if AI.is(file) then return AI.get(file) and h or nil end
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
-- { list = the list to insert into (TB.items unless a menu's), at = index
-- to insert before, replace = index to overwrite, item = an item to
-- overwrite }.
local pick = nil

function TB.picking() return pick ~= nil end

function TB.pick_start(at, replace)
  if pick then reaper.PromptForAction(-1, 0, 0) end
  pick = { at = at, replace = replace }
  reaper.PromptForAction(1, 0, 0)
end

-- Into a menu's list (or any list of this bar), before `at`.
function TB.pick_into(list, at)
  if pick then reaper.PromptForAction(-1, 0, 0) end
  pick = { list = list, at = at }
  reaper.PromptForAction(1, 0, 0)
end

-- A new action for an existing item.
function TB.pick_replace(item)
  if pick then reaper.PromptForAction(-1, 0, 0) end
  pick = { item = item }
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
  local list = p.list or TB.items
  local function set_cmd(it)
    -- a new action: its own icon, unless the button has one you chose
    local had = TB.match_icon(it.cmd)
    it.cmd = cmd
    if it.icon == "" or (had and it.icon == had) then it.icon = TB.match_icon(cmd) or it.icon end
  end
  if p.item then
    if not p.item.sep and not p.item.menu then set_cmd(p.item) end
  elseif p.replace and list[p.replace] and not list[p.replace].sep and not list[p.replace].menu then
    set_cmd(list[p.replace])
  else
    local at = math.max(1, math.min(#list + 1, p.at or (#list + 1)))
    table.insert(list, at, { cmd = cmd, icon = TB.match_icon(cmd) or "", label = "" })
    TB.last_added = list[at]
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
  pop_item = nil, pop_at = nil, open_pop = false,
}

function TB.allow_loads(n) loads_left = math.max(loads_left, n) end

-- What a button says: its own label, else the action's name cut short.
local function text_of(it)
  if it.label and it.label ~= "" then return it.label end
  if it.menu then return "Menu" end
  local sw = TB.switch_of(it)
  if sw == "menu" then return TB.bar_name or "Toolbars" end
  if sw then return (TB.bar_name_of and TB.bar_name_of(sw)) or ("Bar " .. sw) end
  local fk, fw = FB.kind(it)
  if fk then return FB.short(fk, fw) end
  return TB.short_name(TB.action_name(TB.resolve(it.cmd)))
end
TB.text_of = text_of

-- A button whose click opens a menu: a menu, or the menu of bars.
local function has_caret(it) return it.menu or TB.switch_of(it) == "menu" end

-- The little triangle on a menu button. `dir`: "down", "up", "right" or
-- "left": the way its menu opens.
local function caret(dl, cx, cy, dir, col)
  if dir == "up" then
    ImGui.DrawList_AddTriangleFilled(dl, cx - 3, cy + 1.5, cx + 3, cy + 1.5, cx, cy - 2, col)
  elseif dir == "right" then
    ImGui.DrawList_AddTriangleFilled(dl, cx - 1.5, cy - 3, cx - 1.5, cy + 3, cx + 2, cy, col)
  elseif dir == "left" then
    ImGui.DrawList_AddTriangleFilled(dl, cx + 1.5, cy - 3, cx + 1.5, cy + 3, cx - 2, cy, col)
  else
    ImGui.DrawList_AddTriangleFilled(dl, cx - 3, cy - 1.5, cx + 3, cy - 1.5, cx, cy + 2, col)
  end
end

local POP = "_pop"

-- Where a menu opens from a button at x, y, bw, bh: below it, above it
-- (a bar along the bottom), or beside it (a column).
local function anchor(x, y, bw, bh, dir)
  if dir == "up" then return { x, y - 2, 0, 1 }
  elseif dir == "right" then return { x + bw + 2, y, 0, 0 }
  elseif dir == "left" then return { x - 2, y, 1, 0 }
  end
  return { x, y + bh + 2, 0, 0 }
end

-- The button's click: right-click for its menu, left-click runs it (or
-- opens its menu). Returns hovered, held, on, id.
local function press(ctx, i, it, x, y, bw, bh, dir)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local pressed = ImGui.InvisibleButton(ctx, ID .. i, bw, bh)
  local hovered = ImGui.IsItemHovered(ctx)
  local held    = ImGui.IsItemActive(ctx)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    st.item_menu, st.open_item = i, true
    st.label_buf = it.label or ""
  end
  local sw = TB.switch_of(it)
  if it.menu or sw == "menu" then
    local open = st.pop_item == it and ImGui.IsPopupOpen(ctx, ID .. POP)
    if pressed then
      st.pop_item, st.pop_at, st.open_pop = it, anchor(x, y, bw, bh, dir), true
    end
    W.tip(ctx, ID .. i, (not open) and (sw and "Switch toolbar" or text_of(it)) or nil, hovered, false)
    return hovered, held or open, false, sw and true or nil
  end
  if sw then
    -- lit while its bar is the one showing: a tab
    local lit = sw == TB.bar_id
    W.tip(ctx, ID .. i, lit and text_of(it) or ("Switch to " .. text_of(it)), hovered, false)
    if pressed and not lit and TB.switch_to then TB.switch_to(sw) end
    return hovered, held, lit, true
  end
  if FB.kind(it) then
    -- a plugin or an FX chain to add (TS_CV_FXButtons): lit while the
    -- plugin is on the selected track
    W.tip(ctx, ID .. i, (it.label ~= "" and (it.label .. "\n") or "") .. FB.tip(it), hovered, false)
    if pressed then FB.run(it) end
    return hovered, held, FB.is_on(it), true
  end
  local id = TB.resolve(it.cmd)
  local on = id and reaper.GetToggleCommandStateEx(0, id) == 1
  local name = TB.action_name(id)
  W.tip(ctx, ID .. i,
    (it.label ~= "" and it.label) or name
         or ("Action not found: " .. tostring(it.cmd)),
    hovered, false)
  if pressed and id then reaper.Main_OnCommand(id, 0) end
  return hovered, held, on, id
end

-- How big an icon is drawn on a button bh tall: ChannelView's own fill
-- 85% of it, a PNG beside a label a little less.
local function icon_pad(bh) return math.floor(bh * 0.075 + 0.5) end
local function wide_icon(icon, bh)
  if AI.is(icon) then return bh - icon_pad(bh) * 2 end
  return bh - 6
end

-- The width a button will take: its icon's, or its label's.
local function item_width(ctx, it, bh)
  if it.gap then return math.floor(bh * 0.5 + 0.5) end
  if it.sep then return 7 end
  if TB.style == "both" then
    local w = 16
    if it.icon ~= "" and icon_width(ctx, it.icon, wide_icon(it.icon, bh)) then w = w + wide_icon(it.icon, bh) + 5 end
    w = w + ImGui.CalcTextSize(ctx, text_of(it))
    if has_caret(it) then w = w + 10 end
    return math.max(bh, w)
  end
  if it.icon ~= "" then
    local iw = icon_width(ctx, it.icon, bh)
    if iw then return iw end
  end
  local text = text_of(it)
  return math.max(bh, ImGui.CalcTextSize(ctx, text) + 12 + (has_caret(it) and 10 or 0)), text
end

-- A separator or gap, `vertical` when the bar is a column.
local function draw_sep(ctx, dl, i, it, x, y, bw, bh, vertical)
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, ID .. "sep" .. i, bw, bh)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    st.item_menu, st.open_item = i, true
  end
  if it.gap then
    -- A gap is blank; a faint outline on hover shows where to right-click.
    if ImGui.IsItemHovered(ctx) then
      ImGui.DrawList_AddRect(dl, x, y, x + bw, y + bh, C.COL.panel_border, 2.5, 0, 1.0)
    end
    return
  end
  if vertical then
    local cy = math.floor(y + bh * 0.5) + 0.5
    ImGui.DrawList_AddLine(dl, x + 4, cy, x + bw - 4, cy, C.COL.panel_border, 1.0)
  else
    local cx = math.floor(x + bw * 0.5) + 0.5
    ImGui.DrawList_AddLine(dl, cx, y + 4, cx, y + bh - 4, C.COL.panel_border, 1.0)
  end
end

-- How a button shows its colour: its own (it.cs) or the bar's. Returns
-- underline, icon -- both booleans.
function TB.cstyle_of(it)
  local s = (it and it.cs) or TB.cstyle or "u"
  return s:find("u", 1, true) ~= nil, s:find("i", 1, true) ~= nil
end

-- A button's colour: the colour (or nil), whether it tints the icon and
-- label, and whether it's underlined. A PNG icon can't be tinted: it's
-- underlined instead.
local function tint_of(it, png)
  local col = colour_of(it.color)
  if not col then return nil, false, false end
  local u, i = TB.cstyle_of(it)
  local tint = i and not png
  return col, tint, u or (i and png)
end
-- A colour a step lighter, for hover.
local function lighten(col, t)
  local function ch(v) return math.floor(v + (255 - v) * t + 0.5) end
  return (ch((col >> 24) & 0xff) << 24) | (ch((col >> 16) & 0xff) << 16) | (ch((col >> 8) & 0xff) << 8) | (col & 0xff)
end
local function underline(dl, x, y, bw, bh, col)
  ImGui.DrawList_AddRectFilled(dl, x + 4, y + bh - 2.5, x + bw - 4, y + bh - 0.5, col, 1.0)
end

-- The TCP's look: the icon is the button (or a text button without one).
local function draw_item(ctx, dl, i, it, x, y, bw, bh, dir)
  if it.sep then return draw_sep(ctx, dl, i, it, x, y, bw, bh, false) end
  local hovered, held, on, id = press(ctx, i, it, x, y, bw, bh, dir)

  local state = (held or on) and 3 or (hovered and 2 or 1)
  local drawn, frames = nil, nil
  -- A toggle drawn from an "_off" icon shows its "_on" partner while on,
  -- as REAPER's own toolbars do. That partner is the "on" look, so the
  -- pressed frame and the extra marks below aren't wanted with it.
  local icon, paired = it.icon, false
  if on and icon ~= "" then
    local alt = TB.on_icon(icon)
    if alt and image(ctx, alt) then icon, paired, state = alt, true, (held and 3 or (hovered and 2 or 1)) end
  end
  if AI.is(icon) and AI.get(icon) then
    -- ChannelView's own: drawn in the bar's colours, on the accent when on
    local caret_ = has_caret(it)
    local col, tint, under = tint_of(it, false)
    if on or hovered or held then
      ImGui.DrawList_AddRectFilled(dl, x, y, x + bw, y + bh,
        on and ((tint and col) or C.COL.accent) or C.COL.knob_body_hi, 2.5)
    end
    local ink
    if on then ink = C.COL.icon_on
    elseif hovered or held then ink = tint and lighten(col, 0.35) or C.COL.icon_hot
    else ink = tint and col or C.COL.icon end
    local pad = icon_pad(bh)
    AI.draw(dl, icon, x + pad, y + pad, bh - pad * 2, ink)
    if caret_ then caret(dl, x + bw - 4, y + bh - 4, dir == "up" and "up" or "down", ink) end
    if under then underline(dl, x, y, bw, bh, col) end
    drawn = true
  elseif icon ~= "" then
    -- A single-frame icon has no hover or pressed look of its own, so
    -- the button supplies one behind it.
    local img = image(ctx, icon)
    if img then
      local iw, ih = ImGui.Image_GetSize(img)
      if iw and ih and ih > 0 and iw < ih * 2.5 and (hovered or (on and not paired) or held) then
        ImGui.DrawList_AddRectFilled(dl, x, y, x + bw, y + bh,
          (on or (held and it.menu)) and U.with_alpha(C.COL.accent, 0x99) or C.COL.knob_body_hi, 2.5)
      end
    end
    drawn, frames = draw_icon(ctx, dl, icon, x, y, bh, state)
    -- A three-frame icon whose "pressed" frame looks like its normal one
    -- would leave an "on" toggle unmarked; a thin accent underline is
    -- cheap insurance.
    if drawn and on and not paired and frames == 3 then
      ImGui.DrawList_AddLine(dl, x + 3, y + bh - 1, x + bw - 3, y + bh - 1,
        C.COL.accent, 2.0)
    end
    if drawn and has_caret(it) then
      caret(dl, x + bw - 4, y + bh - 4, dir == "up" and "up" or "down",
        hovered and C.COL.icon_hot or C.COL.icon)
    end
    local col, _, under = tint_of(it, true)
    if drawn and under then underline(dl, x, y, bw, bh, col) end
  end
  if not drawn then
    local text = text_of(it)
    local lit = on or (has_caret(it) and held)
    local col, tint, under = tint_of(it, false)
    local bg = lit and ((tint and col) or C.COL.accent)
               or ((hovered or held) and C.COL.knob_body_hi or C.COL.toggle_off)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + bw, y + bh, bg, 2.5)
    ImGui.DrawList_AddRect(dl, x, y, x + bw, y + bh, C.COL.knob_ring, 2.5, 0, 1.0)
    local tw, th = ImGui.CalcTextSize(ctx, text)
    local room = bw - (has_caret(it) and 10 or 0)
    local ink = lit and C.COL.icon_on or ((it.menu or id) and C.COL.label or C.COL.warn)
    if tint and not lit then ink = (hovered or held) and lighten(col, 0.35) or col end
    ImGui.DrawList_AddText(dl, x + (room - tw) * 0.5, y + (bh - th) * 0.5, ink, text)
    if has_caret(it) then caret(dl, x + bw - 8, y + bh * 0.5, dir == "up" and "up" or "down", ink) end
    if under then underline(dl, x, y, bw, bh, col) end
  end
end

-- A drawer's look: a button with an icon (when it has one) and, when
-- `show_label`, its label beside it; a menu has a caret pointing where
-- its menu opens. Columns use it at full width.
local function draw_wide(ctx, dl, i, it, x, y, bw, bh, show_label, dir, vertical)
  if it.sep then return draw_sep(ctx, dl, i, it, x, y, bw, bh, vertical) end
  local hovered, held, on, id = press(ctx, i, it, x, y, bw, bh, dir)
  local menu_ = has_caret(it)
  local lit = on or (menu_ and held)
  local png = it.icon ~= "" and not AI.is(it.icon)
  local col, tint, under = tint_of(it, png)
  local bg = lit and ((tint and col) or C.COL.accent)
             or ((hovered or held) and C.COL.knob_body_hi or C.COL.toggle_off)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + bw, y + bh, bg, 2.5)
  ImGui.DrawList_AddRect(dl, x, y, x + bw, y + bh, C.COL.knob_ring, 2.5, 0, 1.0)
  local ink = lit and C.COL.icon_on or ((it.menu or id) and C.COL.label or C.COL.warn)
  if tint and not lit then ink = (hovered or held) and lighten(col, 0.35) or col end
  local ih = bh - 6
  local cx = x + 6
  local right = x + bw - (menu_ and 12 or 4)
  local has_icon = false
  if AI.is(it.icon) and AI.get(it.icon) then
    local vh = wide_icon(it.icon, bh)
    local ix = show_label and (x + icon_pad(bh) + 2) or (x + (bw - vh) * 0.5 - (menu_ and 3 or 0))
    if ix + vh <= x + bw - 2 then
      local iink = lit and C.COL.icon_on or ((hovered or held) and C.COL.icon_hot or C.COL.icon)
      if tint and not lit then iink = ink end
      AI.draw(dl, it.icon, ix, y + (bh - vh) * 0.5, vh, iink)
      cx = ix + vh + 5
      has_icon = true
    end
  elseif it.icon ~= "" then
    local icon = it.icon
    if on then
      local alt = TB.on_icon(icon)
      if alt and image(ctx, alt) then icon = alt end
    end
    local iw = icon_width(ctx, icon, ih)
    if iw then
      local ix = show_label and cx or (x + (bw - iw) * 0.5 - (menu_ and 3 or 0))
      if ix + iw <= x + bw - 2 then
        ImGui.DrawList_PushClipRect(dl, x, y, x + bw, y + bh, true)
        draw_icon(ctx, dl, icon, ix, y + 3, ih, (held or on) and 3 or (hovered and 2 or 1))
        ImGui.DrawList_PopClipRect(dl)
        cx = ix + iw + 5
        has_icon = true
      end
    end
  end
  if show_label or not has_icon then
    local text = text_of(it)
    local tw, th = ImGui.CalcTextSize(ctx, text)
    local room = right - cx
    if room > 6 then
      if tw > room then
        -- cut it to the room it has
        local n = #text
        while n > 1 do
          n = n - 1
          local t = text:sub(1, n) .. "."
          tw = ImGui.CalcTextSize(ctx, t)
          if tw <= room then text = t break end
        end
      end
      local tx = (show_label and has_icon) and cx or (show_label and x + 8 or x + (bw - tw) * 0.5 - (menu_ and 3 or 0))
      ImGui.DrawList_AddText(dl, tx, y + (bh - th) * 0.5, ink, text)
    end
  end
  if menu_ then caret(dl, x + bw - 7, y + bh * 0.5, dir, ink) end
  if under then underline(dl, x, y, bw, bh, col) end
end

-- Pure: where each button of a row-wise bar goes. `ws` are the buttons'
-- widths in order; they fill rows from `left` to `right`, `gap` apart, up
-- to `rows` rows, and each row is then moved across for `halign` ("c",
-- "r"; anything else stays left). Returns pos[i] = { row, x } (false for
-- a button that didn't fit) and the number of rows used.
function TB.place_rows(ws, left, right, gap, rows, halign)
  local pos, members = {}, {}
  local row, cx, used = 0, left, 0
  for i, bw in ipairs(ws) do
    if cx + bw > right and cx > left then row, cx = row + 1, left end
    if row >= rows then
      pos[i] = false
    else
      pos[i] = { row = row, x = cx, w = bw }
      members[row] = members[row] or {}
      table.insert(members[row], i)
      used = row + 1
      cx = cx + bw + gap
    end
  end
  if halign == "c" or halign == "r" then
    for _, idx in pairs(members) do
      local last = pos[idx[#idx]]
      local spare = (right - left) - (last.x + last.w - left)
      local dx = (halign == "r") and spare or math.floor(spare * 0.5)
      if dx > 0 then for _, i in ipairs(idx) do pos[i].x = pos[i].x + dx end end
    end
  end
  return pos, used
end

-- Pure: the top of a block `used_h` tall in a space at y, h tall, for
-- `valign` ("t", "c", "b"); nil for the usual place.
function TB.place_v(y, h, used_h, valign, pad)
  pad = pad or 2
  if valign == "t" then return y + pad end
  if valign == "c" then return y + math.max(pad, (h - used_h) * 0.5) end
  if valign == "b" then return y + math.max(pad, h - used_h - pad) end
  return nil
end

-- How many rows a horizontal bar w wide needs for every button.
function TB.rows_needed(ctx, w, bh)
  bh = bh or TB.btn
  local cx, rows = 4, 1
  for _, it in ipairs(TB.items) do
    local bw = item_width(ctx, it, bh)
    if cx + bw > w - 4 and cx > 4 then rows, cx = rows + 1, 4 end
    cx = cx + bw + C.TB_GAP
  end
  return rows
end

-- Draws the toolbar into the box x, y, w, h and handles its own menus.
-- Returns:
--   menu      true when the settings button was clicked
--   overflow  the items that didn't fit, for the settings menu to list
-- `no_menu` leaves out the settings button: only the top toolbar has it.
-- `dir` is where a menu button's menu opens ("down" unless said).
function TB.draw(ctx, x, y, w, h, no_menu, dir)
  TB.sync()
  loads_left = 8
  TB.poll()
  dir = dir or "down"
  local dl = ImGui.GetWindowDrawList(ctx)
  local bh = TB.btn
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

  local cx = x + 4
  local right = mx - 6
  if #TB.items == 0 and not pick then
    local hint = "Right-click to add actions"
    local tw, th = ImGui.CalcTextSize(ctx, hint)
    if tw < right - cx then
      ImGui.DrawList_AddText(dl, cx + 2, y + (h - th) * 0.5, C.COL.header_dim, hint)
    end
  end
  local ws = {}
  for i, it in ipairs(TB.items) do ws[i] = item_width(ctx, it, bh) end
  local pos, used = TB.place_rows(ws, x + 4, right, C.TB_GAP, rows, TB.halign)
  if used > 0 then
    top = TB.place_v(y, h, used * bh + (used - 1) * C.TB_GAP, TB.valign) or top
  end
  for i, it in ipairs(TB.items) do
    local p = pos[i]
    if not p then
      if not it.sep then res.overflow[#res.overflow + 1] = it end
    else
      local by = top + p.row * (bh + C.TB_GAP)
      if TB.style == "both" then
        draw_wide(ctx, dl, i, it, p.x, by, p.w, bh, true, dir, false)
      else
        draw_item(ctx, dl, i, it, p.x, by, p.w, bh, dir)
      end
      cx = p.x + p.w + C.TB_GAP
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

-- The bar as a column (a drawer down one side): one button a row, full
-- width, icon and label while there's room for a label, icons only once
-- it's narrower. `dir` is where a menu opens ("right" from a column on
-- the left, "left" from one on the right). What doesn't fit is left off.
function TB.draw_v(ctx, x, y, w, h, dir)
  TB.sync()
  loads_left = 8
  TB.poll()
  local dl = ImGui.GetWindowDrawList(ctx)
  local bh = TB.btn
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, ID .. "bg", math.max(1, w), math.max(1, h))
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then st.open_bg = true end

  local bw = w - 8
  local show_label = bw >= bh + 34
  local cy = y + 4
  if #TB.items > 0 and TB.valign ~= "-" then
    -- the column's height, as far as it fits
    local total = 0
    for _, it in ipairs(TB.items) do
      local ih = it.gap and math.floor(bh * 0.5) or (it.sep and 7 or bh)
      if total + ih > h - 6 then break end
      total = total + ih + C.TB_GAP
    end
    cy = TB.place_v(y, h, total - C.TB_GAP, TB.valign, 4) or cy
  end
  if #TB.items == 0 and not pick then
    local hint = show_label and "Right-click\nto add actions" or "+"
    local _, th = ImGui.CalcTextSize(ctx, hint)
    ImGui.DrawList_AddText(dl, x + 6, cy + 2, C.COL.header_dim, hint)
    cy = cy + th + 4
  end
  for i, it in ipairs(TB.items) do
    local ih = it.gap and math.floor(bh * 0.5) or (it.sep and 7 or bh)
    if cy + ih > y + h - 2 then break end
    draw_wide(ctx, dl, i, it, x + 4, cy, bw, ih, show_label, dir, true)
    cy = cy + ih + C.TB_GAP
  end
  if pick and show_label and cy + 16 < y + h then
    ImGui.DrawList_AddText(dl, x + 6, cy + 2, C.COL.accent, "Pick an action\u{2026}")
  end
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.Dummy(ctx, 0, 0)
end

-- Runs a stored item, for the settings menu's overflow list.
function TB.run(it)
  local sw = TB.switch_of(it)
  if sw then
    if sw ~= "menu" and TB.switch_to then TB.switch_to(sw) end
    return
  end
  if FB.kind(it) then FB.run(it) return end
  local id = it and TB.resolve(it.cmd)
  if id then reaper.Main_OnCommand(id, 0) end
end

function TB.label_of(it)
  if it.menu or TB.switch_of(it) or FB.kind(it) then return text_of(it) end
  local id = TB.resolve(it.cmd)
  return (it.label ~= "" and it.label) or TB.action_name(id) or tostring(it.cmd)
end

-- A list of items as menu entries, menus as submenus to any depth: what a
-- menu button opens, and the TCP's overflow list. `path` keeps ids apart.
-- A menu row's colour and icon, drawn into the room its label's leading
-- spaces keep, from the row's own rectangle (the last item): the colour
-- a strip down the row's left edge (where a bar button has its
-- underline), the icon after it, in the colour when it colours its icon.
local STRIP = 5
local function row_icon(ctx, it, ih, strip)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x0, y0 = ImGui.GetItemRectMin(ctx)
  local _, y1 = ImGui.GetItemRectMax(ctx)
  local col, tint, under = tint_of(it, it.icon ~= "" and not AI.is(it.icon))
  if col and (under or not (it.icon and it.icon ~= "")) then
    ImGui.DrawList_AddRectFilled(dl, x0, y0 + 2, x0 + 3, y1 - 2, col, 1.0)
  end
  if ih <= 0 or not it.icon or it.icon == "" then return end
  local x = x0 + 2 + (strip and STRIP or 0)
  local y = y0 + ((y1 - y0) - ih) * 0.5
  if AI.is(it.icon) then
    AI.draw(dl, it.icon, x, y, ih, tint and col or C.COL.icon)
  else
    draw_icon(ctx, dl, it.icon, x, y, ih, 1)
  end
end

function TB.menu_entries(ctx, items, path)
  path = path or "m"
  if #items == 0 then ImGui.TextDisabled(ctx, "(empty)") end
  -- with an icon on any row, every label leaves room for one; with a
  -- colour on any, room for its strip
  local pad, ih, strip = "", 0, false
  for _, it in ipairs(items) do
    if not it.sep and it.icon and it.icon ~= "" then ih = math.floor(ImGui.GetTextLineHeight(ctx) + 2) end
    if not it.sep and colour_of(it.color) then strip = true end
  end
  if ih > 0 or strip then
    local sw = ImGui.CalcTextSize(ctx, " ")
    local room = (ih > 0 and (ih + 6) or 0) + (strip and STRIP + 2 or 0)
    pad = (" "):rep(math.ceil(room / ((sw and sw > 0) and sw or 4)))
  end
  local marks = ih > 0 or strip
  for k, it in ipairs(items) do
    local key = "##" .. ID .. path .. "." .. k
    if it.menu then
      local open = ImGui.BeginMenu(ctx, pad .. text_of(it) .. key)
      if open then
        TB.menu_entries(ctx, it.items or {}, path .. "." .. k)
        ImGui.EndMenu(ctx)
      end
      -- (once its submenu is done, ImGui hands back the row itself)
      if marks then row_icon(ctx, it, ih, strip) end
    elseif it.gap then
      ImGui.Dummy(ctx, 1, 4)
    elseif it.sep then
      ImGui.Separator(ctx)
    elseif TB.switch_of(it) == "menu" then
      if ImGui.BeginMenu(ctx, pad .. "Switch toolbar" .. key) then
        TB.switch_entries(ctx)
        ImGui.EndMenu(ctx)
      end
      if marks then row_icon(ctx, it, ih, strip) end
    elseif TB.switch_of(it) then
      local sw = TB.switch_of(it)
      if ImGui.MenuItem(ctx, pad .. text_of(it) .. key, nil, sw == TB.bar_id) and sw ~= TB.bar_id and TB.switch_to then
        TB.switch_to(sw)
      end
      if marks then row_icon(ctx, it, ih, strip) end
    elseif FB.kind(it) then
      if ImGui.MenuItem(ctx, pad .. text_of(it) .. key, nil, FB.is_on(it)) then FB.run(it) end
      if marks then row_icon(ctx, it, ih, strip) end
    else
      local id = TB.resolve(it.cmd)
      local on = id and reaper.GetToggleCommandStateEx(0, id) == 1
      local label = (it.label ~= "" and it.label) or TB.action_name(id) or ("not found: " .. tostring(it.cmd))
      if ImGui.MenuItem(ctx, pad .. label .. key, nil, on, id ~= nil) and id then
        reaper.Main_OnCommand(id, 0)
      end
      if marks then row_icon(ctx, it, ih, strip) end
    end
  end
end

-- The menu of bars a switch opens: every bar, the one showing ticked;
-- picking one swaps it in here. TB.switch_list (from TS_CV_Drawers) gives
-- { { id, name, where } }.
function TB.switch_entries(ctx)
  local list = TB.switch_list and TB.switch_list() or {}
  if #list == 0 then ImGui.TextDisabled(ctx, "No other bars") end
  for _, e in ipairs(list) do
    local cur = e.id == TB.bar_id
    if ImGui.MenuItem(ctx, e.name .. "##" .. ID .. "sw" .. e.id, e.where, cur) and not cur and TB.switch_to then
      TB.switch_to(e.id)
    end
  end
end

-- Every button given the ChannelView icon made for its action (menus'
-- too). Returns how many changed.
function TB.use_cv_icons(items)
  local n = 0
  for _, it in ipairs(items or TB.items) do
    if it.menu then n = n + TB.use_cv_icons(it.items)
    elseif not it.sep then
      local m = TB.match_icon(it.cmd)
      if m and it.icon ~= m then it.icon = m; n = n + 1 end
    end
  end
  return n
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

local function new_menu() return { menu = true, icon = "", label = "Menu", items = {} } end
TB.new_menu = new_menu

-- The label box, in a right-click menu.
local function label_box(ctx, it, hint)
  ImGui.TextDisabled(ctx, hint)
  ImGui.SetNextItemWidth(ctx, 150)
  local _, v = ImGui.InputText(ctx, "##" .. ID .. "label", st.label_buf)
  local enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  st.label_buf = v
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Set") or enter then
    it.label = clean(st.label_buf); TB.save()
    ImGui.CloseCurrentPopup(ctx)
  end
end

-- A row of colour swatches for a button, "no colour" first; a click sets
-- it.
function TB.colour_row(ctx, it, id)
  local dl = ImGui.GetWindowDrawList(ctx)
  do
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    if ImGui.InvisibleButton(ctx, "##" .. id .. "none", 20, 20) and colour_of(it.color) then
      it.color = nil; TB.save()
    end
    local hov = ImGui.IsItemHovered(ctx)
    local ink = hov and C.COL.icon_hot or C.COL.icon
    ImGui.DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x0 + 19.5, y0 + 19.5, ink, 2, 0, 1.0)
    ImGui.DrawList_AddLine(dl, x0 + 4, y0 + 16, x0 + 16, y0 + 4, ink, 1.5)
    if not colour_of(it.color) then
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x0 + 22, y0 + 22, C.COL.label, 2, 0, 1.5)
    end
    if hov then ImGui.SetTooltip(ctx, "No colour") end
  end
  for k, hex in ipairs(TB.COLOURS) do
    ImGui.SameLine(ctx, 0, 4)
    if ImGui.ColorButton(ctx, "##" .. id .. k, colour_of(hex), ImGui.ColorEditFlags_NoTooltip, 20, 20) then
      it.color = hex
      TB.save()
    end
    if it.color == hex then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.label, 2, 0, 1.5)
    end
  end
  -- how this button shows it: as the bar does, unless ticked otherwise
  if colour_of(it.color) then
    local u, i = TB.cstyle_of(it)
    local cu, nu = ImGui.Checkbox(ctx, "Underline##" .. id .. "csu", u)
    ImGui.SameLine(ctx, 0, 12)
    local ci, ni = ImGui.Checkbox(ctx, "Colour the icon##" .. id .. "csi", i)
    if cu or ci then
      local v = (nu and "u" or "") .. (ni and "i" or "")
      -- the same as the bar: it follows the bar again
      if v == (TB.cstyle or "u") then it.cs = nil else it.cs = v end
      TB.save()
    end
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextDisabled(ctx, it.cs and "this button's own" or "as the bar")
  end
end

-- What a switch can be: the menu of bars, or one bar. `pick(target)`
-- gets nil for the menu, else the bar's id; `cur` ticks the current one.
function TB.switch_targets(ctx, pick, cur)
  if ImGui.MenuItem(ctx, "A menu of every bar##" .. ID .. "swm", nil, cur == "menu") then pick(nil) end
  ImGui.Separator(ctx)
  local list = TB.switch_list and TB.switch_list() or {}
  if #list == 0 then ImGui.TextDisabled(ctx, "No other bars yet") end
  for _, e in ipairs(list) do
    if ImGui.MenuItem(ctx, e.name .. "##" .. ID .. "swt" .. e.id, e.where, cur == e.id) then pick(e.id) end
  end
end

local function item_menu(ctx)
  if st.open_item then ImGui.OpenPopup(ctx, ID .. "_item"); st.open_item = false end
  if not ImGui.BeginPopup(ctx, ID .. "_item") then return end
  local i  = st.item_menu
  local it = i and TB.items[i]
  if not it then ImGui.EndPopup(ctx) return end

  local sw = TB.switch_of(it)
  if it.menu then
    ImGui.TextDisabled(ctx, text_of(it) .. " (menu)")
  elseif sw then
    ImGui.TextDisabled(ctx, sw == "menu" and "Toolbar switch: a menu of bars" or ("Toolbar switch: " .. text_of(it)))
  elseif it.sep then
    ImGui.TextDisabled(ctx, it.gap and "Gap" or "Separator")
  elseif FB.kind(it) then
    local fk = FB.kind(it)
    ImGui.TextDisabled(ctx, (fk == "fx" and "Adds " or "Adds the FX chain ") .. text_of(it))
  else
    ImGui.TextDisabled(ctx, U.truncate(TB.action_name(TB.resolve(it.cmd))
                                       or ("not found: " .. it.cmd), 40))
  end
  ImGui.Separator(ctx)

  if it.menu then
    if ImGui.MenuItem(ctx, "Add action to it\u{2026}") then TB.pick_into(it.items, nil) end
    if ImGui.MenuItem(ctx, "Add a menu to it") then
      it.items[#it.items + 1] = new_menu(); TB.save()
    end
    if ImGui.MenuItem(ctx, "Add separator to it") then
      it.items[#it.items + 1] = { sep = true }; TB.save()
    end
    if TB.organise and ImGui.MenuItem(ctx, "Organise\u{2026}") then TB.organise(it) end
    ImGui.Separator(ctx)
  end
  if not it.sep then
    if sw then
      if ImGui.BeginMenu(ctx, "Switches to") then
        TB.switch_targets(ctx, function(target) it.cmd = TB.switch_cmd(target); TB.save() end, sw)
        ImGui.EndMenu(ctx)
      end
    elseif not it.menu and ImGui.MenuItem(ctx, "Change action\u{2026}") then TB.pick_start(nil, i) end
    if ImGui.MenuItem(ctx, "Icon\u{2026}") then
      st.icons_for, st.open_icons, st.icons_where = it, true, nil
    end
    if ImGui.MenuItem(ctx, "No icon", nil, false, it.icon ~= "") then
      it.icon = ""; TB.save()
    end
    if ImGui.BeginMenu(ctx, "Colour") then
      TB.colour_row(ctx, it, ID .. "col")
      ImGui.EndMenu(ctx)
    end
    ImGui.Separator(ctx)
    label_box(ctx, it, (it.menu and "Label") or (sw and "Label (blank: the bar's name)") or "Label (blank: the action's name)")
    ImGui.Separator(ctx)
  end
  if ImGui.MenuItem(ctx, "Move left", nil, false, i > 1) then move(i, -1) end
  if ImGui.MenuItem(ctx, "Move right", nil, false, i < #TB.items) then move(i, 1) end
  if ImGui.MenuItem(ctx, "Insert action before\u{2026}") then TB.pick_start(i) end
  if ImGui.BeginMenu(ctx, "Insert toolbar switch before") then
    TB.switch_targets(ctx, function(target)
      table.insert(TB.items, i, { cmd = TB.switch_cmd(target), icon = "", label = "" }); TB.save()
    end, nil)
    ImGui.EndMenu(ctx)
  end
  if ImGui.MenuItem(ctx, "Insert menu before") then
    table.insert(TB.items, i, new_menu()); TB.save()
  end
  if ImGui.MenuItem(ctx, "Insert separator before") then
    table.insert(TB.items, i, { sep = true }); TB.save()
  end
  if ImGui.MenuItem(ctx, "Insert gap before") then
    table.insert(TB.items, i, { sep = true, gap = true }); TB.save()
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, it.menu and "Remove the menu and what's in it" or "Remove") then
    table.remove(TB.items, i); TB.save()
  end
  ImGui.EndPopup(ctx)
end

local function bg_menu(ctx)
  if st.open_bg then ImGui.OpenPopup(ctx, ID .. "_bg"); st.open_bg = false end
  if not ImGui.BeginPopup(ctx, ID .. "_bg") then return end
  if TB.extra_bg then TB.extra_bg(ctx, "head") end
  if ImGui.MenuItem(ctx, "Add action\u{2026}") then TB.pick_start(nil) end
  if ImGui.MenuItem(ctx, "Add menu") then
    TB.items[#TB.items + 1] = new_menu(); TB.save()
  end
  if ImGui.MenuItem(ctx, "Add separator") then
    TB.items[#TB.items + 1] = { sep = true }; TB.save()
  end
  if ImGui.MenuItem(ctx, "Add gap") then
    TB.items[#TB.items + 1] = { sep = true, gap = true }; TB.save()
  end
  if ImGui.BeginMenu(ctx, "Add toolbar switch") then
    TB.switch_targets(ctx, function(target)
      TB.items[#TB.items + 1] = { cmd = TB.switch_cmd(target), icon = "", label = "" }; TB.save()
    end, nil)
    ImGui.EndMenu(ctx)
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Use ChannelView icons") then
    if TB.use_cv_icons() > 0 then TB.save() end
  end
  if ImGui.BeginMenu(ctx, "Copy a REAPER toolbar") then
    local list = TB.reaper_toolbars()
    if #list == 0 then ImGui.TextDisabled(ctx, "No customised toolbars found") end
    for k, name in ipairs(list) do
      if ImGui.MenuItem(ctx, name .. "##" .. ID .. "imp" .. k) then TB.import(name) end
    end
    ImGui.EndMenu(ctx)
  end
  if #DEFAULTS > 0 and ImGui.MenuItem(ctx, "Reset to the default buttons") then
    TB.items = TB.parse(""); TB.save()
  end
  if TB.organise then
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Organise actions\u{2026}") then TB.organise() end
  end
  if TB.extra_bg then TB.extra_bg(ctx, "tail") end
  ImGui.EndPopup(ctx)
end

-- A menu button's menu, opened beside its button.
local function pop_menu(ctx)
  if st.open_pop then ImGui.OpenPopup(ctx, ID .. POP); st.open_pop = false end
  if st.pop_at then
    ImGui.SetNextWindowPos(ctx, st.pop_at[1], st.pop_at[2], ImGui.Cond_Appearing, st.pop_at[3], st.pop_at[4])
  end
  if not ImGui.BeginPopup(ctx, ID .. POP) then return end
  local it = st.pop_item
  if it and TB.switch_of(it) == "menu" then TB.switch_entries(ctx)
  elseif it then TB.menu_entries(ctx, it.items or {}, "p") end
  ImGui.EndPopup(ctx)
end

-- The icon picker opened for any item of this bar (the organiser's too).
-- `where` names the window asking (draw_menus is handed the same), so
-- the picker opens there and not in another window showing this bar.
function TB.open_icons(it, where)
  st.icons_for, st.open_icons, st.icons_where = it, true, where
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

-- Copies a PNG from anywhere into Data/toolbar_icons and returns its file
-- name there (what a button stores), or nil and why. A file already in
-- the folder is used where it is; one of the same name but different
-- content gets " (2)", " (3)" ... rather than replacing it.
function TB.import_png(path, dir)
  dir = dir or TB.icon_dir()
  local fh = io.open(path or "", "rb")
  if not fh then return nil, "Couldn't open that file." end
  local data = fh:read("a"); fh:close()
  if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil, "That isn't a PNG file." end
  local name = (path:match("([^/\\]+)$") or "icon.png"):gsub("[;|]", "")
  if not name:lower():match("%.png$") then name = name .. ".png" end
  local function same(p)
    local h = io.open(p, "rb")
    if not h then return nil end
    local d = h:read("a"); h:close()
    return d == data
  end
  local stem = name:sub(1, -5)
  local n = 1
  while true do
    local cand = (n == 1) and name or (stem .. " (" .. n .. ").png")
    local s = same(dir .. sep .. cand)
    if s == true then return cand end          -- already there
    if s == nil then name = cand break end      -- free
    n = n + 1
  end
  if reaper and reaper.RecursiveCreateDirectory then reaper.RecursiveCreateDirectory(dir, 0) end
  local out = io.open(dir .. sep .. name, "wb")
  if not out then return nil, "Couldn't write to " .. dir .. "." end
  out:write(data); out:close()
  return name
end

-- The PNG grid: every file in Data/toolbar_icons, filtered.
local function png_grid(ctx, it, flt)
  local list = st.icon_list or {}
  if ImGui.Button(ctx, "Add a PNG\u{2026}##" .. ID .. "addpng") then
    local ok, path = reaper.GetUserFileNameForRead("", "Choose an icon (PNG)", "png")
    if ok and path and path ~= "" then
      local name, err = TB.import_png(path)
      if name then
        images[name] = nil
        it.icon = name; TB.save()
        st.icon_list = list_icons()
        ImGui.CloseCurrentPopup(ctx)
      else
        reaper.MB(err, "ChannelView", 0)
      end
    end
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Copies it into Data/toolbar_icons and uses it here")
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, U.truncate(TB.icon_dir(), 60))
  if #list == 0 then
    ImGui.TextDisabled(ctx, "No PNG files in that folder.")
    return nil
  end
  local first
  local cols = 12
  if ImGui.BeginChild(ctx, ID .. "iconsgrid", cols * (ICON_CELL + 4) + 12, 300) then
    local dl = ImGui.GetWindowDrawList(ctx)
    local n = 0
    for _, f in ipairs(list) do
      if flt == "" or f:lower():find(flt, 1, true) then
        first = first or f
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
  return first
end

-- ChannelView's own icons, by family; the one made for this button's
-- action first.
local function cv_grid(ctx, it, flt)
  local first
  local cols = 12
  local fams = AI.families()
  if #fams == 0 then
    ImGui.TextDisabled(ctx, "ChannelView's icon file (" .. AI.FILE .. ") wasn't found.")
    return nil
  end
  local match = TB.match_icon(it.cmd)
  if ImGui.BeginChild(ctx, ID .. "cvgrid", cols * (ICON_CELL + 4) + 12, 300) then
    local dl = ImGui.GetWindowDrawList(ctx)
    local shown = 0
    local function cell(ic, n, tag)
      local key = AI.PREFIX .. ic.key
      first = first or key
      if n % cols ~= 0 then ImGui.SameLine(ctx, 0, 4) end
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.InvisibleButton(ctx, (tag or "cv") .. ic.key .. "_" .. n, ICON_CELL, ICON_CELL) then
        it.icon = key; TB.save()
        ImGui.CloseCurrentPopup(ctx)
      end
      local hov = ImGui.IsItemHovered(ctx)
      local cur = key == it.icon
      if hov or cur then
        ImGui.DrawList_AddRectFilled(dl, x, y, x + ICON_CELL, y + ICON_CELL,
          cur and C.COL.accent or C.COL.knob_body_hi, 2.5)
      end
      if ImGui.IsItemVisible(ctx) then
        AI.draw(dl, key, x + 5, y + 5, ICON_CELL - 10,
          cur and C.COL.icon_on or (hov and C.COL.icon_hot or C.COL.icon))
      end
      if hov then ImGui.SetTooltip(ctx, ic.name) end
    end
    if match and flt == "" then
      ImGui.SeparatorText(ctx, "Made for this action")
      cell(AI.get(match), 0, "cvm")
    end
    for _, fam in ipairs(fams) do
      local n = 0
      local famhit = flt ~= "" and fam.name:lower():find(flt, 1, true)
      for _, ic in ipairs(fam.icons) do
        if flt == "" or famhit or ic.name:lower():find(flt, 1, true) or ic.key:find(flt, 1, true) then
          if n == 0 then ImGui.SeparatorText(ctx, fam.name) end
          cell(ic, n)
          n = n + 1
        end
      end
      shown = shown + n
    end
    if shown == 0 then ImGui.TextDisabled(ctx, "Nothing matches.") end
    ImGui.EndChild(ctx)
  end
  return first
end

local function icon_picker(ctx, where)
  if st.open_icons and st.icons_where == where then
    st.open_icons = false
    st.icon_list = list_icons()
    -- a PNG button opens on the PNGs, anything else on ChannelView's
    st.icon_tab = (st.icons_for and st.icons_for.icon ~= "" and not AI.is(st.icons_for.icon)) and "png" or "cv"
    st.icon_tab_set = true
    ImGui.OpenPopup(ctx, ID .. "_icons")
  end
  if not ImGui.BeginPopup(ctx, ID .. "_icons") then return end
  local it = st.icons_for
  if not it or it.sep then ImGui.EndPopup(ctx) return end

  loads_left = 24
  ImGui.SetNextItemWidth(ctx, 200)
  -- Enter takes the first icon the filter shows
  local _, v = ImGui.InputTextWithHint(ctx, "##" .. ID .. "iconflt", "filter\u{2026}", st.icon_filter)
  local icon_enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  st.icon_filter = v
  local flt = st.icon_filter:lower()
  local first
  if ImGui.BeginTabBar(ctx, ID .. "icontabs") then
    local set = st.icon_tab_set
    st.icon_tab_set = false
    if ImGui.BeginTabItem(ctx, "ChannelView##" .. ID, nil,
        (set and st.icon_tab == "cv") and ImGui.TabItemFlags_SetSelected or 0) then
      st.icon_tab = "cv"
      first = cv_grid(ctx, it, flt)
      ImGui.EndTabItem(ctx)
    end
    if ImGui.BeginTabItem(ctx, "Your PNGs##" .. ID, nil,
        (set and st.icon_tab == "png") and ImGui.TabItemFlags_SetSelected or 0) then
      st.icon_tab = "png"
      first = png_grid(ctx, it, flt)
      ImGui.EndTabItem(ctx)
    end
    ImGui.EndTabBar(ctx)
  end
  if icon_enter and first then
    it.icon = first; TB.save()
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.EndPopup(ctx)
end

-- Draws whichever toolbar popup is open. Call once a frame from the
-- window TB.draw was called in, outside any child.
function TB.draw_menus(ctx, where)
  if where == nil then
    item_menu(ctx)
    bg_menu(ctx)
    pop_menu(ctx)
  end
  icon_picker(ctx, where)
end

return TB
end   -- make

local TB = make("toolbar", "tb", TOP_DEFAULTS)
TB.make = make
function TB.attach(imgui) ImGui = imgui; AI.attach(imgui) end
return TB
