# ChannelView — developer notes

How parts of ChannelView work and the pitfalls behind them, for anyone
editing the code. Not installed; the user guide is `README.md`.

## Tests

`dev/TS_CV_Test.lua` fakes enough of the REAPER API to exercise the parts
that don't need a GUI — nearly two thousand assertions covering plugin-name cleaning, the
layout file round-trip, control type guessing, the panel and sends
geometry, the gain maths and fader taper, the GR meter's peak hold and
scale, the tooltips' place-once-then-freeze behaviour, and the
`__startup.lua` surgery, and the master track's nil reads. It runs in plain
Lua, outside REAPER:

    lua5.4 dev/TS_CV_Test.lua

One block checks the add-plugin submenus against a *real* `reaper-fxtags.ini`,
which is the only way to catch grouping cases a synthetic list never
produces. That file is personal and not in the repo, so point the harness at
your own to run that block:

    TS_CV_TEST_FXTAGS=~/path/to/reaper-fxtags.ini lua5.4 dev/TS_CV_Test.lua

The layout has a baseline of its own. `dev/TS_CV_LayoutFixture.lua` holds
where every control landed in a set of real and made-up layouts, in both
flows at one to six rows; the test checks every one is still where it
was. `dev/TS_CV_WebLayoutTest.js` does
the same for the web page (`node dev/TS_CV_WebLayoutTest.js`).
`dev/TS_CV_LayoutSnap.lua` records a new baseline — only ever before a
layout change, never after it.

`dev/TS_CV_LearnSim.lua` runs EQ learning end to end against made-up
plugins (a switched 73-style EQ and a parametric whose Q means something
else and cuts narrower than it boosts) and checks the canvas draws them
within a dB (`lua5.4 dev/TS_CV_LearnSim.lua`).
It also runs the threshold, reverb-decay and saturation measurements
against made-up plugins.

`TS_CV_Audit.py` catches the class of mistake Lua only reports mid-frame — a
call with the wrong number of arguments, a missing `ctx`, a function that
doesn't exist in your ReaImGui build, an `End`/`EndChild` that isn't
guarded, a file-scope local used above its declaration, a track property
read without a nil fallback, or one of the project's own module functions called
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

## Things that get lost at the edges

Three versions of the same problem, handled the same way — by measuring
rather than guessing:

* **Tooltips** are clamped to the **window**, not the screen, and *flip to
  the other side of the pointer* rather than merely sliding, so the box
  never ends up covering the control it describes. The foreground draw
  list is clipped to the window ReaImGui is drawing into, so a tooltip
  that fits on the monitor but hangs past the right edge of a docked
  ChannelView is simply cut off — which is every tooltip in the Sends
  panel, since that panel *is* the right edge. Clamping to the viewport
  alone doesn't help: there is plenty of screen out there. Both bounds
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
culled. Every `BeginChild` here has an `else` that calls
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

## Air between a name and its control

`C.LABEL_GAP` is the space under a cell's name. One number drives the
knob, the toggle and the stepped combo; with different gaps, only the
one with the smallest reads as having its label sitting on top of it.

The cell height is fixed, so `LABEL_H + LABEL_GAP + KNOB_D` has to leave
room for the value line at the bottom — a bigger gap means a smaller
knob. Padding the *grid* instead doesn't work: it pulls the whole first
row up under the panel header, which fixes nothing and costs the panel
its breathing room.

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

## Things that are centred

* A **grid narrower than the room it has** is centred in it. The panel has
  a minimum width, so otherwise a plugin with a single column of parameters
  sits hard against the left edge with all the air on the right, which
  reads as a layout that went wrong rather than as a small plugin.
* The **level meter** is `C.LEVEL_METER_W` wide and centred in its half,
  the way the fader's track is centred in the other one. Both filling
  their columns is not the same as the two looking aligned: a meter flush
  to the panel edge beside a centred fader reads as a mistake.
* The **track name and FX bypass** in the header are centred on the last
  menu item's own rectangle, not on the cursor — see *Header height*.

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

`TS_CV_Audit.py` flags a bare multi-value ImGui call in a last argument
position, counting the optional parameters as returns. `select(n, f())` is
exempt — picking one of several returns is exactly what it's for.

## When it falls over

The defer loop runs through `xpcall`. On a runtime error the console gets
a **full traceback** — every function on the way down, not just the line
that raised — the layouts are saved, and the loop stops rather than
throwing the same error sixty times a second.

That matters because REAPER reports an error at the line it happened *on*,
which for a nil handed to a drawing helper names the helper rather than
the caller that produced the nil. Most errors in this window are of that
shape.

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
  per-chain caches when the chain changes underneath.

**The trap:** don't clear those caches on a *forced* rescan. A forced
rescan happens whenever REAPER's project change count moves — which is on
**every parameter write**, i.e. on every frame of every knob drag — so the
tooltip would be re-anchored to the pointer sixty times a second, and the
meters' peak hold reset just as often. Re-reading the chain and throwing
away UI state are two different jobs: the first follows `force`, the
second follows the chain hash actually changing.

There are no `SetTooltip` calls anywhere in the project, and there
shouldn't be new ones — a control that uses ImGui's tooltip will behave
differently from every other control the moment you drag it.

## Header height

The track-colour rule has to land on the same line as Track Analyser's,
and no style number written down gets it there.

