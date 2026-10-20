import { chromium } from "playwright";
import { writeFileSync, mkdtempSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

const [, , base, password, shot] = process.argv;
const tmp = mkdtempSync(join(tmpdir(), "xfer-"));
writeFileSync(tmp + "/drop-shell.txt", "dropped in shell\n");
writeFileSync(tmp + "/drop-nvim.txt", "dropped while nvim\n");

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1200, height: 700 } });
const page = await ctx.newPage();
page.on("pageerror", e => console.log("pageerror:", e.message));
page.on("console", m => { if (/onyxia|ttyd\] upload/.test(m.text())) console.log("console:", m.text()); });

await page.goto(base + "/login");
await page.fill("#password", password);
await page.click("#submit");
await page.waitForURL(/\/terminal\/$/);
await page.waitForFunction(() => window.term && window.term.__onyxia, null, { timeout: 20000 });
await page.waitForFunction(() => window.term.__onyxiaTrzsz, null, { timeout: 10000 }).catch(() => {});
console.log("0. trzsz filter hooked:", await page.evaluate(() => !!window.term.__onyxiaTrzsz));
await page.waitForTimeout(1000);

// Sélecteurs du navigateur simulés avec le stockage privé (OPFS)
await page.evaluate(async () => {
  const root = await navigator.storage.getDirectory();
  window.showOpenFilePicker = async () => {
    const name = window.__upName;
    const h = await root.getFileHandle(name, { create: true });
    const w = await h.createWritable(); await w.write("uploaded " + name + "\n"); await w.close();
    return [h];
  };
  window.showDirectoryPicker = async () => root.getDirectoryHandle("dl", { create: true });
});
const opfsRead = (name) => page.evaluate(async (name) => {
  try {
    const d = await (await navigator.storage.getDirectory()).getDirectoryHandle("dl");
    return await (await (await d.getFileHandle(name)).getFile()).text();
  } catch (e) { return "ERR " + e.name; }
}, name);

const screen = () => page.evaluate(() => {
  const b = window.term.buffer.active, out = [];
  for (let i = b.viewportY; i < b.viewportY + window.term.rows; i++) out.push(b.getLine(i).translateToString(true));
  return out;
});
const buffer = async () => (await screen()).join("\n");
const run = async (s, wait = 1200) => { await page.keyboard.type(s); await page.keyboard.press("Enter"); await page.waitForTimeout(wait); };
const cell = await page.evaluate(() => {
  const r = document.querySelector(".xterm-screen").getBoundingClientRect();
  return { x: r.left, y: r.top, w: r.width / window.term.cols, h: r.height / window.term.rows };
});
const at = (col, row) => ({ x: cell.x + (col + 0.5) * cell.w, y: cell.y + (row + 0.5) * cell.h });
const cdp = await ctx.newCDPSession(page);
const drag = async (type, file) => {
  const p = at(30, 6);
  await cdp.send("Input.dispatchDragEvent", { type, x: p.x, y: p.y, data: { items: [], files: [tmp + "/" + file], dragOperationsMask: 1 } });
};
const ls = async () => { await run("clear; ls -1; cat menu-up.txt btn-up.txt 2>/dev/null", 1200); return buffer(); };

await run("mkdir -p ~/work/xfer-test2 && cd ~/work/xfer-test2 && printf 'download me\\n' > dl.txt && clear", 1500);
// le titre (dossier du panneau) est mis à jour au rafraîchissement de la barre
await page.keyboard.press("Alt+t"); await page.waitForTimeout(500); await page.keyboard.press("Alt+1"); await page.waitForTimeout(1500);

