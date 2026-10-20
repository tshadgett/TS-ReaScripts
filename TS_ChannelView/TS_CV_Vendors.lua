-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Vendors.lua -- a look per plugin vendor for the action bars'
  plugin buttons (TS_CV_FXButtons).

  Each vendor can have a colour, initials and a look:
    none      the colour only, shown the way the bar shows colours
    mono      the initials, in a tile in the colour, as the button's icon
    fill      the button's ground in the colour, its icon on top
    prefix    the initials before the label ("IKM - Tape Machine 24")
  A plugin button picks these up from its plugin's vendor, so a new one
  arrives looking right. Anything set on the button itself wins: its own
  colour, and its own PNG icon (a tile never covers one).

  The vendor is the plugin's developer as REAPER's FX browser lists it
  (TS_CV_FXIndex, from reaper-fxtags.ini); JS effects have none. Only
  with no such list does the plugin's name stand in ("Pro-Q 3
  (FabFilter)": the last group in brackets that isn't a channel count).
  "Inc.", "LLC" and the like are dropped, so "iZotope" and "iZotope,
  Inc." are one vendor.

  A vendor can be the same as another ("Brainworx" as "Plugin Alliance"):
  its plugins then take that one's look.

  Kept in ExtState as one line: vendors split by ";", fields by "|":
  name|#rrggbb|initials|look|same as (the last only for one that is).
--]]



local VN = {}

local EXT, KEY = "TS_ChannelView", "vendors"
VN.LOOKS = { "none", "mono", "fill", "prefix" }
VN.LOOK_NAMES = { none = "Colour only", mono = "Initials tile", fill = "Colour fill", prefix = "Prefix" }

-- A wider set than the bars' own colours, for telling a dozen vendors
-- apart; the colour dialog (TS_CV_ColourPick) gives any other.
VN.SUGGEST = {
  "#4aa3df", "#c8453c", "#d98a2f", "#d9be45", "#4f9c62", "#3f74b8", "#8a5cc2", "#d0609a",
  "#2fb3a6", "#9bbf3a", "#e2733c", "#6b7fd6", "#b04a6f", "#7a9cb0", "#c9a77a", "#8d9298",
}

-- ---------------------------------------------------------------------
-- pure
-- ---------------------------------------------------------------------

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local CORP = { ",?%s+[Ii]nc%.?$", ",?%s+LLC%.?$", ",?%s+[Ll]td%.?$", ",?%s+GmbH$", ",?%s+AB$", "%.com$" }

-- A vendor name as one spelling: brackets inside dropped, company
-- endings dropped.
function VN.clean(v)
  v = trim((v or ""):gsub("%s*%b()", ""))
  for _ = 1, 2 do
    for _, p in ipairs(CORP) do v = trim(v:gsub(p, "")) end
  end
  return v
end

local function is_channels(g)
  g = g:lower()
  return g:match("^%d+%s*ch$") or g:match("^%d+%s*%->%s*%d+%s*ch$") or g:match("^%d+%s*out$")
         or g:match("^mono$") or g:match("^stereo$") or g:match("^%d+ in %d+ out$") ~= nil
end

-- The vendor in a plugin's name: its last bracketed group that isn't a
-- channel count ("x (Universal Audio (UADx))" -> "Universal Audio").
function VN.of_name(name)
  local s = trim(name)
  for _ = 1, 4 do
    local head, grp = s:match("^(.-)%s*(%b())$")
    if not grp then return nil end
    local inner = trim(grp:sub(2, -2))
    if not is_channels(inner) then
      local v = VN.clean(inner)
      return v ~= "" and v or nil
    end
    s = head
  end
  return nil
end

-- Initials for a vendor: its capitals ("IK Multimedia" -> "IKM",
-- "FabFilter" -> "FF"), else its first three letters.
function VN.initials(v)
  v = VN.clean(v)
  local caps = v:gsub("[^%u%d]", "")
  if #caps >= 2 then return caps:sub(1, 3) end
  local letters = v:gsub("[^%a]", "")
  return letters:sub(1, 3):upper()
end

function VN.parse(s)
  local out = {}
  for part in (s or ""):gmatch("[^;]+") do
    local name, col, init, look, rest = part:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)(.*)$")
    if name and name ~= "" then
      local same = rest:match("^|([^|]+)$")
      out[#out + 1] = { name = name, color = col:match("^#%x%x%x%x%x%x$") and col:lower() or nil,
                        init = init, look = VN.LOOK_NAMES[look] and look or "none", same = same }
    end
  end
  return out
