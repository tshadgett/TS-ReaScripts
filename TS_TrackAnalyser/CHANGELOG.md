# Track Analyser — changelog

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
- `TS_TA_InsertProbes.lua` no longer writes a report to the ReaScript
  console on every run. The FX chains change in front of you and there is
  an undo point, so the report said nothing you could not see. It now
  speaks only in the two cases you cannot: something failed (with a
  pointer to a missing `TS_TrackProbe.jsfx`, which is the usual cause), or
  every selected track was already probed and it did nothing.
- Added this changelog and a README.

**Upgrading:** re-run `TS_TA_InsertProbes.lua` on your tracks. Probes
inserted by an earlier version carry the old name and the panel will not
find them.

## Before this

The private history is kept in the header of `TS_TrackAnalyser.lua`, which
records what the rewrite took out when the panel stopped drawing from a
model of InfiniStrip and started measuring the audio instead.