// 1. Voile pendant le glisser + dépôt dans un shell
await drag("dragEnter", "drop-shell.txt");
await drag("dragOver", "drop-shell.txt");
await page.waitForTimeout(300);
console.log("1. veil:", JSON.stringify(await page.evaluate(() => [...document.body.children].filter(e => e.textContent.startsWith("Déposer")).map(e => e.style.display + " " + e.textContent)[0])));
await page.screenshot({ path: shot + "-veil.png" });
await drag("drop", "drop-shell.txt");
await page.waitForTimeout(2500);
await page.screenshot({ path: shot + "-drop.png" });
console.log("   receiving pane:", (await buffer()).match(/Réception[^\n]*|Terminé[^\n]*/g));
await page.waitForTimeout(6000);
let out = await ls();
console.log("   file received:", out.includes("drop-shell.txt"), "| no stray trz in shell:", !/\btrz\b/.test(out));

// 2. Dépôt pendant que Neovim tourne
await run("clear; nvim nvim-buf.txt", 3000);
await drag("dragEnter", "drop-nvim.txt");
await drag("drop", "drop-nvim.txt");
await page.waitForTimeout(8500);
await page.screenshot({ path: shot + "-nvim.png" });
await page.keyboard.press("Escape");
await run(":wq", 1500);
out = await ls();
console.log("2. file received:", out.includes("drop-nvim.txt"));
await run("clear; wc -c < nvim-buf.txt", 1000);
console.log("   nvim buffer bytes (expect 0):", (await screen()).find(l => /^\d+$/.test(l.trim())));

// 3. Menu « Envoyer des fichiers ici »
await page.evaluate(() => { window.__upName = "menu-up.txt"; });
await run("clear");
let c = at(20, 5);
await page.mouse.click(c.x, c.y, { button: "right", delay: 150 });
await page.waitForTimeout(1200);
const menu = await buffer();
console.log("3. menu entries:", menu.includes("Envoyer des fichiers ici"), menu.includes("Télécharger des fichiers"));
await page.screenshot({ path: shot + "-menu.png" });
await page.keyboard.press("e");
await page.waitForTimeout(4000);
await page.keyboard.press("Enter");
await page.waitForTimeout(1000);
out = await ls();
console.log("   menu upload received:", out.includes("uploaded menu-up.txt"));

// 4. Bouton [↑] de la barre d'état
await page.evaluate(() => { window.__upName = "btn-up.txt"; });
let rows = await screen();
let last = rows.length - 1, col = rows[last].indexOf("[↑]");
console.log("4. status bar:", JSON.stringify(rows[last].trim()));
c = at(col + 1, last);
await page.mouse.click(c.x, c.y);
await page.waitForTimeout(4000);
await page.keyboard.press("Enter");
await page.waitForTimeout(1000);
out = await ls();
console.log("   button upload received:", out.includes("uploaded btn-up.txt"));

// 5. Menu « Télécharger des fichiers… » : fzf puis tsz
await run("clear");
c = at(20, 5);
await page.mouse.click(c.x, c.y, { button: "right", delay: 150 });
await page.waitForTimeout(1200);
await page.keyboard.press("r");
await page.waitForTimeout(1500);
console.log("5. fzf shown:", (await buffer()).includes("Télécharger >"));
await page.screenshot({ path: shot + "-fzf.png" });
await page.keyboard.type("dl.txt");
await page.waitForTimeout(500);
await page.keyboard.press("Enter");
await page.waitForTimeout(4000);
console.log("   downloaded content:", JSON.stringify(await opfsRead("dl.txt")));
await page.keyboard.press("Enter");
await page.waitForTimeout(1000);

// 6. Bouton [↓]
rows = await screen();
last = rows.length - 1; col = rows[last].indexOf("[↓]");
c = at(col + 1, last);
await page.mouse.click(c.x, c.y);
await page.waitForTimeout(1500);
console.log("6. [↓] opens fzf:", (await buffer()).includes("Télécharger >"));
await page.keyboard.press("Escape");
await page.waitForTimeout(1000);
console.log("   closed on Escape:", !(await buffer()).includes("Télécharger >"));

await browser.close();
