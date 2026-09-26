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

local TM = {}
local ImGui

function TM.attach(imgui) ImGui = imgui end

local CTX_ID    = "tm_ctx"
local RENAME_ID = "tm_rename"
local INSERT_ID = "tm_insert"
local COLOUR_ID = "Track colour###tm_colour"

local SWATCH    = 20     -- custom-colour button size
local SWATCH_W  = 12     -- template colour chip in the insert menu
local CHIP_LEFT = 4

local st = {
  ctx_req    = nil,  ctx_track  = nil,
  ren_req    = false, ren_track = nil, ren_buf = "", ren_focus = false,
  col_req    = false, col_tracks = nil, col_rgb = 0x808080, col_swatches = nil,
  ins_req    = false, ins_anchor = nil, ins_tree = nil,
}

-- ---------------------------------------------------------------------
-- requests, from wherever the click happened
-- ---------------------------------------------------------------------

function TM.open_context(track) st.ctx_req = track end

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

  if ImGui.MenuItem(ctx, "Rename\u{2026}", nil, false, not master) then
    st.ren_req, st.ren_track, st.ren_buf = true, tr, TO.name(tr)
  end

  local sp = TO.has_spacer(tr)
  if ImGui.MenuItem(ctx, "Visual spacer before this track", nil, sp, not master) then
    TO.set_spacer(tg, not sp)
    changed = true
  end
  tip_if_hovered(ctx, "A gap before this track, here and in REAPER's track panel.")

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
  local enter, buf = ImGui.InputText(ctx, "##tmname", st.ren_buf,
    ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_AutoSelectAll)
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

local function colour_dialog(ctx)
  if st.col_req then
    st.col_req = false
    st.col_swatches = TO.custom_colours()   -- re-read each time it opens
    ImGui.OpenPopup(ctx, COLOUR_ID)
  end

  local visible, open = ImGui.BeginPopupModal(ctx, COLOUR_ID, true,
    ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse)
  if not visible then return false end

  local changed = false
  local tracks = {}
  for _, tr in ipairs(st.col_tracks or {}) do
    if valid(tr) then tracks[#tracks + 1] = tr end
  end
  if #tracks == 0 then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return false
  end

  ImGui.TextDisabled(ctx, #tracks == 1 and label_of(tracks[1])
                                        or (#tracks .. " tracks"))

  -- REAPER's 16 custom colours: one click applies and closes.
  ImGui.SeparatorText(ctx, "Custom colours")
  local sw = st.col_swatches or {}
  if #sw == 0 then
    ImGui.TextDisabled(ctx, "REAPER's custom colours couldn't be read here.")
  else
    for i, c in ipairs(sw) do
      if (i - 1) % 8 ~= 0 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.ColorButton(ctx, "Custom colour " .. i .. "##tmsw" .. i,
          rgba(c[1], c[2], c[3]), ImGui.ColorEditFlags_NoTooltip, SWATCH, SWATCH) then
        TO.set_colour(tracks, (c[1] << 16) | (c[2] << 8) | c[3])
        changed = true
        ImGui.CloseCurrentPopup(ctx)
      end
      tip_if_hovered(ctx, ("Custom colour %d  #%02X%02X%02X"):format(i, c[1], c[2], c[3]))
    end
  end

  -- Anything else: pick, then Apply.
  ImGui.SeparatorText(ctx, "Any colour")
  ImGui.SetNextItemWidth(ctx, 8 * (SWATCH + 4) + 60)
  local pch, rgb = ImGui.ColorPicker3(ctx, "##tmpick", st.col_rgb,
    ImGui.ColorEditFlags_DisplayRGB | ImGui.ColorEditFlags_DisplayHex)
  if pch then st.col_rgb = rgb end

  ImGui.Spacing(ctx)
  if ImGui.Button(ctx, "Apply") then
    TO.set_colour(tracks, st.col_rgb)
    changed = true
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Remove colour") then
    TO.set_colour(tracks, nil)
    changed = true
    ImGui.CloseCurrentPopup(ctx)
  end
  tip_if_hovered(ctx, "Back to the theme's default track colour.")
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Cancel") or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    ImGui.CloseCurrentPopup(ctx)
  end

  ImGui.EndPopup(ctx)
  if not open then st.col_tracks = nil end
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

function TM.has_templates(tree)
  return tree ~= nil and (#tree.files > 0 or #tree.dirs > 0)
end

local function insert_menu(ctx)
  if st.ins_req then
    st.ins_req = false
    st.ins_tree = TO.list_templates()      -- once per opening, not per frame
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

  ImGui.EndPopup(ctx)
  return changed
end

-- ---------------------------------------------------------------------

-- Draws whichever track popup is open. Call once per frame from the main
-- window, outside any child. Returns true on a frame something changed.
function TM.draw(ctx)
  local changed = false
  if context_menu(ctx)  then changed = true end
  if rename_popup(ctx)  then changed = true end
  if colour_dialog(ctx) then changed = true end
  if insert_menu(ctx)   then changed = true end
  return changed
end

return TM
