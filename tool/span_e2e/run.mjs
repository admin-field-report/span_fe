#!/usr/bin/env node
// Drives the Flutter web build in headless Edge/Chrome through a scenario and
// saves a screenshot per step: an end-to-end check of the Span report and
// report-template screens against tool/mock_span_api.
//
//   node tool/span_e2e/run.mjs <scenario.json> <out dir>
//
// Elements are found by text through Flutter's semantics tree (accessibility
// is switched on at load), so steps read like what a user does:
//   {"go": "/projects"}                     open a path on the app
//   {"click": "Write report with Span"}     click the element with that text/label
//   {"clickAt": [x, y]}                     click a point
//   {"field": "Template name"}              click the text field with that label/hint
//   {"type": "text"}                        type into the focused field ("$env:NAME" reads it from the environment)
//   {"key": "Enter"}                        press a key (Enter, Escape, Tab, Backspace)
//   {"waitFor": "Saved", "timeout": 60000}  wait until text is on screen
//   {"expect": "Saved"} / {"expectNot": "x"} check text is (not) on screen
//   {"shot": "04-editing"}                  save a screenshot
//   {"wait": 1000}                          pause
//   {"waitGone": "Span is writing"}         wait until text is gone
//   {"scroll": [x, y, deltaY]}              mouse-wheel scroll at a point
//   {"select": "low-viscosity epoxy"}       select that text in the focused field
//   {"download": "docx"}                    expect a download (checks file arrives)
//   {"eval": "js expression"}               run JS and record the result
//   {"files": ["a.docx"], "click": "browse"} answer the file picker the click opens

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [scenarioFile, outDir] = process.argv.slice(2);
const scenario = JSON.parse(fs.readFileSync(scenarioFile, 'utf8'));
const base = scenario.baseUrl || 'http://localhost:5180';
const width = scenario.width || 1480;
const height = scenario.height || 900;
fs.mkdirSync(outDir, { recursive: true });
const downloads = path.resolve(outDir, 'downloads');
fs.mkdirSync(downloads, { recursive: true });

const browsers = [
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  '/usr/bin/google-chrome',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
];
const exe = process.env.BROWSER || browsers.find((b) => fs.existsSync(b));
const port = 9400 + Math.floor(Math.random() * 400);
const profile = path.join(process.env.TEMP || '/tmp', `span-e2e-${port}`);
const browser = spawn(exe, [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', `--remote-debugging-port=${port}`,
  // Flutter draws on animation frames: never let the headless tab throttle them.
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
  '--disable-backgrounding-occluded-windows', '--no-first-run', '--no-default-browser-check',
  `--user-data-dir=${profile}`, `--window-size=${width},${height}`, 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let targets = [];
for (let i = 0; i < 60 && !targets.length; i++) {
  try { targets = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).filter((t) => t.type === 'page'); } catch { /* starting */ }
  await sleep(250);
}
const ws = new WebSocket(targets[0].webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let nextId = 0;
const pending = new Map();
const events = [];
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  else if (m.method) events.push(m);
});
const send = (method, params = {}) => new Promise((r) => { const i = ++nextId; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evaluate = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result?.result?.value;

await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
await send('Page.enable');
await send('Page.bringToFront');
await send('Emulation.setFocusEmulationEnabled', { enabled: true });
await send('Runtime.enable');
await send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads, eventsEnabled: true });

// The build must keep semantics on (--dart-define=SPAN_SEMANTICS=true):
// clicking Flutter's placeholder can toggle them off again.
const enableSemantics = async () => {};

/** Center of the smallest visible element whose text or label contains `text`. */
const locate = (text, exact = false, fieldsOnly = false) => evaluate(`(() => {
  const want = ${JSON.stringify(text)}.toLowerCase();
  const exact = ${exact};
  const fieldsOnly = ${fieldsOnly};
  // Flutter keeps its semantics tree (and text fields) in shadow roots.
  const nodes = [];
  const walk = (root) => {
    for (const el of root.querySelectorAll('*')) {
      if (fieldsOnly ? el.matches('input, textarea, [role=textbox]') : el.matches('flt-semantics, [role], [aria-label], input, textarea')) nodes.push(el);
      if (el.shadowRoot) walk(el.shadowRoot);
    }
  };
  walk(document);
  let best = null;
  for (const n of nodes) {
    const label = ((n.getAttribute('aria-label') || '') + ' ' + (n.getAttribute('placeholder') || '') + ' ' + (n.textContent || '') + ' ' + (n.value || '')).trim().toLowerCase();
    if (!(exact ? label === want : label.includes(want))) continue;
    const r = n.getBoundingClientRect();
    if (r.width < 2 || r.height < 2 || r.bottom < 0 || r.top > innerHeight) continue;
    const area = r.width * r.height;
    if (!best || area < best.area) best = { x: r.left + r.width / 2, y: r.top + r.height / 2, area };
  }
  return best;
})()`);

