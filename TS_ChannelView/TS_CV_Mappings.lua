-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Mappings.lua -- the layout library.

  One layout per PLUGIN TYPE, shared by every instance of that plugin in
  every project. Editing DF-SMACK's panel on one track changes it
  everywhere, which is the point: you set a plugin up once and it always
  looks the same wherever it turns up.

  Stored in TS_ChannelView_Mappings.ini beside this script, in a format
  that's readable and hand-editable:

      [DF-SMACK]
      Ctl0=1|knob|0|Input
      Ctl1=2|knob|0|Output
      Ctl2=9|toggle|0|Power

      Ctl<n>   = <param index>|<type>|<bipolar>|<label>
      Alias<p> = <your name for parameter p>
      Meter    = <1|0>|<full-scale dB>

  <type> is knob | toggle | combo | blank | divider.  "blank" is a
  deliberate empty cell, so a layout can leave a gap where a hardware strip
  would have one; "divider" ends the current column and draws a rule,
  separating one group of controls from the next.

  An ALIAS renames a parameter for this plugin everywhere -- on every
  panel and in the editor's lists -- which is the fix for plugins whose
  own parameter names are cryptic or inconsistent. It applies whether or
  not that parameter is currently on a panel. The per-control <label> is a
  narrower thing: an override for one slot only, for when the same
  parameter needs a shorter caption in a cramped layout. Resolution order
  is label, then alias, then whatever the plugin calls it.

  METER turns the gain-reduction strip on for this plugin and sets its
  full-scale range. It sits at the layout level rather than in the control
  list because a plugin has exactly one gain reduction, not one per
  parameter -- it's a property of the panel, not a slot in it. The range
  is per plugin because a bus compressor and a limiter want very different
  scales.
--]]

local U = require("TS_CV_Util")
local C = require("TS_CV_Config")

local M = {}

local FILE_NAME  = "TS_ChannelView_Mappings.ini"
local BAK_NAME   = "TS_ChannelView_Mappings.bak.ini"
local HEADER     = "; ChannelView layout library -- one section per plugin.\n"
                .. "; Ctl<n>=<param index>|<type>|<bipolar 0|1>|<label>\n"
                .. ";   type: knob | toggle | combo | blank\n"
                .. ";   label overrides the alias for that one slot only\n"
                .. "; Alias<param>=<your name for that parameter, used everywhere>\n"
                .. "; Meter=<1 on, 0 off>|<full-scale dB for the gain-reduction strip>"

local dir         = nil
local sections    = {}   -- raw ini table
local order       = {}   -- section order as read from disk
local cache       = {}   -- plugin_key -> parsed layout
local def_cache   = {}   -- fx guid -> generated default layout
local dirty       = false

local VALID_TYPE = { knob = true, toggle = true, combo = true,
                     blank = true, divider = true }

-- ---------------------------------------------------------------------

local function path()      return dir .. FILE_NAME end
local function bak_path()  return dir .. BAK_NAME  end

local function parse_section(sect)
  local controls, aliases = {}, {}
  local meter = nil
  if sect.Meter then
    local on, range = sect.Meter:match("^%s*(%d)%s*|?%s*([%d%.]*)")
    if on then
      meter = { on = (on == "1"), range = tonumber(range) or C.MAX_GR_DB }
    end
  end
  for k, v in pairs(sect) do
    local p = k:match("^Alias(%d+)$")
    if p then aliases[tonumber(p)] = U.trim(v) end
  end
  local i = 0
  while true do
    local raw = sect["Ctl" .. i]
    if not raw then break end
    local p, t, bi, label = raw:match("^%s*(-?%d+)%s*|%s*(%a*)%s*|%s*(%d*)%s*|?(.*)$")
    if p then
      t = (t ~= "" and VALID_TYPE[t]) and t or "knob"
      controls[#controls + 1] = {
        param   = tonumber(p),
        type    = t,
        bipolar = (bi == "1"),
        label   = U.trim(label),
      }
    end
    i = i + 1
  end
  return { controls = controls, aliases = aliases, meter = meter }
end

local function serialize(layout)
  local out = {}
  if layout.meter then
    out.Meter = string.format("%d|%g", layout.meter.on and 1 or 0,
                              layout.meter.range or C.MAX_GR_DB)
  end
  for p, name in pairs(layout.aliases or {}) do
    if U.trim(name) ~= "" then
      out["Alias" .. p] = (name:gsub("[\r\n]", " "))
    end
  end
  for i, c in ipairs(layout.controls or {}) do
    out["Ctl" .. (i - 1)] = string.format("%d|%s|%d|%s",
      c.param or -1,
      c.type or "knob",
      c.bipolar and 1 or 0,
      (c.label or ""):gsub("[|\r\n]", " "))
  end
  return out
end

-- ---------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------

function M.init(script_dir)
  dir = script_dir
  M.reload()
end

function M.reload()
  sections, order = U.read_ini(path())
  cache = {}
  def_cache = {}
  dirty = false
end

