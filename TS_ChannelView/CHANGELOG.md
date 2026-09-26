# ChannelView — changelog

## 1.3.0 — the EQ curve, and tracks you can manage from here

- **ReaEQ gets a curve editor.** A ReaEQ panel is now a draggable
  frequency-response canvas instead of a knob grid. Double-click empty
  space to add a band -- where you click picks the type: the far ends
  are high/low pass, a little further in is a shelf, the middle is a
  bell -- and a faint preview shows the shape before you commit. Drag a
  node for frequency and gain, use the mouse wheel over it for Q,
  right-click to change its type or remove it. Each band has its own
  colour with a fill toward the 0 dB line. If TS_TrackAnalyser's probe
  is running on the track, its spectrum is drawn behind the curve.
  - The curve follows ReaEQ's own conventions: its Q runs the opposite
    way to the textbook one (higher is wider), and shelves stop changing
    shape once Q is low enough, exactly as ReaEQ's display does.
  - ReaEQ itself limits boost to +12 dB (cut goes much deeper); the
    panel shows that limit rather than working around it.
- **Stepped knob.** A new control type for parameters with a handful of
  fixed positions -- an alternative to the dropdown. It turns like a
  knob but snaps to the plugin's own steps and shows the plugin's own
  text for each one. Available in the editor's Type list and in a
  control's right-click "Show as" menu (where the dropdown is now simply
  called "Dropdown").
- **Insert tracks from the row.** A dashed "+" at the end of the track
  row (both views) offers *Insert new track* and *Insert from track
  template*. Templates are listed from REAPER's TrackTemplates folder,
  subfolders as submenus, each with a swatch of its colour. New tracks go
  after the track you're on, the same place REAPER's own insert puts
  them.
- **Track right-click menu**, on a name button, a mixer strip or the
  Channel panel: rename, visual spacer before the track, move into the
  folder above / out of the folder, folder children (full, collapsed,
  hidden), and colour. Colour and spacer apply to the whole selection
  when you right-click a selected track.
- **Colour dialog** with REAPER's 16 custom colours (whatever palette is
  loaded -- SWS palettes land in the same place) for one-click picks,
  plus a full RGB picker and "Remove colour".
- **Folder button.** Folder tracks carry a folder icon on their name
  button that cycles the folder the same way REAPER's track panel does:
  children full, children collapsed (drawn as collapsed strips), children
  hidden. It's REAPER's own folder state, so the two always agree.
- **Drag to reorder.** Drag a mixer strip's header, or a name button in
  either view, to move the track; a marker shows where it will land. A
  selected track brings the whole selection, a folder brings its
  children, and Escape cancels.
- **Receives panel.** A companion to Sends, pinned after it and
  collapsed by default: every track sending into this one, with level,
  bypass, sidechain and pre/post, and an add menu listing the tracks it
  could receive from.
- **Sends can create their destination.** The send menu (and the
  receive menu) now starts with *New track* and *New track from
  template*: the track is made at the end of the project and routed in
  one step, without moving your selection.
- A whole-chain FX bypass now tints every plugin header, the same as a
  bypassed plugin does.
- Collapsed mixer strips keep a full-height colour cap, so a row of
  mixed strips lines up; header buttons pick light or dark ink from the
  track colour.
- The Setup Edit Parameters editor puts Add gap / Add half-gap / Add
  divider on a row of their own.
- **Fixed: half-gaps weren't remembered** -- they were dropped every
  time a layout was read back.
- **Fixed: a divider's "no line" setting** reset to a line whenever the
  editor was opened.
- Source comments tidied throughout.

## 1.2.0 — one track row, no seams

- **Half-gap: staggered controls.** A new control type for the
  Setup Edit Parameters editor that costs no cell of its own -- it just
  pushes whatever comes after it half a row down, the way some hardware
  panels (and hardware-emulation plugins) stagger their knobs. Column
  flow only; a "row"-flow panel would need a horizontal half-step
  instead, a different feature nobody asked for. Sections with no
  half-gap in them take the exact same column-count arithmetic this
  file has always used (`cols = ceil(n/rows)`), untouched -- that
  formula assumes every control costs the same, which stops being true
  the moment a half-gap is in the mix, so a section that uses one is
  laid out by simulating the fill instead, one half-cell-tall step at a
  time, rather than trying to predict the resulting column count up
  front.
