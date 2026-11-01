-- @noindex
-- dev tool, not released: the selected track's FX tree (paths, names,
-- guids, pins, container channels) and its compare record -> dev/chain.txt
local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = script_dir:gsub("dev[\\/]$", "") .. "?.lua;" .. package.path
local T = require("TS_CV_FXTree")
local tr = reaper.GetSelectedTrack(0, 0)
local out = {}
local function say(s) out[#out + 1] = s end
if not tr then say("no track selected") else
  local _, tn = reaper.GetTrackName(tr)
  say("track: " .. tn .. "  nch " .. reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN"))
  local function pins(addr, isout)
    local _, nin, nout = reaper.TrackFX_GetIOSize(tr, addr)
    local n = isout == 1 and nout or nin
    local t = {}
    for p = 0, (n or 0) - 1 do
      local lo = reaper.TrackFX_GetPinMappings(tr, addr, isout, p)
      t[#t + 1] = tostring(math.floor(lo or 0))
    end
    return table.concat(t, ",")
  end
  local function walk(nodes, ind)
    for _, n in ipairs(nodes or {}) do
      local _, ren = reaper.TrackFX_GetNamedConfigParm(tr, n.addr, "renamed_name")
      local line = ("%s%s %s %s par=%s addr=%s in=[%s] out=[%s]"):format(ind, table.concat(n.path, "."),
        n.name, n.guid, tostring(n.parallel), tostring(n.addr), pins(n.addr, 0), pins(n.addr, 1))
      if n.kind == "container" then
        local _, nch = reaper.TrackFX_GetNamedConfigParm(tr, n.addr, "container_nch")
        local _, nin = reaper.TrackFX_GetNamedConfigParm(tr, n.addr, "container_nch_in")
        line = line .. (" nch=%s nch_in=%s name=%s"):format(nch, nin, ren)
      end
      say(line)
      if n.children then walk(n.children, ind .. "  ") end
    end
  end
  walk(T.collect(tr).tree, "")
  local _, rec = reaper.GetProjExtState(0, "TS_ChannelView", "compare:" .. reaper.GetTrackGUID(tr))
  say("compare: " .. rec)
end
local f = io.open(script_dir .. "chain.txt", "w")
if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
