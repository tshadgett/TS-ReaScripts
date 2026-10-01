# Track Analyser — changelog

## 1.4.1 — in step with ChannelView

No changes. The version moves to 1.4.1 to match ChannelView, so the two
tools carry the same number. 1.4.0 never reached ReaPack (see ChannelView's
1.4.1 notes), so the notes below arrive with this version.


## 1.4.0 — first public release

Track Analyser has been in the repository for a while; this is the version
it's announced with. It's a docked, two-panel display of what your
processing is *actually doing* to the selected track, measured from the
audio rather than modelled from parameter values. It was built for plugins
with no GUI worth the name (PSP InfiniStrip, Scheps Omni Channel), but it
works with anything.

**How it works.** A **TS_TrackProbe** sits at each end of the track's FX
chain. Both take their FFT on the same block boundaries, so the difference
between what they hear *is* the magnitude response of everything between
them, checked against stepped-tone models to 0.069 dB rms. It needs no
parameter maps and no plugin profiles, and it's right about bypass,
saturation and plugins nobody has characterised. The probes don't change the
audio and sit idle until the panel arms the pair on the track you select.
Select a track without them and the header offers **Install?**, after a
yes/no. It only ever adds. A pair inside a container (baked into a track
template) is found where it is.

- **Panel 1:** the spectrum, pre and/or post, with the measured response of
  the chain drawn over it. **Collisions** overlays, in red, where another
  track you pick masks this one, using a perceptual (Bark/ERB) masking
  model rather than raw overlap.
- **Panel 2:** the waveform before (grey) and after, with gain reduction
  over it: a bar per compressor, and a trace showing its shape.
- **The waveform can follow the tempo.** The window is set from the header:
  free (mouse wheel), a length in milliseconds, or a number of **beats**
  (1–32) at the project tempo, with a grid line per beat. **Lock** makes it
  behave like a triggered scope. The picture steps a beat at a time, lined
  up with the beat at the play position, so a kick or snare lands in the
  same place every time and you can watch the compressor's attack and
  release on it rather than chase it. In milliseconds, **Hold** does the
  same in steps of the window length.

Needs ReaImGui 0.9 or newer. ChannelView isn't required. With it installed,
Track Analyser also shows gain reduction for plugins that don't report it
(below).

### What's new in 1.4.0

- **Plugins measured by ChannelView show up here.** When ChannelView is
  set to measure a plugin that doesn't report its gain reduction (see its
  1.4.0 notes), Track Analyser draws it too: a bar, and a trace at 500
  readings a second straight from the probe, the same number as the
  meter. They're pink, ChannelView's colour for measured reduction, with
  their own swatch and Auto box in Settings. A **Σ** bar shows the track's
  total when more than one plugin contributes. The Sources list says
  whether each one's zero has been measured.

- **One trace per reporting plugin, with the probes' detail.** Reported
  values arrive about 18 times a second, so on their own they draw a
  stepped line. The probes see the whole chain at 500 a second. Take away
  what the measured plugins account for and what's left belongs to the
  reporting ones. That is fitted to their reports (scale and offset, over
  the visible window) and split between them by their share of the
  reports at each moment. With nothing reducing, the fit goes to zero and
  the trace lies flat. The old version slid the probes' shape onto the
  meters' average, which drew a square wave beside meters reading 0. The
  scale it settles on is shown in Settings.

- **Traces sit on the transient.** REAPER compensates latency at the end
  of the track, not inside the chain, so a reading taken at a plugin is
  early against the waveform by the latency of everything after it. A
  plugin's own meter is early by its own latency too (a lookahead
  compressor's detector runs ahead of its output). Each trace is now drawn
  that much later. The delay is listed per source in Settings.

- **The chain latency is re-read twice a second**, not just when you pick
  a track, so bypassing a plugin with latency doesn't leave the two probes
  out of step.

- **Paler second and third sources.** Two reporting plugins would have
  been two bars and two traces in one colour. The second and third of a
  kind are now paler, and each bar matches its trace.