- **Dividers can now drop their line.** The "Line" checkbox in the
  editor (divider controls only) turns off the rule a divider draws
  between the two groups it separates, while still ending the column
  and opening the same gap -- for spacing two groups apart without
  implying they're different enough to need a line between them.
  Backward compatible: it's bit 2 of the same flags field bipolar and
  invert already share, so every layout saved before this existed
  reads back exactly as it did.
- **Reduced the padding above and below the track row**, in both
  views. ReaImGui's own default `WindowPadding` was leaving a full
  padding's worth of empty space both above the track buttons and
  below them under the scrollbar -- more than either edge needs just to
  keep the buttons off the border and the scrollbar off the button row.
  `C.TRACKROW_PAD_Y` overrides it for the track row and its own padding
  probe only (`PushStyleVar`/`PopStyleVar` around both), measured
  rather than guessed at; horizontal padding is untouched.
- **The track row's horizontal scrollbar is now always visible**,
  rather than only appearing once the row actually overflows. A
  scrollbar that only sometimes reserves its strip of height made a
  track list with few enough tracks look like it had a dead stripe of
  unused space at the bottom -- reserving that strip unconditionally
  turns the same space into an always-there scrollbar instead, so
  nothing looks like wasted real estate depending on track count.

- **The mixer strips and the track list are now one scrolling row,
  not two kept in step.** They used to be separate windows, each with
  its own ImGui scroll position, synced by a variable written back and
  forth every frame -- which is exactly where two real bugs turned up:
  the wheel not reaching a strip's own child window, and the track
  list never having wheel handling of its own at all, in either view.
  Both are gone now because there's only one window (`trackrow`) for
  both views to draw into -- ImGui remembers its scroll position on
  its own, so nothing can desync it, and the wheel works the same from
  the strips, the name buttons, or the gaps between. Channel view
  draws the same window with just the names in it, at whatever
  position mixer view left it at. Picked up horizontal wheel/trackpad
  scrolling at the same time, matching the plugin row in channel view.
  `TS_CV_TrackStrip.lua` no longer draws anything -- it holds one flag,
  set when the selection changes from outside this window and read by
  the row itself to scroll to it.

- **Fixed: a track row sized off the wrong number could end up too
  short, in either view.** The mixer branch clamped its own height to a
  floor independent of what it was actually handed, and the channel-view
  branch reused a constant (`C.STRIP_H`) sized for the button alone, with
  no room for the child window's own padding -- both left `total_h`
  short of what the row needed, which is exactly the setup for a
  vertical scrollbar that should never exist on a row that only ever
  scrolls sideways.

- **Fixed: a permanent vertical scrollbar could appear the moment the
  horizontal one did.** Past enough tracks to overflow the row
  horizontally, a vertical scrollbar would appear too and never go away.
  A culled `BeginChild` (one pushed off-screen by horizontal scroll,
  returning `false`) still performs a normal cursor advance for the
  space it would have taken -- it just doesn't grow the window's own
  content size the way a real child does. `W.child_skipped`, the
  placeholder every culled `BeginChild` in this project submits instead
  of drawing, used `Dummy`, which has no position argument and so landed
  wherever that phantom advance had left the cursor -- silently doubling
  the row's registered height the moment any column further along got
  culled. Every one of the six call sites now saves its cursor position
  before `BeginChild` and hands it to `W.child_skipped`, which restores
  it before submitting the placeholder -- so a culled child always
  claims exactly the space it was given, never wherever it happened to
  land.

