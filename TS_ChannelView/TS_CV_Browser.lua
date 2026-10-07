-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Browser.lua -- the add-a-plugin picker.

  A search box rather than a menu tree. With a real collection, typing
  three letters beats walking a submenu of two hundred vendors, and it
  costs nothing to also match on the vendor, so "fab sat" finds
  FabFilter Saturn.

  Alongside it, a filter carrying the same three trees REAPER's own Add FX
  browser has -- your FX Folders, Categories, and Developers -- read from
  REAPER's metadata rather than guessed at (see TS_CV_FXIndex.lua for why
  that matters). Folders come first because they're the ones you curated.
  Filter and search compose: pick FabFilter, then type "pro" to narrow to
  their Pro- series.

  Two implementation details worth knowing:

    * Insert by `ident`, never by display name. EnumInstalledFX hands back
      a type-prefixed identifier precisely so it round-trips into
      TrackFX_AddByName unambiguously -- plain names collide across
      formats, and you end up inserting the VST2 when you picked the VST3.
    * TrackFX_AddByName's `instantiate` argument doubles as a position:
      -1000 - n inserts at top-level slot n, while -1 appends. That's why
      this never has to add-then-move.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local SR = require("TS_CV_Search")
local IX = require("TS_CV_FXIndex")
local T  = require("TS_CV_FXTree")

local B = {}
local ImGui

local TITLE       = "Add plugin"
local RECENT_KEY  = "recent_fx"
local RECENT_MAX  = 10
local ROW_H       = 18

-- One active filter at a time: kind is "", "folder", "cat" or "dev".
local NO_DEV = "\1none"         -- the bucket for plugins REAPER can't attribute

local st = {
  open      = false,
  request   = false,
  insert_at = nil,     -- top-level slot, or nil to append
  track     = nil,     -- the track to insert on, when not the caller's
  input     = false,   -- into the input (monitoring) FX chain instead
  query     = "",
  kind      = "",          -- "", "folder", "cat", "dev"
  val       = nil,         -- folder id, or category/developer name
  fkey      = "",          -- cached "kind\0val", to spot changes
  last_q    = nil,
  last_v    = nil,
  devfilt   = "",          -- search box inside the filter dropdown
  results   = {},
  sel       = 1,
  focus     = false,
}

local all_fx   = nil   -- lazily built; EnumInstalledFX is slow on a big rig
local devs, cats, folds = nil, nil, nil
local by_fold, by_cat, by_dev, by_letter = nil, nil, nil, nil

function B.attach(imgui) ImGui = imgui end
function B.is_open() return st.open end

-- ---------------------------------------------------------------------

local installed

-- Forget the collection, so the next look reads it (and your FX Folders)
-- afresh -- after a folder has been edited.
function B.forget()
  all_fx, devs, cats, folds = nil, nil, nil, nil
  by_fold, by_cat, by_dev, by_letter = nil, nil, nil, nil
end

installed = function()
  if all_fx then return all_fx end
  local list, i = {}, 0
  while true do
    local ok, name, ident = reaper.EnumInstalledFX(i)
    if not ok then break end
    if name and ident and name ~= "" then
      list[#list + 1] = {
        name   = name,
        ident  = ident,
        short  = U.clean_fx_name(name),
        vendor = U.fx_vendor(name) or "",
        fmt    = U.fx_format(name) or "",
        lower  = name:lower(),
      }
    end
    i = i + 1
    if i > 30000 then break end        -- sanity stop, never reached in practice
  end
  table.sort(list, function(a, b) return a.short:lower() < b.short:lower() end)
  all_fx = list

  -- Developers, categories and folders all come from REAPER's own
  -- metadata, with counts over what's actually installed.
  devs, cats, folds = IX.build(list)

  -- Reverse indexes, so the cascading menu can hand each submenu its own
  -- plugins without walking the whole collection per frame.
  by_fold, by_cat, by_dev, by_letter = {}, {}, {}, {}
  for _, e in ipairs(list) do
    for fid in pairs(e.folders or {}) do
      by_fold[fid] = by_fold[fid] or {}
      table.insert(by_fold[fid], e)
    end
    for _, c in ipairs(e.cats or {}) do
      by_cat[c] = by_cat[c] or {}
      table.insert(by_cat[c], e)
    end
    local d = e.dev or NO_DEV
    by_dev[d] = by_dev[d] or {}
    table.insert(by_dev[d], e)

    -- "All plugins" is fifteen hundred rows; split by initial so no one
    -- submenu is a scroll marathon.
    local ch = e.short:sub(1, 1):upper()
    if not ch:match("%a") then ch = "#" end
    by_letter[ch] = by_letter[ch] or {}
    table.insert(by_letter[ch], e)
  end
  return all_fx
