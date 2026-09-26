-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Mixer.lua -- the mixer view, and the track row underneath it.

  The other half of this window. Channel view is one track's plugins in
  depth; mixer view is every track's channel at a glance, and the two
  share the same strip: a mixer strip here IS CH.draw_body, the same code
  that draws the pinned Channel panel, given a different id prefix and a
  different track.

  That is the whole design. A second implementation of a fader, a meter
  and a mute button would drift from the first within a week -- and it is
  the same fader taper, the same peak hold, the same swipe, the same
  double-click-for-default, because it is the same function.

  Which tracks appear: those REAPER shows in ITS mixer (B_SHOWINMIXER),
  plus the master. Hiding a track from the mixer is a statement about
  where you want to see it, and this is a mixer.

  The track name row along the bottom is drawn HERE too, by the same
  MX.draw_row that draws the strips, in both views -- not by a second
  module keeping its own scroll position in step with this one. Two
  windows with two independently-tracked scroll offsets, synced by hand,
  is exactly the kind of thing that looks done until someone finds the
  one gesture that wasn't: the wheel not reaching a strip's own child
  window, the wheel not being handled at all on the row underneath. Both
  were real bugs, both lived in the sync code, and the fix that actually
  closes the class of bug is to stop having two scroll positions. One
  BeginChild, one id ("trackrow"), used by both views -- ImGui remembers
  a window's scroll position on its own, for free, which is a better
  guarantee than any variable we could write and maintain by hand. In
  channel view the same window draws just the name buttons, at the
  scroll position mixer view left it at.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local CH = require("TS_CV_Channel")

local St = require("TS_CV_State")
local G  = require("TS_CV_Gang")

local MX = {}
local ImGui

function MX.attach(imgui) ImGui = imgui end

-- Set by TS_CV_TrackStrip.request_scroll() when the selection changed
-- from outside this window (the arrange view, the track manager). Read
-- and cleared here, in channel view only, the same as before the merge
-- -- the mixer doesn't chase a selection made elsewhere, only the one
-- track list does.
MX.scroll_to_sel = false

-- How wide this track's column is, in BOTH views. Channel view has no
-- mixer to line up with, but the buttons keep these widths anyway: a
-- track strip that changes shape when you switch views would undo the
-- point of them being the same object.
function MX.col_width(guid)
  return CH.width(St.is_collapsed("mx:" .. guid))
end

-- ---------------------------------------------------------------------
-- which tracks
-- ---------------------------------------------------------------------

-- The master first, the way every console puts it somewhere fixed rather
-- than in the running order. `guid` is the collapse key and the widget-id
-- prefix; a track pointer would do for neither, since it changes across
-- a reopen and cannot be written into an id. `num` and `name` are the
-- name button's label too, now that one loop over this list draws both
-- the strip and the button under it -- no second, separate re-read of
-- the track's name and colour for the row underneath.
function MX.tracks()
  local out = {}
  local master = reaper.GetMasterTrack(0)
  if master then
    out[#out + 1] = { track = master, num = 0, name = "MASTER",
                      guid = "master", col = U.track_colour(master, 0xff) }
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if MX.in_mixer(tr) then
      local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      nm = U.trim(nm)
      out[#out + 1] = {
        track = tr,
        num   = i + 1,
        name  = (nm ~= "") and nm or ("Track " .. (i + 1)),
        guid  = reaper.GetTrackGUID(tr) or ("t" .. i),
        col   = U.track_colour(tr, 0xff),
        space = (reaper.GetMediaTrackInfo_Value(tr, "I_SPACER") or 0) > 0.5,
      }
    end
  end
  return out
end

-- REAPER answers 0 or 1; a track with no opinion is shown.
function MX.in_mixer(tr)
  if not tr then return false end
  local v = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER")
  if v == nil then return true end
  return v > 0.5
end

-- ---------------------------------------------------------------------
-- selection
-- ---------------------------------------------------------------------

