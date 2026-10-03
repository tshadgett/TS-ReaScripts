-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_WebLink.lua -- is the web companion running, and is a page open?

  For the small tablet in ChannelView's header. Two counters in ExtState
  section TS_CV_WEB say it, neither of them ChannelView's:

    alive   bumped by the bridge (TS_ChannelView_Web.lua) every cycle, and
            cleared when it stops. Moving = running.
    seen    written by each open page about once a second, as "<id>.<n>":
            a random id per page and a counter. Every page writes the same
            key, so pages are told apart by the id, and one counts as
            connected while its id keeps turning up.

  A value that was already there when ChannelView looked first proves
  nothing -- a page closed an hour ago left its last one behind -- so only
  a CHANGE counts. Nothing here touches REAPER: update() is handed the two
  values and the time, which is what the tests do too.
--]]

local WL = {}

WL.BRIDGE_GONE = 3     -- seconds without the bridge's counter moving
WL.PAGE_GONE   = 5     -- seconds without a page's heartbeat

function WL.new() return { alive = nil, alive_at = nil, seen = nil, pages = {} } end

function WL.update(st, now, alive, seen)
  alive, seen = alive or "", seen or ""
  if st.alive ~= nil and alive ~= "" and alive ~= st.alive then st.alive_at = now end
  if alive == "" then st.alive_at = nil end          -- it said it stopped
  st.alive = alive
  if st.seen ~= nil and seen ~= "" and seen ~= st.seen then
    local id = seen:match("^(%w+)%.")
    if id then st.pages[id] = now end
  end
  st.seen = seen
end

-- running (the bridge), pages (how many open pages are still beating).
function WL.state(st, now)
  local running = st.alive_at ~= nil and now - st.alive_at < WL.BRIDGE_GONE
  local n = 0
  for id, t in pairs(st.pages) do
    if now - t < WL.PAGE_GONE then n = n + 1 else st.pages[id] = nil end
  end
  return running, n
end

return WL
