-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Startup.lua -- the "Run when REAPER starts" option.

  __startup.lua is the one file this project touches that can break
  things OTHER than this project: everything else you auto-start runs
  from it, so a mangled edit costs those too. Three rules follow, and
  they are the reason this is a module rather than four lines in the menu
  handler:

    1  A BACKUP FIRST, every time, to __startup.lua.bak.
    2  THE RESULT IS COMPILED BEFORE IT IS SAVED. load() on the new text
       catches a mangled edit while it is still a string in memory. A
       startup file that does not parse is never written.
    3  LINES THIS SCRIPT DID NOT WRITE ARE NOT TOUCHED. Our block is
       fenced with markers and only that is ever removed. If the command
       id turns up OUTSIDE the fence -- added by hand, which is how most
       people get there first -- we say so and leave it alone rather than
       editing somebody else's line.

  The text surgery is separated from the file handling on purpose: the
  three functions that decide what the file should say are pure, take a
  string and return a string, and are the part the tests exercise.

  Ported from Track_Analyser/TA_Panel.lua, which does the same job.
--]]

local SU = {}

local SEP = package.config:sub(1, 1)

SU.BEGIN = "-- >>> ChannelView (added by TS_ChannelView.lua)"
SU.END   = "-- <<< ChannelView"

-- The markers are full of Lua pattern metacharacters -- ( ) - . > -- so
-- they cannot be used as patterns raw. Matching them unescaped is what
-- made Track Analyser report a block it had just written as somebody
-- else's hand-edit.
local function esc(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local BEGIN_PAT, END_PAT = esc(SU.BEGIN), esc(SU.END)

-- ---------------------------------------------------------------------
-- the text surgery (pure)
-- ---------------------------------------------------------------------

-- "none" | "ours" | "manual"
function SU.classify(txt, cmd)
  if not txt or not cmd or cmd == "" then return "none" end
  local fenced = txt:match(BEGIN_PAT .. "(.-)" .. END_PAT)
  if fenced and fenced:find(cmd, 1, true) then return "ours" end
  if txt:find(cmd, 1, true) then return "manual" end
  return "none"
end

-- Appends our fenced block. Never twice: two Main_OnCommand calls for the
-- same script start two copies of the window, both writing to the same
-- parameters.
function SU.fenced_add(txt, cmd)
  txt = txt or "-- REAPER startup script\n"
  if SU.classify(txt, cmd) ~= "none" then return txt end
  if not txt:match("\n$") then txt = txt .. "\n" end
  return txt .. ("\n%s\nlocal channelview_cmd = '%s'\n" ..
                 "reaper.Main_OnCommand(reaper.NamedCommandLookup(channelview_cmd), 0)\n%s\n")
    :format(SU.BEGIN, cmd, SU.END)
end

-- Removes ONLY the fenced block, and leaves the file ending in exactly
-- one newline the way it started. A hand-written line mentioning the same
-- command id is deliberately left where it is.
function SU.fenced_remove(txt)
  if not txt then return nil end
  local out = txt:gsub("\n*" .. BEGIN_PAT .. ".-" .. END_PAT .. "\n*", "\n")
  return (out:gsub("%s*$", "\n"))
end

-- ---------------------------------------------------------------------
-- this script's own command id
-- ---------------------------------------------------------------------

-- Asked for rather than written down. get_action_context gives the
-- numeric id of the running instance; ReverseNamedCommandLookup turns
-- that into the "_RS..." name, which is the stable one and the one
-- __startup.lua needs. A hardcoded id would tie this to one machine's
-- action list and write a dead line into __startup.lua anywhere else.
local my_cmd = nil

function SU.init()
  local _, _, _, num = reaper.get_action_context()
  if num and reaper.ReverseNamedCommandLookup then
    local nm = reaper.ReverseNamedCommandLookup(num)
    if nm and nm ~= "" then
      my_cmd = (nm:sub(1, 1) == "_") and nm or ("_" .. nm)
    end
  end
  return my_cmd
end

-- ---------------------------------------------------------------------
-- the file
-- ---------------------------------------------------------------------

function SU.path()
  return reaper.GetResourcePath() .. SEP .. "Scripts" .. SEP .. "__startup.lua"
end

local function read_all(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local t = f:read("*a"); f:close(); return t
end

-- "none" | "ours" | "manual" | "nocmd", plus a note when there is
-- something the user needs to know.
local state = { value = "none", checked = false, note = nil }

function SU.state()   return state.value, state.note end
function SU.checked() return state.checked end
function SU.forget()  state.checked = false end
function SU.on()      return state.value == "ours" or state.value == "manual" end

-- Read from the file rather than remembered in ExtState: the file is the
-- truth, and a cached boolean is just something that can disagree with it
-- after a hand edit.
function SU.scan()
  state.checked = true
  state.note = nil
  if not my_cmd then
    state.value = "nocmd"
    state.note = "REAPER hasn't given this script an action id yet \u{2014} " ..
                 "add it to the Action List once and this works."
    return state.value
  end
  local txt = read_all(SU.path())
  state.value = SU.classify(txt, my_cmd)
  if state.value == "manual" then
    state.note = "already in __startup.lua, on a line this window did not " ..
                 "write \u{2014} remove it by hand if you want it gone."
  end
  return state.value
end

-- Writes `txt` only if it compiles, and only after the backup is safely
-- on disk. Returns true, or false plus why.
local function write_checked(txt)
  local chunk, err = load(txt, "__startup.lua")
  if not chunk then
    return false, "the result would not compile: " .. tostring(err)
  end
  local path = SU.path()
  local cur = read_all(path)
  if cur then
    local bf = io.open(path .. ".bak", "wb")
    if not bf then
      return false, "could not write the backup, so nothing was changed"
    end
    bf:write(cur); bf:close()
  end
  local f = io.open(path, "wb")
  if not f then return false, "could not open __startup.lua for writing" end
  f:write(txt); f:close()
  return true
end

function SU.add()
  if not my_cmd then return false, "no action id for this script" end
  SU.scan()
  if SU.on() then return true end
  local ok, why = write_checked(SU.fenced_add(read_all(SU.path()), my_cmd))
  SU.scan()
  return ok, why
end

function SU.remove()
  local txt = read_all(SU.path())
  if not txt then SU.scan(); return true end
  local ok, why = write_checked(SU.fenced_remove(txt))
  SU.scan()
  return ok, why
end

return SU
