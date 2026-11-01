-- @noindex  (a development tool, not a package)
--[[
  TS_CV_ContainerMapProbe.lua -- how REAPER removes a container's
  parameter mapping. Select a track with a container (with a plugin in
  it) at the top level of its chain, and run this: the first such
  container is used. It adds a mapping (the first plugin
  inside, its first parameter), then tries each way of removing it and
  notes which one did. Nothing else is changed; the result goes to
  dev/containermap.txt and a message box.
--]]

local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local lines = {}
local function log(s) lines[#lines + 1] = s end
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.MB("Select a track first.", "Container map probe", 0) return end
local C
local function get(k) local ok, v = reaper.TrackFX_GetNamedConfigParm(tr, C, k); return ok, v end
for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local ok, n = reaper.TrackFX_GetNamedConfigParm(tr, i, "container_count")
  if ok and (tonumber(n) or 0) > 0 then C = i break end
end
if not C then reaper.MB("No container with a plugin in it at the top of this track's chain.", "Container map probe", 0) return end
local function count() return reaper.TrackFX_GetNumParams(tr, C) end
local function maps()
  local out = {}
  for i = 0, count() - 1 do
    local ok, fi = get(("param.%d.container_map.fx_index"):format(i))
    local _, fp = get(("param.%d.container_map.fx_parm"):format(i))
    if ok and fi ~= "" then out[#out + 1] = ("%d<-%s:%s"):format(i, fi, fp) end
  end
  return table.concat(out, " ")
end
log("==== " .. os.date("%Y-%m-%d %H:%M:%S") .. "  REAPER " .. reaper.GetAppVersion())
local okc, cc = get("container_count")
local _, cname = reaper.TrackFX_GetFXName(tr, C, "")
log(("container: slot %d (%s), container_count %s %s"):format(C, cname, tostring(okc), tostring(cc)))
log("params " .. count() .. ", mapped: " .. maps())

local function try(name, fn)
  local okA, idx = get("container_map.add.0.0")
  local i = tonumber(idx)
  log(("%s: add -> %s %s, params %d, mapped: %s"):format(name, tostring(okA), tostring(idx), count(), maps()))
  if not i then return end
  local r1, r2 = fn(i)
  log(("   %s(%d) returned %s %s -> params %d, mapped: %s"):format(name, i, tostring(r1), tostring(r2), count(), maps()))
end
try("get param.X.container_map.delete", function(i) return reaper.TrackFX_GetNamedConfigParm(tr, C, ("param.%d.container_map.delete"):format(i)) end)
try("set param.X.container_map.delete ''", function(i) return reaper.TrackFX_SetNamedConfigParm(tr, C, ("param.%d.container_map.delete"):format(i), "") end)
try("set param.X.container_map.delete '1'", function(i) return reaper.TrackFX_SetNamedConfigParm(tr, C, ("param.%d.container_map.delete"):format(i), "1") end)
try("get container_map.delete.X", function(i) return reaper.TrackFX_GetNamedConfigParm(tr, C, ("container_map.delete.%d"):format(i)) end)
try("set container_map.delete X", function(i) return reaper.TrackFX_SetNamedConfigParm(tr, C, "container_map.delete", tostring(i)) end)
log("end: params " .. count() .. ", mapped: " .. maps())

local f = io.open(own .. "containermap.txt", "a")
if f then f:write(table.concat(lines, "\n"), "\n"); f:close() end
reaper.MB(table.concat(lines, "\n"), "Container map probe", 0)