-- The guid of the track the last click landed on, ignoring shift-clicks
-- themselves. Shift-click reaches back to it, the way a list does
-- everywhere -- so shift after shift re-draws the range from the same
-- end rather than walking it along.
MX.anchor = nil

-- Selected as REAPER understands it, not as this window remembers it.
-- One definition, in TS_CV_Gang, because the gang and the highlight
-- have to mean the same thing by "selected" or the strips you can see
-- lit would not be the strips an edit reaches.
function MX.selected(tr) return G.is_selected(tr) end

-- Clicking anywhere on a strip -- the meter and the fader included --
-- selects its track. On a console the strip IS the track; having to
-- find a patch of background first is a computer idea.
--
-- Ctrl (or Cmd) adds and removes one, Shift takes everything from the
-- last plain click to this one. Both are what every list does, and what
-- REAPER's own mixer does.
-- Nothing selected. Clicking the background of a list clears it
-- everywhere else, and a mixer is a list.
function MX.clear_selection()
  reaper.Main_OnCommand(40297, 0)          -- Track: Unselect all tracks
  MX.anchor = nil
  reaper.UpdateArrange()
end

function MX.click(track, guid, mods)
  if not track then return end
  local ctrl  = (mods & ImGui.Mod_Ctrl) ~= 0 or (mods & ImGui.Mod_Super) ~= 0
  local shift = (mods & ImGui.Mod_Shift) ~= 0

  if ctrl then
    local on = MX.selected(track)
    -- Never down to nothing: channel view has to have a track to show,
    -- and an empty selection is a state you can only get out of by
    -- clicking something, which is what you were already doing.
    if on and reaper.CountSelectedTracks2(0, true) <= 1 then return end
    reaper.SetTrackSelected(track, not on)
    if not on then MX.anchor = guid end

  elseif shift and MX.anchor and MX.anchor ~= "master" and guid ~= "master" then
    local list = MX.tracks()
    local a, b
    for i, t in ipairs(list) do
      if t.guid == MX.anchor then a = i end
      if t.guid == guid      then b = i end
    end
    if a and b then
      if a > b then a, b = b, a end
      reaper.Main_OnCommand(40297, 0)          -- Track: Unselect all tracks
      for i = a, b do
        if list[i].guid ~= "master" then
          reaper.SetTrackSelected(list[i].track, true)
        end
      end
    else
      -- The anchor has been hidden or deleted since. Fall back to a
      -- plain click rather than guessing at what the range meant.
      reaper.SetOnlyTrackSelected(track)
      MX.anchor = guid
    end

  else
    reaper.SetOnlyTrackSelected(track)
    MX.anchor = guid
  end
  reaper.UpdateArrange()
end

-- ---------------------------------------------------------------------
-- the name button
-- ---------------------------------------------------------------------