- **Fixed: channel view's name row could end up a sliver, sit a few
  pixels above the window's true bottom edge, or -- once the split was
  corrected -- leave mixer strips a few pixels TALLER than channel
  view's panels the moment the row had few enough tracks not to need
  its own horizontal scrollbar.** Channel view splits the window's
  available height between its panels and the name row below them;
  mixer view hands the whole thing to one row and lets each strip's
  height fall out of whatever the row's real, live content region
  turns out to be. Making those agree meant working out, without a
  `GetStyleVar` in this build, exactly how much of that height
  "trackrow" itself is going to eat: its padding, plus its horizontal
  scrollbar's height on the frames it actually shows one. Not a
  worst-case guess held constant regardless of whether a scrollbar is
  really coming -- an early pass at this tried that, and it cost every
  track list a dead stripe of unused height whenever the scrollbar
  wasn't needed -- but the REAL answer, because it's a single fact
  both views already share: the same tracks, at the same
  `MX.col_width`, against the same window width, so whether the row
  overflows horizontally is never something the two views could
  disagree about. `MX.row_content_w` adds up what the row's columns
  actually need; `MX.row_pad_y` compares that to the window's width and
  picks between two small probed numbers (padding with a scrollbar
  forced on, padding with one forced off) accordingly -- worked out
  before "trackrow" is even drawn, so channel view's panels can use the
  same answer mixer view's own strips do.

- **Fixed: a blank track's fallback colour was two different greys
  depending which view you were in.** Channel view's name button used a
  second, hardcoded guess (`0x3a404cff`) for a track with no custom
  colour, instead of the theme-resolved `C.COL.header_bg` mixer view's
  own column already used. Same fallback in both now.

- **Track colour is always full strength**, matching REAPER's own TCP.
  Mixer strip headers, their name buttons, and collapsed strips no
  longer dim to half alpha for "not selected" or brighten on hover --
  selection reads from the outline alone, the way it already did for the
  strip's own border. A strip header's text also picks its ink from the
  header colour unconditionally now, rather than only while selected,
  since the header is never dimmed for that to matter against anymore.

- **Fixed: a name button's text could be unreadable against its own
  fill** -- white on a bright yellow track, for instance. It only
  picked dark ink while selected, which was fine reasoning back when an
  unselected fill was dimmed towards the background and a fixed light
  ink read against almost anything; now that a track's colour is always
  full strength, the button picks its ink from its own fill the same
  way the strip header above it already does, whether or not it happens
  to be selected right now.

- **Double-clicking a name button in channel view switches to mixer
  view too.** Only the mixer's own empty background (or a strip)
  understood double-click as "change view" before -- channel view's
  name row, past the last button, now answers the same gesture, so
  switching views is symmetric in both directions.

## 1.1.0 — mixer view

- **Mixer view.** A toggle in the header swaps the whole upper area
  between channel view — one track's plugins in depth — and a mixer, one
  strip per track. The track list below stays in both, so switching feels
  like changing what you are looking at rather than changing windows.
  - A mixer strip **is** the Channel panel: the same function, given a
    different track and id prefix. Same fader taper, same peak hold, same
    double-click-for-default, because it is the same code.
  - Each strip's header is the track's own colour, with the name in black
    or white depending on what can actually be read on it. Strips
    collapse individually to a bar with the meter still live.
  - **Mute, solo and record arm take a swipe**: press one and drag along
    the row and every one you cross follows the first. Phase and
    monitoring deliberately don't — a stray drag flipping the polarity of
    six tracks is a bad afternoon, and three states have no "same way as
    the first".
  - Double-click a strip to open it in channel view. Double-click the
    Channel panel's background or the empty space between plugin panels
    to come back. The fader keeps double-click = unity.
  - Double-clicking the window header switches views too.
  - Only tracks REAPER shows in its own mixer appear — and the track list
    along the bottom now honours that too, so the two always agree.
  - **The track list is the mixer's own ruler.** Each button is exactly as
    wide as the strip above it — collapsed strips included, because the
    button asks the panel for its width rather than keeping its own copy
    — and the two share one gap and one spacer, so a track's name always
    sits under that track. The lists scroll together: whichever view you
    are in drives the other, and mixer view drops its own scrollbar
    rather than showing two. Channel view uses the same widths, so the
    row underneath never moves when you switch; the mixer is simply still
    there, with one track's detail laid over it.
  - Mixer strips honour the TCP visual spacer the way the track list and
    the sends already did, with the same hairline in the gap.
  - Strip headers drop the track name: it is right below in the track
    list, at full width, and the header was truncating it to fit a colour
    bar that already says which track this is.
  - Double-clicking the empty space to the right of the last strip
    switches back to channel view, matching the empty space in channel
    view that switches to the mixer.
  - **Anywhere on a strip selects its track** -- the meter, the fader,
    the header, not only a patch of background. On a console the strip
    *is* the track; having to find somewhere clickable first is a
    computer idea.
  - **Multi-select.** Ctrl (or Cmd) adds and removes a track, Shift
    takes everything from the last click to this one -- on the strips
    and on the buttons below them, which answer the same gestures
    because they are the same object. Ctrl never takes the selection
    down to nothing: channel view has to have something to show.
  - Collapsed mixer strips are now the Channel panel's collapsed bar,
    the same way expanded ones are its body: mute, solo, the meter and
    the translucent fader laid over it. Mute and solo swipe across a row
    of collapsed strips too.
  - Unselected strip headers dim to the same alpha as the track button
    beneath them, so the pair reads as one object with one selected
    state rather than a bright header over a muted badge.
  - **The selected strip is outlined in its own colour**, brightened,
    rather than in one blue for every track -- a console is a row of
    coloured channels with one of them lit, and a blue outline among
    them read as a different kind of thing. `C.SEL_OUTLINE = "accent"`
    puts the single colour back.

