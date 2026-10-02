# TS_Visualizer — changelog

## 2.1.0 — release cleanup, Junki credited, Dynamics/targets persist

Public-release pass: README, LICENSE (MIT), and this entry, ahead of adding
the tool to the TS-ReaScripts repository. No change to the metering math.

- **Junki Kim is now credited in both places that matter for a release**:
  a Credits section in the new README, and a quiet, permanent text line in
  the Editor window itself ("Fork of JKK_Visualizer by Junki Kim —
  junkikim.sound@gmail.com"). The old hover-only credit (shown on the logo
  image) and the logo image itself were removed earlier in this cycle at
  Tim's own request; the new line replaces it rather than restoring the
  logo, since a static line can't end up hidden behind another panel's
  tooltip the way the hover version could.
- **Loudness and Genre/Dynamics targets now persist.** Previously lost on
  every reload; now saved per-project (travels with the song) and
  remembered as a global default for new projects.
- **Permanent per-track labels on the Spectrum overlay swatches**, replacing
  an earlier hover-tooltip approach that could be covered by the Spectrum
  panel's own frequency tooltip.
- **A right-edge margin on the swatch strip**, so it clears the panel's own
  edge.
- **Dividers between every module boundary, always on top.** Some
  boundaries (Dynamics/Loudness, Spectrogram/Scope, Spectrogram/
  Dynamics-Loudness) could lose their divider line to a module's own
  background paint depending on draw order. Dividers are now collected
  during layout and drawn in one final pass, guaranteed topmost.
- **Reliable colours on REAPER startup.** Base Hue, Tint, the Sync-with-
  ChannelView toggle, and all seven per-role "follow the hue" flags are now
  restored before the very first frame, not only when the Editor has been
  opened at least once.
- **Grid-role opacity fixed** (0.20 → 1.00, matching TS_TrackAnalyser's own
  always-opaque grid role) — grid lines were barely visible against bright
  content, most noticeably the Spectrum panel's own trace.
- **Logo image removed** from the Editor, along with the blank space it
  reserved; the hover-description layout above "Visual Size" is now sized
  dynamically instead of jumping to a hardcoded offset tuned for the old
  logo row.

## 2.0.1 — one palette across the TS_ tools

- **Follows the shared hue and tint.** Sync to ChannelView now reads
  `TS_Palette`, the section the TS_ tools share, rather than reaching
  into ChannelView's own -- so it follows a change made in any of them,
  not only one made in ChannelView. The old location is still read when
  the new one is empty, so an existing setting survives the update.

  The Sync tick box is unchanged and still decides whether Visualizer
  follows the shared colour at all. This changes where the setting
  lives, not Visualizer's right to ignore it. The editor's message now
  says "the shared TS Hue/Tint" rather than naming ChannelView.

## 2.0.0 and earlier

Not recorded. This file starts here.
