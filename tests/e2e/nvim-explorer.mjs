import { chromium } from "playwright";
// Explorateur de LazyVim (Espace e) : fichiers cachés visibles, .git masqué
const [, , base, password, shot] = process.argv;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 700 } });
await page.goto(base + "/login");
await page.fill("#password", password);
await page.click("#submit");
await page.waitForURL(/\/terminal\/$/);
await page.waitForFunction(() => window.term && window.term.__onyxia, null, { timeout: 20000 });
await page.waitForTimeout(1500);
const screen = () => page.evaluate(() => {
  const b = window.term.buffer.active, out = [];
  for (let i = b.viewportY; i < b.viewportY + window.term.rows; i++) out.push(b.getLine(i).translateToString(true));
  return out.join("\n");
});
await page.keyboard.type("mkdir -p ~/work/dottest/.github && cd ~/work/dottest && git init -q; touch .gitignore .github/ci.yml README.md; clear; nvim");
await page.keyboard.press("Enter");
await page.waitForTimeout(3500);
await page.keyboard.press("Escape");
await page.keyboard.press("Space");
await page.keyboard.press("e");
await page.waitForTimeout(2000);
const s = await screen();
const tree = s.split("\n").map(l => l.slice(0, 40));
console.log("explorer shows .github:", /\.github/.test(s), "| .gitignore:", /\.gitignore/.test(s),
  "| README.md:", /README\.md/.test(s), "| .git/ (expect false):", tree.some(l => /\.git\s*$/.test(l.trim()) || /\s\.git(\s|$)/.test(l)));
await page.screenshot({ path: shot + "-explorer.png" });
await page.keyboard.type(":qa!");
await page.keyboard.press("Enter");
await browser.close();
