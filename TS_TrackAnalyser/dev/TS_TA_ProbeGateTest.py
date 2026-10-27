# @noindex  (a development tool, not a package: never installed)
"""Offline checks of TS_TrackProbe's taps beyond their accuracy (that's
TS_TA_ProbeTapTest / TS_TA_ProbeCalTest, which this borrows from):

  eight  eight plugins measured at once: every tap reads (taps 5..8 at
         their own place in the block, 97..), their waveforms are written
         (taps 5..8 at TW_BASE2), and what eight cost
  gate   ONLY THE TRACKS ON SCREEN: with a reader naming tracks (gmem[76]
         moving), a track not named reads 0 and does no work; named again,
         it reads right at once. The zero is measured at a stop while the
         track isn't named, and used once it is.
  rates  the taps at 44.1, 96 and 192 kHz (THE TEN BANDS, BY FFT scales
         its sizes with the rate)
  cost   what one measuring tap costs, as a share of one core, against
         the test harness alone (loose_eel runs the same EEL2 compiler as
         REAPER)

Usage: LOOSE_EEL=/path/to/loose_eel python3 TS_TA_ProbeGateTest.py path/to/TS_TrackProbe.jsfx [eight|gate|rates|cost ...]
"""
import os, sys, subprocess, time, tempfile
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import TS_TA_ProbeTapTest as T
import TS_TA_ProbeCalTest as C

TMP = os.path.join(tempfile.gettempdir(), 'ts_probe_gate.eel')

def eel(prog, cols):
    open(TMP, 'w').write(prog)
    r = subprocess.run([T.LOOSE, TMP], capture_output=True, text=True, timeout=900)
    rows = [l.split() for l in r.stdout.strip().split('\n') if len(l.split()) == cols]
    if r.returncode != 0 or not rows:
        print(r.stdout[-2000:], r.stderr[-2000:]); raise SystemExit('eel failed')
    return np.array([[float(v) for v in l] for l in rows])

BEAT = "hb += 1; GMB[73] = hb;"
PRINT = 'printf("%f %f %f\\n", gacc/gcnt, (TAP_BASE + TAP_S)[TS_LAST], PBK[64]);'

def gate(src):
    prog = T.build(src, 'comp', secs=24)
    prog = prog.replace(BEAT, BEAT + " GMB[76] = hb; (i < 8*srate || i >= 16*srate) ? PBK[7] = hb;", 1)
    prog = prog.replace(PRINT, 'printf("%f %f %f %f\\n", i/srate, gacc/gcnt, (TAP_BASE + TAP_S)[TS_LAST], PBK[64]);')
    a = eel(prog, 4)
    for lo, hi, name in ((2, 8, 'shown'), (9.5, 16, 'not shown'), (16.5, 24, 'shown again')):
        m = (a[:, 0] >= lo) & (a[:, 0] < hi)
        print(f"gate  {name:12s} true mean {a[m, 1].mean():5.2f} | reading mean {a[m, 3].mean():5.2f} max {a[m, 3].max():5.2f}")
    for name, (thr, ratio, mk) in {'always -40/8 +12': (-40, 8, 12), 'normal -24/4 +6': (-24, 4, 6)}.items():
        p = C.post_prog(src, thr, ratio, mk)
        p = p.replace("  GMB[73] = hbp;", "  GMB[73] = hbp; GMB[76] = hbp; (tb < 8 || tb >= 20) ? PBK[7] = hbp;", 1)
        a = C.run(p)
        t = a[:, 0]
        seg = lambda t0, t1, c: a[(t >= t0) & (t < t1), c].mean()
        print(f"zero  {name:17s} not shown 14-20: {seg(14, 20, 3):5.2f} | shown 21-30: true {seg(21, 30, 1):5.2f}"
              f" reading {seg(21, 30, 3):5.2f} | tap_cal {int(a[-1, 5])}")

SPL = "function spl(i) ( i == 0 ? spl0 : i == 1 ? spl1 : i == 2 ? spl2 : i == 3 ? spl3 : i == 4 ? spl4 : i == 5 ? spl5 : i == 6 ? spl6 : i == 7 ? spl7 : i == 8 ? spl8 : i == 9 ? spl9 : i == 10 ? spl10 : i == 11 ? spl11 : i == 12 ? spl12 : i == 13 ? spl13 : i == 14 ? spl14 : i == 15 ? spl15 : i == 16 ? spl16 : i == 17 ? spl17 : 0; );"
FEED = "spl2 = x; spl3 = x; spl4 = y; spl5 = y;"

