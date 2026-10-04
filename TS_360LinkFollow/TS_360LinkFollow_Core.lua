-- @noindex
-- Shared code for TS_360LinkFollow and TS_360LinkFollow_Refresh.
--
-- SSL 360 drops connections when many 360 Link instances start at once, and an
-- instance that misses its connection never retries. So 360 Links are inserted
-- one at a time, a short gap apart, and each insert is checked against SSL 360's
-- own log: if the track's strip has not registered within VERIFY seconds, its
-- 360 Link is replaced again (up to MAX_TRIES). Without the log (moved, locked,
-- different 360 version) inserts are still staggered, just not checked.

local r = reaper
local Core = {}

Core.IDENT     = "{5653543336304C73736C20333630206C"  -- VST3 ID of SSL 360 Link
Core.ADD_NAME  = "VST3:SSL 360 Link (SSL)"
Core.GAP       = 0.12   -- seconds between inserts
Core.VERIFY    = 4.0    -- seconds to wait for SSL 360 to register a strip
Core.MAX_TRIES = 3
Core.LOG_POLL  = 0.25   -- seconds between log reads

-- Match by the plugin's identity, not its display name (survives renamed instances)
function Core.is_link(tr, fx)
  local ok, ident = r.TrackFX_GetNamedConfigParm(tr, fx, "fx_ident")
  if ok and ident ~= "" then return ident:find(Core.IDENT, 1, true) ~= nil end
  local _, name = r.TrackFX_GetFXName(tr, fx, "")
  return name:find("SSL 360 Link (SSL)", 1, true) ~= nil
end

function Core.link_slots(tr, online_only)
  local slots = {}
  for fx = 0, r.TrackFX_GetCount(tr) - 1 do
    if Core.is_link(tr, fx) and not (online_only and r.TrackFX_GetOffline(tr, fx)) then
      slots[#slots + 1] = fx
    end
  end
  return slots
end

function Core.delete_slots(tr, slots)
  for i = #slots, 1, -1 do r.TrackFX_Delete(tr, slots[i]) end  -- high to low keeps indices valid
end

function Core.insert_fresh(tr, slots)
  table.sort(slots)
  for _, idx in ipairs(slots) do
    r.TrackFX_AddByName(tr, Core.ADD_NAME, false, -1000 - math.min(idx, r.TrackFX_GetCount(tr)))
  end
end

function Core.track_by_guid(g)
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if r.GetTrackGUID(t) == g then return t end
  end
end

----------------------------------------------------------------------------
-- SSL 360's log: every strip it accepts is logged with its DAW track number.
----------------------------------------------------------------------------
local function find_log()
  local base = os.getenv("LOCALAPPDATA")
  if not base then return nil end
  local dir = base .. "\\SSL\\SSL360\\LogFiles\\CurrentRun"
  local best
  local i = 0
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then break end
    if f:match("^SSL360Core_.*%.log$") and (not best or f > best) then best = f end
    i = i + 1
  end
  return best and (dir .. "\\" .. best) or nil
end

-- Returns a reader: call it to get the DAW track numbers SSL 360 has
-- registered since the last call (a set), or nil if the log is unavailable.
function Core.log_reader()
  local path, pos, last_find = nil, 0, -100
  local function open_at_end()
    path = find_log()
    if not path then return end
    local f = io.open(path, "rb")
    if not f then path = nil return end
    pos = f:seek("end")
    f:close()
  end
  open_at_end()
  return function()
    local now = r.time_precise()
    if not path then
      if now - last_find > 5 then last_find = now; open_at_end() end
      return nil
    end
    local f = io.open(path, "rb")
    if not f then path = nil return nil end
    local size = f:seek("end")
    if size < pos then pos = 0 end                 -- rotated or truncated
    f:seek("set", pos)
    local chunk = f:read("a") or ""
    f:close()
    -- keep a partial last line for next time
    local cut = chunk:match(".*()\n")
    if not cut then return {} end
    pos = pos + cut
    local seen = {}
    for daw in chunk:sub(1, cut):gmatch("initialised plugin:[^\n]-DAWPos=(%d+)") do
      seen[tonumber(daw)] = true
    end
    if now - last_find > 5 then                    -- 360 restarted: new log file
      last_find = now
      local p = find_log()
      if p and p ~= path then path = p; pos = 0 end
    end
    return seen
  end
end

----------------------------------------------------------------------------
-- Insert queue with verification.
--   q:add(tr, slots)    queue fresh 360 Links for these slots on a track
--   q:cancel(tr)        forget a track (e.g. it was hidden again)
--   q:tick(ok_to_insert) call every defer cycle; ok_to_insert(tr) may veto
--   q:busy()            anything still queued or awaiting confirmation
----------------------------------------------------------------------------
function Core.queue()
  local q = { list = {}, queued = {}, pending = {}, next_at = 0, last_poll = 0,
              read_log = Core.log_reader(), confirmed = 0, failed = 0 }

  function q:add(tr, slots, tries)
    local g = r.GetTrackGUID(tr)
    if self.queued[g] then return end
    self.queued[g] = true
    self.list[#self.list + 1] = { guid = g, slots = slots, tries = tries or 0 }
  end

  function q:cancel(tr)
    local g = r.GetTrackGUID(tr)
    self.pending[g] = nil
    if self.queued[g] then
      for i = #self.list, 1, -1 do
        if self.list[i].guid == g then table.remove(self.list, i) end
      end
      self.queued[g] = nil
    end
  end

  function q:busy() return #self.list > 0 or next(self.pending) ~= nil end

  function q:tick(ok_to_insert, on_inserted)
    local now = r.time_precise()

    -- one insert per GAP
    if #self.list > 0 and now >= self.next_at then
      local e = table.remove(self.list, 1)
      self.queued[e.guid] = nil
      local tr = Core.track_by_guid(e.guid)
      if tr and (not ok_to_insert or ok_to_insert(tr)) then
        Core.delete_slots(tr, Core.link_slots(tr))  -- a retry replaces the last attempt
        Core.insert_fresh(tr, e.slots)
        if on_inserted then on_inserted(tr) end
        e.tries = e.tries + 1
        e.at = now
        if self.read_log then self.pending[e.guid] = e end
        self.next_at = now + Core.GAP
      end
    end

    -- confirm against SSL 360's log
    if self.read_log and next(self.pending) and now - self.last_poll >= Core.LOG_POLL then
      self.last_poll = now
      local seen = self.read_log()
      if not seen then                       -- log unavailable: stop checking
        self.pending = {}
        self.read_log = nil
        return
      end
      for g, e in pairs(self.pending) do
        local tr = Core.track_by_guid(g)
        if not tr then
          self.pending[g] = nil
        else
          local num = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
          if seen[num] then
            self.pending[g] = nil
            self.confirmed = self.confirmed + 1
          elseif now - e.at >= Core.VERIFY then
            self.pending[g] = nil
            if e.tries < Core.MAX_TRIES then
              self:add(tr, e.slots, e.tries)
            else
              self.failed = self.failed + 1
            end
          end
        end
      end
    end
  end

  return q
end

return Core
