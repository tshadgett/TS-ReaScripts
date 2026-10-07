// @noindex  (a development tool, not a package: never installed)
// The web page's half of the layout baseline: lays every layout in
// TS_CV_LayoutFixture.lua out with the page's own placeControls, at one
// to six rows, and checks it against TS_CV_LayoutFixture_web.json.
//
//     node dev/TS_CV_WebLayoutTest.js [path/to/TS_ChannelView.html] [--record]
//
// --record writes a new baseline instead of checking -- only ever before
// a layout change. The page is looked for beside the scripts (the repo),
// then in REAPER's reaper_www_root (an install), unless a path is given.
const fs = require("fs"), path = require("path");
const here = __dirname;
const args = process.argv.slice(2);
const record = args.includes("--record");
const given = args.find(a => !a.startsWith("--"));
const page = [given, path.join(here, "..", "TS_ChannelView.html"),
  path.join(here, "..", "..", "..", "reaper_www_root", "TS_ChannelView.html")].find(p => p && fs.existsSync(p));
if (!page) { console.log("can't find TS_ChannelView.html"); process.exit(1); }

// the page's layout code, from its constants down to the end of placeControls
const html = fs.readFileSync(page, "utf8");
const start = html.indexOf("const CELL_H =");
const end = html.indexOf("\n// building the page from the layout");
if (start < 0 || end < 0) { console.log("layout code not found in " + page); process.exit(1); }
const src = html.slice(start, html.lastIndexOf("\n}", end) + 2);
const api = new Function(src + "\nreturn { placeControls, placeFlow, CELL_H, DIV_W, cellW: () => CELL_W };")();

const lua = fs.readFileSync(path.join(here, "TS_CV_LayoutFixture.lua"), "utf8");
const cases = [...lua.matchAll(/\{ name = "((?:[^"\\]|\\.)*)", ctl = "([^"]*)" \}/g)].map(m => ({ name: m[1], ctl: m[2] }));
const TYPE = { k: "knob", t: "toggle", c: "combo", s: "stepped", f: "fader", b: "blank", d: "divider", h: "half_gap" };
const parse = s => { const out = []; for (let i = 0; i < s.length; i++) {
  const c = { t: TYPE[s[i]] }; if (s[i + 1] === "!") { c.nr = 1; i++; } out.push(c); } return out; };

const snap = {};
cases.forEach((c, ci) => {
  for (let rows = 1; rows <= 6; rows++) {
    const lay = api.placeControls(parse(c.ctl), rows * api.CELL_H);
    snap[`${ci + 1}|${rows}`] = {
      i: lay.items.map(it => `${it.c.idx + 1},${it.x},${it.y}${it.h ? "," + it.h : ""}`).join(" "),
      r: lay.rules.join(" "), w: lay.width };
  }
});

