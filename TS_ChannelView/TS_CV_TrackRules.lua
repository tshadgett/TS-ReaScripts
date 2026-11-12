-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_TrackRules.lua -- Track rules (Options ▸ Track rules): what
  happens when ChannelView adds or duplicates tracks, and how tracks are
  coloured and spaced.

  ADDING FROM A TEMPLATE beside a track (TR.add_from_template), the
  template's tracks go
    - into a new folder under a top-level track that isn't one (it becomes
      the folder: "Add child from template")
    - into a folder parent's folder, at its top or its bottom ("Add child")
    - after a track inside a folder, in the same folder ("Add sibling")
  Placement works on folder LEVELS, not depths: every track keeps its
  level, the new ones take the folder's, and every depth is worked out
  again from the levels (a track's depth is the next track's level less
  its own). So a folder's close moves to the new last track by itself,
  however many folders that track closed. While the tracks move, every
  depth is 0: a folder that never closes, even for a moment, can take in
  the tracks after it.

  NUMBERING. "Guitar 2" is the base "Guitar" and the number 2. A new track
  takes the next number in its folder (or the project): Guitar 1 beside
  Guitar 1 becomes Guitar 2, and a plain "Guitar" beside numbered ones
  becomes Guitar 1. A new track with no others of its name keeps its name.

  COLOURS, first match wins: the name rules, then the group's colour
  (Faders & strips: VCA leaders, folder parents, FX returns), then the
  folder's (its colour, or shades of it). A track ChannelView coloured is
  stamped with that colour (P_EXT); a track whose colour no longer matches
  its stamp, or that had a colour before any rule ran, was coloured by
  hand and is left alone.

  SPACERS. With any spacer rule on, ChannelView keeps the track spacers:
  before each top-level folder but the first track, after each top-level
  folder (before the track after it), before the first FX return, before
  SUM. None on, spacers are left as they are.

  Settings: ExtState TS_ChannelView/track_rules, one line.
--]]

local TR = {}

local SECT, KEY = "TS_ChannelView", "track_rules"
local STAMP = "P_EXT:TS_CV_RULECOL"
TR.SUM_NAME = "SUM"

-- ---------------------------------------------------------------------
-- settings
-- ---------------------------------------------------------------------

TR.DEFAULTS = {
  number = false, number_scope = "folder", keep_multi = false, alone = {},
  sort = "off", children = "top", tfolders = "flatten",
  arm = false, disarm = false, arm_tracking = false,
  ret_where = "end", ret_folder = "FX",
  col_folder = "off", tpl_col = false, rules = {}, grp = {},
  sp_folder = false, sp_after = false, sp_returns = false, sp_sum = false,
  live = false,
}

