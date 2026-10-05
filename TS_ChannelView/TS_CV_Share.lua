-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Share.lua -- sharing layouts with other people.

  Layouts > Export layouts to file... picks layouts from the library and
  writes them to a file of your choosing; Layouts > Import layouts from
  file... reads a file someone sent you and lets you pick which of its
  layouts to bring in. The file is a layout library in the usual format
  (TS_CV_Mappings), so a whole TS_ChannelView_Mappings.ini works too.

  Importing a layout you already have replaces yours, so those start
  unticked and say so; the library as it was is kept as the .bak by the
  save that follows.
--]]

local U = require("TS_CV_Util")
local M = require("TS_CV_Mappings")

local ImGui
local LS = {}
function LS.attach(imgui) ImGui = imgui end

local SECTION, DIR_KEY = "TS_ChannelView", "share_dir"
local TITLE = { export = "Export layouts###tscv_share", import = "Import layouts###tscv_share" }
local FILTER = "ChannelView layouts (*.ini)\0*.ini\0All files (*.*)\0*.*\0\0"
local LIST_ROWS = 14

local dlg = nil
local function msg(text) reaper.MB(text, "ChannelView", 0) end

-- The folder the last file was picked in, else REAPER's resource folder.
local function last_dir()
  local d = reaper.GetExtState(SECTION, DIR_KEY)
  return (d ~= "" and d) or reaper.GetResourcePath()
end
local function remember_dir(file)
  local d = file:match("^(.*)[\\/]")
  if d then reaper.SetExtState(SECTION, DIR_KEY, d, true) end
end

local function safe_name(s)
  return (s:gsub('[\\/:*?"<>|]', "_"))
end

-- A save-as dialog where js_ReaScriptAPI gives one; otherwise a path to
-- type in, starting from the last folder.
local function ask_save(default_name)
  local file
  if reaper.JS_Dialog_BrowseForSaveFile then
    local rv, f = reaper.JS_Dialog_BrowseForSaveFile("Export ChannelView layouts", last_dir(),
      default_name, FILTER)
    if rv ~= 1 or not f or f == "" then return nil end
    file = f
  else
    local sep = package.config:sub(1, 1)
    local ok, f = reaper.GetUserInputs("Export ChannelView layouts", 1,
      "Save as (full path):,extrawidth=320", last_dir() .. sep .. default_name)
    if not ok or U.trim(f) == "" then return nil end
    file = U.trim(f)
  end
  if not file:lower():match("%.ini$") then file = file .. ".ini" end
  return file
end

local function ask_open()
  local rv, f
  if reaper.JS_Dialog_BrowseForOpenFiles then
    rv, f = reaper.JS_Dialog_BrowseForOpenFiles("Import ChannelView layouts", last_dir(), "", FILTER, false)
    if rv ~= 1 then return nil end
  else
    rv, f = reaper.GetUserFileNameForRead("", "Import ChannelView layouts", "ini")
    if not rv then return nil end
  end
  if not f or f == "" then return nil end
  return f
end

