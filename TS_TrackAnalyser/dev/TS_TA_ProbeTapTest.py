# @noindex  (a development tool, not a package: never installed)
"""Offline test of TS_TrackProbe's per-plugin gain-reduction taps.

Runs the probe's real EEL2 code under loose_eel (the standalone EEL2
interpreter in Cockos' WDL: github.com/justinfrankel/WDL, WDL/eel2,
`make loose_eel NO_GFX=1`), as a POST probe with one tap, as a POST probe with taps,
against a synthetic plugin (EQ -> compressor -> make-up), and compare the tap
reading with the compressor's true gain reduction.

Usage: LOOSE_EEL=/path/to/loose_eel python3 TS_TA_ProbeTapTest.py ../../../Effects/TS_TrackAnalyser/TS_TrackProbe.jsfx [case...]
"""
import re, subprocess, sys, numpy as np

import os
LOOSE = os.environ.get('LOOSE_EEL', 'loose_eel')

def sections(src):
    out = {}; cur = None; buf = []
    for line in src.split('\n'):
        m = re.match(r'^@(\w+)', line)
        if m:
            if cur: out[cur] = '\n'.join(buf)
            cur = m.group(1); buf = []
            continue
        if cur: buf.append(line)
    if cur: out[cur] = '\n'.join(buf)
    return out

def strip_comments(code):
    return re.sub(r'//[^\n]*', '', code)

CASES = {
    #          thr   ratio att  rel  makeup  eq_lo eq_hi  lag  mix
    'comp':    (-24, 4, 5, 120, 6, 0, 0, 0, 1.0),
    'eqcomp':  (-24, 4, 5, 120, 6, 6, -5, 0, 1.0),
    'latency': (-24, 4, 5, 120, 6, 0, 0, 480, 1.0),
    'gentle':  (-18, 2, 20, 200, 0, 0, 0, 0, 1.0),
    'always':  (-40, 8, 1, 300, 12, 0, 0, 0, 1.0),
}

