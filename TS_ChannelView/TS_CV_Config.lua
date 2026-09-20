-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Config.lua -- ChannelView tunables.

  Everything here is meant to be edited by hand. Nothing in this file
  touches REAPER, so it can be reloaded freely while designing the look.
--]]

local C = {}

C.VERSION   = "1.0.1"
C.EXT_SECT  = "TS_ChannelView"       -- reaper.SetExtState section
C.WIN_TITLE = "ChannelView"

-- ---------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------
-- A control occupies one CELL. Panels are a fixed HEIGHT (they fill the
-- window) and grow in COLUMNS: controls flow top-to-bottom down a column,
-- then wrap into a new column to the right, which widens the panel.
C.CELL_W      = 58        -- width of one control cell
C.CELL_H      = 64        -- height of one control cell (name + knob + value)
C.KNOB_D      = 34        -- knob diameter within the cell
C.LABEL_GAP   = 5         -- air between the name and the control under
                          -- it. Two pixels read as the text sitting ON
                          -- the knob. The cell height is fixed, so this
                          -- and KNOB_D trade against each other: name
                          -- band + gap + knob has to leave room for the
                          -- value line at the bottom.
C.PANEL_PAD   = 6         -- inner padding around a panel's control grid
-- The top of the grid. Tried tighter than the sides once; it pulled the
-- whole row up under the header and read worse, not better. The air
-- between a cell's name and its knob is the thing that wanted adjusting,
-- and that is LABEL_GAP below.
C.GRID_TOP_PAD = C.PANEL_PAD
C.PANEL_GAP   = 6         -- gap between adjacent panels
C.HEADER_H    = 20        -- panel header bar height
C.PANEL_MIN_W = 132       -- a panel never narrower than this (header needs room)
C.STRIP_H     = 30        -- bottom track-selector strip height
C.MIN_ROWS    = 1         -- never compute fewer rows than this

-- Control flow within a panel:
--   "column" -- fill a column top-to-bottom, then start a new column.
--              Neighbours stay put when the dock height changes.
--   "row"    -- fill a row left-to-right, then start a new row.
--              Reads like the Fender layout, but every control moves
--              when the dock is resized.
C.FLOW = "column"

-- ---------------------------------------------------------------------
-- Behaviour
-- ---------------------------------------------------------------------
C.RESCAN_INTERVAL = 0.5   -- seconds between FX-chain rescans
C.DRAG_SENS       = 0.006 -- normalised units per pixel of vertical drag
C.FINE_MULT       = 0.15  -- multiplier while Shift is held
C.WHEEL_STEP      = 0.02  -- normalised units per mouse-wheel notch
C.SHOW_VALUES     = true  -- value text under each knob (else hover only)
C.AUTO_DEFAULT_N  = 8     -- controls auto-shown for an unmapped plugin
C.HIDE_BUILTIN    = true  -- hide REAPER's trailing Wet/Bypass/Delta params
                          -- from the auto-default (still assignable by hand)

-- Header buttons are drawn as vector icons on the draw list rather than
-- set as text, so they don't depend on the font having the glyph and they
-- stay crisp at any size. See TS_CV_Widgets.icon_button / W.ICONS.
C.ICON_SIZE = 14          -- header button hit area (the glyph sits inside)

