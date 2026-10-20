import { chromium } from "playwright";

const [, , base, password, shot] = process.argv;
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1200, height: 700 } });
await ctx.grantPermissions(["clipboard-read", "clipboard-write"], { origin: base });
const page = await ctx.newPage();
page.on("pageerror", e => console.log("pageerror:", e.message));

await page.goto(base + "/login");
await page.fill("#password", password);
await page.click("#submit");
await page.waitForURL(/\/terminal\/$/);
await page.waitForFunction(() => window.term && window.term.__onyxia, null, { timeout: 20000 });
await page.waitForTimeout(1500);

const buffer = () => page.evaluate(() => {
  const b = window.term.buffer.active, out = [];
  for (let i = b.viewportY; i < b.viewportY + window.term.rows; i++) out.push(b.getLine(i).translateToString(true));
  return out.join("\n");
});
const clip = () => page.evaluate(() => navigator.clipboard.readText());
const setClip = (t) => page.evaluate((t) => navigator.clipboard.writeText(t), t);
const run = async (s, wait = 1200) => { await page.keyboard.type(s); await page.keyboard.press("Enter"); await page.waitForTimeout(wait); };
const cell = await page.evaluate(() => {
  const r = document.querySelector(".xterm-screen").getBoundingClientRect();
  return { x: r.left, y: r.top, w: r.width / window.term.cols, h: r.height / window.term.rows };
});
const at = (col, row) => ({ x: cell.x + (col + 0.5) * cell.w, y: cell.y + (row + 0.5) * cell.h });

// 1. OSC 52 depuis le shell
await run("clear; printf '\\e]52;c;%s\\a' \"$(printf 'héllo osc52' | base64)\"");
console.log("1. OSC52 -> clipboard:", JSON.stringify(await clip()));

// 2. Sélection à la souris dans tmux
await run("clear; echo SELECTME-ABCDEF");
const lines = (await buffer()).split("\n");
const row = lines.findIndex(l => l.startsWith("SELECTME"));
const a = at(0, row), b = at(14, row);
await page.mouse.move(a.x, a.y); await page.mouse.down();
await page.mouse.move(b.x, b.y, { steps: 8 }); await page.mouse.up();
await page.waitForTimeout(1000);
console.log("2. mouse drag -> clipboard:", JSON.stringify(await clip()));

// 3. Ctrl+V colle le presse-papiers
await setClip("echo PASTED-$((6*7))");
await page.keyboard.press("Control+V");
await page.keyboard.press("Enter");
await page.waitForTimeout(1000);
console.log("3. Ctrl+V pasted:", (await buffer()).includes("PASTED-42"));

// 4. Clic droit : menu tmux, menu du navigateur empêché
await run("clear");
const prevented = page.evaluate(() => new Promise(res => document.addEventListener("contextmenu", e => setTimeout(() => res(e.defaultPrevented), 0), { once: true })));
const c = at(20, 5);
await page.mouse.click(c.x, c.y, { button: "right", delay: 150 });
console.log("4. browser menu prevented:", await prevented);
await page.waitForTimeout(1500);
console.log("   tmux menu shown:", (await buffer()).includes("Coller la dernière copie"));
await page.screenshot({ path: shot + "-menu.png" });
await page.keyboard.press("Escape");
await page.waitForTimeout(500);
console.log("   menu closed by Escape:", !(await buffer()).includes("Coller la dernière copie"));

// 5. Neovim : yy -> presse-papiers
await run("nvim /tmp/n.txt", 3000);
await page.keyboard.type("yy");
await page.waitForTimeout(1000);
await page.screenshot({ path: shot + "-nvim.png" });
console.log("5. nvim yy -> clipboard:", JSON.stringify(await clip()));
await page.keyboard.type(":qa!"); await page.keyboard.press("Enter");
await page.waitForTimeout(1000);

// 6. Aide : Alt+h puis bouton [?]
await page.keyboard.press("Alt+h");
await page.waitForTimeout(1000);
console.log("6. Alt+h help shown:", (await buffer()).includes("Copier / coller"));
await page.screenshot({ path: shot + "-help.png" });
await page.keyboard.press("q");
await page.waitForTimeout(600);
console.log("   closed with q:", !(await buffer()).includes("Copier / coller"));
const statusRow = await page.evaluate(() => window.term.rows - 1);
const statusLine = (await buffer()).split("\n").slice(-1)[0];
const sl = (await page.evaluate(() => { const b = window.term.buffer.active; return b.getLine(b.viewportY + window.term.rows - 1).translateToString(true); }));
const col = sl.indexOf("[?]");
const h = at(col + 1, statusRow);
await page.mouse.click(h.x, h.y);
await page.waitForTimeout(1000);
console.log("   [?] button opens help:", (await buffer()).includes("Copier / coller"));
await page.keyboard.press("q");
await browser.close();