def build(probe_src, case, secs=24, hb=True):
    thr, ratio, att, rel, mk, eqlo, eqhi, lag, mix = CASES[case]
    sec = sections(probe_src)
    init = strip_comments(sec['init'])
    block = strip_comments(sec['block'])
    sample = strip_comments(sec['sample'])
    fix = lambda c: c.replace('gmem[', 'GMB[')
    prog = f'''
GMB = 4000000;
srate = 48000; samplesblock = 480;
function sliderchange(x) ( 0; );
function get_host_placement() ( 3; );
play_state = 1; tap_gen = 0; cal_arm = 0;
role = 1; publish = 0; rel_ms = 400; vis_include = 0; vis_slot = -1;
tap_n = 1; tap_lag1 = {lag}; tap_lag2 = 0; tap_lag3 = 0; tap_lag4 = 0;
tap_rst1 = 0; tap_rst2 = 0; tap_rst3 = 0; tap_rst4 = 0;
tap_gr1 = tap_gr2 = tap_gr3 = tap_gr4 = 0;
{fix(init)}
// ---------------- the test plugin
function peq(x, f0, gdb, q) instance(b0,b1,b2,a1,a2,z1,z2,init) local(A,w0,al,a0,y) (
  !init ? ( A = 10^(gdb/40); w0 = 2*$pi*f0/srate; al = sin(w0)/(2*q);
    a0 = 1 + al/A; b0 = (1+al*A)/a0; b1 = -2*cos(w0)/a0; b2 = (1-al*A)/a0;
    a1 = -2*cos(w0)/a0; a2 = (1-al/A)/a0; init = 1; );
  y = b0*x + z1; z1 = b1*x - a1*y + z2; z2 = b2*x - a2*y; y;
);
pk_b0=0.049922035; pk_b1=-0.095993537; pk_b2=0.050612699; pk_b3=-0.004408786;
pk_a1=-2.494956002; pk_a2=2.017265875; pk_a3=-0.522189400;
aa = exp(-1/(srate*{att}/1000)); ar = exp(-1/(srate*{rel}/1000)); env = 0;
DL = 3000000; dlp = 0;  // latency of the test plugin
nsamp = {secs} * srate; i = 0; gacc = 0; gcnt = 0; col = 0;
while (i < nsamp) (
  {"hb += 1; GMB[73] = hb;" if hb else ""}
  {fix(block)}
  loop(samplesblock,
    tt = i / srate;
    w = rand(2) - 1;
    pn = pk_b0*w + pk_b1*w1 + pk_b2*w2 + pk_b3*w3 - pk_a1*p1 - pk_a2*p2 - pk_a3*p3;
    w3 = w2; w2 = w1; w1 = w; p3 = p2; p2 = p1; p1 = pn;
    phrase = (tt - 8*floor(tt/8)) < 5 ? 1 : 0.15;
    nt = abs(sin($pi*4*tt)); notes = 0.35 + 0.65*nt*nt*nt;
    bass = sin(2*$pi*55*tt) * (sin(2*$pi*0.5*tt) > 0 ? 1 : 0);
    x = (pn * 0.2 / 0.12 + bass*0.3) * phrase * notes;
    // plugin: EQ -> comp -> makeup, then latency
    e = x;
    {eqlo} != 0 ? e = eqa.peq(e, 100, {eqlo}, 1);
    {eqhi} != 0 ? e = eqb.peq(e, 6000, {eqhi}, 0.7);
    c = abs(e);
    env = c > env ? aa*env + (1-aa)*c : ar*env + (1-ar)*c;
    over = 20*log10(env + 0.000000000001) - ({thr});
    g = over > 0 ? -over*(1 - 1/{ratio}) : 0;
    y = e * 10^((g + {mk})/20);
    y = {mix}*y + (1-{mix})*x;
    {lag} > 0 ? ( DL[dlp] = y; dlp2 = dlp - {lag}; dlp2 < 0 ? dlp2 += {lag}+1; y = DL[dlp2]; dlp += 1; dlp > {lag} ? dlp = 0; );
    // the plugin's own delay applies to its reduction too
    GL = 2000000; GL[dlg] = -g; dlg2 = dlg - {lag}; dlg2 < 0 ? dlg2 += {lag}+1; gtrue = {lag} > 0 ? GL[dlg2] : -g; dlg += 1; dlg > {lag} ? dlg = 0;
    spl0 = y; spl1 = y;
    spl2 = x; spl3 = x; spl4 = y; spl5 = y;
    spl6=spl7=spl8=spl9=spl10=spl11=spl12=spl13=spl14=spl15=spl16=spl17=0;
    {fix(sample)}
    gacc += gtrue; gcnt += 1;
    gcnt >= tap_slice ? (
      printf("%f %f %f\\n", gacc/gcnt, (TAP_BASE + TAP_S)[TS_LAST], tap_gr1);
      gacc = 0; gcnt = 0;
    );
    i += 1;
  );
);
'''
    return prog

def run(probe_src, case, hb=True):
    prog = build(probe_src, case, hb=hb)
    open('_tap_test.eel', 'w').write(prog)
    r = subprocess.run([LOOSE, '_tap_test.eel'], capture_output=True, text=True, timeout=900)
    if r.returncode != 0 or not r.stdout.strip():
        print(r.stdout[-2000:], r.stderr[-2000:]); raise SystemExit('eel failed')
    a = np.array([[float(v) for v in l.split()] for l in r.stdout.strip().split('\n') if len(l.split()) == 3])
    return a

if __name__ == '__main__':
    src = open(sys.argv[1]).read()
    cases = sys.argv[2:] or list(CASES)
    for c in cases:
        a = run(src, c)
        k0 = int(2 * 500)
        t, e, d = a[k0:, 0], a[k0:, 1], a[k0:, 2]
        err = np.sqrt(np.mean((t - e) ** 2)); corr = np.corrcoef(t, e)[0, 1]
        print(f"{c:9s} cols {len(a):6d} | true mean {t.mean():5.2f} max {t.max():5.2f} | est mean {e.mean():5.2f} max {e.max():5.2f} | rms {err:4.2f} corr {corr:4.2f} | slider max {d.max():5.2f}")
