-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Inputs.lua -- a track's record input, record mode and input FX.

  The record input is one number, I_RECINPUT:
    < 0              no input
    bit 4096 set     MIDI: low 5 bits the channel (0 = all, 1-16), the
                     next 6 bits the device (63 = all inputs, 62 = the
                     virtual MIDI keyboard)
    otherwise        audio: low 10 bits the first input channel (512 and
                     up is ReaRoute / loopback), with 1024 set for a
                     stereo pair and 2048 for multichannel (as many
                     channels as the track has)

  The input menu is the same shape as REAPER's own: None, Mono, Stereo,
  MIDI, and the record mode underneath. Choosing applies to the whole
  selection when the track is part of it, as the rest of the strip does.

  Input FX: the button opens the track's input FX chain -- or, on the
  master, the monitoring FX chain, which is what REAPER keeps in the
  master's input FX slot.
--]]

local G = require("TS_CV_Gang")

local IN = {}
local ImGui

function IN.attach(imgui) ImGui = imgui end

IN.MIDI    = 4096
IN.STEREO  = 1024
IN.MULTI   = 2048
IN.ALL_DEV = 63
IN.VKB     = 62

-- ---------------------------------------------------------------------
-- encoding (pure)
-- ---------------------------------------------------------------------

function IN.audio(first, stereo)
  return (first or 0) | (stereo and IN.STEREO or 0)
end

function IN.midi(dev, ch)
  return IN.MIDI | ((dev or IN.ALL_DEV) << 5) | (ch or 0)
end

-- I_RECINPUT -> { kind = "none" | "audio" | "midi", ... }
function IN.decode(v)
  v = math.floor(v or -1)
  if v < 0 then return { kind = "none" } end
  if (v & IN.MIDI) ~= 0 then
    return { kind = "midi", dev = (v >> 5) & 63, ch = v & 31 }
  end
  return { kind = "audio", first = v & 1023,
           stereo = (v & IN.STEREO) ~= 0, multi = (v & IN.MULTI) ~= 0 }
end

-- The short text a strip shows for an input. `name(i)` gives an audio
-- input channel's name, `midi_name(d)` a MIDI device's; both may be nil.
function IN.label(v, name, midi_name)
  local d = IN.decode(v)
  if d.kind == "none" then return "No input" end
  if d.kind == "midi" then
    local dev = (d.dev == IN.ALL_DEV) and "All MIDI"
             or (d.dev == IN.VKB) and "VKB"
             or (midi_name and midi_name(d.dev)) or ("MIDI " .. (d.dev + 1))
    return dev .. ((d.ch == 0) and "" or (" ch " .. d.ch))
  end
  local function nm(i) return (name and name(i)) or ("In " .. (i + 1)) end
  if d.multi then return nm(d.first) .. "+" end
  if d.stereo then return nm(d.first) .. "/" .. nm(d.first + 1) end
  return nm(d.first)
end

-- I_RECMODE values, in the order REAPER's own menu lists them.
IN.MODES = {
  { 0, "Input (audio or MIDI)" },
  { 7, "MIDI overdub" },
  { 8, "MIDI replace" },
  { 1, "Output (stereo)" },
  { 3, "Output (stereo, latency compensated)" },
  { 5, "Output (mono)" },
  { 6, "Output (mono, latency compensated)" },
  { 4, "Output (MIDI)" },
  { 2, "Disabled (input monitoring only)" },
}

-- ---------------------------------------------------------------------
-- REAPER side
-- ---------------------------------------------------------------------

function IN.input_name(i)
  local n = reaper.GetInputChannelName(i)
  if n and n ~= "" then return n end
  return nil
end

function IN.midi_name(dev)
  local ok, n = reaper.GetMIDIInputName(dev, "")
  if ok and n and n ~= "" then return n end
  return nil
end

function IN.current(track)
  return reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1
end

function IN.text(track)
  return IN.label(IN.current(track), IN.input_name, IN.midi_name)
end

local function set_input(track, v)
  reaper.Undo_BeginBlock()
  G.set(track, "I_RECINPUT", v)
  reaper.Undo_EndBlock("ChannelView: set record input", -1)
end

local function set_mode(track, m)
  reaper.Undo_BeginBlock()
  G.set(track, "I_RECMODE", m)
  reaper.Undo_EndBlock("ChannelView: set record mode", -1)
end

