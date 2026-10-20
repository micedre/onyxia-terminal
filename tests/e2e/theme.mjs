import { chromium } from "playwright";
import { execFileSync } from "child_process";

const [, , base, password, shot] = process.argv;
const tmuxTheme = () => execFileSync("kubectl", ["exec", (process.env.RELEASE || "terminal-test") + "-0", "-c", "terminal", "--", "tmux", "show", "-gqv", "@theme"]).toString().trim();

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1200, height: 700 } });
const page = await ctx.newPage();
page.on("pageerror", e => console.log("pageerror:", e.message));

const open = async () => {
  await page.waitForFunction(() => window.term && window.term.__onyxia, null, { timeout: 20000 });
  await page.waitForTimeout(3500);   // annonce « hello » de tmux (sleep 2)
};
const state = () => page.evaluate(() => ({
  bg: window.term.options.theme.background,
  stored: (() => { try { return localStorage.getItem("onyxia-theme"); } catch (e) { return "ERR"; } })(),
  body: document.body.style.background,
}));
const screen = () => page.evaluate(() => {
  const b = window.term.buffer.active, out = [];
  for (let i = b.viewportY; i < b.viewportY + window.term.rows; i++) out.push(b.getLine(i).translateToString(true));
  return out;
});
const run = async (s, wait = 1500) => { await page.keyboard.type(s); await page.keyboard.press("Enter"); await page.waitForTimeout(wait); };
const cellAt = async (col, row) => page.evaluate(([col, row]) => {
  const r = document.querySelector(".xterm-screen").getBoundingClientRect();
  return { x: r.left + (col + 0.5) * r.width / window.term.cols, y: r.top + (row + 0.5) * r.height / window.term.rows };
}, [col, row]);

await page.goto(base + "/login");
await page.fill("#password", password);
await page.click("#submit");
await page.waitForURL(/\/terminal\/$/);
await open();
console.log("1. default:", JSON.stringify(await state()), "| tmux @theme:", tmuxTheme());

// 2. Bouton [◐]
let rows = await screen(), last = rows.length - 1;
console.log("   status bar:", JSON.stringify(rows[last].trim()));
let c = await cellAt(rows[last].indexOf("[◐]") + 1, last);
await page.mouse.click(c.x, c.y);
await page.waitForTimeout(1500);
console.log("2. after [◐]:", JSON.stringify(await state()), "| tmux @theme:", tmuxTheme());
await page.screenshot({ path: shot + "-dark.png" });

// 3. Rechargement, puis page de connexion
await page.reload();
await open();
console.log("3. after reload:", JSON.stringify(await state()), "| tmux @theme:", tmuxTheme());
await page.goto(base + "/logout");
console.log("   login page data-theme:", await page.evaluate(() => document.documentElement.dataset.theme),
  "bg:", await page.evaluate(() => getComputedStyle(document.body).backgroundColor));
await page.fill("#password", password);
await page.click("#submit");
await page.waitForURL(/\/terminal\/$/);
await open();

// 4. Commande theme, Alt+m, menu du clic droit
await run("clear; theme clair");
console.log("4. theme clair:", (await state()).bg, tmuxTheme());
await run("clear; theme");
console.log("   theme (affichage):", (await screen()).find(l => /^(clair|sombre|inconnu)$/.test(l.trim())));
await page.keyboard.press("Alt+m");
await page.waitForTimeout(1500);
console.log("   Alt+m:", (await state()).bg, tmuxTheme());
c = await cellAt(20, 5);
await page.mouse.click(c.x, c.y, { button: "right", delay: 150 });
await page.waitForTimeout(1200);
console.log("   menu entry shown:", (await screen()).join("\n").includes("Thème clair / sombre"));
await page.keyboard.press("m");
await page.waitForTimeout(1500);
console.log("   menu:", (await state()).bg, tmuxTheme());

// 5. Neovim ouvert pendant la bascule, et lancé après
await run("clear; nvim /tmp/theme.txt", 3500);
const nvimBg = async () => { await page.keyboard.type(":echo &background"); await page.keyboard.press("Enter"); await page.waitForTimeout(700);
  rows = await screen(); return rows[rows.length - 2].trim() || rows[rows.length - 1].trim(); };
console.log("5. nvim start bg:", await nvimBg(), "(tmux:", tmuxTheme() + ")");
await page.keyboard.press("Alt+m");
await page.waitForTimeout(2500);
console.log("   nvim after Alt+m:", await nvimBg(), "(tmux:", tmuxTheme() + ")");
await page.screenshot({ path: shot + "-nvim1.png" });
await page.keyboard.press("Alt+m");
await page.waitForTimeout(2500);
console.log("   nvim after 2nd Alt+m:", await nvimBg(), "(tmux:", tmuxTheme() + ")");
await page.screenshot({ path: shot + "-nvim2.png" });
await run(":qa!", 1000);

// 6. theme defaut
await run("clear; theme defaut");
console.log("6. theme defaut:", JSON.stringify(await state()), "| tmux @theme:", tmuxTheme());
await page.screenshot({ path: shot + "-default.png" });

await browser.close();
