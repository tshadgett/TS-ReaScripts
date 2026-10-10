-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Config.lua -- ChannelView tunables.

  Everything here is meant to be edited by hand. Nothing in this file
  touches REAPER, so it can be reloaded freely while designing the look.
--]]

local C = {}

C.VERSION   = "1.1.0"
C.EXT_SECT  = "TS_ChannelView"       -- reaper.SetExtState section
C.WIN_TITLE = "ChannelView"

-- ---------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------
-- A control occupies one CELL. Panels are a fixed HEIGHT (they fill the
-- window) and grow in COLUMNS: controls flow top-to-bottom down a column,
-- then wrap into a new column to the right, which widens the panel.
C.CELL_W      = 50        -- width of one control cell (View > Control spacing)
-- View > Control spacing moves the cell width between these (one setting
-- for ChannelView, its TCP window and the web page); the cell's height,
-- the knobs and the type stay as they are, only the air between columns
-- changes. Below the minimum a knob's scale ticks would touch.
C.CELL_W_DEFAULT, C.CELL_W_MIN, C.CELL_W_MAX = 50, 46, 64
function C.set_cell_w(v)
  v = math.floor(tonumber(v) or C.CELL_W_DEFAULT)
  C.CELL_W = math.max(C.CELL_W_MIN, math.min(C.CELL_W_MAX, v))
end
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
C.TAB_STRIP_H = 18        -- a paged panel's tab strip, under its header (TS_CV_Panel P.pages)
C.FOOTER_H    = 20        -- a panel's foot: the layout lock, and the preset bar
C.SCROLL_W    = 8         -- a locked panel's scrollbar, when it's too short
C.PRESET_BAR  = true      -- View > Preset bar (persisted)
C.PANEL_MIN_W = 132       -- a panel never narrower than this (header needs room)
C.STRIP_H     = 30        -- bottom track-selector strip height (see C.set_icon_row)
C.STRIP_BASE_H = C.STRIP_H  -- that height with no icon row
C.ICON_ROW_H  = 44        -- what an icon row adds: stripe and icon

-- The name row grows by C.ICON_ROW_H while track icons are shown. Every
-- layout that depends on the row's height reads C.STRIP_H, so changing
-- it here, once, at the start of a frame, keeps both views and the
-- mixer strips in agreement exactly as before.
function C.set_icon_row(on)
  C.STRIP_H = C.STRIP_BASE_H + (on and C.ICON_ROW_H or 0)
end
C.MIN_ROWS    = 1         -- never compute fewer rows than this

-- "trackrow" (the track-name row shared by both views, and its own
-- padding probe, MX.row_pad_y) push THIS as their vertical WindowPadding
-- instead of taking ReaImGui's own default -- measured at 8.0 on the
-- themes this has been tested against (see the track-rule derivation in
-- TS_ChannelView.lua for how that 8.0 was read off, with no GetStyleVar
-- to just ask for it). A full WindowPadding's worth of empty space sits
-- both above the track buttons and below them, under the scrollbar --
-- more than either edge needs just to keep the buttons off the border
-- and the scrollbar off the button row. This is applied to trackrow and
-- ONLY trackrow (PushStyleVar/PopStyleVar around its BeginChild/EndChild,
-- and identically around row_pad_y's probe, so the probe keeps measuring
-- what the real row actually gets) -- horizontal WindowPadding is left
-- exactly as ReaImGui set it, measured rather than guessed at, so the
-- track buttons don't shift sideways as a side effect of this.
C.TRACKROW_PAD_Y = 4

-- Only used on the vanishingly unlikely frame where the child-window
-- padding probe in TS_ChannelView.lua itself gets culled, so there is
-- no real measurement to fall back on yet. Scaled down from the 14 that
-- matched the probe under ReaImGui's own default WindowPadding, by the
-- same amount TRACKROW_PAD_Y trims off each of the two edges (8 -> 4 is
-- 4 fewer pixels top and bottom). Being exactly right barely matters --
-- this frame is rare enough that it was never observed, only guarded
-- against -- but it should stay in the right ballpark rather than drift
-- back toward the old, larger default.
C.CHILD_PAD_Y_FALLBACK = 6

-- Control flow within a panel:
--   "column" -- fill a column top-to-bottom, then start a new column.
--              Neighbours stay put when the dock height changes.
--   "row"    -- fill a row left-to-right, then start a new row.
--              Reads like the Fender layout, but every control moves
--              when the dock is resized.
C.FLOW = "column"

-- Knob sizes, in half-cells across and down (TS_CV_Panel.layout), and the
-- knob's diameter at each. Medium is the one cell every control has always
-- been. A small knob has its name in small type over a smaller dial and no
-- room for its value, which goes in its tooltip; a large one keeps both
-- and grows its dial about half again.
C.SIZES = {
  small  = { w = 2, h = 1, d = 18,       label = "Small" },
  medium = { w = 2, h = 2, d = C.KNOB_D, label = "Medium" },
  large  = { w = 3, h = 3, d = 52,       label = "Large" },
}
C.SIZE_LIST = { "small", "medium", "large" }

