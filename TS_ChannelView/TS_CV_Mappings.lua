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
      Meter    = <1|0>|<full-scale dB>[|<trace window: 4b, 2s ...>]
      Live     = 1
      Style<n> = <style>|<cap colour>
      Size<n>  = small | large
      Buttons<n> = across | down | <how many>
      Plate    = <faceplate>
      Brush    = <1|0>

  <type> is knob | toggle | combo | fader | blank | divider | half_gap.
  "blank" is a deliberate empty cell, so a layout can leave a gap where a
  hardware strip would have one; "divider" ends the current column and,
  by default, draws a rule separating one group of controls from the
  next -- bit 2 of the bipolar field (see below) turns the rule off
  while keeping the column break, for pure spacing between groups that
  don't need a line between them. "half_gap" staggers the control that
  follows it half a row down, to mimic the staggered knob layouts some
  hardware (and hardware-emulation plugins) use -- see P.layout in
  TS_CV_Panel.lua for how. Column flow only ("row"-flow panels ignore
  it). "fader" is a real parameter, same as knob or toggle, just drawn
  as a vertical slider that claims a whole column to itself at the
  panel's full height rather than one CELL_H cell -- see P.layout for
  how it forces a fresh column the same way a divider does.

  An ALIAS renames a parameter for this plugin everywhere -- on every
  panel and in the editor's lists -- which is the fix for plugins whose
  own parameter names are cryptic or inconsistent. It applies whether or
  not that parameter is currently on a panel. The per-control <label> is a
  narrower thing: an override for one slot only, for when the same
  parameter needs a shorter caption in a cramped layout. Resolution order
  is label, then alias, then whatever the plugin calls it.

  MEASURE (Measure=1) is for plugins that don't report their own gain
  reduction: ChannelView routes a before-and-after copy of every instance
  of the plugin that sits between a TS_TrackProbe pair to the post probe,
  which measures it. See TS_CV_Taps.lua.

  LEVELS (Levels=1) puts input and output meters on the plugin's panel,
  from the same before-and-after copies: any plugin, reporting or not.

  LIVE names are for plugins that rename their own parameters as you use
  them -- Softube Console 1 and Flow name their macros after whatever is
  loaded into them. A saved label or alias would freeze whatever the name
  was on the day. Live=1 makes every control on the panel show what the
  plugin calls its parameter right now; bit 3 of the flags field does the
  same for one slot. Either way the label and alias are kept, just not
  shown, so turning live off brings them back.

  STYLE and PLATE are the hardware look (see "Hardware styles" in
  TS_CV_Config.lua). Style<n> belongs to control n, the same index as its
  Ctl<n> line, and holds the knob or fader style and the cap colour,
  either of which may be empty for "the default". It is a line of its own
  rather than more fields on Ctl<n> because the label is the LAST field of
  that line and takes everything after it -- an older ChannelView reading
  a fifth field would have shown it as part of the name. Plate is the
  panel's faceplate. Both are names, not colours, so the palette they
  name can be retuned without touching anyone's layouts. Brush turns the
  brushed grain on (1) or off (0) for that faceplate; with no Brush line
  it is the faceplate's own (on for aluminium, off for the rest). Size<n>
  makes knob n small or large (C.SIZES in TS_CV_Config.lua); with no Size
  line it is the ordinary size, and an older ChannelView ignores the line.
  Buttons<n> shows dropdown n as buttons -- across or down -- and keeps
  how many choices it had, which is how much room the buttons take.

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
                .. "; Meter=<1 on, 0 off>|<full-scale dB for the gain-reduction strip>\n"
                .. "; Live=1: every control shows the plugin's current name for its\n"
                .. ";   parameter (flags bit 8 does the same for one slot)\n"
                .. "; Style<n>=<knob or fader style>|<cap colour>, for control n (a toggle: |<lit colour>)\n"
                .. "; Size<n>=small|large: knob n's size (no line: medium)\n"
                .. "; Plate=<faceplate>\n"
                .. "; Brush=<1 brushed, 0 plain>: the faceplate's grain, when not its own"

