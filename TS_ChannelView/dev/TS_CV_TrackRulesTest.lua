-- @noindex  (a development tool, not a package: never installed)
-- Track rules (TS_CV_TrackRules): the pure parts, and adding from a
-- template / FX returns against a pretend REAPER.
--   lua TS_CV_TrackRulesTest.lua        (from this folder)
local HERE = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "./"
package.path = HERE .. "../?.lua;" .. package.path

local fails, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got == want then print("ok   " .. name)
  else fails = fails + 1; print(("FAIL %s\n     got  %s\n     want %s"):format(name, tostring(got), tostring(want))) end
end

-- ---------------------------------------------------------------- the pretend REAPER
local P = { tracks = {}, ext = {}, templates = {}, master = { master = true } }
local function T(name, d, extra)
  local t = { name = name, depth = d or 0, col = 0, sel = false, arm = 0, spacer = 0, sends = {}, recv = 0, ext = {}, fx = 0 }
  for k, v in pairs(extra or {}) do t[k] = v end
  t.guid = "{" .. name .. tostring(t):sub(-6) .. "}"
  return t
end
local function idx(tr) for i, t in ipairs(P.tracks) do if t == tr then return i end end end
local function parent(tr)
  local i = idx(tr)
  local lv = {}
  local run = 0
  for k, t in ipairs(P.tracks) do lv[k] = run; run = run + t.depth end
  for k = i - 1, 1, -1 do
    if lv[k] < lv[i] and P.tracks[k].depth > 0 then return P.tracks[k] end
  end
  return nil
