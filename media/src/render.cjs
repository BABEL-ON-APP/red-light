// Render video.html frame by frame.
// Stills:  node render.cjs stills 2 6 15 20 ...
// Full:    node render.cjs full [fps]
// Output goes to the folder in $OUT (frames/, stills/, events.json).
const path = require("path");
const fs = require("fs");
const { chromium } = require(process.env.PW || "playwright");

const OUT = process.env.OUT;
if (!OUT) { console.error("Set OUT to an output folder."); process.exit(1); }
const [mode, ...rest] = process.argv.slice(2);

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  const errs = [];
  page.on("pageerror", (e) => errs.push(String(e)));
  page.on("requestfailed", (r) => errs.push("FAIL " + r.url()));
  await page.goto("file://" + path.join(__dirname, "video.html"), { waitUntil: "networkidle" });
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode().catch(() => {}))));
  if (errs.length) console.log("page errors:", errs);
  const dur = await page.evaluate(() => window.DUR);
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, "events.json"), JSON.stringify(await page.evaluate(() => window.EVENTS)));

  if (mode === "stills") {
    const dir = path.join(OUT, "stills"); fs.mkdirSync(dir, { recursive: true });
    for (const s of rest) {
      const t = Number(s);
      await page.evaluate((t) => window.seek(t), t);
      await page.screenshot({ path: path.join(dir, `t${String(t).padStart(5, "0")}.png`) });
    }
  } else {
    const fps = Number(rest[0] || 30), n = Math.round(dur * fps);
    const dir = path.join(OUT, "frames"); fs.mkdirSync(dir, { recursive: true });
    const t0 = Date.now();
    for (let f = 0; f < n; f++) {
      await page.evaluate((t) => window.seek(t), f / fps);
      await page.screenshot({ path: path.join(dir, `f${String(f).padStart(5, "0")}.jpg`), type: "jpeg", quality: 92 });
      if (f % 300 === 0) console.log(`frame ${f}/${n} ${((Date.now() - t0) / 1000).toFixed(0)}s`);
    }
  }
  await browser.close();
})();
