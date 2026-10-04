-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_PresetUI.lua -- the preset bar along the foot of a panel.

  The header's twin: the plugin's preset in a dropdown in the middle,
  previous and next either side, and a + for saving -- Save preset, Save as
  default, Rename, Delete. The files are TS_CV_Presets' business; this only
  draws and asks.

  The bar sits inside a panel's own child window, so its list and + menu
  are ordinary popups there. The name-entry dialog (save, save as default,
  rename) is a modal, drawn once a frame from the main loop by PU.draw --
  a modal opened from inside a panel that then scrolls out of view would
  otherwise vanish with it.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local PR = require("TS_CV_Presets")

local ImGui
local PU = {}
function PU.attach(imgui) ImGui = imgui end

local LIST_ROWS = 18     -- presets shown before the list scrolls

-- The open name-entry dialog: { mode = "save"|"default"|"rename", track,
-- addr, guid, plugin, name, old, open, focus }.
local dlg = nil

local function err(text) reaper.MB(text, "ChannelView", 0) end

-- The plugin's address now: by the one we had, or by its GUID if the chain
-- moved under the dialog.
local function addr_of(track, addr, guid)
  if not reaper.ValidatePtr(track, "MediaTrack*") then return nil end
  if reaper.TrackFX_GetFXGUID(track, addr) == guid then return addr end
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    if reaper.TrackFX_GetFXGUID(track, i) == guid then return i end
  end
  return nil
end

local function open_dialog(mode, track, fx, name, old)
  dlg = { mode = mode, track = track, addr = fx.addr, guid = fx.guid,
          plugin = U.fx_label(fx), name = name or "", old = old,
          open = true, focus = true }
end

