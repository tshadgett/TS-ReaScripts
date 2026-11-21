// @noindex  (a development tool, not a package: never installed)
// TS_TrackProbe.jsfx compiled and run for real, in ysfx
// (github.com/jpcima/ysfx): two copies as a track's pre and post probe,
// a little JSFX standing in for the scripts' side of gmem TS_TA_Mem.
// REAPER's get_host_placement() isn't in ysfx: the copy run here takes
// the track and place from two sliders instead.
//   git clone --recurse-submodules https://github.com/jpcima/ysfx
//   cmake -S ysfx -B ysfx/build -DYSFX_PLUGIN=OFF -DYSFX_GFX=OFF && make -C ysfx/build
//   g++ -std=c++17 -Iysfx/include dev/TS_CV_ProbeJsfxTest.cpp ysfx/build/libysfx.a \
//     $(find ysfx/build -name '*.a' ! -name libysfx.a) -lpthread -ldl -o probetest
//   ./probetest TS_TrackProbe.jsfx
#include "ysfx.h"
#include <cstdio>
#include <cmath>
#include <string>
#include <fstream>
#include <sstream>
static void replace_all(std::string &s, const std::string &a, const std::string &b) {
  for (size_t p = s.find(a); p != std::string::npos; p = s.find(a, p + b.size())) s.replace(p, a.size(), b);
}
// The probe as ysfx can run it: its track and place from two sliders
static std::string testable(const char *path) {
  std::ifstream in(path); std::stringstream ss; ss << in.rdbuf(); std::string s = ss.str();
  replace_all(s, "options:gmem=TS_TA_Mem\n", "options:gmem=TS_TA_Mem\nslider1:t_tr=0<-2,100,1>-tr\nslider2:t_pos=0<0,100,1>-pos\n");
  replace_all(s, "get_host_placement(pl_pos, pl_fl)", "(pl_pos = t_pos; pl_fl = 0; t_tr)");
  replace_all(s, "get_host_placement()", "t_tr");
  std::string out = "/tmp/ts_trackprobe_test.jsfx";
  std::ofstream(out) << s;
  return out;
}
static int fails = 0;
static void check(const char *n, double got, double want, double tol) {
  bool ok = std::fabs(got - want) <= tol; if (!ok) fails++;
  printf("%s %-50s %g%s\n", ok ? "ok  " : "FAIL", n, got, ok ? "" : " (want other)");
}
static ysfx_t *load(const char *path) {
  ysfx_config_t *c = ysfx_config_new(); ysfx_t *fx = ysfx_new(c); ysfx_config_free(c);
  if (!ysfx_load_file(fx, path, 0)) { fprintf(stderr, "can't load %s\n", path); return nullptr; }
  if (!ysfx_compile(fx, 0)) { fprintf(stderr, "can't compile %s\n", path); return nullptr; }
  ysfx_set_sample_rate(fx, 48000); ysfx_set_block_size(fx, 512); ysfx_init(fx); return fx;
}
static float b[2][512];
static void run(ysfx_t *fx) { const float *in[2] = { b[0], b[1] }; float *out[2] = { b[0], b[1] }; ysfx_process_float(fx, in, out, 2, 2, 512); }
static ysfx_t *H;
static void gw(int i, double v) { ysfx_slider_set_value(H, 0, 1); ysfx_slider_set_value(H, 1, i); ysfx_slider_set_value(H, 2, v); run(H); }
static double gr(int i) { ysfx_slider_set_value(H, 0, 2); ysfx_slider_set_value(H, 1, i); run(H); return ysfx_slider_get_value(H, 2); }
int main(int argc, char **argv) {
  FILE *f = fopen("/tmp/ts_ta_gmem_helper.jsfx", "w");
  fputs("desc:gmem helper\noptions:gmem=TS_TA_Mem\nslider1:op=0<0,3,1>-op\nslider2:idx=0<0,10000000,1>-idx\n"
        "slider3:val=0<-1000000,10000000,0.0001>-val\n@block\nop == 1 ? ( gmem[idx] = val; op = 0; );\n"
        "op == 2 ? ( val = gmem[idx]; op = 0; );\n", f);
  fclose(f);
  H = load("/tmp/ts_ta_gmem_helper.jsfx");
  if (argc < 2) { fprintf(stderr, "usage: probetest TS_TrackProbe.jsfx\n"); return 2; }
  std::string probe = testable(argv[1]);
  ysfx_t *pre = load(probe.c_str()), *post = load(probe.c_str());
  if (!H || !pre || !post) return 2;
  // track index 0: pre at place 0, post at place 1
  ysfx_slider_set_value(pre, 0, 0); ysfx_slider_set_value(pre, 1, 0);
  ysfx_slider_set_value(post, 0, 0); ysfx_slider_set_value(post, 1, 1);
  const int PB = 0x100000 + 128;
  gw(PB + 0, 1); gw(PB + 1, 2);
  gw(79, 2);                 // track index 0 writes the chain's waveform
  ysfx_time_info_t ti = {}; ti.tempo = 120; ti.playback_state = ysfx_playback_playing;
  ti.time_signature[0] = 4; ti.time_signature[1] = 4;
  double t = 0; long n = 0;
  for (int k = 0; k < 400; k++) {
    gw(80, k + 1);
    gw(0x520000 + 272 + 6, k + 1);   // the spectrum going in, asked for
    gw(PB + 127, k + 1);              // and coming out
    ti.time_position = t; ti.beat_position = t * 2;
    for (int i = 0; i < 512; i++) { double s = 0.5 * std::sin(2 * M_PI * 220 * (n + i) / 48000.0); b[0][i] = b[1][i] = (float)s; }
    ysfx_set_time_info(pre, &ti); run(pre);
    for (int i = 0; i < 512; i++) { b[0][i] *= 0.5f; b[1][i] *= 0.5f; }   // the chain: -6 dB
    ysfx_set_time_info(post, &ti); run(post);
    t += 512 / 48000.0; n += 512;
  }
  const int CW = 0x640000;
  double newest = gr(CW), slice = gr(CW + 2), who = gr(CW + 4);
  check("waveform: a column every 4 ms", slice, 192, 0);
  check("waveform: written by track index 0", who, 2, 0);
  check("waveform: the newest column, where the play position is", newest, std::floor(n / 192.0) - 1, 1);
  int c = (int)newest - 10;
  int a = CW + 16 + (c % 2048) * 6;
  check("waveform: in max", gr(a + 1), 0.5, 0.02);
  check("waveform: in min", gr(a + 0), -0.5, 0.02);
  check("waveform: out max (the chain's -6 dB)", gr(a + 3), 0.25, 0.01);
  check("waveform: the column whole (both probes)", gr(a + 4) == c && gr(a + 5) == c, 1, 0);
  const int PR = 0x520000 + 272, PO = 0x3A0000 + 272;
  check("before spectrum: written", gr(PR) > 0, 1, 0);
  check("before spectrum: by track index 0", gr(PR + 5), 2, 0);
  check("before spectrum: 256 bands", gr(PR + 1), 256, 0);
  // the loudest band, in and out: 220 Hz, 6 dB apart
  int bi = 0, bo = 0; double mi = -1e9, mo = -1e9;
  for (int i = 0; i < 256; i++) { double v = gr(PR + 16 + i), w = gr(PO + 16 + i); if (v > mi) { mi = v; bi = i; } if (w > mo) { mo = w; bo = i; } }
  double lo = gr(PR + 2), hi = gr(PR + 3);
  check("before spectrum: its loudest band at 220 Hz", lo * std::pow(hi / lo, (bi + 0.5) / 256), 220, 15);
  check("before and after: the same band", bo, bi, 0);
  check("before and after: 6 dB apart", mi - mo, 6.02, 0.5);
  // stopped: nothing more
  ti.playback_state = 0;
  for (int k = 0; k < 20; k++) { gw(80, 1000 + k); ysfx_set_time_info(pre, &ti); run(pre); ysfx_set_time_info(post, &ti); run(post); }
  check("waveform: stopped, no new columns", gr(CW), newest, 0);
  printf(fails ? "\n%d FAILURES\n" : "\nALL PASS\n", fails);
  return fails ? 1 : 0;
}
