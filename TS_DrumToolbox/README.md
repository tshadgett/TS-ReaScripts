# TS_DrumToolbox

Drum editing for a whole multitrack kit at once, with REAPER's own tools:
take markers, items, envelopes, ReaGate, ReaEQ and RS5K. DrumToolbox finds
every hit on every drum, discounts the bleed between the kit's mics, and
then uses that **hit map** to align, quantise, level, gate, tone and
reinforce the drums. It works offline: the whole track is in view, so every
decision can be seen and changed, and a gate can open just before a hit.

## Standard and Pro

**DrumToolbox** is free (MIT) and on ReaPack: Setup, Detect, Align and
Quantise.

**DrumToolbox Pro** is an add-on to it, installed from its own ReaPack
link, which comes with Pro. It adds Level, Gate, Tone and Reinforce, and
the drum's panel in ChannelView Pro. Pro is on
[Ko-fi](https://ko-fi.com/tshadgett/shop).

The two must be the same version. Without Pro, its tabs show greyed with a
**PRO** mark; open one to see what it does.

A project made with Pro still plays in Standard where the work is
REAPER's own: levelling (clip gain or an envelope), ReaGate and its key,
ReaEQ, RS5K and a kit instrument. The gate, noise, Clean and Debleed
effects are Pro's own JSFX, so they're missing without it.

## The tabs

Across the top of the window, in the order you'd use them. The lanes show
the current drum's hits; the panel under them is the open tab's.

- **Setup**: every track's role in the kit: drum, second mic (a Kick Sub
  or Snare Bottom, which uses its drum's hits), bleed source, reference or
  ignore. Suggested from the tracks' names and folders; a role you set by
  hand always wins.
- **Detect**: every hit on the kit's drums, in the background, then the
  bleed check across the kit. Hits to look at are marked for review in
  the lanes.
- **Align**: second mics to their drum and the rest to the reference,
  measured on the hits. Moves the items, or the audio inside them.
- **Quantise**: the whole kit cut at the same points and moved to the
  grid, crossfaded, with the phase between the mics kept.
- **Level (Pro)**: every hit of a drum evened out, as clip gain or a pre-FX
  envelope, each hit adjustable by hand.
- **Gate (Pro)**: ReaGate opened by the hit map, so it never misses a quiet
  hit and spill never opens it. Duck under another drum's hits, Clean and
  Debleed.
- **Tone (Pro)**: the frequencies a drum rings on, found from its own hits,
  as EQ bands that act all the time, through each hit's attack or only
  after it.
- **Reinforce (Pro)**: noise, samples and a kit instrument under every
  hit, lined up with the drum.

A dot on a tab shows that stage is in use on the current drum (grey when
it's switched off); an amber dot on Detect means hits are waiting for
review.

## The hit map

The hits are kept on the drums' takes as take markers, so they move, trim
and split with the audio, and aligning the items keeps them right.

## Actions

Beside the window, in the Actions list:

- **TS_DrumToolbox_Detect**: sets up the kit and detects, without opening
  the window. The selected tracks, or the whole kit with none selected.
- **TS_DrumToolbox_Clear**: removes the hit map from the selected tracks
  (DrumToolbox's take markers only; your own stay). One undo step.

## In ChannelView (Pro)

With DrumToolbox Pro and **ChannelView Pro**, a drum's channel shows its
DrumToolbox panel beside the console panel, before the fader, and
DrumToolbox's own plugins are left out of the plugin row. Open the window
from ChannelView's main menu ▸ *DrumToolbox…*.

## Installing

**DrumToolbox:** Extensions ▸ ReaPack ▸ Browse packages ▸ *TS_DrumToolbox*
(the TS-ReaScripts repository) ▸ Install, then run it from the Actions
list. Needs the **ReaImGui** extension (ReaPack).

**DrumToolbox Pro:** Extensions ▸ ReaPack ▸ Import repositories ▸ paste the
link that comes with Pro, then Browse packages ▸ *TS_DrumToolbox Pro* ▸
Install, beside DrumToolbox. Keep the two on the same version: update them
together. If they differ, DrumToolbox says which and runs as Standard.