- **A collapsed strip's meter selects its track.** The ghost fader lies
  right over the meter there, so a press cannot mean "select" -- it would
  throw a gang away the moment you reached for the level. The fader now
  reports a press that was let go without ever moving, and that is what
  selects: click picks the track, drag rides the level, and neither gets
  in the other's way.

- **The collapsed strip shows its level in dB.** Under the meter used to
  be the track's name run down the bar -- except that at thirty pixels
  wide with twenty to spare there was room for exactly one stacked
  letter, so what it actually showed, always, was a single ellipsis. The
  name is in the track list directly below; the number is the thing you
  collapsed the strip to keep an eye on.

- **Clicking the empty space in the mixer clears the selection**, the
  same gesture as clicking the background of any list. Double-clicking it
  still goes back to channel view.

- **Double-clicking a name in the track list opens that track in channel
  view**, the same as double-clicking its strip above -- the button and
  the strip are one object and had better answer the same gesture.

- **The dB ladder is printed over the meter**, the way REAPER's own
  meters do it, instead of in a gutter of numbers beside it. At this
  width the gutter was taking a third of the meter to print five short
  figures. The bars got that width back, and then the meter got the rest
  of its half of the panel -- so the bars are roughly twice what they
  were.
  - What made a gutter necessary was one fixed ink, unreadable over
    signal. Each figure knows whether the bar behind it is lit at its own
    level, so it takes dark ink when it is and light ink when it isn't,
    and reads either way. One lookup and one draw per figure -- no halo,
    no outline, no drawing the text five times, which matters when thirty
    strips are doing it sixty times a second.
  - The two inks follow the theme like the rest of the greys, and a test
    measures that they really do straddle the bar colours. A palette is
    data; nothing else would notice a theme change that quietly made the
    scale invisible.
  - The figure sits in the MIDDLE with a dash reaching in from each
    edge, which is what makes it read as a scale rather than a column of
    numbers stuck down one side.
  - A centred figure straddles both channels, and the two are not always
    lit to the same height -- so it is drawn twice, each half clipped to
    one channel and inked from that channel. One ink taken from the
    louder bar would lose half the glyph into the quieter one's unlit
    bar every time the two sat either side of a mark; two draws and two
    clip rects are cheap next to that. The dashes sit squarely on one
    bar each, so they just ask it.
  - `C.METER_SCALE_OVER = false` puts the gutter back.

- **Peak hold is per channel now**, each line only as wide as its own
  bar -- and stopping at the RMS hairline rather than running across it,
  so the two readings get a lane each instead of one hiding the other. One line across the whole meter was the louder channel's peak
  drawn over the quieter one's bar -- a figure about the left channel,
  printed on the right one. The readout underneath still shows the
  higher of the two, since one number for the strip is what it is for.

- **The RMS figure under the meter holds**, the same way the peak figure
  does and with the same hold and fall. It was live, which meant it
  changed sixty times a second and was not a number anybody could read --
  and it sat next to a held peak, so the two behaved differently for no
  reason you could see. The moving strip beside the bar is still live;
  only the figure holds.

- **Both figures are per channel**, one column under each bar. A stereo
  track has two levels, and printing the louder one on its own was a
  number you could not act on: it never said which side it came from.
  They are set in the smaller face, since two columns of "-12.3" do not
  fit a fifty-pixel column at the body size, and the RMS line dropped its
  trailing "r" -- with two columns that was two more marks for something
  the colour, the position and the tooltip already say.

