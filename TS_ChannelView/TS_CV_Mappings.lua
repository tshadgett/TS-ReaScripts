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
      Back<n>  = inset | <faceplate>
      Brush<n> = <1|0>
      Metal<n> = 1
      Scale<n> = values | ten [|cap]
      Plate    = <faceplate>
      Brush    = <1|0>
      Metal    = 1
      Lock     = <rows>

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
  name can be retuned without touching anyone's layouts -- except a
  custom faceplate, which is its colour, #rrggbb (wherever a faceplate
  goes: Plate, Back<n>, a section's Style<n>=plate|#rrggbb). Brush turns the
  brushed grain on (1) or off (0) for that faceplate; with no Brush line
  it is the faceplate's own (on for aluminium, off for the rest). Size<n>
  makes knob n small or large (C.SIZES in TS_CV_Config.lua); with no Size
  line it is the ordinary size, and an older ChannelView ignores the line.
  Buttons<n> shows dropdown n as buttons -- across or down -- and keeps
  how many choices it had, which is how much room the buttons take.
  Back<n> is control n's own background, an inset or a faceplate, drawn
  over its section's; neighbours with the same one join into one shape.
  Brush<n> turns the brushed grain on (1) or off (0) for control n's
  background -- on a divider, for the section it styles. With no line it
  is the faceplate's own (on for aluminium), and off for an inset.
  Metal<n>=1 gives that background (or section) a metallic flake, and
  Metal=1 the faceplate; either can go with the brushed grain, or alone.
  Scale<n> numbers knob n's scale: "values" prints the plugin's own values
  at its marks, "ten" 0 to 10; "|cap" prints them in the cap's colour.
  Medium and large knobs only (a small one has no room).

  LOCK freezes the layout: no edits, and the controls keep the arrangement
  they had at <rows> rows however tall the panel is -- a shorter panel
  scrolls instead of reflowing. Meters are not part of it: they can still
  be switched on and off, and the trace opened, while locked.

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
                .. "; Back<n>=inset|<faceplate>: control n's own background\n"
                .. "; Brush<n>=<1|0>: grain on control n's background (a divider: its section's)\n"
                .. "; Metal<n>=1: metallic flake on control n's background (a divider: its section's)\n"
                .. "; Scale<n>=values|ten[|cap]: numbers round knob n (its own values, or 0-10)\n"
                .. "; Plate=<faceplate, or #rrggbb for a colour of your own>\n"
                .. "; Brush=<1 brushed, 0 plain>: the faceplate's grain, when not its own\n"
                .. "; Metal=1: a metallic flake on the faceplate\n"
                .. "; Lock=<rows>: layout locked, arranged at that many rows"

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

-- Back<n>=inset or a faceplate's key: a control's own background.
local function back_of(v)
  v = U.trim(v or "")
  if v == "inset" then return v end
  return C.plate_key(v)
end

-- Scale<n>=values|ten|none[|cap]: what knob n's scale is numbered with,
-- and whether in the cap's colour. With no line a knob shows its values
-- (the default since 1.8.5, layouts saved before it included); "none"
-- is the only way to have no numbers.
local function scale_of(v)
  local k = U.trim(v or ""):match("^(%a+)")
  return (k == "values" or k == "ten" or k == "none") and k or nil
end
local function scale_ink_of(v)
  local k = scale_of(v)
  return (k and k ~= "none" and U.trim(v or ""):match("|%s*cap%s*$")) and "cap" or nil
end

-- What control c's scale is numbered with: "values" (the default), "ten",
-- or nil for none. Knobs and stepped knobs only.
function M.scale_kind(c)
  if not c or (c.type ~= "knob" and c.type ~= "stepped" and c.type ~= nil) then return nil end
  if c.scale == "none" then return nil end
  return (c.scale == "ten") and "ten" or "values"
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

-- Lock=<rows>: a locked layout's frozen row count, or nil.
local function lock_of(v)
  local n = tonumber(U.trim(v or ""))
  return (n and n >= 1 and n <= 64) and math.floor(n) or nil
end

-- The row count a locked layout keeps, or nil when it isn't locked.
function M.locked(layout) return layout and layout.lock or nil end

-- Whether a layout's faceplate has the metallic flake (Metal=1).
function M.metal(layout, plate)
  return (plate ~= nil and layout ~= nil and layout.metal == true) or false