-- A dropdown can show its choices as buttons instead (a control's
-- right-click menu, Show as): across, one half-cell column per choice,
-- under its name; or down, a column of buttons two to a half-row. Past
-- this many choices it stays a dropdown.
C.BUTTONS_MAX = 8

-- ---------------------------------------------------------------------
-- Behaviour
-- ---------------------------------------------------------------------
C.RESCAN_INTERVAL = 0.5   -- seconds between FX-chain rescans
C.DRAG_SENS       = 0.006 -- normalised units per pixel of vertical drag
C.FINE_MULT       = 0.15  -- multiplier while Shift is held
C.WHEEL_STEP      = 0.02  -- normalised units per mouse-wheel notch
C.SHOW_VALUES     = true  -- value text under each knob (else hover only)
C.WHEEL_CONTROLS  = true  -- the mouse wheel turns the control under it (View menu;
                          -- off, it only ever scrolls)
C.AUTO_DEFAULT_N  = 8     -- controls auto-shown for an unmapped plugin
C.HIDE_BUILTIN    = true  -- hide REAPER's trailing Wet/Bypass/Delta params
                          -- from the auto-default (still assignable by hand)

-- Header buttons are drawn as vector icons on the draw list rather than
-- set as text, so they don't depend on the font having the glyph and they
-- stay crisp at any size. See TS_CV_Widgets.icon_button / W.ICONS.
C.ICON_SIZE = 14
-- The track strip along the bottom and the mixer above it are ONE thing:
-- every button lines up under its own strip, and scrolls with it. So the
-- gap between them is a single number rather than one each, and a button
-- takes its width from the strip above rather than a fixed size.
C.MIX_GAP = 4

-- The strip header's name. Off by default: the track button directly
-- underneath carries the name already, and now that the two line up,
-- printing it twice in a column an inch tall is just noise.
C.MIX_STRIP_NAME = false

-- Draw REAPER's track icons (P_ICON) above the name buttons. Off by
-- default; the View menu setting overrides this.
C.TRACK_ICONS = false

-- What marks the selected strip, and the selected button under it:
--   "track"   -- a lightened version of that track's own colour
--   "accent"  -- C.COL.strip_sel, the same colour for every track
-- "track" by default. A console is a row of coloured channels with one
-- of them lit; one blue outline in among them reads as a different KIND
-- of thing rather than as the same thing selected.
C.SEL_OUTLINE = "track"

-- The corner radius of a mixer strip. Its header is capped to the same
-- radius and its outline traced at it, so the three agree about what
-- shape a strip is -- and the track button below uses it too.
C.STRIP_ROUND = 3.0

-- Unselected strips and track buttons are dimmed to this alpha, so the
-- selected one is the only thing at full strength, and lift to the
-- hover alpha under the mouse. The mixer header and the track button
-- below it use the SAME pair: they are one object, and a header at full
-- colour over a dimmed name badge looked like a bug rather than a
-- decision.
C.DIM_ALPHA   = 0x66
C.HOVER_ALPHA = 0xaa

C.INFX_BTN_W = 22         -- the input FX button in a strip header
C.AUTO_BTN_W = 32         -- the automation-mode button in a panel header.
                          -- Wide enough for "LTCH", which is the longest
                          -- of the six labels.

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

