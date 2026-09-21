-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_TrackStrip.lua -- the track selector along the bottom.

  Two-way with REAPER's own selection: the strip highlights whatever is
  selected in the arrange view, and clicking a name here selects that
  track there. Each button carries the track's own colour, so the strip
  reads the same way the mixer does.
--]]

local C = require("TS_CV_Config")
local U = require("TS_CV_Util")
local W = require("TS_CV_Widgets")
local MX = require("TS_CV_Mixer")

local S = {}
local ImGui

local scroll_to_sel = false
local last_sel_guid = nil

-- Set when a track button was double-clicked. The caller reads and
-- clears it, the same way the mixer hands its own back. Double-clicking
-- a name means "show me this one in full", which is what double-clicking
-- the strip above it already meant -- the button and the strip are one
-- object and had better answer the same gesture.
S.want_channel = false

function S.attach(imgui) ImGui = imgui end

-- Ask the strip to bring the selected track into view on the next frame
-- (used when the selection changed from outside this window).
function S.request_scroll() scroll_to_sel = true end

local function track_label(tr, idx)
  local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  name = U.trim(name)
  if name == "" then name = "Track " .. idx end
  return ("%d  %s"):format(idx, name)
end

-- Draws the strip and returns the track the user just clicked, or nil.
function S.draw(ctx, height, cur_track)
  local clicked, clicked_guid, dbl_track = nil, nil, nil
  -- Read before the buttons are drawn: by the time we act on the click
  -- below we are outside the child, but the modifiers are the ones that
  -- were held when it happened either way.
  local mods = ImGui.GetKeyMods(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, C.COL.strip_bg)
  -- In mixer view the row above owns the scrolling and this follows it,
  -- so it gets no bar of its own: two scrollbars for one position is a
  -- way of asking which one is lying.
  local flags = ImGui.WindowFlags_NoScrollWithMouse
  if not C.MIXER_VIEW then
    flags = flags | ImGui.WindowFlags_HorizontalScrollbar
  end
  local ok = ImGui.BeginChild(ctx, "trackstrip", 0, height, 0, flags)
  -- NoScrollWithMouse stops ImGui turning a plain wheel into VERTICAL
  -- scroll here (there's nothing to scroll vertically); the wheel is
  -- redirected to horizontal by hand below.
  ImGui.PopStyleColor(ctx)

  if ok then
    -- Follow the mixer's scroll, so every button stays under its own
    -- strip. Set before anything is drawn, or the buttons are laid out
    -- at the old offset and the two disagree for a frame.
    if C.MIXER_VIEW then ImGui.SetScrollX(ctx, MX.scroll_x) end

    local n = reaper.CountTracks(0)

    -- Master first, so a master-bus chain is one click away.
    local master = reaper.GetMasterTrack(0)
    local sel_master = MX.selected(master) or (cur_track == master)
    local mhit, mdbl = S.button(ctx, "MASTER", 0x555a66ff, sel_master,
                                "master", MX.col_width("master"))
    if mhit then clicked, clicked_guid = master, "master" end
    if mdbl then clicked, clicked_guid, dbl_track = master, "master", master end

    for i = 0, n - 1 do
      local tr = reaper.GetTrack(0, i)
      -- Hidden from REAPER's mixer means hidden here too. The strip and
      -- the mixer view are two ways of showing the same set of tracks,
      -- and a button with no strip above it would be a lie about which.
      if MX.in_mixer(tr) then
      local col = U.track_colour(tr, 0xff) or 0x3a404cff
      -- Lit if REAPER has it selected, so a multi-selection made in
      -- the mixer (or in the arrange view) shows here too.
      local sel = MX.selected(tr) or (cur_track == tr)
      -- REAPER's own TCP spacer (the "Space" column in the track manager)
      -- opens a gap here too, the same way it does in the send menu.
      -- Grouping you set up in the project is worth something in every
      -- list that shows the project.
      local space = (reaper.GetMediaTrackInfo_Value(tr, "I_SPACER") or 0) > 0.5
      local gap   = space and C.STRIP_SPACER or C.MIX_GAP
      ImGui.SameLine(ctx, 0, gap)
      -- A hairline down the middle of the gap. The gap alone reads as a
      -- gap between two buttons; the rule says somebody MEANT it, which
      -- is the whole point of a spacer.
      if space then
        local bx, by = ImGui.GetCursorScreenPos(ctx)
        local dl = ImGui.GetWindowDrawList(ctx)
        -- Half a pixel, so it lands on one column instead of straddling
        -- two -- and at the same x the mixer draws its own, so in mixer
        -- view the two are one rule down the window.
        local rx = math.floor(bx - gap * 0.5) + 0.5
        ImGui.DrawList_AddLine(dl, rx, by + 2,
          rx, by + C.STRIP_H - 10, C.COL.panel_border, 1.0)
      end
      -- The width comes from the strip above, not from a constant: the
      -- two are one object and a collapsed strip has a narrow button.
      local guid = reaper.GetTrackGUID(tr) or ("t" .. i)
      local hit, dbl = S.button(ctx, track_label(tr, i + 1), col, sel,
                                "t" .. i, MX.col_width(guid))
      if hit then clicked, clicked_guid = tr, guid end
      if dbl then clicked, clicked_guid, dbl_track = tr, guid, tr end
      if sel and scroll_to_sel and not C.MIXER_VIEW then
        ImGui.SetScrollHereX(ctx, 0.5)
        scroll_to_sel = false
      end
      end
    end
    -- In channel view this strip is the only scrolling thing, so it is
    -- the one that writes the shared position.
    if not C.MIXER_VIEW then MX.scroll_x = ImGui.GetScrollX(ctx) end

    -- ReaImGui: EndChild only when BeginChild returned true.
    ImGui.EndChild(ctx)
  else
    -- Culled: still occupy the space, or the parent's bounds
    -- never grow past it. See W.child_skipped.
    W.child_skipped(ctx, 0, height)
  end

  -- Ctrl and Shift do here what they do on a strip: the button and the
  -- strip above it are one object, so they had better answer the same
  -- gesture the same way.
  if clicked then MX.click(clicked, clicked_guid, mods) end
  -- A double-click selects AND opens: MX.click above has already made it
  -- the selection, so the caller only has to change view.
  if dbl_track then S.want_channel = dbl_track end
  return clicked
end

-- One coloured track button, drawn rather than themed so the track colour
-- can be the fill while the label stays readable over it. Fixed width --
-- the strip should read as a row of equal slots like a console, not
-- jump about with the length of each track's name.
-- `w` is the width of the mixer strip this button sits under. Passed in
-- rather than looked up so the strip does not have to know how the mixer
-- lays itself out -- it only has to agree with it.
function S.button(ctx, label, col, selected, id, w)
  local dl = ImGui.GetWindowDrawList(ctx)
  local tw, th = ImGui.CalcTextSize(ctx, label)
  w = w or C.TRACK_BTN_W
  local h = C.STRIP_H - 8

  local x, y = ImGui.GetCursorScreenPos(ctx)
  local pressed = ImGui.InvisibleButton(ctx, "ts_" .. id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)

  -- The same alphas the mixer header above uses, because they are the
  -- same object seen twice.
  local fill = selected and col or U.with_alpha(col, C.DIM_ALPHA)
  if hovered and not selected then fill = U.with_alpha(col, C.HOVER_ALPHA) end
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, fill, C.STRIP_ROUND)
  -- Inset by half the stroke, the same as the strip above: centred on
  -- the bounds it would spill outwards, and the clip rect would eat the
  -- spill on one side only.
  local lw = selected and 2.0 or 1.0
  local o  = lw * 0.5
  ImGui.DrawList_AddRect(dl, x + o, y + o, x + w - o, y + h - o,
    selected and U.sel_colour(C.SEL_OUTLINE, col, C.COL.strip_sel)
              or C.COL.panel_border,
    C.STRIP_ROUND, 0, lw)

  local text_col = (selected and U.is_light(col)) and 0x0d1116ff or C.COL.header_text
  local clip = w - 10
  local shown = label
  if tw > clip then
    local k = #shown
    while k > 1 do
      k = k - 1
      local t = shown:sub(1, k) .. "."
      tw = ImGui.CalcTextSize(ctx, t)
      if tw <= clip then shown = t break end
    end
  end
  ImGui.DrawList_AddText(dl, x + w * 0.5 - tw * 0.5, y + h * 0.5 - th * 0.5, text_col, shown)

  W.tip(ctx, "ts_" .. id, label, hovered, false)
  return pressed,
         hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left)
end

return S