- **TS_TrackProbe 1.3.0.** Tap inputs for up to four measured plugins
  (ChannelView sets them up), and the stop-time zero measurement described
  above. It no longer resets its memory on every play and stop, so what
  it has learnt survives the transport. ChannelView now ships the probe
  as well, for anyone who doesn't have Track Analyser installed.


## 1.2.0 — one palette across the TS_ tools

- **Hue and tint are now shared.** They live in their own ExtState
  section, `TS_Palette`, and ChannelView, its TCP window, TS_Visualizer,
  its editor and this panel all read and write it. Move the hue anywhere
  and the rest follow within half a second.

  They used to live in ChannelView's own section, which three other
  scripts reached across into — workable only for as long as ChannelView
  happened to be the one that owned them. The old location is still read
  when the new one is empty, so an existing setting survives the update
  instead of everybody's colours snapping back to stock.

  Nothing supplies a default from the shared section: absent means "no
  shared setting" and each tool keeps its own, so any of them still runs
  with the others not installed. Applying a change never writes back,
  which is what stops two tools ping-ponging over the last decimal place.

- **The data colours follow the hue, one tick box each.** The spectrum,
  waveform, response-curve and reduction colours were seven hand-picked
  hex values, so moving the Hue slider recoloured the furniture and left
  the data on the old scheme. Each is now written as the offset,
  saturation and lightness that reproduces its hand-picked value *exactly*
  at hue 219 — all six verified to round-trip to their original hex — so
  turning this on changes nothing until you move the hue.

  Two families, and the split was already in the numbers: the unprocessed
  and processed pairs sit within 16° of the base, because they are the
  subject; the response curve and the reduction trace come out at −175°
  and +171°, complementary, which is what makes them readable *on top of*
  the first pair instead of lost in it.

  Collision red does not follow. It is a fixed colour for a fixed
  purpose, like a bypass lamp, and a warning that changes colour with the
  furniture is not a warning.

  Each colour has its own tick box: untick it and that one picker comes
  alive while the rest carry on following. Reset puts them all back.


## 1.1.0 — the measured gain-reduction trace, corrected

Two faults, found by simulating the trace against a compressor whose gain
was known, and neither of them visible by looking at the screen.

- **The measured trace was not measuring gain.** It was post RMS over pre
  RMS across the span, which is the span's *level* change — the same thing
  as its gain only while nothing in the span touches the spectrum. One EQ
  band breaks that. A static +6 dB at 100 Hz adds six decibels to the ratio
  through a bass note and nothing through a cymbal, so the EQ's
  contribution swings with the programme and lands on the trace looking
  exactly like compression. Against a known 13.1 dB reduction it drew
  38.6 dB: 3.10 dB of error, correlation 0.709.

  The probes now publish a level per band per scope column — ten bands
  from 30 Hz to 18 kHz, two cascaded bandpass sections each — and the
  trace is built from per-band ratios. A band's ratio is whatever the EQ
  does in that band, whatever the programme is doing, so subtracting each
  band's own average over the window removes the static EQ exactly, and
  what is left, common to every band, is the compressor. Same material,
  same chain: **0.68 dB of error, correlation 0.972**, and the range stops
  lying. Across seven EQ and saturation chains the mean error went from
  2.55 dB to 0.82 dB. The arithmetic is in `TS_TA_GR.lua`, on its own, so
  it can be tested against synthetic bands with a known answer.

  One section per band is not enough — its skirts overlap far enough that
  neighbouring bands leak into each other and the separation the whole
  idea rests on stops working: 1.53 dB against 0.86 for two. The
  filterbank runs only while the measured trace is on screen.

