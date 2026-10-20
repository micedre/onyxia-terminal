import { chromium } from "playwright";
const [, , base, password, shot] = process.argv;

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1200, height: 700 } });
const page = await ctx.newPage();
page.on("pageerror", e => console.log("pageerror:", e.message));

// 1. Lien du proxy sans cookie : connexion puis retour sur l'application
await page.goto(base + "/proxy/8000/sub/?x=1");
console.log("1. no cookie ->", page.url().replace(base, ""));
await page.fill("#password", password);
await page.click("#submit");
await page.waitForURL(u => u.pathname.startsWith("/proxy/8000/"), { timeout: 15000 }).catch(() => {});
console.log("   after login ->", page.url().replace(base, ""), "| body:", JSON.stringify((await page.textContent("body")).slice(0, 60)));

// 2. Terminal : URL affichée cliquable -> /proxy/PORT/
await page.goto(base + "/terminal/");
await page.waitForFunction(() => window.term && window.term.__onyxia, null, { timeout: 20000 });
await page.waitForTimeout(1500);
const run = async (s, wait = 1500) => { await page.keyboard.type(s); await page.keyboard.press("Enter"); await page.waitForTimeout(wait); };
await run("clear; echo 'Serving on http://0.0.0.0:8000/sub/ now'");
const rows = await page.evaluate(() => {
  const b = window.term.buffer.active, out = [];
  for (let i = b.viewportY; i < b.viewportY + window.term.rows; i++) out.push(b.getLine(i).translateToString(true));
  return out;
});
const row = rows.findIndex(l => l.startsWith("Serving on")), col = rows[row].indexOf("http") + 5;
const pos = await page.evaluate(([col, row]) => {
  const r = document.querySelector(".xterm-screen").getBoundingClientRect();
  return { x: r.left + (col + 0.5) * r.width / window.term.cols, y: r.top + (row + 0.5) * r.height / window.term.rows };
}, [col, row]);
await page.mouse.move(pos.x, pos.y);
await page.waitForTimeout(500);
const [popup] = await Promise.all([
  ctx.waitForEvent("page", { timeout: 8000 }).catch(() => null),
  page.mouse.click(pos.x, pos.y),
]);
if (popup) { await popup.waitForLoadState().catch(() => {}); }
console.log("2. clicked link opened:", popup ? popup.url().replace(base, "") : "NO POPUP",
  "| body:", popup ? JSON.stringify((await popup.textContent("body")).slice(0, 40)) : "");
if (popup) { await popup.close(); }

// 3. Commande ports
await run("clear; ports", 2500);
const portsOut = await page.evaluate(() => {
  const b = window.term.buffer.active, out = [];
  for (let i = b.viewportY; i < b.viewportY + window.term.rows; i++) out.push(b.getLine(i).translateToString(true));
  return out.filter(l => l.trim()).join("\n");
});
console.log("3. ports:\n" + portsOut.split("\n").filter(l => /^\d+\s/.test(l)).join("\n"));
await page.screenshot({ path: shot + "-ports.png" });

// 4. WebSocket via le proxy (serveur d'écho sur 8765)
const ws = await page.evaluate(() => new Promise(res => {
  const w = new WebSocket(location.origin.replace("http", "ws") + "/proxy/8765/");
  w.onopen = () => w.send("ping-proxy");
  w.onmessage = e => { res("echo: " + e.data); w.close(); };
  w.onerror = () => res("error");
  setTimeout(() => res("timeout"), 8000);
}));
console.log("4. websocket:", ws);

// 5. Ports interdits et port sans serveur
for (const p of ["4000", "7681", "8999"]) {
  const r = await page.request.get(base + "/proxy/" + p + "/", { maxRedirects: 0 });
  console.log("5. /proxy/" + p + "/ ->", r.status(), p === "8999" ? JSON.stringify((await r.text()).match(/<h2>[^<]*/)?.[0]) : "");
}
// 6. absproxy garde le préfixe
const abs = await page.request.get(base + "/absproxy/8000/sub/f.txt");
console.log("6. absproxy (http.server sees full path, expect 404):", abs.status());

await browser.close();