local dir         = nil
local sections    = {}   -- raw ini table
local order       = {}   -- section order as read from disk
local cache       = {}   -- plugin_key -> parsed layout
local def_cache   = {}   -- fx guid -> generated default layout
local dirty       = false

local VALID_TYPE = { knob = true, toggle = true, combo = true, stepped = true,
                     fader = true, blank = true, divider = true, half_gap = true }

-- ---------------------------------------------------------------------

local function path()      return dir .. FILE_NAME end
local function bak_path()  return dir .. BAK_NAME  end

-- A knob size worth keeping: small or large. Medium, nothing or anything
-- unknown is the ordinary size, which is no size at all.
local function size_of(v)
  v = U.trim(v or "")
  if v ~= "medium" and C.SIZES[v] then return v end
  return nil
end

-- Buttons<n>=across|4: a dropdown shown as a row (or column) of buttons,
-- and how many choices it had when that was chosen -- the count sets how
-- much room the row takes, and the layout has to know that without
-- asking the plugin. Anything else is the ordinary dropdown.
local function buttons_of(v)
  local d = U.trim(v or ""):match("^(%a+)")
  return (d == "across" or d == "down") and d or nil
end
local function nbtn_of(v)
  local n = tonumber(U.trim(v or ""):match("|%s*(%d+)"))
  return (n and n >= 2 and n <= C.BUTTONS_MAX) and n or nil
end