- **The probes were never aligned.** Everything between them delays the
  post probe by its own reported PDC, and REAPER compensates delay at the
  track *output*, not inside a chain — so column N of one probe and column
  N of the other held audio taken at different moments, and nothing had
  put that right. At 32 samples, which is what a single oversampled plugin
  costs, the error against a known reduction went from 0.01 dB to 2.36 dB
  and the correlation from 1.00 to 0.737. At one whole column a silent gap
  in one ring lines up with a transient in the other and it stops being
  wrong and starts being noise: 226 dB spikes on a 12 dB reduction. Any
  linear-phase EQ or lookahead limiter did this, silently.

  The panel now sums the reported PDC of the enabled FX between the probes
  and the pre probe delays itself to match. Settings shows the figure and
  whether the probe applied it, because a compensation you cannot see is
  indistinguishable from one that is not happening.

- **The band responses are combined with a median, not a mean, and
  smoothed over five columns.** Per-band ratios fixed the trace's *shape*
  but left visible hash on the baseline, and the hash is not evenly
  earned: a 2 ms column holds 26 cycles of the 13 kHz band and 0.08 of a
  cycle of the 41 Hz one, so the bottom band's level is largely a
  statement about phase. Measured, its column-to-column wobble is 1.56 dB
  against 0.13 dB at the top — and a mean hands that band a tenth of the
  answer. Dropping the low bands is worse, not better: they carry real
  information on bass-heavy material and excluding them took the error
  *up*, 0.52 dB to 0.73. Keeping them and outvoting them is what works.

  The smoothing matters more than it looks, because the trace is drawn
  from the DEEPEST column in each pixel — so noise is rectified into
  apparent reduction. On a 1 ms attack the unsmoothed estimate read the
  deepest moment as −10.50 dB where the truth was −8.34; smoothed it
  reads −9.26. It does not blunt the transient, it stops the noise
  deepening it, and that holds from 1/30 ms to 30/400 ms.

  Across the battery: error **0.69 dB → 0.32 dB**, visible hash
  **0.57 dB → 0.10 dB**.

  The median is taken on the ratios rather than the decibels, since a
  logarithm cannot move the middle value — one log per column instead of
  one per band. On windows past 1500 columns every second column is
  sorted, which at that zoom is well inside one pixel.
- **Falling back when the measured route has nothing.** The reported
  trace was suppressed whenever the measured one was *asked for*, whether
  or not it had anything to draw — one variable meaning two things. While
  the measured route was a broadband ratio it always had something, so
  the hole never opened; with the filterbank it can legitimately come up
  empty, and a track with a compressor reporting perfectly well drew no
  trace at all and said nothing about why. The fallback now keys off
  whether the measured trace actually drew.
- Settings says plainly when the probes predate the filterbank, which is
  the state every existing project is in until the FX are reloaded.
- Settings prints the chain latency and the number of GR bands in use,
  beside the publish and frame rates.

**Upgrading:** the probe and the panel have to match — `TS_TrackProbe`
publishes the per-band data the trace is built from, and an older probe
makes the panel fall back to drawing nothing rather than drawing
something it cannot stand behind.


## 1.0.0 — first public release

Released under the MIT Licence.

The version number goes *down*, from 1.10.1. Those were private build
numbers on a tool nobody else had; this is version one of the thing people
actually get. Nothing about the measurement changed with it.

- Renamed onto the `TS_` convention: `TA_Panel.lua` is now
  `TS_TrackAnalyser.lua`, the libraries are `TS_TA_*`, and the folders are
  `Scripts/TS_TrackAnalyser/` and `Effects/TS_TrackAnalyser/`.
- The probe is now **`TS_TrackProbe`**, and readable: its JSFX `desc:`
  said `TAProbe` while the Lua looked for `TA_Probe`, so name matching
  only ever worked by falling back to the file path. File, `desc:` and
  lookup string now all agree.
- ExtState section `TrackAnalyser` is now `TS_TrackAnalyser`, and the gmem
  namespace `TA_Mem` is now `TS_TA_Mem`. Window position, dock state and
  settings reset once on first run after updating.
- The slow-frame console message is gated behind a `DEBUG` flag, off by
  default. There is no other logging in a release build.
- Removed `TA_Archive.lua`. It had already done its job, and its keep-list
  had gone stale: running it would have archived `TA_Mask`,
  `TA_Insert_Probes` and `TA_Quiet_Probes`, all of them live.
