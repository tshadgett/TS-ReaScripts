-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Recipes.lua -- your own knob recipes: looks built from parts and
  saved under a name, for the Style menu's "Your recipes".

  Kept in TS_ChannelView_Recipes.ini beside the layouts, one per line:
    <name>=<look>      (TS_CV_KnobParts.encode)
  A knob given one takes a copy of its look (Look<n>), so a layout carries
  its looks with it wherever it goes.
--]]

local KP = require("TS_CV_KnobParts")

local RC = {}
local FILE = "TS_ChannelView_Recipes.ini"
local dir = ""
local list = nil      -- { { name, look } ... } in the file's order

function RC.init(script_dir) dir = script_dir or ""; list = nil end

local function path() return dir .. FILE end

local function load()
  list = {}
  local fh = io.open(path(), "r")
  if not fh then return end
  for line in fh:lines() do
    local name, enc = line:match("^%s*([^=;#][^=]-)%s*=%s*(.-)%s*$")
    local look = enc and KP.decode(enc)
    if name and look then list[#list + 1] = { name = name, look = look } end
  end
  fh:close()
end

local function save()
  local fh = io.open(path(), "w")
  if not fh then return false end
  fh:write("; ChannelView: your knob recipes (name=look)\n")
  for _, r in ipairs(list or {}) do fh:write(r.name, "=", KP.encode(r.look) or "", "\n") end
  fh:close()
  return true
end

-- Your recipes, in the order saved.
function RC.list()
  if not list then load() end
  return list
end

-- Saves `look` as `name`, replacing one of that name. False when it can't
-- be written.
function RC.put(name, look)
  name = (name or ""):gsub("[=\r\n]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or type(look) ~= "table" then return false end
  RC.list()
  for _, r in ipairs(list) do
    if r.name == name then r.look = KP.copy(look); return save() end
  end
  list[#list + 1] = { name = name, look = KP.copy(look) }
  return save()
end

function RC.remove(name)
  RC.list()
  for i, r in ipairs(list) do
    if r.name == name then table.remove(list, i); return save() end
  end
  return false
end

return RC
