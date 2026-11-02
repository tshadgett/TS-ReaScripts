# @noindex  (a development tool, not a package: never installed)
"""Offline check of TS_TrackProbe's stereo tap (STEREO, ONE TAP): its
correlation, mid and side, and the scope it writes, for a mono, an
inverted, an independent, a half-related and a one-sided signal.

Usage: LOOSE_EEL=/path/to/loose_eel python3 TS_TA_ProbeStereoTest.py path/to/TS_TrackProbe.jsfx
Expect: mono +1 (side silent), anti -1 (mid silent), indep about 0,
half about +0.45, left 0; the scope written by the named track (5); the
levels per channel (LEVELS PER CHANNEL) the right silent for "left".
"""
import sys, subprocess, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import TS_TA_ProbeTapTest as T
src = open(sys.argv[1]).read()
sec = T.sections(src)
fix = lambda c: c.replace('gmem[', 'GMB[').replace('get_host_placement(pl_pos, pl_fl)', '(pl_pos = 5; pl_fl = 0; 3)')
init, block, sample = (T.strip_comments(sec[k]) for k in ('init', 'block', 'sample'))
CASES = {'mono': 'L = w; R = w;', 'anti': 'L = w; R = -w;', 'indep': 'L = w; R = rand(2) - 1;',
         'half': 'L = w; R = 0.5 * w + 0.5 * (rand(2) - 1);', 'left': 'L = w; R = 0;'}
for name, sig in CASES.items():
    prog = f'''
GMB = 4000000;
srate = 48000; samplesblock = 480;
function spl(i) ( i == 0 ? spl0 : i == 1 ? spl1 : i == 2 ? spl2 : i == 3 ? spl3 : i == 4 ? spl4 : i == 5 ? spl5 : 0; );
function get_host_placement() ( 3; );
play_state = 1;
{fix(init)}
PBK = GMB + 0x100000 + 4 * 128;
PBK[1] = 6; PBK[8] = 1; PBK[19] = 1; PBK[25] = 1;
GMB[77] = 5;
nsamp = 2 * srate; i = 0;
while (i < nsamp) (
  hb += 1; GMB[73] = hb;
  {fix(block)}
  loop(samplesblock,
    w = (rand(2) - 1) * 0.5;
    {sig}
    spl0 = L; spl1 = R; spl2 = L; spl3 = R; spl4 = L; spl5 = R;
    lastL = L; lastR = R;
    {fix(sample)}
    i += 1;
  );
);
{fix(block)}
LV = GMB + 0x350000 + 4 * 64;
printf("%s corr %.3f mid %.1f side %.1f cap %d | scope seq %d n %d writer %d | outrms %.1f | per channel pk in %.1f %.1f out %.1f %.1f rms out %.1f %.1f\\n",
  "{name}", PBK[122], PBK[123], PBK[124], PBK[125], GMB[0x340000], GMB[0x340001], GMB[0x340002],
  PBK[84], LV[0], LV[1], LV[2], LV[3], LV[6], LV[7]);
'''
    open('_st.eel', 'w').write(prog)
    r = subprocess.run([T.LOOSE, '_st.eel'], capture_output=True, text=True, timeout=300)
    print(r.stdout.strip()[-400:], r.stderr.strip()[-400:])