- **The meter draws as many bars as the track has channels** (two at
  most). REAPER never takes a track below two, so in practice this is
  always a stereo meter -- but it asks rather than assuming, so nothing
  can end up with a second bar pinned at -inf.

- **The RMS hairline is a fixed few pixels** rather than 28% of the bar.
  That fraction was fine while the bars were narrow and turned into a
  second meter once they were not: the point of the strip is to be a
  hairline beside the bar, and a proportion does not keep a hairline a
  hairline. `C.RMS_STRIP_W`.

- **The meter lost its amber band.** Green, then red at LEVEL_HOT, then a
  harder red past zero. -6 dBFS is not a warning about anything, so the
  colour change there meant nothing, and did it thirty times a second on
  every strip at once. The two reds stay, because those do mean different
  things.

- **The auditor checks palette names.** A `C.COL.<name>` with no matching
  entry used to read back nil and get painted with whatever nil means to
  ImGui -- invisible to the tests and only slightly wrong on screen,
  which is the worst place for a bug to sit. Removing the amber entry is
  exactly the change that would have left one behind.

- **Grabbing a control no longer selects the track.** It is how REAPER
  behaves and the only thing that works: select three tracks to gang
  them, reach for a fader, and a select-on-touch throws the other two
  away before the move has started. The test is item hover, not window
  hover -- a knob or a fader under the pointer swallows the click and the
  selection stays put. Everything that is not a control -- the header,
  the meter, the space around things -- still selects. (The meter's
  tooltip used to hang off an invisible button, which is an item, and
  that is what was eating the click over the meter; it hovers by
  rectangle now, since a readout has no business being clickable.)

- **An Apply button in Setup Edit Parameters.** Pushes the layout you are
  editing into the live mapping so the panel behind redraws while the
  dialog is still open -- the only way to see whether a layout works
  without saving, looking, reopening and guessing again. It does not
  write to the library, and Cancel still puts everything back, including
  taking the layout out again if it was only ever a generated default.
  The modal's scrim is now barely there, so the panel you are watching is
  actually visible.

- **Reverse, per control.** A checkbox beside Centred, for the parameters
  that are wired backwards -- a threshold that opens as it falls, a mix
  control labelled dry. The flip happens at the boundary: the value is
  reversed on the way in and back on the way out, so every widget,
  tooltip and double-click default deals in what the control shows and
  the plugin only ever sees its own numbers. Knobs and toggles only; a
  combo's entries are positions in the plugin's own scale, and mirroring
  those means mirroring the list. It rides in the layout file's existing
  bipolar field, which is now a bitmask -- bit 0 is still centred, so
  every layout written before this reads back exactly as it did.

- **Removed the View ▸ Track list toggle.** The track list is the
  mixer's ruler now; hiding it is not a thing that makes sense.

- **Ganged edits.** With several tracks selected, touching one of them
  moves all of them -- faders, pan, mute, solo, record arm, phase,
  monitoring, automation mode and collapse. Two kinds of edit, and the
  difference is the point:
  - Mute, solo, record arm, phase, monitoring, automation and collapse
    are **absolute**: every track takes the same value. There is no
    sensible "proportionally muted".
  - Volume and pan are **relative**: every track keeps its own value and
    moves *by* the same amount -- volume by the same ratio, which is the
    same number of dB, and pan by the same offset. A balance you spent
    an hour on is a thing you are trying to move, not a thing you are
    trying to flatten. Double-click still means unity or centre, and
    that one *is* absolute: a place, not a distance.
  - Touching an **unselected** track moves that track alone, however
    many others are selected. You reached for it specifically.
  - A track at -inf stays at -inf, and a track without the property --
    record arm on the master -- is skipped rather than written to.
  - It all lives in one new module, `TS_CV_Gang.lua`, and every absolute
    write in the Channel panel goes through it, so there is no control
    that quietly forgot.

- **Fixed: mute, solo and record arm could not be swiped.** Pressing a
  button makes it ImGui's active item, and from then until you let go
  ImGui reports every other item as not hovered -- correct for a click,
  and exactly wrong for a swipe, whose whole subject is the buttons you
  cross with the mouse still down. The swipe now asks the only question
  that still has a true answer: is the pointer inside this button's
  rectangle?

