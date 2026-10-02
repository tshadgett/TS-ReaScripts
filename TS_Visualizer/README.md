# TS_Visualizer

A docked, real-time metering and visualizer window for REAPER — LUFS, a
goniometer, an organic "Symbiote" level blob, an oscilloscope, a log-frequency
spectrum analyser with per-track colour overlay, a spectrogram/waterfall, and
a live LUFS-vs-dynamics plot, all in one resizable panel grid with a shared,
huggable colour theme.

## Origin

This is a fork of **JKK_Visualizer** by Junki Kim. The original shipped six
modules (LUFS, Gonio, Symbiote, Scope, Spectrum, Spectrogram), a fixed RGB
colour scheme, and a drag-to-reorder module list — all of that is still here,
largely unchanged in its core rendering math. Everything described under
"What's new since JKK_Visualizer" below was added on top of it. See
**Credits** for the full acknowledgement.

## Modules

- **LUFS** — momentary and short-term loudness with peak-hold, from the
  original.
- **Gonio** — goniometer/vectorscope with a fading dot trail and
  true-peak markers, from the original.
- **Symbiote** — the organic, bass-reactive blob, from the original.
- **Scope** — oscilloscope with click-to-freeze, from the original.
- **Spectrum** — log-frequency spectrum analyser with a peak-hold line, a
  cursor-following Hz/note readout, and an optional dB/octave slope guide,
  from the original. Extended here with a strip of per-track colour
  swatches down its right edge (see **Per-track spectrum overlay**).
- **Spectrogram** — scrolling waterfall display, from the original.
- **Dynamics** *(new)* — a live scatter plot of short-term LUFS against
  PSR (peak-to-short-term-loudness ratio), with a fading comet trail for
  the last few seconds and a slower-accumulating session cloud that
  resets when the transport stops. Optional reference bands for a
  loudness target and a genre/style dynamic-range target can be overlaid
  (see **Targets**).

## What's new since JKK_Visualizer

This list is compiled from this fork's own CHANGELOG, source comments, and
the full working history of this release pass — it should be complete, but
nothing from before the fork's own CHANGELOG started (version 2.0.1) carries
an exact date.

- **A new Dynamics module.** Not present in the original at all. Backed by
  a new PSR/crest-factor engine added to the JSFX (a short-term 3-second
  sliding true-peak window and a matching unweighted RMS window, alongside
  the original's LUFS engine), so the scatter plot, trail, cloud and target
  bands all run off real measured data rather than a derived approximation.
- **Loudness and genre/dynamics targets.** Two new sliders on the probe
  JSFX, editable from the Editor, each drawn as a reference band on the
  Dynamics panel. Both persist per-project (so a song remembers its own
  target) and fall back to a remembered global default for new projects —
  a two-tier save/load that didn't exist in the original's all-global
  ExtState scheme.
- **Per-track spectrum overlay.** A strip of colour swatches on the
  Spectrum panel's own right edge, one per track carrying a
  `TS_TrackProbe` (the probe plugin shared with TS_TrackAnalyser) with its
  "Include in Visualizer Spectrum" option ticked. Click a swatch to arm
  that track; its spectrum is read from the probe and overlaid on the
  master trace in the track's own colour, so you can see which track is
  dominant at a given frequency without soloing anything. Each swatch's
  track name is drawn beside it, full-time rather than as a hover
  tooltip, since the strip sits exactly where the Spectrum panel's own
  frequency tooltip likes to land. None of this — the probe-sharing
  arrangement, the swatches, or the overlay itself — exists in the
  original, which only ever drew the master signal.
- **Hue/tint colour system.** The original's seven colour roles (bg,
  grid, text, zero/mid/peak signal, peak line) were each a fixed,
  independently-edited RGBA value. This fork drives them from a single
  base hue and tint, with a per-role "follow the hue" toggle so an
  individual role can still be pinned to a fixed colour if you want one.
- **Shared palette sync with TS_ChannelView.** An optional toggle that
  makes the hue and tint track the colour last set in any of the TS_
  tools, via a palette section the tools share, rather than needing to be
  set independently in each one.