TS_TrackAnalyser.lua pushes no `WindowPadding`, `ItemSpacing` or `FramePadding` of
its own — its `STYLE_VAR` list carries only rounding and border sizes — so
its rule sits at `WindowPadding.y` + a frame-height header row +
`ItemSpacing.y` below the window top. The only hard part is
`WindowPadding.y`, because this ReaImGui build has no `GetStyleVar` to ask
with. None of the shortcuts work: ImGui's documented default (ReaImGui's
are not ImGui's), a number read off a screenshot (right on one machine,
wrong on every other), or `MenuBarHeight` worked back from `GetFontSize()`
(ReaImGui's menu bar is not `FontSize + 2 × FramePadding` either).

It is **measured**, from three things the window will tell us:

    start_y = GetCursorStartPos().y   = WindowPadding.y + decorations
    avail_h = GetContentRegionAvail() = Size.y - 2*WindowPadding.y
                                                - decorations
    Size.y - avail_h - start_y        = WindowPadding.y

The decorations — title bar, menu bar — **cancel**, which is the whole
point: their height never has to be known, so neither the menu bar's
padding nor the font nor the display scaling can get it wrong. It holds
only because there is no *bottom* decoration to subtract, which is why
`C.WIN_NO_SCROLLBAR` exists and why a test checks the flag stays set.
`ItemSpacing.y` comes from `GetTextLineHeightWithSpacing() -
GetTextLineHeight()`, read before our own `ItemSpacing` goes on the stack.

The rule is clamped to the window and nothing else. Not to our own
content start, and not to our cursor further down: our content begins
*below* the menu bar, TA has none, so its rule sits above anywhere ours
could start. A clamp there fires every frame and replaces the answer with
the cursor — the cursor is the thing being corrected for, so clamping to
it silently undoes the correction. So the rule can sit a few pixels up
into the menu bar's lower margin — empty space under the labels, and
exactly where TA's lands. The panels are still held below the content
boundary: the rule may overlap the bar, they may not.

### What the metrics said

Measured in one window:

    font 12.0   frame_h 20.5   itemspacing_y 4.0
    window 536 high, content start 36.5, avail 491.5 -> WindowPadding.y 8.0

The padding measurement works: 536 − 491.5 − 36.5 = 8.0, so the rule
belongs at `8 + 20.5 + 4 = 32.5`, four pixels above our content start.
TA's rule measures 32.5 below the same window top, which is what the
derivation says, to the pixel.

**`C.HEADER_NUDGE` is 0**, and a test asserts it stays zero, because a
number there means something above it has gone wrong. A nudge behind a
clamp has no visible effect — you change the number and nothing moves —
so a nudge that seems to be needed is measuring a clamp, not a real
offset.

`C.RULE_H` is 2, the same rect TA draws. Both windows put a 2px rect at a
y carrying a half pixel, so both cover three rows at the top and two at
the bottom; setting ours to 3 to "match what renders" produces four.
Fixing the symptom one layer above the cause is how you end up a pixel
out in the other direction.

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

**`C.ROT_TEXT` is off.** The rotated version is unreadable on a scaled
display, and the reason is the seam in the middle of the approach: LICE has no idea what
size ImGui is actually rendering at. On a scaled display ImGui reports a
font size of 12 while drawing considerably larger, so the bitmap comes
back small and thin and the quad stretches it. Fixing it means finding
ImGui's real pixel height, which `GetFontSize` does not give.

The code is correct where the scaling is 1:1. Turn
the flag on to try it; `C.ROT_UP` picks which way the text reads.

## Selection outline

The outline is inset by half its own stroke width. ImGui centres a stroke
on the path it is given, so a rect drawn on the child's bounds spills half
a line-width past them on every side -- except that the child's clip rect
eats the spill on the right and the bottom and not on the left and the
top. That asymmetry is a visibly fatter left-hand edge, and insetting is
the fix rather than nudging the coordinates.

It is also drawn last, after the header and the body, or the header paints
out the two corners it just rounded; and the header is capped to the
strip's own radius so the two shapes agree about what a strip is.

## The remove badge on a send

That only works because the cell's own button allows being overlapped.
Without `SetNextItemAllowOverlap` the full-cell `InvisibleButton` keeps
the hover for itself and the corner never responds, so every widget that
fills a cell calls `W.allow_overlap()` just before its button. While the
control is being *dragged* ImGui holds the active id, so the badge can't
steal a knob mid-turn.

A send is deleted at the **end** of the frame, never in the middle of the
loop: every send after it shifts down by one, and their cells have already
been drawn with the old indices.

## Two views: one strip, one row

A mixer strip *is* the Channel panel — `CH.draw_body`, the same function,
given a different track and a different id prefix. That is the whole
design and the reason it was worth doing: a second implementation of a
fader, a meter and a mute button would drift from the first inside a
week, and this way it is the same fader taper, the same peak hold, the
same swipe and the same double-click-for-default, because it is the same
code. The id prefix is what makes it possible — without it every strip
would share one set of ImGui ids and one peak store, and they would all
fight over both.

The double-click targets that switch views are submitted *before* the
controls they sit under, so anything you can actually click takes
precedence and only the gaps switch views.

The track list is the mixer's ruler, not a separate list that happens to
agree. Each button asks `MX.col_width` for its width, which asks the
Channel panel — so a collapsed strip's button collapses with it, and the
written-down number that would have drifted does not exist. The gap
between columns and the TCP visual spacer are the same constants in both.

The strips and the track list are one window. `MX.draw_row` draws both,
on a single BeginChild called `trackrow` in both views: the strips with a
name button under each in mixer view, just the name buttons in channel
view. Same id either way, so ImGui's own per-window scroll memory is what
keeps them lined up — there is no variable being copied back and forth,
and so nothing to fall out of step. Channel view uses the same widths, so
nothing under the divider moves when you switch — the mixer stays
scrolled where it was and one track's detail is shown instead of it, not
drawn over it: the strips aren't rendered while channel view is up, only
parked at the same position for when you switch back. That also means
channel view's track list is as wide as the mixer needs it to be rather
than as narrow as channel view could get away with.

Clicking a strip is a window hover rather than a background button: an
item on top of the background swallows the background's click, but
nothing can swallow the fact that the mouse went down inside the strip.
The track buttons go through the same function, `MX.click`, so a button
and the strip above it agree about what a ctrl-click means.

## Double-click means default

What "default" means is the caller's business, not the widget's: the
widget reports the double-click in its `act` table (or as a second return
value for the state buttons) and the caller decides.

## Run when REAPER starts: the command id

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

## Finishes: one tile for every colour

Each finish is one small seamless greyscale tile in `textures/`. At load
it becomes two images, the light grains as white-with-alpha and the dark
as black-with-alpha, so a plate of any colour takes it with plain alpha
drawing (ReaImGui has no blend modes). Bright and Satin are stretched over
the shape's box instead of tiled; Satin lays a brushed grain under itself
at half strength. Inside soft or round corners the tile is drawn in thin
horizontal strips cut to the rounded outline, so the cheap square path is
kept for square corners. The web page uses the same PNGs as CSS layers.

## One light

`TS_CV_Light.lua` owns the light (top left) and every shadow. Anything
standing on the panel gets a contact shadow (a tight dark outline, offset
half a pixel) and a drop shadow drawn as layers, widest and faintest
first; reach and softness grow with the thing's height, and View ▸ Shadows
scales the drop much more than the contact. Polygons (pointer bodies, the
chicken-head) take the layers from `LT.drop` and draw them in their own
shape. Highlights are fixed to the light, never to the knob's angle, which
is why a turning knob's turning parts are drawn separately from its
lighting.

## Knobs from parts

`TS_CV_KnobParts.lua` draws a knob from a parts table with DrawList
primitives only: stacked offset discs for bevels and lit faces, polygons
for flutes and pointers, radial strokes for knurls. Detail drops with
size: the number of discs and strokes is scaled to the radius, and skirt
numbers are left out under 12 px of skirt. A recipe is a `C.KNOB_STYLES`
entry with `parts`; a customised knob saves `Look<n>=k=v,...`
(`KP.encode` / `KP.decode`), and a concentric knob's inner one `Look2<n>`
and `Inner<n>`.

## Two windows, one library

ChannelView and the rack are two scripts with a library each. Every
change marks its key; `save()` first re-reads the file when the ExtState
rev (`maps_rev`, `steps_rev`) has moved, lays the marked keys on top,
writes, and bumps the rev. Each window checks the revs twice a second
(`M.sync`, `SC.sync`) and rescans when they move. A removal is marked too,
so the other window's save doesn't bring a deleted layout back.

## The rack's own keys

The rack is ChannelView run with `TS_CV_RACK = true`. Everything it keeps
apart is a prefix: folding (`rcollapsed:`, `rfold:`), macros and
modulators folding (`rack_`), panel visibility (`rack_<key>` against
ChannelView's `show_<key>`), the layout picked per instance
(`rvariant:`), the layout defaults (`*rack default layouts*`) and the bar
places (`rtop` …). A rack lookup with nothing of its own falls back to
ChannelView's pick and then ChannelView's default.

## Switches that say what they are

`ME.switch_reads_on` goes by the words first (On / Enabled / Active / In /
Yes against Off / Disabled / Inactive / Out / No, "Not …" flipping them)
and the value only when the text says nothing. A parameter named Bypass is
on when it reads off. Reading "off" as a substring is not enough: it
misses "Disabled", which many plugins use.

## Freezing around REAPER's freeze

REAPER's freeze takes every plugin up to the last one online, offline ones
included; only offline plugins after that point stay in the chain. So
setting the probes or ChannelView Modulators offline doesn't keep them out:
`FZ.freeze` moves them to just after the last plugin to freeze, then takes
everything after it offline for the action. The plugins it leaves come
back with new FX GUIDs, so they're found again by name and order
(`FZ.match`), and put back online only once a new `<FREEZE` block shows in
the track chunk (`FZ.poll`, every frame). A multichannel freeze prints
every channel the measuring taps widened the track to, so it's always
41223 (stereo).

The helpers' old slots are kept per freeze level in
`P_EXT:TS_CV_FREEZE2` (each level led by `\30`, entries `slot\31name` by
`\29`; an empty level for one with none, so the record counts the levels).
`FZ.sync` compares that count with the chunk's whenever the chain's shape
changes: an unfreeze from anywhere (REAPER's own, undo) puts the helpers
back. Like the probes' own moves, it makes no undo point: one would sit in
front of the unfreeze and make it unreachable.

## What a model misses

An EQ band's model (bell, shelf, cut…) is evaluated in closed form. What a
measurement shows beyond it is kept as `C<s>`: the measurement less the
band as the canvas would draw it at those settings, per gain setting, on a
third-octave grid about the band's frequency (median over the frequencies
measured; under 0.5 dB everywhere, not kept). It's computed after the
band's other tables, because "as drawn" depends on them (K ratios, the G
table). Drawing blends between the gains measured, scales in proportion
outside them, mirrors a side never measured, holds past the ends of the
measurement (20 Hz to 20 kHz about the band), smooths each row once on
decode ([1 4 1]) and goes through the points with Catmull-Rom. A cut's is
faded out from 6 to 18 dB down, where the measurement is mostly noise.
The web page gets the row at the band's current gain (`ci`, `cr`, `cg`)
and scales it while dragging.

A plugin-wide Model switch multiplies the entries: `<s>` counts shape
positions within model positions (`ME.slot`), and the model's parameter is
part of the band's learning signature, so naming one asks for learning
again.

Not every measurement is a shape. `ME.noise` is the median, over a
shape's gain rows, of the median second difference along the row: a real
band bends gently from one third-octave to the next (0.1 to 0.25 dB on
Kirchhoff-EQ's and Slick EQ's console types), while a measurement that
didn't line up with the plugin's output scatters (1.4 dB and more, seen on
a Pro-Q 4 learn whose frequency, Q and gain ratios came out at 0.19, 12
and 0.42). Over `ME.NOISE_MAX` (0.8): a plugin that reports its own values
keeps the shape's type and is drawn from its readings (K = 1, no C); a
learned-table EQ fails the learn and keeps what it had. The analyser
compares power spectra of what went in, delayed by the plugin's latency,
with what came out, so a wrong latency compares two different stretches of
noise; learning re-reads the copy's `pdc` before every step and measures
the reference again when it moves.

## Reading a plugin's colours

`TS_CV_PluginColours` floats the plugin's window (closing it again if it
opened it), brings it to the front, waits for it to paint (1.5 s when it
opened it, 0.4 s otherwise) and copies the plugin's own GUI off the screen
with GDI: the largest child window that starts below the top of REAPER's
window client area (the preset bar's controls are small and sit along that
top), else the client area less a 45 px bar, clipped to its monitor. About
160 × 160 points are sampled: surfaces are 5-bit-per-channel bins of at
least 1 % (near ones merged), accents are hue buckets of saturated, bright
pixels, each the average of its brightest core so anti-aliased edges don't
pull it toward the plate. The result goes in the layout's `Palette=` line.
Windows only: elsewhere the screen can't be read this way.