const click = async (x, y) => {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  }
};

const KEYS = { Enter: 13, Escape: 27, Tab: 9, Backspace: 8, End: 35, Home: 36, ArrowLeft: 37, ArrowRight: 39 };
const press = async (key, modifiers = 0) => {
  const code = KEYS[key] ?? key.toUpperCase().charCodeAt(0);
  await send('Input.dispatchKeyEvent', { type: 'rawKeyDown', key, windowsVirtualKeyCode: code, modifiers, text: key === 'Enter' ? '\r' : undefined });
  if (key === 'Enter') await send('Input.dispatchKeyEvent', { type: 'char', key, text: '\r', modifiers });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key, windowsVirtualKeyCode: code, modifiers });
};

const results = [];
let failed = false;
const t0 = Date.now();
for (const [index, step] of scenario.steps.entries()) {
  const record = { index, step, ok: true, at: Date.now() - t0 };
  try {
    if (step.go) {
      await send('Page.navigate', { url: base + step.go });
      await sleep(step.settle ?? 6000);
      await enableSemantics();
      await sleep(800);
    } else if (step.files) {
      // The click opens Flutter's file picker; hand it the files directly.
      await send('Page.setInterceptFileChooserDialog', { enabled: true });
      const opened = new Promise((resolve) => {
        const check = setInterval(() => {
          const e = events.find((m) => m.method === 'Page.fileChooserOpened' && !m.handled);
          if (e) { e.handled = true; clearInterval(check); resolve(e.params); }
        }, 200);
      });
      const target = await locate(step.click);
      if (!target) throw new Error(`No element with text "${step.click}"`);
      await click(target.x, target.y);
      const chooser = await Promise.race([opened, sleep(10000).then(() => null)]);
      if (!chooser) throw new Error('No file picker opened');
      // Relative paths are relative to the scenario file.
      const files = step.files.map((f) => path.resolve(path.dirname(path.resolve(scenarioFile)), f));
      await send('DOM.setFileInputFiles', { files, backendNodeId: chooser.backendNodeId });
      await send('Page.setInterceptFileChooserDialog', { enabled: false });
      await sleep(step.settle ?? 2000);
    } else if (step.field) {
      const target = await locate(step.field, false, true);
      if (!target) throw new Error(`No text field "${step.field}"`);
      await click(target.x, target.y);
      await sleep(step.settle ?? 800);
    } else if (step.click || step.clickExact) {
      const text = step.click || step.clickExact;
      let target = null;
      const until = Date.now() + (step.timeout ?? 15000);
      while (!target && Date.now() < until) {
        await enableSemantics();
        target = await locate(text, Boolean(step.clickExact));
        if (!target) await sleep(500);
      }
      if (!target) throw new Error(`No element with text "${text}"`);
      await click(target.x + (step.dx || 0), target.y + (step.dy || 0));
      await sleep(step.settle ?? 1200);
    } else if (step.clickAt) {
      await click(step.clickAt[0], step.clickAt[1]);
      await sleep(step.settle ?? 1200);
    } else if (step.type !== undefined) {
      const text = String(step.type).startsWith('$env:') ? process.env[String(step.type).slice(5)] || '' : step.type;
      await send('Input.insertText', { text });
      await sleep(step.settle ?? 600);
    } else if (step.key) {
      await press(step.key, step.modifiers || 0);
      await sleep(step.settle ?? 600);
    } else if (step.select) {
      record.value = await evaluate(`(() => {
        const el = document.activeElement;
        if (!el || el.value === undefined) return 'no focused field';
        const i = el.value.indexOf(${JSON.stringify(step.select)});
        if (i < 0) return 'text not in field';
        el.setSelectionRange(i, i + ${JSON.stringify(step.select)}.length);
        el.dispatchEvent(new Event('select', { bubbles: true }));
        document.dispatchEvent(new Event('selectionchange'));
        return 'selected';
      })()`);
      if (record.value !== 'selected') throw new Error(record.value);
      await sleep(step.settle ?? 600);
    } else if (step.waitFor || step.expect) {
      const text = step.waitFor || step.expect;
      const until = Date.now() + (step.timeout ?? (step.expect ? 4000 : 30000));
      let found = null;
      while (!found && Date.now() < until) {
        await enableSemantics();
        found = await locate(text);
        if (!found) await sleep(700);
      }
      if (!found) throw new Error(`"${text}" not on screen`);
    } else if (step.waitGone) {
      const until = Date.now() + (step.timeout ?? 120000);
      while (Date.now() < until && (await locate(step.waitGone))) await sleep(1500);
      if (await locate(step.waitGone)) throw new Error(`"${step.waitGone}" still on screen`);
    } else if (step.scroll) {
      const [x, y, dy] = step.scroll;
      await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaX: 0, deltaY: dy });
      await sleep(step.settle ?? 900);
    } else if (step.expectNot) {
      await enableSemantics();
      if (await locate(step.expectNot)) throw new Error(`"${step.expectNot}" should not be on screen`);
    } else if (step.download) {
      const before = new Set(fs.readdirSync(downloads));
      const until = Date.now() + (step.timeout ?? 90000);
      let file = null;
      while (!file && Date.now() < until) {
        file = fs.readdirSync(downloads).find((f) => !before.has(f) && !f.endsWith('.crdownload') && f.toLowerCase().endsWith(`.${step.download}`));
        if (!file) {
          file = fs.readdirSync(downloads).find((f) => f.toLowerCase().endsWith(`.${step.download}`) && !f.endsWith('.crdownload') && !step.fresh);
        }
        if (!file) await sleep(1000);
      }
      if (!file) throw new Error(`No .${step.download} download arrived`);
      record.value = { file, bytes: fs.statSync(path.join(downloads, file)).size };
    } else if (step.eval) {
      record.value = await evaluate(step.eval);
    } else if (step.wait) {
      await sleep(step.wait);
    }
    if (step.shot) {
      await sleep(step.shotDelay ?? 400);
      const shot = await send('Page.captureScreenshot', { format: 'png' });
      const file = path.join(outDir, `${step.shot}.png`);
      fs.writeFileSync(file, Buffer.from(shot.result.data, 'base64'));
      record.screenshot = path.basename(file);
    }
  } catch (error) {
    record.ok = false;
    record.error = String(error.message || error);
    failed = true;
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(path.join(outDir, `FAILED-step-${index}.png`), Buffer.from(shot.result.data, 'base64'));
  }
  results.push(record);
  process.stdout.write(`${record.ok ? 'PASS' : 'FAIL'} ${index} ${step.note || JSON.stringify(step)}${record.error ? ` — ${record.error}` : ''}${record.value ? ` → ${JSON.stringify(record.value)}` : ''}\n`);
  if (!record.ok && !step.optional) break;
}

const consoleErrors = events
  .filter((e) => e.method === 'Runtime.exceptionThrown' || (e.method === 'Runtime.consoleAPICalled' && e.params.type === 'error'))
  .map((e) => JSON.stringify(e.params).slice(0, 400));
const consoleLog = events
  .filter((e) => e.method === 'Runtime.consoleAPICalled')
  .map((e) => e.params.args.map((x) => x.value ?? x.description ?? '').join(' ').slice(0, 1500));
fs.writeFileSync(path.join(outDir, 'results.json'), JSON.stringify({ scenario: scenarioFile, failed, results, consoleErrors, consoleLog, seconds: (Date.now() - t0) / 1000 }, null, 2));
// Close the whole browser (headless Edge/Chrome leaves child processes).
await Promise.race([send('Browser.close'), sleep(3000)]);
ws.close();
if (process.platform === 'win32') spawn('taskkill', ['/PID', String(browser.pid), '/T', '/F'], { stdio: 'ignore' });
else browser.kill();
await sleep(500);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* in use */ }
process.stdout.write(`${failed ? 'FAILED' : 'ALL PASSED'} (${results.length} steps, ${((Date.now() - t0) / 1000).toFixed(0)} s)\n`);
process.exit(failed ? 1 : 0);
