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

local S = {}
local ImGui

local scroll_to_sel = false
local last_sel_guid = nil

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
  local clicked = nil

  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, C.COL.strip_bg)
  local ok = ImGui.BeginChild(ctx, "trackstrip", 0, height, 0,
    ImGui.WindowFlags_HorizontalScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  -- NoScrollWithMouse stops ImGui turning a plain wheel into VERTICAL
  -- scroll here (there's nothing to scroll vertically); the wheel is
  -- redirected to horizontal by hand below.
  ImGui.PopStyleColor(ctx)

  if ok then
    local n = reaper.CountTracks(0)

    -- Master first, so a master-bus chain is one click away.
    local master = reaper.GetMasterTrack(0)
    local sel_master = (cur_track == master)
    if S.button(ctx, "MASTER", 0x555a66ff, sel_master, "master") then
      clicked = master
    end

    for i = 0, n - 1 do
      local tr = reaper.GetTrack(0, i)
      local col = U.track_colour(tr, 0xff) or 0x3a404cff
      local sel = (cur_track == tr)
      -- REAPER's own TCP spacer (the "Space" column in the track manager)
      -- opens a gap here too, the same way it does in the send menu.
      -- Grouping you set up in the project is worth something in every
      -- list that shows the project.
      local space = (reaper.GetMediaTrackInfo_Value(tr, "I_SPACER") or 0) > 0.5
      local gap   = space and C.STRIP_SPACER or 3
      ImGui.SameLine(ctx, 0, gap)
      -- A hairline down the middle of the gap. The gap alone reads as a
      -- gap between two buttons; the rule says somebody MEANT it, which
      -- is the whole point of a spacer.
      if space then
        local bx, by = ImGui.GetCursorScreenPos(ctx)
        local dl = ImGui.GetWindowDrawList(ctx)
        ImGui.DrawList_AddLine(dl, bx - gap * 0.5, by + 2,
          bx - gap * 0.5, by + C.STRIP_H - 10, C.COL.panel_border, 1.0)
      end
      if S.button(ctx, track_label(tr, i + 1), col, sel, "t" .. i) then
        clicked = tr
      end
      if sel and scroll_to_sel then
        ImGui.SetScrollHereX(ctx, 0.5)
        scroll_to_sel = false
      end
    end
    -- ReaImGui: EndChild only when BeginChild returned true.
    ImGui.EndChild(ctx)
  end

  if clicked then
    reaper.SetOnlyTrackSelected(clicked)
    reaper.UpdateArrange()
  end
  return clicked
end

-- One coloured track button, drawn rather than themed so the track colour
-- can be the fill while the label stays readable over it. Fixed width --
-- the strip should read as a row of equal slots like a console, not
-- jump about with the length of each track's name.
function S.button(ctx, label, col, selected, id)
  local dl = ImGui.GetWindowDrawList(ctx)
  local tw, th = ImGui.CalcTextSize(ctx, label)
  local w = C.TRACK_BTN_W
  local h = C.STRIP_H - 8

  local x, y = ImGui.GetCursorScreenPos(ctx)
  local pressed = ImGui.InvisibleButton(ctx, "ts_" .. id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)

  local fill = selected and col or U.with_alpha(col, 0x66)
  if hovered and not selected then fill = U.with_alpha(col, 0xaa) end
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, fill, 3.0)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h,
    selected and C.COL.strip_sel or C.COL.panel_border, 3.0, 0, selected and 2.0 or 1.0)

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
  return pressed
end

return S
