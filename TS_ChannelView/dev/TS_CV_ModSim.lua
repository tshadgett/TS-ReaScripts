-- @noindex  (a development tool, not a package: never installed)
-- Offline check of TS_CV_Mod.lua against a fake REAPER that models FX
-- chains with containers the way REAPER addresses them (0x2000000 + ...),
-- container_map, named config parameters and parameter links.
--     lua5.4 dev/TS_CV_ModSim.lua

local HERE = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "./"
package.path = HERE .. "../?.lua;" .. HERE .. "?.lua;" .. package.path

local fails, passes = 0, 0
local function check(name, got, want)
  if got == want then passes = passes + 1; print(("ok   %-44s %s"):format(name, tostring(got)))
  else fails = fails + 1; print(("FAIL %-44s got %s  want %s"):format(name, tostring(got), tostring(want))) end
end

-- ---------------------------------------------------------------------
-- the fake
-- ---------------------------------------------------------------------
local FLAG = 0x2000000
local gid = 0
local function new_fx(fxname, nparams, container)
  gid = gid + 1
  return { fxname = fxname, guid = ("{%08d-0000-0000-0000-000000000000}"):format(gid),
           cfg = {}, values = {}, params = nparams or 0,
           children = container and {} or nil, maps = container and {} or nil }
end

local TR = { fx = {}, ext = {} }
local MDF   -- TS_CV_Mod's field table, once it's loaded
-- the matrix (192 on): source 0..24, target 0..1515, amount -1..1000000
local MX_RANGE = { { 0, 24 }, { 0, 1515 }, { -1, 1000000 } }
function RANGE(n, p)
  if n.ours and p >= 192 then local r = MX_RANGE[(p - 192) % 3 + 1]; return r[1], r[2] end
  if not n.ours or p < 16 then return 0, 1 end
  local f = MDF[(p - 16) % 22 + 1]
  return f[3], f[4]
end
function DEFAULT(n, p)
  if n.ours and p >= 192 then local lo, hi = RANGE(n, p); return (0 - lo) / (hi - lo) end
  if not n.ours or p < 16 then return 0 end
  local f = MDF[(p - 16) % 22 + 1]
  return (f[2] - f[3]) / (f[4] - f[3])
end
local changes = 0
local INSTALLED = {}    -- path under Effects -> desc

