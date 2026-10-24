# ChannelView — changelog

## 3.1.3 — the taps leave sidechains alone

- **Plugins keep their layout when the taps need more channels.** To make
  room for the measurement taps (gain reduction, I/O meters), ChannelView
  raises the track's channel count. Many VST3s follow that count:
  Pro-C 3 and Pro-Q 4 are stereo on a 2-channel track and 9.1.6 on 16.
  So they changed layout, REAPER wired every pin afresh, and a sidechain
  routed to them stopped arriving (their sidechain pins moved up past the
  new main inputs). Now each plugin that follows the count is held at the
  count the track had before the taps (Plug-in bus size in its pin
  connector), and so is one added later; its pins stay as they were.
  Removing the probes puts the channel count back and lets them follow it
  again, unless something else on the track now uses the channels above.
- **A send or receive routed onto the taps' channels** moves the taps to
  free channels, so it doesn't mix into the copies.
- A plugin that already changed layout before this update keeps its
  wiring: set its Plug-in bus size and sidechain pins back once by hand.
- ChannelView Pro moves to 3.1.3 with it, unchanged.

## 3.1.2 — the web companion's layouts

- **ChannelView Pro: the web companion reads your layouts.** Installed
  from ReaPack, it looked for them in Pro's own folder rather than
  ChannelView's, so the page showed default layouts, and it took out
  the measurement taps ChannelView put in for a plugin's I/O meters or
  gain reduction: the meters flickered and the undo history filled with
  "route" and "remove measurement taps". ChannelView itself is
  unchanged; it moves to 3.1.2 with Pro. Update both.

## 3.1.1 — Import fixed

- **Organise actions ▸ Import…** shows its list of bars again after you
  pick a file (3.1.0 opened the file picker and then nothing). ChannelView
  Pro moves to 3.1.1 with it, unchanged: update both.

## 3.1.0 — bypass modulation, smart folders

Update ChannelView and ChannelView Pro together.

### ChannelView

- **Bypass modulation, to compare.** The Modulators panel has a power
  button in its header for all of them and one on each modulator: held,
  each control a modulator drives sits where it's set, so you hear the
  track without the movement. Macros carry on. The rack's strips have
  the same buttons. *TS_ChannelView_BypassModulation* is an action for a
  key or a toolbar button (lit while the selected track's modulators are
  bypassed); it works with ChannelView closed. They're parameters of the
  track's ChannelView Modulators plugin, so they can be automated or
  mapped. Reopen a project you had open while updating for the buttons
  to appear.
- **Smart folders.** An FX folder that's a smart folder (a search saved
  in REAPER's FX browser) now lists the plugins its search matches, in
  the + menu and the picker. *Save as a smart folder…* at the foot of
  the quick-search menu, or beside the count in the search dialog, saves
  your search as one; *Change its search…* in its submenu or right-click
  edits it, with the plugins it matches listed as you type. REAPER's own
  browser shows a new one after a restart.
- **FX folders** are named and ordered as REAPER's FX browser has them
  (a folder could show another's name).
- **Large submenus** (it was *Large items*, and had no effect): a menu's
  submenus are drawn as the bar's buttons, the same height, background
  and border.
- **ChannelView and Pro at different versions:** ChannelView says which
  one to update, once, and on a button in its header until they match
  (Pro is off meanwhile). The tooltip on Pro's greyed menu items says the
  same.
- **Organise actions ▸ Export…** opens its list of bars (it did nothing).
- **The probes leave a sidechain alone.** A new probe's spare inputs (for
  the gain-reduction taps) start unplugged, so the pin connector no
  longer shows it on 3/4. And a plugin you've routed onto the channels
  the taps use keeps its routing: the taps move to free channels
  instead.

### ChannelView Pro

