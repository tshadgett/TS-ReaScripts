# ChannelView

A docked channel strip for REAPER: one editable control panel per plugin on
the selected track.

    ┌─ ChannelView ────────────────────────────────────────────────────┐
    │ View  Layouts                            Kick In · 3 plugins     │
    │ ┌─1 ReaEQ ──── B F = ┐ ┌─2 DF-SMACK ─ B F = ┐ ┌─3 Arousor ─────┐ │
    │ │  Freq    Gain      │ │  Input   Gain      │ │  Input  Ratio  │ │
    │ │   ◕       ◑        │ │   ◕       ◑        │ │   ◕      ◔     │ │
    │ │  1.2k    +3.0      │ │  0.0     0.0       │ │ -4.0    6:1    │ │
    │ │  BW      Wet       │ │  Output  Trim      │ │  Attack AtMod  │ │
    │ │   ◔       ●        │ │   ◑       ◐        │ │   ◑      ◐     │ │
    │ └────────────────────┘ └────────────────────┘ └────────────────┘ │
    │ [MASTER][1 Kick In][2 Snr Top][3 OH L][4 Bass DI][5 Gtr L]  ···  │
    └──────────────────────────────────────────────────────────────────┘

## Two views

A toggle in the header swaps the upper area between them, as does a
double-click on the header itself — anywhere nothing else lives, which
`IsAnyItemHovered` sorts out for us. The track list
along the bottom belongs to both.

**Channel view** is one track in depth: its plugins, its channel strip,
its sends. **Mixer view** is every track at a glance, one strip each.

A mixer strip *is* the Channel panel — `CH.draw_body`, the same function,
given a different track and a different id prefix. That is the whole
design and the reason it was worth doing: a second implementation of a
fader, a meter and a mute button would drift from the first inside a
week, and this way it is the same fader taper, the same peak hold, the
same swipe and the same double-click-for-default, because it is the same
code. The id prefix is what makes it possible — without it every strip
would share one set of ImGui ids and one peak store, and they would all
fight over both.

Double-click a strip to open it in channel view; double-click the Channel
panel's background, the empty space between plugin panels, or the empty
space to the right of the last mixer strip, to come back. Not the fader:
that still means unity. Both targets are submitted *before* the controls
they sit under, so anything you can actually click takes precedence and
only the gaps switch views.

The track list is the mixer's ruler, not a separate list that happens to
agree. Each button asks `MX.col_width` for its width, which asks the
Channel panel — so a collapsed strip's button collapses with it, and the
written-down number that would have drifted does not exist. The gap
between columns and the TCP visual spacer are the same constants in both.

The strips and the track list aren't two windows kept in sync any more —
they're one window. `MX.draw_row` draws both, on a single BeginChild
called `trackrow` in both views: the strips with a name button under
each in mixer view, just the name buttons in channel view. Same id
either way, so ImGui's own per-window scroll memory is what keeps them
lined up — there is no variable being copied back and forth, and so
nothing to fall out of step. (There used to be one — `MX.scroll_x`,
written by whichever view was up, read by the other — and it's exactly
where two real scroll bugs turned up: the mouse wheel not reaching a
strip's own nested child window, and the track list never having wheel
handling of its own at all. One shared window closes off that whole
class of bug rather than patching the instances of it.) Channel view
uses the same widths, so nothing under the divider moves when you
switch — the mixer stays scrolled where it was and one track's detail is
shown instead of it, not drawn over it: the strips aren't rendered while
channel view is up, only parked at the same position for when you switch
back. That also means channel view's track list is as wide as the mixer
needs it to be rather than as narrow as channel view could get away
with, which is the trade we wanted.

Mixer strip headers carry the track colour and no name. The name is
directly below at full width in the track list, and the header could only
have shown a truncation of it. Unselected, the header and its button
below dim to the same alpha -- one object, one selected state.

Clicking anywhere on a strip selects its track, the meter and the fader
included. That is a window hover rather than a background button: an item
on top of the background swallows the background's click, but nothing can
swallow the fact that the mouse went down inside the strip. Ctrl (or Cmd)
adds and removes, Shift takes the range back to the last click, and the
track buttons answer the same gestures through the same function --
`MX.click` -- because a button and the strip above it had better not
disagree about what a ctrl-click means. Hidden tracks are not in a range:
the range is what you can see. And ctrl can never take the selection down
to nothing, because channel view has to have a track to show.

## Ganging

Select six tracks, touch one, and all six follow. `TS_CV_Gang.lua` is the
layer between a control deciding what it wants and the tracks that end up
with it, and it draws nothing and knows nothing about ImGui.

Two kinds of edit. Mute, solo, record arm, phase, monitoring, automation
mode and collapse are **absolute** -- every ganged track takes the same
value, because there is no sensible "proportionally muted". Volume and
pan are **relative** -- every track keeps its own value and moves *by*
the same amount. Volume by the same ratio, which on linear gain is the
same number of dB; pan by the same offset, because a ratio would leave a
centred track centred however far you dragged. A balance you spent an
hour on is a thing you are trying to move, not a thing you are trying to
flatten.

Double-click is the exception inside the exception: unity and centre are
places rather than distances, so they set the whole gang *to* them.

An edit gangs only when the track you touched is itself one of several
selected. Touching an unselected track's fader while five others are
selected moves that one track -- you reached for it specifically, and an
edit that jumped to five tracks you did not touch is the kind of surprise
that ends in an undo and a lost afternoon. A track at -inf stays at -inf,
and a track that hasn't got the property at all (record arm on the
master, where REAPER answers nil rather than 0) is skipped rather than
written to.

Everything absolute goes through one function -- the Channel panel's
`set` *is* `G.set` -- so there is no control that quietly forgot.

A collapsed strip is the exception that proves the rule. Its ghost fader
lies right over the meter, so there is no background left to click -- and
selecting on the press would break a gang the instant you reached for the
level. `W.fader` therefore reports a press that was let go without ever
moving, on release rather than on press, and the collapsed strip selects
on that. Click picks the track, drag rides the level.