-- Brush=1 / Brush=0, or nil for none set (the faceplate's own grain).
local function brush_of(v)
  v = U.trim(v or "")
  if v == "1" then return true end
  if v == "0" then return false end
  return nil
end

-- Whether a layout's faceplate is drawn brushed: its own choice if it made
-- one, else the faceplate's.
function M.brushed(layout, plate)
  if not plate then return false end
  if layout and layout.brush ~= nil then return layout.brush end
  return plate.brushed or false
end

local function parse_section(sect)
  local controls, aliases, states = {}, {}, {}
  local meter = nil
  if sect.Meter then
    local on, range, win = sect.Meter:match("^%s*(%d)%s*|?%s*([%d%.]*)%s*|?%s*(%w*)")
    if on then
      meter = { on = (on == "1"), range = tonumber(range) or C.MAX_GR_DB,
                win = (win and win:match("^%d+[bs]$")) and win or nil }
    end
  end
  for k, v in pairs(sect) do
    local p = k:match("^Alias(%d+)$")
    if p then aliases[tonumber(p)] = U.trim(v) end
    local sp = k:match("^States(%d+)$")
    if sp then
      local off, on = v:match("^([^|]*)|(.*)$")
      if off then states[tonumber(sp)] = { U.trim(off), U.trim(on) } end
    end
  end
  local i = 0
  while true do
    local raw = sect["Ctl" .. i]
    if not raw then break end
    -- The type field may contain letters and underscores (e.g.
    -- "half_gap"), so the character class has to allow both.
    local p, t, bi, label = raw:match("^%s*(-?%d+)%s*|%s*([%a_]*)%s*|%s*(%d*)%s*|?(.*)$")
    if p then
      t = (t ~= "" and VALID_TYPE[t]) and t or "knob"
      -- Field three is a bitmask: bit 0 is bipolar (its original,
      -- sole meaning, so a layout written before reverse existed still
      -- reads back the same), bit 1 is reverse, bit 2 is "no rule" --
      -- for a divider only, it still ends the column and opens the same
      -- C.DIVIDER_W gap, just without the line. Bit 2 is unused (and
      -- unset) on every other type, the same as bits 0/1 already are on
      -- blank and divider -- one flags field for the whole slot, read
      -- differently by whichever type it's on. The label is always
      -- field four, present but allowed to be empty, so it never gets
      -- confused with the flags field regardless of which bits are set.
      local f = tonumber(bi) or 0
      local sty, cap = (sect["Style" .. i] or ""):match("^%s*([%w_]*)%s*|?%s*([%w_]*)")
      controls[#controls + 1] = {
        param   = tonumber(p),
        type    = t,
        bipolar = (f & 1) ~= 0,
        invert  = (f & 2) ~= 0,
        no_rule = (f & 4) ~= 0,
        live    = (f & 8) ~= 0,
        label   = U.trim(label),
        style   = (sty and sty ~= "") and (C.KNOB_STYLE_ALIAS[sty] or sty) or nil,
        cap     = (cap and cap ~= "") and cap or nil,
        size    = size_of(sect["Size" .. i]),
        buttons = buttons_of(sect["Buttons" .. i]),
        nbtn    = nbtn_of(sect["Buttons" .. i]),
      }
    end
    i = i + 1
  end
  return { controls = controls, aliases = aliases, states = states, meter = meter,
           live = (U.trim(sect.Live or "") == "1") or nil,
           measure = (U.trim(sect.Measure or "") == "1") or nil,
           levels = (U.trim(sect.Levels or "") == "1") or nil,
           plate = C.plate_of(U.trim(sect.Plate or "")) and U.trim(sect.Plate) or nil,
           brush = brush_of(sect.Brush) }
end

local function serialize(layout)
  local out = {}
  if layout.live then out.Live = "1" end
  if layout.measure then out.Measure = "1" end
  if layout.levels then out.Levels = "1" end
  if layout.plate then out.Plate = layout.plate end
  if layout.brush ~= nil then out.Brush = layout.brush and "1" or "0" end
  if layout.meter then
    out.Meter = string.format("%d|%g", layout.meter.on and 1 or 0,
                              layout.meter.range or C.MAX_GR_DB)
      .. (layout.meter.win and ("|" .. layout.meter.win) or "")
  end
  for p, name in pairs(layout.aliases or {}) do
    if U.trim(name) ~= "" then
      out["Alias" .. p] = (name:gsub("[\r\n]", " "))
    end
  end
  for p, st in pairs(layout.states or {}) do
    local off, on = U.trim(st[1] or ""), U.trim(st[2] or "")
    if off ~= "" or on ~= "" then
      out["States" .. p] = off:gsub("[|\r\n]", " ") .. "|" .. on:gsub("[|\r\n]", " ")
    end
  end
  for i, c in ipairs(layout.controls or {}) do
    -- See parse_section: bit 0 bipolar, bit 1 reverse, bit 2 no-rule,
    -- bit 3 live name.
    local flags = (c.bipolar and 1 or 0) | (c.invert and 2 or 0)
                | (c.no_rule and 4 or 0) | (c.live and 8 or 0)
    out["Ctl" .. (i - 1)] = string.format("%d|%s|%d|%s",
      c.param or -1,
      c.type or "knob",
      flags,
      (c.label or ""):gsub("[|\r\n]", " "))
    if c.style or c.cap then
      out["Style" .. (i - 1)] = (c.style or "") .. "|" .. (c.cap or "")
    end
    if size_of(c.size) then out["Size" .. (i - 1)] = c.size end
    if c.buttons and (c.buttons == "across" or c.buttons == "down") and c.nbtn then
      out["Buttons" .. (i - 1)] = c.buttons .. "|" .. math.floor(c.nbtn)
    end
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

-- Whether any plugin in the library is set to have its gain reduction or
-- its levels measured (see TS_CV_Taps). Straight off the raw sections, so
-- it costs a walk of the library rather than a parse of every layout in it.
function M.any_measure()
  for _, s in pairs(sections) do
    if U.trim(s.Measure or "") == "1" or U.trim(s.Levels or "") == "1" then
      return true
    end
  end
  return false
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
      label   = "",      -- the plugin's own name shows by itself; a label would hide an alias
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
    return { on = true, range = m.range or C.MAX_GR_DB, win = m.win }
  end
  return nil
end

function M.set_meter(layout, on, range)
  layout.meter = { on = on and true or false,
                   range = range or (layout.meter and layout.meter.range)
                           or C.MAX_GR_DB,
                   win = layout.meter and layout.meter.win or nil }
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

-- State names: your own words for a toggle's two states ("Off"/"Auto"
-- instead of the plugin's "0.0"/"1.0"), per plugin, per parameter, like an
-- alias. Stored as States<param>=<off name>|<on name>; either may be empty,
-- and an empty one leaves the plugin's own text.
function M.get_states(key, param)
  local l = M.get(key)
  local st = l and l.states and l.states[param]
  if st and ((st[1] or "") ~= "" or (st[2] or "") ~= "") then return st end
  return nil
end

function M.set_states(key, param, off, on)
  local l = M.get(key) or { controls = {}, aliases = {} }
  l.states = l.states or {}
  off, on = U.trim(off or ""), U.trim(on or "")
  l.states[param] = (off ~= "" or on ~= "") and { off, on } or nil
  M.set(key, l)
end

-- What a toggle shows for the plugin's own value `raw` (0..1, before any
-- reverse): the state's name if one is set, else the plugin's text `shown`.
function M.state_text(key, param, raw, shown)
  local st = M.get_states(key, param)
  if not st then return shown end
  local name = ((raw or 0) >= 0.5) and st[2] or st[1]
  return (name and name ~= "") and name or shown
