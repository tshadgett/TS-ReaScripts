-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Drawers.lua -- every action bar ChannelView has, and where each is.

  An action bar is a TS_CV_Toolbar instance (menus, REAPER's toolbar
  icons) with a PLACE. One list, one place per bar:

    top, left, right, bottom   a drawer along that side of ChannelView's
                               main area. Top drawers sit under the
                               header, above the MIDI learn bar (MIDI
                               learn is the passing one); left and right
                               ones are columns beside the panels (drag
                               the inner edge); bottom ones run along the
                               window's foot, under the track names.
                               Several can share a side.
    window                     its own window, shown by the toolbars
                               script (TS_ChannelView_Toolbars.lua):
                               floating or in a REAPER docker.
    tcp1, tcp2                 the TCP's toolbar beside the ruler, and the
                               one by the transport. One bar each.
    web                        the web companion's Actions bar. One bar.
    none                       kept, shown nowhere.

  Moving a bar onto a place that holds one bar (tcp1, tcp2, web) swaps
  the two. Drawers, windows: open or closed.

  The list is ChannelView's, not a project's: ExtState TS_ChannelView/bars,
  one line, bars split by ";", fields by "|":
      id|place|open|width|style|key|dock|name
  `key` is where its buttons are kept (TS_CV_Toolbar's line, in the TCP's
  section) -- except the bar in the web place, whose buttons ARE the web
  page's list (TS_CV_WEB/macros, JSON): moving a bar there writes its
  buttons into that list, and moving it away writes them back under its
  key. "bars#rev" moves with every save, so ChannelView, the TCP and the
  toolbars script follow each other's changes.

  Also reads the older drawers-only list (TS_ChannelView/drawers, the first
  six fields): with no bars line, the first load builds one from it plus
  the TCP's two toolbars and the web bar, and leaves the old line.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local TB = require("TS_CV_Toolbar")

local DR = {}
local ImGui
function DR.attach(imgui) ImGui = imgui end

DR.KEY, DR.OLD_KEY = "bars", "drawers"
DR.REV = "bars#rev"
DR.SIDES = { "top", "left", "right", "bottom" }
DR.PLACES = { "top", "left", "right", "bottom", "window", "tcp1", "tcp2", "web", "none" }
DR.SIDE_NAME = { top = "Top", left = "Left", right = "Right", bottom = "Bottom",
                 window = "Own window", tcp1 = "TCP \u{00B7} by the ruler",
                 tcp2 = "TCP \u{00B7} by the transport", web = "Web companion", none = "Nowhere" }
DR.SINGLE = { tcp1 = true, tcp2 = true, web = true }
DR.SINGLE_NAME = { tcp1 = "TCP toolbar", tcp2 = "TCP transport toolbar", web = "Web actions" }
DR.DRAWER = { top = true, left = true, right = true, bottom = true }
DR.W_DEF, DR.W_MIN, DR.W_MAX = 128, 34, 360
-- button sizes (height, px): a bar's Size
DR.SIZES = { { "Small", 20 }, { "Normal", 24 }, { "Large", 30 }, { "Extra large", 36 } }
DR.SIZE_DEF, DR.SIZE_MIN, DR.SIZE_MAX = 24, 16, 48
-- where a bar's buttons sit: across (l, c, r) and up and down (t, c, b);
-- "-" is the bar's usual place (left; a row centred, a column at the top)
DR.HALIGN = { { "Left", "l" }, { "Centre", "c" }, { "Right", "r" } }
DR.VALIGN = { { "Top", "t" }, { "Centre", "c" }, { "Bottom", "b" } }
-- The align field also carries how button colours show: a third
-- character "i" (coloured icons); none means underlines.
local function align_of(v)
  local h, a, c = tostring(v or ""):match("^([lcr%-])([tcb%-])([ui]?)$")
  if not h then return "-", "-", "u" end
  return h, a, (c == "i") and "i" or "u"
end
local function align_field(d)
  return (d.halign or "-") .. (d.valign or "-") .. ((d.cstyle == "i") and "i" or "")
end
DR.align_of = align_of
local function size_of(v)
  return math.max(DR.SIZE_MIN, math.min(DR.SIZE_MAX, math.floor(tonumber(v) or DR.SIZE_DEF)))
end
DR.WEB_NS, DR.WEB_KEY = "TS_CV_WEB", "macros"
DR.HOST_FILE = "TS_ChannelView_Toolbars.lua"
DR.list = {}

-- Set by whoever hosts the Organise actions window: opens it, on a bar
-- (and an item in it) when given.
DR.organise = nil

local function clean(s) return ((s or ""):gsub("[;|]", "")) end


-- ---------------------------------------------------------------------
-- pure: the stored list
-- ---------------------------------------------------------------------

local VALID = {}
for _, p in ipairs(DR.PLACES) do VALID[p] = true end

