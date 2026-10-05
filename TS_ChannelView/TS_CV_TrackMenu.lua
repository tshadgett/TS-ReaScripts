-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_TrackMenu.lua -- the track menus: right-click, rename, colour, and
  the "+" insert menu.

  Every one of these is opened from inside a track row's child window
  but drawn from the main window, once per frame, by TM.draw. A popup's
  id is resolved against the window it's opened in, so opening one from
  inside a child and drawing it from outside would never match up; the
  open calls here only record what was asked for, and TM.draw does the
  actual opening at the level it draws at -- the same arrangement the
  plugin browser uses.

  What a menu item acts on follows REAPER's own rule: right-click a track
  that's part of the selection and colour/spacer changes apply to the
  whole selection; right-click one that isn't and they apply to it alone.
  The selection itself is never changed by opening a menu. Rename and the
  folder moves always act on the one track clicked.

  All the actual work is in TS_CV_TrackOps.lua.
--]]

local C  = require("TS_CV_Config")
local TO = require("TS_CV_TrackOps")
local CN = require("TS_CV_Chains")
local IC = require("TS_CV_Icons")
local LN = require("TS_CV_Lanes")
local AC = require("TS_CV_Actions")
local CP = require("TS_CV_ColourPick")

local TM = {}
local ImGui

-- The chains menu items are drawn from inside these menus, so Chains is
-- attached along with them -- the TCP window uses these menus too.
function TM.attach(imgui) ImGui = imgui; CN.attach(imgui); CP.attach(imgui) end

local CTX_ID    = "tm_ctx"
local RENAME_ID = "tm_rename"
local INSERT_ID = "tm_insert"
local COLOUR_ID = "Track colour###tm_colour"

local SWATCH_W  = 12     -- template colour chip in the insert menu
local CHIP_LEFT = 4

local st = {
  ctx_req    = nil,  ctx_track  = nil, ctx_tree = nil, ctx_chains = nil,
  ren_req    = false, ren_track = nil, ren_buf = "", ren_focus = false,
  col_req    = false, col_tracks = nil, col_rgb = 0x808080, col = nil,
  ins_req    = false, ins_anchor = nil, ins_tree = nil,
}

-- ---------------------------------------------------------------------
-- requests, from wherever the click happened
-- ---------------------------------------------------------------------

function TM.open_context(track) st.ctx_req = track end

-- Straight to the rename box, without the menu: a double-click on a
-- TCP name, which is where REAPER's own track panel renames too.
function TM.open_rename(track)
  if not track or TO.is_master(track) then return end
  st.ren_req, st.ren_track, st.ren_buf = true, track, TO.name(track)
end

-- `after`: the track a new one should follow, or nil for the end.
function TM.open_insert(after)
  st.ins_req = true
  st.ins_anchor = after
end

-- ---------------------------------------------------------------------

local function valid(track)
  return track ~= nil and reaper.ValidatePtr2(0, track, "MediaTrack*")
end

local function label_of(track)
  if TO.is_master(track) then return "MASTER" end
  local n = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  local nm = TO.name(track)
  if nm == "" then nm = "Track " .. n end
  return ("%d  %s"):format(n, nm)
end

-- The clicked track, or the whole selection when the clicked track is
-- part of it.
local function targets(track)
  if reaper.IsTrackSelected(track) then
    local out = {}
    for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
      out[#out + 1] = reaper.GetSelectedTrack2(0, i, true)
    end
    if #out > 0 then return out end
  end
  return { track }
end

local function tip_if_hovered(ctx, text)
  if text and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, text) end
end

-- ---------------------------------------------------------------------
-- right-click
-- ---------------------------------------------------------------------