-- Collapsed panels: a narrow vertical bar carrying the name, bypass and
-- float only. Wide enough for the icons plus stacked capitals.
-- Wide enough for the meter's stacked readout ("12.4" over "dB") when a
-- collapsed panel is metering; without those few extra pixels the decimal
-- would have to be dropped exactly where the bar is the only thing you
-- can see.
-- Collapsed panels run their label down the bar. Two ways of doing that:
-- letters stacked one per line, or the label genuinely rotated.
--
-- OFF, because the rotated version came out unreadable. ImGui cannot
-- rotate text at all, so the rotated path draws the label into a LICE
-- bitmap and hands ImGui an image to put on a turned quad -- and LICE
-- has no idea what size ImGui is actually rendering at. On a scaled
-- display ImGui reports a font size of 12 while drawing considerably
-- larger, so the bitmap comes back small and thin and the quad stretches
-- it. Fixing it means finding ImGui's real pixel height, which
-- GetFontSize does not give.
--
-- The code is still here and still works where the scaling happens to be
-- 1:1. Turn this on to try it.
C.ROT_TEXT  = false       -- true rotates; false stacks the letters
C.ROT_FONT  = "Arial"     -- the LICE side has no access to ImGui's font
C.ROT_UP    = true        -- reading bottom-to-top, the way a book spine
                          -- does everywhere except the United States

C.COLLAPSED_W = 30

-- Gain-reduction meter: a full-height strip down the edge of the panel
-- body, NOT a cell in the parameter grid. A cell would be 58px wide for
-- one read-only value and would push every panel a whole column wider;
-- this costs a quarter of that. Being full height also means it works
-- unchanged in a collapsed panel, which a grid cell cannot.
-- The BAR stays thin; the readout underneath gets a wider footprint and
-- a smaller font, so "6.4 dB" fits without fattening the meter itself.
-- The whole column is still well under a 58px cell.
-- Sized so the widest readout the ladder can produce -- "60.0 dB" -- fits
-- on one line. The bar itself stays thin; only its column is this wide,
-- and it's still well under a 58px cell.
C.METER_W     = 14        -- the bar
C.METER_COL_W = 40        -- bar plus the room its readout needs
C.METER_FONT  = 10        -- point size for the readout
C.METER_SIDE = "left"     -- "left" or "right" edge of the panel body
C.MAX_GR_DB  = 12         -- per-plugin MINIMUM full scale (it grows, below)
C.GR_HOLD    = 1.2        -- seconds the peak line holds before falling
C.GR_FALL    = 18         -- dB per second it falls once released

-- The scale grows when reduction exceeds it, so a meter set for gentle bus
-- compression still tells the truth when something slams. It steps between
-- fixed rungs rather than scaling continuously -- a scale that moved with
-- every transient would be unreadable -- and only steps back down once the
-- peak has stayed below the smaller rung for a while.
C.GR_LADDER      = { 6, 12, 20, 30, 40, 60 }

-- Learning a stepped parameter's choices means briefly sweeping it -- the
-- API has no read-only enumeration -- so by default that waits until the
-- transport stops. The sweep itself is over in well under a millisecond,
-- so it is unlikely to be audible; the reasons to wait are that some
-- plugins do expensive work on a parameter change (convolution reloads,
-- linear-phase kernels, oversampling reallocations) and sweeping one of
-- those mid-playback can cause a dropout.
--
-- Setting this true accepts that risk. It does NOT override the automation
-- guard: a sweep while write/touch/latch is recording would write the
-- whole sweep into the lane, so that is refused regardless.
--
-- Either way the list is cached once scanned, so it stays available while
-- playing, and a panel drawn even briefly while stopped will have scanned
-- already.
C.SCAN_WHILE_PLAYING = false

-- How many stepped parameters may be swept in one frame. The first frame a
-- chain is drawn would otherwise try to scan every one of them at once --
-- six plugins with a few stepped parameters each is hundreds of writes in
-- a single frame, and it shows. Spread over frames the same work is
-- finished within a second and nothing stutters. Results are cached to
-- disk, so this cost is paid once per plugin, not once per session.
C.SCAN_BUDGET = 2
C.GR_RANGE_RELAX = 3.0    -- seconds before the scale steps back down

