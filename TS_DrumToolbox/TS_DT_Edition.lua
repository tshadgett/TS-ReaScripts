-- @noindex
-- Not a package of its own: installed by TS_DrumToolbox.lua's @provides.
--[[
  TS_DT_Edition.lua -- which DrumToolbox this is: Standard, or Standard
  with the Pro add-on.

  Pro is a package of its own (from its own ReaPack link) holding only its
  own files; TS_DT_Pro.lua is its marker. Standard runs without any of
  them, and turns Pro on when it finds them, of the same release as
  itself (one built for another release is left alone, and ED.mismatch
  says which it was).

  Pro's code goes back into Standard's scripts where it came from: a line
  "--@pro <file>:<n>" in a Standard script is replaced by part <n> of
  that Pro file ("--@part <n>" starts each part), and the script runs
  from the result (ED.self). Without Pro those lines are comments and the
  script runs as it is.

  ED.PRO          the Pro marker, or nil
  ED.mismatch     Pro's release, when it isn't this one
  ED.self(path)   the script at `path` with Pro's parts in, loaded (a
                  function), or nil when there's nothing to put in

  TS_DT_EDITION = "standard" (a global, set before this loads) makes it
  Standard whatever is installed: the tests, and trying Standard out.
--]]

local ED = {}

-- the release both editions are; Pro must be the same
ED.RELEASE = "1.0.0"

-- where ReaPack puts each edition's files, under REAPER's Scripts
ED.STANDARD_DIR = "TS-ReaScripts/TS_DrumToolbox/"
ED.PRO_DIR      = "TS-DrumToolbox-Pro/TS_DrumToolbox/"

-- How to get Pro (shown in Standard)
ED.PRO_URL = "https://github.com/tshadgett/TS-ReaScripts/tree/main/TS_DrumToolbox#standard-and-pro"

function ED.paths(own)
  local res = (reaper and reaper.GetResourcePath and reaper.GetResourcePath() or ".") .. "/Scripts/"
  return own .. "?.lua;" .. res .. ED.STANDARD_DIR .. "?.lua;" .. res .. ED.PRO_DIR .. "?.lua;"
end

do
  local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
  package.path = ED.paths(own) .. package.path
end

do
  local forced = rawget(_G, "TS_DT_EDITION") == "standard"
  local ok, pro = false, nil
  if not forced then ok, pro = pcall(require, "TS_DT_Pro") end
  if ok and type(pro) == "table" then
    if pro.RELEASE == ED.RELEASE then ED.PRO = pro
    else ED.mismatch = tostring(pro.RELEASE) end
  end
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

-- the folder Pro's files are in (beside its marker)
local function pro_dir()
  local p = package.searchpath("TS_DT_Pro", package.path)
  return p and p:match("^(.*[\\/])") or nil
end

-- a Pro file's parts: { [n] = text }
local parts_cache = {}
local function parts_of(file)
  if parts_cache[file] then return parts_cache[file] end
  local dir = pro_dir()
  local src = dir and read(dir .. file)
  if not src then return nil end
  local t, cur, buf = {}, nil, {}
  src = src:gsub("\r?\n$", "")
  for line in (src .. "\n"):gmatch("(.-)\r?\n") do
    local n = line:match("^%-%-@part (%d+)$")
    if n then
      if cur then t[cur] = table.concat(buf, "\n") end
      cur, buf = tonumber(n), {}
    elseif cur then
      buf[#buf + 1] = line
    end
  end
  if cur then t[cur] = table.concat(buf, "\n") end
  parts_cache[file] = t
  return t
end

-- `src` with each "--@pro <file>:<n>" line replaced by that part; nil if
-- it has none, or a part can't be found (then Standard runs as it is)
function ED.splice(src)
  if not src:find("\n%-%-@pro [%w_%.]+:%d+") then return nil end
  local out, missing = {}, false
  for line in (src .. "\n"):gmatch("(.-)\r?\n") do
    local file, n = line:match("^%-%-@pro ([%w_%.]+):(%d+)$")
    if file then
      local p = parts_of(file)
      local part = p and p[tonumber(n)]
      if not part then missing = true; break end
      out[#out + 1] = part
    else
      out[#out + 1] = line
    end
  end
  if missing then return nil end
  if out[#out] == "" then out[#out] = nil end
  return table.concat(out, "\n") .. "\n"
end

-- The script at `path`, with Pro's parts in, loaded: a function to run in
-- its place. nil without Pro, or when there's nothing to put in.
ED.spliced = {}
function ED.self(path)
  if not ED.PRO or ED.spliced[path] then return nil end   -- (the spliced run itself)
  local src = read(path)
  local spliced = src and ED.splice(src)
  if not spliced then return nil end
  local fn, err = load(spliced, "@" .. path)
  if not fn then error(err, 0) end
  ED.spliced[path] = true
  return fn
end

return ED
