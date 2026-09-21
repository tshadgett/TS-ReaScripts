-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Mixer.lua -- the mixer view.

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

-- The horizontal scroll, shared with the track strip below.
--
-- The two are one thing: a button lines up under its own strip and has
-- to stay there. Whichever of them is the scrolling one this frame
-- writes here and the other follows -- the mixer when it is up, the
-- track strip when it is alone in channel view.
MX.scroll_x = 0

-- Set when the mixer's empty space was double-clicked. The caller reads
-- and clears it, the same way the Channel panel hands its own back.
MX.want_channel = false

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
-- a reopen and cannot be written into an id.
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
-- one strip
-- ---------------------------------------------------------------------

local function strip_header(ctx, dl, x, y, w, t, selected, hovered)
  local h = C.HEADER_H
  -- The track's own colour IS the header, not a stripe on it. At mixer
  -- width the name is the only other thing up there, so the colour has
  -- room to do the work it does on a console.
  --
  -- Dimmed when the track isn't selected, at the same alphas as the
  -- button directly underneath: the header and the button are one
  -- object, and only the selected one is at full strength.
  local base = t.col or C.COL.header_bg
  local col  = base
  if not selected then
    col = U.with_alpha(base, hovered and C.HOVER_ALPHA or C.DIM_ALPHA)
  end
  -- Rounded at the top to the same radius as the strip, so the header
  -- is a cap ON the strip rather than a rectangle laid across it. It
  -- used to be square, which left the outline's rounded corners cut
  -- off by the colour and the two shapes visibly disagreeing.
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, col, C.STRIP_ROUND,
                               ImGui.DrawFlags_RoundCornersTop)
  -- No brighter lip on a selected header: the header is already at full
  -- colour while its neighbours are dimmed, and the outline says the
  -- rest. Three marks for one piece of information was two too many.
  ImGui.DrawList_AddLine(dl, x, y + h, x + w, y + h, C.COL.panel_border, 1.0)

  local btn = C.ICON_SIZE
  local aw  = C.AUTO_BTN_W
  -- The automation button lives here too. Mixer view is where you set
  -- these across a session, so leaving it to channel view would mean
  -- visiting every track to do what the row is for.
  local room = (w - btn - aw - 14 > 8)

  if C.MIX_STRIP_NAME then
    local label = (t.num > 0) and ("%d %s"):format(t.num, t.name) or t.name
    local avail = w - btn - 10 - (room and (aw + 4) or 0)
    local tw, th = ImGui.CalcTextSize(ctx, label)
    while tw > avail and #label > 1 do
      label = label:sub(1, #label - 1)
      tw = ImGui.CalcTextSize(ctx, label)
    end
    -- Readable on any track colour, which is the one thing a
    -- user-chosen background cannot be trusted to allow -- and judged
    -- against the colour actually ON SCREEN. On a dimmed header that
    -- is the panel showing through rather than the track's colour, so
    -- a light track would otherwise get black text on a dark bar.
    ImGui.DrawList_AddText(dl, x + 5, y + (h - th) * 0.5,
      selected and U.contrast_text(base) or C.COL.header_text, label)
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
  local base = t.col or C.COL.header_bg
  local col  = selected and base or U.with_alpha(base, C.DIM_ALPHA)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + 4, col, C.STRIP_ROUND,
                               ImGui.DrawFlags_RoundCornersTop)

  return CH.draw_collapsed(ctx, dl, x, y, w, h, t.track,
                           "mx" .. t.guid, "mx:" .. t.guid)
end