-- Every user preset in a list that scrolls rather than running off the
-- screen; `pick(name)` on a click.
local function preset_list(ctx, id, names, current, default, pick, w)
  local lh = ImGui.GetTextLineHeightWithSpacing(ctx)
  local h = math.min(#names, LIST_ROWS) * lh + 4
  if ImGui.BeginChild(ctx, id, w or 0, h, 0) then
    for i, n in ipairs(names) do
      local label = n .. ((n == default) and "   \u{2605}" or "") .. "##p" .. i
      if ImGui.Selectable(ctx, label, n == current) then pick(n) end
    end
    ImGui.EndChild(ctx)
  end
end

-- The bar itself, `h` tall at x, y across `w`.
-- `inset` keeps clear of that much at the bar's left (the layout lock).
function PU.footer(ctx, dl, x, y, w, h, track, fx, inset)
  local addr, guid = fx.addr, fx.guid
  ImGui.DrawList_AddRectFilled(dl, x + 1, y, x + w - 1, y + h - 1, C.COL.header_bg, 2.5,
    ImGui.DrawFlags_RoundCornersBottom)
  ImGui.DrawList_AddLine(dl, x, y, x + w, y, C.COL.panel_border, 1.0)

  local info = PR.list(track, addr)
  local name, same = PR.current(track, addr)
  local shown = (name ~= "") and (name .. (same and "" or " *")) or "No preset"
  local btn = C.ICON_SIZE
  local by = y + (h - btn) * 0.5

  -- + at the right; previous, the dropdown and next together in the
  -- middle, centred on the panel while there's room and shifted left of
  -- the + when there isn't.
  ImGui.SetCursorScreenPos(ctx, x + w - btn - 3, by)
  if W.icon_button(ctx, "pplus##" .. guid, "plus", btn, false, "Save, rename or delete") then
    ImGui.OpenPopup(ctx, "pmenu##" .. guid)
  end

  local gap = 2
  local left, right = x + 3 + (inset or 0), x + w - btn - 3 - 4
  local dw = math.min(220, right - left - (btn + gap) * 2)
  if dw > 30 then
    local gw = dw + (btn + gap) * 2
    local gx = math.min(math.max(x + (w - gw) * 0.5, left), right - gw)
    ImGui.SetCursorScreenPos(ctx, gx, by)
    if W.icon_button(ctx, "pprev##" .. guid, "prev", btn, false, "Previous preset") then
      PR.step(track, addr, -1)
    end
    local tip = (name ~= "" and not same) and (name .. " \u{2014} changed since it was loaded") or nil
    if W.dropdown(ctx, "pdd##" .. guid, shown, gx + btn + gap, y + 2, dw, h - 4, tip) then
      ImGui.OpenPopup(ctx, "plist##" .. guid)
    end
    ImGui.SetCursorScreenPos(ctx, gx + btn + gap + dw + gap, by)
    if W.icon_button(ctx, "pnext##" .. guid, "next", btn, false, "Next preset") then
      PR.step(track, addr, 1)
    end
  end

  if ImGui.BeginPopup(ctx, "plist##" .. guid) then
    if #info.user == 0 and #info.factory == 0 then
      ImGui.TextDisabled(ctx, "No presets yet \u{2014} + saves one")
    end
    local function load(n) PR.load(track, addr, n); ImGui.CloseCurrentPopup(ctx) end
    if #info.user > 0 then
      ImGui.TextDisabled(ctx, "Your presets")
      preset_list(ctx, "##pu" .. guid, info.user, name, info.default, load, 260)
    end
    if #info.factory > 0 then
      ImGui.SeparatorText(ctx, "Factory")
      preset_list(ctx, "##pf" .. guid, info.factory, name, nil, load, 260)
    end
    if info.default then
      ImGui.Separator(ctx)
      if ImGui.Selectable(ctx, ("Load default  (%s)"):format(info.default)) then
        PR.load_default(track, addr)
        ImGui.CloseCurrentPopup(ctx)
      end
    end
    ImGui.EndPopup(ctx)
  end

  if ImGui.BeginPopup(ctx, "pmenu##" .. guid) then
    local is_user = name ~= "" and PR.is_user(track, addr, name)
    if ImGui.MenuItem(ctx, "Save preset\u{2026}", nil, false, info.can_save) then
      open_dialog("save", track, fx, is_user and name or "")
    end
    if ImGui.MenuItem(ctx, "Save as default\u{2026}", nil, false, info.can_save and info.can_default) then
      open_dialog("default", track, fx, info.default or (is_user and name) or "Default")
    end
    ImGui.Separator(ctx)
    local short = (#name > 28) and (name:sub(1, 27) .. "\u{2026}") or name
    if ImGui.MenuItem(ctx, is_user and ("Rename \u{201C}%s\u{201D}\u{2026}"):format(short) or "Rename\u{2026}",
                      nil, false, is_user) then
      open_dialog("rename", track, fx, name, name)
    end
    if ImGui.MenuItem(ctx, is_user and ("Delete \u{201C}%s\u{201D}\u{2026}"):format(short) or "Delete\u{2026}",
                      nil, false, is_user) then
      local msg = ("Delete the preset \u{201C}%s\u{201D}?"):format(name)
      if info.default == name then msg = msg .. "\n\nIt's this plugin's default preset; it won't have one after this." end
      if reaper.MB(msg, "ChannelView", 1) == 1 then
        local ok, e = PR.delete(track, addr, name)
        if not ok then err(e) end
      end
    end
    if not info.can_save then
      ImGui.Separator(ctx)
      ImGui.TextDisabled(ctx, "Saving isn't supported for this\nplugin format yet.")
    end
    ImGui.EndPopup(ctx)
  end
end

-- The name-entry dialog. Call once a frame, outside any panel.
local TITLES = { save = "Save preset###tscv_preset", default = "Save as default###tscv_preset",
                 rename = "Rename preset###tscv_preset" }
function PU.draw(ctx)
  if not dlg then return end
  if dlg.open then ImGui.OpenPopup(ctx, TITLES[dlg.mode]); dlg.open = false end
  ImGui.SetNextWindowSize(ctx, 340, 0, ImGui.Cond_Appearing)
  local visible, open = ImGui.BeginPopupModal(ctx, TITLES[dlg.mode], true,
    ImGui.WindowFlags_AlwaysAutoResize)
  if not visible then
    if not open then dlg = nil end
    return
  end
  local d = dlg
  ImGui.TextDisabled(ctx, d.plugin)
  if d.mode == "default" then
    ImGui.TextWrapped(ctx, "Saved as a preset, and loaded whenever this plugin is added.")
  end
  if d.focus then ImGui.SetKeyboardFocusHere(ctx); d.focus = false end
  ImGui.SetNextItemWidth(ctx, 320)
  local ch, v = ImGui.InputTextWithHint(ctx, "##pname", "preset name", d.name)
  if ch then d.name = v end
  local enter = ImGui.IsItemDeactivated(ctx)
    and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))

  local addr = addr_of(d.track, d.addr, d.guid)
  if addr and d.mode ~= "rename" then
    local info = PR.list(d.track, addr)
    if #info.user > 0 then
      ImGui.TextDisabled(ctx, "or replace one of yours:")
      preset_list(ctx, "##pdlist", info.user, d.name, info.default, function(n) d.name = n end, 320)
    end
  end

  local function close() dlg = nil; ImGui.CloseCurrentPopup(ctx) end
  local label = (d.mode == "rename") and "Rename" or "Save"
  if ImGui.Button(ctx, label, 90) or enter then
    local name = U.trim(d.name)
    if not addr then
      err("The plugin isn't there any more."); close()
    elseif name == "" then
      err("The preset needs a name.")
    else
      local go = true
      if d.mode ~= "rename" and PR.is_user(d.track, addr, name) then
        go = reaper.MB(("Replace the preset \u{201C}%s\u{201D}?"):format(name), "ChannelView", 1) == 1
      end
      if go then
        local ok, e
        if d.mode == "save" then ok, e = PR.save(d.track, addr, name)
        elseif d.mode == "default" then ok, e = PR.save_default(d.track, addr, name)
        else ok, e = PR.rename(d.track, addr, d.old, name) end
        if ok then close() else err(e) end
      end
    end
  end
  ImGui.SameLine(ctx)
  if dlg and ImGui.Button(ctx, "Cancel", 90) then close() end
  ImGui.EndPopup(ctx)
end

return PU
