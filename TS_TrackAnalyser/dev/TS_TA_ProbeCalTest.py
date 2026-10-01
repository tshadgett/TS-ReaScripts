# @noindex  (a development tool, not a package: never installed)
"""Usage: LOOSE_EEL=/path/to/loose_eel python3 TS_TA_ProbeCalTest.py <TS_TrackProbe.jsfx> [post] [pre]

Stop-time zero calibration, offline, against TS_TrackProbe's real code.

post: the POST probe with one tap around a synthetic compressor; the pre
      probe's schedule is played by the harness (phase + heartbeat in gmem,
      pink noise into the chain). Play 8 s, stop (calibrate), play 17 s.
pre:  the PRE probe alone; the harness plays a listening post probe and
      checks the phase clock, the noise level, and aborts.
"""
import subprocess, sys, numpy as np
from TS_TA_ProbeTapTest import sections, strip_comments, LOOSE
import os, tempfile

def prog_common(src):
    sec = sections(src)
    f = lambda c: strip_comments(c).replace('gmem[', 'GMB[')
    return f(sec['init']), f(sec['block']), f(sec['sample'])

HDR = '''
GMB = 4000000;
srate = 48000; samplesblock = 480;
function sliderchange(x) ( 0; );
function get_host_placement() ( 3; );
role = {role}; publish = 0; rel_ms = 400; vis_include = 0; vis_slot = -1;
tap_n = 1; tap_lag1 = 0; tap_lag2 = tap_lag3 = tap_lag4 = 0;
tap_rst1 = tap_rst2 = tap_rst3 = tap_rst4 = 0;
tap_gr1 = tap_gr2 = tap_gr3 = tap_gr4 = 0;
tap_cal1 = tap_cal2 = tap_cal3 = tap_cal4 = 0; tap_gen = 0; cal_arm = {arm};
play_state = 1;
'''

def post_prog(src, thr, ratio, mk, att=1, rel=300, touch_at=-1):
    init, block, sample = prog_common(src)
    return HDR.format(role=1, arm=0) + init + f'''
pk_b0=0.049922035; pk_b1=-0.095993537; pk_b2=0.050612699; pk_b3=-0.004408786;
pk_a1=-2.494956002; pk_a2=2.017265875; pk_a3=-0.522189400;
aa = exp(-1/(srate*{att}/1000)); ar = exp(-1/(srate*{rel}/1000)); env = 0;
SL = 0x60000 + 3*8; hbp = 0; ph = 0;
nsamp = 30 * srate; i = 0; gacc = 0; gcnt = 0; outpk = 0;
while (i < nsamp) (
  tb = i / srate;
  play_state = (tb < 8 || tb >= 13) ? 1 : 0;
  ph = (tb >= 9 && tb < 10) ? 1 : (tb >= 10 && tb < 11) ? 2 : (tb >= 11 && tb < 11.5) ? 3 : 0;
  hbp += 1; GMB[SL + 2] = hbp; GMB[SL + 1] = ph;
  GMB[73] = hbp;
  {touch_at} >= 0 && tb >= {touch_at} && tb < {touch_at} + 0.011 ? tap_rst1 = 7;
  {block}
  loop(samplesblock,
    tt = i / srate;
    w = rand(2) - 1;
    pn = pk_b0*w + pk_b1*w1 + pk_b2*w2 + pk_b3*w3 - pk_a1*p1 - pk_a2*p2 - pk_a3*p3;
    w3 = w2; w2 = w1; w1 = w; p3 = p2; p2 = p1; p1 = pn;
    phrase = (tt - 8*floor(tt/8)) < 5 ? 1 : 0.4;
    nt = abs(sin($pi*4*tt)); notes = 0.6 + 0.4*nt*nt*nt;
    bass = sin(2*$pi*55*tt);
    x = play_state ? (pn * 0.2 / 0.12 + bass*0.3) * phrase * notes : 0;
    // the pre probe's test noise
    (ph == 1 || ph == 2) ? (
      cw = rand(2) - 1;
      q0 = 0.99765 * q0 + cw * 0.0990460; q1 = 0.96300 * q1 + cw * 0.2965164;
      q2 = 0.57000 * q2 + cw * 1.0526913;
      x += (q0 + q1 + q2 + cw * 0.1848) * 10^((ph == 1 ? -60 : -50)/20) / 1.7276;
    );
    c = abs(x);
    env = c > env ? aa*env + (1-aa)*c : ar*env + (1-ar)*c;
    over = 20*log10(env + 0.000000000001) - ({thr});
    g = over > 0 ? -over*(1 - 1/{ratio}) : 0;
    y = x * 10^((g + {mk})/20);
    spl0 = y; spl1 = y; spl2 = x; spl3 = x; spl4 = y; spl5 = y;
    spl6=spl7=spl8=spl9=spl10=spl11=spl12=spl13=spl14=spl15=spl16=spl17=0;
    {sample}
    (ph > 0) ? outpk = max(outpk, abs(spl0));
    gacc += -g; gcnt += 1;
    gcnt >= tap_slice ? (
      printf("%f %f %f %f %f %d\\n", tt, gacc/gcnt, (TAP_BASE + TAP_S)[TS_LAST], tap_gr1, outpk, tap_cal1);
      gacc = 0; gcnt = 0;
    );
    i += 1;
  );
);
'''

