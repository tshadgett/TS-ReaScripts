-- @noindex  (a development tool, not a package: never installed)
--[[
  TS_CV_PinProbe.lua -- what the selected track's plugins do to their pins
  when the track's channel count goes up, as ChannelView's measurement
  taps make it.

  Use it on a test track (or a copy): a surround-capable VST3 there
  (Pro-C 3, Pro-Q 4) with a sidechain routed to it shows the problem.

  For every plugin at the top of the selected track's chain it
  logs its pins -- how many, each one's name and the channels it's wired
  to -- and its channel_config when REAPER offers one. Then it raises the
  track's channel count (16 unless you say otherwise), logs again half a
  second later, puts the count back, and logs a third time. Everything
  goes to dev/pinprobe.txt beside this script. All of it is one undo
  step: Ctrl+Z puts the track back as it was.
--]]

local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.MB("Select the test track first.", "Pin probe", 0) return end

local ok, ans = reaper.GetUserInputs("Pin probe", 1, "Raise the channel count to:", "16")
if not ok then return end
local target = math.max(2, math.floor(tonumber(ans) or 16))
if target % 2 == 1 then target = target + 1 end

local out = {}
local function say(s) out[#out + 1] = s end

local function chans(lo, hi)
  local t = {}
  for b = 0, 31 do if lo & (1 << b) ~= 0 then t[#t + 1] = tostring(b + 1) end end
  for b = 0, 31 do if hi & (1 << b) ~= 0 then t[#t + 1] = tostring(b + 33) end end
  return #t > 0 and table.concat(t, ",") or "-"
end

local function cfg(addr, key)
  local okc, v = reaper.TrackFX_GetNamedConfigParm(tr, addr, key)
  return okc and v or nil
end

-- every plugin at the top of the chain
local function walk()
  local list = {}
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do list[#list + 1] = { addr = i, depth = 0 } end
  return list
end

local function dump(title)
  say(("== %s: track channels %d"):format(title, math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN"))))
  for _, e in ipairs(walk()) do
    local a = e.addr
    local _, name = reaper.TrackFX_GetFXName(tr, a, "")
    local _, nin, nout = reaper.TrackFX_GetIOSize(tr, a)
    local pad = ("  "):rep(e.depth)
    say(("%s[%s] %s  (in %d, out %d)"):format(pad, tostring(a), name, nin or -1, nout or -1))
    local cc = cfg(a, "channel_config")
    if cc then say(pad .. "   channel_config: " .. cc) end
    for _, side in ipairs({ { false, "in", nin }, { true, "out", nout } }) do
      for p = 0, (side[3] or 0) - 1 do
        local lo, hi = reaper.TrackFX_GetPinMappings(tr, a, side[1] and 1 or 0, p)
        local pname = cfg(a, side[2] .. "_pin_" .. p) or ""
        say(("%s   %s %2d %-28s -> %s"):format(pad, side[2], p, pname, chans(math.floor(lo or 0), math.floor(hi or 0))))
      end
    end
  end
  say("")
end

local nch0 = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN"))
reaper.Undo_BeginBlock()
dump("before")
reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", target)
reaper.Undo_EndBlock("Pin probe: raise channel count", -1)

local t0 = reaper.time_precise()
local stage = 1
local function step()
  if reaper.time_precise() - t0 < 0.5 then reaper.defer(step) return end
  if stage == 1 then
    dump(("raised to %d"):format(target))
    reaper.Undo_BeginBlock()
    reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", nch0)
    reaper.Undo_EndBlock("Pin probe: channel count back", -1)
    stage, t0 = 2, reaper.time_precise()
    reaper.defer(step)
    return
  end
  dump(("back to %d"):format(nch0))
  local f = io.open(here .. "pinprobe.txt", "w")
  if f then f:write(table.concat(out, "\n")); f:close() end
  reaper.MB("Written to dev/pinprobe.txt.\n\nCtrl+Z twice puts the track's routing back as it was.", "Pin probe", 0)
end
reaper.defer(step)
