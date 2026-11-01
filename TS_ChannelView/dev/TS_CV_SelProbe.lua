-- @noindex
-- dev tool, not released: removes the selected track's plugins one at a
-- time (last first), 2 s apart, and logs which track is selected after
-- each -> dev/sel.txt. Undo puts them back (one undo point each).
local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local f = io.open(script_dir .. "sel.txt", "w")
local function say(x) f:write(x .. "\n"); f:flush() end
local function sel_names()
  local t = {}
  for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
    local tr = reaper.GetSelectedTrack2(0, i, true)
    local _, n = reaper.GetTrackName(tr)
    t[#t + 1] = n
  end
  return table.concat(t, ", ")
end
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then say("no track selected") f:close() return end
local _, name = reaper.GetTrackName(tr)
say("start on " .. name .. "; selected: " .. sel_names())
local t0 = reaper.time_precise()
local function step()
  if reaper.time_precise() - t0 < 2 then reaper.defer(step) return end
  if not reaper.ValidatePtr2(0, tr, "MediaTrack*") then say("track gone") f:close() return end
  local n = reaper.TrackFX_GetCount(tr)
  say(("  after 2 s: selected = %s"):format(sel_names()))
  if n == 0 then say("done") f:close() return end
  local _, fxn = reaper.TrackFX_GetFXName(tr, n - 1, "")
  reaper.Undo_BeginBlock()
  reaper.TrackFX_Delete(tr, n - 1)
  reaper.Undo_EndBlock("SelProbe: remove " .. fxn, -1)
  say(("removed %s; selected now = %s"):format(fxn, sel_names()))
  t0 = reaper.time_precise()
  reaper.defer(step)
end
reaper.defer(step)
