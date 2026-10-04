-- @noindex
-- TS_360LinkFollow_Refresh: replace every SSL 360 Link on visible tracks with a
-- fresh instance in the same FX slot -- one at a time, each checked against
-- SSL 360's log and replaced again if its strip does not register.
--
-- Track templates and duplicated tracks carry a copy of the same 360 Link
-- identity, and SSL 360 ignores an instance whose identity is already taken. A
-- freshly inserted 360 Link gets an identity of its own. Run this on a session
-- whose strips are missing, or on tracks made from a template (then save the
-- template again). 360 Link's own state is only its A/B defaults and 360's
-- solo/cut flags, so nothing of yours is lost.

local r = reaper
local here = ({ r.get_action_context() })[2]:match("^(.*[/\\])")
local Core = dofile(here .. "TS_360LinkFollow_Core.lua")

local queue = Core.queue()
local total = 0
for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  if r.IsTrackVisible(tr, true) then
    local slots = Core.link_slots(tr, true)
    if #slots > 0 then
      queue:add(tr, slots)
      total = total + 1
    end
  end
end

local started = r.time_precise()
local function loop()
  queue:tick()
  if queue:busy() and r.time_precise() - started < 300 then
    r.defer(loop)
  else
    local msg = string.format("TS_360LinkFollow_Refresh: %d tracks refreshed", total)
    if queue.read_log then
      msg = msg .. string.format(", %d confirmed by SSL 360", queue.confirmed)
      if queue.failed > 0 then msg = msg .. string.format(", %d did not register", queue.failed) end
    else
      msg = msg .. " (SSL 360's log not readable, so not checked)"
    end
    r.ShowConsoleMsg(msg .. "\n")
  end
end

if total > 0 then loop() end
