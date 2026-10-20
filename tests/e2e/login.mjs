import { chromium } from "playwright";

const [, , base, password, shot] = process.argv;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1100, height: 700 } });

await page.goto(base + "/");
await page.waitForURL(/\/login$/);
console.log("redirected to login:", page.url());
await page.screenshot({ path: shot + "-login.png" });

await page.fill("#password", "wrong-password");
await page.click("#submit");
await page.waitForFunction(() => document.getElementById("msg").textContent.length > 0);
console.log("wrong password message:", await page.textContent("#msg"), "| url:", page.url());

await page.fill("#password", password);
await page.click("#submit");
await page.waitForURL(/\/terminal\/$/);
await page.waitForFunction(() => window.term && window.term.buffer.active.length > 1, null, { timeout: 20000 });
await page.waitForTimeout(2000);
const text = await page.evaluate(() => {
  const b = window.term.buffer.active, out = [];
  for (let i = 0; i < b.length; i++) out.push(b.getLine(i).translateToString(true));
  return out.join("\n").trim();
});
console.log("terminal opened, buffer tail:\n" + text.split("\n").slice(-3).join("\n"));
await page.screenshot({ path: shot + "-terminal.png" });

await page.reload();
await page.waitForTimeout(1500);
console.log("after reload:", page.url());

await page.goto(base + "/logout");
await page.waitForURL(/\/login$/);
await page.goto(base + "/terminal/");
console.log("after logout, /terminal/ ->", page.url());
await browser.close();