-- ---------------------------------------------------------------------
-- The pinned panels
-- ---------------------------------------------------------------------
-- Channel sits hard left and Sends hard right, outside the scrolling row,
-- so the fader and the sends stay put however far you scroll through a
-- long chain. Both collapse to the same narrow bar a plugin panel does.
-- Fader and meter split the panel's inner width in half each, so the two
-- read as a balanced pair rather than a fader with an afterthought beside
-- it. FADER_W is just the moving part; its half is wider than that.
C.CHANNEL_W   = 112       -- expanded width of the Channel panel
                          -- (fader and meter take half each, and the
                          --  meter's scale needs room for its numbers)
C.FADER_W     = 26        -- the fader's own track within its half
C.FADER_CAP_H = 16        -- the moving cap: big enough to grab and to
                          -- read the unity mark against
C.LEVEL_METER_W = 44      -- the level meter's own width within its half,
                          -- so it sits centred like the fader rather than
                          -- flush against the panel edge. (C.METER_W, way
                          -- above, is the GAIN REDUCTION bar -- different
                          -- meter, different panel.)
-- A send is a DOUBLE-WIDTH cell on the same grid the plugin panels use,
-- so sends line up row-for-row with parameters: knob in the left half,
-- its buttons in the right. The add tile is simply the next cell.
C.SEND_W      = 2 * C.CELL_W
-- Air between columns of sends. The parameter grid doesn't need any --
-- its cells are a knob and a name and read as a grid on their own -- but
-- a send is a name, a knob and three buttons, so two columns hard against
-- each other read as one wide cell with too much in it.
C.SEND_COL_GAP = 7
C.SENDS_MAX_W = 3 * C.SEND_W + C.SEND_COL_GAP * 2 + C.PANEL_PAD * 2

-- Level metering: floor of the scale, and how the peak behaves.
C.METER_FLOOR = -60       -- dB at the bottom of the level meter
C.METER_MARKS = { 0, -6, -12, -24, -48 }   -- labelled on the channel meter
C.LEVEL_HOLD  = 1.2       -- seconds the peak line holds
C.LEVEL_FALL  = 24        -- dB per second it falls after that
C.LEVEL_CLIP  = 0.0       -- at or above this the meter goes hard red
C.LEVEL_HOT   = -0.2      -- and below it, merely hot
-- The averaging window for the RMS reading. REAPER exposes no sample-level
-- RMS, so this is the RMS of the per-frame PEAK envelope -- a fast VU, in
-- other words. Longer reads steadier and lags more.
C.RMS_WINDOW  = 0.30      -- seconds

-- Fader range when REAPER's own taper isn't available as a fallback.
C.FADER_MIN_DB = -60
C.FADER_MAX_DB = 12

-- A divider is a full-height rule between groups of controls inside one
-- panel -- "these knobs are the EQ, those are the dynamics". Narrower than
-- a cell, since it separates rather than occupies.
C.DIVIDER_W = 9

-- Dragging a panel header past this many pixels starts a reorder rather
-- than counting as a click.
C.DRAG_THRESHOLD = 4

-- Track strip buttons are a fixed width so the strip reads as a row of
-- equal slots, like a console, instead of jumping around with name length.
C.TRACK_BTN_W = 104

-- Pixels of sideways scroll per wheel notch, in the panel row and the
-- track strip.
C.WHEEL_SCROLL_PX = 70

-- The trailing "+" tile that adds a plugin to the end of the chain.
C.ADD_TILE_W = 34

-- Track strip visible by default; the View menu toggles it and the choice
-- is remembered.
C.SHOW_TRACKS = true

-- Breathing room between the track-colour hairline and the top of the
-- panels, so the panel borders don't sit on the rule.
C.ROW_TOP_GAP = 5

-- Vertical padding inside the header (menu) bar. ImGui works the bar's
-- height out from FramePadding when the window opens, so this is the one
-- number that moves it. 4 lands the track-colour rule level with the
-- Track Analyser's, measured off a screenshot of the two docked together
-- -- every point here is two pixels of header, top and bottom.
C.MENU_PAD_Y = 6

-- Header height, derived at RUNTIME with no style constants assumed.
--
-- The track-colour rule has to land on the same line as Track Analyser's.
-- TA_Panel.lua pushes no WindowPadding, ItemSpacing or FramePadding of
-- its own -- STYLE_VAR carries only rounding and border sizes -- so its
-- rule sits at whatever ReaImGui's defaults happen to be:
--
--   WindowPadding.y     Begin puts the cursor here
--   + the header row    Text, a SmallButton, a combo and a drag: the
--                       frame widgets are the tallest, so GetFrameHeight
--   + ItemSpacing.y     before the next item, which is the rule
--
-- Writing those defaults down as numbers is what kept this two or three
-- pixels out: ReaImGui's are not ImGui's, and this build exposes no
-- GetStyleVar to ask. So none of them is written down. We DON'T push a
-- WindowPadding either, which leaves ours equal to TA's, and then:
--
--   cursor_after_menu_bar  = window_top + MenuBarHeight + WindowPadding.y
--   MenuBarHeight          = GetFontSize() + 2 * MENU_PAD_Y   (we set it)
--   ItemSpacing.y          = GetTextLineHeightWithSpacing() - GetTextLineHeight()
--
-- so subtracting the menu bar recovers window_top + WindowPadding.y
-- without ever knowing what WindowPadding is, and the rest is read the
-- same way. Font size, DPI and ReaImGui's own theme all cancel.
-- The main window asks for no scrollbar, which is what lets the header
-- measurement above ignore any bottom decoration. Named here because a
-- test checks the two stay in step.
C.WIN_NO_SCROLLBAR = true

-- How thick the track-colour rule is: the same 2 TA_Panel draws, so that
-- the two land on the same number of pixels for the same reason.
--
-- Both windows draw a 2px rect at a y that usually carries a half pixel,
-- so both cover three rows at the top and two at the bottom. Setting
-- ours to 3 to "match what renders" produced four -- fixing the symptom
-- one layer above the cause, which is how you end up a pixel out in the
-- other direction.
C.RULE_H = 2

-- The residual between where the calculation puts the rule and where
-- Track Analyser's lands. It is ZERO, and the derivation stands on its
-- own. Keep it that way: a number here means something above it is wrong.
--
-- It was briefly -6, then -2, and both were measuring the same mistake.
-- The rule was clamped to our own content start, which sits BELOW where
-- TA's rule goes -- we have a menu bar, TA does not -- so the clamp
-- discarded the answer every frame and the nudge behind it did nothing.
-- Once the clamp was corrected the -2 was still there, overcorrecting by
-- exactly itself. The metrics from a real session:
--
--   font 12.0   frame_h 20.5   itemspacing_y 4.0
--   window 536 high, content start 36.5, avail 491.5 -> WindowPadding.y 8.0
--
-- 8 + 20.5 + 4 = 32.5, and TA's rule measures 32.5 below the same window
-- top. Exactly.
--
-- One half-pixel remains, and it is not ours to fix. Measured side by
-- side: the BOTTOM rules land on identical rows, and at the top TA's
-- covers three rows to our two. Both draw the same 2px rect; TA's
-- happens to straddle a pixel boundary and ours lands on one, so ours is
-- the crisper of the two. That is the two panes starting half a pixel
-- apart in the docker, not a difference in the arithmetic.
--
-- This accepts fractions, so -0.5 here makes ours straddle the same way
-- and cover the same three rows. It trades a crisp rule for a matching
-- one; left at 0 because a blurred edge to imitate somebody else's
-- rounding is a strange thing to ship.
C.HEADER_NUDGE = 0

-- The gap a TCP spacer opens in the track strip along the bottom.
C.STRIP_SPACER = 14

-- Where the panels sit when they're narrower than the window:
--   "left"   -- packed against the left edge
--   "centre" -- centred in the window
-- Either way, once they overflow they pack left and the row scrolls.
C.ROW_ALIGN = "left"


-- ---------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------
-- The palette is generated from ONE hue, so it can be pulled into line
-- with a REAPER theme without editing thirty hex values. Each entry is
-- { role, hue offset from the base, saturation, lightness }:
--
--   "tint"  -- the greys. They aren't neutral grey; they lean slightly
--             toward the base hue, which is what keeps a dark UI from
--             looking muddy. C.TINT scales how far they lean: 0 is true
--             grey, 1 is as designed, higher is more colourful.
--   "solid" -- the accent family, following the base hue at full
--             saturation. The bipolar knob fill sits ~180 degrees away so
--             it stays a real contrast whatever the base becomes.
--   "alert" -- bypass and warnings. Pinned to C.ALERT_HUE and deliberately
--             NOT following the base: a bypassed plugin should still read
--             as bypassed even if you theme everything else amber.
--   "fixed" -- transport and channel states: record red, solo amber,
--             monitor green. These are conventions older than any theme,
--             and a green record button would be a lie however nicely it
--             matched. The offset here is an ABSOLUTE hue, not relative
--             to the base.
--
-- Lightness is never touched by any of this. The contrast relationships
-- are what make the thing readable, and they shouldn't be at the mercy of
-- a colour picker.

C.BASE_HUE  = 219      -- degrees, 0-360
C.TINT      = 1.0      -- how far the greys lean toward the base hue
C.ALERT_HUE = 17       -- bypass / warning hue, independent of the base

C.PALETTE = {
  win_bg        = { "tint",    7.7, 0.209, 0.084 },
  panel_bg      = { "tint",    4.6, 0.169, 0.127 },
  panel_border  = { "tint",    3.4, 0.162, 0.206 },
  header_bg     = { "tint",    2.2, 0.186, 0.169 },
  header_bg_byp = { "alert",    1.0, 0.135, 0.145 },
  header_text   = { "tint",    3.9, 0.206, 0.867 },
  header_dim    = { "tint",   -3.0, 0.100, 0.512 },
  label         = { "tint",   -2.1, 0.148, 0.655 },
  value         = { "tint",    3.9, 0.206, 0.867 },
  knob_track    = { "tint",    0.0, 0.164, 0.239 },
  knob_fill     = { "solid",  -14.0, 0.661, 0.573 },
  knob_fill_bi  = { "solid",  178.2, 0.645, 0.569 },
  knob_body     = { "tint",    1.0, 0.165, 0.178 },
  knob_body_hi  = { "tint",   -2.3, 0.161, 0.220 },
  knob_pointer  = { "tint",   -2.1, 0.394, 0.935 },
  knob_ring     = { "tint",    1.0, 0.147, 0.280 },
  toggle_off    = { "tint",    2.2, 0.160, 0.196 },
  toggle_on     = { "solid",  -14.0, 0.661, 0.573 },
  toggle_text   = { "tint",    3.9, 0.206, 0.867 },
  accent        = { "solid",  -14.0, 0.661, 0.573 },
  warn          = { "alert",   -0.1, 0.645, 0.569 },
  strip_bg      = { "tint",    6.0, 0.160, 0.098 },
  strip_sel     = { "solid",  -14.0, 0.661, 0.573 },
  empty_text    = { "tint",    0.1, 0.109, 0.414 },
  drop_marker   = { "solid",  -14.0, 0.661, 0.573 },
  header_drag   = { "tint",   -1.9, 0.183, 0.225 },
  icon          = { "tint",   -2.1, 0.148, 0.655 },
  icon_hot      = { "tint",   -2.1, 0.394, 0.935 },
  icon_on       = { "tint",   -5.7, 0.257, 0.069 },
  bypass_on     = { "alert",   -0.1, 0.645, 0.569 },
  float_on      = { "solid",  -14.0, 0.661, 0.573 },
  fader_cap  = { "tint",   -2.3, 0.196, 0.820 },
  level_lo   = { "fixed",  130.2, 0.388, 0.475 },
  level_hi   = { "fixed",   43.1, 0.645, 0.569 },
  level_clip = { "fixed",   16.9, 0.645, 0.569 },
  -- Clipping is a different KIND of news from "hot", so it gets a colour
  -- of its own rather than more of the same orange: pure red, and lighter
  -- than anything else on the meter so it reads at a glance.
  level_over = { "fixed",    0.0, 0.870, 0.560 },
  level_rms  = { "fixed",  130.2, 0.330, 0.720 },
  rec_on     = { "fixed",  358.8, 0.650, 0.563 },
  solo_on    = { "fixed",   43.1, 0.645, 0.569 },
  mute_on    = { "fixed",   16.9, 0.645, 0.569 },
  mon_on     = { "fixed",  130.2, 0.388, 0.475 },
  mon_auto   = { "fixed",  213.0, 0.645, 0.569 },
}

-- Plugin formats get a swatch each, and the hues are ABSOLUTE rather than
-- theme-following: the badge is an identity, not decoration, and it has to
-- mean the same thing whatever the base hue is set to. Anything not listed
-- falls back to a neutral grey, so a format REAPER learns about later
-- still looks deliberate.
C.FORMAT_HUE = {
  VST3  = 208,   -- Steinberg blue
  VST   = 262,   -- the older one, clearly a different colour
  CLAP  = 28,    -- amber
  AU    = 140,   -- Apple green
  LV2   = 320,
  JS    =  50,   -- REAPER's own
  DX    = 180,
}

-- HSL -> 0xRRGGBBAA. Hue in degrees, s and l in 0..1.
local function hsl(h, s, l, a)
  h = (h % 360) / 360
  s = math.max(0, math.min(1, s))
  l = math.max(0, math.min(1, l))
  local function hue2(p, q, t)
    if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
    if t < 1/6 then return p + (q - p) * 6 * t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
    return p
  end
  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
    local p = 2 * l - q
    r, g, b = hue2(p, q, h + 1/3), hue2(p, q, h), hue2(p, q, h - 1/3)
  end
  local function b8(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return (b8(r) << 24) | (b8(g) << 16) | (b8(b) << 8) | (a or 0xff)
end
C.hsl = hsl

-- Rebuilds C.COL in place from C.PALETTE. Call after changing BASE_HUE or
-- TINT. In place matters: other modules hold a reference to C.COL.
-- Filled by build_palette: format -> { bg, fg }.
C.FORMAT_COL = {}

function C.build_palette()
  C.COL = C.COL or {}
  for name, e in pairs(C.PALETTE) do
    local role, dh, sat, lum = e[1], e[2], e[3], e[4]
    local h, s
    if role == "fixed" then
      h, s = dh, sat
    elseif role == "alert" then
      h, s = C.ALERT_HUE + dh, sat
    elseif role == "tint" then
      h, s = C.BASE_HUE + dh, sat * C.TINT
    else
      h, s = C.BASE_HUE + dh, sat
    end
    C.COL[name] = hsl(h, s, lum, 0xff)
  end

  -- Format badges. Saturated enough to tell apart at 30 pixels wide, dark
  -- enough that white text sits on them, and a shared lightness so no one
  -- format shouts louder than another.
  C.FORMAT_COL = {}
  for fmt, hue in pairs(C.FORMAT_HUE) do
    C.FORMAT_COL[fmt] = { bg = hsl(hue, 0.52, 0.34, 0xff),
                          fg = hsl(hue, 0.30, 0.93, 0xff) }
  end
  C.FORMAT_COL.__other = { bg = hsl(C.BASE_HUE, 0.06, 0.30, 0xff),
                           fg = hsl(C.BASE_HUE, 0.05, 0.80, 0xff) }

  return C.COL
end

-- The badge colours for a format string, never nil.
function C.format_col(fmt)
  return C.FORMAT_COL[fmt or ""] or C.FORMAT_COL.__other
end

C.build_palette()

return C