local function channel_items(ctx, track, cur, dev)
  local d = IN.decode(cur)
  local on_dev = d.kind == "midi" and d.dev == dev
  if ImGui.MenuItem(ctx, "All channels", nil, on_dev and d.ch == 0) then
    set_input(track, IN.midi(dev, 0))
  end
  for ch = 1, 16 do
    if ImGui.MenuItem(ctx, "Channel " .. ch, nil, on_dev and d.ch == ch) then
      set_input(track, IN.midi(dev, ch))
    end
  end
end

-- The menu body; call between BeginPopup and EndPopup.
function IN.menu(ctx, track)
  local cur = IN.current(track)
  local d = IN.decode(cur)

  if ImGui.MenuItem(ctx, "No input", nil, d.kind == "none") then
    set_input(track, -1)
  end

  local n_in = reaper.GetNumAudioInputs() or 0
  if ImGui.BeginMenu(ctx, "Mono", n_in > 0) then
    for i = 0, n_in - 1 do
      local on = d.kind == "audio" and not d.stereo and not d.multi and d.first == i
      if ImGui.MenuItem(ctx, (IN.input_name(i) or ("Input " .. (i + 1))) .. "##m" .. i,
          nil, on) then
        set_input(track, IN.audio(i, false))
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Stereo", n_in > 1) then
    for i = 0, n_in - 2 do
      local on = d.kind == "audio" and d.stereo and d.first == i
      local a = IN.input_name(i) or ("Input " .. (i + 1))
      local b = IN.input_name(i + 1) or ("Input " .. (i + 2))
      if ImGui.MenuItem(ctx, a .. " / " .. b .. "##s" .. i, nil, on) then
        set_input(track, IN.audio(i, true))
      end
    end
    ImGui.EndMenu(ctx)
  end

  if ImGui.BeginMenu(ctx, "MIDI") then
    if ImGui.BeginMenu(ctx, "All MIDI inputs") then
      channel_items(ctx, track, cur, IN.ALL_DEV)
      ImGui.EndMenu(ctx)
    end
    for dev = 0, (reaper.GetMaxMidiInputs and reaper.GetMaxMidiInputs() or 64) - 1 do
      if dev ~= IN.VKB and dev ~= IN.ALL_DEV then
        local nm = IN.midi_name(dev)
        if nm and ImGui.BeginMenu(ctx, nm .. "##md" .. dev) then
          channel_items(ctx, track, cur, dev)
          ImGui.EndMenu(ctx)
        end
      end
    end
    if ImGui.BeginMenu(ctx, "Virtual MIDI keyboard") then
      channel_items(ctx, track, cur, IN.VKB)
      ImGui.EndMenu(ctx)
    end
    ImGui.EndMenu(ctx)
  end

  ImGui.Separator(ctx)
  if ImGui.BeginMenu(ctx, "Record mode") then
    local m = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_RECMODE") or 0)
    for _, e in ipairs(IN.MODES) do
      if ImGui.MenuItem(ctx, e[2], nil, m == e[1]) then set_mode(track, e[1]) end
    end
    ImGui.EndMenu(ctx)
  end
end

-- Input FX: how many, and whether every one of them is bypassed.
function IN.fx_state(track)
  local n = reaper.TrackFX_GetRecCount(track) or 0
  local any_on = false
  for i = 0, n - 1 do
    if reaper.TrackFX_GetEnabled(track, 0x1000000 + i) then any_on = true break end
  end
  return n, any_on
end

-- Opens the input FX chain (the monitoring FX chain on the master)
-- showing what's in it. Only for a chain that has something in it:
-- REAPER answers an EMPTY chain being opened with its Add FX browser,
-- which is what adding is for, not showing. TrackFX_Show is asked first;
-- if the chain still isn't up, REAPER's own "view input FX chain" action
-- is run for the track (made the last touched one first, which that
-- action needs). Returns false when there was nothing to show.
function IN.open_fx(track)
  if not track or (reaper.TrackFX_GetRecCount(track) or 0) == 0 then return false end
  local master = track == reaper.GetMasterTrack(0)
  reaper.TrackFX_Show(track, 0x1000000, 1)
  if reaper.TrackFX_GetRecChainVisible
     and reaper.TrackFX_GetRecChainVisible(track) ~= -1 then
    return true
  end
  if master then
    reaper.Main_OnCommand(41882, 0)        -- View: Show monitoring FX chain
  else
    reaper.SetOnlyTrackSelected(track)
    reaper.Main_OnCommand(40914, 0)        -- Track: Set first selected track as last touched
    reaper.Main_OnCommand(40844, 0)        -- Track: View input FX chain for current/last touched track
  end
  return true
end

return IN