end

function VN.serialize(vendors)
  local out = {}
  for _, v in ipairs(vendors) do
    local function c(x) return (tostring(x or ""):gsub("[;|]", "")) end
    out[#out + 1] = c(v.name) .. "|" .. (v.color or "") .. "|" .. c(v.init) .. "|" .. (v.look or "none")
                    .. ((v.same and v.same ~= "") and ("|" .. c(v.same)) or "")
  end
  return table.concat(out, ";")
end

-- A colour for a new vendor: the first suggestion not yet used, else the
-- one, from an even spread of hues in three tones, furthest from every
-- colour used. `used`: a list of "#rrggbb".
local function rgb_of(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end
local function hsv(h, sat, val)
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local p, q, t = val * (1 - sat), val * (1 - f * sat), val * (1 - (1 - f) * sat)
  local row = ({ { val, t, p }, { q, val, p }, { p, val, t }, { p, q, val }, { t, p, val }, { val, p, q } })[i + 1]
  local r, g, b = row[1], row[2], row[3]
  return ("#%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
local SPREAD = nil
function VN.next_colour(used)
  local taken = {}
  for _, c in ipairs(used) do taken[c] = true end
  for _, c in ipairs(VN.SUGGEST) do if not taken[c] then return c end end
  if not SPREAD then
    SPREAD = {}
    for _, tone in ipairs({ { 0.62, 0.86 }, { 0.45, 0.70 }, { 0.40, 0.95 } }) do
      for k = 0, 23 do SPREAD[#SPREAD + 1] = hsv(k / 24, tone[1], tone[2]) end
    end
  end
  local best, far = SPREAD[1], -1
  for _, c in ipairs(SPREAD) do
    if not taken[c] then
      local r, g, b = rgb_of(c)
      local near = math.huge
      for _, u in ipairs(used) do
        local ur, ug, ub = rgb_of(u)
        local d = (r - ur) ^ 2 * 0.3 + (g - ug) ^ 2 * 0.59 + (b - ub) ^ 2 * 0.11
        if d < near then near = d end
      end
      if near > far then best, far = c, near end
    end
  end
  return best
end

-- How a button shows, given its own fields and its vendor's settings
-- (nil for none): { color, label, mono, fill }. The label is the button's
-- own text (`text`), prefixed when the look asks and it isn't already.
function VN.apply(it, text, v)
  local out = { color = it.color, label = text, mono = nil, fill = false }
  if not v then return out end
  if not (it.color and it.color ~= "") then out.color = v.color end
  local init = (v.init and v.init ~= "") and v.init or nil
  if v.look == "prefix" and init then
    local p = init .. " - "
    if text:sub(1, #p) ~= p then out.label = p .. text end
  elseif v.look == "mono" and init then
    local png = it.icon and it.icon ~= "" and not it.icon:match("^cv:")
    if not png then out.mono = init end
  elseif v.look == "fill" then
    out.fill = out.color ~= nil
  end
  return out
end

-- ---------------------------------------------------------------------
-- stored
-- ---------------------------------------------------------------------

local list, by_key, read_at, stamp = nil, nil, -1, nil

local function index()
  by_key = {}
  for _, v in ipairs(list) do by_key[VN.clean(v.name):lower()] = v end
end

-- Re-read at most once a second: the toolbars window, the TCP and the
-- web bridge each keep their own copy.
function VN.load(force)
  local now = reaper.time_precise()
  if not force and list and now - read_at < 1.0 then return list end
  read_at = now
  local s = reaper.GetExtState(EXT, KEY)
  if s ~= stamp or not list then
    stamp = s
    list = VN.parse(s)
    index()
  end
  return list
end

function VN.save()
  local s = VN.serialize(list or {})
  reaper.SetExtState(EXT, KEY, s, true)
  stamp, read_at = s, reaper.time_precise()
  index()
end

-- A vendor's own entry, as stored (one that is the same as another too).
function VN.entry(name)
  if not name then return nil end
  VN.load()
  return by_key[VN.clean(name):lower()]
end

-- The settings a vendor's plugins show with: its own, or those of the
-- vendor it is the same as.
function VN.get(name)
  local v = VN.entry(name)
  if v and v.same then return VN.entry(v.same) end
  return v
end

local function add(name)
  local used = {}
  for _, x in ipairs(list) do if x.color and not x.same then used[#used + 1] = x.color end end
  local v = { name = VN.clean(name), color = VN.next_colour(used), init = VN.initials(name), look = "none" }
  list[#list + 1] = v
  return v
end

-- The vendor's settings, made when missing, with initials and a colour
-- not already taken.
function VN.ensure(name)
  VN.load()
  local v = VN.entry(name)
  if v then return v end
  v = add(name)
  VN.save()
  return v
end

-- Every vendor in `names` not yet set up, set up, in one save.
function VN.ensure_all(names)
  VN.load()
  local n = 0
  for _, name in ipairs(names) do
    if not VN.entry(name) then add(name); n = n + 1 end
  end
  if n > 0 then VN.save() end
  return n
end

-- Vendor `name` takes the look of `other` (nil: its own again, a fresh
-- one).
function VN.same_as(name, other)
  VN.load()
  local v = VN.entry(name)
  if other then
    if VN.clean(other):lower() == VN.clean(name):lower() then return end
    if not v then
      v = { name = VN.clean(name), init = VN.initials(name), look = "none" }
      list[#list + 1] = v
    end
    v.same = VN.clean(other)
    -- nothing may point at it now: those follow it to `other`
    for _, x in ipairs(list) do
      if x.same and VN.clean(x.same):lower() == VN.clean(name):lower() then x.same = v.same end
    end
  elseif v then
    v.same = nil
    if not v.color then
      local used = {}
      for _, x in ipairs(list) do if x.color and x ~= v and not x.same then used[#used + 1] = x.color end end
      v.color = VN.next_colour(used)
    end
  end
  VN.save()
end

function VN.remove(name)
  VN.load()
  local k = VN.clean(name):lower()
  for i = #list, 1, -1 do
    local v = list[i]
    -- the vendors that were the same as it go too
    if VN.clean(v.name):lower() == k or (v.same and VN.clean(v.same):lower() == k) then table.remove(list, i) end
  end
  VN.save()
end

function VN.list()
  return VN.load()
end

-- ---------------------------------------------------------------------
-- a plugin button's vendor
-- ---------------------------------------------------------------------

local ident_vendor = nil      -- ident -> vendor, from REAPER's plugin list
local installed = nil         -- clean lower name -> { name, n }

-- A plugin's vendor: REAPER's developer for it, cleaned; with no
-- developer list at all, the one in its name.
local function vendor_of(ident, name)
  local IX = require("TS_CV_FXIndex")
  if IX.tagged() then
    local d = IX.dev_of(ident)
    d = d and VN.clean(d)
    return (d and d ~= "") and d or nil
  end
  return VN.of_name(name or ident)
end

-- REAPER's list of installed plugins, read once: each plugin's vendor,
-- and every vendor with how many plugins (a plugin in two formats counts
-- twice).
local function read_installed()
  if ident_vendor then return end
  ident_vendor, installed = {}, {}
  local i = 0
  while reaper.EnumInstalledFX do
    local ok, name, id = reaper.EnumInstalledFX(i)
    if not ok then break end
    if id and name then
      local v = vendor_of(id, name)
      ident_vendor[id] = v or false
      if v then
        local k = v:lower()
        local e = installed[k]
        if not e then e = { name = v, n = 0 }; installed[k] = e end
        e.n = e.n + 1
      end
    end
    i = i + 1
    if i > 30000 then break end
  end
end

-- Reads REAPER's plugin list again next time (plugins installed since,
-- developers changed in REAPER's FX browser).
function VN.rescan()
  ident_vendor, installed = nil, nil
  require("TS_CV_FXIndex").reset()
end

-- Every vendor among the installed plugins: { name, n } by name.
function VN.installed()
  read_installed()
  local out = {}
  for _, e in pairs(installed) do out[#out + 1] = e end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- The vendor of a plugin identifier (what a plugin button stores), from
-- REAPER's list of installed plugins.
function VN.of_ident(ident)
  if not ident then return nil end
  read_installed()
  local v = ident_vendor[ident]
  if v == nil then v = vendor_of(ident, ident) end    -- not installed now
  return v or nil
end

-- Every vendor among the plugin buttons in `items` (menus opened out),
-- into `seen` (vendor -> count).
function VN.collect(items, seen, kind_of)
  for _, it in ipairs(items or {}) do
    if it.menu then
      VN.collect(it.items, seen, kind_of)
    else
      local k, what = kind_of(it)
      if k == "fx" then
        local v = VN.of_ident(what)
        if v then seen[v] = (seen[v] or 0) + 1 end
      end
    end
  end
  return seen
end

return VN