-- Export: every saved layout, the ones for this track's plugins ticked.
function LS.start_export(current_keys)
  local keys = M.keys()
  if #keys == 0 then
    msg("There are no saved layouts to export yet. A plugin's layout is saved\n" ..
        "the first time you change it or save it in Edit parameters.")
    return
  end
  local cur = {}
  for _, k in ipairs(current_keys or {}) do cur[k] = true end
  local list = {}
  for _, k in ipairs(keys) do
    list[#list + 1] = { key = k, controls = M.count_controls(k), pick = cur[k] or false }
  end
  dlg = { mode = "export", list = list, filter = "", open = true }
end

-- Import: pick a file, then which of its layouts. New ones start ticked;
-- ones that would replace yours start unticked; identical ones, and ones
-- whose layout here is locked, can't be.
function LS.start_import()
  local file = ask_open()
  if not file then return end
  remember_dir(file)
  local list, err = M.read_shared(file)
  if not list then msg(err) return end
  for _, e in ipairs(list) do e.pick = (e.status == "new") end
  dlg = { mode = "import", list = list, filter = "", open = true, file = file }
end

local STATUS = { new = "new", differs = "replaces yours", same = "same as yours",
                 locked = "yours is locked" }

local function matches(e, f)
  return f == "" or e.key:lower():find(f:lower(), 1, true) ~= nil
end

-- Call once a frame, outside any panel. `busy(key)` says whether a layout
-- is open in Edit parameters (importing over it would be undone by its
-- Save). Returns true when the library changed.
function LS.draw(ctx, busy)
  if not dlg then return false end
  if dlg.open then ImGui.OpenPopup(ctx, TITLE[dlg.mode]); dlg.open = false end
  ImGui.SetNextWindowSize(ctx, 380, 0, ImGui.Cond_Appearing)
  local visible, open = ImGui.BeginPopupModal(ctx, TITLE[dlg.mode], true,
    ImGui.WindowFlags_AlwaysAutoResize)
  if not visible then
    if not open then dlg = nil end
    return false
  end
  local d, changed = dlg, false
  local function close() dlg = nil; ImGui.CloseCurrentPopup(ctx) end

  if d.mode == "import" then
    ImGui.TextDisabled(ctx, U.truncate(d.file:match("[^\\/]+$") or d.file, 56))
    ImGui.TextWrapped(ctx, "Tick the layouts to bring in. One you already have is replaced \u{2014} " ..
      "your library as it was is kept as TS_ChannelView_Mappings.bak.ini.")
  else
    ImGui.TextWrapped(ctx, "Tick the layouts to export. This track's plugins are ticked to start with.")
  end
  ImGui.Spacing(ctx)

  ImGui.SetNextItemWidth(ctx, 200)
  local _, f = ImGui.InputTextWithHint(ctx, "##sharefilter", "filter\u{2026}", d.filter)
  d.filter = f
  local function can(e) return not (d.mode == "import" and (e.status == "same" or e.status == "locked")) end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "All") then
    for _, e in ipairs(d.list) do if matches(e, d.filter) and can(e) then e.pick = true end end
  end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "None") then
    for _, e in ipairs(d.list) do if matches(e, d.filter) then e.pick = false end end
  end

  local _, line_h = ImGui.CalcTextSize(ctx, "Ag")
  local rows = math.min(#d.list, LIST_ROWS)
  if ImGui.BeginChild(ctx, "##sharelist", 360, rows * (line_h + 8) + 8,
      ImGui.ChildFlags_Borders or 1) then
    for i, e in ipairs(d.list) do
      if matches(e, d.filter) then
        ImGui.BeginDisabled(ctx, not can(e))
        local ch, v = ImGui.Checkbox(ctx, e.key .. "##sh" .. i, e.pick)
        if ch then e.pick = v end
        ImGui.EndDisabled(ctx)
        if e.status == "locked" and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
          ImGui.SetTooltip(ctx, "Your layout for this plugin is locked. Unlock it with the padlock\n" ..
            "in the panel's foot to import this one over it.")
        end
        ImGui.SameLine(ctx)
        local note = ("%d control%s"):format(e.controls, e.controls == 1 and "" or "s")
        if d.mode == "import" then note = STATUS[e.status] .. "  \u{00B7}  " .. note end
        ImGui.TextDisabled(ctx, note)
      end
    end
    ImGui.EndChild(ctx)
  end

  local picked = {}
  for _, e in ipairs(d.list) do if e.pick and can(e) then picked[#picked + 1] = e end end
  ImGui.Spacing(ctx)
  ImGui.BeginDisabled(ctx, #picked == 0)
  local label = (d.mode == "import") and ("Import %d###shgo") or ("Export %d\u{2026}###shgo")
  if ImGui.Button(ctx, label:format(#picked), 120) then
    if d.mode == "export" then
      local keys = {}
      for _, e in ipairs(picked) do keys[#keys + 1] = e.key end
      local name = (#keys == 1) and (safe_name(keys[1]) .. " layout.ini") or "ChannelView layouts.ini"
      local file = ask_save(name)
      if file then
        remember_dir(file)
        local ok, err = M.export(file, keys)
        if ok then
          msg(("Exported %d layout%s to\n%s"):format(#keys, #keys == 1 and "" or "s", file))
          close()
        else
          msg("Couldn't write the file:\n" .. tostring(err))
        end
      end
    else
      local blocked
      for _, e in ipairs(picked) do if busy and busy(e.key) then blocked = e.key end end
      local replacing = 0
      for _, e in ipairs(picked) do if e.status == "differs" then replacing = replacing + 1 end end
      if blocked then
        msg("Close Edit parameters for " .. blocked .. " first: its Save would undo the import.")
      elseif replacing == 0 or reaper.MB(("Replace %d of your layouts with the ones from this file?\n\n" ..
          "Your library as it was is kept as TS_ChannelView_Mappings.bak.ini."):format(replacing),
          "ChannelView", 1) == 1 then
        local n = M.import(picked)
        local ok, err = M.save()
        if not ok then msg("Imported, but the library couldn't be saved:\n" .. tostring(err)) end
        changed = n > 0
        close()
      end
    end
  end
  ImGui.EndDisabled(ctx)
  ImGui.SameLine(ctx)
  if dlg and ImGui.Button(ctx, "Cancel", 90) then close() end
  ImGui.EndPopup(ctx)
  return changed
end

return LS
