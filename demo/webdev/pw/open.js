// Open N pages in real Microsoft Edge via Playwright (one window per page, so ddir can tile them).
// usage: node open.js '<json array of urls>' <seconds-to-stay>
import { chromium } from 'playwright-core';

const urls = JSON.parse(process.argv[2]);
const stay = Number(process.argv[3] || 120);
const channel = process.env.PW_CHANNEL || 'msedge';
const width = Number(process.env.PW_WIDTH || 900);
const height = Number(process.env.PW_HEIGHT || 1300);

// One window per URL. Edge's translate bubble is suppressed with the legacy + feature flags
// below (a persistent profile is not an option: Playwright rejects --user-data-dir in launch()).

const browser = await chromium.launch({
  channel,
  headless: false,
  args: [
    `--window-size=${width},${height}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-translate',
    '--disable-features=Translate,TranslateUI',
    '--lang=en-US',
    '--autoplay-policy=no-user-gesture-required',
    '--accept-lang=en-US',
  ],
});

for (const url of urls) {
  // one incognito context per URL -> Chromium gives each its own top-level window
  const ctx = await browser.newContext({ viewport: null });
  const page = await ctx.newPage();
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20000 });
    console.log(`opened ${url}`);
  } catch (err) {
    console.log(`failed ${url}: ${err.message.split('\n')[0]}`);
  }
}
console.log(`READY ${urls.length}`);
await new Promise((r) => setTimeout(r, stay * 1000));
await browser.close();