-- One coloured track button, drawn rather than themed so the track colour
-- can be the fill while the label stays readable over it. Fixed width --
-- the row should read as a row of equal slots like a console, not jump
-- about with the length of each track's name. Used both under a strip
-- (mixer view) and on its own (channel view): the same object either
-- way, so it had better look and answer like one.
local function name_button(ctx, label, col, selected, id, w)
  local h = C.STRIP_H - 8
  local dl = ImGui.GetWindowDrawList(ctx)
  local tw, th = ImGui.CalcTextSize(ctx, label)

  local x, y = ImGui.GetCursorScreenPos(ctx)
  local pressed = ImGui.InvisibleButton(ctx, "tsname" .. id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)

  -- Always full strength, the same as the strip header above and the
  -- TCP itself: a track's own colour is never faded for being
  -- unselected. Selection reads from the outline below, not from how
  -- saturated the fill is.
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, col, C.STRIP_ROUND)
  -- Inset by half the stroke, the same as the strip above: centred on
  -- the bounds it would spill outwards, and the clip rect would eat the
  -- spill on one side only.
  local lw = selected and 2.0 or 1.0
  local o  = lw * 0.5
  ImGui.DrawList_AddRect(dl, x + o, y + o, x + w - o, y + h - o,
    selected and U.sel_colour(C.SEL_OUTLINE, col, C.COL.strip_sel)
              or C.COL.panel_border,
    C.STRIP_ROUND, 0, lw)

  -- Picks its ink from THIS button's own fill, unconditionally, the
  -- same as strip_header does above -- not only while selected. That
  -- was fine reasoning back when an unselected fill was dimmed towards
  -- the background and a fixed light ink read against almost anything;
  -- now that a track's colour is always full strength, a light colour
  -- (a bright yellow, say) needs dark ink whether or not it happens to
  -- be selected right now.
  local text_col = U.contrast_text(col)
  local clip = w - 10
  local shown = label
  if tw > clip then
    local k = #shown
    while k > 1 do
      k = k - 1
      local t2 = shown:sub(1, k) .. "."
      tw = ImGui.CalcTextSize(ctx, t2)
      if tw <= clip then shown = t2 break end
    end
  end
  ImGui.DrawList_AddText(dl, x + w * 0.5 - tw * 0.5, y + h * 0.5 - th * 0.5, text_col, shown)

  W.tip(ctx, "tsname" .. id, label, hovered, false)
  return pressed,
         hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left)
end

-- The label a name button shows: "3  Kick Drum", or just "MASTER" --
-- MX.tracks() already worked this out (num is 0 for the master), so
-- there is nothing left to re-derive here.
local function track_label(t)
  if t.num > 0 then return ("%d  %s"):format(t.num, t.name) end
  return t.name
end

-- ---------------------------------------------------------------------
-- one column (mixer view: strip + its name button; channel view: the
-- name button on its own)
-- ---------------------------------------------------------------------

local function strip_header(ctx, dl, x, y, w, t, selected, hovered)
  local h = C.HEADER_H
  -- The track's own colour IS the header, not a stripe on it, always at
  -- full strength -- the same as the TCP, which never fades a track's
  -- colour for being unselected. Selection is the outline's job, not
  -- the fill's.
  local base = t.col or C.COL.header_bg
  -- Rounded at the top to the same radius as the strip, so the header
  -- is a cap ON the strip rather than a rectangle laid across it --
  -- matching STRIP_ROUND here keeps the header's corners and the
  -- strip outline's rounded corners in agreement.
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, base, C.STRIP_ROUND,
                               ImGui.DrawFlags_RoundCornersTop)
  ImGui.DrawList_AddLine(dl, x, y + h, x + w, y + h, C.COL.panel_border, 1.0)

  local btn = C.ICON_SIZE
  local aw  = C.AUTO_BTN_W
  -- The automation button lives here too. Mixer view is where you set
  -- these across a session, so leaving it to channel view would mean
  -- visiting every track to do what the row is for.
  local room = (w - btn - aw - 14 > 8)

  if C.MIX_STRIP_NAME then
    local label = track_label(t)
    local avail = w - btn - 10 - (room and (aw + 4) or 0)
    local tw, th = ImGui.CalcTextSize(ctx, label)
    while tw > avail and #label > 1 do
      label = label:sub(1, #label - 1)
      tw = ImGui.CalcTextSize(ctx, label)
    end
    -- Readable on any track colour, which is the one thing a
    -- user-chosen background cannot be trusted to allow. The header is
    -- always at full track colour now (not just when selected), so the
    -- text has to be judged against that colour unconditionally --
    -- there is no dimmed, colour-neutral state to fall back to a fixed
    -- light text for any more.
    ImGui.DrawList_AddText(dl, x + 5, y + (h - th) * 0.5,
      U.contrast_text(base), label)
  end

  ImGui.SetCursorScreenPos(ctx, x + w - btn - 3, y + 3)
  if W.icon_button(ctx, "mxc" .. t.guid, "collapse", btn, false,
      "Collapse this strip") then
    CH.set_collapse("mx:" .. t.guid, t.track, true)
  end

  if room then
    CH.auto_button(ctx, x + w - btn - aw - 8, y + 3, aw, h - 6,
                   t.track, "mx" .. t.guid)
  end
end

-- A collapsed strip is the Channel panel's collapsed bar, the same way
-- an expanded one is its body: the expand button, mute and solo, and the
-- meter with the ghost fader laid over it. Writing a second one here is
-- how the pinned panel ended up with a fader on its collapsed bar and
-- the mixer did not.
-- Returns true when the meter (that is, the ghost fader over it) was
-- clicked rather than dragged, which on a collapsed strip means "this
-- track": there is nothing else down there to click.
local function strip_collapsed(ctx, dl, x, y, w, h, t, selected)
  -- Always full strength, same as the expanded header -- see strip_header.
  local base = t.col or C.COL.header_bg
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + 4, base, C.STRIP_ROUND,
                               ImGui.DrawFlags_RoundCornersTop)

  return CH.draw_collapsed(ctx, dl, x, y, w, h, t.track,
                           "mx" .. t.guid, "mx:" .. t.guid)