- **Fixed: the selected strip's outline was a pixel fatter on the left.**
  ImGui centres a stroke on the path it is given, so a rect drawn on a
  child's bounds spills half a line-width past them -- and the child's
  clip rect ate the spill on the right and the bottom but not on the
  left and the top. The outline is now inset by half its own width, so
  every edge weighs the same.

- **The header and the outline agree about what shape a strip is.** The
  header is capped to the strip's own corner radius instead of being a
  square rectangle laid across it, the outline is drawn last so the
  header cannot paint out the corners it just rounded, and the extra
  bright lip along the top of a selected header is gone -- the header is
  already at full colour while its neighbours are dimmed, and three
  marks for one piece of information was two too many.

- **An automation-mode button** on the Channel panel's header, and on
  every mixer strip's — mixer view is where you set these across a
  session, so leaving it to channel view would mean visiting every track
  to do what the row is for. It opens a menu rather than cycling: five
  modes deep, clicking four times to get back where you were is how you
  end up recording automation you did not mean to. Each mode has its own
  colour, because which one you are in is worth noticing from across the
  room rather than reading.

- **A routing button on the Sends header.** Opens REAPER's own routing and
  I/O window for the track, and carries the same three lamps its mixer
  button does: parent/master send, sends out, receives in. The lamps
  report exactly what the panel below cannot — the sends are already in
  view, the parent send and anything arriving from elsewhere are not.

## 1.0.1

- **Fixed a crash in a small window.** ReaImGui keeps Dear ImGui's
  pre-1.90 convention, where `EndChild` is called only when `BeginChild`
  returned true — and a culled child then submits no item at all, so the
  parent's content bounds never grow past it. With the track-colour rule
  moving the cursor by hand, that ended the frame with *"Code uses
  SetCursorPos() to extend window/parent boundaries"*, raised from `End`
  and nowhere near the child responsible. Every child now occupies its
  space even when it is skipped. The same bug was quietly misplacing the
  `SameLine` after a culled panel.

### Already in 1.0.0, just never written down

- **The gain-reduction meter reverts to zero when a plugin is bypassed.**
  `GainReduction_dB` keeps answering after bypass — the plugin stopped
  processing, not talking — so the meter froze at whatever it was doing
  when you switched it off.
- Collapsed panels keep the stacked-letter label. A rotated version is
  written and switched off behind `C.ROT_TEXT`: it draws the text into a
  LICE bitmap and puts it on a turned quad, but LICE has no idea what size
  ImGui is really rendering at, so on a scaled display the result is
  unreadable.

## 1.0.0 — first public release

Released under the MIT Licence. No change to behaviour from 0.1.0.

- Renamed onto the `TS_` convention: `ChannelView.lua` is now
  `TS_ChannelView.lua`, the modules are `TS_CV_*`, and the folder is
  `Scripts/TS_ChannelView/`.
- ExtState section `ChannelView` is now `TS_ChannelView`, for both the
  global settings and the per-project collapsed state. Window position and
  dock state reset once on first run after updating.
- The layout library and step cache are now
  `TS_ChannelView_Mappings.ini` and `TS_ChannelView_Steps.ini`. Existing
  files are carried over, including their saved probe entries.
- `CV_Test.lua` and `CV_Audit.py` moved into `dev/` and are no longer part
  of the installed set. Both now resolve their own paths, so they run from
  anywhere; the test harness's real-tag-file block reads
  `TS_CV_TEST_FXTAGS` and skips cleanly without it, rather than failing on
  a `realdata/` folder that no longer exists.
- Removed five unreferenced functions: `E.editing_key`, `T.get_offline`,
  `T.preset_name`, `M.is_dirty`, `SU.command_id`.
- Attribution reworded. StripLink is credited for the parameter-mapping
  idea and the layout file format only — no StripLink code is reproduced.
  RackLib, Plugin Rack and Docked Plugin Display are my own, and now say
  so. Nothing here derives from TK FX Browser or TK Workbench; that was
  checked line by line.
- Added this changelog.

## Before this

0.1.0 was the private working version.
