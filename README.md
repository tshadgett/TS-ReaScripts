# TS-ReaScripts

Two tools for REAPER, built for mixing through channel-strip plugins that
either have no GUI worth using or hide what they are doing.

| | |
|---|---|
| **[ChannelView](TS_ChannelView/)** | A docked channel strip: one editable control panel per plugin on the selected track. Pick the parameters you actually reach for, lay them out once, and every instance of that plugin comes up the same way. |
| **[Track Analyser](TS_TrackAnalyser/)** | A docked two-panel display showing what your processing is *doing* — the measured magnitude response of whatever sits between two probes, drawn over the spectrum, plus a before/after waveform overlay. Nothing is modelled; both panels read the audio. |

Both need the **ReaImGui** extension (v0.9 or newer), which ReaPack installs
for you.

## Installing with ReaPack

1. In REAPER: **Extensions ▸ ReaPack ▸ Import repositories…**
2. Paste this and click OK:

       https://github.com/tshadgett/TS-ReaScripts/raw/main/index.xml

3. **Extensions ▸ ReaPack ▸ Browse packages…**, search for `TS_`, right-click
   what you want and choose Install.

Updates then arrive through **ReaPack ▸ Synchronise packages**.

Don't have ReaPack? It lives at [reapack.com](https://reapack.com).

## Installing by hand

Download the repo, then:

- `TS_ChannelView/*.lua` → `REAPER/Scripts/TS_ChannelView/`
- `TS_TrackAnalyser/*.lua` → `REAPER/Scripts/TS_TrackAnalyser/`
- `TS_TrackAnalyser/TS_TrackProbe.jsfx` → `REAPER/Effects/TS_TrackAnalyser/`

Then **Actions ▸ Show action list ▸ New action ▸ Load ReaScript…** and pick
`TS_ChannelView.lua` and `TS_TrackAnalyser.lua`.

Nothing assumes a fixed install path, so either route works.

## Where to start

Each tool has its own README with the reasoning behind it, not just the
controls:

- [ChannelView](TS_ChannelView/README.md) — what it does, how layouts are
  stored, and a long section of notes on the things that turned out to be
  harder than they looked.
- [Track Analyser](TS_TrackAnalyser/README.md) — why it measures rather than
  models, what the Collisions overlay is actually computing, and what it
  deliberately does not model.

## Working on these

The live copies run from REAPER's own `Scripts/` and `Effects/` folders;
this repo is what gets published. `tools/sync-from-reaper.sh` copies one
way, REAPER to repo, and skips the two things that must never ship: the
`.ini` layout and step caches, which are personal data, and a second copy
of LICENSE.

    ./tools/sync-from-reaper.sh          # from Git Bash

It then checks something easy to forget: **ReaPack pins a version to the
commit where it first appeared**, so changing a file without bumping
`@version` delivers nothing to anyone — no index change, no error, no
warning. The script says so plainly when it happens.

## Licence

MIT — see [LICENSE](LICENSE). Use it, change it, ship it; just keep the
copyright notice.

## Credits

Written by Tim Shadgett, with Claude.

No third-party code is reproduced in either tool. ChannelView took the
parameter-mapping idea and the layout file format from Wormhole Labs'
**StripLink** — the concepts, not the source. Its container-aware FX chain
walk is ported from my own earlier, unreleased Plugin Rack and Docked Plugin
Display scripts.

Track Analyser's masking model is implemented from the published
literature — Glasberg & Moore's ERB-rate scale, Traunmüller's Bark scale and
Schroeder's spreading function — rather than ported from anyone's
implementation.
