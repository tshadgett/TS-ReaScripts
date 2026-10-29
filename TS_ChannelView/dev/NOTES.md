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
