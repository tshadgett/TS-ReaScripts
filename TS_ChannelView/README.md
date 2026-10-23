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

## Standard and Pro

ChannelView comes in two parts. **ChannelView** is free (MIT) and on
ReaPack. **ChannelView Pro** is an add-on to it, installed from its own
ReaPack link (see *Installing*); the two must be the same version. Parts of
this guide marked **(Pro)** need it.

Pro adds grid layouts and the grid editor (*Edit layout*), the Rack view,
the web companion, canvases (EQ, compressor and the rest, for any plugin,
and ReaEQ's and ReaComp's), knob and button styles and colours, faceplates,
finishes, sections and backgrounds, the 3D effect's lighting and shadows,
the plugin's own colours, vendor looks, more than one layout per plugin and
switching between them, Show when rules and virtual controls, the TS_CV
Trimmer and the gain-reduction trace.

Without Pro, everything else works as described, and a layout made with Pro
still works: its grid, Show rules and virtual controls are drawn as they
are, its knobs as the default Arc and its buttons flat, and nothing in it is
lost when it's saved. Pro's menu items are there, greyed and marked (Pro).

## Two views

A toggle in the header swaps the upper area between them, as does a
double-click on the header itself — anywhere nothing else lives — and the
**TS_ChannelView_ToggleMixer**
action, for a keyboard shortcut or a toolbar button (ChannelView's window
never gets the keyboard, so the shortcut has to be REAPER's; a toolbar
button for it lights while the mixer is showing). The track list
along the bottom belongs to both.

**Channel view** is one track in depth: its plugins, its channel strip,
its sends. **Mixer view** is every track at a glance, one strip each.

Double-click a strip to open it in channel view; double-click the Channel
panel's background, the empty space between plugin panels, or the empty
space to the right of the last mixer strip, to come back. Not the fader:
that means unity.

Mixer strip headers carry the track colour and no name. The name is
directly below at full width in the track list, and the header could only
have shown a truncation of it. Unselected, the header and its button
below dim to the same alpha -- one object, one selected state.

Clicking anywhere on a strip selects its track, the meter and the fader
included. Ctrl (or Cmd) adds and removes, Shift takes the range back to
the last click, and the track buttons answer the same gestures. Hidden
tracks are not in a range: the range is what you can see. And ctrl can
never take the selection down to nothing, because channel view has to
have a track to show.

## Rack view (Pro)

**ChannelView Rack** (`TS_ChannelView_Rack.lua`, in the Actions list) is
ChannelView in a window of its own, laid out down a column: the selected
track's plugins top to bottom, for docking beside the arrange while
ChannelView stays where it is. It has no fader panel, mixer or track list:
the track is whichever you select in REAPER's mixer or track panel — or,
with the **padlock** in front of the track's name in its header bar, the
one it's locked to, whatever
you select (kept with the project; click it again to follow the
selection).

- Every plugin is the column's width. A grid layout (see *Grid layouts*)
  is as tall as its grid; in a column narrower than it, its sections wrap
  onto new lines whole, and one wider than the column runs across then
  down (locked, it scrolls sideways instead). Any other layout takes the
  fewest rows that fit across the column, never fewer than its tallest
  control needs (a fader's length, a large knob; an upright fader at least
  two). A layout ChannelView shows too keeps at least the rows its
  controls fill in ChannelView's window, so it's arranged as it is there.
  A locked layout keeps its own rows.
  A gain-reduction meter stands at the side as in ChannelView (click it
  for its trace) on a panel three rows tall or more; on a shorter one it
  lies across the top instead, 0 dB at the right and the bar growing left
  as it pulls down, with no trace. A canvas (an EQ, a compressor, ReaEQ, ReaComp) spans the column,
  with the layout's other controls in rows under it.
- The macros and modulators are strips across the top, the sends and
  receives strips across the foot. They stay put while the plugins scroll
  between them. Its View menu shows or hides each of the four.
- Containers and parallel runs are bracketed down the left; only the
  plugins inside one move in to make room. Click a container's strip for
  its menu. Drag a panel by its header to move the plugin.