Grabbing a control does not select the track. That is REAPER's own
behaviour, and it is the one that works: select three tracks to gang
them, reach for a fader, and a select-on-touch would throw the other two
away before the move started. The select target is the strip's background
button, submitted before everything else, so a knob or a fader under the
pointer swallows the click; the header, the meter and the space around
things fall through to it. That is also why the meter's tooltip hovers by
rectangle rather than hanging off an invisible button -- a button is an
item, and an item over the meter ate the click the background needed.

## The level meter

The dB ladder is printed over the bars rather than in a gutter beside
them, which is what lets the bars have the meter's whole width. A gutter
was needed while the scale had one fixed ink -- any single colour is
unreadable over signal for half its range. Each figure instead asks
whether the bar directly behind it is lit at its own level and takes dark
ink if it is, light ink if it is not. That is one comparison and one draw
per figure, which is the part that matters: thirty strips redrawing five
figures sixty times a second leaves no room for haloes or outlined text.

The figure itself is centred, with a dash reaching in from each edge. A
centred figure straddles both channels, and the two are not always lit to
the same height, so it is drawn twice -- each half clipped to one channel
and inked from that channel. Taking one ink from the louder bar would
lose half the glyph into the quieter one's unlit bar every time the two
sat either side of a mark, and two draws with two clip rects are cheap
next to that. The dashes sit squarely on one bar each, so they simply ask
it.

The two inks are theme colours, not fixed ones, and a test measures that
they straddle the bar colours by a comfortable margin in luminance. A
palette entry is data, so nothing in the code would otherwise notice a
theme change that made the scale invisible.

Both figures under the meter are held and both are per channel, one
column under each bar. The RMS figure holds with the same hold and fall
as the peak one: it used to be live, which made it a number that changed
sixty times a second sitting next to one that did not, and neither of
those is readable for the same reason. The moving strip beside the bar is
still live -- that is what a strip is for, and what a figure is for is
catching a value and keeping it still long enough to look at.

How many bars get drawn comes from the track's own channel count, capped
at two. REAPER never takes a track below two channels, so this always
answers two in practice -- which is also what REAPER itself draws for a
mono track, and matching it is deliberate. A mono source on a stereo
track has a silent right channel and ought to look like it.

Peak hold is kept per channel and drawn per channel, each line only as
wide as its own bar: one line across the whole meter is the louder
channel's peak printed on the quieter one's bar, which is a statement
about the right channel that happens to be about the left. Each line also
stops at the RMS hairline instead of running over it -- peak and RMS are
two readings of the same channel, and a hold line laid across the strip
hides whichever one you were looking at, so each gets a lane of its own. The readout
under the meter still takes the higher of the two, because one number for
the strip is what a readout is for. The RMS hairline beside each bar is a
fixed few pixels (`C.RMS_STRIP_W`) rather than a share of the bar width --
a proportion stops being a hairline as soon as the bars get wider.

## Selection marks

The selected strip is outlined in a brightened version of its own track
colour rather than in one accent colour for every track (`C.SEL_OUTLINE`,
`"track"` or `"accent"`). It has to be brightened rather than used
straight: on the selected strip the fill is already that colour, so the
outline would have nothing to stand against.

The outline is inset by half its own stroke width. ImGui centres a stroke
on the path it is given, so a rect drawn on the child's bounds spills half
a line-width past them on every side -- except that the child's clip rect
eats the spill on the right and the bottom and not on the left and the
top. That asymmetry is a visibly fatter left-hand edge, and insetting is
the fix rather than nudging the coordinates.

It is also drawn last, after the header and the body, or the header paints
out the two corners it just rounded; and the header is capped to the
strip's own radius so the two shapes agree about what a strip is.

## What it does

* **Channel** pinned hard left — pan across the top, then the fader (with a
  unity detent marked either side of the slot) and a labelled level meter
  taking **half the panel's width each**, each with its own readout
  underneath: fader dB on the left, peak hold and RMS on the right. Mute,
  solo, phase and monitoring sit in a button grid at the bottom, with
  **record arm on a full-width row of its own** — it's the one you hit in a
  hurry and the one whose state you check from across the room. It sits outside the scrolling row on purpose: the fader is the one
  control you reach for regardless of which plugin you were looking at.
  Collapses to a bar like any panel, keeping the meter, mute and solo
  reachable. Monitoring cycles – / IN / AU and shows *auto* in its own
  colour — auto is a different behaviour from input monitoring, not a
  stronger one, so the same green would read as "on, but more".
* A **routing button** on the Sends header — opens REAPER's routing and
  I/O window for the track, with the same three lamps as its mixer button:
  parent/master send, sends out, receives in. An unlit lamp is drawn
  rather than omitted, because three slots that are always there say
  *which* one is missing, where two lines and a space only say "two of
  something". There is no API that takes a track, only an action for the
  last-touched one, so the track is selected first — and only if it isn't
  already, since clobbering a multi-track selection to open a window would
  be a poor trade.
* **Sends** pinned hard right — laid out on **the same grid the plugin
  panels use, in double-width cells**, so a send lines up row-for-row with
  the parameters beside it. The destination's colour is a bar down the LEFT
  edge, the way a mixer marks a strip, with its name across the top of the
  cell, the level knob under it and mute / sidechain / pre-post to the
  right, centred on the knob's face. The
  `+` tile is simply the next cell on the grid rather than something bolted
  on the end. The add menu lists **every** track — the one you're sending
  from is disabled rather than dropped, because a number missing from the
  middle of the list reads as a bug in the list — and respects both spacer
  tracks and REAPER's own TCP spacers (`I_SPACER`) as gaps — as does the
  track strip along the bottom, which draws a hairline down the middle of
  the gap: the gap alone reads as a gap between two buttons, the rule says
  somebody meant it. Grouping you set up in the project is worth something
  in every list that shows the project. The add menu hovers the same way the
  insert one does: **Direct** or **Sidechain** first, then the project's
  tracks with a colour swatch each. Sidechain lands on channels 3/4 and
  widens the destination to four channels if it needs it — REAPER won't,
  and a sidechain send into a two-channel track passes no audio. Right-click
  a send to switch it between direct and sidechain, or remove it.
* A **header bar** carrying the menus on the left, the track's colour chip,
  number and name **centred**, and the **FX chain bypass** hard right — the
  latter bypasses every plugin on the track at once, which is a different
  thing from bypassing one panel and belongs where it's always visible. The
  bar's height comes from `C.MENU_PAD_Y`; see *Header height* below for why
  that is the only number that moves it.
