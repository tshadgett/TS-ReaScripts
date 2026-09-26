-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Focus.lua -- handing keyboard focus back to REAPER.

  Clicking anything in a ReaImGui window gives that window the keyboard,
  and REAPER only runs its ordinary shortcuts (Space, the arrow keys,
  every "Main" binding) while its own windows have it. So after a click
  or a drag here, focus goes back to the arrange view, and the next key
  press reaches REAPER as if ChannelView had never been touched.

  Not while the keyboard is still wanted here: a text field being typed
  in, a menu or dialog that's open, a drag in progress. Those keep focus
  until they finish, and focus goes back then. Only ever after a click in
  this window -- nothing here takes focus away from anywhere else.

  Focusing a window isn't in REAPER's own API. It goes through the
  js_ReaScriptAPI extension if present, otherwise SWS's "Focus arrange"
  action; with neither, focus simply stays here as it always has.
--]]

local F = {}

-- ---------------------------------------------------------------------
-- when (pure)
-- ---------------------------------------------------------------------

-- One frame of the decision. `s` is the persistent state table; `now`
-- is this frame's inputs:
--   clicked   a mouse button went down over one of this script's windows
--   busy      the keyboard or mouse is still in use here: a mouse button
--             held, an item active (a drag, a text field being edited),
--             or a popup/menu/dialog open
--   popup     a popup/menu/dialog is open (a subset of busy)
-- Returns true on the frame focus should go back.
function F.step(s, now)
  if now.clicked then s.armed = true end
  -- A popup closing is a hand-back point too: after renaming a track and
  -- pressing Enter, the next key should be REAPER's.
  if s.popup_was and not now.popup then s.armed = true end
  s.popup_was = now.popup
  if s.armed and not now.busy then
    s.armed = false
    return true
  end
  return false
end

-- ---------------------------------------------------------------------
-- how
-- ---------------------------------------------------------------------

local ARRANGE_ID = 1000       -- the arrange view's child id in REAPER's main window

-- "js", "sws" or nil: what's available to move focus with.
function F.mechanism()
  if reaper.JS_Window_SetFocus and reaper.JS_Window_FindChildByID then return "js" end
  if reaper.NamedCommandLookup("_BR_FOCUS_ARRANGE_WND") ~= 0 then return "sws" end
  return nil
end

function F.to_arrange()
  local how = F.mechanism()
  if how == "js" then
    local main = reaper.GetMainHwnd()
    local arrange = reaper.JS_Window_FindChildByID(main, ARRANGE_ID)
    reaper.JS_Window_SetFocus(arrange or main)
    return true
  elseif how == "sws" then
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_FOCUS_ARRANGE_WND"), 0)
    return true
  end
  return false
end

-- Call once per frame, after everything is drawn, while the main window
-- is still current. `enabled` is the user's setting.
local state = {}
function F.update(ctx, ImGui, enabled)
  if not enabled then state.armed = false return end
  -- By the end of the frame a click on a knob or fader has already made
  -- that item active, and an active item hides the window from a plain
  -- hover test -- so the test has to allow for it, or only clicks on
  -- empty space would ever count.
  local over = ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_AnyWindow
    | ImGui.HoveredFlags_AllowWhenBlockedByActiveItem
    | ImGui.HoveredFlags_AllowWhenBlockedByPopup)
  local active = ImGui.IsAnyItemActive(ctx)
  local clicked, held = false, false
  for b = 0, 2 do
    if over and ImGui.IsMouseClicked(ctx, b) then clicked = true end
    if ImGui.IsMouseDown(ctx, b) then held = true end
  end
  -- An item of ours becoming active means it was clicked, whatever the
  -- hover test said.
  if active and not state.active_was then clicked = true end
  state.active_was = active
  local popup = ImGui.IsPopupOpen(ctx, "",
    ImGui.PopupFlags_AnyPopupId | ImGui.PopupFlags_AnyPopupLevel)
  local busy = held or popup or active
  if F.step(state, { clicked = clicked, busy = busy, popup = popup }) then
    F.to_arrange()
  end
end

return F
