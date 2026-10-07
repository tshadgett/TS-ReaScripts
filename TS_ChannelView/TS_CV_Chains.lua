-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Chains.lua -- loading, saving and deleting FX chains.

  The chains are REAPER's own: every .RfxChain file under the FXChains
  folder in the resource path, subfolders as submenus, the same files
  REAPER's "Add FX chain" browser shows. Picking one adds its plugins to
  the end of the track's chain, or, with "Replace the existing FX" ticked,
  in place of everything already there. Either way it is one undo step.

  Saving writes the track's whole chain -- or one container and what's in
  it -- as an .RfxChain, the same text REAPER writes for "Save FX chain":
  the chain's block from the track's state chunk, without the window
  lines at its head. Deleting removes the file, after asking.

  The menu is opened from the header bar but drawn from the main window
  (CN.open only records the request, CN.draw opens and draws it), for the
  same reason the track menus are: a popup's id belongs to the place it
  is opened, and the menu bar is a place of its own.
--]]

local C  = require("TS_CV_Config")
local TO = require("TS_CV_TrackOps")

local CN = {}
local ImGui

function CN.attach(imgui) ImGui = imgui end

local POPUP_ID = "cn_chains"
local REPLACE_KEY = "chain_replace"

local st = { req = false, track = nil, tree = nil,
             save = nil }   -- the Save dialog: { track, path, label, name, folder, req }

-- ---------------------------------------------------------------------
-- pure
-- ---------------------------------------------------------------------

function CN.is_chain(file)
  return type(file) == "string" and file:lower():match("%.rfxchain$") ~= nil
end

-- "Lead Vocal.RfxChain" -> "Lead Vocal"
function CN.chain_name(file)
  return (file:gsub("%.[Rr][Ff][Xx][Cc][Hh][Aa][Ii][Nn]$", ""))
end

-- ---------------------------------------------------------------------
-- an .RfxChain from a track's state chunk (pure: tested)
-- ---------------------------------------------------------------------

local function trim(l) return (l:gsub("^%s+", ""):gsub("%s+$", "")) end