const file = path.join(here, "TS_CV_LayoutFixture_web.json");
if (record) {
  fs.writeFileSync(file, JSON.stringify({ cases: cases.length, snap }, null, 0));
  console.log(`recorded ${Object.keys(snap).length} snapshots from ${page}`);
  process.exit(0);
}
const want = JSON.parse(fs.readFileSync(file, "utf8")).snap;
let fails = 0;
cases.forEach((c, ci) => {
  let bad = null;
  for (let rows = 1; rows <= 6 && !bad; rows++) {
    const k = `${ci + 1}|${rows}`, g = snap[k], w = want[k];
    if (!w || g.i !== w.i || g.r !== w.r || g.w !== w.w) bad = `${rows} rows: ${g.i} | w ${g.w}`;
  }
  // the merged-cell flow must agree with the strips wherever both apply
  for (let rows = 1; rows <= 6 && !bad; rows++) {
    const lay = api.placeFlow(parse(c.ctl), rows * 2, rows), w = want[`${ci + 1}|${rows}`];
    const gi = lay.items.map(it => `${it.c.idx + 1},${it.x},${it.y}${it.h ? "," + it.h : ""}`).join(" ");
    if (!w || gi !== w.i || lay.rules.join(" ") !== w.r || lay.width !== w.w) bad = `flow ${rows} rows: ${gi} | w ${lay.width}`;
  }
  console.log((bad ? "FAIL " : "ok   ") + "web layout baseline: " + c.name.slice(0, 22) + (bad ? "  " + bad : ""));
  if (bad) fails++;
});
// Faders of any shape, placed as TS_CV_Panel.layout places them -- the
// same cases, and answers, as the faders checks in TS_CV_Test.lua.
{
  const K = n => ({ t: "knob", l: n });
  const F = (n, dr, ln, th) => ({ t: "fader", l: n, dr, ln, th });
  const HW = api.cellW() / 2, HH = api.CELL_H / 2;
  const fx = v => String(Math.round(v * 100) / 100);
  const at = (ctls, rows) => api.placeControls(ctls, rows * api.CELL_H).items
    .map(it => `${it.c.l}@${fx(it.x / HW)},${fx(it.y / HH)} ${it.wu}x${it.hu}`).join(" ");
  const fc = [
    ["placed like the mockup", at([K("Thr"), K("Rat"), F("Mk", null, 2), K("Att"), K("Knee"), F("Mix", "h", 2), F("Wid", "h", 2), K("Rel"), K("Look"), F("Out")], 4),
     "Thr@0,0 2x2 Rat@0,2 2x2 Mk@0,4 2x4 Att@2,0 2x2 Knee@2,2 2x2 Mix@2,4 4x2 Wid@2,6 4x2 Rel@4,0 2x2 Look@4,2 2x2 Out@6,0 2x8"],
    ["a row of half-width ones", at([K("A"), K("B"), F("31", null, 3, 1), F("63", null, 3, 1), F("125", null, 3, 1)], 4),
     "A@0,0 2x2 B@0,2 2x2 31@2,0 1x6 63@3,0 1x6 125@4,0 1x6"],
    ["half-width full height", at([K("A"), F("Out", null, null, 1), K("B")], 4), "A@0,0 2x2 Out@2,0 1x8 B@3,0 2x2"],
    ["full length to the right edge", at([K("A"), K("B"), K("C"), K("D"), K("E"), F("Pan", "h", null, 1)], 4),
     "A@0,0 2x2 B@0,2 2x2 C@0,4 2x2 D@0,6 2x2 E@2,0 2x2 Pan@2,2 4x1"],
    ["full length under the first knob", at([K("A"), F("Pan", "h", null, 1), K("B"), K("C"), K("D"), K("E")], 3),
     "A@0,0 2x2 Pan@0,2 6x1 B@0,3 2x2 C@2,0 2x2 D@2,3 2x2 E@4,0 2x2"],
    ["list order kept", at([K("M1"), F("M4", "h", 2), K("M2"), F("M3", null, 2, 1), K("M5"), K("M6"), K("M7"), K("M8"),
       { t: "divider" }, { t: "divider" }, K("P8")], 7),
     `M1@0,0 2x2 M4@0,2 4x2 M2@0,4 2x2 M3@0.5,6 1x4 M5@0,10 2x2 M6@0,12 2x2 M7@2,0 2x2 M8@2,4 2x2 P8@${fx(4 + 4 * api.DIV_W / api.cellW())},0 2x2`],
    ["across a divider", at([K("A"), F("X", "h", 3), K("B"), { t: "divider" }, K("C"), K("D")], 3),
     `A@0,0 2x2 X@0,2 6x2 B@0,4 2x2 C@${fx(2 + 2 * api.DIV_W / api.cellW())},0 2x2 D@${fx(2 + 2 * api.DIV_W / api.cellW())},4 2x2`],
    ["across a divider: width", (() => { const l = api.placeControls([K("A"), F("X", "h", 3), K("B"), { t: "divider" }, K("C"), K("D")], 3 * api.CELL_H);
       return [l.items[1].pw, l.ruleCuts[0].length, l.width].join(","); })(), [3 * api.cellW() + api.DIV_W, 1, 3 * api.cellW() + api.DIV_W].join(",")],
    ["pad merges cells", at([K("A"), { t: "xy", l: "Pad", p2: 1 }, K("B"), K("C"), K("D")], 4),
     "A@0,0 2x2 Pad@0,2 4x4 B@0,6 2x2 C@2,0 2x2 D@2,6 2x2"],
    ["pad no taller than the panel", at([{ t: "xy", l: "Pad", sz: "3x3" }], 2), "Pad@0,0 6x4"],
    ["pad over a divider", at([K("A"), { t: "xy", l: "Pad", sz: "3x2" }, { t: "divider" }, K("B")], 3),
     `A@0,0 2x2 Pad@0,2 6x4 B@${fx(2 + 2 * api.DIV_W / api.cellW())},0 2x2`],
    ["pad over a divider: width", (() => { const l = api.placeControls([K("A"), { t: "xy", l: "Pad", sz: "3x2" }, { t: "divider" }, K("B")], 3 * api.CELL_H);
       return [l.items[1].pw, l.ruleCuts[0].length].join(","); })(), [3 * api.cellW() + api.DIV_W, 1].join(",")],
    ["dual large", at([{ t: "dual", l: "Dl", sz: "large" }, K("A")], 3), "Dl@0,0 3x3 A@0.5,3 2x2"],
    ["half-width pairs", at([F("a", null, 2, 1), F("b", null, 2, 1), F("c", null, 2, 1), F("d", null, 2, 1), K("K")], 4),
     "a@0,0 1x4 b@1,0 1x4 c@0,4 1x4 d@1,4 1x4 K@2,0 2x2"],
  ];
  for (const [name, got, want] of fc) {
    const ok = got === want;
    console.log((ok ? "ok   " : "FAIL ") + "web faders: " + name + (ok ? "" : "  " + got));
    if (!ok) fails++;
  }
}
console.log(fails ? `\n${fails} FAILURES` : "\nALL PASS");
process.exit(fails ? 1 : 0);
