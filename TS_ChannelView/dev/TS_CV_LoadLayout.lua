-- @noindex
--[[
  TS_CV_LoadLayout.lua -- dev tool: brings the layouts in dev/layout_in.ini
  into ChannelView's library (replacing any of the same name) and saves,
  so every ChannelView window reads them again.
--]]
local dev = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local root = dev:gsub("[\\/]dev[\\/]$", "") .. "/"
package.path = root .. "?.lua;" .. package.path
local ok, M = pcall(require, "TS_CV_Mappings")
if not ok then reaper.MB(tostring(M), "Load layout", 0) return end
M.init(root)
local entries, err = M.read_shared(dev .. "layout_in.ini")
if not entries then reaper.MB(tostring(err), "Load layout", 0) return end
local n = M.import(entries)
local saved, why = M.save()
if not saved then reaper.MB("Not saved: " .. tostring(why), "Load layout", 0) return end
reaper.SetExtState("TS_ChannelView", "dev_load_layout", ("%d at %s"):format(n, os.date("%H:%M:%S")), false)