def eight_prog(src, n, secs=24):
    prog = T.build(src, 'comp', secs=secs)
    assert SPL in prog and FEED in prog
    # pins 2..33 from memory: tap t's before pair x, after pair y
    prog = prog.replace(SPL, "SPLB = 3900000; function spl(i) ( i == 0 ? spl0 : i == 1 ? spl1 : SPLB[i]; );")
    prog = prog.replace(FEED, FEED + " k8 = 0; loop(8, SPLB[2 + k8 * 4] = x; SPLB[3 + k8 * 4] = x; SPLB[4 + k8 * 4] = y; SPLB[5 + k8 * 4] = y; k8 += 1; );")
    prog = prog.replace("PBK[8] = 1;", f"PBK[8] = {n}; GMB[74] = 4;", 1)
    return prog

def eight(src):
    prog = eight_prog(src, 8).replace(PRINT, 'printf("%f %f %f %f %f %f %f %f %f %f\n", gacc/gcnt, PBK[64], PBK[65], PBK[66], PBK[67], PBK[97], PBK[98], PBK[99], PBK[100], PBK[121]);')
    prog = prog.replace("\n\nwhile", "\nwhile")
    a = eel(prog, 10)[1000:]
    print("eight  true mean %.2f | taps 1..8 mean %s | capacity %d" % (a[:, 0].mean(), " ".join("%.2f" % a[:, k].mean() for k in range(1, 9)), int(a[-1, 9])))
    # the waveforms: taps 5..8 at TW_BASE2, and nothing left in 1..4's place for them
    prog = eight_prog(src, 8, secs=4).replace(PRINT, '')
    prog = prog.rstrip() + '\nk8 = 0; loop(8, w = k8 < 4 ? GMB + 0x54000 + (k8 * 2048 + 10) * 4 : GMB + 0x208000 + ((k8 - 4) * 2048 + 10) * 4; printf("%f %f\n", w[1], w[2]); k8 += 1; );\n'
    a = eel(prog, 2)
    print("eight  waveforms, column 10, output max / input peak: " + " ".join("%.2f/%.2f" % (r[0], r[1]) for r in a))

def rates(src):
    for sr in (44100, 96000, 192000):
        for case in ('comp', 'always'):
            prog = T.build(src, case, secs=16).replace('srate = 48000; samplesblock = 480;', f'srate = {sr}; samplesblock = {sr // 100};')
            a = eel(prog, 3)
            t, e = a[1000:, 0], a[1000:, 1]
            print(f"rate  {sr:6d} {case:7s} true mean {t.mean():5.2f} est mean {e.mean():5.2f} rms {np.sqrt(np.mean((t - e) ** 2)):4.2f}")

def cost(src):
    def timeit(prog):
        open(TMP, 'w').write(prog); best = 9e9
        for _ in range(3):
            t0 = time.time(); subprocess.run([T.LOOSE, TMP], capture_output=True); best = min(best, time.time() - t0)
        return best
    base = T.build(src, 'comp', secs=48).replace(PRINT, '')
    off = timeit(base.replace(BEAT, "", 1))                        # no reader: the taps idle
    lv = timeit(base.replace("PBK[8] = 1;", "PBK[8] = 1; PBK[19] = 1;", 1))   # levels only
    on = timeit(base)
    print(f"cost  one measuring tap {100 * (on - off) / 48:.1f}% of a core at 48 kHz; levels only {100 * (lv - off) / 48:.2f}%")
    if 'PB_CAP' in src:
        e8 = timeit(eight_prog(src, 8, secs=48).replace(PRINT, ''))
        e0 = timeit(eight_prog(src, 8, secs=48).replace(PRINT, '').replace(BEAT, "", 1))
        print(f"cost  eight measuring taps {100 * (e8 - e0) / 48:.1f}% of a core at 48 kHz")

if __name__ == '__main__':
    src = open(sys.argv[1]).read()
    for w in (sys.argv[2:] or ['eight', 'gate', 'rates', 'cost']):
        {'eight': eight, 'gate': gate, 'rates': rates, 'cost': cost}[w](src)
