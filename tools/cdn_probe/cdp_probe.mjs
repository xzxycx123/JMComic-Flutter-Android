// CDP 探针：用真实 Chrome 过 Cloudflare 挑战，抓页面里的图标/加载图资源
// 用法: node cdp_probe.mjs <url> <outJson>
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const url = process.argv[2];
const outJson = process.argv[3] || 'targets.json';
const headful = process.env.HEADFUL === '1';
const PORT = 9333;
const profile = path.join(os.tmpdir(), 'jmcdp' + Date.now());

const args = [
  `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${profile}`,
  '--no-first-run',
  '--no-default-browser-check',
  '--disable-blink-features=AutomationControlled',
  '--disable-features=IsolateOrigins,site-per-process',
  '--proxy-server=http://127.0.0.1:7890',
  'about:blank',
];
if (!headful) args.unshift('--headless=new', '--disable-gpu', '--window-size=1280,900');

const chrome = spawn(CHROME, args, { stdio: 'ignore', detached: false });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getJson(p) {
  const r = await fetch(`http://127.0.0.1:${PORT}${p}`);
  return r.json();
}

let wsUrl = null;
for (let i = 0; i < 60; i++) {
  try {
    const v = await getJson('/json/version');
    wsUrl = v.webSocketDebuggerUrl;
    if (wsUrl) break;
  } catch {}
  await sleep(250);
}
if (!wsUrl) { console.error('CDP 未就绪'); process.exit(2); }

const ws = new WebSocket(wsUrl);
let id = 0;
const pending = new Map();
const events = [];
ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  else if (msg.method) events.push(msg);
});
const send = (method, params = {}, sessionId) => new Promise((res) => {
  const mid = ++id;
  pending.set(mid, res);
  ws.send(JSON.stringify({ id: mid, method, params, ...(sessionId ? { sessionId } : {}) }));
});

await new Promise((r) => ws.addEventListener('open', r));

// 新建标签页
const { result: { targetId } } = await send('Target.createTarget', { url: 'about:blank' });
const { result: { sessionId } } = await send('Target.attachToTarget', { targetId, flatten: true });

const S = (m, p) => send(m, p, sessionId);
await S('Page.enable');
await S('Network.enable');
await S('Runtime.enable');
await S('Emulation.setUserAgentOverride', {
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  acceptLanguage: 'zh-CN,zh;q=0.9',
});

await S('Page.navigate', { url });

// 等待挑战通过：标题不含 Just a moment
let title = '';
for (let i = 0; i < 60; i++) {
  await sleep(1000);
  const { result } = await S('Runtime.evaluate', { expression: 'document.title', returnByValue: true });
  title = result?.result?.value ?? '';
  if (title && !/just a moment|attention required|请稍候/i.test(title)) break;
}

const probe = await S('Runtime.evaluate', {
  returnByValue: true,
  expression: `(() => {
    const links = [...document.querySelectorAll('link')].map(l => ({rel:l.rel, href:l.href, sizes:l.sizes?.value||'', type:l.type||''}));
    const metas = [...document.querySelectorAll('meta')].map(m => ({p:m.getAttribute('property')||m.getAttribute('name'), c:m.content})).filter(x=>x.c);
    const imgs = [...document.images].map(i => ({src:i.currentSrc||i.src, w:i.naturalWidth, h:i.naturalHeight, alt:i.alt}));
    const css = [...document.styleSheets].flatMap(s => { try { return [...s.cssRules].map(r=>r.cssText).filter(t=>/url\\(/.test(t)); } catch { return []; } });
    return {title: document.title, url: location.href, links, metas, imgs, css, html: document.documentElement.outerHTML.slice(0, 4000)};
  })()`,
});

const res = events
  .filter((e) => e.method === 'Network.responseReceived')
  .map((e) => ({ url: e.params.response.url, status: e.params.response.status, mime: e.params.response.mimeType }));

fs.writeFileSync(outJson, JSON.stringify({ title, probe: probe.result?.result?.value, responses: res }, null, 2), 'utf8');
console.log('title:', title);
console.log('写入', outJson, res.length, 'responses');
chrome.kill();
await sleep(500);
process.exit(0);