## Standard and Pro

ChannelView (TS_ChannelView.lua's @provides, the public TS-ReaScripts repo)
and ChannelView Pro (TS_CV_Pro.lua's @provides, a private repo with its own
ReaPack link) are two packages that must be the same release. ReaPack puts
them in Scripts/TS-ReaScripts/TS_ChannelView/ and
Scripts/TS-ChannelView-Pro/TS_ChannelView/; TS_CV_Edition adds both to
package.path as it loads, and Pro's own entry scripts add Standard's.

- `ED.PRO` is TS_CV_Pro's table when it's there and its RELEASE matches
  `ED.RELEASE`; a mismatch is ignored and named in the greyed items'
  tooltip. Bump both together.
- A Pro module is reached only through `ED.module(name, stub)`: nil, or the
  stub (`ED.stub`, every name a no-op) for modules called from many places.
  `ED.light()` and `ED.switches()` are the Light and Switches with plain
  stand-ins. A direct `require` of a Pro module outside an `ED.PRO` branch
  breaks Standard; TS_CV_StandardTest catches it.
- Pro menu items go through `ED.item` / `ED.menu`, which grey them with
  "(Pro)" and a tooltip without Pro.
- Widgets' `plain(o)` takes a control's style, look, cap colour and arc off
  without Pro, so a styled layout draws with the Arc knob and Flat button.
  The layout itself keeps them.
- `TS_CV_EDITION = "standard"` (a global set before anything loads) forces
  Standard: `lua5.4 dev/TS_CV_StandardTest.lua` loads every module in
  Standard's @provides with Pro's blocked, then checks what Standard does
  with a layout Pro made.
- One working copy holds both in REAPER's own folders. The Pro repo's
  `tools/split.sh` copies Pro's files into it and Standard's into a
  portable REAPER, and TS-ReaScripts' `tools/sync-from-reaper.sh` leaves
  out everything in the Pro repo's `pro-files.txt`.

## Compare: one container, and latency

A compare is one container, [A -> B -> switch], not two parallel
branches. A writes to a spare pair (3/4, or 5/6 when either plugin takes a
sidechain; the container then has 4 inputs and A's sidechain pins are
2/3), B to 1/2, and the switch reads both. Measured with a click through
an A of 480 samples' latency and a B of none: A's click arrives 0 samples
behind B's, because REAPER delays the channels a plugin passes through by
that plugin's latency. Parallel containers line up too, but their sum
peaked at 1.5 for a click of 1.0, so the single container stays.

## Learning's shared memory

TS_CV_Learn.jsfx and TS_CV_Learn.lua share gmem from 0x380000
(LN.BASE): the probes use blocks from 0x100000 and the Trimmer from
0x200000. A gain envelope (timing) is at +2000, 9000 points, with the
input level after it.

## Visual Options: where it keeps things

ExtState section `TS_ChannelView_Visual`: `tab_<cv|rack|tcp|web>` (each
tab's fields, `key=value;...`), `follow_<tab>`, `presets` (one per line,
`name<TAB>encoded`) and `rev`, bumped on every change; the other windows
(separate scripts) poll it twice a second and apply again. ChannelView's
Hue and Tint stay in the shared TS_Palette section. The TCP window's row
settings (tint, indent, indent_px, always, chips) are in its own section
and never followed. Faders & strips are kept in
TS_CV_TrackOps' ExtState lines, ChannelView's channel_w, REAPER's
trackgapmax; your presets copy them as g_* fields. Writing trackgapmax
needs SWS (SNM_SetIntConfigVar).

A control with no style draws as C.DEF (W.defaulted); the web page gets the
same defaults sent per control (o.st, o.cap, o.lit, o.kl, o.va) and the
panel settings as layout.vo.

## Lamps

T.lamp (TS_CV_FXTree; P.lamp is the same function, and the web bridge
sends it as lm per knob): per control, Lamp<n>=gr|gate|off. With none set on a layout (and
no canvas), the control whose name has "thresh" (or "ceil" for a limiter
or clipper) of a plugin that reports or measures gain reduction. A gate's
range is the most it has closed lately, held four seconds. ImGui's hover
rule matters for anything drawn over controls: an earlier item without
AllowOverlap keeps the hover, so the canvas offer is drawn before the
controls and they start under it.

## VU meters

TS_CV_VU (Pro). In and Out read TP.levels (rms for the needle, peak for the
lamp); a VU on in/out makes Taps' wants_levels true, one on gr makes
wants_measure true. The needle is an exponential with tau 65 ms (99% of a
step in 300 ms). The VU scale is a voltage scale from -20 to +3 VU (0 VU
about 0.69 across); GR runs 0 dB at the far right to 20 dB at the far left.
Changing the source syncs the track's taps at once (app.vu_set). The window
and the web bridge both lay taps from their own copy of the code: after an
update, one still running the old code lays them differently and the two
re-lay them in turn (levels come and go) until REAPER is restarted.

The line is Vu<n>=src|look|ref|peak|face|bstyle|stereo|hide (trailing
empty fields left off): look classic, dark, analogue or bar; face empty
(the look's own), "panel" or #RRGGBB; bstyle a C.BUTTON_STYLES key; "st"
for stereo (two meters from TP.levels_lr); "hide" for no In / Out / GR
buttons. On a Trimmer layout a VU reads TR.meters and the Trimmer's REF
and CEIL instead of probes. Analogue's glow is 64 rings widest first, each
adding what takes the light to the profile there; its corner shade is a
16 x 10 grid of AddRectFilledMultiColor (ring strokes left seams).

## Fonts

Visual Options > Text sets C.FONTS (text, head, bar). W.font_of makes each
font once per name and weight/slant and attaches it; PushFont with a nil
font only changes the size. The main window and the TCP window push "text"
for the whole frame; draw_header pushes "head" round the name; the toolbar
functions are wrapped in "bar". ImGui can't underline its own text, so
underline is drawn under what ChannelView draws itself.

## Draw-list splitters

A splitter is bound to the window it was first split in, and every
window's draw list can have the same address ("cannot use DrawListSplitter
over multiple windows"). A new one every frame trips newer ReaImGui's
"excessive creation of short-lived resources". P.split keeps one per
panel (fx GUID; this ReaImGui has no GetID), made again when ValidatePtr
says it was let go or Split refuses it (a panel in another window).

## Visualisers

A layout control Ctl<n>=-1|vis|0| with c.vis, its own canvas-like lines
after Vis<n>: Vis<n>Canvas (the kind), Vis<n>Role<name>, Vis<n>SatCal,
Vis<n>CanvasCol. An EQ curve (Ctl<n>=-1|curve|0|) with bands of its own
keeps a whole EQ canvas there (Vis<n>Band1, Vis<n>Learn1...); M.curve_cv
gives its own, else the layout's canvas. Kinds: filters, fstrip, cenv,
thresh, limit, drive, harm, scurve (M.SAT_KINDS share the saturator's
roles and SatCal), frange (ranges 2..M.FR_MAX as R<k><role>; Threshold
is shown as "Line" and takes any control), width, trimfilt (no roles:
the Trimmer's own filters). RP.draw_vis sets CP.vis_bare round the draw so
the canvas parts leave out their screens and frames. Learn takes job.cv
for a control's own canvas. Taps: frange wants the multiband split
(TP.set_mb), drive/harm/scurve/width want levels, width the stereo tap.

M.sat_bite: the input level where the learned fundamental has fallen 1 dB
(bite_of_gain), carried past the loudest level by its last slope up to
+12 dB; the curve-based knee is the fallback (it pinned on plugins whose
tone filters bend the curve).

## Act buttons

Act<n>=trim_auto|trim_listen: a Trimmer layout's Auto and Listen, drawn
by TRP.draw_act. P.own_trim(key) is true only for the Trimmer's Standard
layout; its other layouts are ordinary grids that start from
TR.starter_layout().

## TS_TrackProbe 2.4.0: stereo and levels per channel

Block 25 is tap_st (the stereo tap, 1..8); 122..124 its correlation, mid
and side; 125 is 1 on a probe that measures stereo. The scope is at
0x340000 (frame count, points, writer = track index + 2), 512 L/R pairs
from 0x340010; gmem[77] names the track allowed to write it. Levels per
channel: 0x350000 + (track index + 1) * 64 + tap * 8, peaks [0..3] (in L,
in R, out L, out R) then RMS [4..7], tracks to index 2999 (stops short of
Learn's 0x380000). Taps 5..8's traces and waveforms moved from 0x200000 /
0x208000 (inside the Trimmer's blocks, 0x200000 + (index + 1) * 256, up
to 0x301100) to 0x310000 / 0x318000; the probe says where at 0x4F000 + 9
and 0x5C000 + 7, and a reader seeing 0 there (an older probe) uses the
old places.

## Plugins that only say where they are

Some plugins (Sonimus A-Console) answer FormatParamValueNormalized with
the control's current text whatever value is asked, and their display
leaves the unit off ("0.20" shown, "0.20 kHz" given). UN.formatter sweeps
such a plugin (moving the control and reading it back) when the two texts
match or differ only by a unit, and puts that unit back on every plain
number it reads. While the plugin plays or writes automation it can't be
swept. Pro-C 3's Lookahead reads "0.000 ms" all along its range while its
Maximum Lookahead is off: CP's reads_flat places such a time along its
range instead.

## Measured latency, shared

TS_CV_Trace measures a tapped plugin's delay from the audio and the tap is
laid with it (TP.set_measured_lag). The window and the web bridge each
re-check the routing, so the measured lags go through ExtState
TS_CV_WEB/lags ("guid=samples,...", TP.lag_of); before that the bridge
laid the reported latency back each time the window laid the measured
one, and every rewrite of the tap record (P_EXT:TS_CV_TAPS, part of Track
Analyser's chain signature) made Track Analyser start over.

## Measured gain reduction, checked against real plugins (4.0)

A live rig (outside the repo, in D:\Projects\ConsoleRig: GRTest_Run.lua
and friends) runs a plugin on four tracks with the same audio: the
plugin alone (rendered), and copies between probe pairs laid as
ChannelView lays them, logging each copy's GainReduction_dB and each
probe's reading. The truth is the gain change in the renders (processed
against dry, 2 ms windows), with the plugin's zero taken from quiet pink
noise through a separate instance. 13 compressors and limiters, a mastered
mix and six stems:

- With the zero measured while stopped, TS_TrackProbe is within ±0.2 dB
  of the real gain change on every pass (0.1–0.3 dB rms offline). Plugins'
  own GainReduction_dB reads up to about 3 dB high (FabFilter, ReaLimit,
  SSL Bus Compressor 2, Weiss, API-2500), close on CLA-76, CL 1B and
  SSLComp. Hence measured first for reporting plugins.
- Without the stopped zero, dense material that's always compressed reads
  0.7–4 dB low: the zero learnt from the music never sees the plugin at
  rest. Material with gaps is fine.
- REAPER delays the channels a plugin doesn't use by the latency it
  reports, so a tap's "before" copy (written in front of the plugin, passing
  through it untouched) arrives in line with the "after" one. A tap lag of
  the reported latency put them out of line and read reduction that wasn't
  there. A lag is only for latency the plugin doesn't report (the trace
  measures it).
- Widening a track makes pins that were mapped past its channels live.
  Waves SSLComp and API-2500 (4 in, sidechain on 3/4) then key from silent
  channels 3/4 and stop compressing; unplugging those inputs fixes it
  (unplug_past, noted in the hold record and put back by release_holds).
- A new tab asks the audio device for whatever its template does; another
  rate can restart the device, and some interfaces then stay closed.

## Make-up gain, followed (TS_TrackProbe 2.5.1)

ChannelView writes each tapped plugin's make-up, in dB, to the probe
block every frame (tap_mugN at 26..29 / 58..61; a multiband tap's split
bands at 30..31 / 62..63), and the probe subtracts it from every ratio
before smoothing, the baseline, the zero and the third-octaves. Each slot
holds dB + 1000 * a count (0..99), one gmem write, so the value and its
meaning arrive together:

- Same count, new value: the plugin's make-up moved (the audio moved with
  it). The value can land a frame after the audio, so the music baseline
  rolls back to its snapshot from 64–128 ms before (TS_BSB), or is
  relearnt if it was only learnt since.
- New count: only what's subtracted changed (ChannelView started, the mark
  moved, a value stopped parsing as dB). The probe shifts everything it
  holds by the difference, so the reading doesn't jump. A new multiband
  split (tap_mb, tap_mbx) counts the same way inside the probe.