-- Generated defaults are cached per FX instance: building one walks every
-- parameter name, which is far too much to redo 30 times a second for a
-- plugin nobody has set up yet. The chain rescan clears this.
function M.clear_default_cache() def_cache = {} end

function M.file_path() return path() end

function M.has(key)
  return sections[key] ~= nil
end

-- The saved layout for a plugin, or nil if it has never been set up.
function M.get(key)
  if cache[key] then return cache[key] end
  local s = sections[key]
  if not s then return nil end
  cache[key] = parse_section(s)
  return cache[key]
end

-- A layout to draw right now: the saved one, or a generated default that
-- is NOT written to disk until the user actually edits and saves it.
-- That way an unconfigured plugin still shows something useful without
-- silently filling the library with machine-made layouts.
function M.get_or_default(key, track, addr, cache_id)
  local saved = M.get(key)
  if saved then return saved, false end
  local id = cache_id or (tostring(addr) .. ":" .. key)
  local d = def_cache[id]
  if not d then
    d = M.build_default(track, addr)
    def_cache[id] = d
  end
  return d, true
end

function M.build_default(track, addr)
  local controls = {}
  local own, total = U.own_param_count(track, addr)
  local limit = C.HIDE_BUILTIN and own or total
  local n = math.min(limit, C.AUTO_DEFAULT_N)
  for p = 0, n - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, p, "")
    controls[#controls + 1] = {
      param   = p,
      type    = U.guess_control_type(track, addr, p),
      bipolar = U.guess_bipolar(nm, track, addr, p),
      label   = U.trim(nm),
    }
  end
  -- A compressor that reports gain reduction gets its meter by default.
  -- This is only the generated starting point -- nothing reaches the
  -- library until the layout is saved, and the panel menu turns it off.
  local T = require("TS_CV_FXTree")
  local meter = nil
  if T.reports_gr(track, addr, nil) then
    meter = { on = true, range = C.MAX_GR_DB }
  end
  return { controls = controls, aliases = {}, meter = meter }
end

-- The meter settings a panel should use, or nil for no meter.
function M.meter_of(layout)
  local m = layout and layout.meter
  if m and m.on then
    return { on = true, range = m.range or C.MAX_GR_DB }
  end
  return nil
end

function M.set_meter(layout, on, range)
  layout.meter = { on = on and true or false,
                   range = range or (layout.meter and layout.meter.range)
                           or C.MAX_GR_DB }
end

-- ---------------------------------------------------------------------
-- aliases: a per-plugin rename of a parameter, independent of whether it
-- is currently on a panel.
-- ---------------------------------------------------------------------

function M.get_alias(key, param)
  local l = M.get(key)
  local a = l and l.aliases and l.aliases[param]
  if a and a ~= "" then return a end
  return nil
end

-- Writes straight through to the library: an alias is a fact about the
-- plugin, not part of an edit session that might be cancelled.
function M.set_alias(key, param, name)
  local l = M.get(key)
  if not l then
    l = { controls = {}, aliases = {} }
  end
  l.aliases = l.aliases or {}
  name = U.trim(name or "")
  l.aliases[param] = (name ~= "") and name or nil
  M.set(key, l)
end

-- What a parameter should be called, most specific first: a slot's own
-- label, then the plugin-wide alias, then the plugin's own name for it.
function M.display_name(key, param, slot_label, plugin_name)
  if slot_label and slot_label ~= "" then return slot_label end
  local a = M.get_alias(key, param)
  if a then return a end
  return plugin_name or ("P" .. tostring(param))
end

function M.set(key, layout)
  def_cache = {}
  cache[key] = layout
  sections[key] = serialize(layout)
  local found = false
  for _, s in ipairs(order) do if s == key then found = true break end end
  if not found then order[#order + 1] = key end
  dirty = true
end

function M.remove(key)
  def_cache = {}
  cache[key] = nil
  sections[key] = nil
  for i = #order, 1, -1 do if order[i] == key then table.remove(order, i) end end
  dirty = true
end

-- Writes the library, keeping one generation of backup -- the same
-- safety net StripLink's connector has, for the same reason: this file is
-- the only place a hand-built layout lives.
function M.save()
  if not dirty then return true end
  local src = io.open(path(), "rb")
  if src then
    local data = src:read("a"); src:close()
    local bak = io.open(bak_path(), "wb")
    if bak then bak:write(data); bak:close() end
  end
  local ok, err = U.write_ini(path(), sections, order, HEADER)
  if ok then dirty = false end
  return ok, err
end

-- Deep copy, so the editor can work on a scratch layout and discard it.
function M.copy(layout)
  local out = { controls = {}, aliases = {} }
  if layout.meter then
    out.meter = { on = layout.meter.on, range = layout.meter.range }
  end
  for i, c in ipairs(layout.controls or {}) do
    out.controls[i] = { param = c.param, type = c.type, bipolar = c.bipolar, label = c.label }
  end
  for p, n in pairs(layout.aliases or {}) do out.aliases[p] = n end
  return out
end

return M
