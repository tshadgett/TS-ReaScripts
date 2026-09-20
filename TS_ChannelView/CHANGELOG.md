# ChannelView — changelog

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
