-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_HwOut.lua -- a track's hardware outputs.

  With the master selected, the Sends panel (and the web page's Sends
  column) becomes Outputs: the master has nothing to send to, but it does
  have hardware outputs, and those are what you reach for there. They are
  REAPER's send category 1 -- the same object as a send, with the same
  volume, mute and pre/post fields -- so the panel draws them the same way;
  only the far end differs, which is a channel of the audio device rather
  than a track.

  I_DSTCHAN on a hardware output: the first output channel (0-based) in
  the low bits, 1024 for a single (mono) channel instead of a pair, 512
  for ReaRoute. Shared by ChannelView's panel and the web bridge.
--]]

local HO = {}

HO.CAT      = 1
HO.MONO     = 1024
HO.REAROUTE = 512

-- first channel (0-based), how many (1 or 2), ReaRoute? (pure)
function HO.decode(dst)
  dst = math.floor(dst or 0)
  return dst & 511, ((dst & HO.MONO) ~= 0) and 1 or 2, (dst & HO.REAROUTE) ~= 0
end

-- "1/2", "3", "RR 1/2" (pure)
function HO.label(dst)
  local f, n, rr = HO.decode(dst)
  local s = (n == 1) and tostring(f + 1) or ((f + 1) .. "/" .. (f + 2))
  return rr and ("RR " .. s) or s
end

-- What the audio device calls output channel `i` (0-based).
function HO.channel_name(i)
  local nm = reaper.GetOutputChannelName and reaper.GetOutputChannelName(i)
  nm = nm and nm:match("^%s*(.-)%s*$") or ""
  return (nm ~= "") and nm or ("Out " .. (i + 1))
end

-- The output's name, as the device names its channels.
function HO.name(dst)
  local f, n, rr = HO.decode(dst)
  if rr then return "ReaRoute " .. HO.label(dst) end
  if n == 1 then return HO.channel_name(f) end
  return HO.channel_name(f) .. " / " .. HO.channel_name(f + 1)
end

-- Every output there is to add or move to: the stereo pairs, then each
-- channel on its own. `nout` is the device's output count, `name(dst)`
-- names one (both looked up when not given). Returns { stereo, mono },
-- lists of { dst, label, name }.
function HO.choices(nout, name)
  nout = nout or (reaper.GetNumAudioOutputs and reaper.GetNumAudioOutputs()) or 2
  name = name or HO.name
  local stereo, mono = {}, {}
  for i = 0, nout - 2, 2 do
    stereo[#stereo + 1] = { dst = i, label = HO.label(i), name = name(i) }
  end
  for i = 0, nout - 1 do
    local d = i | HO.MONO
    mono[#mono + 1] = { dst = d, label = HO.label(d), name = name(d) }
  end
  return { stereo = stereo, mono = mono }
end

-- A new hardware output on `track` to `dst`. Returns its index, or nil.
function HO.add(track, dst)
  if not track then return nil end
  reaper.Undo_BeginBlock()
  local idx = reaper.CreateTrackSend(track, nil)
  if idx and idx >= 0 then
    reaper.SetTrackSendInfo_Value(track, HO.CAT, idx, "I_DSTCHAN", dst or 0)
  end
  reaper.Undo_EndBlock("ChannelView: add hardware output", -1)
  return (idx and idx >= 0) and idx or nil
end

-- Moves output `i` of `track` to `dst`.
function HO.set_dst(track, i, dst)
  reaper.Undo_BeginBlock()
  reaper.SetTrackSendInfo_Value(track, HO.CAT, i, "I_DSTCHAN", dst or 0)
  reaper.Undo_EndBlock("ChannelView: move hardware output", -1)
end

return HO
