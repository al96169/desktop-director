import { chromium } from 'playwright-core';
const b = await chromium.launch({ channel: 'msedge', headless: true,
  args: ['--autoplay-policy=no-user-gesture-required','--lang=en-US'] });
const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
await p.goto('http://127.0.0.1:5173/media-wall.html', { waitUntil: 'load' });
await p.waitForTimeout(2500);
const st = await p.evaluate(() => ({
  videos: [...document.querySelectorAll('video')].map(v => ({ src: v.currentSrc.split('/').pop(), paused: v.paused, ready: v.readyState, t: v.currentTime.toFixed(1), w: v.videoWidth })),
  audios: [...document.querySelectorAll('audio')].map(a => ({ src: a.currentSrc.split('/').pop(), paused: a.paused, ready: a.readyState, t: a.currentTime.toFixed(1), muted: a.muted })),
}));
console.log(JSON.stringify(st));
await p.screenshot({ path: '/tmp/mediawall.png' });
await b.close();