def pre_prog(src, play_until=2.0, replay_at=-1, loud_at=-1):
    init, block, sample = prog_common(src)
    return HDR.format(role=0, arm=1) + init + f'''
SL = 0x60000 + 3*8; hbp = 0;
nsamp = 9 * srate; i = 0; acc = 0; cnt = 0;
while (i < nsamp) (
  tb = i / srate;
  play_state = (tb < {play_until} || ({replay_at} >= 0 && tb >= {replay_at})) ? 1 : 0;
  hbp += 1; GMB[SL + 3] = hbp; GMB[SL + 0] = 1; GMB[SL + 5] = 0; GMB[73] = hbp;
  {block}
  loop(samplesblock,
    tt = i / srate;
    xin = play_state ? 0.3*sin(2*$pi*200*tt) : 0;
    ({loud_at} >= 0 && tt >= {loud_at}) ? xin = 0.01*sin(2*$pi*300*tt);
    spl0 = xin; spl1 = xin;
    spl2=spl3=spl4=spl5=spl6=spl7=spl8=spl9=spl10=spl11=spl12=spl13=spl14=spl15=spl16=spl17=0;
    {sample}
    d = spl0 - xin; acc += d*d; cnt += 1;
    cnt >= 2400 ? ( printf("%f %d %f\\n", tt, GMB[SL+1], 10*log10(acc/cnt + 0.000000000000000000000000000001)); acc = 0; cnt = 0; );
    i += 1;
  );
);
'''

def run(prog):
    open(os.path.join(tempfile.gettempdir(), 'ts_probe_cal.eel'), 'w').write(prog)
    r = subprocess.run([LOOSE, os.path.join(tempfile.gettempdir(), 'ts_probe_cal.eel')], capture_output=True, text=True, timeout=900)
    lines = [l.split() for l in r.stdout.strip().split('\n') if l and l[0].isdigit()]
    if r.returncode != 0 or not lines:
        print(r.stdout[-3000:], r.stderr[-2000:]); raise SystemExit('eel failed')
    return np.array([[float(v) for v in l] for l in lines])

if __name__ == '__main__':
    src = open(sys.argv[1]).read()
    what = sys.argv[2:] or ['post', 'pre']
    if 'post' in what:
        for name, (thr, ratio, mk) in {'always -40/8 +12': (-40, 8, 12),
                                       'normal -24/4 +6': (-24, 4, 6),
                                       'low thr -55/4 +6': (-55, 4, 6)}.items():
            a = run(post_prog(src, thr, ratio, mk))
            t = a[:, 0]
            def seg(t0, t1):
                m = (t >= t0) & (t < t1)
                return a[m, 1].mean(), a[m, 2].mean()
            tr1, e1 = seg(2, 8); tr2, e2 = seg(15, 30)
            print(f"{name:18s} before stop: true {tr1:5.2f} est {e1:5.2f} | after: true {tr2:5.2f} est {e2:5.2f}"
                  f" | out peak while measuring {a[:, 4].max():.2e} | tap_cal {int(a[-1, 5])}")
    if 'pre' in what:
        for name, kw in {'plain': {}, 'replay mid-run': {'replay_at': 3.5}, 'input arrives': {'loud_at': 4.4}}.items():
            a = run(pre_prog(src, **kw))
            changes = []
            last = None
            for row in a:
                if row[1] != last: changes.append(f"{row[0]:.2f}s->{int(row[1])}"); last = row[1]
            lv1 = a[a[:, 1] == 1, 2]; lv2 = a[a[:, 1] == 2, 2]
            print(f"pre {name:15s} phases {' '.join(changes)} | noise A {lv1[1:].mean() if len(lv1)>1 else float('nan'):6.1f} dB"
                  f"  B {lv2[1:].mean() if len(lv2)>1 else float('nan'):6.1f} dB")