* **Run when REAPER starts** under *View* — see below; it edits
  `Scripts/__startup.lua`, carefully.
* One panel per plugin on the selected track, REAPER 7 FX Containers
  expanded so nested plugins get their own panel too.
* Each panel header has the chain position, the plugin name, and four icon
  buttons: collapse, bypass (power), float (opens the plugin's own window)
  and the panel menu.
* **Drag a panel by its name** to reorder the chain. A blue line shows where
  it will land; the move goes through REAPER's undo. Plugins inside an FX
  container can't be dragged — their addressing isn't something the
  documented API lets you move through — and say so on hover.
* **Collapse a panel to a bar** (the chevron, or double-click the name) —
  a narrow vertical strip with the name running down it, keeping bypass and
  float reachable. Collapsed state is per FX instance and saves with the
  project, so collapsing the reverb on the drum bus leaves the vocal's
  alone.
* **Add a plugin** from the dashed `+` tile at the end of the row (adds to
  the end), or a panel's menu ▸ *Insert plugin before / after* to land it at
  a specific slot. Both open a **cascading menu** — Recent, All plugins,
  Folders, Categories, Developers — navigated entirely by hovering, with the
  plugins themselves at the last level. "All plugins" is split by initial so
  no one submenu is a scroll marathon, and a submenu's contents are only
  built when it opens, so a large collection costs nothing until you look at
  it. Every entry is prefixed with its **format** (VST3, CLAP, JS…) in a
  fixed-width field, which lines up down the list and tells apart the two
  entries a plugin installed in more than one format produces — they
  otherwise have identical names.

  The menu's first item opens a **search dialog** for when you know the name
  and typing is quicker: any words you type must all match somewhere in the
  name, format or vendor, so `fab sat` finds FabFilter Saturn. It carries
  the same Folders / Categories / Developers filter, and filter and search
  compose — pick FabFilter, type `pro`, get the Pro- series. Arrows move,
  Enter adds, and the last ten you added sit at the top.
* **Gain reduction meter** — a full-height strip down the edge of the panel
  for plugins that report GR to REAPER. Turn it on per plugin (panel menu,
  or the editor) and it saves with that plugin's layout like everything
  else. It costs 14px, not a whole 58px column, and it stays visible when
  the panel is collapsed, so a folded-down chain still shows which
  compressor is working. The held peak sits under the bar as e.g. `6.4 dB`,
  in a smaller face so the bar itself stays thin — stacking the value over
  the unit when the space is too narrow for one line, as in a collapsed
  panel.

  The per-plugin range is a **minimum, not a ceiling**: if the plugin pulls
  down harder than that the scale steps up a ladder (6/12/20/30/40/60 dB)
  and steps back once the peak has stayed low for a few seconds — so a
  meter set for gentle bus compression still tells the truth when something
  slams, without the scale flickering on every transient.
* **Dividers** — a rule between groups of controls inside one panel, for
  separating an EQ section from a dynamics section. A divider **splits the
  panel into sections**, each laid out in its own block of columns, so
  whatever follows one always starts a new column — however the previous
  section ended, part-filled, padded with gaps, or exactly full. The rule
  itself is a narrow gutter rather than a cell, and is vertical in either
  flow. Its "Line" checkbox in the editor turns the rule off while
  keeping the column break, for spacing two groups apart without a
  visible line between them.
* **Half-gap** — a control type that staggers whatever comes after it
  half a row down, to mimic the staggered knob layouts some hardware
  (and hardware-emulation plugins) use. It costs no cell of its own —
  it's pure vertical offset for the next control — and, like a divider,
  it's a column-flow feature only.
* **Remove a plugin** from a panel's menu. One undo step, no prompt — same
  as deleting from REAPER's own FX chain.
* *View ▸ Panel alignment* centres the panels instead of packing them
  left.
* *View ▸ Colour* has a **base hue** slider: the whole palette is generated
  from one hue, so it can be brought into line with a REAPER theme without
  picking thirty colours. Bypass and warning colours deliberately don't
  follow it, and lightness never changes — the contrast relationships are
  what make it readable.
* The selected track's colour runs as a hairline along the top and bottom of
  the window, with a colour chip and the track's number and name at the top
  right — in view wherever you happen to be looking.
* Knobs, buttons and stepped values write straight to the plugin's
  parameters — no JSFX in the chain, no parameter links, nothing added to
  your projects.
* What a panel shows is **saved per plugin**, so once DF-SMACK is set up it
  looks the same on every track in every project.
* Parameters can be given an **alias** — your name for one of the plugin's
  parameters, which follows it everywhere rather than being tied to one
  knob. Right-click a control and set it there, or use the editor.
* The strip along the bottom mirrors REAPER's track selection both ways.

## Panels are a fixed height and grow in columns

Rows fall out of the window height. Controls flow down a column and wrap
into a new one, so a panel never scrolls vertically — the row of panels
scrolls sideways instead. Make the dock taller and panels get narrower;
make it shorter and they spread out. *View ▸ Control flow* switches
between filling down-then-across (stable when you resize) and
across-then-down (reads like a hardware strip).

## Naming: alias vs label

Two different things, kept apart on purpose:

* An **alias** is your name for one of the plugin's *parameters*. It follows
  the parameter everywhere — every panel, and the editor's lists — whether
  or not it's currently on a panel. This is the one you want for a plugin
  whose own parameter names are cryptic.
* A **label** is a caption for *one slot* on the panel, for when a layout is
  cramped and that particular knob needs something shorter.

Right-clicking a control and setting a name sets the **alias**, since that's
almost always what's wanted. The per-slot label lives in the full editor.

## Setting a plugin up

Right-click a knob for the quick things — remove it, alias it, change it
to a button, make its fill centred, drop a gap in front of it.

For the full dialog: panel menu **=** ▸ *Edit parameters…*, or just click an
unconfigured panel. Plugin parameters on the right, what the panel shows on
the left, `<< Add` / `Remove >>` between them. **Drag a row in the panel list
anywhere you like** — it lands where you drop it, not one place per nudge —
or use ▲/▼. Added parameters land *below* whatever is selected, since a
panel gets built by working down it.
Turn on **Learn** and touching a control in the plugin's own window adds
that parameter. **Auto-fill** grabs the plugin's first eight parameters as a
starting point.

Nothing is written until you hit **Save** — and Save changes that plugin's
panel everywhere, which the dialog says at the top.

## Controls

| | |
|---|---|
| drag up/down | change value |
| wheel over empty space | scroll the row of panels sideways |
| hold Shift | fine |
| mouse wheel | step |
| double-click | back to the parameter's centre/detent |
| hover | the current value, in a tooltip that stays put |
| right-click | control menu |
| click a stepped value | its list of choices |

## Files

| | |
|---|---|
| `TS_ChannelView.lua` | entry point — run this one |
| `TS_CV_Config.lua` | sizes, colours, glyphs, behaviour. All hand-editable |
| `TS_CV_Util.lua` | name cleaning, INI, parameter helpers |
| `TS_CV_FXTree.lua` | container-aware FX chain walk |
| `TS_CV_Mappings.lua` | the layout library |
| `TS_CV_Widgets.lua` | knob / button / stepped-value drawing |
| `TS_CV_Panel.lua` | one plugin's panel |
| `TS_CV_Editor.lua` | the Setup Edit Parameters dialog |
| `TS_CV_Mixer.lua` | mixer view, and the shared track row (`MX.draw_row`) both views draw into |
| `TS_CV_TrackStrip.lua` | asks the track row to scroll to the selection -- everything else moved into TS_CV_Mixer.lua |
| `TS_CV_Browser.lua` | the add-a-plugin picker |
| `TS_CV_FXIndex.lua` | REAPER's Developers / Categories / FX Folders metadata |
| `TS_CV_Channel.lua` | the pinned Channel panel |
| `TS_CV_Sends.lua` | the pinned Sends panel and its add menu |
| `TS_CV_Startup.lua` | the Run-when-REAPER-starts option, and the `__startup.lua` surgery |
| `TS_CV_State.lua` | per-instance view state (collapsed), saved in the project |
| `TS_CV_Steps.lua` | cached choices for stepped parameters (derived, deletable) |
| `dev/TS_CV_Test.lua` | offline tests — see below. Not installed |
| `TS_CV_Diag.lua` | dumps what REAPER reports about the selected track's FX, and how much of your plugin collection the FX index resolves |
| `dev/TS_CV_Audit.py` | checks every ImGui call against your installed ReaImGui. Not installed |
| `TS_ChannelView_Mappings.ini` | your layouts (created on first save) |

The layout library is plain text and safe to edit by hand; *Layouts ▸ Reload
library from disk* picks up changes without restarting. Every save keeps one
generation of backup as `TS_ChannelView_Mappings.bak.ini`.

## Installing

Actions ▸ Show action list ▸ New action ▸ Load ReaScript… ▸ `TS_ChannelView.lua`.
Needs the **ReaImGui** extension (ReaPack). SWS is optional — it only powers
*Layouts ▸ Show the library file*.

## Tests

`dev/TS_CV_Test.lua` fakes enough of the REAPER API to exercise the parts
that don't need a GUI — 442 assertions covering plugin-name cleaning, the
layout file round-trip, control type guessing, the panel and sends
geometry, the gain maths and fader taper, the GR meter's peak hold and
scale, the tooltips' place-once-then-freeze behaviour, and the
`__startup.lua` surgery, and the master track's nil reads. It runs in plain
Lua, outside REAPER:

    lua5.4 dev/TS_CV_Test.lua

One block checks the add-plugin submenus against a *real* `reaper-fxtags.ini`,
which is the only way to catch grouping cases a synthetic list never
produces. That file is personal and not in the repo, so point the harness at
your own and it runs 392 assertions instead of 386:

    TS_CV_TEST_FXTAGS=~/path/to/reaper-fxtags.ini lua5.4 dev/TS_CV_Test.lua

`TS_CV_Audit.py` catches the class of mistake Lua only reports mid-frame — a
call with the wrong number of arguments, a missing `ctx`, a function that
doesn't exist in your ReaImGui build, an `End`/`EndChild` that isn't
guarded, a file-scope local used above its declaration, a track property
read without a nil fallback, or one of *our own* module functions called
with the wrong number of arguments — Lua pads a short call with nils
rather than complaining, so that one surfaces much later as a nil inside
the callee. It reads the binding that ships with REAPER's own ReaImGui reference
(`Data/reaper_imgui_doc.html`), so it always checks against the version you
actually have:

    python dev/TS_CV_Audit.py

Worth running after any edit, before reloading the script in REAPER.

### Two rules worth knowing before you edit

**ReaImGui keeps Dear ImGui's pre-1.90 convention: `End()` and `EndChild()`
are called ONLY when the matching `Begin()`/`BeginChild()` returned true.**
Upstream Dear ImGui now requires the opposite, so most examples you'll find
online are wrong here, and getting it backwards trips an assertion that
kills the defer loop — the window just vanishes, with the real reason only
in the console. Both shapes below are correct:

```lua
local ok = ImGui.BeginChild(ctx, 'x', w, h)
if ok then
  ...
  ImGui.EndChild(ctx)      -- inside the guard
end

if not ImGui.BeginPopup(ctx, 'menu') then return end
...
ImGui.EndPopup(ctx)        -- early-return guard: body is already guarded
```

`TS_CV_Audit.py` checks this by bracket-matching each `End` to its real
partner, so it understands nesting and the early-return form.

**Output parameters occupy real argument positions in the Lua API and must
be passed as `nil`.** `GetMouseDragDelta` is the one that catches people:

```lua
ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left)   -- correct
ImGui.GetMouseDragDelta(ctx, ImGui.MouseButton_Left)             -- wrong
```

The second silently reads the button as the `x` output slot and watches
whichever button is the default. Note that the generated Python binding
(`imgui.py`) *drops* these output parameters from its argument list, so it
is not a safe reference for Lua signatures — which is why the auditor reads
the HTML doc instead. It flags a value in a `nil` slot.

## Stepped parameters

A stepped parameter (filter type, oversampling, a mode selector) opens a
list of the plugin's own choices. Those labels have to be **discovered by
sweeping the parameter** — the ReaScript API has no read-only enumeration,
so the only way to learn what position 3 is called is to set it and read
the formatted value back. The sweep runs once, restores the original value,
and is cached for the session.

Each plugin is swept **once, ever** — the results go into
`TS_ChannelView_Steps.ini`, so a plugin you've used before has its list ready
the moment it appears, with no sweep at all. That file is derived data:
delete it and it rebuilds. *Rescan choices* on a control drops one entry and
sweeps again, which is the fix if a plugin update renames its positions.

Scanning is also budgeted — `C.SCAN_BUDGET` parameters per frame — because
the first frame a chain is drawn would otherwise try to sweep every stepped
parameter at once. Spread over frames it finishes within a second and
nothing stutters.

**Clicking a control always gets you the list**, whatever the transport is
doing. Asking for it is a deliberate act, no different from turning the
knob, so it scans on the spot rather than refusing.

What the transport holds back is *background* scanning — the sweeping the
window does on its own when a chain appears. The reason to wait there is
that some plugins do expensive work on a parameter change (a convolution
reload, a linear-phase kernel rebuild, an oversampling reallocation), and
sweeping one of those unbidden mid-playback can cause a dropout. Set
`C.SCAN_WHILE_PLAYING = true` to let background scanning run too.

The one hard rule: **nothing sweeps while automation is recording**. A
sweep under write, touch or latch writes the whole sweep into the lane,
which is damage to the project rather than a click — so that is refused
even for an explicit click, and no setting overrides it.

Until a parameter has been scanned, the control steps instead: **clicking
cycles** through the positions and wraps around at the end, Shift-click goes
back. The wheel steps too but stops at each end rather than rolling over —
clicking is "give me the next one", where stopping dead looks broken, while
scrolling is a scrubbing gesture, where a silent wrap is a nasty surprise. A
small caret marks the controls that have a list.

## Chains that change underneath you

A REAPER FX address is a **position**, not an identity, so the moment a
plugin is moved or deleted every cached address after it means a different
plugin. Left alone that isn't a cosmetic glitch: dragging a knob would
write to whichever plugin now sits in that slot.

Two guards run every frame, both cheap. The project's change count moves on
any edit, catching the common cases immediately rather than at the next
poll. And each panel's remembered GUID is compared against whatever is now
at its address, catching anything the counter misses. Either forces a
rescan before a single control is drawn, and open menus are dropped because
they hold an index into a chain that no longer exists.

## Run when REAPER starts

*View ▸ Run when REAPER starts* adds a fenced block to
`Scripts/__startup.lua` that calls this script's own action. Ported from
Track Analyser, which does the same job, and treated with the same
caution — that file is the one thing here that can break things **other
than this project**, since everything else you auto-start runs from it
too. Three rules:

1. **A backup first**, every time, to `__startup.lua.bak`.
2. **The result is compiled before it is saved.** `load()` on the new
   text catches a mangled edit while it is still a string in memory. A
   startup file that doesn't parse is never written.
3. **Lines this script did not write are not touched.** Our block is
   fenced with markers and only that is ever removed. If the command id
   turns up *outside* the fence — added by hand, which is how most people
   get there first — the menu says so and leaves it alone rather than
   editing somebody else's line.

The command id is **asked for, not written down**: `get_action_context`
gives the running instance's numeric id and `ReverseNamedCommandLookup`
turns it into the stable `_RS…` name. A hardcoded one would tie the option
to a single machine's action list and quietly write a dead line into
`__startup.lua` anywhere else. If REAPER hasn't given the script an id yet
— it gets one the first time you add it to the Action List — the option is
greyed out and says why.

State is read from the file each time the menu opens, never cached in
ExtState: the file is the truth, and a remembered boolean is just
something that can disagree with it after a hand edit.

The text surgery (`classify`, `fenced_add`, `fenced_remove`) is pure — it
takes a string and returns a string — which is what the tests exercise,
on strings, rather than on your real startup file.

## Things that get lost at the edges

Three separate versions of the same problem, fixed the same way — by
measuring rather than guessing:

* **Tooltips** are clamped to the **window**, not the screen, and *flip to
  the other side of the pointer* rather than merely sliding, so the box
  never ends up covering the control it describes. The foreground draw
  list is clipped to the window ReaImGui is drawing into, so a tooltip
  that fits on the monitor but hangs past the right edge of a docked
  ChannelView is simply cut off — which is every tooltip in the Sends
  panel, since that panel *is* the right edge. Clamping to the viewport
  alone fixed nothing: there was plenty of screen out there. Both bounds
  are applied, whichever is tighter, so a window half off the monitor
  still gets a readable tooltip.
* **A panel header name** loses its tail exactly where the version number
  lives, so hovering the header gives you the name in full, with the
  vendor and format under it. The FX-container warning still has to get
  through, so it goes *underneath* rather than instead.
* **A format badge** in the add menu reserves its room with spaces whose
  count is *measured* (`badge_pad`) rather than hardcoded: the label font
  is proportional and the space width moves with the UI scale, so a count
  that's right on one machine overlaps the plugin name on another.

## A culled child still owes the layout its space

ReaImGui keeps Dear ImGui's **pre-1.90** convention: `EndChild` is called
only when `BeginChild` returned true. The catch nobody mentions is that a
culled child then submits **no item at all** — so the parent's content
bounds never grow past it, the `SameLine` after it starts from the wrong
place, and if the cursor was moved by hand beforehand the frame ends with:

    ImGui_End: Code uses SetCursorPos()/SetCursorScreenPos() to extend
    window/parent boundaries. Please submit an item e.g. Dummy()
    afterwards in order to grow window/parent boundaries.

...raised from `End`, hundreds of lines from the child that caused it, and
only when the window happens to be small enough for something to be
culled. Every `BeginChild` here now has an `else` that calls
`W.child_skipped(ctx, w, h)` — a `Dummy` of the size the child would have
taken.

The track-colour rule moves the cursor by hand and then trusts the panels
below to draw at it, so it submits a zero `Dummy` of its own rather than
relying on that. Moving the cursor is a promise to draw something there;
this keeps the promise outright instead of hoping the next thing does.

## The cursor is not a scratch variable

`SetCursorScreenPos` followed by no item is an assertion at `EndChild`:
*“Code uses SetCursorPos()/SetCursorScreenPos() to extend window/parent
boundaries. Please submit an item e.g. Dummy() afterwards.”* ImGui has no
way to tell “I moved the cursor and changed my mind” from “I drew
something you should have grown the window for”.

That bites anything that saves the cursor, goes somewhere else, and puts
it back — which is exactly what the remove badge does. The fix is a
zero-size `Dummy` after the restore.

## Taking something out

A **send** carries a small **x** in its bottom-left corner, inset past the
colour bar. Only submitted while the pointer is over the cell, so it costs
nothing and hides nothing the rest of the time.

Sends only. A parameter comes off a panel from the setup dialog or its own
right-click menu; an x on every knob would be clutter buying nothing. A
send has nowhere else to be removed from, which is the whole argument for
putting one there.

That only works because the cell's own button allows being overlapped.
Without `SetNextItemAllowOverlap` the full-cell `InvisibleButton` keeps
the hover for itself and the corner never responds, so every widget that
fills a cell calls `W.allow_overlap()` just before its button. While the
control is being *dragged* ImGui holds the active id, so the badge can't
steal a knob mid-turn.

A send is deleted at the **end** of the frame, never in the middle of the
loop: every send after it shifts down by one, and their cells have already
been drawn with the old indices.

## Air between a name and its control

`C.LABEL_GAP` is the space under a cell's name. It was 2px for the knob
and 6 for the toggle and the stepped combo, which is why only the knob
read as having its label sitting on top of it. One number drives all
three now.

The cell height is fixed, so `LABEL_H + LABEL_GAP + KNOB_D` has to leave
room for the value line at the bottom — raising the gap meant taking two
pixels off the knob. Padding the *grid* instead was tried and reverted: it
pulled the whole first row up under the panel header, which fixed nothing
and cost the panel its breathing room.

## A knob belongs at the top of its cell

A cell is `CELL_W` x `CELL_H` and a knob fills it: `W.LABEL_H` of name
band, then the face, then the value readout. Move the knob down even a
little and the readout drops out of the bottom of the cell and into the
next row.

That matters because the Sends panel draws its **own** name — one across a
double-width cell rather than one per half — and the obvious way to do
that is to write the name first and put the knob under it. Which pushes
the knob down a line, out of step with every parameter cell beside it, and
the readout out of the cell. Writing it *lower* instead, into the space
the knob's own label would have used, collides with the top of the face.

So the name goes in the band the knob already reserves, at the very top,
and the knob stays where a knob goes. `W.knob_face_y(cell_top)` gives the
face's centre, and the send's buttons line up on that rather than on the
cell's middle — the name sits above the face and the value below, so the
two are several pixels apart and it's the face the eye lines up with. Two
files, one source for the number.

## Things that should be centred, and were not

* A **grid narrower than the room it has** is centred in it. The panel has
  a minimum width, so a plugin with a single column of parameters sat hard
  against the left edge with all the air on the right, which reads as a
  layout that went wrong rather than as a small plugin.
* The **level meter** is `C.LEVEL_METER_W` wide and centred in its half,
  the way the fader's track is centred in the other one. Both filling
  their columns is not the same as the two looking aligned: a meter flush
  to the panel edge beside a centred fader reads as a mistake.
* The **track name and FX bypass** in the header are centred on the last
  menu item's own rectangle, not on the cursor — see *Header height*.

## Double-click means default

Every control — knob, fader, toggle, stepped combo, channel button — goes
back to its default on a double-click. What "default" means is the
caller's business, not the widget's: the widget reports the double-click
in its `act` table (or as a second return value for the state buttons) and
the caller decides.

| | |
|---|---|
| a plugin parameter | REAPER's own default, from `TrackFX_GetParamEx`'s `mid` |
| the channel fader | unity |
| pan | centre |
| a send's level | unity |
| pre/post | post-fader, which is REAPER's default for a new send |
| mute, solo, phase, record arm, sidechain | off |
| monitoring | off — the only way out of a three-state cycle without going round it |

On a two-state button a double-click is the same as two clicks, so the
first click toggles and the second click's default wins. That is
deliberate: the result is the same either way, and the alternative is
swallowing clicks on the chance that a second one is coming.

## RMS, and what it actually is

REAPER exposes no sample-level RMS. `Track_GetPeakInfo` is a peak and
nothing else, and there is no second call that gives an average. So the
RMS reading here integrates the **per-frame peak envelope** over
`C.RMS_WINDOW`, in power rather than in decibels — averaging dB would read
high on peaky material and quietly flatter the mix.

That makes it a fast VU rather than a programme RMS: on dense material it
sits a few dB under a true one, on sparse material it tracks closely, and
it can't see anything that happens between two frames. Worth knowing
before you mix to it.

It's computed **per channel** and drawn as a narrow strip down the *outer*
edge of each channel's bar — left of the left bar, right of the right one.
The peak stays the wide bar and the thing you read first; the RMS sits
beside it without ever being mistaken for a channel of its own. The figure
is printed under the meter with an `r` after it.

## Clipping

Three steps, and the bar and the readout always agree because both come
from `W.level_colour`:

| | |
|---|---|
| below −6 dB | the normal colour |
| −6 to `C.LEVEL_HOT` (−0.2) | amber |
| `C.LEVEL_HOT` to `C.LEVEL_CLIP` (0) | orange — hot |
| at or above `C.LEVEL_CLIP` | **hard red** |

Clipping is a different *kind* of news from "hot", so it gets a colour of
its own rather than more of the same orange.

The peak-hold line takes `W.level_bar_colour` too — the colour the bar
*would* be at that level — so the line and the bar beneath it can never
say different things.

## Format badges

A plugin installed in more than one format produces entries with identical
names, and picking the wrong one is how you end up with the VST2. So each
entry in the add menu and the search dialog carries a coloured badge with
the format on it, drawn over the leading space of the label from the menu
item's own rectangle so it lines up whatever the font.

The hues in `C.FORMAT_HUE` are **absolute**, not theme-following: the badge
is an identity, not decoration, and VST3 has to stay the same colour
whatever the base hue is set to. A format that isn't listed still gets a
neutral badge rather than nothing.

## ReaImGui returns more than the docs say

`Data/reaper_imgui_doc.html` gives `CalcTextSize` as:

    number w, number h = ImGui.CalcTextSize(ctx, text,
                           hide_text_after_double_hashInOptional,
                           wrap_widthInOptional)

It returns **four** values. REAPER hands optional parameters back as
further return values — `nil` for each one you didn't pass — and the
documented return list doesn't mention them.

Those trailing nils are invisible almost everywhere, because Lua adjusts a
call to a single value in an assignment, in arithmetic, in a comparison.
The exception is the **last argument position of another call**, where the
whole list is passed on:

    gut = math.max(gut, ImGui.CalcTextSize(ctx, label))   -- math.max(gut, w, h, nil, nil)

That raises *attempt to compare number with nil* from inside `math.max`,
naming nothing in this project. Bind it to a name first and the problem
disappears:

    local lw = ImGui.CalcTextSize(ctx, label)
    if lw > gut then gut = lw end

`TS_CV_Audit.py` now flags a bare multi-value ImGui call in a last argument
position, counting the optional parameters as returns. `select(n, f())` is
exempt — picking one of several returns is exactly what it's for.

## When it falls over

The defer loop runs through `xpcall`. On a runtime error the console gets
a **full traceback** — every function on the way down, not just the line
that raised — the layouts are saved, and the loop stops rather than
throwing the same error sixty times a second.

That matters because REAPER reports an error at the line it happened *on*,
which for a nil handed to a drawing helper names the helper rather than
the caller that produced the nil. Nearly every bug this window has had has
been of that shape.

## The master track answers nil, not zero

`GetMediaTrackInfo_Value` returns **nil** — not 0 — when a track does not
*have* the thing you asked about. Record arm, input monitoring and phase
invert on the master are the obvious cases. In Lua `nil > 0.5` is a hard
error, not a false, so one unguarded read takes the whole window down, and
only ever when the master is selected, which is exactly the path you don't
test.

Two defences:

* `CH.read(track, key, default)` gives every read a default — and
  `CH.is_master(track)` decides which controls the track has at all, so
  the master gets mute and solo and gives the freed rows to the fader and
  meter rather than showing three dead buttons. The same applies to sends:
  `GetTrackSendInfo_Value` answers nil for a send that vanished between
  collecting and reading.
* `TS_CV_Audit.py` flags any `*Info_Value` result compared or used in
  arithmetic without an `or <default>` in front of the operator — the
  shape `(reaper.GetMediaTrackInfo_Value(tr, "I_FXEN") or 1) < 0.5` is the
  correct one.

## Tooltips that stay put

ImGui's own tooltip follows the pointer and vanishes the instant the item
stops being hovered — which is exactly when a knob is being *dragged*,
since by then the pointer has usually left the cell. So the ones here are
drawn by hand, in `TS_CV_Widgets`:

* `W.tip(ctx, id, text, hovered, active)` records the box's position the
  first time a control asks for it and **freezes it there** while the
  control is held, so the value you are watching doesn't chase the mouse
  off the screen. The text keeps updating.
* `W.draw_tip(ctx)` paints the live one **once, at the very end of the
  frame**, on `GetForegroundDrawList` — above every panel, child window,
  popup and menu, regardless of what was drawn when. `TS_ChannelView.lua`
  calls it as the last thing inside the window.
* `W.clear_tips()` drops the remembered positions; it runs with the other
  per-chain caches when the chain changes underneath us.

**The trap, which cost a release:** those caches used to be cleared on any
*forced* rescan, and a forced rescan happens whenever REAPER's project
change count moves — which is on **every parameter write**, i.e. on every
frame of every knob drag. So the tooltip was re-anchored to the pointer
sixty times a second, and the meters' peak hold was reset just as often.
Re-reading the chain and throwing away UI state are two different jobs:
the first follows `force`, the second follows the chain hash actually
changing.

There are no `SetTooltip` calls left anywhere in the project, and there
shouldn't be new ones — a control that uses ImGui's tooltip will behave
differently from every other control the moment you drag it.

## Header height

The track-colour rule has to land on the same line as Track Analyser's.
This took four goes, and the first three failed for one reason: a style
number written down.

TS_TrackAnalyser.lua pushes no `WindowPadding`, `ItemSpacing` or `FramePadding` of
its own — its `STYLE_VAR` list carries only rounding and border sizes — so
its rule sits at `WindowPadding.y` + a frame-height header row +
`ItemSpacing.y` below the window top. The only hard part is
`WindowPadding.y`, because this ReaImGui build has no `GetStyleVar` to ask
with. The three failures were: ImGui's documented default (ReaImGui's are
not ImGui's), a number read off a screenshot (right on one machine, wrong
on every other), and `MenuBarHeight` worked back from `GetFontSize()`
(ReaImGui's menu bar is not `FontSize + 2 × FramePadding` either).

It is **measured** now, from three things the window will tell us:

    start_y = GetCursorStartPos().y   = WindowPadding.y + decorations
    avail_h = GetContentRegionAvail() = Size.y - 2*WindowPadding.y
                                                - decorations
    Size.y - avail_h - start_y        = WindowPadding.y

The decorations — title bar, menu bar — **cancel**, which is the whole
point: their height never has to be known, so neither the menu bar's
padding nor the font nor the display scaling can get it wrong. It holds
only because there is no *bottom* decoration to subtract, which is why
`C.WIN_NO_SCROLLBAR` exists and why a test checks the flag is still set.
`ItemSpacing.y` comes from `GetTextLineHeightWithSpacing() -
GetTextLineHeight()`, read before our own `ItemSpacing` goes on the stack.

The rule is clamped to the content start, never to our own cursor further
down — the cursor is the thing being corrected for, so clamping to it
silently undoes the correction. That was failure number three.

### What the metrics said

One session, one line:

    font 12.0   frame_h 20.5   itemspacing_y 4.0
    window 536 high, content start 36.5, avail 491.5 -> WindowPadding.y 8.0
    menu bar + padding left the cursor at 36.5; the rule went to 36.5

The padding measurement works: 536 − 491.5 − 36.5 = 8.0. The calculation
wanted `8 + 20.5 + 4 = 32.5`. **The rule went to 36.5** — because it was
being clamped to our own content start, which sounded careful and was the
bug. Our content begins *below* the menu bar; TA has none, so its rule
sits above anywhere ours could start. The clamp fired every frame and
replaced the answer with the cursor.

That also explains why a `HEADER_NUDGE` of −6 had no visible effect: a
fudge behind a clamp looks exactly like that from the outside. You change
the number and nothing moves.

**`C.HEADER_NUDGE` is 0.** TA's rule measures 32.5 below the same window
top, which is what the derivation says, to the pixel. The two intermediate
values (−6, then −2) were both measuring the clamp rather than any real
offset — the −2 survived the fix and then overcorrected by exactly
itself. A test asserts the nudge stays zero, because a number there means
something above it has gone wrong again.

`C.RULE_H` is 2, the same rect TA draws. It was briefly 3, to "match what
renders" — both windows put a 2px rect at a y carrying a half pixel, so
both cover three rows at the top and two at the bottom, and setting ours
to 3 produced four. Fixing the symptom one layer above the cause is how
you end up a pixel out in the other direction.

The rule is clamped to the window and nothing else now, so it can sit a
few pixels up into the menu bar's lower margin — empty space under the
labels, and exactly where TA's lands. The panels are still held below the
content boundary: the rule may overlap the bar, they may not.

(There was a **View ▸ Log header metrics** command that printed all of
this, including what the rule wanted *before* any clamp — that last
number is what finally found it, after five rounds of reading
screenshots. Removed once it had done its job; the numbers above are its
output, kept because they are the evidence for everything here.)

## dB, gain and the fader taper

REAPER's Lua API does **not** expose `VAL2DB`, `DB2VAL`, `DB2SLIDER` or
`SLIDER2DB`. Plenty of forum snippets reference those names, but calling
one is a nil-value crash, so every conversion here is ours, in `TS_CV_Util`.

That includes the fader taper, which therefore can't match REAPER's
exactly — nothing exposes it. What's here is console-shaped: unity at 72%
of travel, and a curve below it so half travel lands near −14 dB rather
than the −36 a linear-in-dB throw would give, which would spend most of the
fader's length on levels nobody mixes at.

    100%  +12.0      50%  -14.0
     86%   +6.0      36%  -27.7
     72%    0.0      25%  -40.0
                     10%  -58.6

`U.UNITY_POS` and `U.CURVE` adjust it if you want a different feel.

The very bottom of the throw is silence rather than `MIN_DB`: a fader
pulled all the way down has to actually shut up.

Two printers, and they are not interchangeable — `U.db_text(v)` takes a
**volume** and converts, `U.db_str(db)` takes a figure that is **already in
dB** (a meter reading, say). Pushing a meter reading through `db_text`
works by accident, via a round trip through `db2val`, and reads as a
mistake to anyone who looks.

## Spacer tracks in the send menu

Tracks whose name is nothing but punctuation — `--------`, `~~~~` — are
spacers people use to group a template, so the send menu shows them as a
gap rather than as somewhere you can send to. The rule is deliberately
strict: **punctuation only**. A labelled divider like `== BUSES ==` stays a
destination, because guessing wrong there hides a track you meant to send
to, which is worse than listing one you didn't.

## Rotated labels

A collapsed panel runs its name down the bar. Two ways to do that —
letters stacked one per line, which is what ships, or the label genuinely
rotated, which is written and switched off.

ImGui has no way to rotate text — the draw list takes glyphs at a position
and that is that. It can place an arbitrary image on an arbitrary quad,
though, so the label is rendered once into a LICE bitmap, copied into an
ImGui image with `CreateImageFromLICE`, and drawn with
`DrawList_AddImageQuad` on corners turned a quarter turn. One image per
(text, colour, size), cached — a bitmap, a font and a texture upload per
frame would be absurd.

That needs **js_ReaScriptAPI** for the LICE and GDI calls. Without it, or
if any part of it raises, the stacked-capital version still runs and
nothing is retried — whatever was missing will still be missing next
frame, and finding that out sixty times a second is its own bug.

**`C.ROT_TEXT` is off.** The rotated version came out unreadable, and the
reason is the seam in the middle of the approach: LICE has no idea what
size ImGui is actually rendering at. On a scaled display ImGui reports a
font size of 12 while drawing considerably larger, so the bitmap comes
back small and thin and the quad stretches it. Fixing it means finding
ImGui's real pixel height, which `GetFontSize` does not give.

The code is still there and still correct where the scaling is 1:1. Turn
the flag on to try it; `C.ROT_UP` picks which way the text reads.

## A bypassed plugin still answers

`GainReduction_dB` keeps reporting whatever the plugin last measured when
you bypass it. It stopped processing, not stopped talking. So the meter
froze at the reduction it happened to be doing at the moment you switched
it off — a number that is not true of anything.

`T.gain_reduction` returns 0 for a disabled FX before asking. The peak
hold then decays from where it was rather than sticking, because it is
fed a real zero instead of a stale six.

## What it doesn't meter, and why

Gain reduction is **self-reported**: the plugin already computed it and
REAPER will hand it over (`GainReduction_dB`), so it costs one call and
touches no audio. There is no level equivalent in the API — nothing gives
you the signal at an arbitrary point in an FX chain. Per-plugin input and
output levels would mean inserting probe FX either side of every metered
plugin, with PDC compensation, and the reading would still only be a level
*difference* that makeup gain and wet/dry quietly corrupt.

That's a signal-path problem, and it belongs to Track Analyser, which has
the probes for it. This window deliberately inserts nothing into your
chains. GR answers "is this compressor working", which is a glanceable
question; levels answer "is my staging right", which isn't.

## Where this came from

The parameter-mapping idea, the per-plugin layout library and its file
format were taken from Wormhole Labs' **StripLink** — the concepts and the
file format, not the code. No StripLink source is reproduced here.
StripLink puts the idea behind a JSFX embedded UI; ChannelView moves it
onto ReaImGui, so panels can be any size and write parameters directly.

The container-aware chain walk is ported from **RackLib.lua**, shared by my
own **Plugin Rack.lua** and **Docked Plugin Display.lua**. That code is
mine. The difference in approach is that Plugin Rack reparents each
plugin's real GUI into a pane, while ChannelView draws its own controls
instead.

Nothing here derives from TK FX Browser, TK Workbench or any other
third-party script — I checked line by line before release.
