import { chromium } from "playwright";

// Mode application : client HTML5 d'Xpra, mot de passe, puis fenêtre de l'appli.
//   node app.mjs <base> <mot de passe> <préfixe capture> [titre attendu]
const [, , base, password, shot, title = ""] = process.argv;
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 } });
const page = await ctx.newPage();
page.on("pageerror", e => console.log("pageerror:", e.message));

const probe = await page.request.get(base + "/", { maxRedirects: 0 });
console.log("1. GET / ->", probe.status(), "(sondes HTTP du chart vscode-python)");

await page.goto(base + "/");
// Xpra demande le mot de passe au premier défi d'authentification
const pw = page.locator("input[type=password]:visible").first();
await pw.waitFor({ timeout: 20000 });
await pw.fill(password);
await pw.press("Enter");
console.log("2. password sent");

// Les fenêtres de l'application sont des <canvas> dans des div.window
const win = page.locator("div.window").first();
const ok = await win.waitFor({ timeout: 120000 }).then(() => true, () => false);
await page.waitForTimeout(15000);   // laisser l'appli finir de dessiner (JVM, Qt)
const titles = await page.locator("div.window .windowtitle").allTextContents().catch(() => []);
console.log("3. window shown:", ok, "| titles:", JSON.stringify(titles));
if (title) console.log("   expected title:", titles.some(t => t.includes(title)) ? "OK" : "FAIL");
await page.screenshot({ path: shot + "-app.png" });
await browser.close();