local function esc(s) return (tostring(s):gsub("[%%;=|,]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

-- one line: k=v;k=v, lists |-joined, a rule how,text,colour
function TR.encode(s)
  local parts = {}
  for k, d in pairs(TR.DEFAULTS) do
    local v = s[k]
    if v == nil then v = d end
    local str
    if k == "alone" then
      local t = {}
      for _, n in ipairs(v) do t[#t + 1] = esc(n) end
      str = table.concat(t, "|")
    elseif k == "rules" then
      local t = {}
      for _, r in ipairs(v) do t[#t + 1] = esc(r.how) .. "," .. esc(r.text) .. "," .. ("%06x"):format(r.col or 0) end
      str = table.concat(t, "|")
    elseif k == "grp" then
      local t = {}
      for g, c in pairs(v) do t[#t + 1] = esc(g) .. "," .. ("%06x"):format(c) end
      table.sort(t)
      str = table.concat(t, "|")
    elseif type(d) == "boolean" then
      str = v and "1" or "0"
    else
      str = esc(v)
    end
    parts[#parts + 1] = k .. "=" .. str
  end
  table.sort(parts)
  return table.concat(parts, ";")
end

function TR.decode(line)
  local s = {}
  for k, d in pairs(TR.DEFAULTS) do
    if type(d) == "table" then s[k] = {} else s[k] = d end
  end
  for k, v in (line or ""):gmatch("([%w_]+)=([^;]*)") do
    local d = TR.DEFAULTS[k]
    if d == nil then
    elseif k == "alone" then
      for n in v:gmatch("[^|]+") do s.alone[#s.alone + 1] = unesc(n) end
    elseif k == "rules" then
      for r in v:gmatch("[^|]+") do
        local how, text, col = r:match("^([^,]*),([^,]*),(%x+)$")
        if how then s.rules[#s.rules + 1] = { how = unesc(how), text = unesc(text), col = tonumber(col, 16) } end
      end
    elseif k == "grp" then
      for r in v:gmatch("[^|]+") do
        local g, col = r:match("^([^,]*),(%x+)$")
        if g then s.grp[unesc(g)] = tonumber(col, 16) end
      end
    elseif type(d) == "boolean" then
      s[k] = v == "1"
    else
      s[k] = unesc(v)
    end
  end
  return s
end

local cache, cache_line = nil, nil
function TR.get()
  local line = reaper.GetExtState(SECT, KEY) or ""
  if not cache or line ~= cache_line then cache, cache_line = TR.decode(line), line end
  return cache
end

function TR.save(s)
  local line = TR.encode(s)
  reaper.SetExtState(SECT, KEY, line, true)
  cache, cache_line = s, line
end

-- Anything for the colours or spacers to do.
function TR.colours_on(s)
  return s.col_folder ~= "off" or #s.rules > 0 or next(s.grp) ~= nil
end
function TR.spacers_on(s)
  return s.sp_folder or s.sp_after or s.sp_returns or s.sp_sum
end

-- ---------------------------------------------------------------------
-- names (pure)
-- ---------------------------------------------------------------------

-- "Guitar 12" -> "Guitar", 12; "Guitar" -> "Guitar", nil
function TR.parse_name(name)
  local base, num = (name or ""):match("^(.-)%s+(%d+)$")
  if base and base ~= "" then return base, tonumber(num) end
  return name or "", nil
end

-- The name for a new track called `raw` among `others` (the names already
-- in its series' scope, itself not included), and the renames that go with
-- it: { [index in others] = new name } for plain names that become 1.
function TR.number_name(raw, others)
  local base, num = TR.parse_name(raw)
  if base == "" then return raw, {} end
  local high, plain = 0, {}
  for i, n in ipairs(others) do
    local b, k = TR.parse_name(n)
    if b == base then
      if k then high = math.max(high, k)
      else high = math.max(high, 1); plain[#plain + 1] = i end
    end
  end
  local name = raw
  if high > 0 then name = base .. " " .. (high + 1) end
  local renames = {}
  if high > 0 then
    for _, i in ipairs(plain) do renames[i] = base .. " 1" end
  elseif not num then
    -- alone: kept as it is
  end
  return name, renames
end

-- ---------------------------------------------------------------------
-- folders (pure): levels and depths
-- ---------------------------------------------------------------------

-- Level before each track (0 top level) from the depths.
function TR.levels(depths)
  local out, lv = {}, 0
  for k = 1, #depths do
    out[k] = math.max(0, lv)
    lv = lv + (depths[k] or 0)
  end
  return out
end

-- Depths from levels: each track's depth is the next one's level less its
-- own, the last returning to the top.
function TR.depths(levels)
  local out = {}
  for k = 1, #levels do
    out[k] = (levels[k + 1] or 0) - levels[k]
  end
  return out
end

-- The last index of the folder starting at k (k itself for a track that
-- isn't a parent).
function TR.block_end(depths, k)
  if (depths[k] or 0) <= 0 then return k end
  local lv = TR.levels(depths)
  for j = k + 1, #depths do
    if lv[j] <= lv[k] then return j - 1 end
  end
  return #depths
end

-- What adding beside track k does: "child" (it's a top-level track that
-- isn't a parent, or a parent) or "sibling" (it's inside a folder). nil
-- with no track.
function TR.add_kind(depths, k)
  if not k or not depths[k] then return nil end
  local lv = TR.levels(depths)
  if (depths[k] or 0) > 0 or lv[k] == 0 then return "child" end
  return "sibling"
end

-- Where a block of n new tracks goes beside track k: returns the index
-- after which they go (0 = at the start), their folder level, and the
-- final levels of every track, old and new, in the new order (the new
-- ones at pos+1..pos+n). `rel` is each new track's level inside the block
-- (all 0 to flatten); `bottom` puts a folder parent's new children at its
-- end. With no k they go at `at_end` (default the end) at the top level.
function TR.place(depths, k, rel, bottom, at_end)
  local lv = TR.levels(depths)
  local n_old = #depths
  local pos, T
  if not k then
    pos, T = at_end or n_old, 0
  elseif (depths[k] or 0) > 0 then
    T = lv[k] + 1
    pos = bottom and TR.block_end(depths, k) or k
  elseif lv[k] == 0 then
    T, pos = 1, k
  else
    T, pos = lv[k], k
  end
  local out = {}
  for i = 1, pos do out[#out + 1] = lv[i] end
  for j = 1, #rel do out[#out + 1] = T + math.max(0, rel[j] or 0) end
  for i = pos + 1, n_old do out[#out + 1] = lv[i] end
  return pos, T, out
end

-- A block's own levels from its depths, the first at 0 (for keeping a
-- template's own folders).
function TR.rel_levels(depths)
  local lv = TR.levels(depths)
  local base = lv[1] or 0
  local out = {}
  for i = 1, #lv do out[i] = math.max(0, lv[i] - base) end
  return out
end

-- The order of a folder's children (each with what's under it, as one
-- unit): `items` = { { name, i } } in project order; returns the items
-- in the new order. "az": by name, then number, then where they were.
-- "series": each name's tracks together, in number order, where its first
-- one was; nothing else moves.
function TR.sort_children(items, how)
  local out = {}
  for i, it in ipairs(items) do
    local b, n = TR.parse_name(it.name)
    out[i] = { it = it, base = b:lower(), num = n or 1, pos = i }
  end
  if how == "az" then
    table.sort(out, function(a, b)
      if a.base ~= b.base then return a.base < b.base end
      if a.num ~= b.num then return a.num < b.num end
      return a.pos < b.pos
    end)
  elseif how == "series" then
    local first, groups, order = {}, {}, {}
    for _, e in ipairs(out) do
      if not first[e.base] then first[e.base] = e.pos; groups[e.base] = {}; order[#order + 1] = e.base end
      table.insert(groups[e.base], e)
    end
    out = {}
    for _, b in ipairs(order) do
      table.sort(groups[b], function(x, y)
        if x.num ~= y.num then return x.num < y.num end
        return x.pos < y.pos
      end)
      for _, e in ipairs(groups[b]) do out[#out + 1] = e end
    end
  end
  local res = {}
  for i, e in ipairs(out) do res[i] = e.it end
  return res
end

-- ---------------------------------------------------------------------
-- colours (pure)
-- ---------------------------------------------------------------------

local function mix(rgb, to, t)
  local r, g, b = (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff
  local R, G, B = (to >> 16) & 0xff, (to >> 8) & 0xff, to & 0xff
  local function m(a, z) return math.floor(a + (z - a) * t + 0.5) end
  return (m(r, R) << 16) | (m(g, G) << 8) | m(b, B)
end

-- The k-th of n shades of a folder's colour: lighter down the folder, or
-- darker for a light colour.
function TR.shade(rgb, k, n)
  local r, g, b = (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff
  local light = (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6
  local t = 0.45 * k / math.max(1, n)
  return mix(rgb, light and 0x000000 or 0xffffff, t)
end

-- What colour the rules give a track (0xRRGGBB), or nil. `t` = { name,
-- group ("vca"|"parent"|"fxret"|nil), parent_col (0xRRGGBB or nil), k, n
-- (its place among its folder's children, 1-based) }.
function TR.colour_for(s, t)
  local name = (t.name or ""):lower()
  for _, r in ipairs(s.rules) do
    local txt = (r.text or ""):lower()
    if txt ~= "" then
      if (r.how == "is" and name == txt) or (r.how ~= "is" and name:find(txt, 1, true)) then
        return r.col
      end
    end
  end
  if t.group and s.grp[t.group] then return s.grp[t.group] end
  if t.parent_col then
    if s.col_folder == "same" then return t.parent_col end
    if s.col_folder == "shades" then return TR.shade(t.parent_col, t.k or 1, t.n or 1) end
  end
  return nil
end

-- Which tracks get a spacer before them: `t` = list of { level, parent
-- (bool), fxret (bool), sum (bool) } in project order; returns a list of
-- booleans.
function TR.spacer_plan(s, t)
  local out, first_ret = {}, false
  for i, x in ipairs(t) do
    local on = false
    if s.sp_folder and i > 1 and x.level == 0 and x.parent then on = true end
    if s.sp_after and i > 1 and x.level == 0 and t[i - 1].level > 0 then on = true end
    if s.sp_returns and x.fxret and not x.sum and not first_ret then on = true; first_ret = true end
    if x.fxret and not x.sum then first_ret = true end
    if s.sp_sum and x.sum and i > 1 then on = true end
    out[i] = on
  end
  return out
end

-- ---------------------------------------------------------------------
-- REAPER side
-- ---------------------------------------------------------------------

local function tracks()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do out[#out + 1] = reaper.GetTrack(0, i) end
  return out
end

local function depth(tr) return math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0) end
local function name_of(tr)
  local _, n = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return n or ""
end
local function set_name(tr, n) reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", n, true) end
local function index_of(tr) return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) end
local function nrecv(tr) return reaper.GetTrackNumSends(tr, -1) or 0 end
local function nsends(tr) return reaper.GetTrackNumSends(tr, 0) or 0 end
local function is_sum(tr) return name_of(tr) == TR.SUM_NAME end

local function to_rgb(native)
  if not native or native & 0x1000000 == 0 then return nil end
  local r, g, b = reaper.ColorFromNative(native & 0xffffff)
  return (r << 16) | (g << 8) | b
end
local function to_native(rgb)
  return reaper.ColorToNative((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff) | 0x1000000
end

-- The SUM track, or nil.
function TR.sum_track()
  for _, tr in ipairs(tracks()) do if is_sum(tr) then return tr end end
  return nil
end

-- Where something added "at the end" goes: before SUM when there is one
-- (0-based index), else the end.
function TR.end_index()
  local sum = TR.sum_track()
  if sum then return index_of(sum) - 1 end
  return reaper.CountTracks(0)
end

-- Puts every track in `final` order with `levels`. Depths go to 0 first,
-- then the tracks move, then the depths are set from the levels.
local function arrange(final, levels)
  local all = tracks()
  for _, tr in ipairs(all) do
    if depth(tr) ~= 0 then reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0) end
  end
  for i, tr in ipairs(final) do
    if reaper.GetTrack(0, i - 1) ~= tr then
      reaper.SetOnlyTrackSelected(tr)
      reaper.ReorderSelectedTracks(i - 1, 0)
    end
  end
  local d = TR.depths(levels)
  for i, tr in ipairs(final) do
    if depth(tr) ~= d[i] then reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", d[i]) end
  end
end

-- A track's folder parent, or nil.
local function parent_of(tr) return reaper.GetParentTrack(tr) end

-- The tracks a series is counted among: the folder's (or the top level's)
-- direct children, or the whole project.
local function scope_tracks(tr, s)
  local out = {}
  if s.number_scope == "project" then
    for _, t in ipairs(tracks()) do if t ~= tr then out[#out + 1] = t end end
    return out
  end
  local p = parent_of(tr)
  for _, t in ipairs(tracks()) do
    if t ~= tr and parent_of(t) == p then out[#out + 1] = t end
  end
  return out
end

local function left_alone(s, folder)
  if not folder then return false end
  local b = TR.parse_name(name_of(folder)):lower()
  for _, n in ipairs(s.alone) do
    if n:lower():match("^%s*(.-)%s*$") == b then return true end
  end
  return false
end

-- Numbers the new tracks in their series.
function TR.number(new, s)
  for _, tr in ipairs(new) do
    local raw = name_of(tr)
    if raw ~= "" then
      local others, names = scope_tracks(tr, s), {}
      for i, t in ipairs(others) do names[i] = name_of(t) end
      local name, renames = TR.number_name(raw, names)
      if name ~= raw then set_name(tr, name) end
      for i, nn in pairs(renames) do set_name(others[i], nn) end
    end
  end
end

-- Sorts a folder's children (each with what's under it).
function TR.sort_folder(folder, how)
  if not folder or how == "off" then return end
  local all = tracks()
  local deps = {}
  for i, tr in ipairs(all) do deps[i] = depth(tr) end
  local lv = TR.levels(deps)
  local fi = index_of(folder)
  local fend = TR.block_end(deps, fi)
  local items, i = {}, fi + 1
  while i <= fend do
    local e = TR.block_end(deps, i)
    items[#items + 1] = { name = name_of(all[i]), i = i, e = e }
    i = e + 1
  end
  if #items < 2 then return end
  local sorted = TR.sort_children(items, how)
  local same = true
  for k, it in ipairs(sorted) do if it ~= items[k] then same = false end end
  if same then return end
  local final, levels = {}, {}
  for k = 1, fi do final[#final + 1] = all[k]; levels[#levels + 1] = lv[k] end
  for _, it in ipairs(sorted) do
    for k = it.i, it.e do final[#final + 1] = all[k]; levels[#levels + 1] = lv[k] end
  end
  for k = fend + 1, #all do final[#final + 1] = all[k]; levels[#levels + 1] = lv[k] end
  arrange(final, levels)
end

-- A track's group for the colours: as Faders & strips' groups.
-- (SUM isn't an FX return here: it has a rule of its own if any)
local function group_of(tr)
  local TO = require("TS_CV_TrackOps")
  local g = TO.fader_category and TO.fader_category(tr, reaper.time_precise() + 2) or nil
  if g == "fxret" and is_sum(tr) then g = nil end
  return g
end

-- May the rules colour it? Not when it was coloured by hand.
local function ours(tr, fresh)
  local cur = reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR") or 0
  if cur == 0 or fresh then return true end
  local _, st = reaper.GetSetMediaTrackInfo_String(tr, STAMP, "", false)
  return st ~= "" and tonumber(st) == cur
end

local function paint(tr, rgb)
  local nat = to_native(rgb)
  if (reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR") or 0) ~= nat then
    reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", nat)
  end
  reaper.GetSetMediaTrackInfo_String(tr, STAMP, tostring(nat), true)
end

-- Colours `list` (default every track) by the rules. `fresh` tracks
-- (just added) are coloured whatever colour they came with, unless a
-- template's own colour wins. `force` colours tracks coloured by hand too.
function TR.colour(list, s, fresh, force)
  if not TR.colours_on(s) then return 0 end
  local all = tracks()
  list = list or all
  local want = {}
  for _, tr in ipairs(list) do want[tr] = true end
  fresh = fresh or {}
  -- children's places in their folders, for shades
  local kids = {}
  for _, tr in ipairs(all) do
    local p = parent_of(tr) or false
    kids[p] = kids[p] or {}
    table.insert(kids[p], tr)
  end
  local place = {}
  for p, l in pairs(kids) do
    for k, tr in ipairs(l) do place[tr] = { k = k, n = #l, p = p } end
  end
  local n = 0
  for _, tr in ipairs(all) do               -- in order: parents before children
    if want[tr] then
      local f = fresh[tr]
      local keep_tpl = f and s.tpl_col and (reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR") or 0) ~= 0
      if not keep_tpl and (force or ours(tr, f)) then
        local pl = place[tr]
        local pc = pl.p and to_rgb(reaper.GetMediaTrackInfo_Value(pl.p, "I_CUSTOMCOLOR")) or nil
        local col = TR.colour_for(s, { name = name_of(tr), group = group_of(tr), parent_col = pc, k = pl.k, n = pl.n })
        if col then paint(tr, col); n = n + 1 end
      end
    end
  end
  return n
end

-- Tracks coloured by hand (a colour no rule gave them) among `list`.
function TR.hand_coloured(list)
  local n = 0
  for _, tr in ipairs(list or tracks()) do
    if not ours(tr, false) then n = n + 1 end
  end
  return n
end

-- Sets the spacers by the rules (all of them, when any is on).
function TR.spacers(s)
  if not TR.spacers_on(s) then return end
  local all = tracks()
  local deps = {}
  for i, tr in ipairs(all) do deps[i] = depth(tr) end
  local lv = TR.levels(deps)
  local info = {}
  for i, tr in ipairs(all) do
    info[i] = { level = lv[i], parent = deps[i] > 0, fxret = lv[i] == 0 and deps[i] <= 0 and nrecv(tr) > 0, sum = is_sum(tr) }
  end
  local plan = TR.spacer_plan(s, info)
  for i, tr in ipairs(all) do
    local want = plan[i] and 1 or 0
    if math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_SPACER") or 0) ~= want then
      reaper.SetMediaTrackInfo_Value(tr, "I_SPACER", want)
    end
  end
end

-- TS_TrackingMode installed, and in tracking mode now.
function TR.tracking_installed() return (reaper.GetExtState("TS_TrackingMode", "mode") or "") ~= "" end
function TR.tracking_now() return reaper.GetExtState("TS_TrackingMode", "mode") == "1" end

-- Selects the new tracks (the one with the most sends, when one has any)
-- and arms them, by the rules.
function TR.select_arm(new, s)
  if not s.arm or #new == 0 then return end
  local main, most = nil, 0
  for _, tr in ipairs(new) do
    local k = nsends(tr)
    if k > most then main, most = tr, k end
  end
  local target = main and { main } or new
  reaper.Main_OnCommand(40297, 0)            -- Track: Unselect all tracks
  for _, tr in ipairs(target) do reaper.SetTrackSelected(tr, true) end
  if s.arm_tracking and TR.tracking_installed() and not TR.tracking_now() then return end
  if s.disarm then
    for _, tr in ipairs(tracks()) do
      if (reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") or 0) ~= 0 then
        reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
      end
    end
  end
  for _, tr in ipairs(target) do reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1) end
end

-- After ChannelView added `new` (in order): numbering, sorting, colours,
-- spacers, select and arm. `o` = { multi = a template of more than one
-- track, anchor = the track they were added beside, no_select = leave the
-- selection }.
function TR.after_add(new, o)
  o = o or {}
  local s = TR.get()
  local live = {}
  for _, tr in ipairs(new) do
    if reaper.ValidatePtr2(0, tr, "MediaTrack*") then live[#live + 1] = tr end
  end
  new = live
  if #new == 0 then return end
  local folder = parent_of(new[1])
  local leave = left_alone(s, folder)
  if s.number and not leave and not (o.multi and s.keep_multi) then TR.number(new, s) end
  if s.sort ~= "off" and folder and not leave then TR.sort_folder(folder, s.sort) end
  local fresh, list = {}, {}
  for _, tr in ipairs(new) do fresh[tr] = true; list[#list + 1] = tr end
  if o.anchor and reaper.ValidatePtr2(0, o.anchor, "MediaTrack*") then list[#list + 1] = o.anchor end
  TR.colour(list, s, fresh)
  TR.spacers(s)
  if not o.no_select then TR.select_arm(new, s) end
end

-- The menu item's name beside `track`: "Add child from template" or "Add
-- sibling from template", or nil (no track, or the master).
function TR.add_label(track)
  if not track or track == reaper.GetMasterTrack(0) then return nil end
  local k = TR.add_kind_of(track)
  return k == "child" and "Add child from template" or "Add sibling from template"
end

function TR.add_kind_of(track)
  local all = tracks()
  local deps, k = {}, nil
  for i, tr in ipairs(all) do deps[i] = depth(tr); if tr == track then k = i end end
  return TR.add_kind(deps, k)
end

-- The template's tracks beside `anchor` (a child or a sibling, by the
-- rules), as one undo step. Returns the new tracks.
function TR.add_from_template(path, anchor)
  if not path then return nil end
  local s = TR.get()
  local before = tracks()
  local had, deps, k = {}, {}, nil
  for i, tr in ipairs(before) do
    had[tr] = true
    deps[i] = depth(tr)
    if tr == anchor then k = i end
  end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.Main_openProject(path)
  local new = {}
  for _, tr in ipairs(tracks()) do if not had[tr] then new[#new + 1] = tr end end
  if #new == 0 then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: add from template", -1)
    return nil
  end
  local rel = {}
  if s.tfolders == "keep" then
    local nd = {}
    for i, tr in ipairs(new) do nd[i] = depth(tr) end
    rel = TR.rel_levels(nd)
  else
    for i = 1, #new do rel[i] = 0 end
  end
  local at_end = nil
  if not k then at_end = TR.end_index() end
  local pos, _, levels = TR.place(deps, k, rel, s.children == "bottom", at_end)
  local final = {}
  for i = 1, pos do final[#final + 1] = before[i] end
  for _, tr in ipairs(new) do final[#final + 1] = tr end
  for i = pos + 1, #before do final[#final + 1] = before[i] end
  arrange(final, levels)
  TR.after_add(new, { multi = #new > 1, anchor = anchor })
  if not s.arm then
    reaper.Main_OnCommand(40297, 0)
    for _, tr in ipairs(new) do reaper.SetTrackSelected(tr, true) end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: add from template", -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  return new
end

-- A new FX return `tr` (made at the end, its send already made): into the
-- returns folder when the rules say so, then numbered, coloured, spaced.
function TR.after_return(tr)
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return end
  local s = TR.get()
  if s.ret_where == "folder" and (s.ret_folder or "") ~= "" then
    local all = tracks()
    local folder
    for _, t in ipairs(all) do
      if depth(t) > 0 and name_of(t):lower() == s.ret_folder:lower() then folder = t break end
    end
    if folder then
      local rest, deps = {}, {}
      for _, t in ipairs(all) do if t ~= tr then rest[#rest + 1] = t; deps[#deps + 1] = depth(t) end end
      local k
      for i, t in ipairs(rest) do if t == folder then k = i end end
      local pos, _, levels = TR.place(deps, k, { 0 }, true)
      local final = {}
      for i = 1, pos do final[#final + 1] = rest[i] end
      final[#final + 1] = tr
      for i = pos + 1, #rest do final[#final + 1] = rest[i] end
      local sel = {}
      for i = 0, reaper.CountSelectedTracks(0) - 1 do sel[#sel + 1] = reaper.GetSelectedTrack(0, i) end
      arrange(final, levels)
      reaper.Main_OnCommand(40297, 0)
      for _, t in ipairs(sel) do reaper.SetTrackSelected(t, true) end
    end
  end
  local folder = parent_of(tr)
  if s.number and not left_alone(s, folder) then TR.number({ tr }, s) end
  if s.sort ~= "off" and folder and not left_alone(s, folder) then
    local sel = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do sel[#sel + 1] = reaper.GetSelectedTrack(0, i) end
    TR.sort_folder(folder, s.sort)
    reaper.Main_OnCommand(40297, 0)
    for _, t in ipairs(sel) do reaper.SetTrackSelected(t, true) end
  end
  TR.colour({ tr }, s, { [tr] = true })
  TR.spacers(s)
end

-- Every track by the colour and spacer rules (Apply to the project now).
-- `force` recolours tracks coloured by hand too. One undo step.
function TR.apply_all(force)
  local s = TR.get()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  TR.colour(nil, s, nil, force)
  TR.spacers(s)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: apply track rules", -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

-- As tracks are added and moved: once the tracks' order, folders, names
-- or receives change, the colours and spacers are put right. Call once a
-- frame.
local watch = { at = -10, sig = nil }
function TR.tick()
  local now = reaper.time_precise()
  if now - watch.at < 0.5 then return end
  watch.at = now
  local s = TR.get()
  if not s.live or not (TR.colours_on(s) or TR.spacers_on(s)) then watch.sig = nil return end
  local parts = {}
  for _, tr in ipairs(tracks()) do
    parts[#parts + 1] = reaper.GetTrackGUID(tr) .. depth(tr) .. name_of(tr) .. nrecv(tr)
  end
  local sig = table.concat(parts, "|")
  if sig == watch.sig then return end
  watch.sig = sig
  reaper.PreventUIRefresh(1)
  TR.colour(nil, s)
  TR.spacers(s)
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
end

-- ---------------------------------------------------------------------
-- toolbar actions
-- ---------------------------------------------------------------------

local function here()
  return (debug.getinfo(1, "S").source or ""):match("^@?(.*[\\/])") or ""
end

-- A new FX return with the chain at `chain` (its path under FXChains, or
-- full), sent from `src`. One undo step. For the toolbar actions.
function TR.new_return(chain, name, src, full)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local at = TR.end_index()
  reaper.InsertTrackAtIndex(at, true)
  local tr = reaper.GetTrack(0, at)
  if tr then
    if depth(tr) ~= 0 then reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0) end
    set_name(tr, name)
    reaper.TrackFX_AddByName(tr, chain, false, -1)
    if full and reaper.TrackFX_GetCount(tr) == 0 then reaper.TrackFX_AddByName(tr, full, false, -1) end
    if src and src ~= tr then reaper.CreateTrackSend(src, tr) end
    TR.after_return(tr)
  end
  if src then
    reaper.Main_OnCommand(40297, 0)
    reaper.SetTrackSelected(src, true)
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: new FX return " .. name, -1)
  reaper.TrackList_AdjustWindows(false)
  return tr
end

local function lstr(s) return ("%q"):format(s) end

-- Writes and registers an action: kind "template" (add the template beside
-- the selected track) or "return" (a new FX return with the chain, sent
-- from the selected track). Returns the action's name, or nil and why.
function TR.make_action(kind, path, name, full)
  local res = reaper.GetResourcePath()
  local sep = res:find("\\", 1, true) and "\\" or "/"
  local dir = res .. sep .. "Scripts" .. sep .. "TS_ChannelView actions"
  reaper.RecursiveCreateDirectory(dir, 0)
  local title = kind == "template" and ("ChannelView - Add from template - " .. name)
                                   or ("ChannelView - New FX return - " .. name)
  local file = dir .. sep .. title:gsub("[\\/:*?\"<>|]", "_") .. ".lua"
  local call = kind == "template"
    and ("local tr = reaper.GetSelectedTrack(0, 0) or reaper.GetLastTouchedTrack()\nTR.add_from_template(" .. lstr(path) .. ", tr)\n")
    or ("local src = reaper.GetSelectedTrack(0, 0)\nTR.new_return(" .. lstr(path) .. ", " .. lstr(name) .. ", src, " .. lstr(full or path) .. ")\n")
  local text = "-- @noindex\n-- Made by ChannelView (Make toolbar action). Safe to delete.\n" ..
    "package.path = " .. lstr(here() .. "?.lua;") .. " .. package.path\n" ..
    "local TR = require(\"TS_CV_TrackRules\")\n" .. call
  local f = io.open(file, "wb")
  if not f then return nil, "Couldn't write " .. file end
  f:write(text)
  f:close()
  local id = reaper.AddRemoveReaScript(true, 0, file, true)
  if not id or id == 0 then return nil, "Couldn't add it to the action list." end
  return title
end

return TR
