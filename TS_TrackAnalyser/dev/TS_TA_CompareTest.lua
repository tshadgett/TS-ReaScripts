-- @noindex
-- Track Analyser: the comparison flag follows the pick. Run from the
-- repository root:  lua5.4 TS_TrackAnalyser/dev/TS_TA_CompareTest.lua
local mem, tracks = {}, {}
local function track(n, idx)
  local t = { name = n, idx = idx, guid = "{T" .. idx .. "}", fx = { "{" .. n .. "-pre}", "{" .. n .. "-post}" } }
  tracks[#tracks + 1] = t
  return t
end
reaper = {
  gmem_attach = function() end,
  gmem_read = function(a) return mem[a] or 0 end,
  gmem_write = function(a, v) mem[a] = v end,
  GetMediaTrackInfo_Value = function(tr, k) if k == "IP_TRACKNUMBER" then return tr.idx + 1 end return 0 end,
  GetTrackGUID = function(tr) return tr.guid end,
  TrackFX_GetFXGUID = function(tr, fx) return tr.fx[fx + 1] end,
  TrackFX_GetNumParams = function() return 2 end,
  ValidatePtr2 = function() return true end,
}
package.path = "TS_TrackAnalyser/?.lua;" .. package.path
local TA = dofile("TS_TrackAnalyser/TS_TA_Chain.lua")
local PL = TA.PL
assert(PL, "ProbeLink not loaded")

local fails = 0
local function check(name, cond)
  print((cond and "ok   " or "FAIL ") .. name)
  if not cond then fails = fails + 1 end
end
local kick, bass = track("Kick Sub", 10), track("Bass", 20)
local function rig(t) return { track = t, pre = { idx = 0 }, post = { idx = 1 } } end
local function cmp(t) return PL.get(t, 1, "compare") end
local function pub(t) return PL.get(t, 1, "pub_post") end

-- Kick Sub selected, compared against Bass
local rk, rb = rig(kick), rig(bass)
TA.arm(rk); TA.armCompare(rb); TA.tick()
check("Bass is the comparison", cmp(bass) == 1 and pub(bass) == 1)
check("Kick Sub is a post", cmp(kick) == 0 and pub(kick) == 1)

-- Bass selected: Track Analyser keeps Bass's probes (the comparison track
-- became the selected one, so it isn't released), and compares against
-- Kick Sub now
TA.disarm(rk); TA.arm(rig(bass)); TA.armCompare(rig(kick)); TA.tick()
check("Bass selected: no longer the comparison", cmp(bass) == 0)
check("Bass selected: still publishing", pub(bass) == 1)
check("Kick Sub: the comparison now", cmp(kick) == 1 and pub(kick) == 1)

-- the comparison let go: back to an ordinary post probe, quiet
TA.releaseCompare(rig(kick)); TA.tick()
check("Kick Sub released", cmp(kick) == 0 and pub(kick) == 0)

if fails > 0 then print(fails .. " failed") os.exit(1) end
print("all passed")
