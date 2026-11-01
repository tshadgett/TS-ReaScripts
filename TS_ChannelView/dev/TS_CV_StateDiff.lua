-- @noindex  (a development tool, not a package)
--[[
  TS_CV_StateDiff.lua -- what a setting changes in a plugin's saved state,
  for a setting that isn't a parameter (ReaLimit's True peak, say).

  Run it with the track selected, giving part of the plugin's name and a
  label for how it's set now ("all off", "true peak on"). Each run adds the
  state to dev/statediff.txt: its bytes, and which ones changed since the
  run before (with the 4-byte little-endian numbers around them, as ints
  and floats). Change one setting in the plugin between runs.
--]]

local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = own .. "../?.lua;" .. package.path
local RB = require("TS_CV_ReaFX")

local track = reaper.GetSelectedTrack2(0, 0, true)
if not track then reaper.MB("Select a track first.", "State diff", 0) return end
local ok, vals = reaper.GetUserInputs("State diff", 2, "Plugin name contains,Label for this state,extrawidth=120",
  (reaper.GetExtState("TS_ChannelView", "statediff_name") ~= "" and reaper.GetExtState("TS_ChannelView", "statediff_name") or "ReaLimit") .. ",")
if not ok then return end
local want, label = vals:match("^([^,]*),(.*)$")
reaper.SetExtState("TS_ChannelView", "statediff_name", want, false)

local fx
for i = 0, reaper.TrackFX_GetCount(track) - 1 do
  local _, nm = reaper.TrackFX_GetFXName(track, i, "")
  if nm:lower():find(want:lower(), 1, true) then fx = i break end
end
if not fx then reaper.MB("No plugin on this track named like \"" .. want .. "\".", "State diff", 0) return end
local _, b64 = reaper.TrackFX_GetNamedConfigParm(track, fx, "vst_chunk")
local raw = RB.b64dec(b64 or "")

local path = own .. "statediff.txt"
local prev
do
  local f = io.open(own .. "statediff_last.txt", "rb")
  if f then prev = f:read("a"); f:close() end
end
local out = {}
local function w(s) out[#out + 1] = s end
w(("==== %s  [%s]  %d bytes"):format(label, want, #raw))
local hex = {}
for i = 1, #raw do
  hex[#hex + 1] = ("%02x"):format(raw:byte(i))
  if i % 32 == 0 then w("  " .. table.concat(hex, " ")); hex = {} end
end
if #hex > 0 then w("  " .. table.concat(hex, " ")) end
if prev then
  if #prev ~= #raw then w(("  length changed: %d -> %d"):format(#prev, #raw)) end
  local any = false
  for i = 1, math.min(#prev, #raw) do
    if prev:byte(i) ~= raw:byte(i) then
      any = true
      local a = i - ((i - 1) % 4)          -- the 4-byte word it's in
      local function word(s)
        if a + 3 > #s then return "?" end
        local iv = string.unpack("<i4", s, a)
        local fv = string.unpack("<f", s, a)
        return ("int %d / float %g"):format(iv, fv)
      end
      w(("  byte %d (0x%x): %02x -> %02x   word at %d: %s -> %s"):format(
        i - 1, i - 1, prev:byte(i), raw:byte(i), a - 1, word(prev), word(raw)))
    end
  end
  if not any then w("  (no change since the run before)") end
end
local f = io.open(path, "a")
if f then f:write(table.concat(out, "\n"), "\n\n"); f:close() end
local g = io.open(own .. "statediff_last.txt", "wb")
if g then g:write(raw); g:close() end
reaper.MB(("Added \"%s\" to %s"):format(label, path), "State diff", 0)