local function context_menu(ctx)
  if st.ctx_req then
    st.ctx_track = st.ctx_req
    st.ctx_req = nil
    st.ctx_tree = nil                      -- templates re-read per opening
    st.ctx_chains = nil
    ImGui.OpenPopup(ctx, CTX_ID)
  end
  if not ImGui.BeginPopup(ctx, CTX_ID) then return false end

  local tr = st.ctx_track
  if not valid(tr) then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return false
  end

  local changed = false
  local master  = TO.is_master(tr)
  local tg      = targets(tr)

  ImGui.TextDisabled(ctx, label_of(tr) ..
    (#tg > 1 and ("   (+%d selected)"):format(#tg - 1) or ""))
  ImGui.Separator(ctx)

  -- The "+" menu's two choices, landing after this track (at the end of
  -- the project from the master).
  if ImGui.BeginMenu(ctx, "Add track") then
    if ImGui.MenuItem(ctx, master and "New track at the end"
                                  or "New track after this one") then
      TO.insert_new(tr)
      changed = true
    end
    -- Read the first time the submenu opens, not on every right-click.
    if not st.ctx_tree then st.ctx_tree = TO.list_templates() end
    local tree = st.ctx_tree
    if ImGui.BeginMenu(ctx, "New track from template", TM.has_templates(tree)) then
      TM.template_items(ctx, tree, function(path)
        TO.insert_template(path, tr)
        changed = true
      end)
      ImGui.EndMenu(ctx)
    end
    if not TM.has_templates(tree) then
      tip_if_hovered(ctx, "No track templates found in " .. (TO.templates_dir()))
    end
    if not st.ctx_chains then st.ctx_chains = CN.list() end
    if TM.chain_menu(ctx, st.ctx_chains, tr) then changed = true end
    ImGui.EndMenu(ctx)
  end

  ImGui.Separator(ctx)

  if ImGui.MenuItem(ctx, "Rename\u{2026}", nil, false, not master) then
    st.ren_req, st.ren_track, st.ren_buf = true, tr, TO.name(tr)
  end

  local sp = TO.has_spacer(tr)
  if ImGui.MenuItem(ctx, "Visual spacer before this track", nil, sp, not master) then
    TO.set_spacer(tg, not sp)
    changed = true
  end
  tip_if_hovered(ctx, "A gap before this track, here and in REAPER's track panel.")

  local fixed = LN.is_fixed(tr)
  if ImGui.MenuItem(ctx, "Fixed item lanes", nil, fixed, not master) then
    LN.set_fixed(tg, not fixed)
    changed = true
  end
  tip_if_hovered(ctx, "REAPER 7's lanes: several lanes of items inside the track,\n" ..
    "for takes and comping. Each gets a play button in the TCP.")
  if fixed and LN.count(tr) > 1 then
    local col = LN.collapsed(tr)
    if ImGui.MenuItem(ctx, "Collapse lanes", nil, col) then
      LN.set_collapsed(tr, not col)
      changed = true
    end
  end

  ImGui.Separator(ctx)

  local into, why_in = TO.folder_plan(tr, true)
  if ImGui.MenuItem(ctx, "Move into folder above", nil, false, into ~= nil) then
    TO.move_level(tr, true)
    changed = true
  end
  tip_if_hovered(ctx, into and "One folder level deeper." or why_in)

  local out, why_out = TO.folder_plan(tr, false)
  if ImGui.MenuItem(ctx, "Move out of folder", nil, false, out ~= nil) then
    TO.move_level(tr, false)
    changed = true
  end
  tip_if_hovered(ctx, out and "One folder level shallower." or why_out)

  -- The folder's three states, the same three the folder button cycles
  -- through and REAPER's track panel shows. Applies to every folder
  -- parent among the targets.
  if TO.is_folder_parent(tr) and ImGui.BeginMenu(ctx, "Folder children") then
    local mode = TO.folder_mode(tr)
    for m = 0, 2 do
      if ImGui.MenuItem(ctx, TO.FOLDER_MODE_NAME[m], nil, mode == m) then
        TO.set_folder_mode(tg, m)
        changed = true
      end
    end
    ImGui.EndMenu(ctx)
  end

  ImGui.Separator(ctx)

  if ImGui.MenuItem(ctx, "Colour\u{2026}") then
    st.col_req    = true
    st.col_tracks = tg
    st.col_rgb    = TO.colour_rgb(tr) or 0x808080
  end
  if ImGui.MenuItem(ctx, "Icon\u{2026}") then
    st.ico_req, st.ico_tracks = true, tg
  end

  ImGui.Separator(ctx)
  local many = #tg > 1
  if ImGui.MenuItem(ctx, many and ("Duplicate %d tracks"):format(#tg) or "Duplicate track",
      nil, false, not master) then
    TO.duplicate_tracks(tg)
    changed = true
  end
  if ImGui.MenuItem(ctx, many and ("Remove %d tracks"):format(#tg) or "Remove track",
      nil, false, not master) then
    TO.remove_tracks(tg)
    changed = true
  end

  ImGui.EndPopup(ctx)
  return changed
end

-- ---------------------------------------------------------------------
-- rename
-- ---------------------------------------------------------------------

local function rename_popup(ctx)
  if st.ren_req then
    st.ren_req = false
    st.ren_focus = true
    ImGui.OpenPopup(ctx, RENAME_ID)
  end
  if not ImGui.BeginPopup(ctx, RENAME_ID) then return false end

  local changed = false
  local tr = st.ren_track
  if not valid(tr) then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return false
  end

  ImGui.TextDisabled(ctx, "Rename " .. label_of(tr))
  if st.ren_focus then
    ImGui.SetKeyboardFocusHere(ctx)
    st.ren_focus = false
  end
  ImGui.SetNextItemWidth(ctx, 240)
  local _, buf = ImGui.InputText(ctx, "##tmname", st.ren_buf, ImGui.InputTextFlags_AutoSelectAll)
  local enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  st.ren_buf = buf
  ImGui.SameLine(ctx)
  local ok = ImGui.Button(ctx, "OK")
  if enter or ok then
    TO.rename(tr, st.ren_buf)
    changed = true
    ImGui.CloseCurrentPopup(ctx)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    ImGui.CloseCurrentPopup(ctx)
  end

  ImGui.EndPopup(ctx)
  return changed
end

-- ---------------------------------------------------------------------
-- colour
-- ---------------------------------------------------------------------

local function rgba(r, g, b) return (r << 24) | (g << 16) | (b << 8) | 0xff end

-- REAPER's own picker on these tracks, for its built-in palettes. It
-- works on the selected tracks, so these become the selection.
local function open_reaper_picker(tracks)
  reaper.PreventUIRefresh(1)
  reaper.SetOnlyTrackSelected(tracks[1])
  for i = 2, #tracks do reaper.SetTrackSelected(tracks[i], true) end
  reaper.PreventUIRefresh(-1)
  return AC.run("Track: Set to custom color...", 40357)
end

-- The palettes, the picker and its eyedropper are TS_CV_ColourPick's,
-- shared with the faceplate colour dialog.
local function colour_dialog(ctx)
  if st.col_req then
    st.col_req = false
    st.col = CP.new_state(st.col_rgb)
    ImGui.OpenPopup(ctx, COLOUR_ID)
  end

  local visible, open = ImGui.BeginPopupModal(ctx, COLOUR_ID, true,
    ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse)
  if not visible then
    if st.col then CP.release(st.col); st.col = nil end
    return false
  end
  st.col = st.col or CP.new_state(st.col_rgb)
  local s = st.col

  local changed, close = false, false
  local tracks = {}
  for _, tr in ipairs(st.col_tracks or {}) do
    if valid(tr) then tracks[#tracks + 1] = tr end
  end
  if #tracks == 0 then
    CP.release(s)
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return false
  end

  ImGui.TextDisabled(ctx, #tracks == 1 and label_of(tracks[1])
                                        or (#tracks .. " tracks"))

  -- A palette, any of REAPER's (built-in, user, the project's colours) or
  -- the old custom colours; one click on a swatch applies and closes.
  ImGui.SeparatorText(ctx, "Palette")
  local p = CP.palette(ctx, s, "tm")
  if p then
    TO.set_colour(tracks, p)
    changed, close = true, true
  end
  if not close and ImGui.Button(ctx, "REAPER's colour picker\u{2026}") then
    open_reaper_picker(tracks)
    changed, close = true, true
  end
  tip_if_hovered(ctx, "REAPER's own picker, with live preview and palette editing.\n" ..
                      "It colours the selected tracks, so these tracks become the selection.")

  -- Anything else -- or anything on screen, with the eyedropper: pick,
  -- then Apply.
  ImGui.SeparatorText(ctx, "Any colour")
  CP.any_colour(ctx, s, "tm")

  ImGui.Spacing(ctx)
  if not close then
    if ImGui.Button(ctx, "Apply") then
      TO.set_colour(tracks, s.rgb)
      changed, close = true, true
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Remove colour") then
      TO.set_colour(tracks, nil)
      changed, close = true, true
    end
    tip_if_hovered(ctx, "Back to the theme's default track colour.")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel")
       or (not CP.dropping() and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)) then
      close = true
    end
  end

  if close then
    CP.release(s)
    st.col = nil
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.EndPopup(ctx)
  if not open then
    CP.release(s)
    st.col, st.col_tracks = nil, nil
  end
  return changed
end

-- ---------------------------------------------------------------------
-- insert
-- ---------------------------------------------------------------------

-- A menu label with room reserved at the front for a colour chip, which
-- is then painted into the item's own rectangle so it lines up whatever
-- the font. A template with no colour gets an empty outline, so the names
-- still line up.
local function chip_pad(ctx)
  local sw = ImGui.CalcTextSize(ctx, " ")
  if not sw or sw <= 0 then return "     " end
  return (" "):rep(math.ceil((CHIP_LEFT + SWATCH_W + 6) / sw))
end

local function chip(ctx, native)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y  = ImGui.GetItemRectMin(ctx)
  local _, y2 = ImGui.GetItemRectMax(ctx)
  local cy = (y + y2) * 0.5
  local h  = math.min(SWATCH_W, y2 - y - 4)
  local x0, y0 = x + CHIP_LEFT, cy - h * 0.5
  if native then
    local r, g, b = reaper.ColorFromNative(native)
    ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + SWATCH_W, y0 + h, rgba(r, g, b), 2.0)
  else
    ImGui.DrawList_AddRect(dl, x0, y0, x0 + SWATCH_W, y0 + h, C.COL.panel_border, 2.0)
  end
end

local function items(ctx, node, pad, on_pick)
  for _, d in ipairs(node.dirs) do
    if ImGui.BeginMenu(ctx, d.name) then
      items(ctx, d.node, pad, on_pick)
      ImGui.EndMenu(ctx)
    end
  end
  for i, f in ipairs(node.files) do
    if ImGui.MenuItem(ctx, ("%s%s##tt%d"):format(pad, f.name, i)) then
      on_pick(f.path)
    end
    chip(ctx, f.colour)
  end
end

-- The TrackTemplates tree (TO.list_templates) as menu items -- subfolders
-- as submenus, each template with its colour chip. `on_pick(path)` is
-- called for the one chosen. Draw inside an open menu or popup.
function TM.template_items(ctx, tree, on_pick)
  if not tree then return end
  items(ctx, tree, chip_pad(ctx), on_pick)
end

-- "New track with FX chain" and its submenu: the FXChains tree, each
-- chain making a new track (named after it) with the chain loaded, after
-- `after`, or at the end with `at_end`. Returns the new track on the frame
-- one was made. Draw inside an open menu or popup.
function TM.chain_menu(ctx, chains, after, at_end, label)
  at_end = at_end or false
  local made = nil
  local has = CN.has_chains(chains)
  if ImGui.BeginMenu(ctx, label or "New track with FX chain", has) then
    CN.items(ctx, chains, function(f) made = CN.new_track(f, after, at_end) end)
    ImGui.EndMenu(ctx)
  end
  if not has then
    tip_if_hovered(ctx, "No FX chains found in " .. (CN.dir()))
  end
  return made
end

function TM.has_templates(tree)
  return tree ~= nil and (#tree.files > 0 or #tree.dirs > 0)
end

local function insert_menu(ctx)
  if st.ins_req then
    st.ins_req = false
    st.ins_tree = TO.list_templates()      -- once per opening, not per frame
    st.ins_chains = CN.list()
    ImGui.OpenPopup(ctx, INSERT_ID)
  end
  if not ImGui.BeginPopup(ctx, INSERT_ID) then return false end

  local changed = false
  local anchor = st.ins_anchor
  if not valid(anchor) or TO.is_master(anchor) then anchor = nil end
  ImGui.TextDisabled(ctx, anchor and ("Insert after " .. label_of(anchor))
                                  or "Add at the end of the project")
  ImGui.Separator(ctx)

  if ImGui.MenuItem(ctx, "Insert new track") then
    TO.insert_new(anchor)
    changed = true
  end

  local tree = st.ins_tree
  if ImGui.BeginMenu(ctx, "Insert from track template", TM.has_templates(tree)) then
    TM.template_items(ctx, tree, function(path)
      TO.insert_template(path, st.ins_anchor)
      changed = true
    end)
    ImGui.EndMenu(ctx)
  end
  if not TM.has_templates(tree) then
    tip_if_hovered(ctx, "No track templates found in " .. (TO.templates_dir()))
  end
  if TM.chain_menu(ctx, st.ins_chains, anchor, false, "Insert new track with FX chain") then
    changed = true
  end

  ImGui.EndPopup(ctx)
  return changed
end

-- ---------------------------------------------------------------------

-- Draws whichever track popup is open. Call once per frame from the main
-- window, outside any child. Returns true on a frame something changed.
-- ---------------------------------------------------------------------
-- icon
-- ---------------------------------------------------------------------

-- REAPER's track icons live in Data/track_icons. Picking one sets P_ICON
-- -- the field REAPER's own "Set track icon" writes -- so its TCP and
-- mixer show it as well as ours. Applies to the selection when the
-- clicked track is part of it, like colour.
local ICON_ID  = "tm_icon"
local ICO_CELL = 40
local ico = { list = nil, dir = nil, filter = "" }

local function list_track_icons()
  local root = reaper.GetResourcePath()
  local sep = root:find("\\", 1, true) and "\\" or "/"
  local dir = root .. sep .. "Data" .. sep .. "track_icons"
  local out, i = {}, 0
  while true do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    local l = f:lower()
    if l:match("%.png$") or l:match("%.jpe?g$") or l:match("%.ico$") or l:match("%.bmp$") then
      out[#out + 1] = { name = f, path = dir .. sep .. f }
    end
    i = i + 1
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out, dir
end

local function set_icon(tracks, path)
  reaper.Undo_BeginBlock()
  for _, tr in ipairs(tracks) do
    if valid(tr) then reaper.GetSetMediaTrackInfo_String(tr, "P_ICON", path or "", true) end
  end
  reaper.Undo_EndBlock(path and "ChannelView: set track icon"
                            or "ChannelView: remove track icon", -1)
  reaper.TrackList_AdjustWindows(false)
end

local function icon_picker(ctx)
  if st.ico_req then
    st.ico_req = false
    ico.list, ico.dir = list_track_icons()
    ico.filter = ""
    ImGui.OpenPopup(ctx, ICON_ID)
  end
  if not ImGui.BeginPopup(ctx, ICON_ID) then return false end
  local changed = false
  local tracks = {}
  for _, tr in ipairs(st.ico_tracks or {}) do
    if valid(tr) then tracks[#tracks + 1] = tr end
  end
  if #tracks == 0 then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return false
  end

  ImGui.TextDisabled(ctx, #tracks == 1 and label_of(tracks[1]) or (#tracks .. " tracks"))
  ImGui.SetNextItemWidth(ctx, 200)
  -- Enter takes the first icon the filter shows
  local _, v = ImGui.InputTextWithHint(ctx, "##icoflt", "filter\u{2026}", ico.filter)
  local ico_enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  ico.filter = v
  local first_ico
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "No icon") then
    set_icon(tracks, nil)
    changed = true
    ImGui.CloseCurrentPopup(ctx)
  end

  local list = ico.list or {}
  if #list == 0 then
    ImGui.TextDisabled(ctx, "No icons in " .. tostring(ico.dir))
  else
    local cols = 10
    if ImGui.BeginChild(ctx, "icogrid", cols * (ICO_CELL + 4) + 12, 320) then
      local dl = ImGui.GetWindowDrawList(ctx)
      local flt = ico.filter:lower()
      local n = 0
      for _, f in ipairs(list) do
        if flt == "" or f.name:lower():find(flt, 1, true) then
          first_ico = first_ico or f
          if n % cols ~= 0 then ImGui.SameLine(ctx, 0, 4) end
          n = n + 1
          local x, y = ImGui.GetCursorScreenPos(ctx)
          if ImGui.InvisibleButton(ctx, "ico" .. f.name, ICO_CELL, ICO_CELL) then
            set_icon(tracks, f.path)
            changed = true
            ImGui.CloseCurrentPopup(ctx)
          end
          local hov = ImGui.IsItemHovered(ctx)
          if hov then
            ImGui.DrawList_AddRectFilled(dl, x, y, x + ICO_CELL, y + ICO_CELL,
              C.COL.knob_body_hi, 2.5)
          end
          -- Only what's scrolled into view is loaded.
          if ImGui.IsItemVisible(ctx) then
            IC.draw(ctx, dl, f.path, x + 3, y + 3, ICO_CELL - 6, ICO_CELL - 6)
          end
          if hov then ImGui.SetTooltip(ctx, f.name) end
        end
      end
      if n == 0 then ImGui.TextDisabled(ctx, "Nothing matches.") end
      ImGui.EndChild(ctx)
    end
    if ico_enter and first_ico then
      set_icon(tracks, first_ico.path)
      changed = true
      ImGui.CloseCurrentPopup(ctx)
    end
  end
  ImGui.EndPopup(ctx)
  return changed
end

function TM.draw(ctx)
  local changed = false
  if context_menu(ctx)  then changed = true end
  if rename_popup(ctx)  then changed = true end
  if colour_dialog(ctx) then changed = true end
  if icon_picker(ctx)   then changed = true end
  if insert_menu(ctx)   then changed = true end
  return changed
end

return TM
