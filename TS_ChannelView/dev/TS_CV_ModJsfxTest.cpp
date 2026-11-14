// @noindex  (a development tool, not a package: never installed)
// TS_CV_Modulators.jsfx's Steps and MSEG run for real, in ysfx
// (github.com/jpcima/ysfx), with a second little JSFX standing in for
// ChannelView's side of gmem TS_CV_Mod. ysfx allows 64 sliders; this
// plugin has 251, so build it with ysfx_max_sliders = 256 (include/ysfx.h):
//   git clone --recurse-submodules https://github.com/jpcima/ysfx
//   sed -i 's/ysfx_max_sliders = 64,/ysfx_max_sliders = 256,/' ysfx/include/ysfx.h
//   cmake -S ysfx -B ysfx/build -DYSFX_PLUGIN=OFF -DYSFX_GFX=OFF && make -C ysfx/build
//   g++ -std=c++17 -Iysfx/include dev/TS_CV_ModJsfxTest.cpp ysfx/build/*.a \
//     $(find ysfx/build -name '*.a' ! -name libysfx.a) -lpthread -ldl -o modtest
//   ./modtest TS_CV_Modulators.jsfx
#include "ysfx.h"
#include <cstdio>
#include <cmath>
#include <vector>

static int fails = 0, passes = 0;
static void check(const char *name, double got, double want, double tol = 1e-3) {
  bool ok = std::fabs(got - want) <= tol;
  (ok ? passes : fails)++;
  printf("%s %-46s %g%s\n", ok ? "ok  " : "FAIL", name, got, ok ? "" : "  (want other)");
  if (!ok) printf("     want %g\n", want);
}
static ysfx_t *load(const char *path) {
  ysfx_config_t *c = ysfx_config_new();
  ysfx_t *fx = ysfx_new(c);
  ysfx_config_free(c);
  if (!ysfx_load_file(fx, path, 0) || !ysfx_compile(fx, 0)) { fprintf(stderr, "can't load %s\n", path); return nullptr; }
  ysfx_set_sample_rate(fx, 48000); ysfx_set_block_size(fx, 512); ysfx_init(fx);
  return fx;
}
static float bufs[4][512];
static void run(ysfx_t *fx) {
  const float *ins[4] = { bufs[0], bufs[1], bufs[2], bufs[3] };
  float *outs[4] = { bufs[0], bufs[1], bufs[2], bufs[3] };
  ysfx_process_float(fx, ins, outs, 4, 4, 512);
}
static ysfx_t *H;
static void gw(int i, double v) { ysfx_slider_set_value(H, 0, 1); ysfx_slider_set_value(H, 1, i); ysfx_slider_set_value(H, 2, v); run(H); }
static double gr(int i) { ysfx_slider_set_value(H, 0, 2); ysfx_slider_set_value(H, 1, i); run(H); return ysfx_slider_get_value(H, 2); }

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: modtest TS_CV_Modulators.jsfx\n"); return 2; }
  FILE *f = fopen("/tmp/ts_cv_gmem_helper.jsfx", "w");
  fputs("desc:gmem helper\noptions:gmem=TS_CV_Mod\nslider1:op=0<0,3,1>-op\nslider2:idx=0<0,100000,1>-idx\n"
        "slider3:val=0<-1000000,10000000,0.0001>-val\n@block\nop == 1 ? ( gmem[idx] = val; op = 0; );\n"
        "op == 2 ? ( val = gmem[idx]; op = 0; );\n", f);
  fclose(f);
  H = load("/tmp/ts_cv_gmem_helper.jsfx");
  ysfx_t *M = load(argv[1]);
  if (!H || !M) return 2;
  auto S = [&](int n, double v) { ysfx_slider_set_value(M, n - 1, v); };
  auto G = [&](int n) { return ysfx_slider_get_value(M, n - 1); };
  const int ID = 777, m1 = 17, m2 = 17 + 22;
  S(251, ID);
  // modulator 1: Steps, 4 steps of 1/16, notes C major 60..72, gate 50 %
  S(m1, 4); S(m1 + 3, 1); S(m1 + 6, 1); S(m1 + 7, 0); S(m1 + 11, 4); S(m1 + 13, 0);
  S(m1 + 16, 2); S(m1 + 17, 1); S(m1 + 18, 100); S(m1 + 19, 60); S(m1 + 20, 72); S(m1 + 12, 12); S(m1 + 14, -60 + 72 * 0.5);
  // its pattern: 0.2, joined 0.4, 0.9, a rest
  double vals[4] = { 0.2, 0.4, 0.9, 0.0 };
  for (int i = 0; i < 32; i++) { gw(10 + i, i < 4 ? vals[i] : 0); gw(42 + i, i == 1 ? 1 : 0); }
  double seq = gr(0) + 1;
  gw(1, ID); gw(2, 1); gw(3, 2); gw(0, seq);
  ysfx_time_info_t ti = {}; ti.tempo = 120; ti.playback_state = ysfx_playback_playing;
  ti.time_signature[0] = 4; ti.time_signature[1] = 4;
  double beat = 0;
  std::vector<int> ons, offs; std::vector<double> on_at, off_at;
  double out_at[4] = { -1, -1, -1, -1 };
  for (int b = 0; b < 48; b++) {
    ti.beat_position = beat; ysfx_set_time_info(M, &ti); run(M);
    ysfx_midi_event_t ev;
    while (ysfx_receive_midi(M, &ev)) {
      if ((ev.data[0] & 0xF0) == 0x90) { ons.push_back(ev.data[1]); on_at.push_back(beat); }
      if ((ev.data[0] & 0xF0) == 0x80) { offs.push_back(ev.data[1]); off_at.push_back(beat); }
    }
    int step = (int)std::floor(beat / 0.25 + 1e-9);
    if (step < 4 && out_at[step] < 0 && beat > step * 0.25 + 0.05) out_at[step] = G(m1 + 1);
    if (b == 0) check("mailbox: written, done", gr(4), seq);
    beat += 512.0 / 48000.0 * 2.0;
  }
  check("steps: step 1", out_at[0], 0.2);
  check("steps: step 2, joined to step 1", out_at[1], 0.2);
  check("steps: step 3", out_at[2], 0.9);
  check("steps: step 4", out_at[3], 0.0);
  check("notes: the run of two, one note", ons.size() >= 2 ? ons[0] : -1, 62, 0);
  check("notes: the next, high on the scale", ons.size() >= 2 ? ons[1] : -1, 71, 0);
  check("notes: the run's gate (half of two steps)", off_at.size() ? off_at[0] : -1, 0.25, 0.03);
  check("notes: a rest plays nothing", ons.size() >= 3 ? on_at[2] : 1.0, 1.0, 0.03);
  // read back
  seq = gr(0) + 1; gw(1, ID); gw(2, 1); gw(3, 1); gw(0, seq); run(M);
  check("mailbox: read back", gr(12), 0.9);
  check("mailbox: its joins", gr(43), 1);
  check("mailbox: another's message left alone", (gw(1, ID + 1), gw(3, 2), gw(10, 0.5), gw(0, gr(0) + 1), run(M),
    gw(1, ID), gw(3, 1), gw(0, gr(0) + 1), run(M), gr(10)), 0.2);
  // modulator 2: MSEG, a triangle over a bar, with the song
  S(m2, 5); S(m2 + 3, 1); S(m2 + 6, 1); S(m2 + 7, 11); S(m2 + 16, 0); S(m2 + 21, 1);
  double pts[] = { 3, 0, 0, 0, 0.5, 1, 0, 1, 0, 0 };
  for (int i = 0; i < 10; i++) gw(10 + i, pts[i]);
  gw(1, ID); gw(2, 2); gw(3, 4); gw(0, gr(0) + 1);
  for (double bp : { 1.0, 2.0, 3.0 }) {
    ti.beat_position = bp; ysfx_set_time_info(M, &ti); run(M);
    char nm[64]; snprintf(nm, sizeof nm, "mseg: at beat %g", bp);
    check(nm, G(m2 + 1), bp == 2.0 ? 1.0 : 0.5, 0.01);
  }
  check("mseg: where it is, published", gr(1000 + 8 * (ID % 8192) + 1), 0.75, 0.01);
  printf(fails == 0 ? "\nALL PASS (%d)\n" : "\n%d FAILURES\n", fails == 0 ? passes : fails);
  return fails == 0 ? 0 : 1;
}
