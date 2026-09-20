# Track Analyser

A docked, two-panel display for REAPER that shows what your processing is
*actually doing* to the selected track — measured from the audio, not
modelled from parameter values.

## Why it exists

Plugins with no GUI, or a cramped one — PSP InfiniStrip and Scheps Omni
Channel are the ones this was built against — leave you guessing what a
move did. Existing analysers show you the signal but not the *transfer*:
you get a spectrum, and you infer the rest.

This measures the transfer directly. A probe sits either side of your
processing, both take their FFT on the same block boundaries, and the
difference between their running power averages **is** the magnitude
response of whatever sits between them. No parameter map, no plugin
profile, no characterisation step.

Checked against stepped-tone models to **0.069 dB rms**.

Because it measures rather than models, it is automatically right about
things a parameter reader gets wrong: bypass, mute, insert slots,
saturation, and any plugin nobody has ever characterised. What it cannot
tell you is *which band did what* — it sees the sum.

## The two panels

**Panel 1 — spectrum and measured response.** The spectrum the probes are
publishing (pre, post, or both) with the measured magnitude response drawn
over it. The post probe does the subtraction itself, on a 256-point log
grid, and smooths it there, so the panel reads a finished curve rather than
building one every frame.

The response curve is **off until you turn it on**, in Settings ▸ SPECTRUM.
It is the most demanding thing here — it needs both probes publishing and
enough signal through them to average — so on a quiet or half-set-up track
it comes and goes. The spectrum underneath it does not, so that is what you
get by default.

**Panel 2 — waveform overlay and gain reduction.** One overlay, not two:
the untouched signal in grey behind, the processed one in front. A gain
reduction bar runs down the right.

Reduction is drawn **only** from the VST3 named route
(`GainReduction_dB`), where REAPER hands over decibels directly. Plugins
that instead expose reduction as an ordinary parameter — InfiniStrip among
them — need a measured law, a staleness test and a hold to be read at all,
and in practice every one of those was a source of error: a calibration
right for one module and wrong for another, a hold that plateaued, a
staleness test that never released. So the waveforms still show what those
plugins do, and the reduction trace does not pretend to.

One measurement settled it (2026-08-31, Pro-C 3 + InfiniStrip): the named
route answered on **all 159** samples, in decibels; the parameter path
returned a bare zero on **67%** of frames. REAPER also *formats* that same
parameter as `20*log10(v)`, which read "−0.44 dB" while the compressor was
pulling 26 — so read the value and apply the law, never the text.

## Collisions

A toggle and a track picker. Pick a comparison track and Panel 1 overlays
red where that track is masking the one you are looking at.

This is not a "both have energy here" overlay. It is a perceptual model:

1. **ERB bands.** Energy is summed in *power* into about 41 equivalent
   rectangular bands (Glasberg & Moore) from 20 Hz to 20 kHz. Comparing raw
   FFT bins says "both have energy at 3,412 Hz", which the ear does not
   care about.
2. **Spreading.** Masking spreads, and asymmetrically — Schroeder's
   function, roughly 4 dB down one Bark above the masker against 8 dB below,
   12 up against 28 down at two Bark. Upward spread is the dominant effect
   in a mix: it is why a loud bass eats the body of a vocal it shares no
   critical band with. Set the width to 0 and the model collapses to
   same-band-only, which is roughly what the commercial tools describe
   themselves as doing — so you can compare the two on the same material
   instead of arguing about it.
3. **A masking offset.** The spread excitation is not itself a threshold.
   Rather than infer tonality, this is one number you turn until the overlay
   agrees with your ears.
4. **An audibility gate** shaped by the threshold of hearing. Without it the
   top and bottom of the range flag permanently, because down there
   everything is below everything else and none of it is audible anyway.

**What it does not model.** Temporal masking — this compares running
averages, so a kick masking a vocal 20 ms later is invisible to it. And
absolute level: the gate is in dBFS with a hearing-threshold *shape*
applied, not in SPL, because nothing here knows your monitoring level.