end
-- ... and a control's background, or a divider's section (Metal<n>=1).
function M.part_metal(kind, metal)
  return (kind ~= nil and metal == true) or false
end

-- Whether a control's background, or a divider's section, is brushed:
-- `kind` and `pl` as P.back_style / P.section_style give them, `brush` the
-- control's own Brush<n> (nil: the faceplate's own; an inset has none).
function M.part_brushed(kind, pl, brush)
  if not kind then return false end
  if brush ~= nil then return brush end
  return (kind == "plate" and pl and pl.brushed) or false
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
      local sty, cap = (sect["Style" .. i] or ""):match("^%s*([%w_]*)%s*|?%s*([#%w_]*)")
      -- a section's faceplate as saved (a custom colour in lower case); one
      -- no longer in the list leaves the section unstyled
      if sty == "plate" then cap = C.plate_key(cap); if not cap then sty = nil end end
      controls[#controls + 1] = {
        param   = tonumber(p),
        type    = t,
        bipolar = (f & 1) ~= 0,
        invert  = (f & 2) ~= 0,
        no_rule = (f & 4) ~= 0,
        live    = (f & 8) ~= 0,
        label   = U.trim(label),
        style   = (sty and sty ~= "") and (C.KNOB_STYLE_ALIAS[sty] or sty) or nil,
        -- a cap or lit colour by name, or one of your own (#rrggbb)
        cap     = (cap and cap ~= "") and ((cap:sub(1, 1) == "#" and C.custom_key(cap)) or cap) or nil,
        size    = size_of(sect["Size" .. i]),
        buttons = buttons_of(sect["Buttons" .. i]),
        back    = back_of(sect["Back" .. i]),
        nbtn    = nbtn_of(sect["Buttons" .. i]),
        brush   = brush_of(sect["Brush" .. i]),
        metal   = (U.trim(sect["Metal" .. i] or "") == "1") or nil,
        scale   = scale_of(sect["Scale" .. i]),
        scale_ink = scale_ink_of(sect["Scale" .. i]),
      }
    end
    i = i + 1
  end
  return { controls = controls, aliases = aliases, states = states, meter = meter,
           live = (U.trim(sect.Live or "") == "1") or nil,
           measure = (U.trim(sect.Measure or "") == "1") or nil,
           levels = (U.trim(sect.Levels or "") == "1") or nil,
           plate = C.plate_key(U.trim(sect.Plate or "")),
           brush = brush_of(sect.Brush),
           metal = (U.trim(sect.Metal or "") == "1") or nil,
           lock = lock_of(sect.Lock) }
end

local function serialize(layout)
  local out = {}
  if layout.live then out.Live = "1" end
  if layout.measure then out.Measure = "1" end
  if layout.levels then out.Levels = "1" end
  if C.plate_key(layout.plate) then out.Plate = C.plate_key(layout.plate) end
  if layout.brush ~= nil then out.Brush = layout.brush and "1" or "0" end
  if layout.metal then out.Metal = "1" end
  if lock_of(layout.lock) then out.Lock = tostring(math.floor(layout.lock)) end
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
    if back_of(c.back) then out["Back" .. (i - 1)] = back_of(c.back) end
    -- the grain of its background, or a divider's section, when it has one
    local styled = back_of(c.back) or (c.type == "divider" and (c.style == "inset" or c.style == "plate"))
    if styled and c.brush ~= nil then out["Brush" .. (i - 1)] = c.brush and "1" or "0" end
    if styled and c.metal then out["Metal" .. (i - 1)] = "1" end
    -- values is the default, so it's only written to carry |cap
    local sk = scale_of(c.scale)
    if sk == "none" then out["Scale" .. (i - 1)] = "none"
    elseif sk == "ten" or c.scale_ink then
      out["Scale" .. (i - 1)] = (sk or "values") .. (c.scale_ink and "|cap" or "")
    end
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

-- ---------------------------------------------------------------------
-- sharing layouts: export some of the library to a file, import from one
-- ---------------------------------------------------------------------
-- A shared file is a layout library like this one, in the same format, so
-- a whole TS_ChannelView_Mappings.ini from someone else imports just as
-- well. Layouts travel as their raw lines, every field kept as written --
-- including ones this version doesn't know, from a newer ChannelView.

local EXPORT_HEADER = "; ChannelView layouts, exported to share -- import them with\n"
                   .. "; ChannelView's Layouts > Import layouts from file.\n"
                   .. "; Same format as TS_ChannelView_Mappings.ini (see its header)."

local function raw_copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- One line per field, sorted: two layouts are the same if this is.
local function raw_text(t)
  local lines = {}
  for k, v in pairs(t or {}) do lines[#lines + 1] = k .. "=" .. U.trim(tostring(v)) end
  table.sort(lines)
  return table.concat(lines, "\n")
end

-- A section is a layout if it has controls, or at least aliases, state
-- names or a faceplate -- anything else (a stray [section] in some other
-- ini) isn't offered.
local function is_layout(t)
  for k in pairs(t) do
    if k:match("^Ctl%d+$") or k:match("^Alias%d+$") or k:match("^States%d+$") or k == "Plate" then
      return true
    end
  end
  return false
end

-- Every saved layout's name (its plugin key), sorted.
function M.keys()
  local out = {}
  for k, t in pairs(sections) do if is_layout(t) then out[#out + 1] = k end end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

-- How many controls a raw layout has (for the lists).
local function n_controls(t)
  local n = 0
  for k in pairs(t) do if k:match("^Ctl%d+$") then n = n + 1 end end
  return n
end
function M.count_controls(key) return sections[key] and n_controls(sections[key]) or 0 end

-- Writes the chosen layouts to `file`. Returns ok, err.
function M.export(file, keys)
  local data, order = {}, {}
  for _, k in ipairs(keys) do
    if sections[k] then data[k] = raw_copy(sections[k]); order[#order + 1] = k end
  end
  if #order == 0 then return false, "No layouts chosen." end
  return U.write_ini(file, data, order, EXPORT_HEADER)
end

-- Reads a shared file. Returns a list of { key, controls, status, raw }
-- in the file's order -- status "new" (not in the library), "same" (the
-- library's is identical), "differs" (importing replaces yours) or
-- "locked" (yours differs but is locked, so it isn't replaced) -- or nil,
-- err when there's nothing to import.
function M.read_shared(file)
  local f = io.open(file, "rb")
  if not f then return nil, "Can't open " .. tostring(file) end
  f:close()
  local data, order = U.read_ini(file)
  local out = {}
  for _, k in ipairs(order) do
    local t = data[k]
    if t and is_layout(t) then
      local status = "new"
      if sections[k] then
        status = (raw_text(sections[k]) == raw_text(t)) and "same"
                 or (lock_of(sections[k].Lock) and "locked") or "differs"
      end
      out[#out + 1] = { key = k, controls = n_controls(t), status = status, raw = t }
    end
  end
  if #out == 0 then return nil, "There are no ChannelView layouts in that file." end
  return out
end

-- Brings the chosen entries (from M.read_shared) into the library,
-- replacing any of the same name. The caller saves; the save keeps the
-- library as it was as the .bak.
function M.import(entries)
  local n = 0
  for _, e in ipairs(entries) do
    -- a locked layout takes no edits, and an import is one
    if sections[e.key] and lock_of(sections[e.key].Lock) and raw_text(sections[e.key]) ~= raw_text(e.raw) then
      goto continue
    end
    if not sections[e.key] then order[#order + 1] = e.key end
    sections[e.key] = raw_copy(e.raw)
    cache[e.key] = nil
    n = n + 1
    ::continue::
  end
  if n > 0 then def_cache = {}; dirty = true end
  return n
end

-- Deep copy, so the editor can work on a scratch layout and discard it.
function M.copy(layout)
  local out = { controls = {}, aliases = {}, live = layout.live,
                measure = layout.measure, levels = layout.levels,
                plate = layout.plate, brush = layout.brush, metal = layout.metal, lock = layout.lock }
  if layout.meter then
    out.meter = { on = layout.meter.on, range = layout.meter.range, win = layout.meter.win }
  end
  for i, c in ipairs(layout.controls or {}) do
    out.controls[i] = { param = c.param, type = c.type, bipolar = c.bipolar,
                        invert = c.invert, no_rule = c.no_rule, live = c.live,
                        label = c.label, style = c.style, cap = c.cap, size = c.size,
                        buttons = c.buttons, nbtn = c.nbtn, back = c.back, brush = c.brush,
                        metal = c.metal, scale = c.scale, scale_ink = c.scale_ink }
  end
  for p, n in pairs(layout.aliases or {}) do out.aliases[p] = n end
  out.states = {}
  for p, st in pairs(layout.states or {}) do out.states[p] = { st[1], st[2] } end
  return out
end

return M