The window writes; the web bridge only when the window hasn't for 1.5 s
(ExtState mug_at), so two copies of the layouts never take turns. A moved
make-up that's followed isn't a touch (TP.touched with the parameter);
an older probe (no 126 flag) still gets the touch.

Offline (loose_eel, the probe's own code, with TS_TA_ProbeCalTest's
synthetic compressor): a measured zero, make-up stepped ±6 dB, ramped
+6 → −6 over 4 s, or −8 under constant compression, written a frame
late: within 0.05 dB of the true reduction afterwards, where 2.5.0 was
off by the whole move. The zero learnt from the music, ±6 dB: 0.02 dB.
A two-band split with the low band's gain dropping 6 dB: −0.2 dB on the
tap, −0.1 on the band. Every older test reads the same as 2.5.0.

## A spectrum per track, and the spectrum grab (TS_TrackProbe 2.6.0)

Every EQ canvas (ReaEQ, mapped, the role canvases) draws the track's own
spectrum, TP.spectrum(tr). Each call (once per track per frame) moves
field 127 of the track's probe block; while it moved within the last
second, the post probe runs its spectrum and writes it at 0x3A0000 +
(track index + 1) * 272: [0] a count moving with every frame, [1] bands,
[2] lowest and [3] highest frequency, [4] FFT size, [5] track index + 2,
[16..] dB per band. TP.spectrum takes it only while [5] is this track and
[0] moved in the last second, so the channel view, the rack and pop-outs
each see their own track. A probe driven only by ChannelView or the
Visualizer writes its Track Analyser block to a sink (0x4C0000), so it
can't overwrite the track Track Analyser is showing. With an older probe:
Track Analyser's POST spectrum, but only while it publishes this track
(pub_post on its block).