- **ReaGate and ReaLimit start with canvases** (Set up the canvas…
  changes them, as for any other). ReaGate's draws its pre-open before
  the attack, has its RMS time as a slider under the envelope, and its
  detector filters in a panel along the foot, drawn as a delay's are:
  drag the high-pass and low-pass, and the headphones button lets you
  hear what the detector hears. ReaLimit's has *True peak*, *Constant
  gain* and *Low latency* as buttons above its release (they're kept in
  ReaLimit's own settings, not as parameters).
- **The Rack and the web companion** won't start with ChannelView at
  another version: they say which one to update.
- **A gate's close line** is taken by its grip, in the middle, so the
  threshold's line can always be taken anywhere else.
- **The web page:** frozen plugins show where they were, as ice strips;
  tap one to unfreeze. The ❄ beside OS under the fader freezes the
  track, or up to one of its plugins, or unfreezes it. The Modulators
  panel has the bypass buttons too.

## 3.0.0 — ChannelView Pro, grid layouts

ChannelView now comes in two parts. **ChannelView** stays free and on
ReaPack. **ChannelView Pro** is an add-on, installed from its own ReaPack
link beside it; the two must be the same version. Pro has grid layouts and
the grid editor, the rack, the web companion, the canvases (EQ, compressor
and the rest, ReaEQ's and ReaComp's), knob and button styles and colours,
faceplates, finishes, sections and backgrounds, lighting and shadows, the
plugin's own colours, vendor looks, more than one layout per plugin and
switching between them, Show when rules and virtual controls, the TS_CV
Trimmer and the gain-reduction trace. The README marks them **(Pro)**.

### ChannelView

- **Layouts made with Pro work here.** A grid is drawn as it is, Show
  rules and virtual controls work, and nothing Pro keeps in a layout is
  lost when it's saved. Knobs show as the default Arc and buttons flat, so
  a layout styled in 2.x looks plain until Pro is installed, when its
  looks come back.
- **Pro's menu items** are shown greyed and marked (Pro).
- **The Control flow menu is gone.** A panel's controls flow down then
  across (in Pro's rack, across then down).

### ChannelView Pro

- **Grid layouts.** A layout can be a grid: every control has a place of
  its own, in quarter cells (an ordinary knob is 4 × 4), and ChannelView,
  the rack and the web page all show it as it is. Where it doesn't fit, it
  flows a section at a time, or, locked (the default), scrolls. Sections
  are groups: a rectangle round some controls with a fill, an outline, or
  both, each in any colour. Lines run from any corner of the grid to any
  other, in any colour. Empty space is the gap.
- **The grid editor** (*Edit layout…*, from the panel's menu or a control's
  right-click), in a window of its own, takes the place of Edit
  parameters. Drag parameters, lines, sections and virtual controls onto
  the grid; drag to move, the corner to resize (a control's size and a
  fader's length come from what you draw); insert and delete rows and
  columns. Everything about what's selected is on the right: settings,
  style, background, Show when, and for the panel, lock, meters, faceplate
  and layout switching. Select several (Ctrl/Shift+click, a box, Select
  all) to move, align, distribute, copy, paste or change them together.
  *In ChannelView* and *In the rack* preview the panel at a height or
  width you choose, at the rack's real width to start with, and say when
  the rack shows another of the plugin's layouts. *New layout…* makes a
  copy, an empty one or one with a canvas. Every change is saved as you
  make it, with Undo and Redo. A layout that isn't a grid becomes one as
  it opens, arranged as it was.
- **Canvas layouts:** the controls beside the canvas are a grid too, and
  the canvas has its own width in ChannelView and height in the rack.

## 2.6.2 — rack layouts

- **Rack: rows.** A plugin in the rack takes the fewest rows that fit
  across the column, and never fewer than its tallest control needs (a
  fader's length, a large knob; an upright fader at least two), so faders
  and large knobs keep their size. A layout ChannelView shows too, in a
  rack running down then across, keeps at least the rows it fills in
  ChannelView's window, so it's arranged as it is there. A locked layout
  keeps its own rows.
- **Rack: the gain-reduction meter on short panels.** On a panel under
  three rows tall it lies across the top, 0 dB at the right and the bar
  growing left as it pulls down, with no trace. On taller panels it stands
  at the side as in ChannelView.
- **Rack: its own Control flow.** View ▸ *Control flow* in the rack is
  separate from ChannelView's, starting from it until you change it.

## 2.6.1 — rocker colours, bar backgrounds, large menus

- **Pill rockers in colour.** A Pill rocker's colour swatches set the
  colour of its cap (it doesn't light); with none it stays black. The web
  page shows it too.
- **A background for a bar in its own window**, docked or floating: its
  right-click ▸ *Background*, or in Organise actions — the theme's, a
  faceplate colour or any colour at all.
- **Large menu items.** A menu button on a bar can open with the taller
  rows of ChannelView's own header menus: its right-click ▸ *Large items*,
  or in Organise actions.
- **EQ learning: a shelf that doesn't say which end it's at.** Bands whose
  Shape switch just says *Shelf* (or *Cut*, *Pass*, *Filter*) are each
  learned on their own, so a high band's shelf is a high shelf. Learn such
  an EQ again (Set up this layout ▸ Learn again).

## 2.6.0 — auto-float, rack lock, value arcs, plugin colours

- **Float plugins without controls.** View ▸ *Float plugins without
  controls* (the rack has its own): a plugin whose layout has no controls
  (an instrument you'd rather play from its own window, say) has its window
  floated when ChannelView moves to its track, and closed again at the
  next track change unless you pin it (the pin in its panel's header). It
  never closes a window you opened yourself. Its empty panel reads
  *auto float*.
- **Rack: lock to a track.** The padlock in front of the track's name keeps
  the rack on that track whatever's selected; click it again to follow the
  selection. Kept with the project.
- **Value arc on any knob.** Style ▸ *Value arc*: *Positive*, *Negative* or
  *Centred*, a lit arc round the knob in place of its ticks or dots, in the
  theme's fill colour; for one knob, its section or the whole panel.
  *Centred* also makes the knob centred, so a knob's *Centred fill* is now
  here (faders keep theirs in the Control menu). The web page shows it too.
- **The look new controls start with.** Style ▸ *Use this look for new
  knobs* (or *buttons*): new layouts, automatic layouts and controls added
  in the editor start with that knob's style, colours and value arc, or
  that button's style and lit colour. *Forget the look for new …* goes back
  to the plain ones.
- **The plugin's own colours** (Windows, with js_ReaScriptAPI). Every
  colour menu has a *From the plugin* row: its eyedropper reads the
  plugin's window and keeps its main colours and accents with the layout.
  **Faceplate ▸ Match the plugin** colours the whole panel from them.
- **Raised dropdowns.** Style ▸ *Raised* stands a dropdown off the
  faceplate as a dark cap, like an unlit *Backlit* button.
- **A plugin button's own vendor look.** A plugin button on a bar can
  choose its own look over its vendor's (right-click ▸ *Vendor look*, or
  in Organise actions), or *No vendor look* at all.
- **FX chains can replace the plugins.** An FX chain button's *When
  clicked* (its right-click, or in Organise actions): *Add it*, *Replace
  the plugins* or *Ask each time* (a menu at the button; a sheet on the web
  page). Replacing, here and with the header's *Replace the existing FX*,
  keeps the probes, Trimmer and ChannelView Modulators, puts the chain
  where the plugins were, and leaves the track alone if the chain won't
  load.
- **EQ learning that wasn't measured right is caught.** A learn whose
  measurements come back as noise rather than the band (Pro-Q 4, for one)
  no longer bends the canvas: a plugin that reports its own values is
  drawn from them, and any other EQ keeps what it had learned before.
  Learning also follows a plugin whose latency changes as it runs. Learn
  an EQ again if its curves look wrong.

## 2.5.6 — knob grooves, skirts

- **Grooves are cut out of the knob.** A grooved knob (*Console*, or your
  own looks with Grooves) has square-cut grooves out of its edge with the
  panel showing through, rather than dark bars drawn over its side.
- **No more tilt.** Knobs are all drawn straight from above, as
  everything else is: *Console* and *Wing* are no longer tilted, and the
  Knob look window's Tilt is gone (a saved look's tilt is ignored).
- **Printed skirt ticks turn with the knob.**
- The *Numbered skirt* recipe and skirt are gone (they had no room for
  their numbers on a panel); a knob or look that used one is drawn with a
  printed skirt. *Numbered dial* is now just **Dial**.

## 2.5.5 — freeze, collapse all, measured EQ shapes

- **Freeze.** The **❄** button in the header (ChannelView and the rack):
  *Freeze track*, *Freeze up to* the selected plugin, and *Unfreeze*,
  with REAPER's own freeze, in stereo. Frozen plugins stay where they
  were, as ice strips; in the rack a *frozen above* line with an Unfreeze
  button sits under them. The probes and ChannelView Modulators are never
  frozen: they stay live after the frozen plugins and go back to their
  places at any unfreeze, ChannelView's or REAPER's own.
- **Rack: Collapse all.** The double chevron in the rack's header folds
  every plugin; pressed again, it opens only the ones it folded. The
  rack's chevrons point up to fold and down to open.
- **A track left with one probe gets the other back** when ChannelView
  shows it (unless the other is frozen and comes back with the unfreeze).
- **EQ canvases draw what the plugin really does.** Learning keeps what a
  shape does beyond its formula — a console type's long tail, a shelf's
  bump or dip, a boost shaped unlike its cut (Kirchhoff-EQ's console types,
  for one) — and the canvas and the web page draw it, smoothly, at any
  gain.
- **Model.** An EQ layout's setup can name a plugin-wide switch that
  changes every band (TDR Slick EQ's *EQ Model*); ChannelView guesses it.
  Every setting is learned, and the canvas draws the one the plugin is on.
- Bands that are alike are learned once, so a plugin with many identical
  bands learns much faster. Learn an EQ layout again to have these.
- Rack: the plugins' scrollbar sits in the window's margin, right against
  the panels.

## 2.5.1 — rack at startup, toolbar names

- **ChannelView Rack can start with REAPER**: ☰ ▸ *Run when REAPER starts*
  in the rack, separate from ChannelView's own.
- **A toolbar in its own window shows its name** at the start of its row
  (or over its column), as a drawer does: a docker doesn't always show
  the window's title. Right-click the name for the bar's menu.
- Fixed: a toolbar window sized a little short showed nothing and had no
  right-click menu. A floating toolbar window now keeps room for a row of
  its buttons.

## 2.5.0 — hardware looks, Rack view, EQ band shapes

- **Finishes.** A faceplate, a section or a control's background can have
  a surface: *Brushed*, *Anodised*, *Bright*, *Satin*, *Tolex*, *Leather*,
  *Wood*, *Crinkle*, *Enamel*, *Hammertone* or *Checker plate*, in the
  surface's own colour, with the *Metallic flake* over any of them.
  Desktop and web.
- **Corners.** Sections and backgrounds can be *Square*, *Soft* or
  *Round*.
- **Switches.** A toggle can be a bat or paddle toggle, a pill or lit
  rocker, a slide or pill slider, a lamp or round button, a jewel lamp or
  a guarded toggle, lit in its colour. With the 3D effect off they take
  the theme's flat look.
- **Knob recipes.** Seventeen new knob styles built from parts: Bakelite,
  Machined, Red gloss, Chicken-head, Numbered skirt, Printed skirt,
  Soft-touch, Chrome, Two-tone, Cream fluted, Coin edge, Washer, Console,
  White rim, Numbered dial, British and Wing. The Style menu shows every
  style as a picture.
- **Your own knobs.** Style ▸ *Customise…* opens the *Knob look* window:
  body, grip, top, pointer, material, colours, tilt, skirt and its print,
  washer, nut, inner cap, scale and shadow, from any recipe. Apply it to a
  knob, a section or the panel, or save it as a recipe of your own.
- **Concentric knobs** are relit, can be *Arc (flat)*, or any recipe for
  the outer knob with another for the inner, each customisable.
- **One light, and shadows.** Everything is lit from the top left and
  casts a soft shadow that grows with its size. **View ▸ Lighting** and
  **View ▸ Shadows** set how strong. A knob's own shadow can be *None*
  (flush) or *Tall*. Flat buttons and dropdowns cast none.
- **Rack view** (*ChannelView Rack*): the selected track's plugins down a
  column, in a window of its own to dock beside the arrange. Every panel
  is the column's width; a canvas spans it, with its other controls under
  it. Macros, modulators, sends and receives are strips pinned top and
  foot. Container brackets, its own folding, its own action bars, and its
  own layout choice per plugin, falling back to ChannelView's.
- **Show or hide** the Macros, Modulators, Sends and Receives panels (View
  menu; on the web page, the new Show button).
- **EQ canvas band shapes.** Notch, band pass, tilt shelf, flat tilt, flat
  top, sword and all pass bands; cuts at any slope up to 96 dB/oct and
  brickwall. A plugin's own shape names and slope control are read live
  (Pro-Q, Kirchhoff-EQ and its console types). Shape switches of up to 64
  settings can be learned. Web too, with a slope picker.
- **Two ChannelView windows** (ChannelView and the rack) share layout and
  label edits as they're made.
- **Vendors** (Organise actions ▸ *Vendors…*): a colour, initials and a
  look per plugin developer, which every plugin button of theirs picks
  up: *Colour only*, *Initials tile*, *Colour fill* or *Prefix*. *Scan
  plugins*, *Set up all* and *Same as…*. A button's own colour or PNG icon
  still wins. Desktop and web.
- **Any colour** for an action button: **…** beside its swatches opens
  ChannelView's colour dialog.
- **Developers are REAPER's**: the add-plugin menus' *Developers* list
  exactly what REAPER's FX browser does.
- Fixed: a plugin that takes the track's channel count (many VST3s) could
  write over the gain-reduction measuring copies when added, and the GR
  meters after it read nothing.
- Fixed: the selected plugin's outline was partly hidden under its
  panel's header and foot.
- Fixed: a dynamic EQ's DYN button, and band on/off switches, that read
  *Enabled* / *Disabled* (Kirchhoff-EQ) always showed as on. *Not
  Bypassed* and *Bypassed* now read the right way round.
- Fixed: *Measure threshold* (and learning a reverb's decay or a
  saturation curve) turned a *Dry Mix* control fully dry, so the plugin
  passed the test tone untouched. A mix that turns out to work the other
  way round is tried both ways.
- After updating, restart ChannelView, ChannelView toolbars and the web
  companion.

## 2.4.0 — the Trimmer, plugin buttons

- **The Trimmer** (`TS_CV_Trimmer.jsfx`): ChannelView's own plugin for the
  top of a chain, with its own panel. Two VU meters (sine-calibrated, 0 VU
  reference and peak ceiling on their right-click, *Set as default*), a
  trim per channel (±24 dB, linkable), and a low cut and a high cut at 6
  to 48 dB/oct, each off at the end of its range, drawn over the spectrum
  or as two knobs. **Auto** sets the trim from the track's items (average
  on 0 VU, peaks under the ceiling, the loudest item deciding, the items
  untouched); **Listen** sets it from what's playing. One click on the
  header's Trimmer button puts it first in the chain; two new actions add
  it to, or auto-trim, the selected tracks. Zero latency.
- **Plugin and FX chain buttons** on the action bars: one click adds a
  plugin or a chain to the selected tracks, after the plugin selected in
  ChannelView (the panel last clicked, now outlined), without an Insert FX
  action. *+ Plugin* and *+ FX chain* in Organise actions; pick several at
  once. Lit while the track has it; an icon for its type. Web page too.
- **A colour style per button**: *Underline* and *Colour the icon* under a
  button's colour, over the bar's own setting. Desktop and web.
- **Menus show icons and colours**: each row's icon, and its colour as a
  strip down the row's edge. The web page's submenu rows show theirs.

## 2.3.2 — Insert FX with the TCP

- Fixed: with ChannelView TCP running, REAPER's *Insert FX* actions (from
  the Action List, a toolbar or a script) did nothing after a track was
  selected in it. Selecting a track there now makes the tracks REAPER's
  context, as a click in REAPER's own track panel does, so those actions
  go to the selected tracks. As in REAPER's panel, Delete then removes
  the selected tracks.

## 2.3.1 — aligned and coloured action bars

- **Alignment.** Each bar's buttons can sit left, centre or right, and
  top, centre or bottom (a bar's right-click ▸ *Show*, or Organise
  actions). Rows that wrap are aligned one by one. The web's Actions bar
  follows the across setting.
- **Colours.** Any button can have a colour (right-click ▸ *Colour*, or
  Organise actions), from the same set as the web page, now with purple
  and a *no colour* swatch. Each bar shows them as **underlines** (the
  default) or **coloured icons**: the icon and label in the colour,
  filling with it while on. A button with your own PNG icon keeps the
  underline. The web page shows both.
- **Add a PNG…** in the icon picker's *Your PNGs* tab copies an image
  from anywhere into `Data/toolbar_icons` and puts it on the button.
- Fixed: browsing a large folder of PNG icons filled the console with
  *ImGui_Attach: exceeded maximum object attachment limit*.

## 2.3.0 — action bars anywhere, ChannelView's own icons

- **Action bars.** Rows or columns of buttons for any REAPER action, built
  in one place and shown where you put them: drawers along the top, left,
  right or bottom of ChannelView's window, bars in windows of their own
  (floating or docked; the new **ChannelView toolbars** script draws them,
  started for you), the TCP window's two toolbars, the web companion's
  Actions bar, or nowhere for now. Global, not per project.
- **Menus** on any bar, nested as deep as you like; the web page shows the
  menus made on the desktop.
- **Toolbar switches**: a button that swaps another bar into this bar's
  place (lit while it's showing, so a row of them works as tabs), or a
  menu of every bar. On the TCP's bars and the web page too.
- **Organise actions**: one window for every bar — drag to reorder and
  into menus, labels, icons, places, sizes, copying between bars, REAPER
  toolbars and menus imported. Also an action of its own, and it edits the
  web companion's list. **Import / export** bars to a file.
- **ChannelView's own icons**, nearly 300, drawn sharp at any size in the
  bars' colours: REAPER's main toolbar, transport, editing, markers and
  regions, markers 1–16, fixed lanes and comping, zoom, the View menu, SWS
  windows, ChannelView's scripts, instruments and effect types. Buttons get
  the icon made for their action without being asked (copied REAPER
  toolbars too); *Use ChannelView icons* does a whole bar. The web page
  draws the same icons and can pick them.
- **Bar sizes**: Small, Normal, Large or Extra large, per bar.
- **Virtual controls run actions**: each setting of a virtual control can
  run a REAPER action, from the panel or the web page.
- The TCP's settings menu loses *Add toolbar action* and *Add bottom
  toolbar action* (a bar's own right-click does it).
- Curves on the EQ and the other canvases are drawn in one go: thick
  curves join cleanly, and busy panels do less work.
- Code comments tidied throughout, and the README is now the user guide
  only (the developer notes are in `dev/NOTES.md`).

## 2.2.0 — MIDI learn, modulators moved by macros, a quieter probe

**Reopen your projects after updating.** The probe and the Modulators
plugin both changed, and REAPER keeps running the versions a project was
opened with until it's reopened. Everything still works meanwhile.

- **MIDI learn bar.** The new MIDI button in the header opens a bar with
  the parameter you last touched (in ChannelView or a plugin's own window)
  beside the MIDI control you last moved, and a link button between them:
  hollow blue when not linked, green when linked, click again to unlink.
  It writes REAPER's own MIDI learn, so links show in REAPER's learn window
  and work without ChannelView. Takes CCs, notes (footswitches), program
  change and pitch bend; guesses the mode (Relative 1 for endless
  encoders, Absolute for knobs, Toggle for notes) and lets you change it;
  *Only when its track is selected* and *Soft takeover*. A **+** shows the
  parameter's automation lane, *More…* opens REAPER's learn window, and a
  control's right-click ▸ *Automate* ▸ *MIDI learn…* opens the bar on it.
- **Modulators moved by macros and modulators.** Drag a macro's or a
  modulator's ◯ onto a knob in an open modulator tile: LFO depth, rate,
  phase and smoothing; Follower depth, attack, release, floor, ceiling and
  smoothing; MIDI depth, low, high and smoothing. Up to two per modulator.
  They behave like linked plugin controls: the knob follows, a ring with
  a handle at each end shows the reach, Alt-click a handle to remove it.
- **Button and dropdown macros drive switches**: LFO shape, sync or free,
  Follower source and gate, MIDI hold. A dropdown dropped on a switch
  offers to take its choices (a dropdown on *Shape* becomes Sine,
  Triangle, …). Right-click the switch to set what each choice picks or
  to remove the link. The tile shows the setting in use.
- **Header.** *View* and *Layouts* moved into one **☰** menu, with *Web
  companion* (start, stop, start with REAPER), *Dock* and *Run when REAPER
  starts*. The buttons sit in two groups. The web companion's status is a
  thin strip along the top of the header (green with a page connected,
  amber when a page is open but the bridge isn't running) instead of the
  tablet icon. The header glows red while the whole FX chain is bypassed.
- **TS_TrackProbe 2.0.0 has no parameters.** Measuring made a probe
  setting REAPER's *last touched* parameter, so REAPER's own learn and
  lane tools picked up the probe instead of your plugin. The probe now
  talks to ChannelView, Track Analyser and TS Visualizer through shared
  memory only, and never shows in automation or learn lists. The first
  probe on a track is the pre, the last the post. Older probes keep
  working until the project is reopened. A track's *In the Visualizer's
  spectrum* choice made on an older probe needs making again afterwards.
- The probes are always kept out of the plugin row and at the chain's ends;
  the *Show the probes in the plugin row* and *Open the pre/post probe*
  menu items are gone.
- **Track-colour backgrounds** in the mixer, the TCP and the Channel panel
  now tint the knobs, faders, buttons and labels to match, instead of
  leaving them grey on colour.
- **EQ layouts:** a plugin whose gain reads without a unit (TDR Slick EQ)
  now shows its boosts; switched Q (Narrow / Wide on analogue emulations)
  steps one position per wheel notch, and a node's right-click lists the
  positions, on the web companion too. Re-learning a layout keeps boosts
  that were dropped before.
- The modulator trace is drawn against time, so a smooth LFO draws smooth.
- Tooltips throughout are shorter.

## 2.1.1 — fixes

- An EQ layout whose band had its Q learned on one side only (cuts, say)
  stopped ChannelView as soon as the band was boosted. It now uses the
  other side's shape.
- A ReaDelay tap turned up past 0 dB drew its dot above the delay canvas,
  over the panel's header, where it couldn't be dragged back down. The
  canvas now makes room up to +6 dB when anything goes over 0 dB (faint
  lines mark 0 dB), and no dot is drawn off the canvas. On the web
  companion too.

## 2.1.0 — canvas layouts for any plugin

2.0.5 was never released; everything in it is here.

- **Canvas layouts for any plugin.** *Layout* ▸ *New canvas layout* ▸ EQ,
  Compressor, Multiband, Gate, Limiter, De-esser, Saturation, Delay,
  Reverb, Modulation or Envelope. Name the plugin's controls for each role
  (or *Guess from names*); the rest of its controls sit beside the canvas,
  carried over from the layout it was made from, faceplate and looks
  included. Canvases draw what they measure rather than print it.
  - **EQ:** up to 8 bands, each band's shape learned from a hidden copy of
    the plugin (every switch position, boost and cut, each shape and the
    Q). Drag a node, wheel for Q, double-click to take a band out,
    right-click or Alt+wheel for its shape. Optional **dynamic EQ** bands:
    their reach, a range node to drag, and the picked band's level against
    its threshold. Needs *Run FX when stopped* on.
  - **Compressor:** threshold (or input), ratio, knee, attack, hold,
    release, make-up and mix, read from the plugin's own values; reversed
    controls; switched settings snap. **Measure threshold** finds its real
    dBFS (an SSL bus compressor's 0 dB is −22 dBFS), for 1176-style
    compressors driven by their input too, drawn as a fixed threshold with
    the input as a gain bar. Knees read 0–1, ratios under 1:1, and a live
    dot riding the curve.
  - **Gate:** open and close thresholds, range, ratio and a lamp.
    **Limiter:** level history, threshold or input gain, and the ceiling.
  - **Multiband:** up to 4 bands, shared crossovers or each band's own
    edges; per band a small curve with its level riding it and sliders for
    ratio, attack, release and gain, solo, bypass and its in-use setting
    (+ BAND); click a band for the full compressor canvas.
  - **De-esser:** its band filled as it reduces, over the spectrum, and the
    waveform.
  - **Saturation:** its curve and harmonics learned on a hidden copy, the
    music's level riding the curve, and a VU-style drive meter.
  - **Delay:** every delay as echoes on one timeline — left and right,
    sync in note values, ping-pong, stereo modes, offsets and ratios, up to
    10 taps (click one for its pan, level and feedback), and a filter
    strip.
  - **Reverb:** pre-delay, early reflections (size, diffusion, balance)
    and the tail; decay by frequency with crossovers, multipliers, tone
    tilt, shelves and cuts; style chips and freeze. **Measure decay** finds
    its time in seconds when its control doesn't say.
  - **Modulation:** a scope whose timebase follows the rate, shape chips,
    and up to three voices with their pans. **Envelope:** the ADSR with
    curve handles.
  - **ReaDelay and ReaVerbate** set themselves up; ReaDelay's taps are
    added and removed on the canvas.
  - On the web companion too.
- **Virtual controls.** A layout's own buttons, selectors and knobs, drawn
  in violet and kept per instance, to drive *Show when* rules and layout
  switching.
- **Layouts that switch themselves.** Rules in Edit Parameters (*use
  "Dual" when Mode is Dual*) pick the layout from a parameter or a virtual
  control; the header shows the one chosen.
- **A default layout per plugin.** *Make "<name>" the default* in the
  layout menu. The plugin's own layout is now called *Standard*.
- **Custom value ranges.** For plugins that report bare numbers (Acustica):
  right-click ▸ *Values* ▸ *Custom range* — its ends, unit and curve — and
  it reads as that everywhere. The numbers round a knob's dial are set
  there too.
- **Tidier menus.** A control's right-click is in four parts (Control,
  Look, Automate, Arrange); everything but looks is also in Edit
  Parameters, which opens at the control you clicked. New there: *Name* ▸
  label, live name and state names; *Reverse*; *Show when*. Edit
  Parameters gains *State names*. The panel menu is in three parts
  (Layout, Plugin, Chain), with *Meters* and *Reset layout* submenus.
- **Stepped knob** follows a slow drag one position at a time, and lands
  only on the plugin's own choices.
- **Factory presets** now move ChannelView's controls on plugins that don't
  tell REAPER (TDR Slick EQ).
- **VSL Synchron Player** no longer stalls the window: a plugin slow to say
  which preset it's on is asked now and then, and *waiting while REAPER is
  busy* gives up after 15 seconds of slow frames.
- **Gain-reduction trace** lines itself up with the plugin's output (a
  Weiss compressor's was drawn 169 ms late).
- **Input/output meters** now work on canvases, down the panel's edges.
- **TS_TrackProbe 1.8.0:** reads each multiband band's level; no false
  offset after a latency change or on kicks. Reopen projects after
  updating.
- **Mac and Linux:** the colour picker's eyedropper opens the system
  colour picker.
- Plugins that answer every value with their current text (Valhalla) are
  read correctly.

## 2.0.1 — hiding plugins, copying a toolbar

- **Hide plugins in one place.** A plugin taken out of its developer in
  REAPER's FX browser (*Remove from developer*) is left out of
  ChannelView's add-plugin menu and search too. One already on a track
  keeps its panel. Shell plugins such as Waves are now matched to
  REAPER's developers, categories and folders build by build.
- **TCP window toolbar.** Right-click it ▸ *Copy a REAPER toolbar* takes
  the buttons of any toolbar you've customised in REAPER. Icons are found
  in the theme's own folder as well as `Data/toolbar_icons`, and a toggle
  with an `_off` icon shows its `_on` partner while on.

## 2.0.0 — macros and modulators

- **Macros and modulators.** Two new panels between the Channel panel and
  the plugins, folded until you open them. **Macros** (up to 16) are a
  knob, an on/off button, a fader, a dropdown of 2 to 8 named choices, or
  an XY pad (two macros). **Modulators** (up to 8) are an LFO (six shapes,
  synced or free rate, phase, depth, smoothing), a Follower (the track's
  audio or its sidechain, attack, release, floor and ceiling or a gate) or
  MIDI (velocity, note, CC, pitch bend or aftertouch). Add one from the
  dashed tile at the end of each panel.
- **Linking.** Drag a macro's or modulator's ◯ onto any control, or
  right-click a control ▸ *Link to a macro or modulator*. One source drives
  as many controls as you like; XY pads and concentric knobs take one per
  parameter. A driven control follows its source and shows its reach on a
  ring or a bar: from a macro, handles for where it sits at 0% and 100%;
  from a modulator, the two ends of its swing (centred controls such as
  ±dB gains and pans swing both ways). Turn the control to move the whole
  range. Hover a source or a driven control for lines between them.
- **One plugin, automatable.** Macros and modulators run in a small plugin
  of ChannelView's own, *ChannelView Modulators*, put on the track with the
  first one you add and taken off with the last. Controls follow it through
  REAPER's own parameter links, so the track plays back the same without
  ChannelView, and every macro and modulator setting has an automation
  lane button.
- **Credit.** Macros and modulators are the idea of Saxmand's (Jesper
  Ankarfeldt's) FX Modulator Linking, with thanks for his blessing. Taken
  from it: modulators in the chain as a plugin driving others through
  REAPER's parameter links, the kinds of source, one source driving many
  controls, reaching into containers, and the synced LFO rates. Decided
  against: his modulator plugins and *Modulators* container (ChannelView has
  its own single plugin), and compatibility with his script — ChannelView
  doesn't read or need setups made with it. Not included: the A/B snapshot
  slider, the curve-mapped and 4-in-1-out modulators, modulators driving
  modulators, the counter, and mapping by touch.
- **Automation lanes everywhere.** Right-click any control ▸ *Automation
  lane* to show or hide its lane, or *Remove the lane*. Also on the Channel
  panel's fader (Volume) and pan knob (Pan) and a ReaEQ band's menu
  (Frequency / Gain / Q). REAPER switches a parameter's modulation on when
  it makes a lane, which held the control still; ChannelView now switches
  it back off.
- **Track probes out of the way.** The probes are hidden from the plugin
  row and kept at the ends of the chain as you insert, move or remove
  plugins. The header's Probes button shows what's there (lit for a pair,
  teal when the track feeds TS Visualizer's spectrum, amber when one is
  missing) and opens a menu: add the missing probe, choose which probe the
  Visualizer listens to, open either, **Remove the probes…**, or show them
  in the plugin row again.
- **TCP window: track buttons.** Settings ▸ *Track buttons* picks which of
  monitoring, record arm, mute and solo are always on every row; the
  others can still appear while they're on. Each keeps its own place, so
  they line up, and mute, solo and record arm swipe down the column as in
  the mixer. Monitoring is new here. A lane's menu has **Remove envelope**.
- **Web companion.** The Macros and Modulators panels on the tablet: play
  the macros, adjust the modulators' settings, and see driven controls
  follow with their ranges and swings. Setting things up stays on the
  desktop. The macro bar is renamed **Actions**. Restart the web companion
  after updating.

## 1.9.6 — a fix for Edit Parameters

- **Fix:** Edit Parameters could stop ChannelView with an error
  ("TrackFX_GetParamName (MediaTrack expected)") when the selected track
  changed while the dialog was open — nothing selected, or the project
  closed or switched. Selecting a different track also had it read
  parameter names from the wrong plugin. The dialog now works on the
  plugin it was opened for whatever is selected, follows it if it moves
  in the chain, and closes if its track or the plugin is deleted, putting
  back anything you had applied.

## 1.9.5 — pages, conditional controls, layouts per instance, background tint

- **Pages.** A **Page** break in a plugin's layout (the editor's *Page*
  button, beside Gap, Half-gap and Divider) starts a new page: the panel
  shows one page at a time, with a tab strip under its header. Each tab
  has a name and a colour stripe, the theme's accent unless you give it
  one. Click a tab or roll the wheel over the strip to change page;
  right-click a tab for its colour. Dividers inside a page split its
  columns as they always have. The panel is as wide as its widest page,
  and remembers which page it's on with the project.
- **Show when.** Any control can be shown only while another parameter
  of the plugin reads a given way: *is*, *is not*, *is above*, *is below*
  or *is between*, in the plugin's own values (a switch's or dropdown's
  choices, a knob's readout). A hidden control takes no room, so two
  controls side by side with opposite rules swap in one place — a delay's
  sync switch swapping its note knob for its ms knob. Set it in the
  editor's *Show when* row; conditional controls are marked ◐ in the
  panel list.
- **More than one layout per plugin.** The panel menu's **Layout** (at
  the top) picks which layout this instance shows: *Default*, shared by
  every instance not set to another, or any you've made. Type a name and
  **Copy to new layout** copies the one you're on, or **New empty layout**
  starts with no controls (your names for the plugin's parameters come
  with it); *Delete layout…* removes one, and instances using it go back
  to the default. Each instance's choice is kept with the project — a
  Kontakt with a piano on one track and strings on another. Edit
  Parameters has the same at the top of its window, and says which layout
  you're editing.
- **Background tint.** The mixer strip, the track's name button and the
  Channel panel can take a share of the track's colour. Set a strength per
  group in the fader menu ▸ *Group looks* ▸ *Background* (folder parent,
  VCA leader, FX return, Default) — say 60% for folder parents and 15% for
  the rest — or per track with the fader menu's own *Background* slider
  (*As group* goes back to its group's). Off by default. Readouts stay
  readable: a light colour is held back so the text on it still shows. The
  TCP window follows (its View menu ▸ *Background tint* turns that off).
- **While REAPER is busy.** On a long job such as a plugin scan, REAPER
  keeps running scripts, and ChannelView's reading of plugins every frame
  got in the way of it. It now notices when its frames suddenly take far
  longer than usual, shows *waiting while REAPER is busy* and stops
  reading plugins until REAPER is free again. The web companion does the
  same.
- **The trace says why it's empty.** A gain-reduction trace with nothing
  to show says *needs TS_TrackProbe*, *outside the probes*, *in parallel*
  or *connecting…*, rather than *connecting…* for all of them.
- **Fix: a trace flickering** while the web companion was running. The
  window and the web companion each lay the probe taps, and each kept its
  own idea of which traces were open; after one changed, the other
  disagreed and they re-laid the taps in turn.
- **On the web companion** too: pages (tabs under the panel's head),
  conditional controls, each instance's layout, and the background tint.
  Restart the web companion script after updating.

## 1.9.2 — a ReaComp panel, duplicate, wet anywhere

- **ReaComp panel.** ReaComp gets a canvas of its own, as ReaEQ does. The
  transfer curve runs 1:1 up to the threshold, then at the ratio: drag the
  threshold line up or down, the grips on its edges to widen the knee (the
  line becomes a band as wide as the knee, and the corner rounds), and the
  curve's right-hand end to set the ratio (flat at the top is ∞:1). The
  dotted line is where the signal would go uncompressed. Behind it all are
  the plugin's level and its gain reduction over the last few beats, on the
  same dB scale, and a **live dot** shows where the signal is on the curve
  right now: a hit lands on the dotted line and sinks onto the curve at the
  attack speed. **Attack, release and pre-comp** are an envelope at the
  foot: drag its top node for attack, its end node for release, its start
  node back before the threshold crossing for pre-comp; **A** is auto
  release. Wet, dry and auto make-up sit beside it, the reduction and
  output meters run down the right, and the **detector** (main input or
  sidechain, RMS, its filters and preview) is in a drawer underneath. The
  level history and the dot need TS_TrackProbe on the track; the panel
  connects to it while it's open. ReaComp's *Limit output* isn't one of its
  parameters, so it isn't there.
- **Duplicate.** A plugin's menu, or a container's, ▸ *Duplicate* puts a
  copy with the same settings in the slot right after it.
- **Wet at any width.** The wet % in a panel's header only shows where the
  panel has room for it; every plugin's menu now has a **Wet** slider too.
- **Arrow keys in the quick search.** In the add-plugin menu's search box,
  Up and Down pick from the results and Enter adds the one picked, as in
  REAPER's own windows.
- **On the web companion** too: the ReaComp panel, Duplicate, and wet —
  in a panel's head where there's room, and a slider in the plugin's and
  the container's sheets. Restart the web companion script after updating.

## 1.9.1 — oversampling, offline, strip width, measuring inside containers

- **Oversampling.** REAPER's own, set from ChannelView. **OS** in a
  panel's foot oversamples that plugin; a container's menu ▸ *Oversample
  everything in it* does a container; **OS** in the header bar does the
  whole chain. The choices are REAPER's — up to 96, 192, 384 or 768 kHz —
  each with what it means at the rate you're running. While it's on, the
  switch is lit with the factor (a collapsed panel and a container's
  bracket show it too); outlined, the plugin is oversampled from around it
  or set to a rate REAPER already runs at. Also in a panel's right-click
  menu.
- **Offline.** A panel's menu ▸ *Set offline* unloads the plugin — unlike
  bypass, it frees its CPU and memory. The panel's header and foot turn
  steel blue, with *Bring online* where its controls were.
- **Strip width.** View ▸ *Strip width* sets how wide the fader panel,
  every mixer strip and the track name buttons are, from 72 to 240 px
  (112 by default). The meter grows and shrinks with it, the fader a
  little; collapsed strips keep their width.
- **A sidechain into a container.** A container passes only two channels
  in until it's widened, so a compressor inside one never hears a
  sidechain on 3/4. When that's the case its menu offers *Pass the
  sidechain into its container*.
- **Measured plugins inside containers.** Measured gain reduction and
  input/output meters now work on a plugin inside an FX container, however
  deep it sits. Each container on the way gets the extra pins to carry the
  copies out. Pins are only ever added, and the added ones are left empty
  when you untick.
- **Not while in parallel.** A plugin running in parallel with another, or
  inside a container that does, isn't measured, because its own output
  isn't what the chain passes on. Edit parameters says so.
- **Probes behind ARA plugins.** REAPER keeps an ARA plugin (Melodyne,
  VocAlign and the like) in the first slot and won't put anything in front
  of it. On such a track the **Probes** button puts the first probe second,
  behind it.
- **On the web companion** too: oversampling, offline, strip width and the
  sidechain fix. Restart the web companion script after updating.

## 1.9.0 — parallel FX and containers, new controls, FX chains and folders

**The chain**

- **Parallel FX and containers.** A bracket over the panels shows what
  runs together: parallel groups (marked `||`) and FX containers (a small
  square, in their own colour). A panel's menu ▸ **Route** sets how a plugin
  runs against the one before it — in series, in parallel, or in parallel
  with MIDI merged — and *Put in a new container* wraps it in one. Click a
  container's square to bypass it, set its routing, add a plugin into it,
  unpack it, remove it or save it as an FX chain.
- **Drag panels into and out of containers.** Drop on the left half of a
  panel to land before it, the right half after it, in its container.
  *Move left / right* and *Remove* work anywhere in the chain.
- **Parameter modulation.** Right-click a control ▸ *Parameter
  modulation…* opens REAPER's Parameter Modulation / Link window for that
  parameter. Modulated controls are marked: a dot on a knob, a corner on
  a button, dropdown or fader.
- **Save and delete FX chains** from the chain button in the header:
  *Save this track's chain as…* (into a folder of your FXChains folder if
  you like) and *Delete a chain*. A container saves on its own from its
  menu.
- **FX folders in the add-plugin menu.** REAPER's own folders: right-click
  a plugin to add it to a folder (or a new one) or take it out of one;
  right-click a folder to remove it; **[+]** at the foot of the folder list
  makes a new one.
- **Collapsed plugins stay collapsed.** A plugin you last left collapsed
  comes in collapsed when you add it to the track.

**Controls**

- **Faders of any shape.** Up or across; 2, 3 or 4 rows (columns) long or
  full length; a whole column (row) thick or half. Among the controls they
  show their name over them and the plugin's value under them — a row of
  half-width faders makes a graphic EQ's bands. New **Slim** fader style.
- **Merged cells.** A fader among the controls takes every cell it covers
  and the controls after it flow round it, in the list's order; a fader
  across runs over a divider. Existing layouts don't move.
- **XY pad**: two parameters on one pad, 2×2 to 3×3. Click or touch to put
  the dot there, Shift-drag for fine, double-click for both defaults.
- **Concentric knob**: two parameters on one knob — the ring and the inner
  knob. Where the drag starts says which turns. Each half can be reversed.
- **Copy and paste style.** Right-click a control ▸ *Copy style*, then
  *Paste style* on another — on any panel — or paste to every knob, fader
  or button in a section or on the panel. Style, colour, size (a fader's
  shape), scale, background and finish.
- **Matte knobs.** Every knob cap is matte now, like the skirted knob's
  skirt; the reverse bezel's ring is satin.
- **Buttons show the plugin's names.** A dropdown shown as buttons reads
  the plugin's own choices straight away, instead of numbers until the
  list had been opened.

**Edit parameters**

- The selected control's settings are a column beside the lists, one per
  row, showing only what its type has — the window no longer runs off to
  the right. The plugin's options sit on one line at the top.

**On the web page**

- Route in series or parallel, put in a new container, and drag into and
  out of containers; tap a container's square for its options.
- Shaped faders, XY pads and concentric knobs, all playable; modulation
  marks. Restart the web companion script after updating.

## 1.8.6 — track fader looks

- **Right-click any track fader** — the Channel panel's, a mixer strip's,
  a collapsed strip's, the TCP window's — for its **Style** (Flat, Console,
  Rail) and **Colour** (the cap colours, **[+]** for any colour with the
  eyedropper, and your recent colours). The fader shows a colour as you
  pick it. It acts on the selection when the track is part of it, as
  REAPER's own menus do, and is saved with the track in the project.
- **Group looks** in the same menu: **Folder parents**, **VCA leaders**
  and **FX returns** (tracks with receives that are neither folder parents
  nor in a folder) can each have a look, and **Default** covers every other
  track and whatever a group leaves unset. Kept with ChannelView, so they
  apply in every project. A track's own choice wins, then its group's, then
  the Default, style and colour separately; *Reset to default* takes a
  track back to its group's. A VCA leader that's also a folder parent
  counts as a VCA leader.
- A collapsed strip's see-through fader takes the colour only.
- The web page's channel strip and mixer show the same looks. Restart the
  web companion script to pick this up.

## 1.8.5 — colours of your own, lit buttons, scales, LED ring, metallic finish

**Colour**

- **Any colour, anywhere.** Faceplates, control backgrounds, sections, knob
  and fader caps, and the colour a toggle or button row lights up in can
  all be any colour now: **[+] Custom colour…** after the swatches opens
  the colour picker. The panel shows the colour as you pick it; *Apply*
  keeps it, *Cancel* puts back what was there. Labels and scales on a
  custom faceplate pick their own readable ink.
- **The colour picker** (the same one the track colour dialog uses) has the
  palettes, *REAPER's colour picker…*, and an **eyedropper** that takes the
  colour of anything on screen, inside REAPER or out: switch it on, point,
  and click — or press Enter, so the click doesn't land in another program.
  Esc puts it away. Every colour dialog has it, track colours included, in
  ChannelView and the TCP window. Needs the js_ReaScriptAPI extension.
- **Recent colours.** The colours of your own you've used since ChannelView
  started are a click away: a *Recent colours* flyout in the Faceplate,
  Background and Section menus, and a row under the cap and lit-colour
  swatches.
- **Gold** faceplate; **White**, **Brown** and **Gold** cap colours.
- **Metallic finish** on any faceplate, background or section — a fine
  metallic flake and sheen, like metallic paint — on its own or with the
  brushed finish.

**Buttons and knobs**

- **Button faces.** A toggle's or button row's Style menu now has a Style:
  *Flat* (as before), *Lit lens* (dark tinted glass that glows when on),
  *LED window* (a lamp strip across the top that lights) or *Backlit* (a
  dark cap whose edge and lettering light up), each previewed lit in the
  button's colour. *Apply to every button on this panel* copies the face
  with the colour.
- **Numbered scales.** Knobs print their values round the dial — units
  left off, thousands as k, so 12000 Hz reads 12k. That's every knob's
  default now, layouts from before included; a knob's Style ▸ **Scale**
  switches it to **0–10** or **None**, and *Numbers in cap colour* prints
  them in the knob's colour. The knob keeps its size: a number with no room
  in the cell is left out (its tick stays). A medium knob's value moves to
  its tooltip; small knobs have no numbers.
- **LED ring** knob style: a ring of lamps close round an encoder, lit up
  to the value — or out from the middle on a centred control — in its cap
  colour.

**View**

- **View ▸ 3D effect** (on by default; it replaces *Faceplate texture*):
  light from the top left — a gentle gradient on faceplates, panel edges
  that catch it, and soft shadows under knobs, buttons and fader caps (not
  the Arc knob, which is a printed scale).
- **View ▸ Use mouse wheel on controls.** Off, the wheel never turns a knob
  or moves a fader, pan or dropdown; it only scrolls. Shared with the TCP
  window.
- **Toggle mixer view** action (*TS_ChannelView_ToggleMixer*) for a
  keyboard shortcut or toolbar button — ChannelView's window never gets the
  keyboard, so the shortcut has to be REAPER's. A toolbar button for it
  lights while the mixer is showing.

**Layouts**

- **Sharing layouts.** *Layouts ▸ Export layouts to file…* writes the
  layouts you pick to a file; *Import layouts from file…* reads one,
  showing which layouts are new, which would replace yours (it asks first)
  and which are the same. Locked layouts are never replaced.
- **Sections** are no longer experimental, and neighbouring sections styled
  the same way now join into one shape across the divider between them.

**TCP window**

- **Plugin delay (PDC) under meters**, in the settings menu (off by
  default): each track's plugin delay compensation, in samples and
  milliseconds, under its meter — on tracks with any, when the row is tall
  enough.

**Fixes**

- ChannelView no longer stops with "InvisibleButton: Assertion failed" when
  its window is docked so short that the mixer has no room for its strips
  (the same goes for the TCP window).

**Web page**

- Follows all of the above: custom colours, button faces, scales, the LED
  ring, metallic finishes, the 3D effect.
- **Full screen, and installable as an app on Android:** a full-screen
  button at the right of the transport bar, and an app manifest and icons
  so Chrome can install the page (see *As an app on Android* in the
  README). Restart the web companion script to pick up this version.

## 1.8.2 — lock layout, brushed backgrounds

- **Lock layout.** A padlock at the left of every panel's foot locks that
  plugin's layout, on every track. Locked, nothing about the layout can be
  edited (the right-click menus say so, and Edit parameters stays shut), and
  the controls keep the arrangement they had when you locked it, however the
  panel is resized. A panel too short for it scrolls up and down, with a
  thin scrollbar, while its meters stay put; the wheel turns a control under
  the pointer and scrolls anywhere else. Meters aren't locked: they can
  still be switched on and off, and the trace opened. The padlock lights up
  while locked, readable on every faceplate.
- The panel's foot is now always there, for the padlock — with
  **View ▸ Preset bar** off it's an empty bar, so a panel has 20 px less
  room for controls than before with the bar off.
- **Brushed backgrounds and sections.** A control's background, or a
  section, can have a brushed finish: a *Brushed finish* tick in its
  right-click menu, or *Brushed* in the editor. Aluminium is brushed unless
  you turn it off; other colours and insets are plain unless you turn it on.
  A brushed and a plain background of the same colour stay separate shapes.
- The web page follows both: locked panels scroll there too, with the
  padlock shown, and the grain matches.

## 1.8.1 — control backgrounds

- **A background for any control.** Right-click a control ▸ **Background**
  (or the Background column in the editor): an inset, or any faceplate
  colour, drawn behind that one control over its section's.
- **Neighbours join up.** Controls side by side or above each other with
  the same background become one shape with rounded corners — an L, a
  block, a ring round a different one — outlined once round the outside.
  A background always fills the control's whole column, and two controls
  facing each other across a divider join over it. A control with no
  background shows its section's.
- **Half-gaps and gaps** can have one too (right-click the empty space), so
  they can join a shape or bridge two.
- Controls on a faceplate-coloured background take that plate's label and
  tick colours. The shapes follow every resize and reorder as it happens.
- **Values under controls** are in the small type, just under the dial or
  button, so they no longer hang off the bottom of the cell.
- The web page draws the same shapes.

## 1.8.0 — hardware looks, sizes, button rows, sections

Every existing layout looks and lays out exactly as before until you change
something: the new layout code was checked against where every control sat
in 1.7.6, in 444 desktop and 222 web snapshots.

- **New knob styles.** *Bar* (a round dome with a raised bar across it),
  *Fluted* (one domed body with finger flutes), *Bezel* (a black centre in a
  polished chrome ring), *Reverse bezel* (a glossy black ring round a
  turned-metal centre) and *Hi-fi* (a solid spun-aluminium knob in a narrow
  bevel). Pointers turn black or white to read on whatever colour the knob
  is. New cap colours **Silver** and **Stone**.
- **New faceplates.** **Stone**, **Cobalt** and **Amber**, and a
  **Brushed finish** tick in the Faceplate menu that puts a fine grain on
  any faceplate (aluminium keeps it unless you turn it off).
- **Knob sizes.** Right-click ▸ Style ▸ Size, or the editor's Size column:
  *Small* (half height — a small dial under its name in small type, the
  value in the tooltip; two stack in one cell), *Medium* (as before) and
  *Large* (half again as big). A large knob in a panel only one row tall
  draws at medium.
- **Toggle buttons.** A button now says what the state is called — your
  name for it, else the plugin's own word for it ("Thrust", "Link"), and
  ON/OFF only when the plugin just reports a number. Right-click ▸ **State
  names** to give the two states names of your own. Right-click ▸ Style
  for a **lit colour** (Amber, Green, Red, Blue, Yellow, White, or the
  theme's) and a **Small** size: a half-height lit push-button with its
  name on it.
- **Button rows.** Right-click a dropdown ▸ Show as ▸ *Buttons across* or
  *Buttons down*: one button per choice, the current one lit, like a VCA /
  FET / OPT row on hardware. For parameters with 2 to 8 choices; the lit
  colour comes from Style.
- **Sections (experimental).** A divider can put the controls after it, up
  to the next divider, on an **inset** or on a **faceplate of their own**:
  right-click any control ▸ Section, or the Section column on a divider in
  the editor.
- **Control spacing.** View ▸ Control spacing sets how wide each control's
  column is, 46 to 64 px. The default is now 50 px (it was 58), so panels
  are narrower; the setting is shared with the TCP window and the web page.
- **REAPER's own instance names.** A plugin renamed in REAPER's FX chain
  shows that name on its panel — and keeps its layout, which is still the
  plugin's. Rename from the panel menu's name box (or the web page's panel
  menu); it's REAPER's name, so the FX chain shows it too.
- **Enter commits.** Every text box takes Enter: the name boxes do what
  their button does, and the filter boxes take the first match.
- **Web page.** All of the above, plus small knobs show their name (there's
  no hovering on a touch screen) and buttons have an edge so they read as
  buttons on any faceplate.
- **Layout.** Controls are placed on a half-cell grid, which is what lets
  sizes and button rows sit beside ordinary controls. Narrower controls in
  a column with a wider one are centred in it.

## 1.7.6 — master outputs, collapsed strips, folders on the web page

- **The master's outputs.** With the master selected, the Sends panel is
  its hardware **Outputs**: one cell per output, named by your audio
  device's channels, with the level, mute and pre/post of a send. The
  middle button shows where it goes ("1/2", "5") — click it to move the
  output, or remove it; the add tile lists the device's stereo pairs and,
  under Mono, its single channels. The master has no Receives panel any
  more, here or in the track panel's pop-out.
- **Master Mono.** The master's strip has a Mono switch where other tracks
  have record arm — an open circle on red when mono, two linked circles
  when stereo — using REAPER's own *Master track: Toggle stereo/mono*.
- **Strips that line up.** Every strip, the master's included, now has the
  same three button rows, so faders and buttons sit on the same lines
  across the mixer. A collapsed strip keeps to them too: its meter and
  fader cover exactly the full strip's fader span, its level sits on the
  same line, and mute, solo and record arm (mono on the master) are
  stacked in the button rows. Its empty pan space has a **mini pan**: drag
  sideways or up and down, Shift for fine, double-click for centre; the
  value shows under it when *Values under controls* is on.
- **The master strip collapses** (its collapse button did nothing), and a
  collapsed strip's fader is plainly visible at rest rather than only on
  hover.
- **Arrows the right way round.** Collapse points left and expand points
  right, on plugin panels, mixer strips, the channel strip and the
  Sends/Receives panels.
- **CLAP presets.** Saving, *Save as default*, rename and delete now work for
  CLAP plugins as well as VST2, VST3 and JS (checked against REAPER's own
  save of FabFilter Pro-DS). AU still loads but doesn't save.

### Web page

- **Mixer:** tap anywhere on a strip that isn't a control to select its
  track. Double-tap a strip, or its name button, to collapse it to a narrow
  strip (open button, mini pan, meter and fader, level, M S R) and again to
  open it — per device. The pan readout sits centred over the meters.
- **Folders:** a folder's name button carries the folder icon; tap it to
  step the folder full → collapsed → hidden. This is REAPER's own folder
  state, so the track panel and ChannelView follow. Collapsed children are
  narrow strips; hidden ones are left out.
- **Master:** Outputs instead of Sends, no Receives, and the Mono switch.
- **Macro bar:** centred, and onto a second row when the buttons don't fit.
  *Add spacer* (in the + sheet while editing) puts a gap between buttons;
  press and drag a button or spacer to move it.
- **Fader panel:** double-tap its empty space to collapse it to a narrow
  strip, and again to open it. Plugin panels collapse with a double tap on
  their header too.
- A send's MIDI mode shows a MIDI socket; the master's colour bar no longer
  shows a stale colour REAPER left behind.


## 1.7.5 — presets, and REAPER's palettes

- **A preset bar on every panel.** Along the foot of each panel, the
  header's twin: the plugin's current preset in a dropdown in the middle,
  with previous and next either side and a **+** at the right. The
  dropdown lists your presets (★ marks the default), the plugin's factory
  presets and *Load default*. A `*` after the name means the plugin has
  changed since the preset was loaded. The **+** menu:
  - **Save preset…** — type a name, or pick one of yours to replace.
  - **Save as default…** — saves it and makes it the preset REAPER loads
    whenever the plugin is added.
  - **Rename** and **Delete** your own presets (the default follows a
    rename; deleting it asks first and says so).

  The presets are REAPER's own — the same files, the same list as the
  plugin window's preset box — written byte for byte as REAPER writes
  them. Saving works for VST2, VST3 and JS plugins; CLAP and AU load but
  don't save yet. A name too long for a narrow panel shows in full when
  you hover over it. **View ▸ Preset bar** turns it off.
- **Web page:** the same bar on every panel, with the same menu.
- **Track colours: a palette dropdown.** The *Colour…* dialog used to show
  only REAPER's 16 custom colours — the list SWS palettes load into, which
  REAPER 7.81 copied into its *User 1* palette and no longer keeps in step
  with it. It now has a dropdown with everything REAPER 7.81's picker
  offers: the project's colours, the ten built-in palettes (REAPER,
  Primary, Pride, Perceptual, Warm, Cool, Vice, Casablanca, Devon,
  Technoir) and User 1 to 4 — plus the old custom colours, for SWS. It
  opens on the palette you last chose, or else the one REAPER's picker
  last showed. **REAPER's colour picker…** opens REAPER's own, for live
  preview and editing palettes.
- **Round nose knob.** A new knob style (right-click a knob ▸ *Style*): a
  neutral grey body with a short, blunt nose that is the pointer, and the
  cap colour only in the round cap set into its centre.
- **Web companion in the header.** A small tablet appears in ChannelView's
  header while the web companion is running: an outline while no page is
  connected, filled in while one is (the tooltip says how many), amber
  when a page is open but the companion isn't running — click it to start
  it. Pages now report in about once a second for this.
- **Start the web companion with REAPER.** *View ▸ Start web companion
  with REAPER*, or the new **TS_ChannelView_Web_Startup** action (for the
  Action List or a toolbar), adds it to `__startup.lua` — with the same
  backup and checks as ChannelView's own *Run when REAPER starts*, and
  either undoes the other.
- **Renaming a control shows straight away.** Right-click ▸ *Alias* set the
  name, but most controls carried a label holding the plugin's own name
  for the parameter — every auto-filled or added control got one — and a
  label outranks an alias, so nothing changed. Those labels no longer hide
  an alias, new controls don't get one, and renaming clears the label on
  the control you renamed.
- **Dropdowns on light faceplates.** The track input box (and the new
  preset box) used dark lettering on Aluminium and Cream; they now use the
  light lettering the combo boxes got in 1.7.2.

## 1.7.2 — long search results, light faceplates

- **Search results no longer run off the screen.** Typing in the [+] menu
  could list more matches than fit below it, with no way to scroll to the
  rest — most noticeable with ChannelView docked at the bottom of the
  screen. The matches now sit in a list that scrolls after 14, and a menu
  opened in the lower half of the screen grows upward from the mouse. The
  search dialog's folder / category / developer filter scrolls too.
- **Auto-fill layout asks first.** It, *Clear layout* and *Forget saved
  layout* each replaced a saved layout — for every instance of the plugin —
  the moment they were clicked. Now, when there's a saved layout to lose,
  they ask, and say where the previous library is kept
  (`TS_ChannelView_Mappings.bak.ini`, until the next save).
- **Combo boxes on light faceplates.** On Aluminium and Cream their text was
  dark on the dark box; it now uses the same light lettering as the
  buttons.
- **Web page:** selecting the master track could stop the bridge script
  (REAPER answers nothing, not zero, for the master's record arm and
  phase). It now reads those safely.


## 1.7.1 — mixer alignment on the web page

- **Web page:** in the mixer, each fader now sits directly under its pan
  knob, with the meters and the pan value off to the right.


## 1.7.0 — the web companion, and a forgiving search

- **ChannelView on a tablet.** A web page, served by REAPER's own web
  interface, showing the selected track the way ChannelView does: your
  layouts, control styles and faceplates. Around it: the transport (drawn
  like the default theme's, with the big round play), macro buttons you set
  up on the page itself, the channel strip, sends and receives, the ReaEQ
  curve editor with the track's spectrum behind it, and gain-reduction
  traces. Add, remove and reorder plugins from the page.
- **A mixer** slides up from the bottom — drag the divider to closed, half
  or full — with pan, fader, meters, phase and monitoring, and a swipe along
  M, S or R to set a run of tracks at once. Its strips line up with the
  track buttons and scroll with them.
- **A navigator** shows the whole session: a lane per track, regions,
  markers with their names, the time selection and the playhead. Tap to move
  the edit cursor, tap a region to go to it, drag the box to scroll the
  arrange view.
- `TS_ChannelView_Web.lua` bridges the page to REAPER, whether or not
  ChannelView's window is open. Setup is in the README under *On a tablet*.
- **Type to search in the [+] menu.** The add menu opens with a search box
  that already has the keyboard: start typing and the menu becomes a list of
  matches. Enter adds the top one.
- **A forgiving plugin search** in the add dialog, the menu and the web
  page. Punctuation and spaces don't matter ("proq", "ssleq"), initials work
  ("pq4"), and one slip is forgiven in a longer word ("saturm",
  "compresor"). Results are ranked, best first, with plugins you've used
  recently nudged up.
- Under the hood: the gain-reduction trace's data moved into
  `TS_CV_Trace.lua` so the web page draws exactly the same picture, and
  ChannelView and the web page now agree on which plugins are tapped rather
  than undoing each other's routing.


## 1.6.0 — hardware styles, and a gain-reduction trace

- **Knobs and faders can wear a hardware look.** Right-click one ▸ *Style*:
  *Skirted*, *Pointer* or *Trim pot* knobs beside the familiar *Arc*, and
  *Console* or *Rail* fader caps beside *Flat*, each in one of nine cap
  colours. *Apply to every knob on this panel* copies a look across.
- **Faceplates.** The panel menu's *Faceplate* puts the panel on Charcoal,
  Gunmetal, Aluminium, Steel blue, Navy, Cream, Racing green or Oxblood
  instead of the theme's grey, with labels, values and scales inked to stay
  readable on each. *View ▸ Faceplate texture*, on by default, adds a gentle
  top-lit gradient, and brushed grain on aluminium.
- Only the Theme faceplate and the Accent cap follow Hue/Tint; the rest are
  fixed colours, like the hardware they're modelled on. Looks are saved with
  the plugin's layout, so every instance shares them.
- **Gain-reduction trace.** Click a plugin's gain-reduction meter and it
  opens out into a trace: the plugin's own output waveform with its input
  behind it, and its reduction drawn down from the top. Right-click it for
  the window: 1 to 8 beats, tempo-locked, or 1 to 4 seconds. It freezes when
  the transport stops. Needs TS_TrackProbe 1.5.0 (reopen the project after
  updating); a plugin that reports its own reduction is tapped for its
  levels while its trace is open.
- The wet slider's **100%** button is gone; the slider does the same job.


## 1.5.3 — no measured reduction on ReaEQ

- **ReaEQ can no longer be set to measure gain reduction.** An EQ has no
  reduction to measure: what the probe read for it was the curve's effect
  on the programme, which swings with every note, and Track Analyser drew
  it as a second measured trace bouncing several dB. ChannelView's ReaEQ
  panel never showed that meter, so there was no sign of it there. The
  option is gone from ReaEQ's menu and Edit Parameters, and a saved layout
  that still has it is ignored: ReaEQ is tapped for its input and output
  levels only.


## 1.5.2 — wet % on ReaEQ

- **Fixed: ReaEQ's wet % could show (and set) the wrong value** after a band
  was added or removed: it read whichever ReaEQ parameter had moved into
  the wet control's old place, often a band's gain or frequency. The wet
  control is now looked up again whenever a plugin's parameter count
  changes.


## 1.5.1 — I/O meters on ReaEQ

- **The ReaEQ panel gets input/output meters too.** Ticking *Input/output
  meters* on ReaEQ now does what it does on any other plugin: input meter
  hard left, output hard right, with the EQ canvas between them at its usual
  width. 1.5.0 left them off that panel.


## 1.5.0 — input/output meters, and wet

- **Input/output meters per plugin.** Tick **Input/output meters** in a
  plugin's right-click menu or in Setup Edit Parameters, and its panel gets
  two slim meters, one at each edge of the panel so it reads the way the
  audio flows: input hard left, output hard right, with the gain reduction
  meter now on the right too, just before the output. Under the input is its
  held peak. Under the output is the change in level, output RMS minus input
  RMS, which answers "what is this plugin doing to my gain staging". The
  tooltip gives peak and RMS for both. A bypassed plugin reads "byp".

  They're measured by the track's TS_TrackProbe pair from the same copies
  of the audio as measured gain reduction, so they work for any plugin
  between the probes. Peak falls at 20 dB/s, and RMS is true RMS over
  300 ms. A plugin that reports its own reduction is tapped for its levels
  alone, which costs the probe almost nothing. The limit is still four
  measured plugins per track, gain reduction and levels together.

- **Wet % in every panel header.** REAPER's own wet/dry mix for the plugin,
  the one in the corner of its FX window. It's centred in the header, dim
  at 100% and highlighted when it's anything else, so a
  plugin mixed back stands out. Click it for a slider, with a 100% button
  to put it back. It's hidden on panels too narrow to spare the room.

- **TS_TrackProbe 1.4.0**, with the levels. Reinsert or reload the probes
  (or reopen the project) to pick it up.


## 1.4.1 — MIDI sends

- **MIDI sends and receives.** A third mode beside Direct and Sidechain:
  MIDI only, all channels, no audio, for driving an instrument on another
  track. It's in the add menu, and on each send's mode button, which now
  cycles **DIR** → **SC** → MIDI: DIR for direct, SC lit for sidechain, and a
  MIDI socket on blue for MIDI.
  Double-click still goes straight back to Direct, and the right-click menu
  has all three. Switching back from MIDI turns the audio on and the MIDI
  off.

1.4.0 never reached ReaPack: three development files in the repository were
missing the marker that tells the index builder they aren't packages, and the
build stopped on them. Both versions arrive together with this one.


## 1.4.0 — gain reduction for plugins that don't report it

### First, the probes

Measuring a plugin needs a **TS_TrackProbe pair** on the track: one at the
very start of the FX chain, one at the very end. The plugins to be measured
sit between them. The probes are a small JSFX that ships with ChannelView
(and with Track Analyser, which uses the same pair for its displays).

- **What they do.** The last probe is where the measuring happens: it
  compares a copy of each measured plugin's input with its output. The
  first probe marks where the chain starts, and while playback is stopped
  it supplies the quiet test signal that sets each plugin's zero (below).
- **What they don't do.** They don't change your audio while you play. They
  sit idle — a few instructions per sample — until ChannelView or Track
  Analyser is open and reading them.
- **Where they go.** Anywhere they bracket the plugins you want measured:
  the top level of the chain, or inside a container (a probe pair baked into
  your track templates works as is). Plugins outside the pair aren't
  measured, and Setup says so.
- **Adding them.** The new **Probes** button in the header bar (left of the
  FX chain button) adds a pair to the selected tracks that don't have one,
  after asking. Ticking *Measure gain reduction* on a track without them
  offers the same. It only ever adds: nothing is removed, reordered or
  replaced.

### What's new

- **Measure gain reduction.** Plenty of compressors never tell REAPER how
  hard they're working, so there was nothing to meter. Tick **Measure gain
  reduction (estimated)** in a plugin's right-click menu, or in Setup Edit
  Parameters, and every instance of it that sits between a TS_TrackProbe
  pair gets a meter anyway, on every track at once, with nothing to arm.
  ChannelView routes a copy of the audio going into the plugin and coming
  out of it on spare channels (from 5/6 up, skipping anything a plugin,
  send or receive already uses) to the post probe, which compares the
  two in ten bands. Up to four plugins per track. The routing is written on
  the track and taken out exactly when you untick it. A track with no
  probes is offered a pair.

- **Its zero is measured while you're stopped.** A compressor that never
  lets go has no "no reduction" moment to learn from. So each time
  playback stops, the pre probe plays a second of quiet pink noise at
  −60 dBFS and another at −50 dBFS through the chain. The post probe keeps
  the track silent while it does. Whatever each plugin does to that is its
  zero. It waits for a second of silence first, and gives way the moment
  you press play or audio arrives. The meter's tooltip and Setup say
  whether the zero has been measured. **Measure the zero while stopped
  (all tracks)** in Setup turns it off, for instrument tracks you play
  while stopped. It needs REAPER's "Run FX when stopped", which is on by
  default.

- **Probes button** in the header bar. Hover it to see whether the track has
  its pair; click to add one to the selected tracks that don't, with a yes/no
  first.

- **Measured is pink, reported is amber.** A measured meter is drawn in a
  colour of its own (`gr_measured`, following the hue), paler until its
  zero has been measured.

- **The whole track's gain reduction**, as a slim bar beside the level
  meter in the Channel panel and every mixer strip. Its tooltip breaks it
  down per plugin. Reported reduction is stacked above measured, in their
  own colours.

- **GR meters default to 18 dB full scale** instead of 12. The ladder the
  scale steps up when reduction runs past it is now 6, 12, 18, 24, 30, 40,
  60. Meters you've already set up keep their own scale.

- **New track with FX chain** joins New track and New track from template
  in every add-track menu: the track menu, the empty space under the last
  track, and the send and receive menus. Your FXChains folder as
  submenus; the new track is named after the chain.

- **TCP: the channel panel follows the selection.** Once it's open,
  selecting a track anywhere (here, in the arrange view, from an action)
  moves it to that track. Selecting still never *opens* it.

- **TCP: toolbar gaps.** Right-click the toolbar for **Add gap** or
  **Insert gap before**: half a button of blank space for grouping, with
  a faint outline on hover so it can still be right-clicked. A button's
  tooltip is now just its label when it has one.

- **Errors are written to a file too.** If ChannelView stops on an error,
  the report also goes to `TS_ChannelView_error.log` beside the script, in
  case the console opened somewhere you can't see it.


## 1.3.4 — names that keep up

- **Live parameter names.** Some plugins rename their own parameters as
  you use them -- Softube Console 1 and Flow name each macro after
  whatever is loaded into it. A saved label or alias froze the name as it
  was on the day. Two new switches in Setup Edit Parameters:
  - **Live parameter names** (under Gain reduction meter): every control
    on that plugin's panel shows what the plugin calls its parameter
    right now.
  - **Live name** (in the Selected control row): the same, for one slot.

  Labels and aliases are kept, just greyed out, so turning live off
  brings them back. The dialog's own parameter lists now refresh twice a
  second, so they follow the plugin too. Stored as `Live=1` on the
  plugin's section, or bit 3 of a control's flags field.

- **Smarter abbreviations.** A caption too wide for its cell used to be
  chopped at the end. It's now shortened the way a console scribble strip
  does it, one step at a time and only as far as needed: brackets
  ("Threshold (dB)"), then the audio world's own short forms (Frequency →
  Freq, Attack → Atk, Resonance → Reso, High → Hi), then filler words
  ("Resonance Control" → "Reso"), then closing up spaces if that alone is
  enough ("Output Gain" → "OutGain"), then vowels from the right, never a
  word's first letter ("Reverb Drive" → "Verb Drv"), and only then a cut.
  Values are never abbreviated, only cut. The short forms are the
  `U.SHORT` table in TS_CV_Util.lua, easy to add to.

- **Fixed: "Show the input FX chain"** opened REAPER's Add FX browser.
  The item is now greyed out while the input chain is empty (an empty
  chain is REAPER's cue to open the browser; "Add input FX" above it is
  the way in), and with plugins in it, the chain window itself opens,
  falling back to REAPER's own "View input FX chain" action if it
  doesn't.


## 1.3.3 — one palette across the TS_ tools

- **Hue and tint moved to a shared section.** They now live in their own
  ExtState section, `TS_Palette`, rather than in ChannelView's -- read
  and written by ChannelView, the TCP window, TS_Visualizer, its editor
  and TS_TrackAnalyser alike. Change the hue in any of them and the rest
  follow within half a second, the same poll the two ChannelView windows
  already shared.

  They lived here because ChannelView had them first, and three other
  scripts reached across into this section to find them -- which worked
  only for as long as ChannelView was the one that owned them. Nothing
  about the controls or the palette maths changed.

  The old location is still read when the new one is empty, so an
  existing setting survives the update rather than snapping back to
  stock. Nothing supplies a default from the shared section: absent
  means "no shared setting" and each tool keeps its own, so ChannelView
  still runs with neither of the others installed.


- **Also in 1.3.3**, released without notes of their own:
  - **ChannelView TCP**, a second window (its own action, installed with
    ChannelView) docked beside the arrange view: a track panel in
    ChannelView's style, lined up with REAPER's arrange row for row, with
    a toolbar of REAPER actions above the first track and ChannelView's
    own channel panel opening beside a clicked track. Needs
    js_ReaScriptAPI.
  - **Record input and input FX.** A record-input dropdown across the top
    of every strip (No input / Mono / Stereo / MIDI devices and channels /
    Record mode), and an **IN** button at the left of each strip header
    (**MON** on the master) for the input FX chain: lit when there are
    input FX, amber when they're all bypassed, with a menu to add, bypass,
    remove and show them.
  - **Drag a track onto another to make it a child.** The middle of a
    strip (or a TCP row) nests the dragged tracks inside it, outlined as
    you hover; the outer quarters still reorder. A folder with hidden
    children opens so what you dropped stays in view.
  - **Add track in the right-click menu:** a new track, or one from a
    template, after the track you clicked.
  - **Load FX chain** button in the header bar: your FXChains folder as a
    menu, added to the end of the chain, or replacing it with "Replace the
    existing FX" ticked. One undo step either way.
  - The channel/mixer view toggle moved to the left of the header bar.


## 1.3.2 — track icons

- **Track icons (optional).** View > Track icons shows each track's
  REAPER icon above its name button, in both views. The name button
  becomes one taller button: a thin stripe of the track colour along the
  top, the icon on the neutral panel colour (where any icon reads,
  whatever the track colour), and the name in the track colour below.
  Tracks without an icon keep the same shape, empty, so the row stays
  even; with no icons in the project the row stays its usual height.
  Off by default.

## 1.3.1 — shortcuts keep working

- **Keyboard focus goes back to REAPER.** Clicking a ReaImGui window
  gives it the keyboard, and REAPER's ordinary shortcuts -- Space,
  navigation, your own Main bindings -- only run while REAPER's own
  windows have it. Now, once a click or drag in ChannelView is finished,
  focus returns to the arrange view, so the next key press is REAPER's.
  Text fields, menus and dialogs keep the keyboard until you're done
  with them. On by default; View > Return keyboard focus to REAPER turns
  it off. Needs the js_ReaScriptAPI or SWS extension to move focus; with
  neither, the option is greyed out and nothing changes.

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