-- Returns the track to open in channel view, or nil.
local function strip(ctx, t, avail_h, cur_track)
  local collapsed = St.is_collapsed("mx:" .. t.guid)
  local w = MX.col_width(t.guid)
  -- Selected as REAPER sees it, so a multi-selection lights every strip
  -- in it -- with the track channel view is showing always lit, even on
  -- the master, which REAPER does not always report as selected.
  local selected = MX.selected(t.track) or (t.track == cur_track)
  local open_it = nil

  local ok = ImGui.BeginChild(ctx, "mx##" .. t.guid, w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    -- Only for dimming the header -- selection is decided by item
    -- hover below, deliberately.
    local over = ImGui.IsWindowHovered(ctx)
    local sel_col = U.sel_colour(C.SEL_OUTLINE, t.col, C.COL.strip_sel)

    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh,
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
    ImGui.InvisibleButton(ctx, "mxbg" .. t.guid, ww, wh)
    if ImGui.IsItemHovered(ctx) then
      if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
        open_it = t.track
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
        MX.click(t.track, t.guid, ImGui.GetKeyMods(ctx))
      end
    end

    if collapsed then
      if strip_collapsed(ctx, dl, x, y, ww, wh, t, selected) then
        MX.click(t.track, t.guid, ImGui.GetKeyMods(ctx))
      end
    else
      strip_header(ctx, dl, x, y, ww, t, selected, over)
      CH.draw_body(ctx, dl, x, y + C.HEADER_H, ww, wh - C.HEADER_H,
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
    ImGui.DrawList_AddRect(dl, x + o, y + o, x + ww - o, y + wh - o,
      selected and sel_col or C.COL.panel_border, C.STRIP_ROUND, 0, lw)
    ImGui.EndChild(ctx)
  else
    W.child_skipped(ctx, w, avail_h)
  end
  return open_it
end

-- ---------------------------------------------------------------------
-- the row
-- ---------------------------------------------------------------------

-- Draws the whole mixer. Returns the track to open in channel view, or
-- nil to stay here.
function MX.draw(ctx, avail_h, cur_track)
  local open_it = nil

  local ok = ImGui.BeginChild(ctx, "mixerrow", 0, avail_h, 0,
    ImGui.WindowFlags_HorizontalScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local _, inner_h = ImGui.GetContentRegionAvail(ctx)
    local list = MX.tracks()

    if #list == 0 then
      ImGui.TextDisabled(ctx, "No tracks are shown in the mixer.")
    end

    for i, t in ipairs(list) do
      if i > 1 then
        -- REAPER's own TCP spacer opens a gap here too, the same as it
        -- does in the track strip and the send menu.
        local gap = t.space and C.STRIP_SPACER or C.MIX_GAP
        ImGui.SameLine(ctx, 0, gap)
        -- And the same hairline down the middle of it. The gap alone
        -- reads as a gap; the rule says somebody MEANT it. Drawn at a
        -- half pixel so it lands on one column rather than straddling
        -- two, and at the same x as the track strip's own, so the two
        -- read as one rule running the height of the window.
        if t.space then
          local bx, by = ImGui.GetCursorScreenPos(ctx)
          local rx = math.floor(bx - gap * 0.5) + 0.5
          ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx),
            rx, by + 2, rx, by + inner_h - 2, C.COL.panel_border, 1.0)
        end
      end
      local want = strip(ctx, t, inner_h, cur_track)
      if want then open_it = want end
    end

    -- Sideways on a plain wheel, the same as the plugin row: there is
    -- nothing to scroll vertically and a mixer is a horizontal thing.
    if ImGui.IsWindowHovered(ctx) and not W.wheel_taken() then
      local wheel = ImGui.GetMouseWheel(ctx)
      if wheel ~= 0 then
        ImGui.SetScrollX(ctx, ImGui.GetScrollX(ctx) - wheel * C.WHEEL_SCROLL_PX)
      end
    end

    -- The mixer is the scrolling one while it is up; the track strip
    -- reads this and follows, so a button stays under its strip whether
    -- you scrolled with the wheel or dragged the bar.
    MX.scroll_x = ImGui.GetScrollX(ctx)

    -- Past the last strip is empty space. Clicking it clears the
    -- selection -- the same gesture as clicking the background of any
    -- list anywhere -- and double-clicking goes back to channel view on
    -- whatever track was last shown. Submitted last, at the cursor the
    -- strips left behind, so it can only ever catch what none of them
    -- wanted.
    ImGui.SameLine(ctx, 0, 0)
    local ew, eh = ImGui.GetContentRegionAvail(ctx)
    if ew > 4 and eh > 4 then
      ImGui.InvisibleButton(ctx, "mixbg", ew, eh)
      if ImGui.IsItemHovered(ctx) then
        if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
          MX.want_channel = true
        elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
          MX.clear_selection()
        end
      end
    else
      ImGui.Dummy(ctx, 0, 0)
    end
    ImGui.EndChild(ctx)
  else
    W.child_skipped(ctx, 0, avail_h)
  end

  return open_it
end

return MX