The grab (EQP.util.grab, called after a canvas's background button):
the pointer on the spectrum's line for 0.8 s shows the hold: anywhere
from 12 px below the live line to 12 px above the loudest it has been
since the pointer got there (the live line jumps with the music, so the
live line alone would keep restarting the wait). The hold is that
loudest, still building, drawn as a thick outline with a fill fading to
the foot, the live spectrum dimmed under it. Its peaks get nodes (local
highs above −70 dB standing 6 dB clear of the lowest point within 12
bands either side, the loudest 8, none within 8 bands of a louder one,
refined between bands by a parabola). Pressing within 10 px of a node
drags it: gain only, from the press point, ±EQ_GAIN_RANGE over half the
canvas. Let go at 0.5 dB or more: ReaEQ adds a bell there (add_node,
with the gain and Q corrected as for a double-click); a mapped canvas
takes its first band not in use, else the first turned off by its own
switch, that has frequency and gain and can be a bell (put_bell: into
use, a bell shape, frequency, gain, on; one undo point). None free:
"every band is in use", and nothing changes. The hold fades in over
0.2 s, and fades out over 0.35 s once the pointer has been away for half
a second: 60 px outside the span from the live line to the outline (no
node near), off the canvas or on a band's node. Back within the half
second, it stays; back while it fades, it fades in again. After a grab
it fades out at once and isn't shown again until it's waited for again. While it shows, the double-click preview is
hidden; a double-click still adds a band.

A dynamic EQ's panel on a mapped canvas (draw_dyn_box) shows only for
the band last clicked (ps.dopen: a press and release within 3 px on a
dynamic band's node); a click on that node again or on empty canvas
hides it. The panel takes its whole area as an item, so a click on it
isn't one on the canvas and the grab doesn't wake under it.

Offline (loose_eel, the probe's code, a 1 kHz tone): the per-track place
carries its peak at 1014 Hz, with Track Analyser's block untouched unless
published; the tap tests read the same as 2.5.1.

## A band alone: Solo, or the probe's listen

Every EQ canvas (EQP.util.solo; ReaEQ's and the mapped ones, small
curves too). A mapped EQ band's Solo control (Band<k>'s 8th field;
guessed from "... Solo", Pro-Q 3 and 4) or, without one (ReaEQ,
Kirchhoff-EQ), the track's post probe: a hovered band shows a headphone
button 22 px above its node (below, near
the top), for 0.6 s after the pointer leaves the node or the button.
Held, it soloes: the band's Solo switched on until it's let go, or
TP.listen each frame (TS_TrackProbe 2.6.0, LISTENING TO A BAND: [6..9]
of the track's place at 0x3A0000; the probe lets go a quarter of a
second after the count stops). What's heard without a Solo: two
band-pass sections at the band's frequency and Q (at least 0.5), or
below the frequency for a low cut or low shelf, above it for a high cut
or high shelf; the canvas shades it. The listen is offered only where
the probe writes its own spectrum (TP.can_listen), i.e. a 2.6.0 probe
while the canvas is drawn. Kirchhoff-EQ has no Solo (its paramdump: 28
controls a band, none a solo), so it listens through the probe.

Guess from names keeps the learning of a band on the same frequency and
gain controls (CS.keep_learned): its learning signature leaves Slope and
Solo out, so adding them doesn't ask for learning again. A first guess
takes 16 numbered bands (ME.GUESS_BANDS).

Offline (loose_eel, the probe's code, 100 Hz + 5 kHz at 0.5 each): the
band about 5 kHz, Q 2: 0.000 / 0.500; about 100 Hz: 0.500 / 0.000;
below 1 kHz: 0.500 / 0.001; above it: 0.000 / 0.499; the count stopped:
both 0.500 again.

## A new band on a mapped EQ canvas

As on ReaEQ's: hovering empty canvas shows a faint band of the shape a
double-click adds there (RQ.infer_type by frequency: low cut, low shelf,
bell, high shelf, high cut; a cut at 0 dB, the rest at the pointer's
gain). A double-click puts it in the next free band (free_band: not in
use, else off by its own switch; one with that very type among its
shapes first, else its family; frequency, and gain unless it's a cut),
one undo point. None free: "every band is in use". A spectrum grab takes
a bell the same way.

## The EQ canvases on the web page

- Both canvases (ReaEQ's, a mapped EQ's) draw the track's own spectrum
  (vals.sp, from TP.spectrum: the bridge keeps it asked for while an EQ
  canvas is shown). vals.ls: a band can be heard through the probe.
- Spectrum grab by touch (specGrab): hold an empty spot still (12 px)
  for half a second; the spectrum held, the loudest since, with peak
  nodes; it stays after the finger lifts. Drag from a node: gain from
  where it's touched; let go at 0.5 dB or more: mqadd|guid|hz|db|bell (a
  mapped EQ) or eqadd|guid|hz|db|2 (ReaEQ). A tap elsewhere or 8 s
  untouched hides it.
- Double-tap empty canvas: mqadd with the family for where it is (the
  bridge: ME.infer_fam, ME.free_band, ME.put_band; "Every band is in
  use" when none is free), or ReaEQ's eqadd. A faint band of that type
  shows while the finger is down.
- Stereo placement: each band's pl (l, r, m, s) and sti; the layout's
  st (the settings' names). A tag on the node's left (a tap: mqst to the
  next setting), a picker in the strip, a curve per placement as on the
  desktop.
- Solo: a headphone button in the strip (a band with its own Solo, or
  vals.ls). Held, it sends mqsolo|guid|band|1 (eqsolo|guid|type|index|1
  for ReaEQ) every 120 ms, 0 on letting go; the bridge's TP.listen_hold
  switches the band's Solo on, or listens through the probe each cycle
  (TP.listen_tick), and lets go 0.35 s after the messages stop.

## Stereo placement of EQ bands

A band's Stereo placement control (Band<k>'s 9th field; guessed from
"... Stereo Placement": Pro-Q 3 and 4, Kirchhoff-EQ, also in the known
plugins' bands) is read by name each frame: Left, Right, Mid, Side, or
anything else (Stereo) for none. A placed band shows its letter in a
tag on its node's left (a stereo one a faint "St" while the node or tag
is hovered); a click steps it round the control's settings
(ME.live_positions), and the right-click menu lists them. With any band
placed, the curve is the stereo bands' alone, and each placement in use
has a curve of its own in its colour (PLACE_COL: left, right, mid,
side): the stereo bands plus its own.

## Long shape lists, by model

ME.shape_groups groups a band's shapes when there are 8 or more and two
or more start with the same word that isn't a shape word (Low, High,
Flat, Band, Tilt, All, Bell...): Kirchhoff-EQ's 47 types come out as
Standard (the unprefixed ones, first), E, G, BritN, 250, VT, Tone, Wall,
Allpass and Blue. Pro-Q's ten stay one list. The node's right-click menu
shows a submenu per group, the one in use naming its shape; the web page
gets each setting's group (shg) and its name without the model, and its
picker uses an optgroup per group.

## Console setup (Pro)

- Each console is a description in TS_CV_Consoles.lua (CO.LIST): its
  channel and buss plugins (found by name), which parameters are its type,
  drive, in, group and channel number, its target level and its slot.
  Parameters are found by name and kept per FX GUID (CO.param), never by
  index: Sonimus's Buss module has fewer parameters than its Channel.
- Sonimus keeps its module (Channel / Buss), its group and the group
  settings in its saved state, not in parameters. TS_CV_ConsoleState reads
  the JUCE XML out of REAPER's VST3 chunk and writes an edited one back,
  fixing every size field that counts it (REAPER's header, which holds the
  pin maps and can wrap onto more lines; the component length; the bank's
  byte and chunk sizes; JUCE's XML length). An unedited block round-trips
  byte for byte. A rewritten Buss needs its own paramAttachments
  (CO.SONIMUS_BUS_ATTACH) or it has no parameters. A group's settings live
  in one Buss's <MasterGrouping> and only group that console's own
  instances.
- NLS: setting Bank loads a preset and puts the instance back in VCA group
  1, so Bank goes first and the group after. Its VCA controls set from
  outside are ignored (only the plugin's own AUTO instance takes them);
  every instance is switched through its own Studio, Bypass and Drive.
  Drive adds level, so its Output (Trim on the Buss) is set to minus the
  measured make-up (CO.NLS_MAKEUP) to keep in and out level.
- VCC: a module joining an occupied group takes the group's Console,
  Drive and Input (with Group I/O on), so Group I/O goes off before it
  joins. Setting every VCC parameter in turn, and opening a new project tab
  while VCC is loaded, have both crashed REAPER: nothing sweeps its
  parameters.
- The Analog Molecule's Flavor and Link aren't set: its Link is
  overwritten by its own shared memory every block. A type is set as the
  Flux / Thermal / Analog values the flavour applies (CO.TAMD_FLAVOURS).
  The Hot Summer's buses send to their stem's channel pair on SUM with
  their master send off.
- Levels for gain staging come from CalculateNormalization over each item's
  stretch of its source, which reads the whole stretch: slow on a long
  file, so each is kept per source and stretch in the project
  (TS_CV_con_levels) and Console setup measures one track a quarter second
  apart.
- Console setup asks a lot every frame (each row's stage, in, number). The
  slow answers are kept: whether a plugin is installed (EnumInstalledFX
  searched once per name), whether the first slot is ARA (that needs the
  track's state chunk, which every plugin on it has to write out; kept
  until the first slot's FX GUID changes) and NLS's own Bypass among its
  three.
- Console setup's picks wait in st.choice until Apply.

## MIDI envelopes and trigger tracks

- Envelope, Envelope × velocity and Duck are MIDI Source 5–7. ChannelView
  Modulators had no sliders to spare (REAPER's limit is 256), so they keep
  their settings in the Follower's fields, which a MIDI modulator otherwise
  doesn't use: Attack, Release, Floor as Sustain (-80..0 dB is 0..100 %),
  Ceiling as Decay (-60..12 is 0..2000 ms, squared), Gate as Exp curve,
  Hold as Legato. The rack and the web page show them under those names
  (MD.sustain_of, MD.decay_of and back).
- The envelope runs at block rate in @block, after the MIDI has been read
  (the MIDI loop comes before the modulators, so a note acts in its own
  block). Linear stages step by the block's length; Exp curve approaches
  the target with exp(-6.9 t / T), about -60 dB over the stage's time.
- A trigger track is a MIDI-only send (I_SRCCHAN -1) onto MIDI bus 8 + j
  of this track (I_MIDIFLAGS dest bus at >> 22). The plugin sets
  ext_midi_bus, reads midi_bus, and for a modulator whose bit is set in
  slider 250 (Trigger tracks) takes only that bus's notes and passes none
  of them on. MD.trigger finds the send by its bus; CO.roles counts only
  audio receives, so a trigger doesn't make a track a return.
- The JSFX was checked outside REAPER with WDL's loose_eel: its @init and
  @block, with slider() turned into memory and midirecv_buf / midisend_buf
  stubbed, stepped through notes for each source.

## Folder borders

- C.fold_bw() (ExtState fold_borders / fold_bw, read every second, so the
  web bridge follows it). MX.tracks gives each row lbars (outermost first)
  and rbars (innermost first): the folders whose first and last shown track
  it is, with tracks hidden from the mixer passed over. The bar against a
  strip runs under it by the strip's rounding, and MX.fold_edges paints
  over the strip's outline on that side, so the two meet with no gap.

## Plugins ChannelView knows: ReEQ2

- ReEQ2 (a JSFX) gives the host its sliders' own numbers: frequency 0..104
  for 10 Hz x 2205^(x / 100), Q 0..100 for 0.1 x 400^(x / 100), slope
  steps of 6 dB/oct. M.known_ranges gives any ReEQ2 layout (saved or
  default) ranges for them and for gain and the dynamics, where it has
  none of its own, so its controls read in their units everywhere
  (U.fmt_value, UN.formatter).
- ME.builtin maps its 16 bands (parameter numbers in M.REEQ2, checked
  against the names) with a learn line that's D=1 (the canvas uses the
  readings) and X=1 (its types are its own: the shape names don't
  override them). M.known_ranges also puts that line on any band of a
  ReEQ2 layout mapped the same way, so a change to the recipes reaches
  canvases already made.
- Its types are modelled from its own recipes
  (Dependencies/reeq-analog-adapter.jsfx-inc ri_recipe, drawn by
  ivantsov_filter's ivf_sec_amag): cuts with every second-order section at
  Q (hpq, lpq) or Butterworth (hpbw, lpbw), a tilt of a full shelf each
  way (rtilt), Pultec Low (a low shelf at 1.5 f and a dip there of
  Q / 40 x the boost, to 10 dB), Vintage Lo (a low shelf at 1.25 f and a
  first-order low cut at f), Vintage Hi (a high shelf and a second-order
  high cut at 22 kHz when boosting, f x (1 + 3.25 t) when cutting,
  t = 1 + gain / 12). The test rebuilds its curves from those recipes and
  compares. ME.FAMILY says which plain type each behaves like for focus,
  spans and gain nodes.
- Mode has three settings: Off (ME.find_used: the band unused), Disabled
  (off), Enabled. Turning a band off sets Disabled; a double-click sets
  Off.
- Learn runs inside the layout's ranges (CanvasSetup round LN.step), so a
  plugin given custom ranges in Hz, dB and Q learns the quick way.

## Plugins ChannelView knows: ready canvases (M.KNOWN)

- M.KNOWN lists the plugins whose canvas comes ready, by the layout key's
  plugin (`base`, or `find` in it): ReEQ2, Pro-Q 3 and 4, Kirchhoff-EQ
  (EQ); Pro-C 2 and 3, Cenozoix Compressor (compressor).
- A plugin with no layout of its own gets its canvas in its generated
  default (M.known_default, Pro): an EQ's alone, a compressor's with the
  plugin's other controls beside it. An EQ only once its learning is
  known.
- EQ bands by name (TS_CV_MapEQ KNOWN_EQ): the first 16 bands, each field
  the band's name start plus the rest ("Band 1 " + "Frequency"; Kirchhoff
  "Band1 " + "Freq."), and the plugin told apart by a name only it has.
  Each carries the plugin's Learn line, taken once from learning a band
  (every band alike): Pro-Q 3's and 4's, and Kirchhoff-EQ's 47 types with
  their measured shapes (its latest learning, 7 Nov).
- Compressors by parameter number, each role's name checked
  (M.known_comp), with ThrCal / AtkCal / RelCal from measuring once:
  Pro-C 2's and 3's threshold, attack and release; Cenozoix's threshold
  and attack (the Compressor 2 layout's, its Dry Mix reversed).
- M.known_learned gives a layout of theirs made before what it lacks: an
  EQ band on frequency and gain not learned gets the learning; a
  compressor whose threshold or attack is on the same control gets its
  measuring. Canvas setup's guesses come from the same (CS.guess, and
  Guess from names keeps a band's own learning only when the guess has
  none).