end

-- What a toggle's button should SAY, or nil for plain ON / OFF: your name
-- for the state it's in if you've given one, else the plugin's own word
-- for it ("Thrust", "Normal", "Link") -- but not when the plugin only has
-- a number for it ("0.0", "1.00", "100 %", "-inf dB"), which says less
-- than ON / OFF does.
function M.button_text(key, param, raw, shown)
  local st = M.get_states(key, param)
  if st then
    local name = ((raw or 0) >= 0.5) and st[2] or st[1]
    if name and name ~= "" then return name end
  end
  local s = U.trim(shown or "")
  if s == "" then return nil end
  local low = s:lower()
  if low:match("^[%-%+]?%d*%.?%d") or low:match("^[%-%+]?inf") then return nil end
  return s
end

-- What a parameter should be called, most specific first: a slot's own
-- label, then the plugin-wide alias, then the plugin's own name for it --
-- or, when `live` (the slot's or the whole layout's), the plugin's own
-- name regardless.
function M.display_name(key, param, slot_label, plugin_name, live)
  if live then
    local n = plugin_name and U.trim(plugin_name) or ""
    return (n ~= "") and n or ("P" .. tostring(param))
  end
  -- A label that's only the plugin's own name for the parameter says
  -- nothing of its own -- layouts before 1.7.5 filled every slot with one
  -- -- so it doesn't hide the alias.
  local own = plugin_name and U.trim(plugin_name) or ""
  if slot_label and slot_label ~= "" and U.trim(slot_label) ~= own then return slot_label end
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

-- Writes the library, keeping one generation of backup: this file is the
-- only place a hand-built layout lives, so a failed or interrupted write
-- should not be able to take it out entirely.
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
  local out = { controls = {}, aliases = {}, live = layout.live,
                measure = layout.measure, levels = layout.levels,
                plate = layout.plate, brush = layout.brush }
  if layout.meter then
    out.meter = { on = layout.meter.on, range = layout.meter.range, win = layout.meter.win }
  end
  for i, c in ipairs(layout.controls or {}) do
    out.controls[i] = { param = c.param, type = c.type, bipolar = c.bipolar,
                        invert = c.invert, no_rule = c.no_rule, live = c.live,
                        label = c.label, style = c.style, cap = c.cap, size = c.size,
                        buttons = c.buttons, nbtn = c.nbtn }
  end
  for p, n in pairs(layout.aliases or {}) do out.aliases[p] = n end
  out.states = {}
  for p, st in pairs(layout.states or {}) do out.states[p] = { st[1], st[2] } end
  return out
end

return M