local function decode(tr, addr)
  if addr < FLAG then return { addr } end
  local v = addr - FLAG
  local sc = #tr.fx + 1
  local path = { (v % sc) - 1 }
  v = v // sc
  local node = tr.fx[path[1] + 1]
  while v > 0 do
    if not (node and node.children) then return nil end
    local cc = #node.children + 1
    -- the last level needs no modulo: its slot can be the one past the
    -- end (an insertion point), which a modulo would wrap to nothing
    local i
    if v <= cc then i, v = v - 1, 0
    else i = (v % cc) - 1; v = v // cc end
    path[#path + 1] = i
    node = node.children[i + 1]
  end
  return path
end
local function at(tr, path)
  local list, node = tr.fx, nil
  for d, i in ipairs(path) do
    node = list[i + 1]
    if not node then return nil end
    if d < #path then
      if not node.children then return nil end
      list = node.children
    end
  end
  return node, list, path[#path]
end
local function node_of(tr, addr) local p = decode(tr, addr); return p and at(tr, p) end

reaper = {
  TrackFX_GetCount = function(tr) return #tr.fx end,
  TrackFX_GetNamedConfigParm = function(tr, addr, k)
    local n = node_of(tr, addr)
    if not n then return false, "" end
    if k == "container_count" then
      if n.children then return true, tostring(#n.children) end
      return false, ""
    end
    if k == "fx_name" then return true, n.fxname end
    if k == "renamed_name" then return true, n.cfg.renamed_name or "" end
    local s, p = k:match("^container_map%.add%.(%d+)%.(%d+)$")
    if s and n.maps then
      n.maps[#n.maps + 1] = { tonumber(s), tonumber(p) }
      changes = changes + 1
      return true, tostring(#n.maps - 1)
    end
    local i, f = k:match("^param%.(%d+)%.container_map%.(fx_%a+)$")
    if i and n.maps then
      local m = n.maps[tonumber(i) + 1]
      if not m then return false, "" end
      return true, tostring(f == "fx_index" and m[1] or m[2])
    end
    local v = n.cfg[k]
    if v == nil then
      if k:match("^param%.%d+%.plink%.active$") or k:match("%.mod%.active$")
         or k:match("%.lfo%.active$") or k:match("%.acs%.active$") then return true, "0" end
      return false, ""
    end
    return true, tostring(v)
  end,
  TrackFX_SetNamedConfigParm = function(tr, addr, k, v)
    local n = node_of(tr, addr)
    if not n then return false end
    n.cfg[k] = v
    changes = changes + 1
    return true
  end,
  TrackFX_GetNumParams = function(tr, addr)
    local n = node_of(tr, addr)
    if not n then return 0 end
    if n.maps then return #n.maps end
    return n.params
  end,
  TrackFX_GetParamNormalized = function(tr, addr, p)
    local n = node_of(tr, addr); return n and (n.values[p] or 0) or 0
  end,
  TrackFX_SetParamNormalized = function(tr, addr, p, v)
    local n = node_of(tr, addr); if n then n.values[p] = v end; return true
  end,
  TrackFX_GetFXGUID = function(tr, addr) local n = node_of(tr, addr); return n and n.guid end,
  TrackFX_GetFXName = function(tr, addr)
    local n = node_of(tr, addr); if not n then return false, "" end
    return true, n.cfg.renamed_name and n.cfg.renamed_name ~= "" and n.cfg.renamed_name or n.fxname
  end,
  TrackFX_AddByName = function(tr, name, rec, inst)
    local fx
    if name == "Container" then fx = new_fx("Container", 0, true)
    elseif INSTALLED[name] then fx = new_fx("JS: " .. INSTALLED[name], INSTALLED[name] == "ChannelView Modulators" and (OLD_MODS and 192 or 240) or 5)
      fx.ours = INSTALLED[name] == "ChannelView Modulators"
    else return -1 end
    local pos
    if inst == -1 then pos = #tr.fx else pos = -1000 - inst end
    table.insert(tr.fx, pos + 1, fx)
    changes = changes + 1
    return pos
  end,
  TrackFX_CopyToTrack = function(tr, src, dtr, dest, move)
    local dpath = decode(tr, dest)
    local spath = decode(tr, src)
    local sn, slist, si = at(tr, spath)
    assert(sn, "no source")
    -- the destination's parent level, found before the source moves
    local parent = {}
    for d = 1, #dpath - 1 do parent[d] = dpath[d] end
    local plist = tr.fx
    if #parent > 0 then plist = (at(tr, parent)).children end
    if move then table.remove(slist, si + 1) end
    table.insert(plist, dpath[#dpath] + 1, move and sn or sn)
    changes = changes + 1
  end,
  TrackFX_Delete = function(tr, addr)
    local p = decode(tr, addr); local _, list, i = at(tr, p)
    table.remove(list, i + 1); changes = changes + 1; return true
  end,
  TrackFX_GetEnabled = function() return true end,
  -- real values: ours have each field's own range, the rest 0..1
  TrackFX_GetParam = function(tr, addr, p)
    local n = node_of(tr, addr); if not n then return 0, 0, 1 end
    local lo, hi = RANGE(n, p)
    return lo + (n.values[p] or DEFAULT(n, p)) * (hi - lo), lo, hi
  end,
  TrackFX_SetParam = function(tr, addr, p, v)
    local n = node_of(tr, addr); if not n then return false end
    local lo, hi = RANGE(n, p)
    n.values[p] = (v - lo) / (hi - lo); changes = changes + 1; return true
  end,
  TrackFX_Show = function() end,
  TrackFX_GetParameterStepSizes = function(tr, addr, p)
    local n = node_of(tr, addr)
    if n and n.steps and n.steps[p] then return true, 1 / (n.steps[p] - 1), 0, 0, n.steps[p] == 2 end
    return false
  end,
  TrackFX_FormatParamValueNormalized = function(tr, addr, p, v) return true, ("S%.0f"):format(v * 100) end,
  GetFXEnvelope = function(tr, addr, p, create)
    local n = node_of(tr, addr); if not n then return nil end
    n.envs = n.envs or {}
    if not n.envs[p] and create then n.envs[p] = { points = 0, vis = true } end
    return n.envs[p]
  end,
  CountEnvelopePoints = function(env) return env.points end,
  GetMediaTrackInfo_Value = function(tr, k) return tr.info and tr.info[k] or 2 end,
  SetMediaTrackInfo_Value = function(tr, k, v) tr.info = tr.info or {}; tr.info[k] = v end,
  TrackList_AdjustWindows = function() end, UpdateArrange = function() end,
  GetSetMediaTrackInfo_String = function(tr, k, v, setnew)
    if setnew then tr.ext[k] = v; return true, v end
    return tr.ext[k] ~= nil, tr.ext[k] or ""
  end,
  Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
  PreventUIRefresh = function() end,
  GetProjectStateChangeCount = function() return changes end,
  time_precise = function() return os.clock() end,
}

local MD = require("TS_CV_Mod")
local T  = require("TS_CV_FXTree")
MDF = MD.FIELDS
package.loaded["TS_CV_Envelopes"] = {
  fx_lane = function(tr, fx, p)
    local env = reaper.GetFXEnvelope(tr, fx, p, false)
    if not env then return nil end
    return { env = env, shown = env.vis, auto = env.points > 1 }
  end,
  toggle_fx_lane = function(tr, fx, p)
    local env = reaper.GetFXEnvelope(tr, fx, p, false)
    if not env then reaper.GetFXEnvelope(tr, fx, p, true) else env.vis = not env.vis end
  end,
}

-- ---------------------------------------------------------------------
-- a chain: probe, an EQ, a container with a compressor in it, probe
-- ---------------------------------------------------------------------
INSTALLED["TS_ChannelView/TS_CV_Modulators.jsfx"] = "ChannelView Modulators"

local pre  = new_fx("JS: TS_TrackProbe", 20)
local eq   = new_fx("VST3: Pro-Q 3 (FabFilter)", 12)
local box  = new_fx("Container", 0, true)
local comp = new_fx("VST3: Pro-C 2 (FabFilter)", 10)
box.children[1] = comp
local post = new_fx("JS: TS_TrackProbe", 20)
TR.fx = { pre, eq, box, post }
eq.values[3] = 0.4
comp.values[5] = 0.7
comp.steps = { [6] = 3 }

check("no plugin yet", MD.plugin(TR), nil)
check("nothing listed", #MD.scan(TR).list, 0)
check("strip with no plugin", #MD.strip(TR, T.collect(TR)), 4)
check("slot after the probe", MD.slot_for(TR, false), 1)
check("slot behind ARA and probe", (function()
  local ara = new_fx("VST3: Melodyne (Celemony)", 4)
  table.insert(TR.fx, 1, ara)
  local s = MD.slot_for(TR, true)
  table.remove(TR.fx, 1)
  return s
end)(), 2)
check("field count", #MD.FIELDS, 22)
check("param of mod 2 depth", MD.param(2, "depth"), 16 + 22 + 3)

-- the first macro puts the plugin on the track, after the probe
local g1 = MD.add_macro(TR, "knob", false)
check("macro guid", g1, "m1")
check("plugin made", MD.plugin(TR), 1)
check("chain order kept", TR.fx[1] == pre and TR.fx[3] == eq and TR.fx[5] == post, true)
local s = MD.scan(TR)
check("one source", #s.list, 1)
check("macro named", s.list[1].name, "Macro")
check("macro out param", s.list[1].out[1], 0)
check("used 1", MD.macros_used(TR), 1)

-- an XY takes two slots; a knob after it the next free one
check("xy", MD.add_macro(TR, "xy", false), "m2")
check("knob after xy", MD.add_macro(TR, "knob", false), "m4")
s = MD.scan(TR)
check("used 4", MD.macros_used(TR), 4)
check("xy outs", s.macros[2].out[1] .. "," .. s.macros[2].out[2], "1,2")
check("second knob numbered", s.macros[3].name, "Macro 2")
check("dropdown", MD.add_macro(TR, "dropdown", false), "m5")
s = MD.scan(TR)
check("dropdown default choices", #s.macros[4].choices, 3)

-- modulators
local go = MD.add_mod(TR, "lfo", false)
check("lfo guid", go, "o1")
check("plugin not doubled", #TR.fx, 5)
s = MD.scan(TR)
local lfo = s.mods[1]
check("lfo kind", lfo.kind, "lfo")
check("lfo type set", MD.field(TR, 1, 1, "type"), 1)
check("lfo depth default", MD.field(TR, 1, 1, "depth"), 1)
check("lfo rate default 1/4", MD.SYNC[MD.field(TR, 1, 1, "rsync") + 1], "1/4")
MD.add_mod(TR, "lfo", false)
MD.add_mod(TR, "follower", false)
s = MD.scan(TR)
check("three mods", #s.mods, 3)
check("second lfo name", s.mods[2].name, "LFO 2")
check("second lfo other colour", s.mods[2].col ~= s.mods[1].col, true)

-- the plugin row leaves ours out
local stripped = MD.strip(TR, T.collect(TR))
local names = {}
for _, fx in ipairs(stripped) do names[#names + 1] = fx.name end
check("row without ours", table.concat(names, ","),
  "JS: TS_TrackProbe,VST3: Pro-Q 3 (FabFilter),VST3: Pro-C 2 (FabFilter),JS: TS_TrackProbe")

-- an LFO onto the EQ's parameter 3: swings from where it's set
check("link lfo", MD.link(TR, lfo, 1, { 2 }, 3), true)
check("plink effect is ours", eq.cfg["param.3.plink.effect"], "1")
check("plink param is the output", eq.cfg["param.3.plink.param"], tostring(MD.param(1, "out")))
check("baseline kept", eq.cfg["param.3.mod.baseline"], "0.4")
check("native LFO switched off by the link", eq.cfg["param.3.lfo.active"], "0")
check("default depth to the far end", eq.cfg["param.3.plink.scale"], "0.6")
local l = MD.link_of(TR, eq.guid, 3)
check("scan finds it", l and l.mod.guid, "o1")
check("not a macro link", l.macro, false)
local lo, hi = MD.span(l, TR)
check("span", ("%.2f %.2f"):format(lo, hi), "0.40 1.00")
MD.set_field(TR, 1, 1, "depth", 0.5)
lo, hi = MD.span(MD.link_of(TR, eq.guid, 3), TR)
check("span follows Depth", ("%.2f %.2f"):format(lo, hi), "0.40 0.70")
MD.set_bipolar(TR, l, true)
l = MD.link_of(TR, eq.guid, 3)
check("bipolar uses the bipolar output", eq.cfg["param.3.plink.param"], tostring(MD.param(1, "outb")))
check("is bipolar", MD.is_bipolar(l), true)
lo, hi = MD.span(l, TR)
check("bipolar span", ("%.2f %.2f"):format(lo, hi), "0.25 0.55")
MD.set_bipolar(TR, l, false)
check("back to one way", MD.link_of(TR, eq.guid, 3).sparam, MD.param(1, "out"))
MD.set_field(TR, 1, 1, "depth", 1)
-- the swing's handles: each end set, the other staying put
l = MD.link_of(TR, eq.guid, 3)
local e1 = MD.swing_ends(TR, l)
check("one way: rest and full", ("%.2f %.2f"):format(e1[1], e1[2]), "0.40 1.00")
MD.set_swing_end(TR, l, 2, 0.7)
e1 = MD.swing_ends(TR, l)
check("full end dragged", ("%.2f %.2f %.2f"):format(e1[1], e1[2], l.scale), "0.40 0.70 0.30")
MD.set_swing_end(TR, l, 1, 0.2)
e1 = MD.swing_ends(TR, l)
check("rest end dragged, full stays", ("%.2f %.2f"):format(e1[1], e1[2]), "0.20 0.70")
MD.set_swing_end(TR, l, 1, 0.9)
e1 = MD.swing_ends(TR, l)
check("crossed: works the other way", ("%.2f %.2f %.2f"):format(e1[1], e1[2], l.scale), "0.90 0.70 -0.20")
MD.set_field(TR, 1, 1, "depth", 0.5)
MD.set_swing_end(TR, l, 2, 0.5)
e1 = MD.swing_ends(TR, l)
check("follows the LFO's Depth", ("%.2f %.2f %.2f"):format(e1[1], e1[2], l.scale), "0.90 0.50 -0.80")
MD.set_field(TR, 1, 1, "depth", 1)
MD.set_bipolar(TR, l, true)
l = MD.link_of(TR, eq.guid, 3)
MD.set_swing_end(TR, l, 1, 0.2); MD.set_swing_end(TR, l, 2, 0.6)
local e2 = MD.swing_ends(TR, l)
check("both ways: ends set", ("%.2f %.2f %.2f"):format(e2[1], e2[2], l.baseline), "0.20 0.60 0.40")
MD.shift_link(TR, l, 0.6)
e2 = MD.swing_ends(TR, l)
check("turned: the swing moves, stops at the top", ("%.2f %.2f"):format(e2[1], e2[2]), "0.60 1.00")
MD.set_bipolar(TR, l, false)
MD.set_baseline(TR, l, 0.4)
MD.set_depth(TR, MD.link_of(TR, eq.guid, 3), 0.6)
-- centre-oriented controls: a modulator swings them both ways
local fmt = reaper.TrackFX_FormatParamValueNormalized
reaper.TrackFX_FormatParamValueNormalized = function(tr, a, p, v)
  if p == 7 then return true, v < 0.25 and "-24.0 dB" or (v > 0.75 and "+24.0 dB" or "0.0 dB") end
  if p == 8 then return true, v < 0.25 and "100L" or (v > 0.75 and "100R" or "C") end
  if p == 9 then return true, v < 0.25 and "-inf dB" or "+6.0 dB" end
  return fmt(tr, a, p, v)
end
check("centred: a ± gain", MD.is_centred(TR, 2, 7), true)
check("centred: pan", MD.is_centred(TR, 2, 8), true)
check("not centred: -inf to +6", MD.is_centred(TR, 2, 9), false)
check("not centred: plain", MD.is_centred(TR, 2, 5), false)
eq.values[7] = 0.5
MD.link(TR, lfo, 1, { 2 }, 7)
local lc = MD.link_of(TR, eq.guid, 7)
check("centred: linked bipolar", lc.bipolar, true)
check("centred: full swing both ways", ("%.2f %.2f"):format(MD.span(lc, TR)), "0.00 1.00")
eq.values[9] = 0.5
MD.link(TR, lfo, 1, { 2 }, 9, true)
check("layout says centred", MD.link_of(TR, eq.guid, 9).bipolar, true)
MD.unlink(TR, lc); MD.unlink(TR, MD.link_of(TR, eq.guid, 9))
reaper.TrackFX_FormatParamValueNormalized = fmt
local high = new_fx("VST3: Hi", 2)
check("default depth high goes down", MD.default_depth(0.8), -0.8)

-- a macro onto the compressor inside the container: its whole range
local mac = MD.scan(TR).macros[1]
check("link macro nested", MD.link(TR, mac, 1, { 3, 0 }, 5), true)
check("box exposes comp param", #box.maps, 1)
check("link lives on the box", box.cfg["param.0.plink.effect"], "1")
local l2 = MD.link_of(TR, comp.guid, 5)
check("scan resolves nested", l2 and l2.mod.guid, "m1")
check("macro link", l2.macro, true)
local a, b = MD.range(l2)
check("whole range", a .. " " .. b, "0 1")
MD.set_range(TR, l2, 0.25, 0.8)
l2 = MD.link_of(TR, comp.guid, 5)
a, b = MD.range(l2)
check("range set", ("%.2f %.2f"):format(a, b), "0.25 0.80")
TR.fx[2].values[0] = 0.5
check("live mid", ("%.3f"):format(MD.live(TR, l2)), "0.525")
MD.shift_range(TR, l2, 0.5)
a, b = MD.range(MD.link_of(TR, comp.guid, 5))
check("shift stops at the top", ("%.2f %.2f"):format(a, b), "0.45 1.00")
MD.set_range(TR, l2, 0.9, 0.1)
lo, hi = MD.span(MD.link_of(TR, comp.guid, 5), TR)
check("crossed ends: span still lo..hi", ("%.2f %.2f"):format(lo, hi), "0.10 0.90")

-- replacing the macro with an LFO: baseline from where it sits now
MD.link(TR, lfo, 1, { 3, 0 }, 5)
check("no duplicate box mapping", #box.maps, 1)
local l3 = MD.link_of(TR, comp.guid, 5)
check("replaced source", l3.mod.guid, "o1")
check("macro was there: fresh depth", l3.scale ~= -0.8, true)

-- XY's Y links as output 2
local xy = MD.scan(TR).macros[2]
MD.link(TR, xy, 2, { 2 }, 4)
local l4 = MD.link_of(TR, eq.guid, 4)
check("xy Y link", l4.out .. " " .. l4.sparam, "2 2")

-- dropdown on a stepped param: its choices
local names3 = MD.steps_of(TR, T.addr_of(TR, { 3, 0 }), 6)
check("stepped param choices", names3 and #names3, 3)
check("not stepped", MD.steps_of(TR, T.addr_of(TR, { 3, 0 }), 2), nil)
local dd = MD.scan(TR).macros[4]
MD.set_choices(TR, dd, { "Soft", "Med", "Hard", "x", "y", "z", "a", "b", "c" })
check("choices capped at 8", #MD.scan(TR).macros[4].choices, 8)
MD.set_choices(TR, dd, { "Soft", "Hard|x" })
check("choices cleaned", MD.scan(TR).macros[4].choices[2], "Hard x")
check("choice of", MD.choice_of(0.5, 3), 2)
check("choice value", MD.choice_value(3, 3), 1)

-- control type: knob to xy needs the next slot free
local k4 = MD.scan(TR).macros[3]   -- m4; m5 is the dropdown
check("xy refused when next taken", MD.set_ctl(TR, k4, "xy"), false)
check("to a button", MD.set_ctl(TR, k4, "button"), true)
check("now a button", MD.scan(TR).macros[3].kind, "button")
-- xy back to a knob drops Y's links
MD.set_ctl(TR, xy, "knob")
check("Y link gone", MD.link_of(TR, eq.guid, 4), nil)
check("slot 3 free again", MD.add_macro(TR, "fader", false), "m3")

-- rename, colour (kept on the track)
MD.rename(TR, mac, "Fil|ter")
check("renamed", MD.scan(TR).macros[1].name, "Fil ter")
MD.set_colour(TR, lfo, 0x112233ff)
check("colour saved", MD.find(TR, "o1").col, 0x112233ff)

-- lanes
check("no lane", MD.lane(TR, 1, 0), nil)
MD.toggle_lane(TR, 1, 0)
local ln = MD.lane(TR, 1, 0)
check("lane made and shown", ln and ln.shown, true)
check("no automation yet", ln.auto, false)
ln.env.points = 3
check("has automation", MD.lane(TR, 1, 0).auto, true)
MD.toggle_lane(TR, 1, 0)
check("lane hidden", MD.lane(TR, 1, 0).shown, false)

-- a macro under REAPER's own parameter modulation: the write sets its baseline too
do
  local ours = TR.fx[2]
  ours.cfg["param.0.mod.active"] = "1"
  MD.set_macro(TR, MD.scan(TR).macros[1], 1, 0.5)
  check("stray modulation (no source) switched off", ours.cfg["param.0.mod.active"], "0")
  ours.cfg["param.0.mod.active"] = "1"
  ours.cfg["param.0.lfo.active"] = "1"
  MD.set_macro(TR, MD.scan(TR).macros[1], 1, 0.66)
  check("modulated macro: baseline follows", ours.cfg["param.0.mod.baseline"], "0.66")
  ours.cfg["param.0.mod.active"] = nil
  ours.cfg["param.0.lfo.active"] = nil
  ours.cfg["param.0.mod.baseline"] = nil
  MD.set_macro(TR, MD.scan(TR).macros[1], 1, 0.3)
  check("unmodulated macro: no baseline written", ours.cfg["param.0.mod.baseline"], nil)
end

-- a flat lane (one point) follows the macro; real automation is left alone
do
  local ours = TR.fx[2]
  ours.envs = ours.envs or {}
  local keep = ours.envs[0]
  ours.envs[0] = { points = 1, v0 = 0.4351, vis = false }
  local sp = reaper.SetEnvelopePoint
  reaper.SetEnvelopePoint = function(env, i, t, v) env.v0 = v end
  reaper.Envelope_SortPoints = function() end
  reaper.TrackFX_GetParamEx = function() return 0, 0, 1, 0.5 end
  MD.set_macro(TR, MD.scan(TR).macros[1], 1, 0.8)
  check("flat lane follows", ours.envs[0].v0, 0.8)
  ours.envs[0].points, ours.envs[0].v0 = 3, 0.1
  MD.set_macro(TR, MD.scan(TR).macros[1], 1, 0.6)
  check("automation left alone", ours.envs[0].v0, 0.1)
  ours.envs[0] = keep
  reaper.SetEnvelopePoint = sp
end

-- sidechain
MD.need_sidechain(TR)
check("track to 4 channels", TR.info.I_NCHAN, 4)

-- THE MATRIX: a modulator's settings moved by a macro or another modulator
do
  local lfo = MD.find(TR, "o1")
  local knob = MD.find(TR, "m1")
  local fol
  for _, src in ipairs(MD.scan(TR).mods) do if src.kind == "follower" then fol = src end end
  check("matrix: the plugin has it", MD.mx_ok(TR, lfo.slot), true)
  check("matrix: a macro moves the LFO's rate", (MD.mx_link(TR, lfo, "rsync", knob, 1)), true)
  local e = MD.mx_get(TR, lfo.slot, lfo.j)
  local first = e[1] or e[2]
  check("matrix: rate from macro 1", first and (first.tg.key .. " " .. first.code), "rate 1")
  check("matrix: half the range to start", first and first.amt, 0.5)
  check("matrix: not by itself", select(2, MD.mx_can(TR, lfo, "depth", lfo, 1)), "Can't move itself")
  check("matrix: a knob macro can't move a switch",
    select(2, MD.mx_can(TR, lfo, "shape", knob, 1)), "Switches: button or dropdown macros only")
  check("matrix: the follower ducks its depth", (MD.mx_link(TR, lfo, "depth", fol, 1)), true)
  local dd = MD.find(TR, "m5")
  check("matrix: full at two", select(2, MD.mx_can(TR, lfo, "shape", dd, 1)), lfo.name .. " is moved by two already")
  check("matrix: the same pair again just updates", (MD.mx_can(TR, lfo, "rsync", knob, 1)), true)
  -- a dropdown macro picks the follower's source
  check("matrix: dropdown to a switch", (MD.mx_link(TR, fol, "fsrc", dd, 1, 1)), true)
  local fe = MD.mx_get(TR, fol.slot, fol.j)
  local sw = fe[1] or fe[2]
  check("matrix: its choices counted", sw and sw.nch, #dd.choices)
  check("matrix: choice 2 -> Sidechain, the rest its own", sw and MD.mx_unpack(sw.amt, sw.nch)[2], 1)
  check("matrix: pack / unpack", MD.mx_pack(MD.mx_unpack(4030, 4), 4), 4030)
  -- a dropdown taking a switch's names: choice c picks setting c
  check("matrix: dropdown one for one", MD.mx_direct(TR, fol, "fsrc", dd, 1), true)
  local de = MD.mx_get(TR, fol.slot, fol.j)
  local dw = de[1] or de[2]
  local dm = dw and MD.mx_unpack(dw.amt, dw.nch)
  check("matrix: Track, Sidechain by choice", dm and (tostring(dm[1]) .. tostring(dm[2])), "01")
  check("matrix: the LFO's six shapes", #MD.mx_names("shape"), 6)
  -- removing a source clears what it moved
  MD.remove(TR, fol)
  local after = MD.mx_get(TR, lfo.slot, lfo.j)
  local n = 0
  for _ in pairs(after) do n = n + 1 end
  check("matrix: the follower's slot gone with it", n, 1)
  for sl in pairs(after) do MD.mx_unlink(TR, lfo, sl) end
  check("matrix: unlinked", next(MD.mx_get(TR, lfo.slot, lfo.j)), nil)
end

-- remove the LFO: its links go with it
MD.remove(TR, MD.find(TR, "o1"))
check("lfo removed", MD.find(TR, "o1"), nil)
check("its link removed", eq.cfg["param.3.plink.active"], "0")
check("type off", MD.field(TR, 1, 1, "type"), 0)
-- remove everything: the plugin stays (it has a lane with automation)
for _, src in ipairs(MD.scan(TR).list) do MD.remove(TR, src) end
check("all gone", #MD.scan(TR).list, 0)
check("plugin kept for its automation", MD.plugin(TR), 1)
TR.fx[2].envs = nil
MD.add_macro(TR, "knob", false)
MD.remove(TR, MD.scan(TR).list[1])
check("plugin gone with the last one", MD.plugin(TR), nil)
check("chain back as it was", #TR.fx, 4)

print(fails == 0 and ("\nALL PASS (" .. passes .. ")") or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
