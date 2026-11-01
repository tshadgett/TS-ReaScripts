-- @noindex  (a development tool, not a package)
--[[
  TS_Theme_ListProbe.lua -- which theme colours REAPER's own windows
  (the Actions list, the FX browser, dialogs, edit boxes, buttons, the
  dockers' tabs) actually take, before the theme's are set to match
  ChannelView.

  Each button paints one group of theme colours a loud test colour, live
  (nothing is saved). Open (or re-open) the Actions list and the FX
  browser after each and note what turned that colour. "Put them all
  back" restores the colours as they were when this started. The results
  go into dev/listprobe.txt as you note them.
--]]

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ImGui = require("imgui")("0.10")
local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local LOG = own .. "listprobe.txt"

local GROUPS = {
  { "Lists (genlist_*)", 0xff2020, { "genlist_bg" }, 0xffff00, { "genlist_fg" }, 0x20ff20, { "genlist_grid" },
    0x2060ff, { "genlist_selbg" } },
  { "Dialog background and text (col_main_bg2 / text2)", 0x20c040, { "col_main_bg2" }, 0xff00ff, { "col_main_text2" } },
  { "Window background and text (col_main_bg / col_main_text)", 0xc04020, { "col_main_bg" }, 0x00ffff, { "col_main_text" } },
  { "Edit boxes (col_main_editbk)", 0x2040ff, { "col_main_editbk" } },
  { "Buttons (col_buttonbg, col_main_3dhl / 3dsh)", 0xffc000, { "col_buttonbg" }, 0xff0080, { "col_main_3dhl" },
    0x00ff80, { "col_main_3dsh" } },
  { "Dockers and tabs (docker_*, windowtab_bg)", 0x8000ff, { "docker_bg", "windowtab_bg" }, 0xff8000, { "docker_selface" },
    0x00c0c0, { "docker_unselface" } },
  { "Text shadow, resize bar (col_main_textshadow, col_main_resize2)", 0xff0000, { "col_main_textshadow" }, 0x00ff00, { "col_main_resize2" } },
}

local saved = {}
local function save(k) if saved[k] == nil then saved[k] = reaper.GetThemeColor(k, 0) end end
local function native(rgb) return reaper.ColorToNative((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) end
local function refresh()
  reaper.ThemeLayout_RefreshAll(); reaper.UpdateArrange(); reaper.UpdateTimeline()
  reaper.TrackList_AdjustWindows(false); reaper.DockWindowRefresh()
end
local lines = {}
local function log(s)
  lines[#lines + 1] = s
  local f = io.open(LOG, "a"); if f then f:write(s, "\n"); f:close() end
end
log("==== " .. os.date("%Y-%m-%d %H:%M:%S") .. "  REAPER " .. reaper.GetAppVersion() ..
  "  theme " .. ((reaper.GetLastColorThemeFile() or ""):match("[^\\/]*$") or "?"))
do
  local ks = {}
  for _, g in ipairs(GROUPS) do for i = 3, #g, 2 do for _, k in ipairs(g[i]) do ks[#ks + 1] = k end end end
  local parts = {}
  for _, k in ipairs(ks) do
    local v = reaper.GetThemeColor(k, 0)
    local r, gg, b = reaper.ColorFromNative(v)
    parts[#parts + 1] = ("%s=#%02x%02x%02x"):format(k, r, gg, b)
  end
  log("now: " .. table.concat(parts, "  "))
end

local function paint(g)
  local desc = {}
  for i = 2, #g, 2 do
    for _, k in ipairs(g[i + 1]) do
      save(k)
      reaper.SetThemeColor(k, native(g[i]), 1)
      desc[#desc + 1] = ("%s #%06x"):format(k, g[i])
    end
  end
  refresh()
  log("painted " .. g[1] .. ": " .. table.concat(desc, ", "))
end
local function put_back()
  for k, v in pairs(saved) do reaper.SetThemeColor(k, v, 1) end
  saved = {}
  refresh()
  log("put back")
end

local NAMES = { [0xff2020] = "red", [0xffff00] = "yellow", [0x20ff20] = "green", [0x2060ff] = "blue",
  [0x20c040] = "green", [0xff00ff] = "magenta", [0xc04020] = "rust", [0x00ffff] = "cyan", [0x2040ff] = "blue",
  [0xffc000] = "amber", [0xff0080] = "pink", [0x00ff80] = "mint", [0x8000ff] = "purple", [0xff8000] = "orange",
  [0x00c0c0] = "teal", [0xff0000] = "red", [0x00ff00] = "green" }

local ctx = ImGui.CreateContext("TS Theme List Probe")
local note = ""
local function frame()
  ImGui.SetNextWindowSize(ctx, 640, 520, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "Theme list probe", true)
  if visible then
    ImGui.TextWrapped(ctx, "Click a group, then open (or re-open) the Actions list and the FX browser and look. Type what changed colour, and Note it.")
    for gi, g in ipairs(GROUPS) do
      if ImGui.Button(ctx, g[1] .. "##g" .. gi) then paint(g) end
      ImGui.SameLine(ctx)
      local cs = {}
      for i = 2, #g, 2 do cs[#cs + 1] = (NAMES[g[i]] or "?") .. " = " .. table.concat(g[i + 1], "/") end
      ImGui.TextDisabled(ctx, table.concat(cs, ", "))
    end
    if ImGui.Button(ctx, "Put them all back") then put_back() end
    ImGui.SetNextItemWidth(ctx, 460)
    local _, v = ImGui.InputText(ctx, "##note", note)
    note = v
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Note") and note ~= "" then log("NOTE: " .. note); note = "" end
    ImGui.Separator(ctx)
    for _, s in ipairs(lines) do ImGui.TextWrapped(ctx, s) end
    ImGui.End(ctx)
  end
  if open then reaper.defer(frame) else put_back() end
end
reaper.atexit(function() if next(saved) then put_back() end end)
reaper.defer(frame)
