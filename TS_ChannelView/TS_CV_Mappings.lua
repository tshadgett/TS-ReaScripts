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
      Finish<n> = <finish>
      Corners<n> = soft | round
      Look<n>  = <knob parts>
      Inner<n> = <parts recipe>     (dual: the inner knob's)
      Look2<n> = <knob parts>       (dual: the inner knob's own look)
      Metal<n> = 1
      Scale<n> = values | ten [|cap]
      Shape<n> = v | h  |  2 | 3 | 4 | full  |  full | half
      Dual<n>  = <second param index>   (xy: its Y; dual: the inner knob)
      Plate    = <faceplate>
      Brush    = <1|0>
      Finish   = <finish>
      Metal    = 1
      Lock     = <rows>
      Palette  = <#rrggbb ...>|<#rrggbb ...>

  <type> is knob | toggle | combo | stepped | fader | xy | dual | blank |
  divider | half_gap | page. "page" is a page break: everything after it,
  up to the next one, is a page of its own, and the panel shows one page
  at a time with a tab strip under its header (TS_CV_Panel's P.pages).
  Its label names the tab; its Style<n> colour (the cap field) is the
  tab's stripe, the theme's accent when unset. Dividers inside a page
  split its columns as usual. "xy" is an XY pad (Ctl is X, Dual<n> Y),
  "dual" a concentric knob (Ctl the outer ring, Dual<n> the inner knob).
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

  RANGE<p>=<low>|<high>|<unit>|<curve> is your own range for parameter p,
  for a plugin that won't say what its values are (Acustica's give the
  host only their own internal numbers): what it reads as everywhere --
  the panel, the scale round a knob, tooltips, canvases, the web page.
  <unit> Hz kHz ms s dB % :1 or empty; <curve> lin, log or sq.

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
  Finish<n> (Finish for the faceplate) is its surface finish, a key from
  C.FINISHES ("plain" for none); when there is one it says what Brush<n>
  would, and Brush<n> is still read when there isn't. The metallic flake
  goes over any finish. Corners<n> rounds that background's or section's
  corners more than the usual slight rounding: soft, or round (ends fully
  rounded; a shape that isn't a plain rectangle is drawn soft).
  Look<n> is knob n's own look, built from parts (TS_CV_KnobParts.encode:
  k=v pairs, comma separated); it's drawn in place of its Style's.
  A concentric knob's Style is "arc" (flat), a parts recipe for its outer
  knob, or none (the default ring); with a recipe, Inner<n> is its inner
  knob's recipe and Look<n> / Look2<n> the outer's / inner's own looks.
  Scale<n> numbers knob n's scale: "values" prints the plugin's own values
  at its marks, "ten" 0 to 10; "|cap" prints them in the cap's colour.
  Medium and large knobs only (a small one has no room).

  GRIDS: Grid=<columns>x<rows> makes the layout a grid, measured in
  quarter cells (an ordinary knob is 4 x 4, a small one 4 x 2, a large
  one 6 x 6), and At<n>=<column>,<row>,<width>,<height> puts control n
  on it. A divider is a line from <column>,<row> to <column + width>,
  <row + height>, any way (width and height may be below 0), and its
  ends may be at a half. A "section" control (Ctl<n>=-1|section|0|) is a
  group, a rectangle round the controls on it, styled with the same
  lines as a divider's section (Style<n> inset or plate|<faceplate>,
  Brush, Finish, Metal, Corners) or with none, and Edge<n> for an outline
  (a faceplate's colour or #rrggbb); a line's Edge<n> is its colour.
  Empty space
  is a gap: a grid has no blank or half_gap. Controls whose Show rules
  take turns can share a place. A layout without Grid is laid out down
  then across, as before (TS_CV_Panel P.layout).

  VARIANTS: a section named "<plugin> :: <name>" is another layout for
  the same plugin, picked per instance from the panel's menu (Layout).
  Which instance shows which is kept with the project, not here.

  SHOW<n> makes control n conditional:
  Show<n>=<param>|<value>|<tol>|<op>[|<value2>] shows the control only
  while parameter <param> (any parameter of the plugin, on the panel or
  not) reads a given way, values normalised 0..1. <op>: 0 is (within
  <tol> of <value>), 1 is not, 2 above <value>, 3 below it, 4 between
  <value> and <value2>. A hidden control takes no cell, so two side by
  side with opposite rules swap in one place (a delay's "sync" knob for
  its "ms" knob when sync is on). A toggle rule is 1|0.499|0 (on); a
  dropdown's is the choice's value with half a step either side. Page
  breaks have no rule of their own.

  VIRTUAL CONTROLS (Virt<n>) belong to the layout, with no parameter
  behind them: Ctl<n>=-1|toggle|... (a virtual button), |combo| (a
  virtual selector: its Buttons<n> line shows it as chips) or |knob| (a
  virtual knob, 0..100 %), and
      Virt<n>=<start>|<choice 1>;<choice 2>;...
  <start> is where a new instance starts (0..1); the choices are a
  button's two state names or a selector's list (none for a knob). Its
  label is its NAME: Show rules and layout switching find it by that, and
  two layouts of a plugin with one of the same name share its setting.
  The setting is kept per instance, with the project (TS_CV_State
  St.vget). A Show rule on one: Show<n>=v:<name>|<value>|...
  A button or selector can also run a REAPER action as you pick each of
  its settings (a button: Off, then On):
      VAct<n>=<action>;<action>;...
  one per setting, in order, empty for none; an action is its command id
  or, for a script or extension, its "_NAME".

  LAYOUT SWITCHING (the plugin's own section only, not a variant's):
      Switch<n>=<source>|<value>|<tol>|<op>|<value2>|<layout>
  puts up <layout> (a variant's name, empty for the plugin's own) while
  <source> (a parameter's number, or v:<name> for a virtual control)
  reads that way, ops as Show<n>. Read in order; the first that matches
  wins, and with none the instance shows the layout it's set to. Kept
  when the layout itself is saved over (TS_CV_Editor sets them apart).

  LOCK freezes the layout: no edits, and the controls keep the arrangement
  they had at <rows> rows however tall the panel is -- a shorter panel
  scrolls instead of reflowing. Meters are not part of it: they can still
  be switched on and off, and the trace opened, while locked.

  CANVAS makes the layout a canvas of its kind (EQ, compressor, gate,
  limiter, de-esser, delay, reverb, envelope, modulation), for any plugin:
  the canvas fills the panel and the layout's controls (Ctl<n>) sit in
  columns beside it.
      Canvas=eq|<all bands' On param, or ->
      Canvas=comp | multi|<bands> | gate | limit | deess | delay | reverb | env | mod | sat
      Band<k>=<name>|<freq>|<gain>|<Q>|<shape switch>|<On>[|<slope>]   (k 1..8, - for none)
      Learn<k>=<what was learned about band k, see TS_CV_MapEQ>
      Dyn<k>=<threshold>|<range>|<ratio>|<attack>|<release>|<dynamics On>[|<reversed>]
          band k's dynamics (a dynamic EQ), each a param or -; reversed
          lists the ones that run the other way (thr,range,ratio,atk,rel).
          A band with a threshold or a range mapped is dynamic. Not part
          of what its learning is checked against.
      ThrCal=<param>|<d or n>|<x>:<dBFS> ...   where a compressor's threshold
          really is (measured, TS_CV_Learn LN.start_thr): its reading in
          dB (d) or its position (n) against dBFS, two or more points
      Ref0=<dBFS>   a compressor or limiter with no threshold, only an input
          gain: the level its gain's 0 dB stands for (-18 when absent)
      SatCal=<drive>|<style>|<tone>|<drive norms>|<style norms>|<tone norms>|<levels>|<entries>
          a saturator's curve and harmonics, learned on a hidden copy
          (TS_CV_Learn LN.start_sat): per Drive x Style x Tone setting
          "d.s.t:" its curve on the way up / down (24 steps of the input,
          output x1000) / its fundamental gain and harmonics 2..9 (dB x10)
          at each level, levels ";"-separated; "x" for a missing value
      DeessShape=around   a de-esser with only a frequency: its band is an
          octave around it (absent: a split-band shelf from it upward)
      DecayCal=<decay param>|<size param or ->|<size>:<decay>:<ms> ...   a reverb's
          decay time measured (TS_CV_Learn LN.start_decay) at positions of
          its decay (and size) control, size -1 when it has none
      Role<name>=<param>[|rev]   roles, by kind (M.ROLES):
          comp   Threshold, Input, Ratio, Knee, Attack, Hold, Release,
                 Makeup, Mix (Input: a compressor with no threshold,
                 driven into a fixed one by its input)
          gate   Threshold (opens), Close (its own closing threshold) or
                 Hysteresis (how far under the threshold it closes),
                 Range, Ratio (an expander's), Attack, Hold, Release
          limit  Threshold, or Input (gain into the ceiling), Ceiling,
                 Release
          deess  Frequency, Low / High (its band's edges) or Width,
                 Threshold, Range
          delay  Time (ms or a note value), Note (a note-value switch),
                 Sync (when on, Note rules), Feedback, PingPong, Mix;
                 stereo: TimeR / NoteR (the right's own), or Offset (ms
                 or % added to the left's) or Ratio (right = left x it),
                 FeedbackR, Cross (cross-feedback), Width, Link (right
                 follows left), Mode (its mono / dual / ping-pong switch)
          reverb Predelay, Decay, Size, Early (level), Balance (early
                 against late), Diffusion, LowFreq / Bass and HighFreq /
                 Damping (the decay by frequency), Tone (a tilt), LowEQ /
                 HighEQ (shelves on the wet), LowCut / HighCut and their
                 switches LowCutOn / HighCutOn, Style (its character
                 switch), Freeze, Mix
          env    Delay, Attack, Hold, Decay, Sustain, Release, and the
                 Attack / Decay / Release curves
          mod    Rate, Depth, Shape, Phase (the right side's), Delay,
                 Feedback, Mix, Voices (a count of voices); and up to
                 three voices of its own, V<k>Depth, Rate, Note, Sync,
                 Phase, Pan, On (a voice without a rate or depth of its
                 own shares the main one)
          multi  Canvas=multi|<bands, 2..4>: Crossover1..3, and per band
                 B<k>Threshold, Ratio, Attack, Release, Gain, Solo,
                 Bypass; Output, Mix
  An EQ band's shape isn't set by hand: it is learned (TS_CV_Learn) from a
  copy of the plugin and kept in Learn<k>, with the mapping it was learned
  for, so changing the mapping asks for it to be learned again.

  METER turns the gain-reduction strip on for this plugin and sets its
  full-scale range. It sits at the layout level rather than in the control
  list because a plugin has exactly one gain reduction, not one per
  parameter -- it's a property of the panel, not a slot in it. The range
  is per plugin because a bus compressor and a limiter want very different
  scales.
--]]

local U = require("TS_CV_Util")
local KP = require("TS_CV_KnobParts")
local C = require("TS_CV_Config")

local M = {}

local FILE_NAME  = "TS_ChannelView_Mappings.ini"
local BAK_NAME   = "TS_ChannelView_Mappings.bak.ini"
local HEADER     = "; ChannelView layout library -- one section per plugin.\n"
                .. "; Ctl<n>=<param index>|<type>|<bipolar 0|1>|<label>\n"
                .. ";   type: knob | toggle | combo | stepped | fader | xy | dual | blank | divider | half_gap | page | section\n"
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
                .. "; Finish<n>=<plain|brushed|anodised|bright|satin|tolex|leather|wood|crinkle|enamel|hammertone|checker>:\n"
                .. ";   the finish of control n's background (a divider: its section's)\n"
                .. "; Corners<n>=soft|round: the corners of control n's background (a divider: its section's)\n"
                .. "; Look<n>=<k=v,...>: knob n's own look, built from parts (profile, grip, mat, col, ptr, skirt ...)\n"
                .. "; Inner<n>=<recipe>, Look2<n>=<k=v,...>: a concentric knob's inner knob\n"
                .. "; Scale<n>=values|ten[|cap]: numbers round knob n (its own values, or 0-10)\n"
                .. "; Shape<n>=v|h|<2|3|4|full>|<full|half>: fader n's direction, length and thickness\n"
                .. "; Dual<n>=<param index>: the second parameter of an XY pad (its Y; Ctl is X)\n"
                .. ";   or a concentric knob (the inner knob; Ctl is the outer ring)\n"
                .. "; Size<n>=<2|3>x<2|3> on an XY pad: columns x rows (no line: 2x2)\n"
                .. ";   (no line: vertical, full height, a column wide)\n"
                .. "; Plate=<faceplate, or #rrggbb for a colour of your own>\n"
                .. "; Brush=<1 brushed, 0 plain>: the faceplate's grain, when not its own\n"
                .. "; Metal=1: a metallic flake on the faceplate\n"
                .. "; Finish=<finish>: the faceplate's finish (as Finish<n>)\n"
                .. "; Palette=<surfaces>|<accents>: the plugin's own colours, sampled from its window\n"
                .. "; Lock=<rows>: layout locked, arranged at that many rows (a grid: never flows, scrolls instead)\n"
                .. "; Grid=<columns>x<rows>: the layout is a grid, in quarter cells (an ordinary knob is 4x4)\n"
                .. "; At<n>=<column>,<row>,<width>,<height>: control n's place on the grid, in quarter cells\n"
                .. ";   (a divider: a line to <column + width>,<row + height>, either way; a section: its rectangle)\n"
                .. "; Edge<n>=<faceplate, or #rrggbb>: section n's outline, or line n's colour\n"
                .. "; CanvasW=<px>, CanvasH=<px>: a canvas layout's canvas, its width in ChannelView, its height in the rack"
                .. "; CanvasFold=1, CanvasFoldRack=1: its controls folded away, popping out from the panel's edge"

local dir         = nil
local sections    = {}   -- raw ini table
local order       = {}   -- section order as read from disk
local cache       = {}   -- plugin_key -> parsed layout
local def_cache   = {}   -- fx guid -> generated default layout
local dirty       = false
-- More than one window can hold the library at once (ChannelView and its
-- Rack view, each a script of its own): what each has changed since it
-- last read the file, by key (true: set, false: removed), so a save merges
-- into what the other saved rather than over it. A revision in ExtState
-- moves with every save, so each sees the other's.
local changed     = {}
local my_rev      = nil
local REV_SECT, REV_KEY = "TS_ChannelView", "maps_rev"
local function mark(key, removed)
  dirty = true
  if key then changed[key] = not removed end
end

local VALID_TYPE = { knob = true, toggle = true, combo = true, stepped = true,
                     fader = true, blank = true, divider = true, half_gap = true,
                     xy = true, dual = true, page = true, section = true }

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

-- Size<n>=3x2 on an XY pad: columns by rows, 2 or 3 each; nil is 2x2.
local function pad_size_of(v)
  local w, h = U.trim(v or ""):match("^([23])%s*x%s*([23])$")
  if not w or (w == "2" and h == "2") then return nil end
  return w .. "x" .. h
end
M.pad_size_of = pad_size_of

-- An XY pad's size in columns and rows.
function M.pad_dims(c)
  local w, h = tostring(c and c.size or ""):match("^([23])x([23])$")
  return tonumber(w) or 2, tonumber(h) or 2
end

-- The control types with a second parameter (Dual<n>): an XY pad's Y, a
-- concentric knob's inner knob.
function M.has_second(c) return c ~= nil and (c.type == "xy" or c.type == "dual") end

-- Shape<n>=h|3|half: a fader's direction (v or h), length in rows or
-- columns (2, 3 or 4, or full) and thickness (a whole column or row, or
-- half of one). Returns dir ("h" or nil), len (2..4 or nil) and thin
-- (true or nil); nil throughout is the default fader -- vertical, full
-- height, a column wide.
local function shape_of(v)
  local d, l, t = U.trim(v or ""):match("^(%a)%s*|%s*(%w+)%s*|%s*(%a+)")
  if not d then return nil, nil, nil end
  local dir = (d == "h") and "h" or nil
  local len = tonumber(l)
  if len and (len < 2 or len > 4) then len = nil end
  if len then len = math.floor(len) end
  local thin = (t == "half") or nil
  return dir, len, thin
end
M.shape_of = shape_of

-- The line for a control's shape, or nil when it's the default one.
local function shape_line(c)
  if c.type ~= "fader" or not (c.dir or c.len or c.thin) then return nil end
  return (c.dir == "h" and "h" or "v") .. "|" .. (c.len and tostring(c.len) or "full")
         .. "|" .. (c.thin and "half" or "full")
end
M.shape_line = shape_line

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
-- (the default, for every layout without a Scale line); "none" is the
-- only way to have no numbers.
local function scale_of(v)
  local k = U.trim(v or ""):match("^(%a+)")
  return (k == "values" or k == "ten" or k == "none") and k or nil
end
-- ArcCol<n>: a value arc's colour, a cap colour's name or #rrggbb
function M.arc_col_of(v)
  v = U.trim(v or "")
  if v == "" then return nil end
  if C.CAP[v] or (C.custom_rgb and C.custom_rgb(v)) then return v end
  return nil
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

-- A Finish line's key, or nil when it names none we know.
local function finish_of(v)
  v = U.trim(v or "")
  return C.FINISH[v] and v or nil
end
M.finish_of = finish_of

-- A Corners line: "soft" or "round"; square (the usual) is no line at all.
local CORNERS = { soft = true, round = true }
-- a concentric knob's inner recipe: a parts recipe's key, or nil
local function inner_of(v)
  v = v and U.trim(v) or ""
  local d = v ~= "" and C.KNOB_STYLE[v]
  return (d and d.parts) and v or nil
end

local function corners_of(v)
  v = U.trim(v or "")
  return CORNERS[v] and v or nil
end
M.corners_of = corners_of

-- At<n>=c,r,w,h: a place on a grid, in quarter cells; nil when it isn't one.
-- (a line's runs from c, r to c + w, r + h, either way: w and h may be
-- below 0; anything else's are its size)
local function at_of(v, line)
  local c, r, w, h = U.trim(v or ""):match("^(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)$")
  c, r, w, h = tonumber(c), tonumber(r), tonumber(w), tonumber(h)
  if not (c and r and w and h) or c < 0 or r < 0 then return nil end
  if line then
    if (w == 0 and h == 0) or c + w < 0 or r + h < 0 then return nil end
  elseif w < 0 or h < 0 or (w <= 0 and h <= 0) then
    return nil
  end
  return { c = c, r = r, w = w, h = h }
end
-- the corners of a place, whichever way a line runs: c0, r0, c1, r1
function M.at_box(a)
  return math.min(a.c, a.c + a.w), math.min(a.r, a.r + a.h), math.max(a.c, a.c + a.w), math.max(a.r, a.r + a.h)
end
M.at_of = at_of
local function num(n) return (math.tointeger(n) and tostring(math.tointeger(n))) or ("%g"):format(n) end
function M.at_line(at)
  if not at then return nil end
  return num(at.c) .. "," .. num(at.r) .. "," .. num(at.w) .. "," .. num(at.h)
end
-- Grid=<columns>x<rows>, in quarter cells; nil when the layout isn't a grid.
local function grid_of(v)
  local w, h = U.trim(v or ""):match("^(%d+)%s*[xX]%s*(%d+)$")
  w, h = tonumber(w), tonumber(h)
  if not (w and h) or w < 1 or h < 1 then return nil end
  return { cols = math.min(w, 400), rows = math.min(h, 400) }
end
M.grid_of = grid_of
-- Whether a layout is a grid (a canvas layout's: the controls beside
-- the canvas).
function M.is_grid(layout) return layout ~= nil and layout.grid ~= nil end

-- A layout's faceplate finish: its Finish if it has one, else brushed when
-- Brush (or the faceplate's own grain) says so. nil: plain.
function M.finish(layout, plate)
  if not plate then return nil end
  local f = layout and layout.finish
  if f then return (f ~= "plain") and f or nil end
  return M.brushed(layout, plate) and "brushed" or nil
end

-- ... and a control's background, or a divider's section: `finish` its
-- Finish<n>, `brush` its Brush<n>, kind and pl as for M.part_brushed.
function M.part_finish(kind, pl, finish, brush)
  if not kind then return nil end
  if finish then return (finish ~= "plain") and finish or nil end
  return M.part_brushed(kind, pl, brush) and "brushed" or nil
end

-- Whether a control's background, or a divider's section, is brushed:
-- `kind` and `pl` as P.back_style / P.section_style give them, `brush` the
-- control's own Brush<n> (nil: the faceplate's own; an inset has none).
function M.part_brushed(kind, pl, brush)
  if not kind then return false end
  if brush ~= nil then return brush end
  return (kind == "plate" and pl and pl.brushed) or false
end

-- ---------------------------------------------------------------------
-- canvases (Canvas, Band<k>, Learn<k>, Role<name>)
-- ---------------------------------------------------------------------

M.MAX_BANDS = 8
M.COMP_ROLES = { "Threshold", "Input", "Ratio", "Knee", "Attack", "Hold", "Release", "Makeup", "Mix" }
-- the roles each kind of role canvas has, in the order setup lists them
M.ROLES = {
  comp  = M.COMP_ROLES,
  gate  = { "Threshold", "Close", "Hysteresis", "Range", "Ratio", "Preopen", "Attack", "Hold", "Release",
            "Hipass", "Lowpass", "Preview", "RMS" },
  limit = { "Threshold", "Input", "Ceiling", "Release" },
  deess = { "Frequency", "Low", "High", "Width", "Threshold", "Range" },
  delay = { "Time", "Note", "Rhythm", "Sync", "Multiplier", "Feedback", "Mode", "PingPong", "TimeR", "NoteR",
            "Offset", "Ratio", "FeedbackR", "Cross", "Width", "Link", "LowCut", "HighCut", "Mix", "Dry" },
  reverb = { "Predelay", "Decay", "Size", "Balance", "Early", "Diffusion", "LowFreq", "Bass", "HighFreq", "Damping",
             "Tone", "LowEQ", "HighEQ", "LowCutOn", "HighCutOn", "LowCut", "HighCut", "Style", "Freeze", "Mix" },
  env = { "Delay", "Attack", "Hold", "Decay", "Sustain", "Release", "AttackCurve", "DecayCurve", "ReleaseCurve" },
  mod = { "Rate", "Depth", "Shape", "Phase", "Delay", "Feedback", "Mix", "Voices" },
  sat = { "Drive", "Style", "Tone", "Tone2", "Output", "Mix" },
}
-- A multiband compressor: up to M.MB_MAX bands, each with the compressor's
-- roles (named B<k><role>), the crossovers between them, and its output.
M.MB_MAX = 4
-- Low / High: the band's own edges, for a plugin whose bands each have
-- theirs (FabFilter Pro-MB) rather than crossovers between them; Used:
-- whether the band is in use (a plugin with more band slots than bands)
M.MB_BAND_ROLES = { "Low", "High", "Threshold", "Ratio", "Knee", "Attack", "Release", "Gain", "Solo", "Bypass", "Used" }
do
  local r = {}
  for k = 1, M.MB_MAX - 1 do r[#r + 1] = "Crossover" .. k end
  for k = 1, M.MB_MAX do
    for _, b in ipairs(M.MB_BAND_ROLES) do r[#r + 1] = "B" .. k .. b end
  end
  r[#r + 1] = "Output"; r[#r + 1] = "Mix"
  M.ROLES.multi = r
end
-- A delay's taps (a multi-tap): up to M.DL_TAPS, each with these roles
-- (named T<k><role>); Canvas=delay|<taps>, 0 for none.
M.DL_TAPS = 10
M.DL_TAP_ROLES = { "Time", "Note", "Rhythm", "Sync", "Level", "Pan", "On", "PingPong", "Feedback", "LowCut", "HighCut" }
M.DL_MAIN = {}
for i, r in ipairs(M.ROLES.delay) do M.DL_MAIN[i] = r end
for k = 1, M.DL_TAPS do
  for _, r in ipairs(M.DL_TAP_ROLES) do M.ROLES.delay[#M.ROLES.delay + 1] = "T" .. k .. r end
end
-- A modulation's voices (a chorus with up to three of its own): each with
-- these roles, named V<k><role>
M.MOD_VOICES = 3
M.MOD_VOICE_ROLES = { "Depth", "Rate", "Note", "Sync", "Phase", "Pan", "On" }
M.MOD_MAIN = {}
for i, r in ipairs(M.ROLES.mod) do M.MOD_MAIN[i] = r end
for k = 1, M.MOD_VOICES do
  for _, r in ipairs(M.MOD_VOICE_ROLES) do M.ROLES.mod[#M.ROLES.mod + 1] = "V" .. k .. r end
end
-- A voice role's voice and role ("V2Pan" -> 2, "Pan"), or nil.
function M.mod_voice_split(name)
  local k, r = (name or ""):match("^V(%d)(%a+)$")
  if k then return tonumber(k), r end
  return nil
end
-- The voices a modulation's roles have (in order), each { k, roles };
-- empty for one without
function M.mod_voices(roles)
  local v = {}
  for k = 1, M.MOD_VOICES do
    local any = false
    for _, r in ipairs(M.MOD_VOICE_ROLES) do if roles and roles["V" .. k .. r] then any = true end end
    if any then v[#v + 1] = k end
  end
  return v
end

-- A tap role's tap and role ("T3Level" -> 3, "Level"), or nil.
function M.dl_tap_split(name)
  local k, r = (name or ""):match("^T(%d+)(%a+)$")
  if k then return tonumber(k), r end
  return nil
end
-- What each of a mode switch's settings means (setup's choice):
-- DelayModes=<setting>:<mono|dual|pp|none>;...
function M.dl_modes_parse(s)
  local t = {}
  for item in ((s or "") .. ";"):gmatch("([^;]*);") do
    local k, v = item:match("^(.-):(%a+)%s*$")
    if k and k ~= "" and (v == "mono" or v == "dual" or v == "pp" or v == "none") then t[k] = v end
  end
  return next(t) and t or nil
end
function M.dl_modes_write(t)
  if not t then return nil end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  if #keys == 0 then return nil end
  table.sort(keys)
  local o = {}
  for _, k in ipairs(keys) do o[#o + 1] = (k:gsub("[;:\r\n]", " ")) .. ":" .. t[k] end
  return table.concat(o, ";")
end

-- A multiband role's band and role ("B2Ratio" -> 2, "Ratio"), or nil.
function M.mb_split(name)
  local k, r = (name or ""):match("^B(%d)(%a+)$")
  if k then return tonumber(k), r end
  return nil
end

-- what each kind is called, and the order the menu offers them
M.CANVAS_NAMES = { sat = "Saturation", eq = "EQ", comp = "Compressor", gate = "Gate", limit = "Limiter", deess = "De-esser",
                   delay = "Delay", reverb = "Reverb", env = "Envelope", mod = "Modulation",
                   multi = "Multiband" }
M.CANVAS_ORDER = { "eq", "comp", "multi", "gate", "limit", "deess", "sat", "delay", "reverb", "env", "mod" }
local BAND_FIELDS = { "freq", "gain", "q", "shape", "on" }
-- (a band's Slope control comes after them: written only when mapped, and
-- not part of what its learning is checked against -- the slope is read
-- live)
M.BAND_FIELDS = { "freq", "gain", "q", "shape", "on", "slope" }
-- a dynamic EQ band's dynamics (b.dyn), in the order Dyn<k> keeps them
M.DYN_FIELDS = { "thr", "range", "ratio", "atk", "rel", "on" }
M.DYN_NAMES = { thr = "Threshold", range = "Range", ratio = "Ratio", atk = "Attack", rel = "Release", on = "Dynamics On" }
-- Whether band b is dynamic: a threshold or a range mapped.
function M.band_dynamic(b)
  local d = b and b.dyn
  return d ~= nil and (d.thr ~= nil or d.range ~= nil)
end

local function pnum(v)
  v = U.trim(v or "")
  local n = tonumber(v)
  return (n and n >= 0) and math.floor(n) or nil
end

-- What a band's mapping is, as text: what its learning is checked against
-- (and the canvas's model switch, when it has one: every setting of it is
-- learned).
function M.band_sig(b, model)
  local t = {}
  for i, f in ipairs(BAND_FIELDS) do t[i] = b[f] and tostring(b[f]) or "-" end
  return table.concat(t, ",") .. (model and (",m" .. model) or "")
end

-- A size in pixels from the library, between lo and hi, or nil.
local function size_px(v, lo, hi)
  local n = tonumber(U.trim(v or ""))
  return (n and n >= lo and n <= hi) and math.floor(n) or nil
end

function M.canvas_of(sect)
  local raw = U.trim(sect.Canvas or "")
  local kind, rest = raw:match("^(%a+)%s*|?%s*(.*)$")
  if kind ~= "eq" and not M.ROLES[kind] then return nil end
  local cv = { kind = kind }
  if kind == "eq" then
    -- eq|<all on>|<model>: "x" for the model, none on purpose (not guessed)
    local a, m = (rest .. "|"):match("^([^|]*)|([^|]*)")
    cv.all_on = pnum(a)
    cv.model = pnum(m)
    if U.trim(m or "") == "x" then cv.no_model = true end
    cv.bands = {}
    for k = 1, M.MAX_BANDS do
      local line = sect["Band" .. k]
      if line then
        local f = {}
        for v in (line .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
        local b = { name = U.trim(f[1] or "") }
        for i, key in ipairs(BAND_FIELDS) do b[key] = pnum(f[i + 1]) end
        b.slope = pnum(f[#BAND_FIELDS + 2])
        local l = sect["Learn" .. k]
        if l and l ~= "" then
          local sig, data = l:match("^([^~]*)~(.*)$")
          if sig then b.learn_sig, b.learn = sig, data end
        end
        local dl = sect["Dyn" .. k]
        if dl and U.trim(dl) ~= "" then
          local g = {}
          for v in (dl .. "|"):gmatch("([^|]*)|") do g[#g + 1] = v end
          local d, any = { rev = {} }, false
          for i, key in ipairs(M.DYN_FIELDS) do
            d[key] = pnum(g[i]); if d[key] then any = true end
          end
          for w in (g[#M.DYN_FIELDS + 1] or ""):gmatch("%a+") do d.rev[w] = true end
          if any then b.dyn = d end
        end
        cv.bands[#cv.bands + 1] = b
      end
    end
  else
    if kind == "multi" then
      local nb = tonumber(rest)
      cv.nb = (nb and nb >= 2 and nb <= M.MB_MAX) and math.floor(nb) or 3
    end
    if kind == "delay" then
      local nt = tonumber(rest)
      cv.nt = (nt and nt >= 1 and nt <= M.DL_TAPS) and math.floor(nt) or nil
      cv.dmodes = sect.DelayModes and M.dl_modes_parse(U.trim(sect.DelayModes)) or nil
    end
    cv.roles, cv.rev = {}, {}
    local tc = sect.ThrCal and U.trim(sect.ThrCal)
    if tc and tc ~= "" then
      local p, how, rest = tc:match("^(%d+)%s*|%s*(%a)%s*|%s*(.*)$")
      local pts = {}
      for x, t in (rest or ""):gmatch("([-%d%.e]+):([-%d%.e]+)") do
        local a, b = tonumber(x), tonumber(t)
        if a and b then pts[#pts + 1] = { a, b } end
      end
      if p and #pts >= 2 then
        table.sort(pts, function(a, b) return a[1] < b[1] end)
        cv.thr_cal = { p = tonumber(p), n = (how == "n"), pts = pts }
      end
    end
    -- a compressor or limiter driven by its input: the level (dBFS) its
    -- input gain's 0 dB stands for
    local r0 = tonumber(sect.Ref0 and U.trim(sect.Ref0) or "")
    if r0 and r0 > -96 and r0 < 24 then cv.ref0 = r0 end
    -- a saturator's learned curve and harmonics
    if kind == "sat" and sect.SatCal then cv.sat_cal = M.sat_decode(U.trim(sect.SatCal)) end
    -- a de-esser with only a frequency: a shelf from it up, or a band around it
    if kind == "deess" and sect.DeessShape and U.trim(sect.DeessShape):lower() == "around" then cv.dshape = "around" end
    local dc = sect.DecayCal and U.trim(sect.DecayCal)
    if dc and dc ~= "" then
      local p, sz, rest = dc:match("^(%d+)%s*|%s*([%d%-]+)%s*|%s*(.*)$")
      local pts = {}
      for a, b, c in (rest or ""):gmatch("([-%d%.e]+):([-%d%.e]+):([-%d%.e]+)") do
        local x, y, z = tonumber(a), tonumber(b), tonumber(c)
        if x and y and z then pts[#pts + 1] = { x, y, z } end
      end
      if p and #pts >= 2 then cv.dec_cal = { p = tonumber(p), s = tonumber(sz), pts = pts } end
    end
    for _, r in ipairs(M.ROLES[kind]) do
      local line = sect["Role" .. r]
      if line then
        local p, flag = U.trim(line):match("^(%d+)%s*|?%s*(%a*)")
        if p then
          cv.roles[r] = tonumber(p)
          if flag == "rev" then cv.rev[r] = true end
        end
      end
    end
  end
  -- its size: ChannelView's width, the rack's height (pixels; none: the
  -- usual)
  local cw, chh = tonumber(U.trim(sect.CanvasW or "")), tonumber(U.trim(sect.CanvasH or ""))
  cv.w = (cw and cw >= 160 and cw <= 2000) and math.floor(cw) or nil
  cv.h = (chh and chh >= 100 and chh <= 1200) and math.floor(chh) or nil
  -- its controls folded away (they pop out from the panel's edge): in
  -- ChannelView, in the rack
  cv.fold = (U.trim(sect.CanvasFold or "") == "1") or nil
  cv.fold_rack = (U.trim(sect.CanvasFoldRack or "") == "1") or nil
  return cv
end

function M.canvas_lines(cv, out)
  if not cv then return end
  if cv.kind == "eq" then
    local m = cv.model and tostring(cv.model) or (cv.no_model and "x") or nil
    out.Canvas = "eq" .. ((cv.all_on or m) and ("|" .. (cv.all_on and tostring(cv.all_on) or "-")) or "")
      .. (m and ("|" .. m) or "")
    for k, b in ipairs(cv.bands or {}) do
      if k > M.MAX_BANDS then break end
      local f = { ((b.name or ""):gsub("[|\r\n]", " ")) }
      for i, key in ipairs(BAND_FIELDS) do f[i + 1] = b[key] and tostring(b[key]) or "-" end
      if b.slope then f[#f + 1] = tostring(b.slope) end
      out["Band" .. k] = table.concat(f, "|")
      if b.learn and b.learn_sig then out["Learn" .. k] = b.learn_sig .. "~" .. b.learn end
      if b.dyn then
        local g, any = {}, false
        for i, key in ipairs(M.DYN_FIELDS) do
          g[i] = b.dyn[key] and tostring(b.dyn[key]) or "-"
          if b.dyn[key] then any = true end
        end
        local rv = {}
        for _, key in ipairs(M.DYN_FIELDS) do if b.dyn.rev and b.dyn.rev[key] and b.dyn[key] then rv[#rv + 1] = key end end
        if #rv > 0 then g[#g + 1] = table.concat(rv, ",") end
        if any then out["Dyn" .. k] = table.concat(g, "|") end
      end
    end
  elseif M.ROLES[cv.kind] then
    out.Canvas = cv.kind .. ((cv.kind == "multi") and ("|" .. (cv.nb or 3)) or "")
      .. ((cv.kind == "delay" and cv.nt and cv.nt > 0) and ("|" .. cv.nt) or "")
    if cv.kind == "delay" then out.DelayModes = M.dl_modes_write(cv.dmodes) end
    local dc = cv.dec_cal
    if dc and dc.p and dc.pts and #dc.pts >= 2 and not dc.builtin then
      local t = {}
      for i, q in ipairs(dc.pts) do t[i] = ("%g:%g:%.5g"):format(q[1], q[2], q[3]) end
      out.DecayCal = ("%d|%s|%s"):format(dc.p, dc.s and tostring(dc.s) or "-", table.concat(t, " "))
    end
    if cv.ref0 and cv.ref0 ~= M.REF0 then out.Ref0 = ("%g"):format(cv.ref0) end
    if cv.kind == "deess" and cv.dshape == "around" then out.DeessShape = "around" end
    if cv.kind == "sat" and cv.sat_cal then out.SatCal = M.sat_encode(cv.sat_cal) end
    local tc = cv.thr_cal
    if tc and tc.p and tc.pts and #tc.pts >= 2 then
      local t = {}
      for i, q in ipairs(tc.pts) do t[i] = ("%.6g:%.4g"):format(q[1], q[2]) end
      out.ThrCal = ("%d|%s|%s"):format(tc.p, tc.n and "n" or "d", table.concat(t, " "))
    end
    for _, r in ipairs(M.ROLES[cv.kind]) do
      local p = cv.roles and cv.roles[r]
      if p then out["Role" .. r] = tostring(p) .. ((cv.rev and cv.rev[r]) and "|rev" or "") end
    end
  end
  if cv.w then out.CanvasW = tostring(math.floor(cv.w)) end
  if cv.h then out.CanvasH = tostring(math.floor(cv.h)) end
  if cv.fold then out.CanvasFold = "1" end
  if cv.fold_rack then out.CanvasFoldRack = "1" end
end

function M.copy_canvas(cv)
  if not cv then return nil end
  local out = { kind = cv.kind, all_on = cv.all_on, model = cv.model, no_model = cv.no_model, nb = cv.nb, nt = cv.nt, ref0 = cv.ref0, dshape = cv.dshape,
                w = cv.w, h = cv.h, fold = cv.fold, fold_rack = cv.fold_rack,
                 dmodes = cv.dmodes and M.dl_modes_parse(M.dl_modes_write(cv.dmodes)) or nil,
                 sat_cal = cv.sat_cal and M.sat_decode(M.sat_encode(cv.sat_cal)) or nil }
  if cv.bands then
    out.bands = {}
    for i, b in ipairs(cv.bands) do
      out.bands[i] = { name = b.name, freq = b.freq, gain = b.gain, q = b.q, shape = b.shape,
                       on = b.on, slope = b.slope, learn = b.learn, learn_sig = b.learn_sig }
      if b.dyn then
        local d = { rev = {} }
        for _, key in ipairs(M.DYN_FIELDS) do d[key] = b.dyn[key] end
        for key, v in pairs(b.dyn.rev or {}) do d.rev[key] = v end
        out.bands[i].dyn = d
      end
    end
  end
  if cv.roles then
    out.roles, out.rev = {}, {}
    for k, v in pairs(cv.roles) do out.roles[k] = v end
    for k, v in pairs(cv.rev or {}) do out.rev[k] = v end
  end
  if cv.dec_cal then
    local pts = {}
    for i, q in ipairs(cv.dec_cal.pts or {}) do pts[i] = { q[1], q[2], q[3] } end
    out.dec_cal = { p = cv.dec_cal.p, s = cv.dec_cal.s, pts = pts }
  end
  if cv.thr_cal then
    local pts = {}
    for i, q in ipairs(cv.thr_cal.pts or {}) do pts[i] = { q[1], q[2] } end
    out.thr_cal = { p = cv.thr_cal.p, n = cv.thr_cal.n, pts = pts }
  end
  return out
end

-- ---------------------------------------------------------------------
-- a saturator's learned curve and harmonics (TS_CV_Learn LN.start_sat)
-- ---------------------------------------------------------------------
M.SAT_CB = 24            -- steps of the input, -1 to 1 of its peak
M.SAT_NH = 9             -- the fundamental's gain, then harmonics 2..9

local function nums(s, sep)
  local t = {}
  for v in ((s or "") .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do t[#t + 1] = v end
  return t
end
local function norms_of(s)
  if s == "-" or s == "" then return { false } end
  local t = {}
  for _, v in ipairs(nums(s, ",")) do t[#t + 1] = tonumber(v) or 0 end
  return t
end
local function enc_list(t, mul, n)
  local o = {}
  for i = 1, n do
    local v = t[i]
    o[i] = (v == nil or v ~= v or v <= -900 or v >= 1e9) and "x" or tostring(math.floor(v * mul + 0.5))
  end
  return table.concat(o, ",")
end
local function dec_list(s, mul, n)
  local t = {}
  local raw = nums(s, ",")
  for i = 1, n do local v = tonumber(raw[i] or "") ; t[i] = v and v / mul or nil end
  return t
end

function M.sat_encode(c)
  local function nl(t) if not t or t[1] == false then return "-" end local o = {} for i, v in ipairs(t) do o[i] = ("%g"):format(v) end return table.concat(o, ",") end
  local keys = {}
  for k in pairs(c.e or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  local ents = {}
  for _, k in ipairs(keys) do
    local e = c.e[k]
    local hs = {}
    for li = 1, #c.L do hs[li] = enc_list(e.h[li] or {}, 10, M.SAT_NH) end
    ents[#ents + 1] = k .. ":" .. enc_list(e.up, 1000, M.SAT_CB) .. "/" .. enc_list(e.dn, 1000, M.SAT_CB) .. "/" .. table.concat(hs, ";")
  end
  return table.concat({ tostring(c.d or "-"), tostring(c.s or "-"), tostring(c.t or "-"), nl(c.dn), nl(c.sn), nl(c.tn),
    nl(c.L), table.concat(ents, " ") }, "|")
end

function M.sat_decode(line)
  local f = nums(line or "", "|")
  if #f < 8 then return nil end
  local c = { d = tonumber(f[1]), s = tonumber(f[2]), t = tonumber(f[3]),
              dn = norms_of(f[4]), sn = norms_of(f[5]), tn = norms_of(f[6]), L = norms_of(f[7]), e = {} }
  if not c.d or c.L[1] == false then return nil end
  local n = 0
  for ent in (f[8] or ""):gmatch("%S+") do
    local k, up, dn, hs = ent:match("^([%d%.]+):([^/]*)/([^/]*)/(.*)$")
    if k then
      local e = { up = dec_list(up, 1000, M.SAT_CB), dn = dec_list(dn, 1000, M.SAT_CB), h = {} }
      local lv = nums(hs, ";")
      for li = 1, #c.L do e.h[li] = dec_list(lv[li] or "", 10, M.SAT_NH) end
      c.e[k] = e
      n = n + 1
    end
  end
  return n > 0 and c or nil
end

-- where `v` sits among a grid's points: the two either side and how far
-- between (a grid of one, or none, is that point)
local function between(grid, v)
  if not grid or grid[1] == false or #grid <= 1 then return 1, 1, 0 end
  if v <= grid[1] then return 1, 1, 0 end
  for i = 1, #grid - 1 do
    if v <= grid[i + 1] then
      local a, b = grid[i], grid[i + 1]
      return i, i + 1, (b > a) and (v - a) / (b - a) or 0
    end
  end
  return #grid, #grid, 0
end
local function nearest(grid, v)
  if not grid or grid[1] == false then return 1 end
  local best, bd = 1, math.huge
  for i, g in ipairs(grid) do if math.abs(g - v) < bd then best, bd = i, math.abs(g - v) end end
  return best
end
local function mix(a, b, t)
  if a == nil then return b end
  if b == nil then return a end
  return a + (b - a) * t
end
local function mix_list(a, b, t, n)
  local o = {}
  for i = 1, n do o[i] = mix(a and a[i], b and b[i], t) end
  return o
end
local function mix_ent(a, b, t, nl)
  if not a then return b end
  if not b then return a end
  local o = { up = mix_list(a.up, b.up, t, M.SAT_CB), dn = mix_list(a.dn, b.dn, t, M.SAT_CB), h = {} }
  for li = 1, nl do o.h[li] = mix_list(a.h[li], b.h[li], t, M.SAT_NH) end
  return o
end

-- The learned curve and harmonics at a Drive / Style / Tone setting
-- (normalised; style the nearest learned, drive and tone between theirs).
function M.sat_at(c, dnorm, snorm, tnorm)
  if not c then return nil end
  local si = nearest(c.sn, snorm or 0)
  local d1, d2, dt = between(c.dn, dnorm or 0)
  local t1, t2, tt = between(c.tn, tnorm or 0)
  local nl = #c.L
  local function at(di, ti) return c.e[("%d.%d.%d"):format(di, si, ti)] end
  local a = mix_ent(at(d1, t1), at(d2, t1), dt, nl)
  local b = mix_ent(at(d1, t2), at(d2, t2), dt, nl)
  return mix_ent(a, b, tt, nl)
end

-- Its harmonics at an input level (dBFS, between the levels learned):
-- { g = the fundamental's gain dB, [2..9] = dB against the fundamental },
-- and its THD in %.
function M.sat_harm(c, at, level)
  if not (c and at) then return nil end
  local l1, l2, lt = between(c.L, level or c.L[#c.L])
  local a, b = at.h[l1], at.h[l2]
  local o = { g = mix(a and a[1], b and b[1], lt) }
  local p = 0
  for h = 2, M.SAT_NH do
    local v = mix(a and a[h], b and b[h], lt)
    o[h] = v
    if v then p = p + 10 ^ (v / 10) end
  end
  return o, math.sqrt(p) * 100
end

-- The curve, both sides averaged: the output at input x (-1..1).
function M.sat_curve(at, x, side)
  side = side or "both"
  if not at then return nil end
  local n = M.SAT_CB
  local function v(i)
    local u, d = at.up[i], at.dn[i]
    if side == "up" then return u or d elseif side == "dn" then return d or u end
    if u and d then return (u + d) * 0.5 end
    return u or d
  end
  local fx = (math.max(-1, math.min(1, x)) + 1) * 0.5 * n + 0.5   -- 1-based, at the steps' centres
  local i = math.max(1, math.min(n - 1, math.floor(fx)))
  local t = math.max(0, math.min(1, fx - i))
  local a, b = v(i), v(i + 1)
  if a == nil or b == nil then return a or b end
  return a + (b - a) * t
end

-- Where it starts to bite: the input level (dBFS) at which the curve has
-- fallen 1 dB under its small-signal slope, or nil when it never does.
function M.sat_bite(at)
  if not at then return nil end
  local n = M.SAT_CB
  local function xc(i) return -1 + (i - 0.5) * 2 / n end
  local lo, hi = M.sat_curve(at, xc(n / 2)), M.sat_curve(at, xc(n / 2 + 1))
  if not (lo and hi) then return nil end
  local g0 = (hi - lo) / (xc(n / 2 + 1) - xc(n / 2))
  if math.abs(g0) < 1e-6 then return nil end
  local best
  for i = n / 2 + 2, n do
    for _, sgn in ipairs({ 1, -1 }) do
      local x = sgn * xc(i)
      local y = M.sat_curve(at, x)
      local y0 = M.sat_curve(at, 0) or 0
      if y and math.abs((y - y0) / (g0 * x)) < 0.891 then
        local db = 20 * math.log(math.abs(x), 10)
        if not best or db < best then best = db end
      end
    end
  end
  return best
end

-- ---------------------------------------------------------------------
-- a delay's echoes, left and right
-- ---------------------------------------------------------------------
-- How a stereo delay's mode switch reads: "pp" (ping-pong), "dual" (left
-- and right each their own), "mono" (one delay, the same both sides), or
-- nil when its text says none of these (an algorithm's name, say).
function M.dl_mode_of(text)
  local s = " " .. (text or ""):lower() .. " "
  if s:find("ping", 1, true) or s:find("pong", 1, true) or s:find("bounce", 1, true) then return "pp" end
  if s:find("dual", 1, true) or s:find("stereo", 1, true) or s:find("l/r", 1, true) or s:find("l-r", 1, true)
     or s:find("split", 1, true) or s:find("double", 1, true) or s:find("wide", 1, true) then return "dual" end
  if s:find("single", 1, true) or s:find("mono", 1, true) then return "mono" end
  return nil
end

-- Whether a sync control's setting means it's following the tempo: its
-- text when that says ("Free", "ms", "Off" no; "Sync", "Straight",
-- "Dotted", a note value yes), else its switch being on.
function M.dl_sync_of(text, norm)
  local s = " " .. (text or ""):lower() .. " "
  if s:find(" off ", 1, true) or s:find("free", 1, true) or s:match("%Wms%W") or s:find("msec", 1, true) or s:find(" time ", 1, true)
     or s:find("hz", 1, true) or s:find("unsync", 1, true) then return false end
  if s:find(" on ", 1, true) or s:find("sync", 1, true) or s:find("straight", 1, true) or s:find("dot", 1, true)
     or s:find("trip", 1, true) or s:find("note", 1, true) or s:find("tempo", 1, true) or s:find("bpm", 1, true)
     or s:find("beat", 1, true) or s:find("host", 1, true) or s:match("%d+%s*/%s*%d+") then return true end
  return (norm or 0) >= 0.5
end

-- A ratio control's reading (the right's time against the left's): "3:4",
-- "0.75", "75 %"; nil when it reads in none of these.
function M.dl_ratio_of(text)
  local s = (text or ""):lower()
  local a, b = s:match("(%d+%.?%d*)%s*[:/]%s*(%d+%.?%d*)")
  if a and tonumber(b) and tonumber(b) > 0 then return tonumber(a) / tonumber(b) end
  local p = s:match("(%-?%d+%.?%d*)%s*%%")
  if p then return tonumber(p) / 100 end
  local v = tonumber(s:match("^%s*x?%s*(%d+%.?%d*)%s*x?%s*$") or "")
  if v and v > 0 and v <= 8 then return v end
  return nil
end

-- The echoes of two delay lines, each feeding itself back (fbL, fbR) and
-- the other (cross), the dry sound going into the left by inL and the
-- right by inR: { {t ms, sd "L"/"R", a (the dry sound 1), n (its count on
-- that side, from 0), x (came from the other side)} ... } by time, up to
-- `span` ms and down to `floor`.
function M.dl_taps(o)
  local T = { L = math.max(1, o.tL or 300), R = math.max(1, o.tR or o.tL or 300) }
  local FB = { L = math.max(0, math.min(1.2, o.fbL or 0)), R = math.max(0, math.min(1.2, o.fbR or o.fbL or 0)) }
  local cross = math.max(0, math.min(1.2, o.cross or 0))
  local span, floor, cap = o.span or 2000, o.floor or 0.02, o.cap or 160
  local q, out, count = {}, {}, { L = 0, R = 0 }
  local function push(t, sd, a, x)
    if t > span + 1e-6 or a < floor then return end
    q[#q + 1] = { t = t, sd = sd, a = a, x = x }
  end
  if (o.inL or 0) > 0 then push(T.L, "L", o.inL, false) end
  if (o.inR or 0) > 0 then push(T.R, "R", o.inR, false) end
  while #q > 0 and #out < cap do
    local bi = 1
    for i = 2, #q do if q[i].t < q[bi].t then bi = i end end
    local e = table.remove(q, bi)
    -- one echo where two land together
    local same
    for i = #out, 1, -1 do
      if out[i].t < e.t - 0.5 then break end
      if out[i].sd == e.sd then same = out[i] break end
    end
    if same then
      same.a = same.a + e.a
    else
      out[#out + 1] = { t = e.t, sd = e.sd, a = e.a, n = count[e.sd], x = e.x }
      count[e.sd] = count[e.sd] + 1
      -- its own repeats, then what crosses over (from the whole echo)
      local ot = e.sd == "L" and "R" or "L"
      if FB[e.sd] > 0 then push(e.t + T[e.sd], e.sd, e.a * FB[e.sd], false) end
      if cross > 0 then push(e.t + T[ot], ot, e.a * cross, true) end
    end
  end
  return out
end

-- The echoes as drawn: those landing together in one, how much is in each
-- side (l, r) once `width` (0..1) narrows them: { {t, l, r, i} ... };
-- each tap's .bar its bar's index.
function M.dl_bars(taps, width)
  local w = math.max(0, math.min(1, width or 1))
  local bars = {}
  for _, e in ipairs(taps) do
    local b = bars[#bars]
    if not (b and math.abs(b.t - e.t) < 0.5) then b = { t = e.t, l = 0, r = 0 }; bars[#bars + 1] = b end
    if e.sd == "L" then b.l = b.l + e.a else b.r = b.r + e.a end
    e.bar = #bars
  end
  for i, b in ipairs(bars) do
    local m = (b.l + b.r) / 2
    b.l, b.r, b.i = m + w * (b.l - m), m + w * (b.r - m), i
  end
  return bars
end

-- A time in beats as a note value: a fraction of a bar of 4/4 ("1/8",
-- "3/8", "1 bar", "5/4"); nil for none within a 1/64.
function M.dl_note_label(beats)
  if not beats or beats <= 0 then return nil end
  local w = beats / 4
  if w >= 1 and math.abs(w - math.floor(w + 0.5)) < 1e-3 then
    local n = math.floor(w + 0.5)
    return n == 1 and "1 bar" or (n .. " bars")
  end
  for _, d in ipairs({ 1, 2, 4, 8, 16, 32, 64 }) do
    local a = w * d
    if math.abs(a - math.floor(a + 0.5)) < 1e-3 then return ("%d/%d"):format(math.floor(a + 0.5), d) end
  end
  return nil
end

-- The beat grid's step (in beats) for `span_beats`: about eight lines.
function M.dl_beat_step(span_beats)
  for _, s in ipairs({ 0.25, 0.5, 1, 2, 4, 8, 16 }) do if span_beats / s <= 8 then return s end end
  return 32
end

-- The drive meter's scale, VU-like: how far the music's peaks are over
-- where the curve starts to bite, -20..+6 dB, 0 at 0.7 of the way along
-- (amplitude below it, as a VU's, even dB above). 0..1.
M.SAT_VU_LO, M.SAT_VU_HI = -20, 6
function M.sat_vu_pos(db)
  db = math.max(M.SAT_VU_LO, math.min(M.SAT_VU_HI, db or M.SAT_VU_LO))
  if db <= 0 then
    local a0 = 10 ^ (M.SAT_VU_LO / 20)
    return 0.7 * (10 ^ (db / 20) - a0) / (1 - a0)
  end
  return 0.7 + 0.3 * db / M.SAT_VU_HI
end

-- What an input gain's 0 dB stands for, unless a layout says otherwise:
-- the usual "0 VU" of a plugin modelled on analogue gear.
M.REF0 = -18
function M.ref0(cv) return (cv and cv.ref0) or M.REF0 end

-- The control a compressor's threshold is set by: its Threshold, or with
-- none, its Input (1176-style: the input drives it into a fixed threshold).
-- The parameter, and whether it's the input.
function M.thr_param(cv)
  local r = cv and cv.roles
  if not r then return nil end
  if r.Threshold then return r.Threshold, false end
  if r.Input then return r.Input, true end
  return nil
end

-- A compressor layout's measured threshold, when it's for the threshold
-- mapped now: its points, else nil.
function M.thr_cal(cv)
  local tc = cv and cv.thr_cal
  if tc and tc.p and tc.p == M.thr_param(cv) and tc.pts and #tc.pts >= 2 then
    -- one where the threshold never moved measured nothing (a
    -- measurement of a copy that passed no sound): set aside
    local lo, hi = math.huge, -math.huge
    for _, q in ipairs(tc.pts) do lo = math.min(lo, q[2]); hi = math.max(hi, q[2]) end
    if hi - lo > 1 then return tc end
  end
  return nil
end

-- Where the threshold is in dBFS at reading (or position) x: between the
-- measured points, and on past the ends along the nearest two.
function M.thr_dbfs(cv, x)
  local tc = M.thr_cal(cv)
  if not tc or not x then return nil end
  local p = tc.pts
  local i = 1
  while i < #p - 1 and x > p[i + 1][1] do i = i + 1 end
  local a, b = p[i], p[i + 1]
  if b[1] == a[1] then return a[2] end
  return a[2] + (x - a[1]) * (b[2] - a[2]) / (b[1] - a[1])
end

-- A reverb layout's measured decay, when it's for the decay (and size)
-- mapped now: its points, else nil.
function M.dec_cal(cv)
  local dc = cv and cv.dec_cal
  if dc and cv.roles and cv.roles.Decay == dc.p and cv.roles.Size == dc.s and dc.pts and #dc.pts >= 2 then
    -- (one where nothing rang for even 30 ms measured the burst, not a reverb)
    local most = 0
    for _, q in ipairs(dc.pts) do most = math.max(most, q[3]) end
    if most >= 30 then return dc end
  end
  return nil
end

-- along one row of {position, ms}: log time between the points, on past
-- the ends along the nearest two
local function row_ms(row, dn)
  local i = 1
  while i < #row - 1 and dn > row[i + 1][1] do i = i + 1 end
  local a, b = row[i], row[i + 1]
  if not b then return a[2] end
  if b[1] == a[1] then return a[2] end
  local la, lb = math.log(math.max(1, a[2])), math.log(math.max(1, b[2]))
  return math.exp(la + (dn - a[1]) * (lb - la) / (b[1] - a[1]))
end

-- The decay time, ms, at decay position dn (and size position sn).
function M.decay_ms(cv, dn, sn)
  local dc = M.dec_cal(cv)
  if not dc or not dn then return nil end
  local rows, keys = {}, {}
  for _, q in ipairs(dc.pts) do
    local k = q[1]
    if not rows[k] then rows[k] = {}; keys[#keys + 1] = k end
    table.insert(rows[k], { q[2], q[3] })
  end
  table.sort(keys)
  for _, k in ipairs(keys) do table.sort(rows[k], function(a, b) return a[1] < b[1] end) end
  if #keys == 1 or not sn or sn < 0 then return row_ms(rows[keys[1]], dn) end
  local i = 1
  while i < #keys - 1 and sn > keys[i + 1] do i = i + 1 end
  local ka, kb = keys[i], keys[i + 1]
  local ma, mb = math.log(row_ms(rows[ka], dn)), math.log(row_ms(rows[kb], dn))
  local t = (kb == ka) and 0 or (sn - ka) / (kb - ka)
  return math.exp(ma + t * (mb - ma))
end

-- The decay position that gives `ms` at size position sn (between 0 and 1).
function M.decay_pos(cv, ms, sn)
  local f0, f1 = M.decay_ms(cv, 0, sn), M.decay_ms(cv, 1, sn)
  if not (f0 and f1) then return nil end
  local up = f1 >= f0
  local lo, hi = 0, 1
  for _ = 1, 30 do
    local mid = (lo + hi) * 0.5
    local v = M.decay_ms(cv, mid, sn)
    if (v < ms) == up then lo = mid else hi = mid end
  end
  return (lo + hi) * 0.5
end

-- The reading (or position) that puts the threshold at `db` dBFS.
function M.thr_from_dbfs(cv, db)
  local tc = M.thr_cal(cv)
  if not tc or not db then return nil end
  local p = tc.pts
  -- the measured points run one way or the other (a reversed control)
  local up = p[#p][2] >= p[1][2]
  local i = 1
  local function past(q) if up then return db > q[2] else return db < q[2] end end
  while i < #p - 1 and past(p[i + 1]) do i = i + 1 end
  local a, b = p[i], p[i + 1]
  if b[2] == a[2] then return a[1] end
  return a[1] + (db - a[2]) * (b[1] - a[1]) / (b[2] - a[2])
end

-- The parameters a canvas puts on itself: { [param] = true }.
function M.canvas_params(cv)
  local out = {}
  if not cv then return out end
  if cv.all_on then out[cv.all_on] = true end
  for _, b in ipairs(cv.bands or {}) do
    for _, f in ipairs(M.BAND_FIELDS) do if b[f] then out[b[f]] = true end end
    for _, f in ipairs(M.DYN_FIELDS) do if b.dyn and b.dyn[f] then out[b.dyn[f]] = true end end
  end
  for _, p in pairs(cv.roles or {}) do out[p] = true end
  return out
end

local SPACERS = { divider = true, blank = true, half_gap = true }
-- A canvas layout's side columns: the controls it has, less any its canvas
-- already puts on itself (a pair goes if either half does). The spacers
-- left with nothing between them close up -- a run of them becomes one
-- (a divider if there is one) -- and none is left at either end. Each
-- control keeps its own look (style, size, cap, background), so the
-- layout it was made from comes across. A lock goes: the rows it froze
-- aren't the same any more. Nothing changes when nothing is taken.
function M.drop_placed(layout)
  local on = M.canvas_params(layout.canvas)
  local kept, dropped = {}, false
  for _, c in ipairs(layout.controls or {}) do
    if SPACERS[c.type] then
      local last = kept[#kept]
      if last and SPACERS[last.type] then
        if c.type == "divider" and last.type ~= "divider" then kept[#kept] = c end
      elseif last then
        kept[#kept + 1] = c
      end
    elseif (c.param and on[c.param]) or (c.param2 and on[c.param2]) then
      dropped = true
    else
      kept[#kept + 1] = c
    end
  end
  while kept[#kept] and SPACERS[kept[#kept].type] do kept[#kept] = nil end
  if dropped then
    layout.controls = kept
    layout.lock = nil
  end
  return layout, dropped
end

-- Whether band b's learning is for its mapping as it is now.
function M.band_learned(b, model)
  return b ~= nil and b.learn ~= nil and b.learn_sig == M.band_sig(b, model)
end

-- How far an EQ canvas is from usable: nil when ready, else
-- { mapped = n, learned = n, total = n }.
function M.canvas_todo(cv)
  if not cv or cv.kind ~= "eq" then return nil end
  local total, mapped, learned = #(cv.bands or {}), 0, 0
  for _, b in ipairs(cv.bands or {}) do
    if b.freq or b.gain then mapped = mapped + 1 end
    if M.band_learned(b, cv.model) then learned = learned + 1 end
  end
  if total > 0 and learned == total then return nil end
  return { mapped = mapped, learned = learned, total = total }
end

local function parse_section(sect)
  local controls, aliases, states, ranges = {}, {}, {}, {}
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
    local rp = k:match("^Range(%d+)$")
    if rp then ranges[tonumber(rp)] = M.range_of_line(v) end
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
      -- Field three is a bitmask: bit 0 is bipolar (so a plain 0 or 1
      -- in this field reads as bipolar off or on, nothing else set),
      -- bit 1 is reverse, bit 2 is "no rule" --
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
      -- not in the list leaves the section unstyled
      if sty == "plate" then cap = C.plate_key(cap); if not cap then sty = nil end end
      controls[#controls + 1] = {
        param   = tonumber(p),
        type    = t,
        bipolar = (f & 1) ~= 0,
        invert  = (f & 2) ~= 0,
        no_rule = (f & 4) ~= 0,
        live    = (f & 8) ~= 0,
        -- bit 4: the second parameter reversed (an XY pad's Y, a
        -- concentric knob's inner knob); bit 1 reverses the first
        invert2 = ((f & 16) ~= 0 and (t == "xy" or t == "dual")) or nil,
        -- bits 5-6: a knob's value arc (1 positive, 2 negative, 3 centred)
        arc     = ({ "pos", "neg", "mid" })[(f >> 5) & 3],
        label   = U.trim(label),
        style   = (sty and sty ~= "") and (C.KNOB_STYLE_ALIAS[sty] or sty) or nil,
        -- a cap or lit colour by name, or one of your own (#rrggbb)
        cap     = (cap and cap ~= "") and ((cap:sub(1, 1) == "#" and C.custom_key(cap)) or cap) or nil,
        size    = size_of(sect["Size" .. i]),
        buttons = buttons_of(sect["Buttons" .. i]),
        back    = back_of(sect["Back" .. i]),
        nbtn    = nbtn_of(sect["Buttons" .. i]),
        brush   = brush_of(sect["Brush" .. i]),
        finish  = finish_of(sect["Finish" .. i]),
        corners = corners_of(sect["Corners" .. i]),
        look    = (t == "knob" or t == "stepped" or t == "dual") and KP.decode(sect["Look" .. i]) or nil,
        -- a concentric knob's inner knob: its recipe, or its own look
        style2  = (t == "dual") and inner_of(sect["Inner" .. i]) or nil,
        look2   = (t == "dual") and KP.decode(sect["Look2" .. i]) or nil,
        metal   = (U.trim(sect["Metal" .. i] or "") == "1") or nil,
        scale   = scale_of(sect["Scale" .. i]),
        scale_ink = scale_ink_of(sect["Scale" .. i]),
        -- a value arc's own colour (a cap colour's name, or #rrggbb)
        arcc    = (t == "knob" or t == "stepped") and M.arc_col_of(sect["ArcCol" .. i]) or nil,
        show    = (t ~= "page" and t ~= "section") and M.show_of(sect["Show" .. i]) or nil,
        at      = at_of(sect["At" .. i], t == "divider"),
        -- a section's outline or a line's colour: a faceplate's or your own
        edge    = (t == "section" or t == "divider") and C.plate_key(U.trim(sect["Edge" .. i] or "")) or nil,
        virtual = (tonumber(p) or 0) < 0 and M.virt_of(sect["Virt" .. i], sect["VAct" .. i]) or nil,
      }
      -- a virtual selector shown as chips: one for each of its choices
      do
        local cc = controls[#controls]
        if cc.virtual and t == "combo" and cc.buttons then
          cc.nbtn = math.max(2, #M.vchoices(cc))
        end
      end
      if t == "fader" then
        local cc = controls[#controls]
        cc.dir, cc.len, cc.thin = shape_of(sect["Shape" .. i])
      end
      -- a second parameter: an XY pad's Y, a concentric knob's inner one
      if t == "xy" or t == "dual" then
        local cc = controls[#controls]
        local p2 = tonumber(U.trim(sect["Dual" .. i] or ""))
        cc.param2 = p2 and math.floor(p2) or nil
        if t == "xy" then cc.size = pad_size_of(sect["Size" .. i])
        elseif cc.size == "small" then cc.size = nil end
      end
    end
    i = i + 1
  end
  -- a grid's size goes with its controls, for the panel to lay out
  local grid = grid_of(sect.Grid)
  controls.grid = grid
  return { controls = controls, aliases = aliases, states = states, ranges = next(ranges) and ranges or nil, meter = meter,
           canvas = M.canvas_of(sect), switch = M.switch_of(sect),
           -- ReaEQ's and ReaComp's own canvases: their width in ChannelView,
           -- height in the rack (a canvas layout keeps them in its canvas)
           own_w = (not sect.Canvas) and size_px(sect.CanvasW, 160, 2000) or nil,
           own_h = (not sect.Canvas) and size_px(sect.CanvasH, 100, 1200) or nil,
           live = (U.trim(sect.Live or "") == "1") or nil,
           measure = (U.trim(sect.Measure or "") == "1") or nil,
           levels = (U.trim(sect.Levels or "") == "1") or nil,
           plate = C.plate_key(U.trim(sect.Plate or "")),
           brush = brush_of(sect.Brush),
           finish = finish_of(sect.Finish),
           metal = (U.trim(sect.Metal or "") == "1") or nil,
           palette = M.palette_of(sect.Palette),
           lock = lock_of(sect.Lock),
           grid = grid }
end

-- Palette=: the plugin's own colours, sampled from its window (Faceplate >
-- Match the plugin, or a menu's From the plugin row): its surfaces, most
-- used first, then after the | its accents (arcs, LEDs). Each 0xRRGGBB.
function M.palette_of(v)
  v = U.trim(v or "")
  if v == "" then return nil end
  local sf, ac = v:match("^([^|]*)|?(.*)$")
  local function list(str)
    local out = {}
    for h in (str or ""):gmatch("#?(%x%x%x%x%x%x)") do out[#out + 1] = tonumber(h, 16) end
    return out
  end
  local p = { surfaces = list(sf), accents = list(ac) }
  if #p.surfaces == 0 and #p.accents == 0 then return nil end
  return p
end

function M.palette_line(p)
  if not p or (#(p.surfaces or {}) == 0 and #(p.accents or {}) == 0) then return nil end
  local function list(t)
    local out = {}
    for i, c in ipairs(t or {}) do out[i] = ("#%06x"):format(c & 0xffffff) end
    return table.concat(out, " ")
  end
  return list(p.surfaces) .. "|" .. list(p.accents)
end

local function serialize(layout)
  local out = {}
  if layout.live then out.Live = "1" end
  if layout.measure then out.Measure = "1" end
  if layout.levels then out.Levels = "1" end
  if C.plate_key(layout.plate) then out.Plate = C.plate_key(layout.plate) end
  if layout.brush ~= nil then out.Brush = layout.brush and "1" or "0" end
  if finish_of(layout.finish) then out.Finish = layout.finish end
  if layout.metal then out.Metal = "1" end
  if lock_of(layout.lock) then out.Lock = tostring(math.floor(layout.lock)) end
  if layout.grid then out.Grid = math.floor(layout.grid.cols) .. "x" .. math.floor(layout.grid.rows) end
  out.Palette = M.palette_line(layout.palette)
  M.canvas_lines(layout.canvas, out)
  if not layout.canvas then
    if layout.own_w then out.CanvasW = tostring(math.floor(layout.own_w)) end
    if layout.own_h then out.CanvasH = tostring(math.floor(layout.own_h)) end
  end
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
  for p, rg in pairs(layout.ranges or {}) do
    local line = M.range_line(rg)
    if line then out["Range" .. p] = line end
  end
  for i, c in ipairs(layout.controls or {}) do
    -- See parse_section: bit 0 bipolar, bit 1 reverse, bit 2 no-rule,
    -- bit 3 live name, bit 4 the second parameter reversed, bits 5-6 the
    -- value arc.
    local flags = (c.bipolar and 1 or 0) | (c.invert and 2 or 0)
                | (c.no_rule and 4 or 0) | (c.live and 8 or 0)
                | ((c.invert2 and (c.type == "xy" or c.type == "dual")) and 16 or 0)
                | ((({ pos = 1, neg = 2, mid = 3 })[c.arc or ""] or 0) << 5)
    out["Ctl" .. (i - 1)] = string.format("%d|%s|%d|%s",
      c.param or -1,
      c.type or "knob",
      flags,
      (c.label or ""):gsub("[|\r\n]", " "))
    if c.style or c.cap then
      out["Style" .. (i - 1)] = (c.style or "") .. "|" .. (c.cap or "")
    end
    if c.type == "xy" then
      if pad_size_of(c.size) then out["Size" .. (i - 1)] = pad_size_of(c.size) end
    elseif size_of(c.size) and not (c.type == "dual" and c.size == "small") then
      out["Size" .. (i - 1)] = c.size
    end
    if (c.type == "xy" or c.type == "dual") and c.param2 then
      out["Dual" .. (i - 1)] = tostring(math.floor(c.param2))
    end
    if shape_line(c) then out["Shape" .. (i - 1)] = shape_line(c) end
    if back_of(c.back) then out["Back" .. (i - 1)] = back_of(c.back) end
    -- the grain of its background, or a divider's section, when it has one
    local styled = back_of(c.back) or ((c.type == "divider" or c.type == "section") and (c.style == "inset" or c.style == "plate"))
    if styled and c.brush ~= nil then out["Brush" .. (i - 1)] = c.brush and "1" or "0" end
    if styled and finish_of(c.finish) then out["Finish" .. (i - 1)] = c.finish end
    if styled and corners_of(c.corners) then out["Corners" .. (i - 1)] = c.corners end
    if c.look and (c.type == "knob" or c.type == "stepped" or c.type == "dual") then
      local enc = KP.encode(c.look)
      if enc and enc ~= "" then out["Look" .. (i - 1)] = enc end
    end
    if c.type == "dual" then
      if inner_of(c.style2) then out["Inner" .. (i - 1)] = c.style2 end
      local enc = c.look2 and KP.encode(c.look2)
      if enc and enc ~= "" then out["Look2" .. (i - 1)] = enc end
    end
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
    if c.arcc and (c.type == "knob" or c.type == "stepped") then out["ArcCol" .. (i - 1)] = c.arcc end
    if c.show and c.type ~= "page" and c.type ~= "section" then out["Show" .. (i - 1)] = M.show_line(c.show) end
    if layout.grid and c.at then out["At" .. (i - 1)] = M.at_line(c.at) end
    if (c.type == "section" or c.type == "divider") and C.plate_key(c.edge) then out["Edge" .. (i - 1)] = C.plate_key(c.edge) end
    if c.virtual and (c.param or -1) < 0 then
      out["Virt" .. (i - 1)] = M.virt_line(c.virtual)
      local va = M.vact_line(c.virtual.actions, #(M.vchoices(c) or {}))
      if va then out["VAct" .. (i - 1)] = va end
    end
  end
  for k, line in ipairs(M.switch_lines(layout.switch)) do out["Switch" .. (k - 1)] = line end
  return out
end

-- A layout as one string, to tell whether two are the same.
function M.signature(layout)
  local t, keys = serialize(layout or { controls = {} }), {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  for i, k in ipairs(keys) do keys[i] = k .. "=" .. t[k] end
  return table.concat(keys, "\n")
end

-- ---------------------------------------------------------------------
-- conditional controls (Show<n>)
-- ---------------------------------------------------------------------

-- A rule from its line, or nil: { param, op, norm, norm2, tol }.
-- op: "is" (within tol of norm), "not" (isn't), "above" / "below" (past
-- norm), "between" (norm..norm2, either way round, ends included). In
-- the fourth field 0 is "is" and 1 is "not", as SHOW_CODE has them.
local SHOW_OPS  = { [0] = "is", "not", "above", "below", "between" }
local SHOW_CODE = { is = 0, ["not"] = 1, above = 2, below = 3, between = 4 }
M.SHOW_OPS = { "is", "not", "above", "below", "between" }

-- A rule's source from its field: a parameter's number, or v:<name> (a
-- virtual control); param, vname
local function source_of(f)
  local vn = (f or ""):match("^v:(.+)$")
  if vn then vn = M.clean_vname(vn); return vn and -1 or nil, vn end
  local p = tonumber(f or "")
  if not p or p < 0 then return nil end
  return math.floor(p), nil
end
local function source_line(r)
  if r.vname then return "v:" .. r.vname end
  return tostring(math.floor(r.param or 0))
end

function M.show_of(line)
  if not line then return nil end
  local f = {}
  for v in (U.trim(line) .. "|"):gmatch("([^|]*)|") do f[#f + 1] = U.trim(v) end
  local p, vn = source_of(f[1])
  local v = tonumber(f[2] or "")
  if not p or not v then return nil end
  local op = SHOW_OPS[tonumber(f[4] or "") or 0] or "is"
  local r = { param = p, vname = vn, op = op, norm = math.max(0, math.min(1, v)),
              tol = math.max(0.0005, tonumber(f[3] or "") or 0.499) }
  if op == "between" then
    r.norm2 = math.max(0, math.min(1, tonumber(f[5] or "") or r.norm))
  end
  return r
end

-- A rule's op; one with no op but `inv` set is "not".
function M.show_op(r) return r.op or (r.inv and "not") or "is" end

function M.show_line(r)
  local op = M.show_op(r)
  local line = ("%s|%.4f|%.4f|%d"):format(source_line(r), r.norm or 0, r.tol or 0.499, SHOW_CODE[op] or 0)
  if op == "between" then line = line .. ("|%.4f"):format(r.norm2 or r.norm or 0) end
  return line
end

-- Whether a value satisfies a rule. `slack` widens a rule on a range
-- (above, below, between) -- a layout switch that's on stays on until the
-- knob is that far back past its line, so one sitting on it can't flicker.
function M.show_match(v, r, slack)
  v = v or 0
  slack = slack or 0
  local op, eps = M.show_op(r), 1e-6
  if op == "above" then return v > r.norm + eps - slack end
  if op == "below" then return v < r.norm - eps + slack end
  if op == "between" then
    local a, b = r.norm, r.norm2 or r.norm
    if a > b then a, b = b, a end
    return v >= a - eps - slack and v <= b + eps + slack
  end
  local hit = math.abs(v - r.norm) <= r.tol
  if op == "not" then return not hit end
  return hit
end

-- The controls a layout shows right now, given a reader for its
-- parameters' normalised values (`getv(param, vname)`: vname for a
-- virtual control's, param -1 then), plus the set of
-- indexes (into `controls`) it hides. The list keeps the controls'
-- own tables, so a caller can still find each one in the full list.
function M.visible(controls, getv)
  local out, hidden, any = {}, {}, false
  for i, c in ipairs(controls or {}) do
    local r = c.show
    if r and c.type ~= "page" then
      any = true
      if M.show_match(getv(r.param, r.vname), r) then out[#out + 1] = c else hidden[i] = true end
    else
      out[#out + 1] = c
    end
  end
  if not any then return controls, hidden end
  return out, hidden
end

-- ---------------------------------------------------------------------
-- virtual controls (Virt<n>) and layout switching (Switch<n>)
-- ---------------------------------------------------------------------
-- A virtual control's name as typed, made safe for the lines it's
-- written into; nil when nothing's left.
function M.clean_vname(name)
  name = U.trim((name or ""):gsub("[|;:~\r\n%[%]=]", " "):gsub("%s+", " "))
  return name ~= "" and name or nil
end

function M.virt_of(line, act_line)
  if not line then return nil end
  local start, rest = U.trim(line):match("^([^|]*)|?(.*)$")
  local v = { start = math.max(0, math.min(1, tonumber(start or "") or 0)), choices = {} }
  for ch in ((rest or "") .. ";"):gmatch("([^;]*);") do
    ch = U.trim(ch)
    if ch ~= "" then v.choices[#v.choices + 1] = ch end
  end
  v.actions = M.vact_of(act_line)
  return v
end

-- The actions a virtual control runs, by setting (1-based; nil where it
-- runs none): VAct<n>. nil when there are none at all.
function M.vact_of(line)
  if not line or U.trim(line) == "" then return nil end
  local out, i, any = {}, 0, false
  for part in (U.trim(line) .. ";"):gmatch("([^;]*);") do
    i = i + 1
    part = U.trim(part)
    if part ~= "" and not part:find("[|%s]") then out[i] = part; any = true end
  end
  return any and out or nil
end
-- And back, for the first n settings; nil when none is set.
function M.vact_line(actions, n)
  if not actions then return nil end
  local list, any = {}, false
  for i = 1, n or 0 do
    local a = actions[i]
    a = (type(a) == "string" and not a:find("[|;%s]")) and a or ""
    if a ~= "" then any = true end
    list[i] = a
  end
  if not any then return nil end
  while list[#list] == "" do list[#list] = nil end
  return table.concat(list, ";")
end

-- The action a button or selector runs at value v, or nil.
function M.vaction(c, v)
  local acts = c and c.virtual and c.virtual.actions
  if not acts or c.type == "knob" then return nil end
  return acts[M.vindex(c, v)]
end

-- Runs it (picked on the panel or the web page). Returns whether it ran.
function M.run_vaction(c, v)
  local cmd = M.vaction(c, v)
  if not cmd then return false end
  local id = (cmd:sub(1, 1) == "_") and reaper.NamedCommandLookup(cmd) or tonumber(cmd)
  if not id or id <= 0 then return false end
  reaper.Main_OnCommand(id, 0)
  return true
end
function M.virt_line(v)
  local list = {}
  for _, ch in ipairs(v.choices or {}) do
    local c = U.trim((ch or ""):gsub("[|;\r\n]", " "))
    if c ~= "" then list[#list + 1] = c end
  end
  return ("%g|%s"):format(math.floor((v.start or 0) * 10000 + 0.5) / 10000, table.concat(list, ";"))
end

function M.is_virtual(c) return c ~= nil and c.virtual ~= nil and (c.param or -1) < 0 end
-- its name: its label (a selector "View", a button "More", a knob "Amount"
-- when it has none)
function M.vname_of(c)
  return M.clean_vname(c.label) or ((c.type == "combo") and "View" or (c.type == "toggle") and "More" or "Amount")
end
-- its settings' names: a button's two (Off / On when it has none of its
-- own), a selector's list; nil for a knob
function M.vchoices(c)
  local v = c.virtual or {}
  if c.type == "toggle" then
    return { v.choices[1] or "Off", v.choices[2] or "On" }
  end
  if c.type == "combo" then
    if #(v.choices or {}) >= 1 then return v.choices end
    return { "1", "2" }
  end
  return nil
end
-- choice i's value (1-based), and the choice a value is on
function M.vnorm(c, i)
  local list = M.vchoices(c)
  if not list or #list < 2 then return 0 end
  return (math.max(1, math.min(#list, i)) - 1) / (#list - 1)
end
function M.vindex(c, v)
  local list = M.vchoices(c)
  if not list or #list < 2 then return 1 end
  return math.max(1, math.min(#list, math.floor((v or 0) * (#list - 1) + 0.5) + 1))
end
-- what it reads as at value v
function M.vtext(c, v)
  local list = M.vchoices(c)
  if list then return list[M.vindex(c, v)] or "" end
  return ("%d %%"):format(math.floor((v or 0) * 100 + 0.5))
end
-- A virtual control of that name in a list of controls, or nil.
function M.vfind(controls, name)
  for _, c in ipairs(controls or {}) do
    if M.is_virtual(c) and M.vname_of(c) == name then return c end
  end
  return nil
end

-- A rule list from a section's Switch<n> lines: { source, op, values,
-- layout } each (layout nil: the plugin's own).
function M.switch_of(sect)
  local out, i = {}, 0
  while sect and sect["Switch" .. i] do
    local f = {}
    for v in (U.trim(sect["Switch" .. i]) .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
    local p, vn = source_of(U.trim(f[1] or ""))
    local v = tonumber(U.trim(f[2] or ""))
    if p and v then
      local op = SHOW_OPS[tonumber(U.trim(f[4] or "")) or 0] or "is"
      local name = U.trim(table.concat(f, "|", 6))
      local r = { param = p, vname = vn, op = op, norm = math.max(0, math.min(1, v)),
                  tol = math.max(0.0005, tonumber(U.trim(f[3] or "")) or 0.499),
                  layout = (name ~= "") and name or nil }
      if op == "between" then r.norm2 = math.max(0, math.min(1, tonumber(U.trim(f[5] or "")) or r.norm)) end
      out[#out + 1] = r
    end
    i = i + 1
  end
  return (#out > 0) and out or nil
end
function M.switch_lines(rules)
  local out = {}
  for _, r in ipairs(rules or {}) do
    local op = M.show_op(r)
    out[#out + 1] = ("%s|%.4f|%.4f|%d|%s|%s"):format(source_line(r), r.norm or 0, r.tol or 0.499,
      SHOW_CODE[op] or 0, (op == "between") and ("%.4f"):format(r.norm2 or r.norm or 0) or "",
      ((r.layout or ""):gsub("[\r\n]", " ")))
  end
  return out
end
-- A rule in words ("Mode is Dual"): `pname(p)` a parameter's name,
-- `fmt(p, norm)` what it reads as there (nil: a %), `vfind(name)` a
-- virtual control of that name (for its choices' names).
local OP_WORDS = { is = "is", ["not"] = "is not", above = "is above", below = "is below", between = "is between" }
function M.rule_text(r, pname, fmt, vfind)
  local src, say
  if r.vname then
    local vc = vfind and vfind(r.vname)
    src = "\u{25C6} " .. r.vname
    say = function(n) return vc and M.vtext(vc, n) or ("%d %%"):format(math.floor(n * 100 + 0.5)) end
  else
    src = (pname and pname(r.param)) or ("P" .. tostring(r.param))
    say = function(n) return (fmt and fmt(r.param, n)) or ("%d %%"):format(math.floor(n * 100 + 0.5)) end
  end
  local op = M.show_op(r)
  local t = src .. " " .. (OP_WORDS[op] or op) .. " " .. say(r.norm or 0)
  if op == "between" then t = t .. " and " .. say(r.norm2 or r.norm or 0) end
  return t
end

-- A copy of a rule list
function M.copy_rules(rules)
  if not rules then return nil end
  local out = {}
  for i, r in ipairs(rules) do
    out[i] = { param = r.param, vname = r.vname, op = M.show_op(r), norm = r.norm, norm2 = r.norm2,
               tol = r.tol, layout = r.layout }
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
  changed = {}
  if reaper and reaper.GetExtState then my_rev = reaper.GetExtState(REV_SECT, REV_KEY) end
end

-- Another window saved the library: read it again, keeping what was
-- changed here and not saved yet on top. Cheap when nothing moved.
-- True when anything was read.
function M.sync()
  if not (reaper and reaper.GetExtState and dir) then return false end
  local rev = reaper.GetExtState(REV_SECT, REV_KEY)
  if rev == my_rev then return false end
  my_rev = rev
  local new_sec, new_order = U.read_ini(path())
  for key, set in pairs(changed) do
    local was = new_sec[key] ~= nil
    if set then
      new_sec[key] = sections[key]
      if not was then new_order[#new_order + 1] = key end
    elseif was then
      new_sec[key] = nil
      for i = #new_order, 1, -1 do if new_order[i] == key then table.remove(new_order, i) end end
    end
  end
  sections, order = new_sec, new_order
  cache, def_cache = {}, {}
  return true
end

-- Generated defaults are cached per FX instance: building one walks every
-- parameter name, which is far too much to redo 30 times a second for a
-- plugin nobody has set up yet. The chain rescan clears this.
function M.clear_default_cache() def_cache = {} end

function M.file_path() return path() end

function M.has(key)
  return sections[key] ~= nil
end

-- ---------------------------------------------------------------------
-- layout variants: more than one layout for a plugin, picked per
-- instance (a Kontakt with a piano on one track, strings on another).
-- A variant is a section of its own, "<plugin> :: <name>"; which one an
-- instance shows is kept with the project (TS_CV_State St.variant).
-- ---------------------------------------------------------------------
M.VARIANT_SEP = " :: "

function M.variant_key(base, name)
  if not name or name == "" then return base end
  return base .. M.VARIANT_SEP .. name
end

-- The plugin's own key and the variant's name, from a layout key.
function M.split_variant(key)
  local b, v = (key or ""):match("^(.-) :: (.+)$")
  if b then return b, v end
  return key, nil
end

-- A variant's name as typed, made safe for a section name.
function M.clean_variant(name)
  name = U.trim((name or ""):gsub("[%[%]\r\n]", ""):gsub(" :: ", " - "))
  return name ~= "" and name or nil
end

-- Makes a variant: a copy of `from` (a layout), or an empty one that
-- keeps `from`'s aliases, button names and meter (a fresh arrangement of
-- the same plugin). Saved straight away. Returns its key, or nil when
-- the name is unusable or already taken.
function M.new_variant(base, name, from, empty)
  name = M.clean_variant(name)
  if not name then return nil end
  local k = M.variant_key(base, name)
  if M.has(k) then return nil end
  local l = M.copy(from or { controls = {} })
  l.switch = nil
  if empty then
    l.controls = {}
    l.lock = nil
  end
  M.set(k, l)
  M.save()
  return k, name
end

-- Which of a plugin's layouts its instances use unless set to another:
-- a variant's name, or nil for the plugin's own. Kept in a section of its
-- own ("*default layouts*", one line per plugin), so the plugin's own
-- layout section -- or its absence, which means "generate one" -- is
-- left as it is.
M.DEFAULTS_SECT = "*default layouts*"
-- The Rack view keeps defaults of its own (a plugin may have a layout laid
-- out across and another laid out down): VIEW_DEFAULTS is the section this
-- window reads and writes, the rack's when it is the rack.
M.RACK_DEFAULTS_SECT = "*rack default layouts*"
M.VIEW_DEFAULTS = M.DEFAULTS_SECT
function M.default_variant(base, sect)
  local d = sections[sect or M.VIEW_DEFAULTS]
  local v = d and d[base]
  v = v and U.trim(v) or ""
  if v == "" or not M.has(M.variant_key(base, v)) then return nil end
  return v
end
function M.set_default_variant(base, name, sect)
  sect = sect or M.VIEW_DEFAULTS
  local d = sections[sect]
  if not d then
    d = {}
    sections[sect] = d
    order[#order + 1] = sect
  end
  d[base] = (name and name ~= "") and name or nil
  mark(sect)
end

-- The variants the library has for a plugin, by name, sorted.
function M.variants(base)
  local out, pre = {}, base .. M.VARIANT_SEP
  for _, k in ipairs(order) do
    if sections[k] and k:sub(1, #pre) == pre then out[#out + 1] = k:sub(#pre + 1) end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
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
-- ReaDelay and ReaVerbate get their own canvas (TS_CV_ReaFX), and by
-- default nothing beside it but ReaVerbate's dry and width; ReaGate's
-- and ReaLimit's defaults start with a gate and a limiter canvas.
function M.get_or_default(key, track, addr, cache_id)
  local RB = require("TS_CV_ReaFX")
  local saved = M.get(key)
  if saved then return RB.ensure(track, addr, cache_id, key, saved), false end
  local id = cache_id or (tostring(addr) .. ":" .. key)
  local d = def_cache[id]
  if not d then
    -- (another layout of theirs, never saved: a normal default)
    local kind = (not select(2, M.split_variant(key))) and RB.kind(key) or nil
    if kind == "readelay" then d = { controls = {}, aliases = {} }
    elseif kind == "reaverbate" then
      d = { controls = { { param = 1, type = "knob", label = "" }, { param = 4, type = "knob", label = "", bipolar = true } }, aliases = {} }
    else d = M.build_default(track, addr) end
    -- ReaGate's and ReaLimit's start with a canvas
    if RB.DEFAULT_CANVAS[kind or ""] then d = RB.default_canvas(track, addr, cache_id, kind, d) end
    def_cache[id] = d
  end
  return RB.ensure(track, addr, cache_id, key, d), true
end

-- The look new knobs and new buttons start with, taken from a control
-- (its Style menu > Use this look for new knobs/buttons): for automatic
-- layouts, new layouts and controls added in the editor. Kept in ExtState,
-- a key per field: knob = style, look, cap, ink, arc; button = style, cap.
local DEF_FIELDS = {
  knob   = { "style", "look", "cap", "scale_ink", "arc", "arcc" },
  toggle = { "style", "cap" },
}
local function def_key(fam, f) return "default_" .. fam .. "_" .. f end

function M.default_look(fam)
  local fields = DEF_FIELDS[fam]
  if not fields or not reaper.GetExtState
     or reaper.GetExtState(C.EXT_SECT, def_key(fam, "on")) ~= "1" then return nil end
  local d = {}
  for _, f in ipairs(fields) do
    local v = reaper.GetExtState(C.EXT_SECT, def_key(fam, f))
    if v ~= "" then d[f] = (f == "look") and KP.decode(v) or v end
  end
  return d
end

-- c: the control to take the look from, or nil to forget the default.
function M.set_default_look(fam, c)
  local fields = DEF_FIELDS[fam]
  if not fields then return end
  for _, f in ipairs(fields) do
    local v = c and c[f]
    if f == "look" and v then v = KP.encode(v) end
    if v and v ~= "" then reaper.SetExtState(C.EXT_SECT, def_key(fam, f), tostring(v), true)
    else reaper.DeleteExtState(C.EXT_SECT, def_key(fam, f), true) end
  end
  if c then reaper.SetExtState(C.EXT_SECT, def_key(fam, "on"), "1", true)
  else reaper.DeleteExtState(C.EXT_SECT, def_key(fam, "on"), true) end
  def_cache = {}
end

-- Give a new control the default look of its kind. A knob's arc follows
-- whether it's centred: a centred knob gets the Centred arc whenever the
-- default has an arc, and the rest get the default's (Positive when the
-- default is Centred).
function M.apply_default_look(c)
  local fam = (c.type == "knob" or c.type == "stepped") and "knob"
              or (c.type == "toggle") and "toggle" or nil
  local d = fam and M.default_look(fam)
  if not d then return c end
  c.style, c.cap = d.style, d.cap
  if fam == "knob" then
    c.look, c.scale_ink, c.arcc = KP.copy(d.look), d.scale_ink, d.arcc
    if d.arc then
      c.arc = c.bipolar and "mid" or ((d.arc == "mid") and "pos" or d.arc)
    end
  end
  return c
end

function M.build_default(track, addr)
  local controls = {}
  local own, total = U.own_param_count(track, addr)
  local limit = C.HIDE_BUILTIN and own or total
  local n = math.min(limit, C.AUTO_DEFAULT_N)
  for p = 0, n - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, p, "")
    controls[#controls + 1] = M.apply_default_look({
      param   = p,
      type    = U.guess_control_type(track, addr, p),
      bipolar = U.guess_bipolar(nm, track, addr, p),
      label   = "",      -- the plugin's own name shows by itself; a label would hide an alias
    })
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

-- Your own range for a parameter (RANGE<p>=<low>|<high>|<unit>|<curve>):
-- what it reads as when the plugin won't say. Per plugin, per parameter,
-- like a state's names (TS_CV_Util U.range_*).
function M.range_of_line(line)
  local f = {}
  for v in (U.trim(line or "") .. "|"):gmatch("([^|]*)|") do f[#f + 1] = U.trim(v) end
  local lo, hi = tonumber(f[1] or ""), tonumber(f[2] or "")
  if not lo or not hi then return nil end
  local unit = f[3] or ""
  local ok_u = false
  for _, u_ in ipairs(U.RANGE_UNITS) do if u_ == unit then ok_u = true end end
  local curve = f[4] or "lin"
  if curve ~= "log" and curve ~= "sq" then curve = "lin" end
  return { lo = lo, hi = hi, unit = ok_u and unit or "", curve = curve }
end
function M.range_line(r)
  if not (r and r.lo and r.hi) then return nil end
  return ("%g|%g|%s|%s"):format(r.lo, r.hi, r.unit or "", r.curve or "lin")
end
function M.get_range(key, param)
  local l = M.get(key)
  return l and l.ranges and l.ranges[param] or nil
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
  -- nothing of its own -- older layouts have one in every slot -- so it
  -- doesn't hide the alias.
  local own = plugin_name and U.trim(plugin_name) or ""
  if slot_label and slot_label ~= "" and U.trim(slot_label) ~= own then return slot_label end
  local a = M.get_alias(key, param)
  if a then return a end
  return plugin_name or ("P" .. tostring(param))
end

function M.set(key, layout)
  def_cache = {}
  -- the plugin's layout switching isn't the layout's to change: what the
  -- library has stays (M.set_switch_rules sets it), and a variant has none
  local base, var = M.split_variant(key)
  if var then layout.switch = nil
  else
    local had = cache[key] or (sections[key] and parse_section(sections[key]))
    layout.switch = M.copy_rules(had and had.switch)
  end
  cache[key] = layout
  sections[key] = serialize(layout)
  local found = false
  for _, s in ipairs(order) do if s == key then found = true break end end
  if not found then order[#order + 1] = key end
  mark(key)
end

-- The plugin's layout switching (its own layout's Switch<n>): a list of
-- rules, or nil.
function M.switch_rules(base)
  local l = M.get(base)
  return l and l.switch or nil
end
-- Sets it. The plugin's own layout is written for it when it has none yet
-- (`make()` builds it: the generated default it was showing). Saved.
function M.set_switch_rules(base, rules, make)
  local l = M.get(base)
  if not l then
    if not make then return false end
    l = make()
    if not l then return false end
  end
  l = M.copy(l)
  def_cache = {}
  l.switch = (rules and #rules > 0) and M.copy_rules(rules) or nil
  cache[base] = l
  sections[base] = serialize(l)
  local found = false
  for _, s_ in ipairs(order) do if s_ == base then found = true break end end
  if not found then order[#order + 1] = base end
  mark(base)
  M.save()
  return true
end

-- The value a virtual control of that name starts at, for a plugin:
-- from `controls` (the layout showing) when it has one, else from the
-- first of the plugin's layouts that does; 0 when none has.
function M.vstart(base, name, controls)
  local c = M.vfind(controls, name)
  if not c and base then
    local l = M.get(base)
    c = l and M.vfind(l.controls, name)
    if not c then
      for _, v in ipairs(M.variants(base)) do
        local lv = M.get(M.variant_key(base, v))
        c = lv and M.vfind(lv.controls, name)
        if c then break end
      end
    end
  end
  return c and c.virtual and c.virtual.start or 0, c
end

function M.remove(key)
  def_cache = {}
  cache[key] = nil
  sections[key] = nil
  for i = #order, 1, -1 do if order[i] == key then table.remove(order, i) end end
  mark(key, true)
end

-- Writes the library, keeping one generation of backup: this file is the
-- only place a hand-built layout lives, so a failed or interrupted write
-- should not be able to take it out entirely.
function M.save()
  if not dirty then return true end
  M.sync()            -- anything another window saved meanwhile, under ours
  local src = io.open(path(), "rb")
  if src then
    local data = src:read("a"); src:close()
    local bak = io.open(bak_path(), "wb")
    if bak then bak:write(data); bak:close() end
  end
  local ok, err = U.write_ini(path(), sections, order, HEADER)
  if ok then
    dirty = false
    changed = {}
    if reaper and reaper.SetExtState then
      my_rev = tostring(reaper.time_precise and reaper.time_precise() or os.clock()) .. ":" .. tostring(math.random(1e6))
      reaper.SetExtState(REV_SECT, REV_KEY, my_rev, false)
    end
  end
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
    if k:match("^Ctl%d+$") or k:match("^Alias%d+$") or k:match("^States%d+$") or k:match("^Range%d+$") or k == "Plate"
       or k == "Canvas" then
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
    changed[e.key] = true
    n = n + 1
    ::continue::
  end
  if n > 0 then def_cache = {}; dirty = true end
  return n
end

-- ---------------------------------------------------------------------
-- Copy and paste a control's look
-- ---------------------------------------------------------------------
-- What a control looks like, apart from what it is (its parameter, type,
-- label) and a dropdown's buttons: its style, colour, size (a fader's
-- shape), scale, background and finish. Pasting takes only what fits the
-- control it lands on: a style within its own kind (knob, fader or
-- button), the colour across kinds (as the nearest thing that kind
-- offers), size within the kind (a fader's shape fader to fader), the
-- scale on knobs, the background and finish on anything but a divider.

-- "knob" (a stepped or concentric knob too), "fader", "xy", "button" (a
-- toggle, or a dropdown shown as buttons), or nil for anything with no
-- style of its own.
function M.look_family(c)
  if not c then return nil end
  if c.type == "knob" or c.type == "stepped" or c.type == "dual" or c.type == nil then return "knob" end
  if c.type == "xy" then return "xy" end
  if c.type == "fader" then return "fader" end
  if c.type == "toggle" or (c.type == "combo" and c.buttons) then return "button" end
  return nil
end

function M.look_of(c)
  return { fam = M.look_family(c), type = c.type, style = c.style, cap = c.cap, size = c.size,
           scale = c.scale, scale_ink = c.scale_ink, arc = c.arc, arcc = c.arcc, back = c.back, brush = c.brush, metal = c.metal,
           finish = c.finish, corners = c.corners, look = KP.copy(c.look),
           style2 = c.style2, look2 = KP.copy(c.look2),
           dir = c.dir, len = c.len, thin = c.thin }
end

-- the colour a look actually shows: its own, or its style's
local function shown_cap(s)
  if s.cap then return s.cap end
  local st = (s.fam == "knob" and C.KNOB_STYLE[C.KNOB_STYLE_ALIAS[s.style] or s.style or "arc"])
          or (s.fam == "fader" and C.FADER_STYLE[s.style or "flat"]) or nil
  return st and st.cap or nil
end

-- A look's colour for a control of kind `fam`: the same key where the
-- kinds share a palette (knobs and faders), else the same name in that
-- kind's palette, or the same colour, or it as a custom one; the theme's
-- own (nil) when it has none.
local function cap_for(fam, s)
  if fam == s.fam then return s.cap end
  local key = shown_cap(s)
  if key == nil then return nil end
  local custom = C.custom_key(key)
  if custom then return custom end
  local to_button, from_button = fam == "button", s.fam == "button"
  if to_button == from_button then return key end
  local src = (from_button and C.TOGGLE_COL or C.CAP)[key]
  if not (src and src.col) then return nil end
  -- the same name first (a knob's red is a button's red), then the same colour
  local dst = to_button and C.TOGGLE_COL or C.CAP
  if dst[key] and dst[key].col then return key end
  for _, t in ipairs(to_button and C.TOGGLE_COLS or C.CAPS) do
    if t.col == src.col then return t.key end
  end
  return ("#%06x"):format(src.col >> 8)
end

-- Paste look `s` (M.look_of) onto control `o`, in place. True when there
-- was anything it could take.
function M.paste_look(o, s)
  if not (o and s) or o.type == "divider" then return false end
  local fam = M.look_family(o)
  if fam then
    if fam == s.fam then o.style = s.style end
    o.cap = cap_for(fam, s)
    if fam == "knob" and s.fam == "knob" then
      o.scale, o.scale_ink, o.arc, o.arcc = s.scale, s.scale_ink, s.arc, s.arcc
      -- a value arc says whether the knob is centred
      if s.arc then o.bipolar = (s.arc == "mid") or nil end
      -- its own look, built from parts (on a concentric knob, the outer's),
      -- and a concentric knob's inner one from another concentric knob
      o.look = KP.copy(s.look)
      if o.type == "dual" and s.type == "dual" then o.style2, o.look2 = s.style2, KP.copy(s.look2) end
      -- a concentric knob comes medium or large
      if not (o.type == "dual" and s.size == "small") then o.size = s.size end
    elseif fam == "xy" and s.fam == "xy" then
      o.size = s.size
    elseif fam == "fader" and s.fam == "fader" then
      -- a fader's shape goes to a fader: which way, how long, how thick
      o.dir, o.len, o.thin = s.dir, s.len, s.thin
    elseif o.type == "toggle" and s.type == "toggle" then
      o.size = s.size
    end
  end
  -- a hardware switch is a toggle's alone: a button row stays flat
  if o.type ~= "toggle" and o.style and C.SWITCH[o.style] then o.style = nil end
  o.back, o.brush, o.metal, o.finish, o.corners = s.back, s.brush, s.metal, s.finish, s.corners
  return true
end

-- Deep copy, so the editor can work on a scratch layout and discard it.
function M.copy(layout)
  local out = { controls = {}, aliases = {}, live = layout.live,
                measure = layout.measure, levels = layout.levels,
                own_w = layout.own_w, own_h = layout.own_h,
                plate = layout.plate, brush = layout.brush, metal = layout.metal, finish = layout.finish,
                lock = layout.lock, palette = M.palette_of(M.palette_line(layout.palette)),
                grid = layout.grid and { cols = layout.grid.cols, rows = layout.grid.rows } or nil }
  if layout.meter then
    out.meter = { on = layout.meter.on, range = layout.meter.range, win = layout.meter.win }
  end
  for i, c in ipairs(layout.controls or {}) do
    out.controls[i] = { param = c.param, type = c.type, bipolar = c.bipolar,
                        invert = c.invert, no_rule = c.no_rule, live = c.live,
                        label = c.label, style = c.style, cap = c.cap, size = c.size,
                        buttons = c.buttons, nbtn = c.nbtn, back = c.back, brush = c.brush,
                        metal = c.metal, finish = c.finish, corners = c.corners, look = KP.copy(c.look),
                        style2 = c.style2, look2 = KP.copy(c.look2),
                        scale = c.scale, scale_ink = c.scale_ink, arc = c.arc, arcc = c.arcc,
                        dir = c.dir, len = c.len, thin = c.thin, param2 = c.param2,
                        invert2 = c.invert2, edge = c.edge,
                        at = c.at and { c = c.at.c, r = c.at.r, w = c.at.w, h = c.at.h } or nil,
                        show = c.show and { param = c.show.param, vname = c.show.vname, op = M.show_op(c.show),
                                            norm = c.show.norm, norm2 = c.show.norm2,
                                            tol = c.show.tol } or nil,
                        virtual = c.virtual and { start = c.virtual.start, choices = { table.unpack(c.virtual.choices or {}) },
                                                  actions = c.virtual.actions and M.vact_of(M.vact_line(c.virtual.actions, 64)) or nil } or nil }
  end
  out.controls.grid = out.grid
  for p, n in pairs(layout.aliases or {}) do out.aliases[p] = n end
  out.canvas = M.copy_canvas(layout.canvas)
  out.switch = M.copy_rules(layout.switch)
  out.states = {}
  for p, st in pairs(layout.states or {}) do out.states[p] = { st[1], st[2] } end
  if layout.ranges then
    out.ranges = {}
    for p, rg in pairs(layout.ranges) do out.ranges[p] = { lo = rg.lo, hi = rg.hi, unit = rg.unit, curve = rg.curve } end
  end
  return out
end

return M