end

local function filter_label()
  if st.kind == "" then return "All plugins" end
  if st.kind == "folder" then
    for _, f in ipairs(folds or {}) do
      if f.id == st.val then return "\u{1F5C0} " .. f.name end
    end
    return "Folder"
  end
  if st.kind == "cat" then return "\u{25E7} " .. tostring(st.val) end
  if st.val == NO_DEV then return "(no developer)" end
  return tostring(st.val)
end

local function in_filter(entry)
  if st.kind == "" then return true end
  if st.kind == "folder" then
    return entry.folders ~= nil and entry.folders[st.val] == true
  end
  if st.kind == "cat" then
    for _, c in ipairs(entry.cats or {}) do
      if c == st.val then return true end
    end
    return false
  end
  if st.val == NO_DEV then return entry.dev == nil end
  return entry.dev == st.val
end

local function set_filter(kind, val)
  st.kind, st.val = kind, val
  st.fkey = tostring(kind) .. "\0" .. tostring(val)
  st.sel = 1
end

local function recents()
  local out = {}
  local raw = reaper.GetExtState(C.EXT_SECT, RECENT_KEY)
  for id in raw:gmatch("[^\n]+") do out[#out + 1] = id end
  return out
end

local function remember(ident)
  local list, out = recents(), { ident }
  for _, id in ipairs(list) do
    if id ~= ident and #out < RECENT_MAX then out[#out + 1] = id end
  end
  reaper.SetExtState(C.EXT_SECT, RECENT_KEY, table.concat(out, "\n"), true)
end

-- Searching is TS_CV_Search's: every term has to find a home in the full
-- name (format, name and vendor), but forgivingly -- "proq", "pq4" and
-- "saturm" all work -- and the best fit comes first. A recently used
-- plugin gets a nudge up the list.
local RECENT_BONUS = 15
local function recent_bonus()
  local set = {}
  for _, id in ipairs(recents()) do set[id] = true end
  return function(e) return set[e.ident] and RECENT_BONUS or 0 end
end

local function rebuild()
  local list = installed()
  local q = U.trim(st.query):lower()

  -- Recents only lead when nothing is being narrowed. Once you've picked a
  -- developer you're browsing THEM, and a recents block from elsewhere on
  -- top of that list is just noise.
  if q == "" and st.kind == "" then
    local by_ident = {}
    for _, e in ipairs(list) do by_ident[e.ident] = e end
    local out = {}
    for _, id in ipairs(recents()) do
      if by_ident[id] then out[#out + 1] = by_ident[id] end
    end
    local n_recent = #out
    for _, e in ipairs(list) do out[#out + 1] = e end
    st.results, st.n_recent = out, n_recent
  else
    local out
    if q == "" then
      out = {}
      for _, e in ipairs(list) do
        if in_filter(e) then out[#out + 1] = e end
      end
    else
      out = SR.search(list, q, in_filter, recent_bonus())
    end
    st.results, st.n_recent = out, 0
  end

  st.last_q, st.last_v = st.query, st.fkey
  st.sel = math.min(math.max(1, st.sel), math.max(1, #st.results))
end

-- ---------------------------------------------------------------------

-- insert_at: top-level chain slot to insert before, or nil to append --
-- or { parent = a container's path, gap = the slot in it } to add into a
-- container (see TS_CV_FXTree.add_into).
-- `opts`, optional: { track = the track to add to (when it isn't the one
-- the dialog is drawn for), input = true for the input FX chain }.
function B.open(insert_at, opts)
  st.open      = true
  st.request   = true
  st.insert_at = insert_at
  st.track     = opts and opts.track or nil
  st.input     = (opts and opts.input) and true or false
  st.query     = ""
  st.kind, st.val, st.fkey = "", nil, ""
  st.devfilt   = ""
  st.last_q    = nil
  st.last_v    = nil
  st.sel       = 1
  st.focus     = true
end

-- `input` puts it at the end of the input FX chain instead -- the
-- monitoring FX chain on the master, which is where REAPER keeps those.
local function insert(track, entry, at, input)
  if not track or not entry then return false end
  if type(at) == "table" and not input then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    local ok = T.add_into(track, entry.ident, at.parent or {}, at.gap or 0)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: add " .. entry.short, -1)
    if ok then remember(entry.ident) end
    return ok
  end
  -- instantiate doubles as a position: -1000 - n inserts at slot n.
  local instantiate = (at and not input) and (-1000 - at) or -1
  reaper.Undo_BeginBlock()
  local idx = reaper.TrackFX_AddByName(track, entry.ident, input and true or false, instantiate)
  reaper.Undo_EndBlock("ChannelView: add " .. entry.short, -1)
  if idx and idx >= 0 then
    remember(entry.ident)
    return true
  end
  return false
end

-- ---------------------------------------------------------------------
-- cascading menu
-- ---------------------------------------------------------------------
-- The default way in. Browsing a collection by folder or developer is a
-- pointing exercise, and a menu does that with no dialog to open, aim at
-- and dismiss. Typing is still faster when you know the name, so the menu
-- opens the search dialog from its first item.

local MENU_ID = "addfxmenu"
local menu = { request = false, insert_at = nil, query = "", focus = false }

-- Where the menu's items insert: set by B.draw_menu for the chain, or by
-- B.menu_items when the same list is shown somewhere else (the input FX
-- button's menu).
local cur = { insert_at = nil, track = nil, input = false }

function B.open_menu(insert_at)
  menu.request   = true
  menu.insert_at = insert_at
end

local inserted_now = false

-- A format badge drawn over the leading space of a menu label.
--
-- The format is what tells apart the two entries a plugin installed in
-- more than one format produces -- otherwise identical names, and picking
-- the wrong one is how you end up with the VST2. A padded label reserves
-- the room; the swatch is then painted into it from the item's own
-- rectangle, so it lines up whatever the font.
local BADGE_W    = 36    -- the swatch itself
local BADGE_LEFT = 4     -- margin from the item's left edge
local BADGE_GAP  = 7     -- clear air before the plugin name

-- How many spaces reserve the badge's room. Measured rather than
-- hardcoded: the label font is proportional and the space width moves
-- with the UI scale, and a count that is right on one machine overlaps
-- the name on another.
local function badge_pad(ctx)
  local sw = ImGui.CalcTextSize(ctx, " ")
  if not sw or sw <= 0 then return "          " end
  return (" "):rep(math.ceil((BADGE_LEFT + BADGE_W + BADGE_GAP) / sw))
end

local function badge(ctx, dl, fmt)
  local x, y  = ImGui.GetItemRectMin(ctx)
  local _, y2 = ImGui.GetItemRectMax(ctx)
  local col   = C.format_col(fmt)
  local txt   = (fmt ~= "" and fmt) or "?"
  local tw, th = ImGui.CalcTextSize(ctx, txt)
  -- Inset top and bottom as well: a swatch that runs the full row height
  -- reads as a selection highlight rather than as a label on the row.
  local cy = (y + y2) * 0.5
  local bh = math.min(y2 - y - 4, th + 4)
  ImGui.DrawList_AddRectFilled(dl, x + BADGE_LEFT, cy - bh * 0.5,
    x + BADGE_LEFT + BADGE_W, cy + bh * 0.5, col.bg, 3.0)
  ImGui.DrawList_AddText(dl, x + BADGE_LEFT + (BADGE_W - tw) * 0.5,
    cy - th * 0.5, col.fg, txt)
end

-- ---------------------------------------------------------------------
-- your FX Folders, edited from the picker
-- ---------------------------------------------------------------------
-- REAPER's own (reaper-fxfolders.ini, TS_CV_FXIndex): right-click a
-- plugin to add it to a folder or take it out of one; in the Folders
-- menu, right-click a folder to remove it, and the [+] row at the foot
-- makes a new one. Every write keeps the file as it was beside it (.bak).
-- REAPER's own Add FX browser keeps its copy in memory, so it may only
-- show a change after a restart.

local fold_m, fold_at = nil, -1
local function folder_model()
  local now = reaper.time_precise()
  if not fold_m or now - fold_at > 1 then fold_m, fold_at = IX.read_folders(), now end
  return fold_m
end

local function edit_folders(fn)
  local m, before = IX.read_folders()
  if not fn(m) then return end
  if IX.save_folders(m, before) then
    fold_m = nil
    B.forget()
    installed()            -- rebuilt now: the menus being drawn read it
  else
    reaper.MB("Couldn't write reaper-fxfolders.ini.", "ChannelView", 0)
  end
end

-- A name box and [+]: `make(name)` is called with what was typed.
local newfold = { buf = "" }
local function new_folder_row(ctx, id, make)
  ImGui.SetNextItemWidth(ctx, 160)
  local _, v = ImGui.InputTextWithHint(ctx, "##nf" .. id, "new folder\u{2026}", newfold.buf)
  local enter = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
  newfold.buf = v
  ImGui.SameLine(ctx)
  if (ImGui.SmallButton(ctx, "+##nfb" .. id) or enter) and U.trim(newfold.buf) ~= "" then
    make(U.trim(newfold.buf))
    newfold.buf = ""
  end
end

-- Removing a folder, after asking. The plugins in it stay installed.
local function remove_folder(f)
  if reaper.MB(("Remove the folder \"%s\"?\n\nThe plugins in it stay installed; " ..
      "only the folder goes."):format(f.name), "ChannelView", 4) == 6 then
    edit_folders(function(mm) return IX.folder_delete(mm, f.id) end)
  end
end

-- A plugin's right-click menu: add it to a folder, take it out of one.
local function folder_actions(ctx, e)
  local kind = IX.kind_of(e.name)
  if not kind then
    ImGui.TextDisabled(ctx, "Folders can't hold this kind of plugin")
    return
  end
  local m = folder_model()
  local ins, outs = {}, {}
  for _, f in ipairs(IX.folder_list(m)) do
    if IX.folder_has(m, f.id, e.ident) then ins[#ins + 1] = f else outs[#outs + 1] = f end
  end
  if ImGui.BeginMenu(ctx, "Add to folder") then
    for _, f in ipairs(outs) do
      if ImGui.MenuItem(ctx, f.name .. "##af" .. f.id) then
        edit_folders(function(mm) return IX.folder_add(mm, f.id, e.ident, kind) end)
      end
    end
    if #outs > 0 then ImGui.Separator(ctx) end
    new_folder_row(ctx, "p", function(name)
      edit_folders(function(mm)
        IX.folder_add(mm, IX.folder_new(mm, name), e.ident, kind)
        return true
      end)
      ImGui.CloseCurrentPopup(ctx)
    end)
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Remove from folder", #ins > 0) then
    for _, f in ipairs(ins) do
      if ImGui.MenuItem(ctx, f.name .. "##rf" .. f.id) then
        edit_folders(function(mm) return IX.folder_remove(mm, f.id, e.ident) end)
      end
    end
    ImGui.EndMenu(ctx)
  end
end

local function plugin_items(ctx, track, list)
  local dl  = ImGui.GetWindowDrawList(ctx)
  local pad = badge_pad(ctx)
  for i, e in ipairs(list or {}) do
    if ImGui.MenuItem(ctx, ("%s%s##m%d"):format(pad, e.short, i)) then
      if insert(cur.track or track, e, cur.insert_at, cur.input) then inserted_now = true end
    end
    badge(ctx, dl, e.fmt)
    if ImGui.BeginPopupContextItem(ctx, "##fxctx" .. i) then
      ImGui.TextDisabled(ctx, e.short)
      ImGui.Separator(ctx)
      folder_actions(ctx, e)
      ImGui.EndPopup(ctx)
    end
  end
end

-- A submenu whose body is only built when it opens, which is what keeps a
-- menu over a large collection cheap.
local function group_menu(ctx, track, label, list)
  if not list or #list == 0 then return end
  if ImGui.BeginMenu(ctx, ("%s  (%d)"):format(label, #list)) then
    plugin_items(ctx, track, list)
    ImGui.EndMenu(ctx)
  end
end

-- The menu's body: Search, Recent, and the plugin trees. Shared by the
-- chain's own add menu and anything else that adds plugins.
local function items(ctx, track)
  installed()
  if ImGui.MenuItem(ctx, "Search\u{2026}") then
    B.open(cur.insert_at, { track = cur.track, input = cur.input })
  end

  local rec = {}
  do
    local by_ident = {}
    for _, e in ipairs(installed()) do by_ident[e.ident] = e end
    for _, id in ipairs(recents()) do
      if by_ident[id] then rec[#rec + 1] = by_ident[id] end
    end
  end
  if #rec > 0 and ImGui.BeginMenu(ctx, "Recent") then
    plugin_items(ctx, track, rec)
    ImGui.EndMenu(ctx)
  end

  ImGui.Separator(ctx)

  if ImGui.BeginMenu(ctx, "All plugins") then
    local letters = {}
    for ch in pairs(by_letter or {}) do letters[#letters + 1] = ch end
    table.sort(letters)
    for _, ch in ipairs(letters) do
      group_menu(ctx, track, ch, by_letter[ch])
    end
    ImGui.EndMenu(ctx)
  end

  -- every folder, empty ones too, in REAPER's order with its separators;
  -- right-click one to remove it, [+] at the foot for a new one
  if ImGui.BeginMenu(ctx, "Folders") then
    local fm = folder_model()
    local row_h = ImGui.GetTextLineHeightWithSpacing(ctx)
    for _, f in ipairs(fm.order) do
      if IX.is_separator(f) then
        ImGui.Separator(ctx)
      else
        local members = (by_fold or {})[f.id] or {}
        -- the row's own rectangle, read before the submenu can open over it
        -- (across the whole menu window, not just the text)
        local _, y = ImGui.GetCursorScreenPos(ctx)
        local x = ImGui.GetWindowPos(ctx)
        local w = ImGui.GetWindowSize(ctx)
        -- (a folder's submenu opens as soon as its row is hovered, and an
        -- open submenu counts as a popup over this one: without the flag
        -- the window never reads as hovered while you're pointing at a row)
        if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right)
           and ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_AllowWhenBlockedByPopup) then
          local mx, my = ImGui.GetMousePos(ctx)
          if mx >= x and mx <= x + w and my >= y and my < y + row_h then
            newfold.ctx = f
            ImGui.OpenPopup(ctx, "##foldctx")
          end
        end
        if ImGui.BeginMenu(ctx, ("%s  (%d)##fold%d"):format(f.name, #members, f.id)) then
          if #members == 0 then ImGui.TextDisabled(ctx, "Empty") end
          plugin_items(ctx, track, members)
          ImGui.Separator(ctx)
          if ImGui.MenuItem(ctx, "Remove this folder\u{2026}##rmf" .. f.id) then remove_folder(f) end
          ImGui.EndMenu(ctx)
        end
        -- and the row itself, which ImGui hands back as the last item
        -- once its submenu is done
        if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right)
           and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenBlockedByPopup) then
          newfold.ctx = f
          ImGui.OpenPopup(ctx, "##foldctx")
        end
      end
    end
    if #fm.order > 0 then ImGui.Separator(ctx) end
    new_folder_row(ctx, "f", function(name)
      edit_folders(function(mm) IX.folder_new(mm, name) return true end)
    end)
    if ImGui.BeginPopup(ctx, "##foldctx") then
      local f = newfold.ctx
      if f then
        ImGui.TextDisabled(ctx, f.name)
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, "Remove folder") then remove_folder(f) end
      end
      ImGui.EndPopup(ctx)
    end
    ImGui.EndMenu(ctx)
  end

  if #(cats or {}) > 0 and ImGui.BeginMenu(ctx, "Categories") then
    for _, c in ipairs(cats) do
      group_menu(ctx, track, c.name, by_cat[c.name])
    end
    ImGui.EndMenu(ctx)
  end

  if #(devs or {}) > 0 and ImGui.BeginMenu(ctx, "Developers") then
    for _, d in ipairs(devs) do
      group_menu(ctx, track, d.name, by_dev[d.name])
    end
    ImGui.EndMenu(ctx)
  end

end

-- The same list, drawn inside a menu that's already open -- a submenu of
-- the input FX button, say. `opts` as for B.open. Returns true on the
-- frame a plugin was inserted.
function B.menu_items(ctx, track, opts)
  inserted_now = false
  cur.insert_at = opts and opts.insert_at or nil
  cur.track     = opts and opts.track or nil
  cur.input     = (opts and opts.input) and true or false
  items(ctx, track)
  return inserted_now
end

-- TYPE TO SEARCH. The menu opens with a search box at the top that already
-- has the keyboard, so typing searches straight away -- no "Search..." to
-- click first. Once there is something in it the trees give way to a flat
-- list of matches, best first (TS_CV_Search, as in the dialog); Enter takes
-- the first. With the box empty the menu is the menu it always was. The box
-- lives in the menu rather than handing over to the search dialog because
-- a text box that takes focus with text already in it selects that text,
-- and the next key typed would replace the first.
local MENU_MAX = 40
local MENU_ROWS = 14     -- matches shown before the list scrolls

-- Where the menu opens, and which way it grows. ImGui places a popup once,
-- when it opens, sized for what it held then, and leaves it there however
-- tall it gets after -- so a menu opened low on the screen (ChannelView
-- docked at the bottom, say) had its matches pushed off the bottom as you
-- typed. Opened in the lower half of the monitor, it's anchored by its
-- bottom edge at the mouse and grows upward instead; and the matches scroll
-- past MENU_ROWS rather than growing without end.
local function menu_anchor(ctx)
  local mx, my = ImGui.GetMousePos(ctx)
  local ok, top, bot = pcall(function()
    local conv = ImGui.PointConvertNative
    local nx, ny = mx, my
    if conv then nx, ny = conv(ctx, mx, my, true) end
    local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, nx, ny, nx + 1, ny + 1, true)
    local y0, y1 = t, b
    if conv then
      local _
      _, y0 = conv(ctx, l, t, false)
      _, y1 = conv(ctx, r, b, false)
    end
    return math.min(y0, y1), math.max(y0, y1)
  end)
  local up = ok and top and bot and bot > top and (my - top) > (bot - my) or false
  return mx, my, up
end

-- The matches in a list of their own that scrolls, as wide as the longest.
local function results_list(ctx, track, found)
  local row_h = ImGui.GetTextLineHeightWithSpacing(ctx)
  local pad = badge_pad(ctx)
  local w = 240
  for _, e in ipairs(found) do
    local tw = ImGui.CalcTextSize(ctx, pad .. e.short) + 28
    if tw > w then w = tw end
  end
  w = math.min(w, 520)
  local h = math.min(#found, MENU_ROWS) * row_h + 4
  if ImGui.BeginChild(ctx, "##addfxres", w, h, 0) then
    plugin_items(ctx, track, found)
    ImGui.EndChild(ctx)
  end
end

local function quick_search(q)
  if #SR.terms(q) == 0 then return {} end
  return SR.search(installed(), q, nil, recent_bonus(), MENU_MAX)
end

-- Returns true on the frame a plugin was inserted from the menu.
function B.draw_menu(ctx, track)
  if menu.request then
    ImGui.OpenPopup(ctx, MENU_ID)
    menu.request = false
    menu.query, menu.focus = "", true
    menu.ax, menu.ay, menu.up = menu_anchor(ctx)
    installed()                       -- index now, not mid-hover
  end
  inserted_now = false
  -- Only while it's open: a position set for a popup that then doesn't
  -- begin would land on whatever window begins next.
  if menu.ax and ImGui.IsPopupOpen(ctx, MENU_ID) then
    ImGui.SetNextWindowPos(ctx, menu.ax, menu.ay, ImGui.Cond_Always, 0, menu.up and 1 or 0)
  end
  if not ImGui.BeginPopup(ctx, MENU_ID) then return false end

  local where = type(menu.insert_at) == "table" and "Add into the container"
    or menu.insert_at and ("Insert at position " .. (menu.insert_at + 1))
    or "Add to the end of the chain"
  ImGui.TextDisabled(ctx, where)

  if menu.focus then
    ImGui.SetKeyboardFocusHere(ctx)
    menu.focus = false
  end
  ImGui.SetNextItemWidth(ctx, 240)
  local ch, q = ImGui.InputTextWithHint(ctx, "##addfxq", "type to search\u{2026}", menu.query)
  if ch then menu.query = q end
  ImGui.Separator(ctx)

  cur.insert_at, cur.track, cur.input = menu.insert_at, nil, false
  if U.trim(menu.query) ~= "" then
    local found = quick_search(U.trim(menu.query))
    if #found == 0 then
      ImGui.TextDisabled(ctx, "No matches")
    else
      results_list(ctx, track, found)
      -- a click inside the list's own window doesn't close the menu by
      -- itself, as it would a row of the menu proper
      if inserted_now then ImGui.CloseCurrentPopup(ctx) end
      if #found >= MENU_MAX then ImGui.TextDisabled(ctx, "\u{2026}keep typing to narrow it") end
      if not inserted_now and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                               or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)) then
        if insert(track, found[1], cur.insert_at, false) then inserted_now = true end
        ImGui.CloseCurrentPopup(ctx)
      end
    end
  else
    items(ctx, track)
  end
  ImGui.EndPopup(ctx)
  return inserted_now
end

-- Returns true on the frame a plugin was inserted.
function B.draw(ctx, track)
  if not st.open then return false end

  if st.request then
    ImGui.OpenPopup(ctx, TITLE)
    st.request = false
  end

  ImGui.SetNextWindowSize(ctx, 460, 420, ImGui.Cond_Appearing)
  local visible, open = ImGui.BeginPopupModal(ctx, TITLE, true,
    ImGui.WindowFlags_NoCollapse)
  local inserted = false

  if visible then
    if st.last_q ~= st.query or st.last_v ~= st.fkey then rebuild() end

    local where = st.input and "add to the input FX chain"
      or (type(st.insert_at) == "table" and "add into the container")
      or (st.insert_at and ("insert at position " .. (st.insert_at + 1)))
      or "add to the end of the chain"
    ImGui.TextDisabled(ctx, where)

    if st.focus then
      ImGui.SetKeyboardFocusHere(ctx)
      st.focus = false
    end
    ImGui.SetNextItemWidth(ctx, -186)
    local ch, q = ImGui.InputTextWithHint(ctx, "##q",
      "search name or vendor\u{2026}", st.query)
    if ch then st.query = q; st.sel = 1 end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, filter_label() .. "  \u{25BE}###filter", -1) then
      ImGui.OpenPopup(ctx, "filterpop")
      st.devfilt = ""
    end

    -- Kind first, values in a submenu -- the same shape REAPER's own Add
    -- FX browser uses. A flat list of every folder, category and developer
    -- is a hundred-odd rows to scroll past before reaching anything, which
    -- is a poor trade for saving one click.
    --
    -- Typing in the box at the top flattens it back out, matching across
    -- all three kinds at once, so browsing and searching each stay fast.
    if ImGui.BeginPopup(ctx, "filterpop") then
      ImGui.SetNextItemWidth(ctx, 220)
      -- Enter takes the first match
      local _, fv = ImGui.InputTextWithHint(ctx, "##ffilt",
        "filter folders, categories, developers\u{2026}", st.devfilt)
      local f_enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
      st.devfilt = fv
      local needle = U.trim(st.devfilt):lower()
      local function keep(name)
        return needle == "" or name:lower():find(needle, 1, true) ~= nil
      end

      ImGui.Separator(ctx)
      if ImGui.Selectable(ctx, "All plugins", st.kind == "") then
        set_filter("", nil)
        ImGui.CloseCurrentPopup(ctx)
      end

      local function folder_item(f)
        local lbl = ("%s  (%d)##fo%d"):format(f.name, f.count, f.id)
        if ImGui.Selectable(ctx, lbl, st.kind == "folder" and st.val == f.id) then
          set_filter("folder", f.id)
          ImGui.CloseCurrentPopup(ctx)
        end
        if ImGui.BeginPopupContextItem(ctx, "##fodctx" .. f.id) then
          ImGui.TextDisabled(ctx, f.name)
          ImGui.Separator(ctx)
          if ImGui.MenuItem(ctx, "Remove folder") then
            remove_folder(f)
            if st.kind == "folder" and st.val == f.id then st.kind, st.val, st.fkey = "", nil, "" end
          end
          ImGui.EndPopup(ctx)
        end
      end
      local function cat_item(c)
        local lbl = ("%s  (%d)##ca%s"):format(c.name, c.count, c.name)
        if ImGui.Selectable(ctx, lbl, st.kind == "cat" and st.val == c.name) then
          set_filter("cat", c.name)
          ImGui.CloseCurrentPopup(ctx)
        end
      end
      local function dev_item(d)
        local lbl = ("%s  (%d)##de%s"):format(d.name, d.count, d.name)
        if ImGui.Selectable(ctx, lbl, st.kind == "dev" and st.val == d.name) then
          set_filter("dev", d.name)
          ImGui.CloseCurrentPopup(ctx)
        end
      end

      if needle == "" then
        -- browse: three submenus, folders first since you curated those
        if ImGui.BeginMenu(ctx, ("Folders  (%d)"):format(#(folds or {})),
                           #(folds or {}) > 0) then
          for _, f in ipairs(folds or {}) do folder_item(f) end
          ImGui.EndMenu(ctx)
        end
        if ImGui.BeginMenu(ctx, ("Categories  (%d)"):format(#(cats or {})),
                           #(cats or {}) > 0) then
          for _, c in ipairs(cats or {}) do cat_item(c) end
          ImGui.EndMenu(ctx)
        end
        if ImGui.BeginMenu(ctx, ("Developers  (%d)"):format(#(devs or {})),
                           #(devs or {}) > 0) then
          for _, d in ipairs(devs or {}) do dev_item(d) end
          ImGui.EndMenu(ctx)
        end
      else
        -- search: flat matches, labelled by which kind they came from, in
        -- a list that scrolls rather than running off the screen
        local rows = 0
        for _, f in ipairs(folds or {}) do if keep(f.name) then rows = rows + 1 end end
        for _, c in ipairs(cats or {}) do if keep(c.name) then rows = rows + 1 end end
        for _, d in ipairs(devs or {}) do if keep(d.name) then rows = rows + 1 end end
        local lh = ImGui.GetTextLineHeightWithSpacing(ctx)
        local open_list = ImGui.BeginChild(ctx, "##filtres", 260, math.min(rows + 3, 18) * lh + 4, 0)
        local shown = false
        for _, f in ipairs(folds or {}) do
          if keep(f.name) then
            if not shown then ImGui.SeparatorText(ctx, "Folders"); shown = true end
            folder_item(f)
          end
        end
        shown = false
        for _, c in ipairs(cats or {}) do
          if keep(c.name) then
            if not shown then ImGui.SeparatorText(ctx, "Categories"); shown = true end
            cat_item(c)
          end
        end
        shown = false
        for _, d in ipairs(devs or {}) do
          if keep(d.name) then
            if not shown then ImGui.SeparatorText(ctx, "Developers"); shown = true end
            dev_item(d)
          end
        end
        if open_list then ImGui.EndChild(ctx) end
        if f_enter then
          local hit
          for _, f in ipairs(folds or {}) do if not hit and keep(f.name) then hit = { "folder", f.id } end end
          for _, c in ipairs(cats or {}) do if not hit and keep(c.name) then hit = { "cat", c.name } end end
          for _, d in ipairs(devs or {}) do if not hit and keep(d.name) then hit = { "dev", d.name } end end
          if hit then set_filter(hit[1], hit[2]); ImGui.CloseCurrentPopup(ctx) end
        end
      end

      ImGui.EndPopup(ctx)
    end

    -- Arrows move the selection while the search box keeps focus, so you
    -- never have to leave the keyboard to pick something.
    local n = #st.results
    if n > 0 then
      if ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow) then
        st.sel = math.min(n, st.sel + 1); st.scroll = true
      elseif ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow) then
        st.sel = math.max(1, st.sel - 1); st.scroll = true
      end
      if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
         or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter) then
        inserted = insert(st.track or track, st.results[st.sel], st.insert_at, st.input)
        if inserted then ImGui.CloseCurrentPopup(ctx); st.open = false end
      end
    end

    if ImGui.BeginChild(ctx, "list", 0, -30, 0) then
      for i, e in ipairs(st.results) do
        if st.n_recent and st.n_recent > 0 then
          if i == 1 then ImGui.TextDisabled(ctx, "Recent") end
          if i == st.n_recent + 1 then
            ImGui.Spacing(ctx)
            ImGui.TextDisabled(ctx, "All plugins")
          end
        end
        -- Same badge as the cascading menu, for the same reason.
        local label = badge_pad(ctx) .. e.short
        if e.dev then label = label .. "   \u{00B7} " .. e.dev end
        if ImGui.Selectable(ctx, label .. "##fx" .. i, st.sel == i) then
          st.sel = i
        end
        badge(ctx, ImGui.GetWindowDrawList(ctx), e.fmt)
        -- right-click a result: the rest of that developer, or its folders
        if ImGui.BeginPopupContextItem(ctx, "##fxdctx" .. i) then
          ImGui.TextDisabled(ctx, e.short)
          ImGui.Separator(ctx)
          if ImGui.MenuItem(ctx, "More by " .. (e.dev or "the same developer")) then
            set_filter("dev", e.dev or NO_DEV)
            st.query = ""
          end
          folder_actions(ctx, e)
          ImGui.EndPopup(ctx)
        end
        if ImGui.IsItemHovered(ctx)
           and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
          inserted = insert(st.track or track, e, st.insert_at, st.input)
          if inserted then ImGui.CloseCurrentPopup(ctx); st.open = false end
        end
        if st.sel == i and st.scroll then
          ImGui.SetScrollHereY(ctx, 0.5)
          st.scroll = false
        end
      end
      ImGui.EndChild(ctx)
    end

    if ImGui.Button(ctx, "Add", 90) then
      inserted = insert(st.track or track, st.results[st.sel], st.insert_at, st.input)
      if inserted then ImGui.CloseCurrentPopup(ctx); st.open = false end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 90) then
      ImGui.CloseCurrentPopup(ctx)
      st.open = false
    end
    ImGui.SameLine(ctx, 0, 16)
    if st.kind ~= "" then
      ImGui.TextDisabled(ctx, ("%d of %d  \u{00B7}  %s")
        :format(n, #installed(), filter_label()))
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "clear filter") then set_filter("", nil) end
    else
      ImGui.TextDisabled(ctx, ("%d of %d"):format(n, #installed()))
    end

    ImGui.EndPopup(ctx)
  end

  if not open then st.open = false end
  return inserted
end

return B