-- Collapsed panels: a narrow vertical bar carrying the name, bypass and
-- float only. Wide enough for the icons plus stacked capitals, and wide
-- enough for the meter's stacked readout ("12.4" over "dB") when a
-- collapsed panel is metering -- without those few extra pixels the
-- decimal would have to be dropped exactly where the bar is the only
-- thing you can see.
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
C.IO_COL_W    = 28        -- a plugin's input or output meter, with its readout
C.GRV_W       = 220       -- the gain-reduction trace, when a meter is opened out
-- Its window: beats (tempo-locked, like Track Analyser's) or seconds.
C.GRV_WINDOWS = { "1b", "2b", "4b", "8b", "1s", "2s", "4s" }
C.GRV_DEFAULT = "4b"
C.IO_BAR_W    = 8         -- the bar itself
C.METER_FONT  = 10        -- point size for the readout
-- "left" or "right" edge of the panel body. Right, so a panel reads the way
-- the audio flows: input meter, controls, gain reduction, output meter.
C.METER_SIDE = "right"
C.MAX_GR_DB  = 18         -- per-plugin MINIMUM full scale (it grows, below)
C.GR_HOLD    = 1.2        -- seconds the peak line holds before falling
C.GR_FALL    = 18         -- dB per second it falls once released

-- The scale grows when reduction exceeds it, so a meter set for gentle bus
-- compression still tells the truth when something slams. It steps between
-- fixed rungs rather than scaling continuously -- a scale that moved with
-- every transient would be unreadable -- and only steps back down once the
-- peak has stayed below the smaller rung for a while.
C.GR_LADDER      = { 6, 12, 18, 24, 30, 40, 60 }

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
C.CHANNEL_W   = 112       -- expanded width of the Channel panel (View > Strip width)
-- The width of an expanded channel strip: the pinned Channel panel, every
-- mixer strip, and the track name buttons, which share it. Set from View >
-- Strip width; the fader and meter scale with it (TS_CV_Channel.draw_body),
-- so it can go narrower than the default as well as wider. Collapsed
-- strips keep their own width.
C.CHANNEL_W_DEFAULT, C.CHANNEL_W_MIN, C.CHANNEL_W_MAX = 112, 72, 240
function C.set_channel_w(v)
  v = math.floor(tonumber(v) or C.CHANNEL_W_DEFAULT)
  C.CHANNEL_W = math.max(C.CHANNEL_W_MIN, math.min(C.CHANNEL_W_MAX, v))
end
                          -- (fader and meter take half each, and the
                          --  meter's scale needs room for its numbers)
C.FADER_W     = 26        -- the fader's own track within its half
C.FADER_CAP_H = 16        -- the moving cap: big enough to grab and to
                          -- read the unity mark against
C.GR_BAR_W = 5          -- the track's total gain-reduction bar beside it
C.LEVEL_METER_W = 52      -- the level meter's own width within its half.
                          -- Wider than it was, because the dB ladder is
                          -- printed OVER the bars now instead of in a
                          -- gutter beside them (C.METER_SCALE_OVER) --
                          -- the bars got the gutter's width back and
                          -- then the meter got the rest of its half. It
                          -- is still capped at the half, so it sits
                          -- centred like the fader rather than flush
                          -- against the panel edge. (C.METER_W, way
                          -- above, is the GAIN REDUCTION bar --
                          -- different meter, different panel.)
-- A send is a DOUBLE-WIDTH cell on the same grid the plugin panels use,
-- so sends line up row-for-row with parameters: knob in the left half,
-- its buttons in the right. The add tile is simply the next cell.
C.SEND_W      = 116       -- a send's double-width cell, whatever the control spacing
-- Air between columns of sends. The parameter grid doesn't need any --
-- its cells are a knob and a name and read as a grid on their own -- but
-- a send is a name, a knob and three buttons, so two columns hard against
-- each other read as one wide cell with too much in it.
C.SEND_COL_GAP = 7
C.SENDS_MAX_W = 3 * C.SEND_W + C.SEND_COL_GAP * 2 + C.PANEL_PAD * 2

-- Level metering: floor of the scale, and how the peak behaves.
C.METER_FLOOR = -60       -- dB at the bottom of the level meter
C.METER_MARKS = { 0, -6, -12, -24, -48 }   -- labelled on the channel meter
-- The ladder goes ON the bars, the way REAPER's own meters do it, rather
-- than in a gutter of numbers beside them -- at this width the gutter was
-- taking a third of the meter to print five short numbers. Each figure
-- takes dark ink where the bar behind it is lit and light ink where it
-- isn't, which is what makes an overlaid scale readable at all. False
-- puts the gutter back.
C.METER_SCALE_OVER = true
-- The RMS hairline beside each bar. Fixed pixels, not a fraction of the
-- bar: the point of it is to be a hairline, and a proportion stops being
-- one as soon as the bars get wider.
C.RMS_STRIP_W = 3
-- The RMS hairline beside each bar. Fixed pixels, not a fraction of the
-- bar: the point of it is to be a hairline, and a proportion stops being
-- one as soon as the bars get wider.
C.RMS_STRIP_W = 3
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

-- ---------------------------------------------------------------------
-- ReaEQ panel -- see TS_CV_ReaEQ.lua / TS_CV_EQPanel.lua.
-- ---------------------------------------------------------------------
-- Whenever the plugin mapped to a panel IS ReaEQ, that panel's whole body
-- becomes the draggable-node curve canvas instead of the ordinary knob
-- grid -- a fixed width, the same way the grid's width would otherwise
-- fall out of P.layout, because there's no grid here to measure.
C.EQ_PANEL_W  = 480

-- The ReaComp panel (TS_CV_CompPanel.lua) is a canvas of the same kind, a
-- fixed width with its meters inside it.
C.RC_PANEL_W  = 480

-- The canvas axes. Frequency is drawn log-scaled end to end (a straight
-- read of what "extremes / a little in / the broad middle" means as
-- pixel positions); gain is linear, +-EQ_GAIN_RANGE dB top to bottom.
-- Genuinely large boosts/cuts still draw -- they just run off the top or
-- bottom of the canvas rather than stretching every ordinary band flat.
C.EQ_FREQ_LO    = 20
C.EQ_FREQ_HI    = 20000
C.EQ_GAIN_RANGE = 18

-- Where a double-click lands a node: the extremes are a pass filter, a
-- little further in is a shelf, and the broad middle -- low mids to high
-- mids -- is a bell. Four numbers, easy to retune without hunting through
-- the drawing code for them.
C.EQ_HP_MAX      = 40      -- below this: high pass
C.EQ_LOSHELF_MAX = 150     -- below this (and above HP_MAX): low shelf
C.EQ_HISHELF_MIN = 5000    -- above this (and below LP_MIN): high shelf
C.EQ_LP_MIN      = 12000   -- above this: low pass
                            -- between LOSHELF_MAX and HISHELF_MIN: a bell

C.EQ_NODE_R      = 5       -- node marker radius, and roughly its grab size
C.EQ_CURVE_SEGS  = 160     -- points sampled across the canvas width for
                            -- each drawn curve -- combined response, each
                            -- band's own trace, and the live preview
C.EQ_FILL_STRIDE = 1       -- sample stride of the per-band gradient-fill
                            -- strips (see EQPanel) -- one rect per sampled
                            -- point, same as TS_TrackAnalyser's own
                            -- spectrum fill. Was 3: a flat-topped rect
                            -- spanning three samples reads as a visible
                            -- staircase on any part of the curve with real
                            -- slope (peaks, rolloffs, notches) -- the extra
                            -- draw calls at 1 are the same order TA already
                            -- pays per frame for its 256-band fill.

-- Cycled by a band's position in RQ.read's list, so bands keep a stable
-- colour frame to frame without needing identity beyond that. Spaced by
-- the golden angle so no two adjacent bands land on similar hues even as
-- more are added, rather than marching evenly around the wheel and
-- occasionally producing near-neighbours.
C.EQ_HUE_START = 200
C.EQ_HUE_STEP  = 137.5

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

-- The bracket strip above the panel row: plugins running in parallel
-- (REAPER 7's "Run selected FX in parallel with previous FX") and FX
-- containers, one row per level of nesting. Only the panels under a
-- bracket give up the height; the rest of the row keeps all of it.
C.BRK_ROW_H = 12
C.BRK_PAD   = 2

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
-- The rule must NOT be clamped to this window's own content start -- that
-- sits below where TA's rule goes, since this window has a menu bar and
-- TA does not.
--
-- Example: with font 12.0, frame_h 20.5, itemspacing_y 4.0, and a window
-- 536 high with content start 36.5 (avail 491.5, giving WindowPadding.y
-- 8.0): 8 + 20.5 + 4 = 32.5, and TA's rule measures 32.5 below the same
-- window top. Exactly.
--
-- One half-pixel remains, and it is not ours to fix. Measured side by
-- side: the BOTTOM rules land on identical rows, and at the top TA's
-- covers three rows to our two. Both draw the same 2px rect; TA's happens
-- to straddle a pixel boundary and ours lands on one, so ours is the
-- crisper of the two. That is the two panes starting half a pixel apart
-- in the docker, not a difference in the arithmetic.
--
-- This accepts fractions, so -0.5 here would make ours straddle the same
-- way and cover the same three rows. It trades a crisp rule for a
-- matching one; left at 0 because a blurred edge to imitate someone
-- else's rounding is a strange thing to ship.
C.HEADER_NUDGE = 0

-- The gap a TCP spacer opens in the track strip along the bottom.
C.STRIP_SPACER = 14

-- ---------------------------------------------------------------------
-- The TCP (TS_ChannelView_TCP.lua)
-- ---------------------------------------------------------------------
-- A second window, docked beside the arrange view, that draws its own
-- track panel lined up with REAPER's arrange row for row. Its sizes live
-- here with everything else so the two windows can't drift apart.
C.TCP_EXT_SECT   = "TS_ChannelView_TCP"   -- its own settings; colour stays
                                          -- in C.EXT_SECT, shared with CV
C.TCP_WIN_TITLE  = "ChannelView TCP"
-- The track-colour mark: the TCP's strip down the left of a row, and the
-- stripe along the bottom of ChannelView's name buttons. One number, so
-- the two stay the same thickness.
C.COLOUR_STRIPE  = 7
C.TCP_STRIP_W    = C.COLOUR_STRIPE
C.TCP_INDENT     = 8      -- per folder level, the way REAPER indents
C.TCP_INDENT_FOLDERS = true  -- indent at all (settings menu)
C.TCP_PAD        = 4      -- inner padding of a row
C.TCP_METER_H    = 12     -- the horizontal meter under the name
C.TCP_METER_THIN = 4      -- ...and the line it shrinks to on short rows
C.TCP_PDC        = false  -- the track's plugin delay under its meter (settings menu)
C.TCP_ICON_MAX   = 40     -- the track icon's box is never bigger than this
C.TCP_LANES      = true   -- fixed item lane controls (settings menu)
C.TCP_LANE_W     = 18     -- their column (one button), reserved on every row while any
                          -- track in the project uses fixed lanes
C.TCP_CHIP       = 13     -- the M / S / rec chips shown while one is on
C.TCP_STATE_CHIPS = true  -- show them at all
C.TCP_ICONS      = true   -- track icons on the right of a row (settings)
C.TCP_EDGE       = 6      -- the grab zone straddling a row's bottom edge
C.TCP_ADD_H      = 22     -- the "+" tile under the last track
C.TCP_PANEL_H    = 320    -- the channel flyout's height (clamped to the
                          -- arrange view's)
C.TCP_WHEEL_PX   = 60     -- arrange pixels per wheel notch over the TCP
C.TB_BTN         = 24     -- a toolbar button: square, icon or label
C.TB_GAP         = 3
C.TB_MIN_H       = 18     -- below this there's no toolbar row to draw in

-- Apply a hue and tint read from somewhere else -- the other window's
-- setting, via ExtState. Returns true when it changed anything, so the
-- caller only rebuilds what depends on the palette when it has to.
function C.apply_colour(hue, tint)
  hue, tint = tonumber(hue), tonumber(tint)
  if not hue or not tint then return false end
  if math.abs(hue - C.BASE_HUE) < 1e-6 and math.abs(tint - C.TINT) < 1e-4 then
    return false
  end
  C.BASE_HUE, C.TINT = hue, tint
  C.build_palette()
  return true
end

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
  -- an offline plugin (unloaded, not just bypassed): a cool steel blue of
  -- its own, lighter than any header, so it reads apart from bypass's warm
  -- red-brown and from a blue-based theme's ordinary header
  header_bg_off = { "fixed",  205.0, 0.300, 0.270 },
  header_text   = { "tint",    3.9, 0.206, 0.867 },
  header_dim    = { "tint",   -3.0, 0.100, 0.512 },
  label         = { "tint",   -2.1, 0.148, 0.655 },
  value         = { "tint",    3.9, 0.206, 0.867 },
  knob_track    = { "tint",    0.0, 0.164, 0.239 },
  knob_fill     = { "solid",  -14.0, 0.661, 0.573 },
  knob_fill_bi  = { "solid",  178.2, 0.645, 0.569 },
  -- Gain reduction MEASURED by a probe tap rather than reported by the
  -- plugin: a hue of its own, well away from both the reported fill
  -- (knob_fill_bi) and the accent, so the two can't be mistaken at a
  -- glance. Follows the base hue like the reported fill does.
  gr_measured   = { "solid",  110.0, 0.560, 0.600 },
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
  -- The bracket strip: a parallel run in the accent, an FX container in
  -- a soft violet a third of the wheel round from it -- both follow the
  -- hue, and stay that far apart whatever it is.
  brk_parallel  = { "solid",  -14.0, 0.661, 0.573 },
  brk_container = { "solid",   70.0, 0.420, 0.660 },
  header_drag   = { "tint",   -1.9, 0.183, 0.225 },
  icon          = { "tint",   -2.1, 0.148, 0.655 },
  icon_hot      = { "tint",   -2.1, 0.394, 0.935 },
  icon_on       = { "tint",   -5.7, 0.257, 0.069 },
  bypass_on     = { "alert",   -0.1, 0.645, 0.569 },
  float_on      = { "solid",  -14.0, 0.661, 0.573 },
  fader_cap  = { "tint",   -2.3, 0.196, 0.820 },
  -- ReaEQ canvas chrome. Grid follows the theme like every other rule in
  -- the panel; the combined-response curve gets the same accent everything
  -- else uses for "the one thing that's really happening" (drop_marker,
  -- strip_sel); the spectrum backdrop is deliberately dim -- it's context
  -- for the curve, not something competing with it for attention.
  eq_grid      = { "tint",  0.0, 0.130, 0.230 },
  eq_grid_0db  = { "tint",  0.0, 0.160, 0.360 },
  eq_curve     = { "solid", -14.0, 0.661, 0.573 },
  eq_preview   = { "tint",  0.0, 0.148, 0.500 },
  eq_spectrum  = { "tint",  0.0, 0.160, 0.220 },
  level_lo   = { "fixed",  130.2, 0.388, 0.475 },
  -- Green below LEVEL_HOT, red at it, a harder red past LEVEL_CLIP.
  -- There was an amber step from -6 up; it was removed because -6 dBFS
  -- is not a warning about anything, and a colour change that means
  -- nothing is worse than no colour change at all.
  level_clip = { "fixed",    6.0, 0.720, 0.560 },
  -- Clipping is a different KIND of news from "hot", so it gets a colour
  -- of its own rather than more of the same orange: pure red, and lighter
  -- than anything else on the meter so it reads at a glance.
  level_over = { "fixed",    0.0, 0.870, 0.560 },
  level_rms  = { "fixed",  130.2, 0.330, 0.720 },
  -- The dB ladder printed over the bars, in two inks. Neither is a
  -- "fixed" colour: they are the meter's own furniture and should follow
  -- the theme like the rest of the greys. The pair only has to satisfy
  -- one thing -- meter_ink readable on the unlit bar (lightness 0.127),
  -- meter_ink_lit readable on a lit one (0.475 to 0.560) -- so one is
  -- well above that range and the other well below it.
  meter_ink     = { "tint",  0.0, 0.110, 0.620 },
  meter_ink_lit = { "tint",  0.0, 0.240, 0.105 },
  rec_on     = { "fixed",  358.8, 0.650, 0.563 },
  solo_on    = { "fixed",   43.1, 0.645, 0.569 },
  mute_on    = { "fixed",   16.9, 0.645, 0.569 },
  mon_on     = { "fixed",  130.2, 0.388, 0.475 },
  mon_auto   = { "fixed",  213.0, 0.645, 0.569 },
  -- A MIDI-only send or receive. Blue, as MIDI is in REAPER's own routing
  -- window; fixed, because it's a kind of routing, not decoration.
  midi_on    = { "fixed",  213.0, 0.645, 0.569 },
  -- The routing button's three lamps. Distinct hues rather than three
  -- shades of the accent: they mean different things and you read them
  -- at a glance, not by counting rows.
  route_parent = { "fixed",   43.1, 0.645, 0.569 },
  route_send   = { "fixed",  199.0, 0.600, 0.560 },
  route_recv   = { "fixed",  130.2, 0.450, 0.520 },
  route_off    = { "tint",    0.0,  0.120, 0.230 },
  -- Automation modes. Read is the safe one and gets the safe colour;
  -- write and latch are the ones that change your session while you are
  -- not looking at them, so they get the ones that carry alarm. Fixed
  -- hues: these are transport conventions, not decoration.
  auto_trim    = { "tint",    0.0,  0.120, 0.300 },
  auto_read    = { "fixed",  130.2, 0.450, 0.480 },
  auto_touch   = { "fixed",   43.1, 0.600, 0.520 },
  auto_write   = { "fixed",  358.8, 0.650, 0.540 },
  auto_latch   = { "fixed",   16.9, 0.645, 0.540 },
  auto_preview = { "fixed",  280.0, 0.500, 0.560 },
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

-- ---------------------------------------------------------------------
-- Hardware styles: faceplates, knobs and fader caps
-- ---------------------------------------------------------------------
-- A panel can wear a FACEPLATE in place of the theme's grey, and each knob
-- or fader on it a STYLE and a CAP COLOUR, chosen by right-clicking. All
-- three are saved with the plugin's layout (TS_CV_Mappings), so every
-- instance of that plugin looks the same.
--
-- Only "theme" follows Hue/Tint. The other faceplates and every cap colour
-- are fixed: a cream faceplate is cream and a red cap is red whatever the
-- theme, the way hardware is -- "fixed colour for fixed purpose". Each
-- faceplate carries its own inks (text, dim, tick) so the labels and
-- scales on it stay readable, light on dark and dark on light.
--
-- EFFECT_3D (View > 3D effect) is the light falling on the panels from the
-- top left: a gentle top-lit gradient on the faceplates, the panels' edges
-- catching it, and knobs and buttons casting soft shadows. A plate's
-- `sheen` scales its gradient (1 when absent): near-black shows a lift
-- toward white far more than a mid colour does, so Charcoal takes much
-- less of one. Theme stays flat either way, so it still matches the rest
-- of REAPER.
--
-- The surface itself -- brushed, metallic, both or neither -- belongs to
-- each faceplate, background and section (Brush / Metal in the layout),
-- not to this. METAL_K is the metallic flake's strength (the one Tim
-- settled on with the web page's version), and the shadows' too.
C.EFFECT_3D = true
C.METAL_K = 0.8

C.PLATES = {
  { key = "theme",     label = "Theme" },
  { key = "charcoal",  label = "Charcoal", sheen = 0.3,
    bg = 0x19191bff, head = 0x111112ff, text = 0xd6d5d1ff, dim = 0x8f8e8aff,
    tick = 0x606164ff, border = 0x2b2c2eff },
  { key = "gunmetal",  label = "Gunmetal",
    bg = 0x3d4044ff, head = 0x313337ff, text = 0xe2e3e4ff, dim = 0xa3a7abff,
    tick = 0x8a8e93ff, border = 0x4b4f54ff },
  { key = "aluminium", label = "Aluminium", brushed = true,
    bg = 0xb9bcbfff, head = 0xa6a9adff, text = 0x1f2124ff, dim = 0x45494eff,
    tick = 0x3c4044ff, border = 0x9ea2a6ff },
  { key = "steel",     label = "Steel blue",
    bg = 0x4a5866ff, head = 0x3a4652ff, text = 0xeef2f5ff, dim = 0xc0cad2ff,
    tick = 0xcfd7deff, border = 0x5b6977ff },
  { key = "navy",      label = "Navy",
    bg = 0x1f2d4aff, head = 0x18233bff, text = 0xe5eaf3ff, dim = 0xa2b2caff,
    tick = 0x8fa1bdff, border = 0x2b3b5dff },
  { key = "cream",     label = "Cream",
    bg = 0xd9d1bfff, head = 0xc8bfaaff, text = 0x2b2722ff, dim = 0x5c554bff,
    tick = 0x4a443bff, border = 0xbcb29bff },
  { key = "cobalt",    label = "Cobalt",
    bg = 0x2456a3ff, head = 0x1b4382ff, text = 0xf2f5faff, dim = 0xc5d3eaff,
    tick = 0xd2deefff, border = 0x3366b5ff },
  { key = "amber",     label = "Amber",
    bg = 0xd9921fff, head = 0xc07d12ff, text = 0x22190aff, dim = 0x4d3916ff,
    tick = 0x3b2b0fff, border = 0xb57411ff },
  { key = "stone",     label = "Stone",
    bg = 0xafa493ff, head = 0x9d9281ff, text = 0x1d1b18ff, dim = 0x47413aff,
    tick = 0x38332dff, border = 0x978c7bff },
  { key = "green",     label = "Racing green",
    bg = 0x2e4639ff, head = 0x24382dff, text = 0xe6ebe4ff, dim = 0xadbbb0ff,
    tick = 0xa6b6a9ff, border = 0x3c5748ff },
  { key = "oxblood",   label = "Oxblood",
    bg = 0x4a2428ff, head = 0x3a1c1fff, text = 0xf2e7e5ff, dim = 0xc8adabff,
    tick = 0xbd9f9dff, border = 0x5b2f34ff },
  -- a champagne gold (made for the metallic finish)
  { key = "gold",      label = "Gold",
    bg = 0xb8995eff, head = 0xa78b56ff, text = 0x1a150dff, dim = 0x423722ff,
    tick = 0x372e1cff, border = 0xa08552ff },
}

-- Cap colours. "accent" has no colour of its own: it is the theme's accent,
-- the one the arc knob has always used.
C.CAPS = {
  { key = "accent", label = "Accent" },
  { key = "red",    label = "Red",    col = 0xc8453cff },
  { key = "orange", label = "Orange", col = 0xd98a2fff },
  { key = "yellow", label = "Yellow", col = 0xd9be45ff },
  { key = "green",  label = "Green",  col = 0x4f9c62ff },
  { key = "blue",   label = "Blue",   col = 0x3f74b8ff },
  { key = "grey",   label = "Grey",   col = 0x8d9298ff },
  { key = "cream",  label = "Cream",  col = 0xe6e0d2ff },
  { key = "silver", label = "Silver", col = 0xc9ccd0ff },
  { key = "stone",  label = "Stone",  col = 0xb3a896ff },
  { key = "black",  label = "Black",  col = 0x26282bff },
  { key = "white",  label = "White",  col = 0xeeece6ff },
  { key = "brown",  label = "Brown",  col = 0x6b4a32ff },
  { key = "gold",   label = "Gold",   col = 0xc9a24aff },
}

-- What a toggle lights up in when it's on, chosen from its right-click
-- Colour menu and saved in its Style line's colour field. "theme" is the
-- theme's own toggle colour (no colour saved); the rest are fixed, like a
-- lamp behind the button.
C.TOGGLE_COLS = {
  { key = "theme",  label = "Theme" },
  { key = "amber",  label = "Amber",  col = 0xe8a23aff },
  { key = "green",  label = "Green",  col = 0x4caf5eff },
  { key = "red",    label = "Red",    col = 0xd8463cff },
  { key = "blue",   label = "Blue",   col = 0x3f7fd0ff },
  { key = "yellow", label = "Yellow", col = 0xe0c84aff },
  { key = "white",  label = "White",  col = 0xe9e7e1ff },
}
C.TOGGLE_COL = {}
for _, t in ipairs(C.TOGGLE_COLS) do C.TOGGLE_COL[t.key] = t end

-- The styles, each with the cap colour it wears until one is chosen. The
-- first of each list is the default, and is what a control with no style
-- saved is drawn as.
C.KNOB_STYLES = {
  { key = "arc",     label = "Arc",      cap = "accent" },
  { key = "skirted", label = "Skirted",  cap = "black" },
  { key = "pointer", label = "Pointer",  cap = "black" },
  { key = "trim",    label = "Trim pot", cap = "grey" },
  { key = "nose",    label = "Round nose", cap = "black" },
  { key = "bar",     label = "Bar",      cap = "silver" },
  { key = "fluted",  label = "Fluted",   cap = "black" },
  { key = "bezel",   label = "Bezel",    cap = "black" },
  { key = "rbezel",  label = "Reverse bezel", cap = "silver" },
  { key = "hifi",    label = "Hi-fi",    cap = "silver" },
  -- a ring of dots round a small knob, lit up to the value (from the
  -- centre when the control is centred); the colour is the dots'
  { key = "led",     label = "LED ring", cap = "accent" },
}
-- Toggles' and button rows' faces (TS_CV_Widgets.button_face); the first,
-- flat, is the default and what a button with no style saved is drawn as.
C.BUTTON_STYLES = {
  { key = "flat",    label = "Flat" },
  { key = "lens",    label = "Lit lens" },
  { key = "window",  label = "LED window" },
  { key = "backlit", label = "Backlit" },
}
C.BUTTON_STYLE = {}
for _, b in ipairs(C.BUTTON_STYLES) do C.BUTTON_STYLE[b.key] = b end

C.FADER_STYLES = {
  { key = "flat",    label = "Flat" },
  { key = "console", label = "Console",  cap = "cream" },
  { key = "rail",    label = "Rail",     cap = "grey" },
  -- a thin groove and a small cap, filled up to the value (out from the
  -- middle when centred) in the cap's colour: made for rows of narrow
  -- faders, a graphic EQ's bands say
  { key = "slim",    label = "Slim" },
}

C.PLATE, C.CAP, C.KNOB_STYLE, C.FADER_STYLE = {}, {}, {}, {}
for _, p in ipairs(C.PLATES)       do C.PLATE[p.key] = p end
for _, p in ipairs(C.CAPS)         do C.CAP[p.key] = p end
for _, p in ipairs(C.KNOB_STYLES)  do C.KNOB_STYLE[p.key] = p end
C.KNOB_STYLE_ALIAS = { api = "nose" }   -- Round nose's name for a few days before 1.7.5
for _, p in ipairs(C.FADER_STYLES) do C.FADER_STYLE[p.key] = p end

-- A faceplate by key, or nil for the theme's own (or anything unknown --
-- including a faceplate that has since been taken out of the list, which
-- leaves the layout on the theme's).
--
-- Besides the list, any colour at all: a key "#rrggbb" is a CUSTOM
-- faceplate in that colour (chosen with the [+] after the swatches, see
-- TS_CV_ColourPick), with inks worked out from it the same way the list's
-- were tuned by hand -- dark on a light colour, light on a dark one, the
-- header a shade darker and the edge a shade off the face.
local custom = {}

local function mix(c, to, t)
  local out = 0
  for _, sh in ipairs({ 24, 16, 8 }) do
    local x, y = (c >> sh) & 0xff, (to >> sh) & 0xff
    out = out | (math.floor(x + (y - x) * t + 0.5) << sh)
  end
  return out | 0xff
end

-- "#rrggbb" (any case, with or without the #) -> "#rrggbb", or nil.
function C.custom_key(key)
  if type(key) ~= "string" then return nil end
  local h = key:match("^%s*#?(%x%x%x%x%x%x)%s*$")
  return h and ("#" .. h:lower()) or nil
end

-- The 0xRRGGBB a custom key stands for, or nil.
function C.custom_rgb(key)
  local k = C.custom_key(key)
  return k and tonumber(k:sub(2), 16) or nil
end

local function custom_plate(key)
  local p = custom[key]
  if p then return p end
  local rgb = tonumber(key:sub(2), 16)
  local bg = (rgb << 8) | 0xff
  local r, g, b = (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff
  local lum = 0.299 * r + 0.587 * g + 0.114 * b
  local K, Wt = 0x000000ff, 0xffffffff
  if lum > 140 then
    p = { head = mix(bg, K, 0.09), border = mix(bg, K, 0.13), text = mix(bg, K, 0.86),
          dim = mix(bg, K, 0.62), tick = mix(bg, K, 0.68) }
  else
    p = { head = mix(bg, K, 0.18), border = mix(bg, Wt, 0.10), text = mix(bg, Wt, 0.92),
          dim = mix(bg, Wt, 0.75), tick = mix(bg, Wt, 0.70) }
  end
  p.key, p.bg, p.custom = key, bg, true
  p.label = key:upper()
  -- near-black shows the 3D effect's lift far more, as Charcoal does
  if lum < 45 then p.sheen = 0.3 end
  custom[key] = p
  return p
end

function C.plate_of(key)
  if not key then return nil end
  local p = C.PLATE[key]
  if p then return p.bg and p or nil end
  local ck = C.custom_key(key)
  return ck and custom_plate(ck) or nil
end

-- A faceplate's key as saved (a custom colour in lower case), or nil.
function C.plate_key(key)
  local p = C.plate_of(key)
  return p and p.key or nil
end

return C