- Folding is its own, and so are its action bars: the four *Rack* places
  (a bar's right-click ▸ *Place*, or ☰ ▸ Drawers ▸ *New* in the rack).
  Its chevrons point up to fold a panel and down to open it.
- **Collapse all**: the double chevron in its header folds every plugin;
  pressed again, it opens only the ones it folded.
- **A layout of its own.** A plugin can have one layout laid out across
  for ChannelView and another laid out down for the rack: pick it from the
  panel's *Layout* menu in the rack, and *Make … the rack's default* for
  every instance there. Until you pick one in the rack, it uses
  ChannelView's.
- Layouts, labels and settings are shared: change one in either window and
  the other follows.
- **☰ ▸ Run when REAPER starts** starts the rack with REAPER, on its own:
  ChannelView's option and the rack's are separate.

## Freeze

The **❄** button in the header (ChannelView and the rack) freezes the
track with REAPER's own freeze: **Freeze track**, **Freeze up to** the
selected plugin (click its panel first), and **Unfreeze**. The freeze is
stereo. Frozen plugins stay where they were, as ice strips at the start of
the chain; in the rack, a *frozen above* line with an Unfreeze button sits
under them. Click a strip for the same menu. The button is lit while the
track has frozen plugins.

ChannelView's own plugins are never frozen: the probes and ChannelView
Modulators move to just after the plugins being frozen, so they go on
measuring and modulating the live chain, and go back to their places at
any unfreeze, ChannelView's or REAPER's own. With *Freeze up to*, the
plugins after the chosen one are taken offline while REAPER freezes and
put back online when it's done. REAPER's freeze includes the track's
receives.

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
item, and an item over the meter would eat the click the background needs.

## The level meter

The dB ladder is printed over the bars rather than in a gutter beside
them, which is what lets the bars have the meter's whole width. One
fixed ink would need a gutter -- any single colour is unreadable over
signal for half its range. Each figure instead asks
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
as the peak one: a live figure changes sixty times a second, and beside
one that does not, neither reads well. The moving strip beside the bar is
live -- that is what a strip is for, and what a figure is for is
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
* A **header bar**: on the left the **☰** menu (*View*, *Layouts*, *Web
  companion*, *Dock* and *Run when REAPER starts*) and the view toggle, then
  the **MIDI learn** and **Probes** buttons; the track's colour chip, number
  and name **centred**; and on the right **OS**, the FX chain button and the
  **FX chain bypass** — which bypasses every plugin on the track at once, a
  different thing from bypassing one panel, and belongs where it's always
  visible. While the whole chain is bypassed the header glows red along its
  bottom edge. The bar's height comes from `C.MENU_PAD_Y`; see *Header
  height* in `dev/NOTES.md` for why that is the only number that moves it.
* **Run when REAPER starts** under **☰** — see below; it edits
  `Scripts/__startup.lua`, carefully.
* One panel per plugin on the selected track, REAPER 7 FX Containers
  expanded so nested plugins get their own panel too.
* Each panel header has the chain position, the plugin name, and four icon
  buttons: collapse, bypass (power), float (opens the plugin's own window)
  and the panel menu.
* **Float plugins without controls** (View): a plugin whose layout has no
  controls — an instrument you'd rather play from its own window, say —
  opens its own window when you come to its track, a moment after so
  stepping through tracks doesn't flash windows open, and closes it when
  you move on. While it's open, a **pin** in its panel's header keeps it
  open across track changes. A window you opened yourself is never closed,
  and one you close stays closed until you come back. The rack has its own
  setting.
* **Drag a panel by its name** to reorder the chain, into and out of FX
  containers too: dropped on the left half of a panel it lands before that
  plugin, on the right half after it, in that plugin's container. A blue
  line shows where it will land (violet when it's going into a container);
  the move goes through REAPER's undo.
* **Parallel FX and containers.** A bracket over the panels marks what runs
  together: a parallel group (marked `||`) and each FX container (marked
  with a small square, in a colour of its own). Panels only drop as far as
  their own brackets need. A panel's menu ▸ **Route** sets how a plugin is routed
  against the one before it — *In series*, *In parallel with previous*, or
  *In parallel, merge MIDI* — and *Put in a new container* wraps it in one.
  Click a container's square for its menu: bypass it, set its routing, add
  a plugin into it, unpack it (its plugins move out to where it was),
  remove it, or save it as an FX chain. *Move left / right* and *Remove*
  work anywhere in the chain.
* **Oversampling.** REAPER's own, set from ChannelView: **OS** in a panel's
  foot oversamples that plugin, a container's menu ▸ *Oversample everything
  in it* does a container, and **OS** in the header bar does the whole
  chain. The choices are REAPER's — *up to* 96, 192, 384 or 768 kHz — each
  with what it means at the rate you're running (at 48 kHz, up to 192 kHz
  is 4x; at 96 kHz it's 2x). While it's on, the switch is lit with the
  factor (a collapsed panel and a container's bracket show it too), so you
  can't miss it. Outlined **OS** means the plugin is oversampled from
  around it (its container or the chain), or is set to a rate REAPER
  already runs at. REAPER applies a change when playback next starts.
* **Strip width.** View ▸ *Strip width* sets how wide the fader panel,
  every mixer strip and the track name buttons are, from 72 to 240 px
  (112 by default). The meter grows and shrinks with it, the fader a
  little; collapsed strips keep their width. The web companion follows.
* **Offline.** A panel's menu ▸ *Set offline* unloads the plugin — unlike
  bypass, it frees its CPU and memory — and the panel's header and foot
  turn steel blue, with *Bring online* where its controls were.
* **A sidechain into a container.** A container passes only two channels
  in until it's widened, so a compressor inside one never hears a
  sidechain on the track's 3/4. When that's the case, the plugin's menu
  offers *Pass the sidechain into its container*, which widens it.
* **Collapse a panel to a bar** (the chevron, or double-click the name) —
  a narrow vertical strip with the name running down it, keeping bypass and
  float reachable. Collapsed state is per FX instance and saves with the
  project, so collapsing the reverb on the drum bus leaves the vocal's
  alone. ChannelView also remembers it per plugin: a plugin you last left
  collapsed comes in collapsed when you add it to the track you're on.
* **(Pro) ReaComp** gets a panel of its own, as ReaEQ does: a transfer curve
  you drag. The threshold is a line across it (drag it up or down); the
  grips on its edges widen the knee, which turns the line into a band as
  wide as the knee and rounds the curve's corner; the curve's right-hand
  end sets the ratio (flat at the top is ∞:1). The dotted line is where the
  signal would go uncompressed, and the faint amber wedge between it and
  the curve is the reduction. Behind the curve are the plugin's level and
  gain reduction over the last few beats on the same dB scale, and a
  **live dot** shows where the signal is on the curve right now, with a
  short tail: a hit lands on the dotted line and sinks onto the curve at
  the attack speed, and drifts back at the release speed. At the foot,
  attack, release and pre-comp are an **envelope** — the reduction rising
  over the attack and falling straight into the release from the moment
  the signal crosses the threshold (the dotted tick). Drag the top node for
  attack, the end node for release, and the start node back before the
  tick for pre-comp (ReaComp's lookahead, which adds that much latency);
  **A** is auto release. Wet, dry and auto make-up sit beside it, the
  reduction and output meters run down the right, and the **detector** —
  main input or sidechain, RMS, its low- and high-pass and preview — is in
  a drawer underneath. The level history and the dot come from the track's
  TS_TrackProbe pair, connected while the panel is open. ReaComp's *Limit
  output* switch isn't one of its parameters, so the panel can't offer it.
* **Duplicate** a plugin or a container from its menu: a copy, settings and
  all, in the slot right after it.
* **Parameter modulation.** Right-click a control ▸ *Parameter
  modulation…* opens REAPER's Parameter Modulation / Link window for that
  parameter (ticked while its modulation is on). A control with REAPER's
  own LFO or audio follower on shows a mark — a dot in the middle of a
  knob, a corner on a button, dropdown or fader — in the accent colour, or
  black or white where the accent wouldn't show. A control driven by a
  macro or modulator shows that instead (see *Macros and modulators*).
* **Automation lanes.** Right-click any control ▸ *Automation lane* shows
  its lane in the arrange view (ticked while it's showing, with *has
  automation* beside it when it has some), and *Remove the lane* takes the
  lane away, asking first if there's automation on it. An XY pad or a
  concentric knob has one of each for its two parameters. The Channel
  panel's fader menu has *Volume automation lane*, a right-click on its pan
  knob *Pan automation lane*, and a ReaEQ band's menu *Automation lanes ▸
  Frequency / Gain / Q*. REAPER switches a parameter's modulation on when
  it makes a lane for it, which holds the control where it is; ChannelView
  switches that straight back off.
* **FX chains.** The chain button in the header, left of the FX bypass,
  loads an FX chain onto the track — after its plugins, or with *Replace
  the existing FX* ticked, in their place (the probes, Trimmer and
  ChannelView Modulators stay); it can also **save this track's chain**
  under a name of your own (in a folder of your FXChains folder, if you
  like) and **delete** a chain. A container's menu saves just that
  container as a chain. They're REAPER's own `.RfxChain` files, so REAPER's
  FX browser sees them too.
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

  A plugin you've taken out of its developer in REAPER's FX browser
  (right-click ▸ *Remove from developer*) is left out of the menu and the
  search too, so one gesture hides it everywhere; one already on a track
  keeps its panel. Shell plugins such as Waves are matched to REAPER's
  developers, categories and folders build by build. **Developers** are
  exactly REAPER's list: JS effects have no developer there, so they are
  found through All plugins, the search and your folders instead.

  **FX folders** are REAPER's own (the ones its FX browser shows), and the
  menu edits them: right-click any plugin for *Add to folder* (or a new
  folder, named on the spot) and *Remove from folder*; right-click a folder
  in *Folders* to remove it (its plugins stay installed), or use *Remove
  this folder…* inside it; the name box and **[+]** at the foot of the list
  make a new one. A backup of REAPER's folders file is kept before each
  change.

  The menu's first item opens a **search dialog** for when you know the name
  and typing is quicker: any words you type must all match somewhere in the
  name, format or vendor, so `fab sat` finds FabFilter Saturn. It carries
  the same Folders / Categories / Developers filter, and filter and search
  compose — pick FabFilter, type `pro`, get the Pro- series. Arrows move,
  Enter adds, and the last ten you added sit at the top. The search box at
  the top of the menu itself works the same way: type, Up and Down to pick,
  Enter to add.
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
* *View ▸ Macros*, *Modulators*, *Sends* and *Receives* show or hide those
  panels; a hidden one gives its room to the plugins.
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

## The Trimmer (Pro)

ChannelView's own first-in-the-chain plugin (`TS_CV_Trimmer.jsfx`, shown as
**Trimmer**): two VU meters, a trim for each channel, and a low cut and a
high cut. The header's Trimmer button adds one with a click, after an ARA
plugin, the pre probe and the modulators; with one there, it's the menu.
*Add TS_CV Trimmer to selected tracks* does the same from the Action List.

- **Meters.** VU, after the trim and the filters, sine-calibrated: a sine
  at the 0 VU reference reads 0. The lamp lights when a peak goes over the
  peak ceiling. Right-click a meter: the 0 VU reference (−24 to −12 dBFS,
  or your own), *Set 0 VU to this level*, the peak ceiling, and *Set as
  default* for new Trimmers.
- **Trims.** ±24 dB, linked or not (the rings between them): linked, moving
  one moves the other by the same amount.
- **Auto.** Sets the trim from the track's items: their average on 0 VU and
  their peaks under the ceiling, whichever needs less, the loudest item
  deciding, inside the time selection when there is one. The items
  themselves aren't touched. *Auto trim TS_CV Trimmer on selected tracks*
  does a whole selection, or the session.
- **Listen.** For a track with nothing recorded: press it, play the
  loudest part, press Stop, and the trim is set by the same rule.
- **Filters.** 6 to 48 dB/oct, each off at the end of its range (low cut
  all the way left, high cut all the way right). Over the spectrum (the
  switch by the slope lists): drag a handle, wheel over it for the slope,
  or double-click the canvas to put the low cut (under 1 kHz) or the high
  cut there. With the spectrum off, two knobs.

## Macros and modulators

Two panels sit between the Channel panel and the plugins: **Macros** and
**Modulators**. Both start folded; click the header to open one. The
dashed tile at the end of each adds one, and the foot says how many of
the track's 16 macros or 8 modulators are in use.

They live in one small plugin, **ChannelView Modulators**
(`TS_CV_Modulators.jsfx`), which ChannelView puts on the track when you
add the first macro or modulator and takes off again with the last (unless
it has automation lanes). It sits at the start of the chain, after the
pre probe and behind an ARA plugin such as Melodyne, and is kept out of
the plugin row. Controls follow it through REAPER's own parameter links,
so the track plays back the same without ChannelView running, and every
macro and every modulator setting is a parameter you can automate, learn
to a control surface, or draw in a lane.

**Macros** are a knob, an on/off button, a fader, a dropdown or an XY pad
(which uses two macros, X and Y). Right-click a macro's name to rename
it, change its colour, change what it's shown as, open its automation
lane, see what it drives, or remove it. A **dropdown** has 2 to 8 named
choices, spread evenly (right-click ▸ *Choices…*); drop one on a stepped
parameter and it offers to take that parameter's own choices.

**Modulators** are an **LFO** (six shapes, a rate synced to the tempo or
free in Hz, phase, depth, smoothing), a **Follower** (the track's own
audio or its sidechain on 3/4, attack, release, floor and ceiling, or a
gate that's on above the floor) or **MIDI** (velocity, note, CC, pitch
bend or aftertouch, on any channel or one, with the note range, CC number
or a velocity hold as fits). MIDI passes through untouched. Click a tile's
name to open its settings; every setting has a small lane button for its
automation lane.

**Linking.** Drag the ◯ on a macro or modulator onto any control, or
right-click a control ▸ *Link to a macro or modulator*. One source can
drive as many controls as you like; a control takes one source, and
dropping a different one on it asks first. An XY pad or a concentric knob
takes one per parameter: drop on the pad's left or right half for X or Y,
on the knob's ring or its inner knob. Linking switches off any LFO or
audio follower REAPER itself had on that parameter. Hover a ◯ to see
faint lines to everything it drives, or hover a driven control for the
line back to its source.

A driven control **follows its source** as it moves, and shows its reach:
a ring around a knob, a bar beside a fader or along an XY pad's edges.
Turn the control itself and the whole range moves with it.

- From a **macro**, the two handles are where the control sits with the
  macro at 0% and at 100%. They can cross, to run it backwards. A new link
  takes the control's whole range. The control's menu has the same as
  *At 0%* and *At 100%*, *Swap the ends* and *Whole range*.
- From a **modulator**, the handles are the two ends of its swing, at rest
  and at full. A control that sits in the middle of its range (a gain in
  ±dB, a pan) swings both ways round where it's set; others swing one way.
  The control's menu has *Depth*, *Invert* and *Bipolar*.

Right-click a lane button (on a macro, or on a modulator setting) to show
or hide its lane, or to remove it, automation and all after asking. A
lane that exists but is hidden shows faintly in the source's colour.

**Modulators moved by macros and modulators.** A modulator's own settings
take links too: drag a macro's or another modulator's ◯ onto a knob in an
open modulator tile — an LFO's depth, rate, phase or smoothing; a
Follower's depth, attack, release, floor, ceiling or smoothing; a MIDI
modulator's depth, low, high or smoothing. Each modulator takes up to two
of these. They behave like any linked control: the knob follows its
source, a ring shows the reach with a handle at each end to drag, Alt-click
a reach's handle to remove it, and turning the knob moves the setting under
them. A modulator moving another is read a block late, so two can move
each other without a loop; a modulator can't move itself.

A **button or dropdown macro** can also drive a switch: an LFO's shape,
sync or free, a Follower's source or gate, a MIDI modulator's hold. Dropped
on one, a dropdown offers to take the switch's own choices (so a dropdown
dropped on *Shape* becomes Sine, Triangle, … and picks the shape); right-
click the switch to set which setting each choice gives, or to remove the
link. The switch shows the setting in use.

Dots after a tile's name, in the sources' colours, say what moves it; the
tile's name menu and a knob's right-click list them. All of this lives in
the Modulators plugin, so it plays back without ChannelView running. A
project still running an older copy of the plugin gets it once it's
reopened (until then REAPER runs the plugin as it was loaded, and
ChannelView doesn't offer it).

## MIDI learn

The **MIDI** button in the header opens a bar under it, full width: the
parameter you last touched — a ChannelView control or one in a plugin's
own window — on the left, the MIDI control you last moved on the right,
and a link button between them. Click it to link the two (hollow blue: not
linked; filled green: linked; click a green one to unlink). The link is
REAPER's own MIDI learn, the same one REAPER's learn window makes, so it
shows there too and works without ChannelView.

It takes CCs, notes (a footswitch, say), program change and pitch bend.
The mode is guessed from what the control sends — an endless encoder's
1/127 is *Relative 1*, a control swept from 0 to 127 is *Absolute*, a note
is *Toggle* — and can be changed before or after linking. *Only when its
track is selected* (on by default) and *Soft takeover* sit beside it. The
**+** left of the parameter shows its automation lane; **More…** opens
REAPER's own learn window for it (OSC and anything else). A control's
right-click ▸ *Automate* ▸ *MIDI learn…* opens the bar with that
parameter in it.

## Action bars

Rows (or columns) of buttons that run any REAPER action — native, SWS,
your own scripts — built and arranged in one place and shown wherever you
put them. Every bar is global, not per project.

- **Where a bar goes.** A *drawer* in ChannelView's window: along the top
  (above the MIDI learn bar), down the left or right, or along the bottom
  under the track names. A bar in **its own window**, floating or in one of
  REAPER's dockers (wider than tall: rows; taller: a column). The TCP
  window's toolbar by the ruler or by the transport, or the web companion's
  Actions bar. Or **nowhere**, kept for later. One place per bar; the TCP's
  two and the web's take one bar each, and moving a bar onto one swaps it
  with the bar there. The header's drawers button lists the drawers and
  windowed bars (click to open or close one), makes new ones and opens
  **Organise actions**.
- **Menus.** A button can be a menu of actions, separators and further
  menus, nested as deep as you like. Clicking it always opens the menu.
  *Large items* (its right-click, or in Organise actions) gives it the
  taller rows of ChannelView's own header menus. The web page shows the
  same menus (a sheet, with *‹ Back* for a submenu).
- **Plugins and FX chains.** A button that adds a plugin, or an FX chain,
  with one click — no Insert FX action in REAPER's Action List. *+ Plugin*
  and *+ FX chain* in Organise actions: the menu stays open, each click
  makes a button and a second click takes it off again; in *Search…*, tick
  several and *Add* them together. A click adds it to the selected tracks
  (the last touched one when none is): after the plugin selected in
  ChannelView (the panel last clicked, outlined), else at the end of the
  chain, never ahead of the Trimmer, the pre probe or the modulators. Its
  window stays closed. The button lights while the selected track has that
  plugin, and gets an icon for its type (EQ, compressor, reverb…). They
  work on every bar, the web page's included; REAPER's own toolbars can't
  hold them. An FX chain button's **When clicked** (its right-click, or in
  Organise actions) is *Add it*, *Replace the plugins* (the chain takes
  their place; the probes, Trimmer and ChannelView Modulators stay) or
  *Ask each time* (a click asks which, on the web page too).
- **Toolbar switches.** A button that puts another bar in this bar's place
  — its spot, width, docker or window position — and puts this one away;
  lit while its bar is the one showing, so a row of them copied onto each
  bar of a set works as tabs. Or a **menu of every bar** to pick from.
  Right-click a bar ▸ *Add toolbar switch*, or *+ Switch* in Organise
  actions; *Switch to* in a bar's right-click does the same once. They work
  on the TCP's bars and the web page too.
- **Icons.** ChannelView has its own icons, drawn sharp at any size in the
  bars' colours (lit on the accent while a toggle is on): REAPER's main
  toolbar, transport, editing, markers and regions, fixed lanes and
  comping, the View menu, SWS windows, ChannelView's own scripts,
  instruments and effect types, nearly 300 in all. A button added from the
  Action List, or copied from a REAPER toolbar, gets the icon made for its
  action without being asked; right-click a bar ▸ *Use ChannelView icons*
  gives every button its icon. The icon picker has a *ChannelView* tab
  (the icon made for that action first) and *Your PNGs* (from
  `Data/toolbar_icons`; *Add a PNG…* copies one there from anywhere).
  The web page draws the same icons from the same
  file, `TS_CV_ActionIcons.json`.
- **Look.** *Icons and labels* or *Icons*, a **Size** per bar (Small,
  Normal, Large, Extra large) and where the buttons sit (**Align** left,
  centre or right; top, centre or bottom), in a bar's right-click ▸
  *Show* or in Organise actions. The TCP's bars still fit the ruler's
  height.
- **Colours.** A button can have a colour (its right-click ▸ *Colour*, or
  Organise actions; the first swatch is *no colour*). Each bar shows them
  as **underlines** or as **coloured icons**, where the icon and label
  are drawn in the colour and the button fills with it while on; a
  button with your own PNG icon keeps the underline. A button can go its
  own way: *Underline* and *Colour the icon* under its colour, either,
  both or neither. **…** beside the swatches opens ChannelView's colour
  dialog for any other colour (palettes, a picker, the eyedropper). In a
  menu, a button's colour is a strip down its row's edge, beside its icon.
  The web page shows the same.
- **(Pro) Vendors.** Organise actions ▸ *Vendors…* gives each plugin developer
  a colour, initials and a look, and every plugin button of theirs picks
  it up, new ones included: *Colour only*, *Initials tile* (the initials
  in a tile where the icon goes), *Colour fill* (the button's ground in
  the colour) or *Prefix* ("IKM - Tape Machine 24"). The list shows the
  vendors on your bars; *Scan plugins* adds every developer among your
  installed plugins, as REAPER's FX browser lists them, with how many each
  has; *Set up* one, or *Set up all* (each gets a colour of its own).
  *Same as…* gives one vendor another's look (Brainworx as Plugin
  Alliance). A colour or a PNG icon set on a button itself still wins, and
  so does a look of its own: **Vendor look** (a plugin button's
  right-click, or beside its colour in Organise actions) picks any of the
  four for that one plugin, or *No vendor look*; *As its vendor* follows
  the vendor again. The web page shows the same.
- **Organise actions** (the drawers button, a bar's right-click, or the
  *Organise actions* action, which works without ChannelView open): every
  bar by place on the left; the selected bar's buttons as a tree in the
  middle — drag rows to reorder, drop onto a menu to put it inside, + adds
  actions, menus, switches, separators and gaps, *Import* copies a REAPER
  toolbar or menu; the selected button's label, icon, action and (web)
  colour on the right, with *Copy to* another bar. The web companion's
  list is edited here too.
- **Import / export.** The drawers button ▸ *Export bars to file* writes
  any of your bars to a text file; *Import bars from file* brings them in
  (new ones, or replacing yours of the same name), naming any action the
  importing REAPER doesn't have.
- **Bars in their own windows** are drawn by **ChannelView toolbars**
  (`TS_ChannelView_Toolbars.lua`), started for you when a bar goes in a
  window; it can run when REAPER starts (a windowed bar's right-click).
  A bar in a window shows its name as a drawer does (at the start of a
  row, over a column), as a docker doesn't always show a window's title.
  **Background** (its right-click, or in Organise actions) gives it a
  colour of its own: a faceplate colour or any colour at all.

## Panels are a fixed height and grow in columns

Rows fall out of the window height. Controls flow down a column and wrap
into a new one, so a panel never scrolls vertically — the row of panels
scrolls sideways instead. Make the dock taller and panels get narrower;
make it shorter and they spread out. A grid layout keeps its own
arrangement instead (below).

## Grid layouts (Pro)

A layout can be a grid: every control has a place of its own on it, in
quarter cells (an ordinary knob is 4 × 4, a small one 4 × 2, a large one
6 × 6), and ChannelView, the rack and the web page all show it as it is.
**Edit layout** makes a layout a grid as it opens it, keeping the
arrangement it has now, in the rows the panel has: each control where it
is, each divider a line, each column of controls between dividers a
section, and a gap's background a section. The gaps themselves become
empty space. Undo puts it back.

- **Sections and lines.** A section is a group: a rectangle round some
  controls, with an inset, a faceplate or a colour of your own behind
  them, or none, and an outline, or none. A line is only a line, from one
  corner of the grid to another, any way, in the theme's colour or
  another. An outline's or a line's colour offers what a background
  does: the faceplates', the plugin's own (From the plugin), recent
  ones, or one of your own.
- **Locked to start with.** A layout made a grid is locked: where it
  doesn't fit it scrolls, up and down in ChannelView, sideways in the
  rack. Unlock it (the padlock in the panel's foot, or **Locked** in the
  grid editor) to have it flow instead.
- **Too small for it, unlocked.** Where the grid doesn't fit (ChannelView
  shorter than it, a rack column narrower) it flows: each section, with what's
  on it, as one, and the controls on no section a run at a time. One that
  fits keeps its arrangement and only moves; one that doesn't is laid out
  afresh, its background stretched round it. In ChannelView they go down
  then across, in the rack across then down. A line between two of them
  is drawn between them still.
- A control added to a grid layout goes on a new row under it.

**Edit layout…** (the panel's ☰ menu, or a control's right-click) opens
the grid editor, a window of its own. A layout that isn't a grid yet
becomes one as it opens, arranged as it was (**Undo** puts it back).

- **On the left**, the plugin's parameters (find one by name) and what
  else a layout can hold: a line, a section, a virtual knob, button or
  selector. Drag any of them onto the grid, or double-click a parameter to
  put it where it first fits. With **Learn** ticked, touching a control in
  the plugin's own window puts it on the panel. A parameter already on the
  panel is greyed: click it to select it there, drag it to move it.
- **In the middle**, the panel as it is, with the grid over it in quarter
  cells. Drag a control to move it, and its corner to resize it: a knob
  steps small, medium and large, a fader goes upright or across, a
  dropdown takes any width, a section any size. A section shows as an
  outline: drag it by its edge, and what's on it goes with it (inside it,
  the grid works as anywhere else). To draw lines, click **Line** on the
  left, then press on one corner of the grid and let go on another, any
  way; click Line again (or right-click the grid) to stop. Drag a line's
  end to move it, or the line to move it all. Two controls can't share a place unless
  they have Show rules (they take turns). Drag a control back to the
  list, or use **Take it off the panel** on the right, to remove it. The
  numbers under and beside the grid insert or delete a column or row of
  cells; **+** adds one at the end.
- **On the right**, everything about what's selected. For a control: its
  type, its alias and label, its values and scale, state names,
  Show when, a virtual control's name, choices and actions, then its
  **Style**, **Background** and **Copy and paste the style**, as its
  right-click has them (automation stays on the right-click). Its size
  (a knob's or a button's, a fader's length, thickness and way) is what
  you draw it on the grid. A control that changes shape (a dropdown shown
  as buttons, say) takes its own size where it is, if there's room. For a
  section, **Outline** and **Fill**, side by side: click either for its
  choices (the fill's finish and corners too). For a line, **Colour**. With nothing
  selected, the panel itself: locked, fit the grid to what's on it, the
  meters and live names, the faceplate, and **Switch layouts
  automatically…**. The look menus work while ChannelView shows the
  plugin's track.
- **In ChannelView** and **In the rack** show the panel at a window height
  or a column width of your choosing, flowing as it would there.
- **Layout**, at the top: the plugin's layouts. The one picked is the one
  this instance shows, and the one you edit. **New layout…** makes
  another, under a name you give it: a copy of this one, empty (your
  parameter names come with it), or **With a canvas** (an EQ, compressor
  or other canvas, this layout's controls beside it), which opens the
  canvas's setup.
- On a canvas layout (an EQ, compressor or other canvas), the grid is the
  controls beside the canvas, or under it in the rack. **Set up the
  canvas…** on the right opens the canvas's own setup. **In ChannelView**
  has a **Canvas width** too, and **In the rack** a **Canvas height**: the
  canvas's own size for this layout (**Reset**: the usual).
- **Several at once.** Ctrl+click adds a control to the selection or
  takes it out, Shift+click adds it; drag a box on empty grid round what
  you want (Ctrl+drag adds to it), Ctrl+click or Shift+click in the
  parameter list, or **Select all**. Drag any of them and they all move,
  as they are; drag them to the list to take them all off the panel. On
  the right: **Align** (left, centre, right, top, middle, bottom),
  **Distribute** (equal gaps across or down, three or more), and the
  settings the controls share (size, scale, Show when, centred, reverse,
  style, background), made on all of them. **Copy** and **Paste** make
  copies where they first fit, here or in another of the plugin's
  layouts: a virtual control gets a name of its own, and a parameter
  already on the panel isn't pasted.
- Every change is saved as you make it. **Undo** and **Redo** step back
  and forward through what you've done since the window opened.

## Panel layout: sizes, button rows and sections

Controls sit on a grid of half-cells. An ordinary control is one cell;
**View ▸ Control spacing** sets how wide a column is (46–64 px, 50 by
default), shared with the TCP window and the web page.

- **Sizes.** *Size* in the editor (with Pro, also right-click a knob ▸
  Style ▸ Size): *Small* is half height — a
  small dial under its name in small type, the value in the tooltip — so two
  stack in one cell; *Large* is half again as big. A toggle can be *Small*
  too: a half-height lit push-button with its name on it. A large knob in a
  panel one row tall draws at medium.
- **Button rows.** Right-click a dropdown ▸ Show as ▸ *Buttons across* or
  *Buttons down*: one button per choice, the current one lit. For 2 to 8
  choices; a column too tall for the panel shows as a dropdown.
- **(Pro) Raised dropdowns.** Right-click a dropdown ▸ Style ▸ *Raised*: the box
  becomes a dark cap like a *Backlit* button (unlit), standing off the
  faceplate with a shadow under it; *Flat* (the default) prints it on the
  panel. *Apply to every dropdown on this panel* does the rest.
- **(Pro) Sections.** A divider owns the controls after it, up to
  the next divider. Right-click any of them ▸ Section to put them on an
  **inset** or on a **faceplate of their own**. To style the first group,
  start the panel with a divider with *Line* off.
- **(Pro) Backgrounds.** Right-click a control ▸ Background for an inset or a
  faceplate behind that one control, over its section's. Neighbours with
  the same background — side by side, stacked, or facing each other across
  a divider — join into one rounded shape, always the full width of their
  column. Gaps and half-gaps (right-click the empty space) can have one too.
  Backgrounds and sections can have a **Finish** and the **Metallic flake**
  (in the same menus), like a faceplate's, and **Corners**: *Square*,
  *Soft* or *Round*. Sections in a row with the same style, faceplate,
  finish and corners join into one.
- **Faders of any shape.** Right-click a fader ▸ Style ▸ Shape, or in the
  editor: *Direction* up or across, *Length* 2, 3 or 4 rows (columns,
  across) or *Full*, *Thickness* a whole column (row) or half of one. Up
  and full is the standard fader, a column of its own at the panel's full
  height. The rest sit among the controls, their name over
  them and the plugin's value under them — half-width ones side by side
  make a graphic EQ's row of bands. A full-length fader across runs from
  where it lands to the panel's right edge.
- **XY pad.** Show as ▸ *XY pad*: two parameters on one pad, the first
  across (X) and a second, chosen in the control's menu or the editor, up
  and down (Y). 2×2, 3×2, 2×3 or 3×3 cells. Click or touch to put the dot
  there; Shift-drag moves it finely without a jump; double-click puts both
  back; the wheel moves Y, Shift+wheel X.
- **Concentric knob.** Show as ▸ *Concentric knob*: two parameters on one
  knob, as on a stacked pot — the outer ring turns the first, the inner
  knob (in the cap colour) a second, chosen in the control's menu or the
  editor. Where a drag starts decides which turns; the wheel turns the
  inner knob, Shift+wheel the ring; double-click puts back the one under
  the pointer. Medium or large. Either half of a concentric knob or an XY
  pad can be reversed on its own. Its **Style** is *Default* (a lit ring
  round a soft dome), *Arc (flat)* (the outer value as an arc round a flat
  knob that shows the inner one, and how it draws with the 3D effect off),
  or any knob recipe for the outer knob with another for the inner;
  *Customise…* edits either, with an *Outer / Inner* switch.
- **Where they go.** Controls fill a column top to bottom, then the next,
  in the panel list's order. A fader among the controls or an XY pad takes
  every cell it covers — like merged cells in a spreadsheet — and what
  comes after flows round it: below it in its own column, then above or
  below it in the columns it runs into. A fader across and an XY pad run
  over a divider (its line stops at their edges); everything else starts a
  new column at one. Panels with neither are laid out as usual.
- **Pages.** A **Page** break (the editor's *Page* button, beside Gap,
  Half-gap and Divider) starts a new page: everything after it, up to the
  next break, is a page of its own, and the panel shows one page at a time
  with a tab strip under its header. Controls before the first break are
  page 1. Select a break in the editor to name its tab and pick its
  colour (the stripe over the name; the theme's accent unless you choose
  one). Click a tab, or roll the wheel over the strip, to change page;
  right-click a tab for its colour. Dividers inside a page split its
  columns as usual. The panel is as wide as its widest page, and keeps
  the page it's on with the project.
- **(Pro) Show when.** A control can be shown only while another parameter of
  the plugin — on the panel or not — reads a given way: *is*, *is not*,
  *is above*, *is below* or *is between*. Set it in the editor's *Show
  when* row: pick the parameter, then the comparison and the value, from
  its choices for a switch or dropdown, or on a slider in the plugin's own
  readout for a knob. A hidden control takes no room, so two side by side
  with opposite rules swap in one place: a delay's sync switch showing its
  note knob when on and its ms knob when off. A rule can follow one of the
  layout's **virtual controls** too (below). Right-click a control ▸ *Show
  when* for the quick ones: *Always*, or one click on any button,
  dropdown, stepped knob or virtual control on the layout; anything else
  opens the editor at that control. Conditional controls are marked ◐ in
  the editor's panel list.
- **(Pro) Virtual controls.** A layout can have controls of its own that drive
  no parameter: a **button** (two named states), a **selector** (choices,
  as chips or a dropdown) or a **knob**. Add one with the editor's
  *Virtual* button; change its kind under *Type*. They're drawn in violet,
  and their state is kept per instance, with the project. Their job is to
  drive *Show when* rules and layout switching: a VIEW button that swaps
  two sets of controls in one place, or a selector that pages through a
  plugin's sections. Two layouts of the same plugin with a virtual control
  of the same name share its state. Right-click one for *Back to where it
  starts*. Each setting can also run a REAPER action (*Actions* in the
  editor: one per setting, a button's Off and On), from the panel and from
  the web page alike.
- **Lock layout.** The padlock at the left of a panel's foot locks that
  plugin's layout, on every track: no more edits, and the controls keep the
  arrangement they had however the panel is resized — a panel too short
  for it scrolls up and down instead (the wheel scrolls when it isn't on a
  control). Meters aren't part of it: they can still be switched on and
  off, and the trace opened. Click the padlock again to unlock.

## Naming: alias vs label

Two different things, kept apart on purpose:

* An **alias** is your name for one of the plugin's *parameters*. It follows
  the parameter everywhere — every panel, and the editor's lists — whether
  or not it's currently on a panel. This is the one you want for a plugin
  whose own parameter names are cryptic.
* A **label** is a caption for *one slot* on the panel, for when a layout is
  cramped and that particular knob needs something shorter.

Right-click a control ▸ **Name** has both — the alias, and this slot's
label — and *Live name*, which shows whatever the plugin calls the
parameter right now (for plugins that rename their parameters as you use
them). Setting the alias there clears the slot's label, so the new name
shows on the control you renamed. The editor has the same: *Alias*,
*Label* and *Live name*.

A **toggle** says what its state is called: your **state names** if you've
set them (right-click ▸ Name ▸ State names, or the editor's *State names*
row), else the plugin's own word for the state, and ON/OFF only when the
plugin just reports a number.

A **plugin instance** renamed in REAPER's FX chain shows that name on its
panel and keeps its layout, which belongs to the plugin. The panel menu's
name box renames it the same way (empty goes back to the plugin's name).

Every text box takes **Enter**: a name box does what its button does, and a
filter box takes the first match.

## Setting a plugin up

Right-click a control for the quick things. The menu is in four parts:
**Control** — what it does: *Show as*, *Name*, *Values*, *Centred fill* (a
fader's; a knob's is *Style ▸ Value arc ▸ Centred*),
*Reverse*, *Show when* (Pro); **Look** (Pro) — *Style*, *Background*,
*Section* and *Copy / paste style*; **Automate** — macros and modulators, its
automation lane and REAPER's parameter modulation; **Arrange** — *Insert
before* a gap, half-gap or divider, and *Remove from panel*. *Plugin ▸*
at the foot collapses, moves or opens the whole plugin. Everything under
Control is in the editor too; looks are set from the right-click only.
*Edit parameters…* from a control opens the editor with that control
selected. With Pro, **Edit layout…** (see *Grid layouts*) takes its
place.

The panel menu (**=**) is in three parts: **Layout** (which layout, *Edit
parameters…*, *Faceplate*, *Meters*, *Reset layout* — auto-fill, clear,
forget), **Plugin** (collapse, its window, the FX chain, oversampling,
offline) and **Chain** (move, route, duplicate, insert, containers), with
*Remove* at the foot.

For the full dialog: panel menu **=** ▸ *Edit parameters…*, or just click an
unconfigured panel. What the panel shows on the left, the plugin's
parameters in the middle, `<< Add` / `Remove >>` under them, and the
selected control's settings in a column on the right — one per row, only
the ones its type has. **Drag a row in the panel list
anywhere you like** — it lands where you drop it, not one place per nudge —
or use ▲/▼. Added parameters land *below* whatever is selected, since a
panel gets built by working down it.
Turn on **Learn** and touching a control in the plugin's own window adds
that parameter. **Auto-fill** grabs the plugin's first eight parameters as a
starting point.

Nothing is written until you hit **Save** — and Save changes the panel of
every instance on that layout, which the dialog says at the top.

### More than one layout for a plugin (Pro)

A plugin's layout is shared by every instance of it, which is usually what
you want. When it isn't — a Kontakt with a piano on one track and strings
on another — the panel menu's **Layout** (at the top) picks which layout
this instance shows: *Standard*, the plugin's own, or any you've made. Type
a name in the box and **Copy to new layout** makes a copy of the one
you're on, or **New empty layout** starts with no controls (your names for
the plugin's parameters come with it); either switches this instance to
it. Pick it on any other instance from the same menu. *Delete layout…*
removes one, and the instances using it go back to the plugin's default.
Each instance's choice is kept with the project; the layouts themselves are
in the library like any other, as `<plugin> :: <name>`.

A plugin's layouts can also **switch themselves**: Edit Parameters ▸
*Switch layouts automatically* holds rules such as *use "Dual" when Mode
is Dual*, on any parameter or one of the layout's virtual controls (*is*,
*is not*, *is above*, *is below*, *is between*). The first rule that
matches decides; when none does, the instance's own pick applies. A rule
on a knob has a little slack, so a knob sitting on the line doesn't
flicker. The panel's header shows which layout a rule chose, and the
*Layout* menu says which rule is in charge. The rules belong to the
plugin and are saved as you change them.

Any of them can be the plugin's **default**: *Make "<name>" the default* in
the same menu. New instances, and any not set to another, show it; the
menu marks it *(default)*. *Standard* is the default until you choose
another.

*Edit Parameters* has the same at the top of its window: which layout
you're editing (switching it switches the instance, and asks first if
you've changes you haven't saved), and *Copy to new layout* / *New empty
layout*, which work from what's in the editor — unsaved changes go to the
new layout and the one you started from is left as it was.

### Canvas layouts for any plugin (Pro)

ReaEQ and ReaComp have canvases of their own. Any other plugin of the right
kind can have one too, as a layout: panel menu **=** ▸ *Layout* ▸ **New
canvas layout** ▸ *EQ*, *Compressor*, *Multiband*, *Gate*, *Limiter*,
*De-esser*, *Saturation*, *Delay*, *Reverb*, *Modulation* or *Envelope*.
ReaDelay and ReaVerbate set themselves up. The canvas fills the left of the panel and
the plugin's other controls sit in columns beside it: the new layout starts
with the controls of the one you made it from, less those the canvas takes,
with their looks and the faceplate. Set it up in the window that opens —
name the plugin's controls for each role, or let **Guess from names** do
it; *Set up this layout…* in the same menu, the panel's own
button, or *Set up the … canvas…* in Edit Parameters brings it back.
Canvases show no text readouts of what they measure: they draw it.

**An EQ layout** has up to 8 bands. Name each band's controls — frequency,
gain, Q, a shape switch, an On switch; any can be left out — or **Guess**
them from the parameters' names. A plugin's controls don't say what shape a
band is, so ChannelView **learns** it: it puts a copy of the plugin on a
hidden track between a pair of its own measuring plugins
(`TS_CV_Learn.jsfx`), plays noise through it and measures what each
setting does — every position of a switch, a range of gains (boost and cut
separately, since many EQs differ), each shape and the Q. A band whose
plugin reports its frequency, gain and Q needs only a quick check of each
shape, at each gain; bands that are alike (the same shape switch) are
learned once and share it. REAPER has to be processing FX while stopped
(Preferences ▸ Audio ▸ *Run FX when stopped*, on by default). The canvas is
ready once every band is learned; change a band's controls and it learns
that band again.
On the canvas, drag a node across for frequency (a switch snaps to its
settings) and up or down for gain; the wheel turns Q; double-click takes
the band out (flat, or off). Right-click a node for its shapes and its On
switch, or Alt+wheel to step the shape. The nodes say what the plugin's
own controls read.

Bands can be any shape: bell, shelves, cuts at any slope up to 96 dB/oct
and brickwall, notch, band pass, tilt shelf, flat tilt, flat top, sword and
all pass. A plugin that names its shapes (Pro-Q's *Notch*, Kirchhoff-EQ's
*E LMF* or *Wall LP*) is drawn by the name it shows now, and its slope is
read from its own *Slope* control, so a change made in the plugin shows at
once. A switch with up to 64 settings can be learned.

Learning also keeps what a shape does that no formula catches — a console
type's long tail, a shelf's bump or dip, a boost shaped unlike its cut —
and the canvas draws it, smoothly, at any gain. The *Learned* column in the
setup says *measured shape* where a band has one. A plugin-wide switch that
changes every band (TDR Slick EQ's *EQ Model*) can be named as the
**Model** in the setup (ChannelView guesses it from the names; clear it if
it guessed wrong): learning measures every setting of it, which takes as
many times longer, and the canvas draws the one the plugin is on. Layouts
learned with an earlier ChannelView keep drawing as they did; learn again
(*Set up this layout…* ▸ *Learn*) to have the measured shapes.

An EQ layout can be a **dynamic EQ**: tick *Dynamics* in its setup and map
each band's threshold, range, ratio, attack, release and dynamics switch.
Learning holds the dynamics off; the canvas draws each dynamic band's
reach, with its range node to drag, and the picked band's level going in
against its threshold.

**A compressor layout** maps roles to the plugin's controls: Threshold,
Input, Ratio, Knee, Attack, Hold, Release, Make-up and Mix, each optional.
The canvas takes the plugin's own values as fact, and a control that
doesn't read in its role's unit (a 1176's attack of 1 to 7) runs along its
range instead. A compressor's dB isn't always dBFS (an SSL bus compressor's
0 dB is −22 dBFS), so **Measure threshold** in its setup plays a sine
through a hidden copy at rising levels and finds where it starts to
compress; the canvas then draws and drags the threshold in true dBFS. A
knee reading 0–1 is drawn as a share, and ratios under 1:1 (expansion)
are drawn as such. Tick **Reversed** for a *Compression* or
*Peak reduction* control (more of it is a lower threshold), or an attack,
hold or release that's fastest at the top. A compressor with no threshold
maps its **Input**: its threshold is drawn fixed (measured, or a guessed
−10 dBFS), and the input as a gain bar raised towards it from where a
signal at its 0 dB sits (−18 dBFS unless you set it); map its Output as
Make-up. A switched ratio or time snaps to the plugin's own settings (a
release's *Auto* sits after its longest time). Hold draws as a flat top on
the envelope. With a probe pair on the track, a live dot rides the curve.

**Gate and limiter.** A gate draws its open and close thresholds (solid
and dashed), the range floor and the ratio, with a lamp that lights while
it's open; a limiter its level history with the threshold (or input gain)
and the ceiling.

**Multiband.** Up to four bands, split by shared crossovers or by each
band's own edges (as Pro-MB does). *All bands* shows the bands over the
spectrum with a strip each — a small transfer curve with its threshold,
a dot riding it at the band's level going in, and sliders for ratio,
attack, release and gain — plus solo, bypass and the band's in-use
setting; + BAND takes an unused band into use. Click a band for the full
compressor canvas. One reduction meter for the whole plugin.

**De-esser.** Its band (split-band above the frequency, or around it) over
the spectrum, filled from the top as it reduces, and the waveform with the
reduced part in the reduction colour.

**Saturation.** ChannelView **learns** the plugin's curve on a hidden copy
— a sine at three levels, across the drive's positions and each style —
and draws it with the music's level riding it, the harmonics it adds, and
a VU-style drive meter: 0 is where the curve starts to bite. Tone controls
are held where they're set while it learns.

**Delay.** Every delay is drawn as echoes on one timeline: left above the
line, right below, the time across (in note values when synced), feedback
as the second echo, ping-pong, stereo modes (their meanings set in setup),
offsets and ratios. Up to 10 **taps** with their own time, level, pan and
feedback — click a tap's dot for its own controls. A *Filters* strip
draws the low and high cuts. ReaDelay's taps are added (+) and removed on
the canvas.

**Reverb.** Its energy over time — the pre-delay gap, early reflections
spaced by size and thinned by diffusion, the tail falling to −60 dB at
the decay time (or held, when frozen) — and, under it, *decay by
frequency* with the lows' and highs' crossovers and multipliers, a tone
tilt or shelves, and the low and high cuts. Style chips and FREEZE along
the top. A decay that doesn't read in seconds can be **measured**
(*Measure decay* plays bursts through a hidden copy).

**Modulation.** A scope of its LFO whose timebase follows the rate, depth,
rate and phase handles, shape chips, and up to three **voices** (a
chorus's L/C/R, each in its own colour, with its pan). **Envelope:** the
ADSR with its curve handles.

### Values: when a plugin won't say

Some plugins report their values as bare numbers (Acustica's, for one:
a frequency as 0.35). Right-click a knob or fader ▸ **Values** ▸ *Custom
range*: type what its ends read (20 to 20k), the unit and the curve
(linear, log, squared), and it reads as that everywhere — the panel, the
tooltip, the numbers round the dial and the web page. *The plugin's own*
goes back. The same is in the editor's *Values* row. For a knob, *Values*
also holds the **numbers round the dial**: *None*, *Values* or *0–10*.

## Hardware looks (Pro)

Everything here is Pro except **Track faders** and **Background tint**, at
the end. Right-click a knob or fader ▸ **Style** to give it a hardware face, and the
panel's **=** menu ▸ **Faceplate** to change the panel behind it.

- **Knobs:** *Arc* (the theme's own, and the default), *Skirted*, *Pointer*,
  *Trim pot*, *Round nose* (a round cap whose short, blunt nose is the
  pointer), *Bar* (a dome with a raised bar across it), *Fluted* (a domed
  body with finger flutes), *Bezel* (a black centre in a chrome ring),
  *Reverse bezel* (a satin black ring round a metal centre), *Hi-fi* (a
  spun-aluminium knob) and *LED ring* (a ring of lamps close round an
  encoder, lit up to the value, or out from the middle on a centred
  control, in its cap colour). Knob caps are matte, the way the skirted
  knob's skirt is. Then the **recipes**, built from parts: *Bakelite*,
  *Machined*, *Red gloss*, *Chicken-head*, *Printed skirt*,
  *Soft-touch*, *Chrome*, *Two-tone*, *Cream fluted*, *Coin edge*,
  *Washer*, *Console*, *White rim*, *Dial*, *British* and *Wing*.
  The Style menu shows them all as pictures.
- **Value arc.** Style ▸ *Value arc* puts a lit arc round any knob in place
  of its ticks or dots: *Positive* (from the start of its travel up to the
  value), *Negative* (from the end back to it) or *Centred* (out from the
  middle), in the theme's fill colour; on an Arc knob it sets which way
  its arc fills. *Centred* also makes the knob centred: an Arc or LED ring
  face fills from the middle, and a modulator swings it both ways round
  its setting. *The same for its section* and *For the whole panel* pass
  it on. The web page shows it too.
- **Your own knobs.** Style ▸ **Customise…** opens the *Knob look* window:
  start from any recipe and change its body, grip (and how many flutes or
  grooves), top, pointer, material, colours (body, sides, rim, pointer
  ink), skirt (its material, colour, print and size, a knurled
  edge), washer, hex nut, inner cap, scale and **Shadow** (*Normal*, *None*
  for a knob sitting flush, *Tall*). Apply it to this knob, this section
  or every knob on the panel, and **Save as recipe** to have it under
  *Your recipes* in every Style menu. Recipes are kept in
  `TS_ChannelView_Recipes.ini` beside your layouts. **Faders:** *Flat* (the default), *Console*, *Rail* and
  *Slim* (a fine groove and a small cap, filled to the value in its
  colour — made for rows of narrow faders).
- **Cap colours:** Accent, Red, Orange, Yellow, Green, Blue, Grey, Cream,
  Silver, Stone, Black, White, Brown and Gold. *Apply to every knob on this panel* copies one
  control's look to the rest. **Copy style** (right-click any control)
  takes its style, colour, size (a fader's shape), scale, background and
  finish; **Paste style** puts it on another control, on any panel, and
  *Paste to every knob (fader, button) in this section / on this panel*
  does the lot. A pasted look takes only what fits: a knob's style stays
  with knobs, but its colour goes onto a fader or a button. A toggle's Style is the colour it lights
  when on (Amber, Green, Red, Blue, Yellow, White or the theme's), and so
  is a button row's, along with its face: *Flat*, *Lit lens* (dark tinted
  glass that glows when on), *LED window* (a lamp strip across its top) or
  *Backlit* (a dark cap whose edge and lettering light up). A toggle can
  also be a **switch**: *Bat toggle*, *Paddle toggle*, *Pill rocker*, *Lit
  rocker*, *Slide*, *Pill slider*, *Lamp button*, *Round button*, *Jewel
  lamp* or *Guarded toggle* (a cover to lift first), lit in its colour —
  except the *Pill rocker*, which doesn't light: its colour is the colour
  of its cap (black when it has none). With the 3D effect off the levers
  draw as the pill slider. Under either row of swatches, **[+]** opens the colour
  picker for any colour at all, with your recent colours beside it.
- **The look new controls start with.** Style ▸ *Use this look for new
  knobs* (or *buttons*) on any knob or toggle: new layouts, the layouts
  ChannelView makes for plugins you haven't set up, and controls added
  in the editor start with it — a knob's style or own look, colours and
  value arc (a centred knob gets *Centred*), a button's style and lit
  colour. Layouts you've saved keep their looks. *Forget the look for new
  knobs* (*buttons*) goes back to the plain ones.
- **Faceplates:** Theme, Charcoal, Gunmetal, Aluminium, Steel blue, Navy,
  Cream, Cobalt, Amber, Stone, Racing green, Oxblood and Gold — or any
  colour at all: **[+] Custom colour…** after the list opens the colour
  picker (palettes, a picker and an eyedropper, below), and **Recent
  colours** keeps the colours of your own you've used since ChannelView
  started, for going back and forth between a few. The same goes for
  backgrounds and sections. Labels, values and scale ticks switch ink to
  stay readable on each, a custom colour's worked out from the colour
  itself. In the Faceplate menu, **Finish** gives any of them a surface:
  *Plain*, *Brushed* (aluminium's own unless you change it), *Anodised*,
  *Bright*, *Satin*, *Tolex*, *Leather*, *Wood*, *Crinkle*, *Enamel*,
  *Hammertone* or *Checker plate*, each in the faceplate's colour; the
  **Metallic flake** (a fine flake and sheen, like metallic paint) goes
  over any of them.
- **The plugin's own colours** (Windows, with js_ReaScriptAPI). Every
  colour menu — faceplate, section, background, knob and fader caps, lit
  colours — has a **From the plugin** row: the eyedropper reads the
  plugin's window (it comes to the front for a moment, and closes again
  if ChannelView opened it) and keeps its main colours and its accents
  with the layout, one click each from then on. **Faceplate ▸ Match the
  plugin** does the lot: the faceplate in its main colour, section
  faceplates and backgrounds in the next ones, and its accent on buttons,
  Arc and LED ring knobs and Slim faders.
- **Numbered scales:** knobs print numbers round their dial — **Values**
  (the plugin's own, units left off and thousands as k, so 12000 Hz reads
  12k) unless a knob's **Values** menu (or the editor's *Scale*) says **0–10** or **None**. A large knob has room for seven
  values (eleven for 0–10, or every step of a stepped knob with up to
  eleven); a medium one for three, its ends and middle (six for 0–10, or
  every step up to five). The knob keeps its size, so a number with no
  room for it in the cell is left out (its tick stays); a medium knob's
  value moves to its tooltip, and a small knob has no room for numbers.
  **Numbers in cap colour** (Style) prints them in the knob's colour
  instead of the faceplate's.

Only *Theme* and the *Accent* cap follow Hue/Tint; every other faceplate and
cap colour is fixed, the way hardware is. The menus stay open while you
click through them, so you can try a few and watch the panel change.
**View ▸ 3D effect** (on by default) lights the panels from the top left:
a gentle gradient on the faceplates (Theme stays flat), panel edges that
catch the light, and shadows under knobs, switches, styled buttons and
fader caps (not the Arc knob, which is a printed scale, nor flat buttons and
flat dropdowns, which are printed on the panel). One light lights everything, so
highlights stay put as a knob turns. **View ▸ Lighting** sets how strongly
(a more pronounced gradient on faceplates and knobs above 100%), and **View
▸ Shadows** how deep and far the shadows fall.

Like everything else on a panel, the look is saved with the plugin's layout,
so every instance of that plugin wears it.

**Track faders** — the Channel panel's, a mixer strip's, the TCP window's —
have looks too: right-click the fader for its **Style** (Flat, Console,
Rail) and **Colour** (the cap colours, [+] for any colour, recent colours).
It acts on the selection when the track is part of it, as REAPER's menus
do, and is saved with the track in the project. **Group looks** in the same
menu give every **folder parent**, **VCA leader** and **FX return** (a
track with receives that's neither a folder parent nor in a folder) a look
of its own, and **Default** covers every other track — and whatever a
group leaves unset — all kept with ChannelView for every project. A
track's own choice wins, then its group's, then the Default, part by part,
and *Reset to default* takes it back to its group's (or the Default).
A VCA leader that's also a folder parent counts as a VCA leader.

**Background tint** gives a track's mixer strip, its name button and the
Channel panel a share of the track's colour. Each group in *Group looks*
has a **Background** strength (folder parents at 60% and everything else at
15%, say), and a track can have its own in the fader menu's **Background**
slider; *As group* goes back to its group's. Off by default. A light
colour is held back so the readouts on it stay readable. The TCP window
follows, unless its View menu ▸ *Background tint* is off. The web page has
it too.

## Controls

| | |
|---|---|
| drag up/down | change value |
| wheel over empty space | scroll the row of panels sideways |
| hold Shift | fine |
| mouse wheel | step (unless *View ▸ Use mouse wheel on controls* is off: then it only ever scrolls) |
| double-click | back to the parameter's centre/detent |
| hover | the current value, in a tooltip that stays put |
| right-click | control menu |
| click a stepped value | its list of choices |

## Presets

The bar along the foot of each panel is the plugin's preset box: the
current preset in the middle (a `*` after it means the plugin has changed
since it was loaded), previous and next beside it, and **+** for *Save
preset…*, *Save as default…*, *Rename* and *Delete*. The default is the
preset REAPER loads whenever the plugin is added; ★ marks it in the list.

These are REAPER's presets, not ChannelView's: the same `presets/*.ini`
files, written exactly as REAPER writes them, so whatever you save shows up
in the plugin window's own preset box and the other way round. Saving
works for VST2, VST3, JS and CLAP; AU presets load but can't be saved from
here. **View ▸ Preset bar** hides the bar; the foot itself stays, for
the layout lock at its left.

Some plugins change programs without telling REAPER their parameters
moved, which would leave the controls where they were. After loading a factory
preset, ChannelView checks, and if nothing moved it hands the plugin its
own state back so REAPER reads every parameter again. A plugin that's slow
to say what preset it's on (VSL's Synchron Player takes a third of a
second) is asked only now and then.

## The master

With the master selected, the Sends panel shows its hardware **Outputs**
instead: level, mute and pre/post as on a send, and a button showing which
of the audio device's channels it goes to ("1/2", "5") — click it to move
the output or remove it. The add tile lists the stereo pairs and, under
Mono, the single channels. The master has no Receives panel. Its strip has
a **Mono** switch where other tracks have record arm (REAPER's *Master
track: Toggle stereo/mono*).

## Track colours

Right-click a track ▸ *Colour…*. The palette dropdown has what REAPER
7.81's colour picker has — the project's colours, the built-in palettes and
User 1 to 4 (from `reaper-colors.ini`) — and the old 16 custom colours
(`custcolors` in reaper.ini, the list SWS palettes load into). A click on a
swatch colours the track and closes; *REAPER's colour picker…* opens
REAPER's own, which works on the selected tracks. The built-in palettes
aren't saved anywhere REAPER can be asked for them, so ChannelView carries
a copy of 7.81's.

Under *Any colour*, the **eyedropper** beside the picker takes the colour
of anything on screen, in REAPER or out of it: switch it on, point, and
click — or press Enter, so the click doesn't land on another program —
and Esc puts it away. It needs the js_ReaScriptAPI extension (from
ReaPack). Every colour picker in ChannelView and the TCP window has it.

In the TCP window, the settings menu's **Plugin delay (PDC) under
meters** shows each track's plugin delay compensation under its meter,
in samples and milliseconds — on tracks with any, when the row is tall
enough.

Its **Track buttons** (the settings menu) choose which of monitoring,
record arm, mute and solo are on every row; with *Show the others while
on*, the rest appear only while they're on. Each keeps its own place, in
that order, so they line up down the panel. Press mute, solo or record arm
and drag down the column to set a run of tracks, as in the mixer;
double-click clears one. Monitoring cycles off, input and auto. A lane's
menu in the TCP window has **Remove envelope**, which asks first when the
lane has automation.

The TCP window's two toolbars are action bars like any other (see
*Action bars*): right-click one ▸ **Copy a REAPER toolbar** to fill it
with the buttons of any toolbar you've customised in REAPER. A button
whose action has a ChannelView icon gets that; otherwise REAPER's own
icon comes too, found in `Data/toolbar_icons` and the current theme's
folder as REAPER's toolbars find them (a toggle with an `_off` icon shows
its `_on` partner while it's on).

## Files

| | |
|---|---|
| `TS_ChannelView.lua` | entry point — run this one |
| `TS_CV_Config.lua` | sizes, colours, glyphs, behaviour. All hand-editable |
| `TS_CV_Util.lua` | name cleaning, INI, parameter helpers |
| `TS_CV_FXTree.lua` | container-aware FX chain walk |
| `TS_CV_Mappings.lua` | the layout library |
| `TS_CV_Edition.lua` | Standard or Pro: finds Pro's files, and greys Pro's menu items without them |
| `TS_CV_Pro.lua` | ChannelView Pro's package; Standard looks for it (Pro) |
| `TS_CV_GridEditor.lua` | the grid editor (*Edit layout*) (Pro) |
| `TS_CV_Widgets.lua` | knob / button / stepped-value drawing |
| `TS_CV_Panel.lua` | one plugin's panel |
| `TS_CV_Editor.lua` | the Setup Edit Parameters dialog |
| `TS_CV_Mixer.lua` | mixer view, and the shared track row (`MX.draw_row`) both views draw into |
| `TS_CV_TrackStrip.lua` | asks the track row to scroll to the selection |
| `TS_CV_Browser.lua` | the add-a-plugin picker |
| `TS_CV_Search.lua` | the forgiving, ranked plugin search (picker, [+] menu and web page) |
| `TS_CV_FXIndex.lua` | REAPER's Developers / Categories / FX Folders metadata |
| `TS_CV_Channel.lua` | the pinned Channel panel |
| `TS_CV_Taps.lua` | routing for measured gain reduction, and reading it back |
| `TS_CV_ProbeLink.lua` | talking to TS_TrackProbe: through shared memory, or parameters on older probes |
| `TS_CV_MidiLearn.lua` | the MIDI learn bar |
| `TS_CV_Trace.lua` | the gain-reduction trace's data, shared with the web page |
| `TS_CV_Mod.lua` | macros and modulators: the plugin, the links, ranges and swings |
| `TS_CV_ModRack.lua` | the Macros and Modulators panels |
| `TS_CV_Modulators.jsfx` | the ChannelView Modulators plugin. Goes in `Effects/` |
| `TS_CV_CanvasSetup.lua` | setting up a canvas layout for any plugin (Pro) |
| `TS_CV_RolePanel.lua` | the canvases for gates, limiters, multiband, de-essers, saturation, delays, reverbs, modulation and envelopes (Pro) |
| `TS_CV_Delay.lua` | the delay canvas's model: every delay as echo lines or taps (Pro) |
| `TS_CV_ReaFX.lua` | ReaDelay's and ReaVerbate's canvases, and adding and removing ReaDelay taps |
| `TS_CV_Busy.lua` | backing off while REAPER is busy |
| `TS_CV_MapPanel.lua` | an EQ layout's canvas (Pro) |
| `TS_CV_MapEQ.lua` | an EQ layout's bands: their shapes, reading and setting them (Pro) |
| `TS_CV_AutoFloat.lua` | View ▸ Float plugins without controls: opening and closing their windows |
| `TS_CV_PluginColours.lua` | A plugin's own colours, read off its window (Pro) |
| `TS_CV_Freeze.lua` | freezing: REAPER's own, with the frozen plugins shown where they were and ChannelView's own plugins kept live |
| `TS_CV_Learn.lua` | learning and measuring on a hidden copy of the plugin: EQ bands, thresholds, reverb decay, saturation (Pro) |
| `TS_CV_Learn.jsfx` | the measuring pair it uses. Goes in `Effects/` (Pro) |
| `TS_CV_Trimmer.jsfx` | the Trimmer plugin. Goes in `Effects/` (Pro) |
| `TS_CV_Trimmer.lua`, `TS_CV_TrimmerPanel.lua` | the Trimmer's insert, auto trim and listen; its panel (Pro) |
| `TS_CV_Units.lua` | reading a plugin's values from its own text (dB, Hz, ms, ratios) |
| `TS_TrackProbe.jsfx` | the probe that measures it (shared with Track Analyser). Goes in `Effects/` |
| `TS_CV_Sends.lua` | the pinned Sends panel and its add menu |
| `TS_CV_Share.lua` | importing and exporting layouts (*Layouts ▸ Import / Export*) |
| `TS_CV_ColourPick.lua` | the colour picker every colour dialog shares: palettes, eyedropper, recent colours |
| `TS_ChannelView_ToggleMixer.lua` | the *Toggle mixer view* action, for a shortcut or toolbar |
| `TS_CV_Toolbar.lua` | an action bar: its buttons, menus, switches, icon picker |
| `TS_CV_FXButtons.lua` | buttons that add a plugin or an FX chain |
| `TS_CV_Vendors.lua` | a colour, initials and a look per plugin vendor (Pro) |
| `TS_CV_Finish.lua`, `textures/` | faceplate, section and background finishes, and their texture tiles (copied to `reaper_www_root/` for the web page) (Pro) |
| `TS_CV_Switches.lua` | the switch styles for toggles (Pro) |
| `TS_CV_Light.lua` | the one light and the shadows (Pro) |
| `TS_CV_KnobParts.lua` | knobs drawn from parts, for the recipes and your own looks |
| `TS_CV_KnobEditor.lua` | the *Knob look* window (Pro) |
| `TS_CV_Recipes.lua` | your knob recipes (Pro) |
| `TS_ChannelView_Rack.lua` | **ChannelView Rack**: the plugins down a column (Pro) |
| `TS_CV_Drawers.lua` | every action bar and where it is: drawers, windows, the TCP's, the web's |
| `TS_CV_ActionEditor.lua` | the Organise actions window, and importing and exporting bars |
| `TS_CV_ActionIcons.lua` | drawing ChannelView's icons, and finding the one made for an action |
| `TS_CV_ActionIcons.json` | the icons themselves, shared with the web page. Goes in `reaper_www_root/` |
| `TS_ChannelView_Toolbars.lua` | **ChannelView toolbars**: bars in windows of their own |
| `TS_ChannelView_OrganiseActions.lua` | the *Organise actions* action |
| `TS_CV_Startup.lua` | the Run-when-REAPER-starts option, and the `__startup.lua` surgery |
| `TS_CV_State.lua` | per-instance view state (collapsed), saved in the project |
| `TS_CV_Steps.lua` | cached choices for stepped parameters (derived, deletable) |
| `TS_ChannelView_Web.lua` | the web companion's bridge — see *On a tablet* (Pro) |
| `TS_ChannelView.html` | the web companion's page. Goes in `reaper_www_root/` (Pro) |
| `TS_ChannelView.webapp.json`, `TS_ChannelView-*.png` | what lets a tablet install the page as an app, and its icons. Go in `reaper_www_root/` (Pro) |
| `dev/TS_CV_Test.lua` | offline tests — see `dev/NOTES.md`. Not installed |
| `dev/NOTES.md` | developer notes: how parts of it work and the pitfalls behind them. Not installed |
| `TS_CV_Diag.lua` | dumps what REAPER reports about the selected track's FX, and how much of your plugin collection the FX index resolves |
| `dev/TS_CV_Audit.py` | checks every ImGui call against your installed ReaImGui. Not installed |
| `TS_ChannelView_Mappings.ini` | your layouts (created on first save) |
| `TS_ChannelView_Recipes.ini` | your knob recipes (created when you save one) |

The layout library is plain text and safe to edit by hand; *Layouts ▸ Reload
library from disk* picks up changes without restarting. Every save keeps one
generation of backup as `TS_ChannelView_Mappings.bak.ini`.

### Sharing layouts

*Layouts ▸ Export layouts to file…* lists your saved layouts — the ones for
the selected track's plugins already ticked — and writes the ones you tick
to a file you name. Send it to someone, and they use *Layouts ▸ Import
layouts from file…*: it lists what's in the file, marked *new*, *replaces
yours* or *same as yours*, and brings in the ones they tick. New ones start
ticked; ones that would replace a layout you already have start unticked,
and importing them asks first. A layout you've locked here isn't replaced
(it shows as *yours is locked*) until you unlock it. The library as it was
is kept as the `.bak`. The file is an ordinary layout library, so a whole
`TS_ChannelView_Mappings.ini` imports too.

## On a tablet: the web companion (Pro)

`TS_ChannelView.html` puts ChannelView in a browser — built for an iPad in
landscape beside the desk, and fine in any modern browser. It shows the
selected track as ChannelView does (your layouts, styles and faceplates),
with the transport, macro buttons, sends and receives, the ReaEQ and
ReaComp canvases, gain-reduction traces, a mixer and a session navigator.

Two pieces, both installed by ReaPack with ChannelView:

| | |
|---|---|
| `TS_ChannelView.html` | the page. Lives in `REAPER/reaper_www_root/`, where REAPER's web interface serves it (with `TS_ChannelView.webapp.json` and its icons, for installing it as an app) |
| `TS_ChannelView_Web.lua` | the bridge: a background script that publishes the selected track's chain and applies what the page sends back. Runs whether or not ChannelView's window is open |

### Setting it up

1. **Turn on REAPER's web interface.** *Options ▸ Preferences ▸
   Control/OSC/web ▸ Add*, and choose **Web browser interface**. Pick a port
   (8080 is usual) and set a username and password under access control:
   anyone on your network who can reach that port can drive REAPER. The
   dialog shows the address REAPER is listening on.
2. **Start the bridge.** *Actions ▸ Show action list*, run
   **Script: TS_ChannelView_Web.lua**. It keeps running in the background
   (the action shows as on); run it again to stop it. To start it with
   REAPER, tick ChannelView's *☰ ▸ Web companion ▸ Start it with REAPER*, or
   run the **TS_ChannelView_Web_Startup** action. While it runs, a
   thin strip along the top of ChannelView's header shows it: green with a
   page connected, fainter green with none, amber when a page is open but
   the bridge isn't running. *☰ ▸ Web companion* starts and stops it.
3. **Open the page on the tablet**, on the same network:
   `http://<your computer's address>:8080/TS_ChannelView.html`. If Windows
   asks whether REAPER may accept connections on private networks, allow it.
4. **On an iPad**, *Share ▸ Add to Home Screen* opens it full-screen, like
   an app.
5. **On Android** (a Galaxy Tab, say), the full-screen button (four corner
   marks) at the right of the transport bar makes the page full screen — no
   address bar, no status bar. It remembers: a page left full screen goes
   full screen again at the first tap after it's opened (browsers only
   allow it from a tap).

### As an app on Android

Chrome can install the page as an app that always opens full screen, with
its own icon. It only installs from secure addresses, and REAPER's web
interface is plain `http`, so Chrome has to be told to trust this one
address, once:

1. In Chrome on the tablet, open `chrome://flags`, find **Insecure origins
   treated as secure**, enable it, and enter the page's address without the
   page name — e.g. `http://192.168.1.20:8080`.
2. Relaunch Chrome, open the page, and choose **⋮ ▸ Install app** (or *Add
   to home screen ▸ Install*).

The app is tied to that address, so give the computer a fixed address on
your network (a DHCP reservation in your router), or the app will lose it.

Installing by hand instead of with ReaPack: copy `TS_ChannelView.html`,
`TS_ChannelView.webapp.json` and the three `TS_ChannelView-*.png` icons into
`REAPER/reaper_www_root/` and `TS_ChannelView_Web.lua` into
`REAPER/Scripts/TS_ChannelView/` beside the other modules, then load the
script into the action list.

### What needs what

- Gain-reduction meters and traces need **TS_TrackProbe** on the track, as
  on the desktop.
- The spectrum behind the ReaEQ canvas comes from **Track Analyser** while
  it's running. Without it the canvas has no backdrop.
- Choices made on the page — collapsed panels, open traces and their
  windows, the mixer's height, whether the navigator and Actions bar show,
  which Macros and Modulators panels are open — are kept by the browser,
  so a tablet and a laptop can differ. Action buttons are stored in
  REAPER, so every device shares one set.

### Using it

- **Plugins:** knobs drag up and down; double-tap for the default. ⋯ on a
  header inserts, moves, opens or removes a plugin, sets its routing (in
  series or parallel), puts it in a new container. Press and hold a header,
  then drag, to reorder — into and out of containers, as on the desktop.
  Tap a container's square for its options. The dashed + adds to the end
  of the chain, and the chevron collapses a panel on this device.
  Oversampling is in the preset bar (or ⋯), a container's options, and
  **OS** under the fader for the whole chain; lit while it's on. ⋯ also
  sets a plugin offline or brings it back.
- **Show:** the button with the columns icon, beside the Actions button,
  shows or hides the macros, modulators, sends and receives on this
  device.
- **Looks:** finishes, corners, switches, knob recipes, your own knob
  looks and concentric pairs draw as on the desktop, lit and shadowed to
  the desktop's Lighting and Shadows.
- **XY pads and concentric knobs** play here too: touch the pad to put the
  dot there; on a concentric knob, start on the inner knob or the ring.
  Modulated controls carry the same marks as on the desktop.
- **ReaEQ:** drag a node for frequency and gain, double-tap empty space to
  add a band, tap a node to select it and set its type and Q underneath.
- **ReaComp:** the same canvas as on the desktop — drag the threshold line,
  the knee grips, the curve's end for ratio and the envelope's nodes; tap
  the Detector tab for the drawer.
- **Canvas layouts** of other plugins show their canvas too, with the
  layout's other controls beside it: drag an EQ node for frequency and
  gain, double-tap it to take the band out, tap it to select it for its Q,
  shape and slope underneath; drag a compressor's threshold, the curve's end for
  ratio (snapping to a switch's settings) and the envelope's nodes; the
  other kinds' handles, chips and taps work as on the desktop. They're set
  up on the desktop.
- **Pages, conditional controls and virtual controls** work as on the
  desktop: tap a tab to change page (the page is remembered per device), a
  control with a *Show when* rule comes and goes as its parameter or
  virtual control changes, and a layout switching rule switches the layout
  here too. Each plugin shows its instance's layout, as chosen on the
  desktop.
- **Wet:** in a panel's head where there's room (tap it for a slider), and
  a slider at the top of every plugin's ⋯ sheet and container's sheet.
- **Gain reduction:** tap a meter to open its trace; tap the trace for its
  window.
- **Mixer:** drag the bar labelled MIXER up (closed, half or full), or tap
  it. Press M, S or R and drag along the row to set a run of tracks at once.
  Touching one of several selected tracks moves them all, as in REAPER. Tap
  a strip's empty space to select its track; double-tap it (or its name
  button) to collapse it to a narrow strip, and again to open it.
- **Folders:** tap the folder icon on a folder's name button to step it
  full → collapsed → hidden — REAPER's own folder state, so the track panel
  follows.
- **Master:** its Sends column is its hardware Outputs; tap an output's
  channel button to move it. The Mono switch sits under M and S.
- **Fader panel:** double-tap its empty space to collapse it, and again to
  open it.
- **Navigator:** the button to the left of the Actions button. Tap to move the
  edit cursor, tap a region's name to go to it, drag the box to scroll
  REAPER's arrange view.
- **Presets:** the bar along the foot of a panel — tap the name for the
  list, ‹ › to step, + to save, save as default, rename or delete.
- **Actions:** the bar of action buttons.
  The pencil turns on editing. + adds a button for any action (searchable)
  or a spacer, tap a button to change it (its label, icon and colour),
  press and drag to move it, × removes it. Menus, toolbar switches and
  ChannelView's icons from the desktop's Organise actions show here, and
  the bar reloads when it's changed there.
- **Macros and modulators:** their panels come first in the row when the
  track has any, folded until you open them. Macros play here — knobs,
  buttons, faders, dropdowns and XY pads — and a modulator's tile opens to
  its settings. Controls they drive follow them and show their range or
  swing, as on the desktop. Adding and removing, linking, ranges, names,
  colours and lanes are done on the desktop.

## While REAPER is busy

On a long job — a plugin scan, say — REAPER keeps running scripts behind
its progress window, and ChannelView reading plugins every frame would
get in the way. It times its own frames, and when they suddenly take many times
longer than usual it shows *ChannelView is waiting while REAPER is busy…*
and stops reading plugins, trying again once a second until REAPER is
free. A machine that's simply slow never trips it: it goes by what a frame
usually costs on that machine. If frames stay slow for 15 seconds, that's
taken as what a frame costs now and it carries on, so it can never be left
waiting. The web companion backs off the same way.

## Installing

**ChannelView:** Extensions ▸ ReaPack ▸ Browse packages ▸ *TS_ChannelView*
(the TS-ReaScripts repository) ▸ Install, then run it from the Actions
list. Needs the **ReaImGui** extension (ReaPack). SWS is optional — it only
powers *Layouts ▸ Show the library file*.

**ChannelView Pro:** Extensions ▸ ReaPack ▸ Import repositories ▸ paste the
link that comes with Pro, then Browse packages ▸ *ChannelView Pro* ▸
Install, beside ChannelView. Keep the two on the same version: update them
together. For the tablet page, see *On a tablet* above.

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

A **stepped knob** (Show as ▸ *Stepped knob*) turns like a knob but lands
only on the parameter's positions — the plugin's own choices once they've
been read. It keeps count of a slow drag, so it clicks round one position
at a time; the wheel moves one position a notch.

Until a parameter has been scanned, the control steps instead: **clicking
cycles** through the positions and wraps around at the end, Shift-click goes
back. The wheel steps too but stops at each end rather than rolling over —
clicking is "give me the next one", where stopping dead looks broken, while
scrolling is a scrubbing gesture, where a silent wrap is a nasty surprise. A
small caret marks the controls that have a list.

## Run when REAPER starts

**☰ ▸ Run when REAPER starts** adds a fenced block to
`Scripts/__startup.lua` that calls this script's own action, the same way
Track Analyser does. It is careful with that file: it is the one thing
here that can break things **other than this project**, since everything
else you auto-start runs from it too. Three rules:

1. **A backup first**, every time, to `__startup.lua.bak`.
2. **The result is compiled before it is saved.** `load()` on the new
   text catches a mangled edit while it is still a string in memory. A
   startup file that doesn't parse is never written.
3. **Lines this script did not write are not touched.** Its block is
   fenced with markers and only that is ever removed. If the command id
   turns up *outside* the fence — added by hand, which is how most people
   get there first — the menu says so and leaves it alone rather than
   editing somebody else's line.

## Taking something out

A **send** carries a small **x** in its bottom-left corner, inset past the
colour bar. Only submitted while the pointer is over the cell, so it costs
nothing and hides nothing the rest of the time.

Sends only. A parameter comes off a panel from the setup dialog or its own
right-click menu; an x on every knob would be clutter buying nothing. A
send has nowhere else to be removed from, which is the whole argument for
putting one there.

## Double-click means default

Every control — knob, fader, toggle, stepped combo, channel button — goes
back to its default on a double-click:

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

## Spacer tracks in the send menu

Tracks whose name is nothing but punctuation — `--------`, `~~~~` — are
spacers people use to group a template, so the send menu shows them as a
gap rather than as somewhere you can send to. The rule is deliberately
strict: **punctuation only**. A labelled divider like `== BUSES ==` stays a
destination, because guessing wrong there hides a track you meant to send
to, which is worse than listing one you didn't.

## A bypassed plugin still answers

`GainReduction_dB` keeps reporting whatever the plugin last measured when
you bypass it. It has stopped processing, not stopped talking. Read as
is, the meter would freeze at the reduction it happened to be doing at
the moment you switched it off — a number that is not true of anything.

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

So anything beyond self-reported reduction needs probes: the measured
gain reduction and input/output meters below use a TS_TrackProbe pair,
and ChannelView only adds one when you press a button that says so. A
whole track's signal path is Track Analyser's job.

### Measured gain reduction

A plugin that doesn't report its reduction can still be *measured*. Tick
**Measure gain reduction (estimated)** in its right-click menu or in Setup
Edit Parameters. Every instance between a TS_TrackProbe pair (one at the
start of the chain, one at the end) then gets a meter, in pink rather than
the reported amber.

The probes are a small JSFX installed with ChannelView. They don't change
the audio while you play and sit idle until something reads them. The
**Probes** button in the header bar adds a pair to the selected tracks
that lack one, after asking. Inside a container is fine, so a pair baked into
a track template works as is. On a track whose first plugin is an ARA plugin
such as Melodyne, which REAPER keeps first, the first probe goes second.

The probes are kept out of the plugin row, and the **Probes** button says
what's there: dim with none (click it to add a pair), lit with a pair,
teal when this track feeds TS Visualizer's spectrum, amber when one of
the pair is missing. A track left with one probe of the pair gets the other
back when ChannelView shows it, unless the other is frozen (it comes back
with the unfreeze). With any there, clicking it opens a menu: *Add the
missing probe*; *In the Visualizer's spectrum* — *Not included*, *Before
the chain* (the pre probe) or *After the chain* (the post probe); and
*Remove the probes…*, which asks first, saying how many plugins they
measure, and takes the measuring routing out with them. ChannelView keeps
them at the ends of the chain: insert, move or remove a plugin and the pre
probe goes back to first (second behind an ARA plugin) and the post probe
to last. One dragged into a container comes back out; a pair put together
inside a container is left there.

The probe has **no parameters**: nothing of it shows in automation or
learn lists, and measuring never makes it REAPER's *last touched*
parameter. ChannelView and Track Analyser talk to it through shared
memory, and the first probe on a track is the pre, the last the post. A
project saved with probes older than TS_TrackProbe 2.0.0 keeps running
them until it's reopened, and both work with them.

Nothing is inserted next to the plugin. ChannelView routes a copy of what
goes in and what comes out on spare channels, from 5/6 up, skipping any
pair a plugin, send or receive already uses. The post probe compares the
two in ten bands. Up to four plugins per track. What was changed is written
on the track (`P_EXT:TS_CV_TAPS`) and taken out exactly when you untick it.

A plugin inside a container is measured too, however deep it sits. Each
container on the way gets the extra pins to carry the copies out. Pins are
only ever added, and the added ones are left empty when you untick. A
plugin running in parallel with another, or inside a container that does,
isn't measured, because its own output isn't what the chain passes on.

Its zero, what "no reduction" looks like, is measured each time playback
stops. The first probe plays a second of pink noise at −60 dBFS and one at
−50 through the chain while the last probe keeps the track silent. It needs
REAPER's *Run FX when stopped* (on by default). It's an estimate: a plugin
at 50% mix reads about half, and after a make-up gain change it's out until
the next stop. **Measure the zero while stopped** in Setup turns the
stop-time measurement off, for instrument tracks you play while stopped.

### Input/output meters

**Input/output meters** (right-click a plugin, or Setup) puts two slim meters
on its panel: what goes into the plugin and what comes out, from the same
probe copies. Under them is the change in level, output RMS minus input RMS.
It works for any plugin between the probes, including ones that report their
own reduction; those are tapped for their levels alone. Gain reduction and
levels together share the limit of four plugins per track. On a canvas the
two meters run down the panel's left and right edges.

### The gain-reduction trace (Pro)

**Click a gain-reduction meter** and it opens out into a trace beside it:
the plugin's own output waveform, its input faintly behind, and its
reduction drawn down from the top, the way Track Analyser draws the whole
track, for just this plugin. Click the meter again to close it.
Right-click the trace for its window: 1, 2, 4 or 8 beats (tempo-locked, so
hits land in the same place every pass) or 1, 2 or 4 seconds. Stop the
transport and the last pass stays on screen.

The trace lines itself up: about once a second it compares the plugin's
output with what went in, and its reports with the reduction that shows,
and draws each at the delay where they agree — a plugin whose meter runs
early, late or in step with its output all come out right.

The audio comes from the probes, so the track needs a TS_TrackProbe pair
(1.8.0 or newer: reopen the project after updating). A measured plugin is
already tapped; one that reports its own reduction is tapped for its levels
while its trace is open, which counts toward the four taps a track can have.
The waveform shown is one track's at a time, the selected one's. With
nothing to show, the trace says why: *needs TS_TrackProbe* (no pair on the
track), *outside the probes* (the plugin isn't between them), *in
parallel* (it is, but runs in parallel, which a tap can't measure), or
*connecting…* while the tap is being laid.

### Wet

Every panel header shows the plugin's wet %, REAPER's own wet/dry mix,
where the panel has room for it. It's dim at 100% and highlighted
otherwise. Click it for a slider. The panel menu has the same **Wet**
slider at any width, and a container's menu has the container's.

## Where this came from

Macros and modulators are **Saxmand**'s idea (Jesper Ankarfeldt's **FX
Modulator Linking**), with thanks to him for his blessing to build on it.
What ChannelView takes from it: modulators living in the track's own chain
as a plugin whose parameters drive other plugins' through REAPER's
parameter links, so the modulation is part of the project rather than of
the script; the kinds of source (macros, an XY pad, an on/off button, an
LFO, an audio follower, MIDI sources); one source driving many controls;
reaching a plugin inside a container by exposing its parameter up through
each container; and the list of synced LFO rates. Apart from that list,
none of his code or JSFX is used. What ChannelView decided against: his
separate modulator plugins in a *Modulators* container (it has one plugin
of its own, ChannelView Modulators, at the top of the chain), and any
compatibility with his script — it doesn't read, control or need setups
made with it; the two are independent. Also left out: his A/B snapshot
slider, the curve-mapped (MSEG) and 4-in-1-out modulators, the counter,
and mapping by touching a plugin's parameter.

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

The Hammertone finish is made from TextureCan's *Hammered Copper* height
map (CC0). The other finish textures are generated.

Nothing here derives from TK FX Browser, TK Workbench or any other
third-party script — I checked line by line before release.
