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
const api = new Function(src + "\nreturn { placeControls, CELL_H };")();

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
  console.log((bad ? "FAIL " : "ok   ") + "web layout baseline: " + c.name.slice(0, 22) + (bad ? "  " + bad : ""));
  if (bad) fails++;
});
console.log(fails ? `\n${fails} FAILURES` : "\nALL PASS");
process.exit(fails ? 1 : 0);