end

-- Draws one column: the strip (full or collapsed) plus its name button
-- underneath, both inside the one child this column gets. `avail_h` is
-- the WHOLE column height, strip and name button together.
-- Returns the track to open in channel view (the strip's own body was
-- double-clicked), and the track a name-button double-click wants opened
-- -- which may be the same track, or nil, independently.
local function column(ctx, t, avail_h, cur_track)
  local collapsed = St.is_collapsed("mx:" .. t.guid)
  local w = MX.col_width(t.guid)
  -- Selected as REAPER sees it, so a multi-selection lights every strip
  -- in it -- with the track channel view is showing always lit, even on
  -- the master, which REAPER does not always report as selected.
  local selected = MX.selected(t.track) or (t.track == cur_track)
  local open_it, dbl_name = nil, nil

  -- The name button's own fixed-height slot at the bottom of the
  -- column -- the same STRIP_H the track row used on its own before the
  -- merge, with the button itself STRIP_H - 8 tall and a 4px gap above
  -- it so it isn't jammed against the strip.
  local name_h    = C.STRIP_H
  local name_gap  = 4
  local strip_h   = math.max(0, avail_h - name_h)

  local col_x, col_y = ImGui.GetCursorPos(ctx)
  local ok = ImGui.BeginChild(ctx, "mx##" .. t.guid, w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww = w
    -- Only for dimming the header -- selection is decided by item
    -- hover below, deliberately.
    local over = ImGui.IsWindowHovered(ctx)
    local sel_col = U.sel_colour(C.SEL_OUTLINE, t.col, C.COL.strip_sel)

    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + strip_h,
      selected and C.COL.header_drag or C.COL.panel_bg, C.STRIP_ROUND)

    -- The strip's background is both the select target and the
    -- double-click target, submitted BEFORE the controls so every one of
    -- them sits on top of it.
    --
    -- Which is the point: GRABBING A CONTROL MUST NOT SELECT THE TRACK.
    -- That is how REAPER behaves and it is the only behaviour that
    -- works -- select three tracks to gang them, reach for a fader, and
    -- a select-on-touch would throw the other two away before the move
    -- even started. So the test is item hover, not window hover: a knob
    -- or a fader under the pointer swallows the click and the selection
    -- stays as it was. Everything that is NOT a control -- the header,
    -- the meter, the space around things -- falls through to here.
    ImGui.SetCursorScreenPos(ctx, x, y)
    W.allow_overlap(ctx)
    ImGui.InvisibleButton(ctx, "mxbg" .. t.guid, ww, strip_h)
    if ImGui.IsItemHovered(ctx) then
      if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
        open_it = t.track
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
        MX.click(t.track, t.guid, ImGui.GetKeyMods(ctx))
      end
    end

    if collapsed then
      if strip_collapsed(ctx, dl, x, y, ww, strip_h, t, selected) then
        MX.click(t.track, t.guid, ImGui.GetKeyMods(ctx))
      end
    else
      strip_header(ctx, dl, x, y, ww, t, selected, over)
      CH.draw_body(ctx, dl, x, y + C.HEADER_H, ww, strip_h - C.HEADER_H,
                   t.track, "mx" .. t.guid)
    end

    -- The outline goes on LAST, over the header, or the header paints
    -- out the two corners the outline had just rounded.
    --
    -- And it is inset by half its own thickness. ImGui centres a stroke
    -- on the path it is given, so a rect drawn ON the child's bounds
    -- spills half a line-width past them on every side -- except that
    -- the child's clip rect eats the spill on the right and the bottom
    -- and not on the left and the top. That asymmetry is the extra
    -- pixel down the left-hand edge. Inset, the whole stroke is inside
    -- the strip and every edge weighs the same.
    local lw = selected and 2.0 or 1.0
    local o  = lw * 0.5
    ImGui.DrawList_AddRect(dl, x + o, y + o, x + ww - o, y + strip_h - o,
      selected and sel_col or C.COL.panel_border, C.STRIP_ROUND, 0, lw)

    -- The name button, in its own slot right below -- same object, same
    -- click semantics as the strip above it, drawn by the one function
    -- channel view also uses for this button on its own.
    ImGui.SetCursorScreenPos(ctx, x, y + strip_h + name_gap)
    local nb_hit, nb_dbl = name_button(ctx, track_label(t), t.col or C.COL.header_bg,
                                       selected, t.guid, ww)
    if nb_hit then MX.click(t.track, t.guid, ImGui.GetKeyMods(ctx)) end
    if nb_dbl then dbl_name = t.track end

    ImGui.EndChild(ctx)
  else
    W.child_skipped(ctx, w, avail_h, col_x, col_y)
  end
  return open_it, dbl_name
