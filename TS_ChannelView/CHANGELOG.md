# ChannelView — changelog

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