## Installing

1. Put `TS_TrackProbe.jsfx` in `Effects/TS_TrackAnalyser/`.
2. Put the Lua files in `Scripts/TS_TrackAnalyser/`.
3. Actions ▸ Show action list ▸ New action ▸ Load ReaScript… ▸
   `TS_TrackAnalyser.lua`. Do the same for `TS_TA_InsertProbes.lua` and
   `TS_TA_QuietProbes.lua` if you want them on hand.

Needs the **ReaImGui** extension (ReaPack), v0.9 or newer.

## Setting a track up

Select a track with no probes and the panel says so in its header —
**No probes on track – Install?** Click it, say yes, and it sets the track
up. Settings ▸ PROBES has the same thing as a plain button, which also works
across several selected tracks at once.

Both run `TS_TA_InsertProbes.lua`, so the rules are the same wherever you
start from. The header asks for confirmation first, because that one sits
under your pointer while you are looking at something else; the Settings
button does not, because you went looking for it.

You can also run **`TS_TA_InsertProbes.lua`** from the action list.
It puts a `TS_TrackProbe` in the first slot and another in the last, sets each
one's Position so the panel knows which is which, and leaves both idle.

It only ever *adds*. Nothing is removed, reordered or replaced, and a track
that already has a pair — including one living inside a container, which is
what a baked track template gives you — is skipped rather than
double-probed.

It is quiet when it works: the FX chains change in front of you and there is
an undo point, so there is nothing to report. You hear from it only in the
two cases you cannot see — something failed, or every selected track was
already set up.

Then open the panel and select a track. That is the whole workflow.

### Why the probes are idle by default

The panel never inserts or removes anything at analysis time. You bake the
probe pair into your track templates and every track carries one, idle. An
idle probe does no FFT and writes no shared memory — it costs a branch per
sample. Fifty armed templates cost nothing.

The panel arms the pair on whichever track you select, by writing a single
parameter, and disarms it when you select away.

### Making them recede

`TS_TA_QuietProbes.lua` renames every probe it finds to a single dot, so the
pair stops competing for attention in the FX chain. Run it again to put the
real names back. Nothing is inserted, removed, reordered or bypassed — the
only thing that changes is the label REAPER shows.

## Files

| | |
|---|---|
| `TS_TrackAnalyser.lua` | the panel — run this one |
| `TS_TA_Chain.lua` | finds the probes and the strip on a track, through containers, and arms the right pair |
| `TS_TA_Strip.lua` | finds every plugin between the probes that reports reduction to the host, reads it, and says whether it is switched on |
| `TS_TA_Mask.lua` | the perceptual masking model. Pure arithmetic on two arrays of decibels — no REAPER calls, so it can be tested on synthetic spectra with known answers |
| `TS_TA_InsertProbes.lua` | puts a probe at each end of a chain |
| `TS_TA_QuietProbes.lua` | renames probes to a dot, and back |
| `TS_TrackProbe.jsfx` | the probe itself. Goes in `Effects/TS_TrackAnalyser/` |

`TS_TA_Chain`, `TS_TA_Strip` and `TS_TA_Mask` are libraries, not scripts to
run. The panel states what it needs from each by name, so a half-updated
install is reported as such before anything runs, rather than surfacing as
a nil call several hundred lines away.

## Diagnostics

There is no debug logging in a release build. `TS_TrackAnalyser.lua` has a
`DEBUG` flag near the top, off by default; turn it on and any frame that
takes longer than `FRAME_BUDGET` prints one line to the ReaScript console,
at most once every two seconds, split into time spent gathering state and
time spent drawing.

## Credits

Written by Tim Shadgett, with Claude.

No third-party code is reproduced here. The perceptual masking model is
built on published work — Glasberg & Moore's ERB-rate scale, Traunmüller's
Bark scale, and Schroeder's spreading function — implemented from the
literature rather than ported from an implementation.
