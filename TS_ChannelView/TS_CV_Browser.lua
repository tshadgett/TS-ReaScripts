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

  Two details carried over from Plugin Rack.lua -- my own earlier,
  unreleased script -- both learned the hard way there:

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
local IX = require("TS_CV_FXIndex")

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

local function installed()
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

-- Every whitespace-separated term must appear somewhere in the full name
-- (which carries the format prefix and the vendor tag), so "fab sat" and
-- "sat fab" both land on FabFilter Saturn.
local function matches(entry, terms)
  for _, t in ipairs(terms) do
    if not entry.lower:find(t, 1, true) then return false end
  end
  return true
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
    local terms = {}
    for t in q:gmatch("%S+") do terms[#terms + 1] = t end
    local out = {}
    for _, e in ipairs(list) do
      if in_filter(e) and matches(e, terms) then out[#out + 1] = e end
    end
    st.results, st.n_recent = out, 0
  end

  st.last_q, st.last_v = st.query, st.fkey
  st.sel = math.min(math.max(1, st.sel), math.max(1, #st.results))
end

-- ---------------------------------------------------------------------

-- insert_at: top-level chain slot to insert before, or nil to append.
function B.open(insert_at)
  st.open      = true
  st.request   = true
  st.insert_at = insert_at
  st.query     = ""
  st.kind, st.val, st.fkey = "", nil, ""
  st.devfilt   = ""
  st.last_q    = nil
  st.last_v    = nil
  st.sel       = 1
  st.focus     = true
end

local function insert(track, entry, at)
  if not track or not entry then return false end
  -- instantiate doubles as a position: -1000 - n inserts at slot n.
  local instantiate = at and (-1000 - at) or -1
  reaper.Undo_BeginBlock()
  local idx = reaper.TrackFX_AddByName(track, entry.ident, false, instantiate)
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
local menu = { request = false, insert_at = nil }

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

local function plugin_items(ctx, track, list)
  local dl  = ImGui.GetWindowDrawList(ctx)
  local pad = badge_pad(ctx)
  for i, e in ipairs(list or {}) do
    if ImGui.MenuItem(ctx, ("%s%s##m%d"):format(pad, e.short, i)) then
      if insert(track, e, menu.insert_at) then inserted_now = true end
    end
    badge(ctx, dl, e.fmt)
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

-- Returns true on the frame a plugin was inserted from the menu.
function B.draw_menu(ctx, track)
  if menu.request then
    ImGui.OpenPopup(ctx, MENU_ID)
    menu.request = false
    installed()                       -- index now, not mid-hover
  end
  inserted_now = false
  if not ImGui.BeginPopup(ctx, MENU_ID) then return false end

  local where = menu.insert_at
    and ("Insert at position " .. (menu.insert_at + 1))
    or "Add to the end of the chain"
  ImGui.TextDisabled(ctx, where)
  ImGui.Separator(ctx)

  if ImGui.MenuItem(ctx, "Search\u{2026}") then
    B.open(menu.insert_at)
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

  if #(folds or {}) > 0 and ImGui.BeginMenu(ctx, "Folders") then
    for _, f in ipairs(folds) do
      group_menu(ctx, track, f.name, by_fold[f.id])
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

    local where = st.insert_at
      and ("insert at position " .. (st.insert_at + 1))
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
      local fch, fv = ImGui.InputTextWithHint(ctx, "##ffilt",
        "filter folders, categories, developers\u{2026}", st.devfilt)
      if fch then st.devfilt = fv end
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
        -- search: flat matches, labelled by which kind they came from
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
        inserted = insert(track, st.results[st.sel], st.insert_at)
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
        -- right-click a result to browse the rest of that developer
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
          set_filter("dev", e.dev or NO_DEV)
          st.query = ""
        end
        if ImGui.IsItemHovered(ctx)
           and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
          inserted = insert(track, e, st.insert_at)
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
      inserted = insert(track, st.results[st.sel], st.insert_at)
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