end

-- ---------------------------------------------------------------------
-- the row
-- ---------------------------------------------------------------------

-- The padding+scrollbar height "trackrow" reserves along its bottom
-- edge -- ALWAYS, not only on a frame the row's content actually
-- overflows. A constant reserved every frame is what keeps mixer view,
-- channel view, and successive frames from ever disagreeing about the
-- row's height; a comparison that only reserved the height when content
-- genuinely overflowed would have to probe for that, and a probe taken
-- from inside "trackrow" itself inherits whatever horizontal scroll the
-- row is already at, which is not a stable thing to measure from.
--
-- WindowFlags_AlwaysHorizontalScrollbar (below, and on "trackrow" itself
-- in MX.draw_row) makes REAPER's scrollbar show unconditionally, overflow
-- or not, so the reserved strip is always what gets drawn there -- never
-- empty space with nothing to explain it. WindowFlags_HorizontalScrollbar
-- still has to stay alongside it: that's the flag that turns horizontal
-- scrolling on at all, and Always* only changes ImGui's answer to "show
-- it or not", not whether the machinery exists to ask.
--
-- There's no GetStyleVar to ask for this height directly, so it's
-- measured empirically: one throwaway child window, using the same
-- Always* flag as the real row, reports exactly what the always-visible
-- scrollbar costs from its very first frame.
--
-- Called exactly ONCE per frame -- see MX.draw_row below, which takes
-- this value as a parameter rather than measuring it again itself. The
-- id ("mxpadprobe") is a stable, reused child window, and calling
-- BeginChild with the SAME id a second time in the SAME frame is
-- undefined, the same as reopening any window twice in one frame would
-- be -- so this is measured exactly once and threaded through as a
-- parameter rather than re-measured at each call site.
--
-- `pad_x` is trackrow's own horizontal WindowPadding, measured once in
-- TS_ChannelView.lua off the main window (nothing ever pushes a
-- different one ahead of it) and handed down -- this probe pushes it
-- right back, unchanged, alongside C.TRACKROW_PAD_Y, so what it measures
-- is what trackrow itself will actually get, not ReaImGui's default.
function MX.row_pad_y(ctx, pad_x)
  local pad_y = C.CHILD_PAD_Y_FALLBACK
  local probe_x, probe_y = ImGui.GetCursorPos(ctx)

  -- Pushed before BeginChild, like any style var -- and popped
  -- unconditionally below, whether or not BeginChild itself returns
  -- true, since the push happened regardless of that.
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, pad_x, C.TRACKROW_PAD_Y)
  local ok = ImGui.BeginChild(ctx, "mxpadprobe", 40, 100, 0,
    ImGui.WindowFlags_HorizontalScrollbar | ImGui.WindowFlags_AlwaysHorizontalScrollbar
    | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    -- No overflow to fake any more -- AlwaysHorizontalScrollbar means
    -- this child's own scrollbar is already showing on this very first
    -- read, not "as of whatever it overflowed by last frame", so there
    -- is nothing left that a Dummy submitted afterward would have been
    -- protecting this read from.
    local _, h = ImGui.GetContentRegionAvail(ctx)
    pad_y = 100 - h
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleVar(ctx)
  ImGui.SetCursorPos(ctx, probe_x, probe_y)

  return pad_y
end

-- Draws the whole track row: strips and their name buttons in mixer
-- view (`strips` true), just the name buttons in channel view (`strips`
-- false) -- one BeginChild either way, same id, so the scroll position
-- is one thing, not two kept in step.
--
-- `pad_y` is MX.row_pad_y's own result, measured ONCE by the caller
-- (TS_ChannelView.lua, every frame, before either view branch) and
-- handed in here rather than measured again -- see row_pad_y's own
-- comment for why the same "mxpadprobe" id can't safely be measured a
-- second time in one frame. It also can't be measured from inside
-- "trackrow" itself: nested inside a row that scrolls horizontally, an
-- ordinary probe child sits at content-x 0 -- exactly where the row
-- starts and exactly what scrolls out of view first -- so scrolling the
-- row past the probe's own width would clip it like any other
-- fully-clipped child and return a wrong measurement. Taking pad_y as a
-- parameter avoids both: it is measured once, outside "trackrow", and
-- threaded down to wherever it's needed.
--
-- `pad_x` is the same horizontal WindowPadding row_pad_y's probe was
-- handed, pushed here around this BeginChild too -- see row_pad_y's own
-- comment on `pad_x` for where it comes from. Both push the identical
-- (pad_x, C.TRACKROW_PAD_Y) pair, which is what keeps pad_y (measured
-- against the SAME override) an honest number for inner_h below.
--
-- Returns three things:
--   open_it   -- a strip's own body was double-clicked (mixer view
--               only): open this track in channel view.
--   want_view -- the empty space past the last strip or name button
--               was double-clicked: switch to the OTHER view (channel
--               view on whatever track is already current, from mixer
--               view; mixer view, from channel view).
--   dbl_track -- a NAME BUTTON was double-clicked, in either view: open
--               this track in channel view.
function MX.draw_row(ctx, total_h, cur_track, strips, pad_y, pad_x)
  local open_it, want_view, dbl_track = nil, false, nil

  local row_x, row_y0 = ImGui.GetCursorPos(ctx)
  -- Popped unconditionally below (after the if/else, before return),
  -- the same as row_pad_y -- the push happens regardless of what
  -- BeginChild returns, so the pop has to as well.
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, pad_x, C.TRACKROW_PAD_Y)
  -- AlwaysHorizontalScrollbar: see row_pad_y's own comment on the same
  -- pair of flags. Without it, THIS row -- the real one, not the probe
  -- -- only shows a scrollbar on a frame its own content genuinely
  -- overflows, so a short track list reserved the strip and then drew
  -- nothing in it: reserved space with nothing there to explain it.
  -- With it, the strip is never anything other than a scrollbar.
  local ok = ImGui.BeginChild(ctx, "trackrow", 0, total_h, 0,
    ImGui.WindowFlags_HorizontalScrollbar | ImGui.WindowFlags_AlwaysHorizontalScrollbar
    | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    -- One constant, always -- see row_pad_y. A strip's height never
    -- depends on which VIEW is asking (both are handed the exact same
    -- pad_y, from the ONE call per frame) or on whether the row's
    -- content happens to overflow this frame, because nothing here asks
    -- that question any more.
    local inner_h = total_h - pad_y
    local list = MX.tracks()

    if strips and #list == 0 then
      ImGui.TextDisabled(ctx, "No tracks are shown in the mixer.")
    end

    -- Each column is placed at an EXPLICITLY tracked (x, row_y), not by
    -- chaining the "same line as the last item" call off the previous
    -- one. That call trusts ImGui's own bookkeeping of where the last
    -- item was, and that bookkeeping is exactly what a wide
    -- horizontally-scrolled row of BeginChild-per-track breaks: once
    -- enough columns push a track past the visible width, ReaImGui
    -- culls its BeginChild (it returns false, same as a fully-clipped
    -- window is meant to), and the next "same line" call measures its
    -- offset from that culled child instead of a normally-drawn one --
    -- which is where a whole extra row's height would appear from
    -- nowhere, every track after it inheriting the same drift. Tracking
    -- our own x_off sidesteps ImGui's bookkeeping entirely: nothing
    -- after a culled column can ever be mispositioned by it, because
    -- nothing here depends on where that column thinks it left the
    -- cursor.
    local row_y = select(2, ImGui.GetCursorPos(ctx))
    local x_off = 0

    for i, t in ipairs(list) do
      local gap = 0
      if i > 1 then
        -- REAPER's own TCP spacer opens a gap here too, the same as it
        -- does in the send menu.
        gap = t.space and C.STRIP_SPACER or C.MIX_GAP
      end
      x_off = x_off + gap
      ImGui.SetCursorPos(ctx, x_off, row_y)

      if i > 1 and t.space then
        -- And the same hairline down the middle of it. The gap alone
        -- reads as a gap; the rule says somebody MEANT it. Drawn at a
        -- half pixel so it lands on one column rather than straddling
        -- two.
        local bx, by = ImGui.GetCursorScreenPos(ctx)
        local rx = math.floor(bx - gap * 0.5) + 0.5
        ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx),
          rx, by + 2, rx, by + inner_h - 2, C.COL.panel_border, 1.0)
      end

      local w = MX.col_width(t.guid)

      if strips then
        local want, dbl = column(ctx, t, inner_h, cur_track)
        if want then open_it = want end
        if dbl  then dbl_track = dbl end
      else
        -- Channel view: just the button, at the top of the row -- there
        -- is no strip above it to leave room for.
        local selected = MX.selected(t.track) or (t.track == cur_track)
        -- Same fallback colour as mixer view's column() uses for a
        -- blank track (C.COL.header_bg, the resolved theme colour) --
        -- not a second, hardcoded guess at it, which is how a blank
        -- track ended up a visibly different grey in each view.
        local hit, dbl = name_button(ctx, track_label(t), t.col or C.COL.header_bg,
                                     selected, t.guid, w)
        if hit then MX.click(t.track, t.guid, ImGui.GetKeyMods(ctx)) end
        if dbl then dbl_track = t.track end
        -- Bring a selection made elsewhere (the arrange view, the track
        -- manager) into view. Mixer view doesn't chase this -- it has
        -- its own scrollbar to drag, and a strip disappearing off to
        -- follow a selection made somewhere else is a bigger jump than
        -- a name button doing the same.
        if selected and MX.scroll_to_sel then
          ImGui.SetScrollHereX(ctx, 0.5)
          MX.scroll_to_sel = false
        end
      end

      x_off = x_off + w
    end

    -- Pin the row back to a single explicit line, regardless of
    -- whatever the last column (culled or not) left the cursor doing.
    ImGui.SetCursorPos(ctx, x_off, row_y)

    -- Sideways on a plain wheel, the same as the plugin row. ChildWindows
    -- matters in mixer view: every strip is its own child window, so
    -- without it "hovered" means the thin gaps between strips (and
    -- between name buttons) and nowhere else -- the mouse is almost
    -- always over a strip. In channel view there is nothing nested to
    -- steal hover, so it costs nothing to ask for it there too. A tilt
    -- wheel or trackpad's horizontal axis always scrolls, since no
    -- control here uses it.
    if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows) then
      local wy, wx = ImGui.GetMouseWheel(ctx)
      local d = 0
      if wx ~= 0 then d = wx
      elseif wy ~= 0 and not W.wheel_taken() then d = wy end
      if d ~= 0 then
        ImGui.SetScrollX(ctx, ImGui.GetScrollX(ctx) - d * C.WHEEL_SCROLL_PX)
      end
    end

    do
      -- Past the last strip (or, in channel view, the last name button)
      -- is empty space. Clicking it clears the selection -- the same
      -- gesture as clicking the background of any list anywhere -- and
      -- double-clicking switches to the OTHER view, symmetric either
      -- way: empty mixer background goes to channel view on whatever
      -- track was last shown, empty channel-view background goes back
      -- to mixer. Submitted last, at the cursor the loop left behind,
      -- so it can only ever catch what none of the strips/buttons
      -- wanted. Cursor is already at (x_off, row_y) from the loop
      -- above -- explicitly, not via SameLine -- so this needs no
      -- repositioning of its own.
      local ew, eh = ImGui.GetContentRegionAvail(ctx)
      if ew > 4 and eh > 4 then
        ImGui.InvisibleButton(ctx, "mixbg", ew, eh)
        if ImGui.IsItemHovered(ctx) then
          if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
            want_view = true
          elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
            MX.clear_selection()
          end
        end
      else
        ImGui.Dummy(ctx, 0, 0)
      end
    end

    -- Claim the row's bounds with one final, real item. A bare
    -- SetCursorPos only moves where the NEXT item starts -- it does not
    -- by itself tell ReaImGui how tall the window's content is, and
    -- ReaImGui says so plainly when nothing follows one that would grow
    -- the window: "Please submit an item e.g. Dummy() afterwards". In
    -- channel view there is nothing after the button loop to be that
    -- item, which is exactly what made this the hard error rather than
    -- just a stray scrollbar. Reasserting (x_off, row_y) and a
    -- zero-width, one-row-tall Dummy here does double duty: it is the
    -- item ReaImGui asked for, and it caps the row's content height at
    -- exactly one row no matter what the last thing drawn above -- a
    -- strip, a name button, a culled column's stand-in -- left the
    -- cursor doing, which is what keeps a vertical scrollbar from ever
    -- appearing on a row that only ever scrolls sideways.
    ImGui.SetCursorPos(ctx, x_off, row_y)
    ImGui.Dummy(ctx, 0, inner_h)

    -- This row is one line, always -- it scrolls sideways and never up
    -- or down. Whatever ReaImGui's own bookkeeping thinks the content
    -- height is (and that bookkeeping is exactly what has been fought
    -- through this whole file), a vertical scroll position is never
    -- allowed to leave 0, so there is never a "second row" to land on
    -- by scrolling, no matter what the bookkeeping says exists below it.
    if ImGui.GetScrollY(ctx) ~= 0 then
      ImGui.SetScrollY(ctx, 0)
    end

    ImGui.EndChild(ctx)
  else
    W.child_skipped(ctx, 0, total_h, row_x, row_y0)
  end
  ImGui.PopStyleVar(ctx)

  return open_it, want_view, dbl_track
end

return MX