function DR.serialize(list)
  if #list == 0 then return "none" end
  local out = {}
  for _, d in ipairs(list) do
    out[#out + 1] = table.concat({ d.id, d.side, d.open and "1" or "0",
      tostring(math.floor(d.width or DR.W_DEF)), d.style or "both", clean(d.key or ""),
      tostring(math.floor(d.dock or 0)), tostring(size_of(d.size)),
      align_field(d), clean(d.name) }, "|")
  end
  return table.concat(out, ";")
end

-- Every form: id|place|open|width|style|key|dock|size|align|name, the
-- same without align, without size too, and the older drawers-only
-- id|side|open|width|style|name.
function DR.parse(s)
  local out = {}
  if not s or s == "" or s == "none" then return out end
  for part in (s .. ";"):gmatch("([^;]*);") do
    local id, side, open, width, style, key, dock, size, align, name =
      part:match("^(%d+)|(%w+)|([01])|(%d+)|(%a+)|([^|]*)|(%-?%d+)|(%d+)|([lcr%-][tcb%-][ui]?)|(.*)$")
    if not id then
      id, side, open, width, style, key, dock, size, name =
        part:match("^(%d+)|(%w+)|([01])|(%d+)|(%a+)|([^|]*)|(%-?%d+)|(%d+)|(.*)$")
      align = nil
    end
    if not id then
      id, side, open, width, style, key, dock, name =
        part:match("^(%d+)|(%w+)|([01])|(%d+)|(%a+)|([^|]*)|(%-?%d+)|(.*)$")
      size = nil
    end
    if not id then
      id, side, open, width, style, name = part:match("^(%d+)|(%w+)|([01])|(%d+)|(%a+)|(.*)$")
      key, dock = nil, "0"
    end
    if id then
      out[#out + 1] = { id = tonumber(id), side = VALID[side] and side or "top", open = open == "1",
                        width = math.max(DR.W_MIN, math.min(DR.W_MAX, tonumber(width) or DR.W_DEF)),
                        style = (style == "icons") and "icons" or "both",
                        key = (key and key ~= "") and key or ("drawer_" .. id),
                        dock = tonumber(dock) or 0, size = size_of(size), name = name }
      local e = out[#out]
      e.halign, e.valign, e.cstyle = align_of(align)
    end
  end
  return out
end

-- The list from the older drawers-only line, plus the bars that line
-- doesn't hold: the TCP's two toolbars and the web's.
function DR.migrate(old_line)
  local list = DR.parse(old_line)
  local id = 0
  for _, d in ipairs(list) do id = math.max(id, d.id) end
  local function add(side, key, name)
    id = id + 1
    list[#list + 1] = { id = id, side = side, open = true, width = DR.W_DEF, style = "icons",
                        key = key, dock = 0, size = DR.SIZE_DEF, name = name }
  end
  add("tcp1", "toolbar", "TCP toolbar")
  add("tcp2", "toolbar2", "TCP transport toolbar")
  add("web", "web_actions", "Web actions")
  list[#list].style = "both"
  return list
end

-- Moves bar d to `place`, in a list: a single place's bar swaps with it.
-- Pure (the bars' buttons are moved by DR.set_place). Returns the bar
-- that swapped, if any.
function DR.place_in(list, d, place)
  if not VALID[place] or d.side == place then return nil end
  local other
  if DR.SINGLE[place] then
    for _, e in ipairs(list) do
      if e ~= d and e.side == place then other = e break end
    end
  end
  if other then other.side = d.side end
  d.side = place
  if DR.DRAWER[place] or place == "window" then d.open = true end
  return other
end

-- ---------------------------------------------------------------------
-- pure: JSON, as much as the web's list needs
-- ---------------------------------------------------------------------

DR.json_decode = U.json_decode

local function enc_str(v)
  return '"' .. tostring(v):gsub('[%c"\\]', function(ch)
    local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
    return map[ch] or ("\\u%04x"):format(ch:byte())
  end) .. '"'
end

-- The web list, in the page's own key order. "ic" (an icon, which the
-- page doesn't draw) only when there is one: kept so a bar moved off the
-- web gets its icons back.
local function enc_list(list)
  local out = {}
  for _, e in ipairs(list) do
    local ic = (e.ic and e.ic ~= "") and (',"ic":' .. enc_str(e.ic)) or ""
    if e.sp then
      out[#out + 1] = '{"sp":1}'
    elseif e.m then
      out[#out + 1] = '{"m":1,"l":' .. enc_str(e.l or "") .. ',"c":' .. enc_str(e.c or "") .. ic
                      .. ',"i":' .. enc_list(e.i or {}) .. '}'
    else
      out[#out + 1] = '{"l":' .. enc_str(e.l or "") .. ',"a":' .. enc_str(e.a or "")
                      .. ',"c":' .. enc_str(e.c or "") .. ic .. '}'
    end
  end
  return "[" .. table.concat(out, ",") .. "]"
end
DR.json_encode_list = enc_list

-- The web's entries as toolbar items, and back.
function DR.from_web(arr)
  local out = {}
  for _, e in ipairs(type(arr) == "table" and arr or {}) do
    if type(e) == "table" then
      if e.sp then
        out[#out + 1] = { sep = true, gap = true }
      elseif e.m then
        out[#out + 1] = { menu = true, icon = tostring(e.ic or ""), label = tostring(e.l or ""), color = e.c or "",
                          items = DR.from_web(e.i) }
      elseif e.a and tostring(e.a) ~= "" then
        out[#out + 1] = { cmd = tostring(e.a), icon = tostring(e.ic or ""), label = tostring(e.l or ""), color = e.c or "" }
      end
    end
  end
  return out
end

function DR.to_web(items)
  local out = {}
  for _, it in ipairs(items or {}) do
    if it.menu then
      out[#out + 1] = { m = 1, l = it.label or "", c = it.color or "", ic = it.icon, i = DR.to_web(it.items) }
    elseif it.sep then
      out[#out + 1] = { sp = 1 }
    else
      out[#out + 1] = { l = it.label or "", a = it.cmd or "", c = it.color or "", ic = it.icon }
    end
  end
  return out
end

DR.web_store = {
  load = function()
    return DR.from_web(DR.json_decode(reaper.GetExtState(DR.WEB_NS, DR.WEB_KEY)) or {})
  end,
  save = function(items)
    -- The page has no way to name an action, so a button left without a
    -- label goes over with the action's name (after its category).
    local function fill(list)
      for _, e in ipairs(list) do
        if e.m then fill(e.i)
        elseif e.a and (e.l or "") == "" then
          local n = TB.action_name(TB.resolve(e.a))
          if n then e.l = n:match(":%s*(.+)$") or n end
        end
      end
      return list
    end
    reaper.SetExtState(DR.WEB_NS, DR.WEB_KEY, enc_list(fill(DR.to_web(items))), true)
  end,
  stamp = function() return reaper.GetExtState(DR.WEB_NS, DR.WEB_KEY) end,
}

-- ---------------------------------------------------------------------
-- the bars
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- pure: sharing bars (a file of [Bar] sections)
-- ---------------------------------------------------------------------

--[[
  An export file, plain text:
      [Bar 1]
      name=Edit
      place=top             where it was (TS_CV_Drawers places)
      style=both            buttons: both (icon + label) or icons
      width=128             a side drawer's width
      dock=0                a window's docker
      items=...             its buttons, TS_CV_Toolbar's line (menus too)
      web=[...]             the same as the web page's JSON (colours)
      action=40029|Edit: Undo     one per action, so an action missing
                                  on the importing side can be named
]]
local function one_line(s) return ((s or ""):gsub("[\r\n]", " ")) end

-- `name_of(cmd)` gives an action's name (or nil).
function DR.export_text(list, name_of)
  local out = { "; ChannelView action bars. Import them in Organise actions (Import\u{2026}).", "" }
  for i, d in ipairs(list) do
    local items = d.tb and d.tb.items or d.items or {}
    out[#out + 1] = ("[Bar %d]"):format(i)
    out[#out + 1] = "id=" .. tostring(d.id or i)
    out[#out + 1] = "name=" .. one_line(d.name)
    out[#out + 1] = "place=" .. (d.side or "none")
    out[#out + 1] = "style=" .. (d.style or "both")
    out[#out + 1] = "width=" .. tostring(math.floor(d.width or DR.W_DEF))
    out[#out + 1] = "dock=" .. tostring(math.floor(d.dock or 0))
    out[#out + 1] = "size=" .. tostring(size_of(d.size))
    out[#out + 1] = "align=" .. align_field(d)
    out[#out + 1] = "items=" .. TB.serialize(items)
    out[#out + 1] = "web=" .. DR.json_encode_list(DR.to_web(items))
    local seen = {}
    for _, it in ipairs(TB.flatten(items)) do
      if it.cmd and not seen[it.cmd] and not TB.switch_of(it) then
        seen[it.cmd] = true
        local n = name_of and name_of(it.cmd)
        out[#out + 1] = "action=" .. it.cmd .. "|" .. one_line(n or "")
      end
    end
    out[#out + 1] = ""
  end
  return table.concat(out, "\n")
end

-- The bars in an export file: { name, place, style, width, dock, items,
-- web_items, names = { [cmd] = name } }, or nil and why.
function DR.parse_export(text)
  if type(text) ~= "string" then return nil, "Couldn't read the file." end
  local list, cur = {}, nil
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    if line:match("^%[Bar[^%]]*%]%s*$") then
      cur = { name = "", place = "none", style = "both", width = DR.W_DEF, dock = 0, items = {}, names = {} }
      list[#list + 1] = cur
    elseif cur and not line:match("^%s*;") then
      local k, v = line:match("^([%a_]+)=(.*)$")
      if k == "id" then cur.id = tonumber(v)
      elseif k == "name" then cur.name = clean(v)
      elseif k == "place" then cur.place = VALID[v] and v or "none"
      elseif k == "style" then cur.style = (v == "icons") and "icons" or "both"
      elseif k == "width" then cur.width = math.max(DR.W_MIN, math.min(DR.W_MAX, tonumber(v) or DR.W_DEF))
      elseif k == "dock" then cur.dock = tonumber(v) or 0
      elseif k == "size" then cur.size = size_of(v)
      elseif k == "align" then cur.halign, cur.valign, cur.cstyle = align_of(v)
      elseif k == "items" then cur.items = TB.parse(v ~= "" and v or "none")
      elseif k == "web" then cur.web_items = DR.from_web(DR.json_decode(v) or {})
      elseif k == "action" then
        local cmd, n = v:match("^([^|]+)|(.*)$")
        if cmd then cur.names[cmd] = n end
      end
    end
  end
  if #list == 0 then return nil, "There are no ChannelView action bars in that file." end
  return list
end

-- ---------------------------------------------------------------------
-- load / save
-- ---------------------------------------------------------------------

function DR.name_of(d)
  return (d.name and d.name ~= "") and d.name or ("Bar " .. d.id)
end

local function bar_for(d)
  local tb
  if d.side == "web" then
    tb = TB.make("web", "dr" .. d.id, {}, DR.web_store)
  else
    tb = TB.make(d.key, "dr" .. d.id, d.key == "toolbar" and TB.DEFAULTS or {})
  end
  tb.load()
  tb.style = d.style
  tb.btn = size_of(d.size)
  tb.halign, tb.valign, tb.cstyle = d.halign or "-", d.valign or "-", d.cstyle or "u"
  tb.organise = function(item) if DR.organise then DR.organise(d, item) end end
  tb.extra_bg = function(ctx, where) DR.drawer_menu(ctx, d, where) end
  -- toolbar switches (TS_CV_Toolbar): what this bar is, and the others
  tb.bar_id, tb.bar_name = d.id, DR.name_of(d)
  tb.bar_name_of = function(id) local e = DR.by_id(id) return e and DR.name_of(e) end
  tb.switch_to = function(id) DR.switch(d, DR.by_id(id)) end
  tb.switch_list = function() return DR.switch_list() end
  return tb
end

local revs = 0
function DR.load()
  for _, d in ipairs(DR.list) do if d.tb then d.tb.cancel_pick() end end
  local s = reaper.GetExtState(C.EXT_SECT, DR.KEY)
  if s == "" then
    DR.list = DR.migrate(reaper.GetExtState(C.EXT_SECT, DR.OLD_KEY))
    reaper.SetExtState(C.EXT_SECT, DR.KEY, DR.serialize(DR.list), true)
  else
    DR.list = DR.parse(s)
  end
  for _, d in ipairs(DR.list) do d.tb = bar_for(d) end
  DR.stamp = reaper.GetExtState(C.EXT_SECT, DR.REV)
end

function DR.save()
  reaper.SetExtState(C.EXT_SECT, DR.KEY, DR.serialize(DR.list), true)
  revs = revs + 1
  DR.stamp = ("%.3f.%d"):format(reaper.time_precise(), revs)
  reaper.SetExtState(C.EXT_SECT, DR.REV, DR.stamp, false)
  for _, d in ipairs(DR.list) do
    if d.tb then
      d.tb.style = d.style; d.tb.btn = size_of(d.size); d.tb.bar_name = DR.name_of(d)
      d.tb.halign, d.tb.valign, d.tb.cstyle = d.halign or "-", d.valign or "-", d.cstyle or "u"
    end
  end
end

-- Another process changed the list: reload it. Returns true when it did.
function DR.sync()
  if reaper.GetExtState(C.EXT_SECT, DR.REV) ~= DR.stamp then DR.load(); return true end
  return false
end

function DR.by_id(id)
  for _, d in ipairs(DR.list) do if d.id == id then return d end end
  return nil
end

function DR.at(place)
  for _, d in ipairs(DR.list) do if d.side == place then return d end end
  return nil
end

-- A single place with no bar gets an empty one (the TCP asks).
function DR.ensure(place, name)
  return DR.at(place) or DR.new(place, name)
end

function DR.new(side, name)
  local id = 1
  for _, d in ipairs(DR.list) do id = math.max(id, d.id + 1) end
  local d = { id = id, side = VALID[side] and side or "top", open = true, width = DR.W_DEF,
              style = "both", key = "drawer_" .. id, dock = 0, size = DR.SIZE_DEF,
              name = name or ((side == "window") and ("Toolbar " .. id) or ("Drawer " .. id)) }
  -- a single place already has its bar: the new one goes nowhere yet
  if DR.SINGLE[d.side] and DR.at(d.side) then d.side = "none" end
  d.tb = bar_for(d)
  DR.list[#DR.list + 1] = d
  DR.save()
  return d
end

-- Bars that moved get new instances; a bar moving onto or off the web
-- takes its buttons with it. `was` has each bar's place and buttons from
-- before.
local function rebuild(moved, was)
  -- off the web first, onto it last: both are the one JSON list
  table.sort(moved, function(a, b) return (a.side == "web" and 1 or 0) < (b.side == "web" and 1 or 0) end)
  for _, e in ipairs(moved) do
    local before = was[e].side
    if e.tb then e.tb.cancel_pick() end
    e.tb = bar_for(e)
    if (before == "web") ~= (e.side == "web") then
      e.tb.items = was[e].items
      e.tb.save()
    end
  end
end

-- Pure: bar e takes d's place (shown or not, its width and dock) and d
-- takes e's -- what a toolbar switch does.
function DR.swap_in(d, e)
  if not d or not e or d == e then return false end
  d.side, e.side = e.side, d.side
  d.open, e.open = e.open, d.open
  d.width, e.width = e.width, d.width
  d.dock, e.dock = e.dock, d.dock
  if DR.DRAWER[e.side] or e.side == "window" then e.open = true end
  return true
end

-- A switch on bar d: bar e shows where d was. In a window, e opens where
-- d's window was (the toolbars script reads `took_from`).
function DR.switch(d, e)
  if not d or not e or d == e then return false end
  local was = {}
  for _, b in ipairs({ d, e }) do was[b] = { side = b.side, items = b.tb and TB.copy_items(b.tb.items) or {} } end
  DR.swap_in(d, e)
  if e.side == "window" then e.took_from = d.id end
  rebuild({ d, e }, was)
  DR.save()
  if e.side == "window" then DR.ensure_host() end
  if DR.on_change then DR.on_change() end
  return true
end

-- Every bar, for a switch's menu: { id, name, where }.
function DR.switch_list()
  local out = {}
  for _, e in ipairs(DR.list) do
    out[#out + 1] = { id = e.id, name = DR.name_of(e),
                      where = (e.side == "none") and "not shown" or DR.SIDE_NAME[e.side] }
  end
  return out
end

-- Moves a bar, its buttons with it (into or out of the web's list).
function DR.set_place(d, place)
  if d.side == place or not VALID[place] then return end
  local was = {}
  for _, e in ipairs(DR.list) do was[e] = { side = e.side, items = e.tb and TB.copy_items(e.tb.items) or {} } end
  local other = DR.place_in(DR.list, d, place)
  local moved = { d }
  if other then moved[#moved + 1] = other end
  rebuild(moved, was)
  -- a single place left empty gets an empty bar: the TCP and the web
  -- always show one (the web's list emptied first, or the new bar would
  -- read back the buttons that just left)
  for p in pairs(DR.SINGLE) do
    if not DR.at(p) then
      if p == "web" then reaper.SetExtState(DR.WEB_NS, DR.WEB_KEY, "[]", true) end
      DR.new(p, DR.SINGLE_NAME[p])
    end
  end
  DR.save()
  if place == "window" then DR.ensure_host() end
  if DR.on_change then DR.on_change() end
end

-- Brings in bars from an export file: each entry { ... (DR.parse_export),
-- replace = a bar of yours to replace, or nil for a new one }. A new bar
-- goes where it was, except onto the TCP's or the web's place (those
-- have a bar already) unless `use_places`: then it swaps in and yours
-- goes nowhere. A replaced bar keeps its place unless `use_places`.
function DR.import(entries, use_places)
  local window = false
  local new_id, done = {}, {}
  for _, e in ipairs(entries) do
    local d = e.replace
    if not d then
      d = DR.new(DR.SINGLE[e.place] and "none" or e.place, e.name)
      if DR.SINGLE[e.place] and use_places then DR.set_place(d, e.place) end
    elseif use_places and d.side ~= e.place then
      DR.set_place(d, e.place)
    end
    d.style, d.width, d.dock = e.style, e.width, e.dock
    d.size = size_of(e.size)
    d.tb.btn = d.size
    d.halign, d.valign, d.cstyle = e.halign or "-", e.valign or "-", e.cstyle or "u"
    d.tb.halign, d.tb.valign, d.tb.cstyle = d.halign, d.valign, d.cstyle
    local items = (d.side == "web" and e.web_items) or e.items
    d.tb.items = TB.copy_items(items or {})
    d.tb.style = d.style
    if e.id then new_id[e.id] = d.id end
    done[#done + 1] = d
    if d.side == "window" then window = true end
  end
  -- switches name bars by id: the file's ids become these bars' ids, and
  -- one naming a bar that didn't come in becomes the menu of bars
  for _, d in ipairs(done) do
    DR.remap_switches(d.tb.items, new_id)
    d.tb.save()
  end
  DR.save()
  if window then DR.ensure_host() end
end

-- Pure: switches in `items` (menus too) pointed at map[old id].
function DR.remap_switches(items, map)
  for _, it in ipairs(items or {}) do
    if it.menu then DR.remap_switches(it.items, map)
    else
      local sw = TB.switch_of(it)
      if type(sw) == "number" then it.cmd = TB.switch_cmd(map[sw]) end
    end
  end
end

function DR.remove(d)
  if DR.SINGLE[d.side] then return false end
  for i, e in ipairs(DR.list) do
    if e == d then
      table.remove(DR.list, i)
      if d.tb then d.tb.cancel_pick(); d.tb.forget() end
      DR.save()
      return true
    end
  end
  return false
end

function DR.any_open()
  for _, d in ipairs(DR.list) do
    if d.open and (DR.DRAWER[d.side] or d.side == "window") then return true end
  end
  return false
end

function DR.open_on(side)
  local out = {}
  for _, d in ipairs(DR.list) do if d.open and d.side == side then out[#out + 1] = d end end
  return out
end

function DR.cancel_picks()
  for _, d in ipairs(DR.list) do if d.tb then d.tb.cancel_pick() end end
end

-- ---------------------------------------------------------------------
-- the toolbars script (windows, and the organiser on its own)
-- ---------------------------------------------------------------------

local SEP = package.config:sub(1, 1)
local HERE = (debug.getinfo(1, "S").source:match("^@?(.*[\\/])")) or ""
DR.HOST_ALIVE = "bars_host_alive"
DR.HOST_ORGANISE = "bars_organise"
DR.HOST_QUIT = "bars_host_quit"

-- Running? It writes the time every second or so, and clears it on exit.
function DR.host_running()
  local t = tonumber(reaper.GetExtState(C.EXT_SECT, DR.HOST_ALIVE))
  return t ~= nil and math.abs(reaper.time_precise() - t) < 3
end

local host_cmd = nil
function DR.host_command()
  if host_cmd then return host_cmd end
  local SU = require("TS_CV_Startup")
  local fh = io.open(reaper.GetResourcePath() .. SEP .. "reaper-kb.ini", "rb")
  local id = fh and SU.kb_find(fh:read("*a"), DR.HOST_FILE)
  if fh then fh:close() end
  local num = id and reaper.NamedCommandLookup(id) or 0
  if num == 0 and reaper.AddRemoveReaScript then
    num = reaper.AddRemoveReaScript(true, 0, HERE .. DR.HOST_FILE, true) or 0
  end
  host_cmd = (num and num > 0) and num or nil
  return host_cmd
end

-- Starts the toolbars script when a bar wants a window and it isn't on.
function DR.ensure_host()
  if DR.host_running() then return true end
  local need = false
  for _, d in ipairs(DR.list) do if d.side == "window" and d.open then need = true end end
  if not need and reaper.GetExtState(C.EXT_SECT, DR.HOST_ORGANISE) ~= "1" then return false end
  local cmd = DR.host_command()
  if not cmd then return false end
  -- seen as running straight away, so a second ask this frame doesn't
  -- start a second copy
  reaper.SetExtState(C.EXT_SECT, DR.HOST_ALIVE, tostring(reaper.time_precise()), false)
  reaper.Main_OnCommand(cmd, 0)
  return true
end

-- Organise actions, from somewhere that can't show the window itself (the
-- TCP, the action): the toolbars script opens it.
function DR.request_organiser()
  reaper.SetExtState(C.EXT_SECT, DR.HOST_ORGANISE, "1", false)
  DR.ensure_host()
end

-- ---------------------------------------------------------------------
-- sizes
-- ---------------------------------------------------------------------

local PAD = 5               -- around the buttons
local NAME_GAP = 12

local function name_w(ctx, d)
  if not d.name or d.name == "" then return 0 end
  return ImGui.CalcTextSize(ctx, d.name:upper()) + NAME_GAP
end

-- A top or bottom drawer's height at width w: as many rows as its
-- buttons need, up to three.
local function bar_h(ctx, d, w)
  local bh = size_of(d.size)
  local rows = math.min(3, d.tb.rows_needed(ctx, w - name_w(ctx, d) - PAD * 2, bh))
  return rows * bh + (rows - 1) * C.TB_GAP + PAD * 2
end

-- All of a side's open drawers: the height (top, bottom) or the width
-- (left, right) they take, gaps included.
function DR.extent(ctx, side, w)
  local total = 0
  for _, d in ipairs(DR.open_on(side)) do
    if side == "top" or side == "bottom" then total = total + bar_h(ctx, d, w) + 1
    else total = total + d.width + 1 end
  end
  return total
end

-- ---------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------

local function chrome(dl, x, y, w, h, side)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.header_bg)
  local b = C.COL.panel_border
  if side == "top" then ImGui.DrawList_AddLine(dl, x, y + h - 0.5, x + w, y + h - 0.5, b, 1.0)
  elseif side == "bottom" then ImGui.DrawList_AddLine(dl, x, y + 0.5, x + w, y + 0.5, b, 1.0)
  elseif side == "left" then ImGui.DrawList_AddLine(dl, x + w - 0.5, y, x + w - 0.5, y + h, b, 1.0)
  else ImGui.DrawList_AddLine(dl, x + 0.5, y, x + 0.5, y + h, b, 1.0) end
end

-- Top or bottom: the drawers stacked from y down, each full width.
-- Returns the height taken.
function DR.draw_h(ctx, side, x, y, w)
  local dl = ImGui.GetWindowDrawList(ctx)
  local cy = y
  for _, d in ipairs(DR.open_on(side)) do
    local h = bar_h(ctx, d, w)
    chrome(dl, x, cy, w, h, side)
    local nw = name_w(ctx, d)
    if nw > 0 then
      local _, th = ImGui.CalcTextSize(ctx, "X")
      ImGui.DrawList_AddText(dl, x + PAD + 2, cy + (h - th) * 0.5, C.COL.header_dim, d.name:upper())
    end
    d.tb.draw(ctx, x + nw + PAD, cy + PAD - 2, w - nw - PAD * 2, h - PAD * 2 + 4, true,
      side == "bottom" and "up" or "down")
    cy = cy + h + 1
  end
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.Dummy(ctx, 0, 0)
  return cy - y
end

-- Left or right: the drawers side by side from x, h tall. A drag on a
-- drawer's inner edge resizes it.
local resizing = nil
function DR.draw_v(ctx, side, x, y, h)
  local dl = ImGui.GetWindowDrawList(ctx)
  local list = DR.open_on(side)
  local cx = x
  -- on the right, the first drawer is the outermost
  if side == "right" then
    local rev = {}
    for i = #list, 1, -1 do rev[#rev + 1] = list[i] end
    list = rev
  end
  for _, d in ipairs(list) do
    local w = d.width
    chrome(dl, cx, y, w, h, side)
    local top = y
    if d.name and d.name ~= "" and w >= 60 then
      local _, th = ImGui.CalcTextSize(ctx, "X")
      ImGui.DrawList_PushClipRect(dl, cx, y, cx + w, y + h, true)
      ImGui.DrawList_AddText(dl, cx + 6, y + 5, C.COL.header_dim, d.name:upper())
      ImGui.DrawList_PopClipRect(dl)
      top = y + th + 6
    end
    d.tb.draw_v(ctx, cx, top, w, y + h - top, side == "left" and "right" or "left")
    -- the inner edge: a grip to drag
    local gx = (side == "left") and (cx + w - 3) or (cx - 3)
    ImGui.SetCursorScreenPos(ctx, gx, y)
    ImGui.InvisibleButton(ctx, "drgrip" .. d.id, 6, math.max(1, h))
    local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    if hov or act then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
      local my = y + h * 0.5
      ImGui.DrawList_AddLine(dl, gx + 3, my - 14, gx + 3, my + 14,
        act and C.COL.accent or C.COL.knob_ring, 2.0)
    end
    if act then
      if not resizing then resizing = { d = d, w0 = d.width } end
      local dx = ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left, 0)
      if side == "right" then dx = -dx end
      d.width = math.max(DR.W_MIN, math.min(DR.W_MAX, math.floor(resizing.w0 + dx)))
    elseif resizing and resizing.d == d then
      resizing = nil
      DR.save()
    end
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
      -- double-click the edge: back to the default width
      d.width = DR.W_DEF; DR.save()
    end
    cx = cx + w + 1
  end
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.Dummy(ctx, 0, 0)
end

-- A bar in a window of its own (the toolbars script): a row (wrapping)
-- when the window is wider than tall, a column when it's taller.
function DR.draw_window_bar(ctx, d)
  local w, h = ImGui.GetContentRegionAvail(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if h > w * 1.3 then
    d.tb.draw_v(ctx, x - 4, y, w + 8, h, "right")
  else
    d.tb.draw(ctx, x, y, w, h, true, "down")
  end
end

-- Each drawer's popups (its buttons' menus, its right-click menu), once
-- a frame from the window the drawers were drawn in.
function DR.draw_menus(ctx)
  for _, d in ipairs(DR.list) do
    if d.open and DR.DRAWER[d.side] and d.tb then d.tb.draw_menus(ctx) end
  end
end

-- Picks still have to be polled for a bar this window doesn't draw.
function DR.poll()
  for _, d in ipairs(DR.list) do
    if d.tb and not (d.open and DR.DRAWER[d.side]) then d.tb.poll() end
  end
end

-- ---------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------

DR.DOCKS = { { "Floating", 0 } }
for i = 1, 16 do DR.DOCKS[#DR.DOCKS + 1] = { "Docker " .. i, -i } end

local rename_buf, rename_for = "", nil

-- Which ways a bar's buttons can be aligned where it is: across for a
-- row, up and down for both (the web's bar only across).
function DR.aligns(d)
  local column = d.side == "left" or d.side == "right"
  return not column or d.side == "window", d.side ~= "web"
end

-- The alignment entries, for a bar's Show menu.
function DR.align_items(ctx, d)
  local across, updown = DR.aligns(d)
  local h, v = d.halign or "-", d.valign or "-"
  if across then
    for _, a in ipairs(DR.HALIGN) do
      local cur = h == a[2] or (h == "-" and a[2] == "l")
      if ImGui.MenuItem(ctx, "Align " .. a[1]:lower() .. "##drha" .. d.id .. a[2], nil, cur) then
        d.halign = a[2]; DR.save()
      end
    end
  end
  if updown then
    if across then ImGui.Separator(ctx) end
    for _, a in ipairs(DR.VALIGN) do
      local column = d.side == "left" or d.side == "right"
      local cur = v == a[2] or (v == "-" and a[2] == (column and "t" or "c"))
      if ImGui.MenuItem(ctx, "Align " .. a[1]:lower() .. "##drva" .. d.id .. a[2], nil, cur) then
        d.valign = a[2]; DR.save()
      end
    end
  end
end

-- A bar's own entries in its right-click menu (TB's background menu calls
-- this at its head and tail).
function DR.drawer_menu(ctx, d, where)
  if where == "head" then
    ImGui.TextDisabled(ctx, (d.name ~= "" and d.name or "Bar") .. "  \u{00B7}  " .. DR.SIDE_NAME[d.side])
    ImGui.Separator(ctx)
    return
  end
  ImGui.Separator(ctx)
  if ImGui.BeginMenu(ctx, "Place##dr" .. d.id) then
    for _, s in ipairs(DR.PLACES) do
      local label = DR.SIDE_NAME[s]
      local e = DR.SINGLE[s] and DR.at(s)
      if e and e ~= d then label = label .. "  (swaps with " .. (e.name ~= "" and e.name or "its bar") .. ")" end
      if ImGui.MenuItem(ctx, label .. "##drs" .. d.id .. s, nil, d.side == s) then DR.set_place(d, s) end
      if s == "bottom" or s == "window" or s == "web" then ImGui.Separator(ctx) end
    end
    ImGui.EndMenu(ctx)
  end
  if d.tb and ImGui.BeginMenu(ctx, "Switch to##dr" .. d.id) then
    d.tb.switch_entries(ctx)
    ImGui.EndMenu(ctx)
  end
  if d.side == "window" and ImGui.BeginMenu(ctx, "Dock##dr" .. d.id) then
    for _, k in ipairs(DR.DOCKS) do
      if ImGui.MenuItem(ctx, k[1] .. "##drd" .. d.id .. k[2], nil, (d.dock or 0) == k[2]) then
        d.dock, d.dock_req = k[2], k[2]; DR.save()
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Show##dr" .. d.id) then
    if ImGui.MenuItem(ctx, "Icons and labels##drst" .. d.id, nil, d.style == "both") then d.style = "both"; DR.save() end
    if ImGui.MenuItem(ctx, "Icons##drst" .. d.id, nil, d.style == "icons") then d.style = "icons"; DR.save() end
    ImGui.Separator(ctx)
    for _, z in ipairs(DR.SIZES) do
      if ImGui.MenuItem(ctx, z[1] .. "##drsz" .. d.id .. z[2], nil, size_of(d.size) == z[2]) then d.size = z[2]; DR.save() end
    end
    ImGui.Separator(ctx)
    DR.align_items(ctx, d)
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Colours as underlines##drcu" .. d.id, nil, d.cstyle ~= "i") then d.cstyle = "u"; DR.save() end
    if ImGui.MenuItem(ctx, "Coloured icons##drci" .. d.id, nil, d.cstyle == "i") then d.cstyle = "i"; DR.save() end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Rename##dr" .. d.id) then
    if rename_for ~= d then rename_for, rename_buf = d, d.name or "" end
    ImGui.SetNextItemWidth(ctx, 150)
    local _, v = ImGui.InputText(ctx, "##drname" .. d.id, rename_buf)
    rename_buf = v
    local enter = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Set##drname" .. d.id) or enter then
      d.name = clean(rename_buf); DR.save(); rename_for = nil
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndMenu(ctx)
  end
  if d.side == "window" and DR.host_extra then DR.host_extra(ctx) end
  if (DR.DRAWER[d.side] or d.side == "window") and ImGui.MenuItem(ctx, "Close##dr" .. d.id) then
    d.open = false; DR.save()
  end
  if not DR.SINGLE[d.side] and ImGui.MenuItem(ctx, "Remove the bar\u{2026}##dr" .. d.id) then
    if reaper.MB(("Remove \"%s\" and its buttons?"):format(d.name or ""), "ChannelView", 4) == 6 then
      DR.remove(d)
    end
  end
end

-- What the header's drawers button opens: the drawers and windowed bars,
-- ticked while open (a click opens or closes one), new ones, and the
-- organiser.
function DR.header_menu(ctx)
  local any = false
  for _, d in ipairs(DR.list) do
    if DR.DRAWER[d.side] or d.side == "window" then
      any = true
      local label = (d.name ~= "" and d.name or ("Bar " .. d.id)) .. "##drh" .. d.id
      if ImGui.MenuItem(ctx, label, DR.SIDE_NAME[d.side], d.open) then
        d.open = not d.open; DR.save()
        if d.open and d.side == "window" then DR.ensure_host() end
      end
    end
  end
  if not any then ImGui.TextDisabled(ctx, "No drawers or toolbars yet") end
  ImGui.Separator(ctx)
  if ImGui.BeginMenu(ctx, "New") then
    for _, s in ipairs({ "top", "left", "right", "bottom", "window" }) do
      local label = (s == "window") and "Toolbar in its own window" or (DR.SIDE_NAME[s] .. " drawer")
      if ImGui.MenuItem(ctx, label .. "##drnew" .. s) then
        DR.new(s)
        if s == "window" then DR.ensure_host() end
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.MenuItem(ctx, "Organise actions\u{2026}") then
    if DR.organise then DR.organise() end
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Import bars from file\u{2026}") and DR.share then DR.share("import") end
  if ImGui.MenuItem(ctx, "Export bars to file\u{2026}") and DR.share then DR.share("export") end
end

return DR