- Removed `TA_Cal.jsfx` and `TA_WaveProbe.jsfx`, unreferenced since the
  stepped-measurement rig was taken out in 1.0.0.
- Removed two unreferenced functions (`disarmAll`, `bandHz`). `measureOff`
  is kept as the documented counterpart to `measureLive`, with a note
  saying why nothing calls it.
- Settings scrolls with the mouse wheel. The panel window is created with
  `NoScrollWithMouse`, because over the spectrum the wheel means floor and
  over the scope it means time — but that flag belongs to the window, and
  settings was drawn inside it, so the wheel did nothing there and anything
  past the bottom edge could not be reached at all. Settings now has its
  own child window with its own scrollbar, bounded so that opening it no
  longer pushes the panels off the bottom of a short window. The wheel
  keeps out of the spectrum floor while the pointer is inside it.
- The response curve is **off by default**. It needs both probes
  publishing and enough signal to average, so on a quiet or half-set-up
  track it comes and goes; the spectrum underneath it does not. Settings ▸
  SPECTRUM turns it on.
- The header's "no probes" note is now an offer to fix it: **No probes on
  track – Install?**, which asks for confirmation and then sets the track
  up. It used to say `no TS_TrackProbe on this track` and point at
  Settings. The Settings button and the header prompt now run the same
  routine rather than two copies of it.
- The Settings **PROBES** section has gone with it. Two buttons for one
  action, one of them behind a scroll in a panel you open to change
  settings rather than to fix a track. The header prompt appears on the
  track that needs it, at the moment you are looking at it. Running
  `TS_TA_InsertProbes.lua` from the Action List still does several
  selected tracks at once, which is the one thing the header offer cannot.
- `TS_TA_InsertProbes.lua` no longer writes a report to the ReaScript
  console on every run. The FX chains change in front of you and there is
  an undo point, so the report said nothing you could not see. It now
  speaks only in the two cases you cannot: something failed (with a
  pointer to a missing `TS_TrackProbe.jsfx`, which is the usual cause), or
  every selected track was already probed and it did nothing.
- The measured gain-reduction trace is **level-gated**. Its only guard was
  a `1e-7` floor -- -140 dBFS -- so in the gaps between phrases it was
  dividing one noise floor by another and drawing whatever came out. On
  quiet material that is a spike to the bottom of the scale on every gap,
  and because the trace's height comes from a mean, the garbage dragged
  the whole thing off as well. Two thresholds now: an absolute -70 dBFS,
  and 45 dB below the loudest moment in the window, since a track riding
  at -50 has real gaps far above any fixed floor. Gated columns hold the
  last real reading -- a gap in the audio is not a moment of no gain
  reduction, it is a moment that cannot be measured.
- Settings prints the **panel's own frame rate** beside the publish rate,
  and says which of the two is the limit. The publish figure counts how
  often the reduction value *changes*, which only means the plugin's
  update rate if we are looking more often than it changes -- without the
  comparison it could as easily have been reporting our frame rate under
  the plugin's name. Measured on Pro-C 3: 16.7 readings a second against a
  31.7 fps panel, so the plugin is the limit and nothing on this side
  would move it.
- The **compare-against list** now looks like ChannelView's send menu: a
  colour swatch down the left of every row, and the project's grouping
  kept rather than flattened -- tracks named with nothing but punctuation
  become a rule, and REAPER's own track spacer puts one above the track it
  sits on. Track numbers stay real, so a gap in the numbering reads as the
  spacer it is. The selected track is still listed, now disabled with its
  swatch dimmed rather than as grey text, so the row keeps its shape.
- Added this changelog and a README.

**Upgrading:** re-run `TS_TA_InsertProbes.lua` on your tracks. Probes
inserted by an earlier version carry the old name and the panel will not
find them.

## Before this

The private history is kept in the header of `TS_TrackAnalyser.lua`, which
records what the rewrite took out when the panel stopped drawing from a
model of InfiniStrip and started measuring the audio instead.