-- The FX entries of one level, from `lines[a..b]` (the inside of an
-- FXCHAIN or CONTAINER block): each { a, b } runs from its BYPASS line to
-- the line before the next one at this level. Lines before the first
-- BYPASS are the block's own header (window, selection, container setup).
local function entries(lines, a, b)
  local out, depth, cur = {}, 0, nil
  for i = a, b do
    local t = trim(lines[i])
    if depth == 0 and t:match("^BYPASS%s") then
      if cur then cur.b = i - 1 end
      cur = { a = i }
      out[#out + 1] = cur
    end
    if t:sub(1, 1) == "<" then depth = depth + 1
    elseif t == ">" then depth = depth - 1 end
  end
  if cur then cur.b = b end
  return out
end

-- Where a block opened on line `i` ends (its closing ">").
local function block_end(lines, i)
  local depth = 0
  for k = i, #lines do
    local t = trim(lines[k])
    if t:sub(1, 1) == "<" then depth = depth + 1
    elseif t == ">" then
      depth = depth - 1
      if depth == 0 then return k end
    end
  end
  return #lines
end

-- The text of an .RfxChain for a track: its whole FX chain, or with
-- `path` (slot numbers from the top level down, as TS_CV_FXTree gives
-- them) the container there and everything in it. nil when there is no
-- chain, or nothing at that path.
function CN.chain_text(chunk, path)
  local lines = {}
  for l in (chunk .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = l end
  local fa
  for i, l in ipairs(lines) do
    if trim(l):match("^<FXCHAIN$") or trim(l):match("^<FXCHAIN%s") then fa = i break end
  end
  if not fa then return nil end
  local a, b = fa + 1, block_end(lines, fa) - 1
  local list = entries(lines, a, b)
  if #list == 0 then return nil end
  local pick
  if path and #path > 0 then
    for depth, slot in ipairs(path) do
      local e = list[slot + 1]
      if not e then return nil end
      if depth == #path then pick = e break end
      -- into the container: its block's inside
      local open
      for k = e.a, e.b do
        if trim(lines[k]):match("^<CONTAINER") then open = k break end
      end
      if not open then return nil end
      list = entries(lines, open + 1, block_end(lines, open) - 1)
    end
    if not pick then return nil end
    a, b = pick.a, pick.b
  else
    a, b = list[1].a, list[#list].b
  end
  local out = {}
  for k = a, b do out[#out + 1] = trim(lines[k]) end
  return table.concat(out, "\n") .. "\n"
end

-- A name that's safe as a file name on every system ("" when nothing is
-- left of it).
function CN.safe_name(s)
  s = tostring(s or ""):gsub('[\\/:%*%?"<>|%c]', " "):gsub("%s+", " ")
  return (s:gsub("^%s+", ""):gsub("[%s%.]+$", ""))
end

-- ---------------------------------------------------------------------
-- the FXChains folder
-- ---------------------------------------------------------------------

function CN.dir()
  local root = reaper.GetResourcePath()
  local sep = root:find("\\", 1, true) and "\\" or "/"
  return root .. sep .. "FXChains", sep
end

local function sort_ci(list)
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
end

-- The folder as a tree: { dirs = { { name, node }... },
-- files = { { name, path, rel }... } }, where rel is the path under the
-- FXChains folder. Re-read every call; call it when the menu opens.
function CN.list()
  local root, sep = CN.dir()
  local function scan(dir, rel, depth)
    local node = { dirs = {}, files = {} }
    if depth > 8 then return node end
    reaper.EnumerateFiles(dir, -1)             -- drop REAPER's listing cache
    reaper.EnumerateSubdirectories(dir, -1)
    local i = 0
    while true do
      local f = reaper.EnumerateFiles(dir, i)
      if not f then break end
      if CN.is_chain(f) then
        node.files[#node.files + 1] = { name = CN.chain_name(f),
          path = dir .. sep .. f, rel = rel .. f }
      end
      i = i + 1
    end
    i = 0
    while true do
      local d = reaper.EnumerateSubdirectories(dir, i)
      if not d then break end
      local sub = scan(dir .. sep .. d, rel .. d .. sep, depth + 1)
      if #sub.files > 0 or #sub.dirs > 0 then
        node.dirs[#node.dirs + 1] = { name = d, node = sub }
      end
      i = i + 1
    end
    sort_ci(node.files)
    sort_ci(node.dirs)
    return node
  end
  return scan(root, "", 0)
end

function CN.replace_on()
  return reaper.GetExtState(C.EXT_SECT, REPLACE_KEY) == "1"
end

local function set_replace(on)
  reaper.SetExtState(C.EXT_SECT, REPLACE_KEY, on and "1" or "0", true)
end

-- Adds the chain `f` (an entry from CN.list) to the end of the track's
-- FX, or in place of them when `replace`. TrackFX_AddByName takes an
-- .RfxChain directly; it's given the path under FXChains first, the way
-- REAPER names chains itself, then the full path. Returns true when
-- anything was added; when nothing could be, the track is left as it was.
local function add(track, f, replace)
  local before = reaper.TrackFX_GetCount(track)
  local kept = {}
  if replace then
    -- Added first and the old ones removed after, so a chain that fails
    -- to load doesn't cost the track its existing plugins.
    for i = 0, before - 1 do kept[#kept + 1] = reaper.TrackFX_GetFXGUID(track, i) end
  end
  local ok = false
  for _, name in ipairs({ f.rel, f.path }) do
    reaper.TrackFX_AddByName(track, name, false, -1)
    if reaper.TrackFX_GetCount(track) > before then ok = true break end
  end
  if ok and replace then
    for i = reaper.TrackFX_GetCount(track) - 1, 0, -1 do
      local g = reaper.TrackFX_GetFXGUID(track, i)
      for _, k in ipairs(kept) do
        if g == k then reaper.TrackFX_Delete(track, i) break end
      end
    end
  end
  return ok
end

function CN.load(track, f, replace)
  if not track or not f then return false end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local ok = add(track, f, replace)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock((replace and "ChannelView: replace FX with chain "
                                 or "ChannelView: load FX chain ") .. f.name, -1)
  return ok
end

-- A new track with the chain `f` on it, named after the chain -- the
-- third way in beside "New track" and "New track from template". Placed
-- after `after` the way the track menus insert (TO.insert_new), or, with
-- `at_end`, at the end of the project without touching the selection,
-- for the send and receive menus. One undo step. Returns the new track.
function CN.new_track(f, after, at_end)
  if not f then return nil end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local tr
  if at_end then
    tr = TO.new_track_at_end()
  else
    local had = {}
    for i = 0, reaper.CountTracks(0) - 1 do had[reaper.GetTrack(0, i)] = true end
    TO.insert_new(after)
    for i = 0, reaper.CountTracks(0) - 1 do
      local t = reaper.GetTrack(0, i)
      if not had[t] then tr = t break end
    end
  end
  if tr then
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", f.name, true)
    add(tr, f, false)
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: new track with FX chain " .. f.name, -1)
  reaper.TrackList_AdjustWindows(false)
  return tr
end

local function valid(track)
  return track ~= nil and reaper.ValidatePtr2(0, track, "MediaTrack*")
end

local function track_label(track)
  if track == reaper.GetMasterTrack(0) then return "MASTER" end
  local _, n = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  local num = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  if n == nil or n == "" then return "Track " .. num end
  return ("%d  %s"):format(num, n)
end

-- ---------------------------------------------------------------------
-- saving and deleting
-- ---------------------------------------------------------------------

-- Every folder under FXChains, as paths relative to it ("" the top),
-- sorted, for the Save dialog's folder list.
function CN.folders(tree)
  local out = { "" }
  local _, sep = CN.dir()
  local function walk(node, rel)
    for _, d in ipairs(node.dirs or {}) do
      local r = rel .. d.name
      out[#out + 1] = r
      walk(d.node, r .. sep)
    end
  end
  if tree then walk(tree, "") end
  return out
end

-- Every folder, empty ones too (CN.list leaves those out of the menus).
local function all_folders()
  local root, sep = CN.dir()
  local out = { "" }
  local function scan(dir, rel, depth)
    if depth > 8 then return end
    reaper.EnumerateSubdirectories(dir, -1)
    local subs, i = {}, 0
    while true do
      local d = reaper.EnumerateSubdirectories(dir, i)
      if not d then break end
      subs[#subs + 1] = d
      i = i + 1
    end
    table.sort(subs, function(a, b) return a:lower() < b:lower() end)
    for _, d in ipairs(subs) do
      out[#out + 1] = rel .. d
      scan(dir .. sep .. d, rel .. d .. sep, depth + 1)
    end
  end
  scan(root, "", 0)
  return out
end

-- Where a chain called `name` in `folder` (relative to FXChains) goes.
function CN.file_for(folder, name)
  local root, sep = CN.dir()
  local dir = (folder and folder ~= "") and (root .. sep .. folder) or root
  return dir .. sep .. name .. ".RfxChain", dir
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- Writes the track's chain (or the container at `path`) as `name` in
-- `folder`. Returns true, or false and why.
function CN.save(track, path, folder, name)
  name = CN.safe_name(name)
  if name == "" then return false, "Give the chain a name." end
  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  if not ok then return false, "Couldn't read the track." end
  local text = CN.chain_text(chunk, path)
  if not text then return false, "There's nothing to save there." end
  local file, dir = CN.file_for(folder, name)
  reaper.RecursiveCreateDirectory(dir, 0)
  local fh = io.open(file, "wb")
  if not fh then return false, "Couldn't write\n" .. file end
  fh:write(text)
  fh:close()
  return true
end

-- Deletes a chain file (an entry from CN.list). Permanent: no Recycle Bin
-- from a script. Returns true, or false and why.
function CN.delete(f)
  if not f or not f.path then return false end
  local ok, err = os.remove(f.path)
  if not ok then return false, tostring(err) end
  return true
end

-- Opens the Save dialog: the track's whole chain, or with `path` the
-- container there (`label` names it in the dialog).
function CN.open_save(track, path, label)
  st.save = { track = track, path = path, label = label, name = label or "",
              folder = "", req = true, folders = all_folders() }
end

local SAVE_ID = "cn_save"

local function draw_save(ctx)
  local sv = st.save
  if not sv then return end
  if sv.req then
    sv.req = false
    ImGui.OpenPopup(ctx, SAVE_ID)
  end
  if not ImGui.BeginPopup(ctx, SAVE_ID) then
    st.save = nil
    return
  end
  if not valid(sv.track) then
    ImGui.CloseCurrentPopup(ctx); ImGui.EndPopup(ctx); st.save = nil
    return
  end
  ImGui.TextDisabled(ctx, sv.path and ("Save the container " .. (sv.label or "") .. " as an FX chain")
                                   or ("Save the FX chain on " .. track_label(sv.track)))
  ImGui.SetNextItemWidth(ctx, 240)
  if sv.focus == nil then ImGui.SetKeyboardFocusHere(ctx); sv.focus = true end
  local _, nm = ImGui.InputTextWithHint(ctx, "Name##cnname", "chain name", sv.name)
  local enter = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
  sv.name = nm
  ImGui.SetNextItemWidth(ctx, 240)
  if ImGui.BeginCombo(ctx, "Folder##cnfolder", sv.folder == "" and "FXChains" or sv.folder) then
    for _, f in ipairs(sv.folders or { "" }) do
      if ImGui.Selectable(ctx, (f == "" and "FXChains" or f) .. "##cnf" .. f, f == sv.folder) then sv.folder = f end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.TextDisabled(ctx, "A new folder: type it before the name, as Folder/Name.")
  ImGui.Separator(ctx)
  local go = ImGui.Button(ctx, "Save##cnsave") or enter
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Cancel##cncancel") then
    ImGui.CloseCurrentPopup(ctx); ImGui.EndPopup(ctx); st.save = nil
    return
  end
  if go then
    -- "Folder/Name" makes (or uses) a folder under the chosen one
    local folder, name = sv.folder, sv.name
    local sub, base = name:match("^(.*)[/\\]([^/\\]*)$")
    if sub then
      local _, sep = CN.dir()
      local parts = {}
      for piece in sub:gmatch("[^/\\]+") do
        local p = CN.safe_name(piece)
        if p ~= "" then parts[#parts + 1] = p end
      end
      if #parts > 0 then
        folder = (folder ~= "" and (folder .. sep) or "") .. table.concat(parts, sep)
      end
      name = base
    end
    local file = CN.file_for(folder, CN.safe_name(name))
    local go_on = true
    if CN.safe_name(name) ~= "" and exists(file) then
      go_on = reaper.MB("There's already a chain called \"" .. CN.safe_name(name) ..
        "\" there.\n\nReplace it?", "ChannelView", 4) == 6
    end
    if go_on then
      local ok, why = CN.save(sv.track, sv.path, folder, name)
      if ok then
        ImGui.CloseCurrentPopup(ctx); ImGui.EndPopup(ctx); st.save = nil
        return
      end
      reaper.MB(why or "Couldn't save the chain.", "ChannelView", 0)
    end
  end
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- the menu
-- ---------------------------------------------------------------------

function CN.open(track)
  st.req, st.track = true, track
end

local function items(ctx, node, pick)
  for _, d in ipairs(node.dirs) do
    if ImGui.BeginMenu(ctx, d.name) then
      items(ctx, d.node, pick)
      ImGui.EndMenu(ctx)
    end
  end
  for i, f in ipairs(node.files) do
    if ImGui.MenuItem(ctx, f.name .. "##cn" .. i) then pick(f) end
  end
end

-- The FXChains tree (CN.list) as menu items -- subfolders as submenus.
-- `pick(f)` is called for the one chosen. Draw inside an open menu.
function CN.items(ctx, tree, pick)
  if tree then items(ctx, tree, pick) end
end

function CN.has_chains(tree)
  return tree ~= nil and (#tree.files > 0 or #tree.dirs > 0)
end

-- Draws the menu when it's open. Call once per frame from the main
-- window, outside any child and outside the menu bar. Returns true on
-- the frame a chain was loaded.
function CN.draw(ctx)
  draw_save(ctx)
  if st.req then
    st.req = false
    st.tree = CN.list()                   -- once per opening, not per frame
    ImGui.OpenPopup(ctx, POPUP_ID)
  end
  if not ImGui.BeginPopup(ctx, POPUP_ID) then return false end

  local tr = st.track
  if not valid(tr) then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return false
  end

  ImGui.TextDisabled(ctx, "Load an FX chain onto " .. track_label(tr))
  local rep = CN.replace_on()
  local chg, v = ImGui.Checkbox(ctx, "Replace the existing FX", rep)
  if chg then set_replace(v) end
  ImGui.Separator(ctx)

  local loaded = false
  local tree = st.tree
  if not tree or (#tree.files == 0 and #tree.dirs == 0) then
    ImGui.TextDisabled(ctx, "No FX chains found in")
    ImGui.TextDisabled(ctx, (CN.dir()))
  else
    items(ctx, tree, function(f)
      if CN.load(tr, f, CN.replace_on()) then
        loaded = true
      else
        reaper.MB("Couldn't load the FX chain\n\n" .. f.path, "ChannelView", 0)
      end
    end)
  end

  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Save this track's chain as\u{2026}", nil, false,
                    reaper.TrackFX_GetCount(tr) > 0) then
    CN.open_save(tr, nil, nil)
  end
  if ImGui.BeginMenu(ctx, "Delete a chain", CN.has_chains(tree)) then
    items(ctx, tree, function(f)
      if reaper.MB("Delete the FX chain \"" .. f.name .. "\"?\n\n" .. f.path ..
                   "\n\nThis can't be undone.", "ChannelView", 4) == 6 then
        local ok, why = CN.delete(f)
        if ok then st.tree = CN.list()
        else reaper.MB("Couldn't delete it:\n" .. (why or ""), "ChannelView", 0) end
      end
    end)
    ImGui.EndMenu(ctx)
  end

  ImGui.EndPopup(ctx)
  return loaded
end

return CN