- **A gear icon and in-panel settings access**, plus a launcher that
  resolves the Editor script's path relative to its own file rather than
  a hardcoded resource-path string, so moving or renaming the install
  folder doesn't silently break the gear icon.
- **Divider lines between every module boundary**, always drawn as the
  topmost thing on screen. The original's dividers could be silently
  painted over by a module's own background fill depending on z-order
  (which module happened to draw last); this fork collects every
  divider's colour and endpoints during layout and draws them all in one
  pass at the very end of the frame, so a boundary is never missing.
- **A reliable colour bootstrap on startup.** The original (and early
  versions of this fork) could show default grey instead of the saved
  palette on REAPER's first paint, because several colour/sync settings
  were only ever restored by the Editor's own load path, not by the
  visualizer script's own startup. All of it now restores unconditionally
  before the first frame, Editor open or not.
- **Persistent Loudness/Genre targets**, per the two-tier scheme above —
  the original had no targets to persist.
- **A swatch margin and permanent track labels**, tuned so the per-track
  overlay strip clears the Spectrum panel's own right edge and its own
  tooltip.
- **One shared hue/tint/grid-opacity palette** across the TS_ tools
  (TS_ChannelView, TS_TrackAnalyser, TS_Visualizer) — see the CHANGELOG's
  2.0.1 entry for the mechanics.

Beyond the above, the original's six modules keep their rendering
approach — the exponential dot trails, the symbiote's noise-driven
wobble, the log-frequency spectrum math, the waterfall's interpolated
scan — essentially as Junki wrote them.

## Targets

**Loudness Target** sets a reference LUFS value, drawn as a ±2.5 LUFS band
on the Dynamics panel. **Genre/Dynamics Target** sets an illustrative
dynamic-range band for a given genre or style. Both are editable from the
Editor, both are saved with the project (so they travel with the song) and
also remembered as your default for new projects.

## Installing

With ReaPack: install **TS_Visualizer** from the TS-ReaScripts repository
(see the repository's main README). It brings the window, the Editor, the
theme helper and the JSFX.

By hand:

1. Put `TS_Visualizer.jsfx` in `Effects/TS_Visualizer/`.
2. Put the Lua files (`TS_Visualizer.lua`, `TS_Visualizer_Editor.lua`,
   `TS_Theme.lua`) together in one folder under `Scripts/`, for example
   `Scripts/TS_Visualizer/`.
3. Actions ▸ Show action list ▸ New action ▸ Load ReaScript… ▸
   `TS_Visualizer.lua`.

Then put **JS: TS_Visualizer** on the master track (or whichever track you
want to watch) and run the `TS_Visualizer.lua` action. The Editor
(`TS_Visualizer_Editor.lua`) opens from the running visualizer's gear icon
or right-click menu, or runs as its own action.

Needs the **ReaImGui** extension (ReaPack) for the Editor window.

## Files

| | |
|---|---|
| `TS_Visualizer.lua` | the visualizer window — run this one |
| `TS_Visualizer_Editor.lua` | the settings/theme editor, launched from the visualizer's gear icon |
| `TS_Theme.lua` | shared ImGui theming helper for the Editor window |
| `TS_Visualizer.jsfx` | the metering engine — LUFS, PSR/crest-factor, FFT. Goes in `Effects/TS_Visualizer/` |

The per-track spectrum overlay also depends on `TS_TrackProbe.jsfx`, which
ships with TS_TrackAnalyser rather than here — any track carrying one with
its "Include in Visualizer Spectrum" option on becomes eligible for a
swatch.

## Credits

Forked from **JKK_Visualizer** by **Junki Kim**
(junkikim.sound@gmail.com), released here with his permission. The LUFS,
Gonio, Symbiote, Scope, Spectrum and Spectrogram modules are his design and
his rendering code at heart; this fork builds the Dynamics module, the
per-track overlay, the hue/tint theming system, and the various reliability
fixes above on top of that foundation.

Fork maintained by Tim Shadgett, with Claude.