end
reaper = {
  CountTracks = function() return #P.tracks end,
  GetTrack = function(_, i) return P.tracks[i + 1] end,
  GetMasterTrack = function() return P.master end,
  GetMediaTrackInfo_Value = function(tr, k)
    if k == "I_FOLDERDEPTH" then return tr.depth
    elseif k == "IP_TRACKNUMBER" then return idx(tr)
    elseif k == "I_CUSTOMCOLOR" then return tr.col
    elseif k == "I_SPACER" then return tr.spacer
    elseif k == "I_RECARM" then return tr.arm
    elseif k == "I_FOLDERCOMPACT" then return 0 end
    return 0
  end,
  SetMediaTrackInfo_Value = function(tr, k, v)
    if k == "I_FOLDERDEPTH" then tr.depth = v
    elseif k == "I_CUSTOMCOLOR" then tr.col = v
    elseif k == "I_SPACER" then tr.spacer = v
    elseif k == "I_RECARM" then tr.arm = v end
  end,
  GetSetMediaTrackInfo_String = function(tr, k, v, set)
    if k == "P_NAME" then if set then tr.name = v end return true, tr.name end
    if set then tr.ext[k] = v end
    return true, tr.ext[k] or ""
  end,
  GetTrackGUID = function(tr) return tr.guid end,
  GetParentTrack = parent,
  GetTrackNumSends = function(tr, cat) if cat == -1 then return tr.recv end return #tr.sends end,
  ValidatePtr2 = function(_, tr) return idx(tr) ~= nil end,
  ValidatePtr = function(tr) return idx(tr) ~= nil end,
  ColorToNative = function(r, g, b) return r | (g << 8) | (b << 16) end,
  ColorFromNative = function(c) return c & 0xff, (c >> 8) & 0xff, (c >> 16) & 0xff end,
  SetOnlyTrackSelected = function(tr) for _, t in ipairs(P.tracks) do t.sel = (t == tr) end end,
  SetTrackSelected = function(tr, on) tr.sel = on end,
  CountSelectedTracks = function() local n = 0 for _, t in ipairs(P.tracks) do if t.sel then n = n + 1 end end return n end,
  GetSelectedTrack = function(_, i)
    local n = -1
    for _, t in ipairs(P.tracks) do if t.sel then n = n + 1; if n == i then return t end end end
  end,
  ReorderSelectedTracks = function(before, _)
    local target = P.tracks[before + 1]
    local moving, rest = {}, {}
    for _, t in ipairs(P.tracks) do if t.sel then moving[#moving + 1] = t else rest[#rest + 1] = t end end
    local at = #rest + 1
    if target and not target.sel then for i, t in ipairs(rest) do if t == target then at = i end end end
    for k, t in ipairs(moving) do table.insert(rest, at + k - 1, t) end
    P.tracks = rest
    return true
  end,
  Main_OnCommand = function(id) if id == 40297 then for _, t in ipairs(P.tracks) do t.sel = false end end end,
  Main_openProject = function(path)
    for _, spec in ipairs(P.templates[path]) do
      P.tracks[#P.tracks + 1] = T(spec[1], spec[2], { col = spec[3] or 0 })
    end
  end,
  InsertTrackAtIndex = function(i) table.insert(P.tracks, i + 1, T("", 0)) end,
  CreateTrackSend = function(src, dst) src.sends[#src.sends + 1] = dst; dst.recv = dst.recv + 1; return #src.sends - 1 end,
  TrackFX_AddByName = function(tr) tr.fx = tr.fx + 1; return tr.fx - 1 end,
  TrackFX_GetCount = function(tr) return tr.fx end,
  GetExtState = function(s, k) return P.ext[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) P.ext[s .. "/" .. k] = v end,
  Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
  PreventUIRefresh = function() end, TrackList_AdjustWindows = function() end, UpdateArrange = function() end,
  time_precise = function() return os.clock() end,
}
package.loaded["TS_CV_TrackOps"] = {
  fader_category = function(tr)
    if tr.depth > 0 then return "parent" end
    if tr.recv > 0 and not parent(tr) then return "fxret" end
    return nil
  end,
}

local TR = require("TS_CV_TrackRules")

local function layout()
  local out = {}
  for _, t in ipairs(P.tracks) do out[#out + 1] = t.name .. ":" .. t.depth end
  return table.concat(out, " ")
end
local function set(s)
  local cfg = TR.decode("")
  for k, v in pairs(s or {}) do cfg[k] = v end
  TR.save(cfg)
end
local function by(name) for _, t in ipairs(P.tracks) do if t.name == name then return t end end end
local function nat(rgb) return reaper.ColorToNative((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff) | 0x1000000 end

-- ---------------------------------------------------------------- pure
check("parse: number", select(2, TR.parse_name("Guitar 12")), 12)
check("parse: base", (TR.parse_name("Rack Tom 2")), "Rack Tom")
check("parse: plain", select(2, TR.parse_name("Guitar")), nil)
check("number: next", (TR.number_name("Guitar 1", { "Guitar 1", "Bass" })), "Guitar 2")
do
  local n, ren = TR.number_name("Guitar", { "Guitar", "Guitar 2" })
  check("number: beside plain and 2", n .. " / " .. tostring(ren[1]), "Guitar 3 / Guitar 1")
end
check("number: alone keeps its name", (TR.number_name("Guitar 1", { "Bass 1" })), "Guitar 1")
check("number: alone plain", (TR.number_name("Hall Reverb", {})), "Hall Reverb")
check("levels -> depths", table.concat(TR.depths(TR.levels({ 1, 0, -1, 0 })), ","), "1,0,-1,0")
check("block end", TR.block_end({ 1, 0, -1, 0 }, 1), 3)
check("block end: nested", TR.block_end({ 1, 1, -1, 0, -1, 0 }, 1), 5)
check("kind: top-level plain", TR.add_kind({ 0, 1, -1 }, 1), "child")
check("kind: parent", TR.add_kind({ 0, 1, -1 }, 2), "child")
check("kind: inside", TR.add_kind({ 0, 1, -1 }, 3), "sibling")
do
  local pos, T_, lv = TR.place({ 0, 0 }, 1, { 0 }, false)
  check("place: plain top-level becomes a folder", pos .. " " .. T_ .. " " .. table.concat(TR.depths(lv), ","), "1 1 1,-1,0")
  pos, T_, lv = TR.place({ 1, 0, -1, 0 }, 3, { 0 }, false)
  check("place: after the closing child takes the close", table.concat(TR.depths(lv), ","), "1,0,0,-1,0")
  pos, T_, lv = TR.place({ 1, 1, -2, 0 }, 1, { 0 }, true)
  check("place: bottom of a folder whose last closes two", pos .. " " .. table.concat(TR.depths(lv), ","), "3 1,1,-1,-1,0")
  pos, T_, lv = TR.place({ 1, 0, -1, 0 }, 1, { 0, 0 }, false)
  check("place: top of a folder", pos .. " " .. table.concat(TR.depths(lv), ","), "1 1,0,0,0,-1,0")
  pos, T_, lv = TR.place({ 0, 0 }, 1, TR.rel_levels({ 1, 0, -1 }), false)
  check("place: a template's own folder kept", table.concat(TR.depths(lv), ","), "1,1,0,-2,0")
  pos, T_, lv = TR.place({ 1, -1, 0 }, nil, { 0 }, false, 2)
  check("place: at the end, before SUM", pos .. " " .. table.concat(TR.depths(lv), ","), "2 1,-1,0,0")
end
do
  local items = { { name = "Guitar 2" }, { name = "Bass" }, { name = "Guitar 1" }, { name = "Acoustic" } }
  local function names(l) local t = {} for i, x in ipairs(l) do t[i] = x.name end return table.concat(t, ",") end
  check("sort: A-Z", names(TR.sort_children(items, "az")), "Acoustic,Bass,Guitar 1,Guitar 2")
  check("sort: series together", names(TR.sort_children({ { name = "Guitar 1" }, { name = "Bass" }, { name = "Guitar 3" }, { name = "Keys" }, { name = "Guitar 2" } }, "series")),
    "Guitar 1,Guitar 2,Guitar 3,Bass,Keys")
end
do
  local s = TR.decode("")
  s.rules = { { how = "contains", text = "acoust", col = 0x6db966 }, { how = "is", text = "SUM", col = 0xffffff } }
  s.grp = { fxret = 0xf085fe }
  s.col_folder = "same"
  check("colour: name rule first", TR.colour_for(s, { name = "Acoustic 1", group = "fxret", parent_col = 0x112233 }), 0x6db966)
  check("colour: 'is' is whole", TR.colour_for(s, { name = "SUM bus" }), nil)
  check("colour: is", TR.colour_for(s, { name = "sum" }), 0xffffff)
  check("colour: group", TR.colour_for(s, { name = "Hall", group = "fxret" }), 0xf085fe)
  check("colour: folder's", TR.colour_for(s, { name = "Gtr", parent_col = 0x112233 }), 0x112233)
  s.col_folder = "shades"
  check("colour: shades lighten", TR.colour_for(s, { name = "Gtr", parent_col = 0x000000, k = 2, n = 2 }) > 0, true)
  check("colour: none", TR.colour_for(TR.decode(""), { name = "Gtr", parent_col = 0x112233 }), nil)
  local back = TR.decode(TR.encode(s))
  check("settings round trip", back.rules[2].text .. back.rules[1].col .. back.grp.fxret .. back.col_folder, "SUM" .. 0x6db966 .. 0xf085fe .. "shades")
  local a = TR.decode(""); a.alone = { "Drums", "Strings; and more" }
  check("settings: lists with odd names", TR.decode(TR.encode(a)).alone[2], "Strings; and more")
end
do
  local s = TR.decode(""); s.sp_folder, s.sp_after, s.sp_returns, s.sp_sum = true, true, true, true
  local plan = TR.spacer_plan(s, {
    { level = 0, parent = true }, { level = 1 }, { level = 0, parent = true }, { level = 1 },
    { level = 0 }, { level = 0, fxret = true }, { level = 0, fxret = true }, { level = 0, fxret = true, sum = true } })
  local t = {}
  for i, v in ipairs(plan) do t[i] = v and "S" or "." end
  check("spacers", table.concat(t), "..S.SS.S")
end

-- ---------------------------------------------------------------- adding from a template
P.templates["guitar"] = { { "Guitar 1", 0, nat(0x123456) } }
P.templates["kit"] = { { "Drums", 1 }, { "Kick", 0 }, { "Rack Tom 1", 0 }, { "Rack Tom 2", -1 } }
local function project()
  P.tracks = { T("Guitars", 1, { col = nat(0xc98a3a) }), T("Guitar 1", 0), T("Guitar 2", -1), T("Bass", 0), T("SUM", 0, { recv = 2 }) }
end

project(); set({ number = true, sort = "az" })
TR.add_from_template("guitar", by("Guitar 2"))
check("sibling: numbered, after, takes the close", layout(), "Guitars:1 Guitar 1:0 Guitar 2:0 Guitar 3:-1 Bass:0 SUM:0")

project(); set({ number = true })
TR.add_from_template("guitar", by("Bass"))
check("child of a plain top-level track", layout(), "Guitars:1 Guitar 1:0 Guitar 2:-1 Bass:1 Guitar 1:-1 SUM:0")

project(); set({ number = true, children = "bottom" })
TR.add_from_template("guitar", by("Guitars"))
check("child of a folder, at the bottom", layout(), "Guitars:1 Guitar 1:0 Guitar 2:0 Guitar 3:-1 Bass:0 SUM:0")

project(); set({ number = true, sort = "az" })
P.tracks[3].name = "Guitar 4"
TR.add_from_template("guitar", by("Guitars"))
check("child at the top, numbered, sorted", layout(), "Guitars:1 Guitar 1:0 Guitar 4:0 Guitar 5:-1 Bass:0 SUM:0")

project(); set({})
TR.add_from_template("guitar", nil)
check("no track: at the end, before SUM", layout(), "Guitars:1 Guitar 1:0 Guitar 2:-1 Bass:0 Guitar 1:0 SUM:0")

project(); set({ number = true, keep_multi = true })
TR.add_from_template("kit", by("Bass"))
check("a kit flattened, names kept", layout(), "Guitars:1 Guitar 1:0 Guitar 2:-1 Bass:1 Drums:0 Kick:0 Rack Tom 1:0 Rack Tom 2:-1 SUM:0")

project(); set({ tfolders = "keep" })
TR.add_from_template("kit", by("Bass"))
check("a kit kept as a sub-folder", layout(), "Guitars:1 Guitar 1:0 Guitar 2:-1 Bass:1 Drums:1 Kick:0 Rack Tom 1:0 Rack Tom 2:-2 SUM:0")

project(); set({ number = true, alone = { "Guitars" } })
TR.add_from_template("guitar", by("Guitar 2"))
check("a folder left alone: not numbered", layout(), "Guitars:1 Guitar 1:0 Guitar 2:0 Guitar 1:-1 Bass:0 SUM:0")

-- colours
project(); set({ col_folder = "same" })
local new = TR.add_from_template("guitar", by("Guitar 2"))
check("folder colour over the template's", new[1].col, nat(0xc98a3a))
project(); set({ col_folder = "same", tpl_col = true })
new = TR.add_from_template("guitar", by("Guitar 2"))
check("the template's own colour wins", new[1].col, nat(0x123456))
project(); set({ col_folder = "same" })
by("Guitar 1").col = nat(0x00ff00)                -- by hand
TR.apply_all(false)
check("apply: hand colour left alone", by("Guitar 1").col, nat(0x00ff00))
check("apply: the rest coloured", by("Guitar 2").col, nat(0xc98a3a))
check("apply: hand-coloured counted", TR.hand_coloured(), 2)   -- Guitars too (its own)
TR.apply_all(true)
check("apply, forced: recoloured", by("Guitar 1").col, nat(0xc98a3a))
by("Guitars").col = nat(0x0000ff)
TR.apply_all(false)
check("a stamped colour follows its folder", by("Guitar 2").col, nat(0x0000ff))
by("Guitar 2").col = nat(0x777777)                -- changed by hand since
by("Guitars").col = nat(0xff0000)
TR.apply_all(false)
check("changed by hand since: left alone", by("Guitar 2").col, nat(0x777777))

-- spacers
project(); set({ sp_folder = true, sp_after = true, sp_sum = true })
TR.apply_all(false)
local sp = {}
for _, t in ipairs(P.tracks) do sp[#sp + 1] = t.spacer end
check("spacers applied", table.concat(sp), "00011")

-- select and arm
project(); set({ arm = true, disarm = true })
by("Bass").arm = 1
new = TR.add_from_template("guitar", by("Guitar 2"))
check("armed, others disarmed", new[1].arm .. by("Bass").arm .. tostring(new[1].sel), "10true")
project(); set({ arm = true, arm_tracking = true })
P.ext["TS_TrackingMode/mode"] = "0"
new = TR.add_from_template("guitar", by("Guitar 2"))
check("mixing mode: selected, not armed", new[1].arm .. tostring(new[1].sel), "0true")
P.ext["TS_TrackingMode/mode"] = "1"
project()
new = TR.add_from_template("guitar", by("Guitar 2"))
check("tracking mode: armed", new[1].arm, 1)
P.ext["TS_TrackingMode/mode"] = nil

-- FX returns
project(); set({ number = true, grp = { fxret = 0xf085fe } })
local src = by("Bass")
P.tracks[#P.tracks + 1] = T("Hall Reverb", 0, { recv = 1 })
table.insert(P.tracks, 5, table.remove(P.tracks))   -- before SUM
local tr = TR.new_return("Hall Reverb.RfxChain", "Hall Reverb", src)
check("return: before SUM, numbered", layout(), "Guitars:1 Guitar 1:0 Guitar 2:-1 Bass:0 Hall Reverb 1:0 Hall Reverb 2:0 SUM:0")
check("return: sent, coloured, source selected", tr.recv .. tostring(tr.col == nat(0xf085fe)) .. tostring(src.sel), "1truetrue")
project(); set({ ret_where = "folder", ret_folder = "FX" })
P.tracks = { T("Bass", 0), T("FX", 1), T("Plate", -1, { recv = 1 }), T("SUM", 0, { recv = 1 }) }
tr = TR.new_return("Hall.RfxChain", "Hall", by("Bass"))
check("return: into the FX folder", layout(), "Bass:0 FX:1 Plate:0 Hall:-1 SUM:0")

-- Apply: existing series numbered, renaming as few as it can, then sorted
do
  local ren = TR.renumber({ "Gtr DI 1", "Gtr DI 1", "Gtr DI 2", "Guitar", "Guitar", "Solo", "Bass" })
  local t = {}
  for i = 1, 7 do t[i] = ren[i] or "-" end
  check("renumber: fewest renames", table.concat(t, ","), "-,Gtr DI 3,-,Guitar 1,Guitar 2,-,-")
end
P.tracks = { T("Guitars", 1), T("Gtr DI 1", 0), T("Gtr DI 1", 0), T("Gtr DI 2", 0), T("Guitar", 0), T("Guitar", -1),
             T("Drums", 1), T("Tom", 0), T("Tom", -1), T("Solo", 0), T("Solo", 0) }
set({ number = true, sort = "series", alone = { "Drums" } })
TR.apply_all(false)
check("apply: numbered and kept together", layout(),
  "Guitars:1 Gtr DI 1:0 Gtr DI 2:0 Gtr DI 3:0 Guitar 1:0 Guitar 2:-1 Drums:1 Tom:0 Tom:-1 Solo 1:0 Solo 2:0")

-- keep at the end: another name, or none
P.tracks = { T("Bass", 0), T("Mix Bus", 0, { recv = 1 }) }
set({ last = "Mix Bus" })
TR.add_from_template("guitar", nil)
check("keep at the end: another track", layout(), "Bass:0 Guitar 1:0 Mix Bus:0")
P.tracks = { T("Bass", 0), T("SUM", 0, { recv = 1 }) }
set({ last = "" })
TR.add_from_template("guitar", nil)
check("keep at the end: none", layout(), "Bass:0 SUM:0 Guitar 1:0")

-- the menu item's name
project()
check("label: plain top-level", TR.add_label(by("Bass")), "Add child from template")
check("label: inside a folder", TR.add_label(by("Guitar 1")), "Add sibling from template")
check("label: master", TR.add_label(P.master), nil)

print(fails == 0 and ("\nALL PASS (" .. checks .. ")") or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
