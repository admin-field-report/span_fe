#!/usr/bin/env node
// Local stand-in for the Span backend, for running the app's Span report and
// report-template screens without a dev login. Serves the be_rest_api routes
// those screens call (sign-in, projects, reports, /span-report/*), simulates
// Span writing a report or building a template, and rebuilds the Word file on
// save with the agent's real fill_template.py.
//
//   node tool/mock_span_api/server.mjs --fixtures <dir> [--port 8787]
//   flutter run -d chrome --dart-define=SPAN_API_BASE_URL=http://localhost:8787
//
// Fixtures (not in the repo; real report data stays out of git):
//   <dir>/mock-users.json      [{"email": ..., "password": ...}] test accounts
//   <dir>/t1/                  one profiled template + one generated report:
//     template.docx template-spec.json instructions.md style-guide.md
//     uncertainty-report.md fill_map.json filled.docx filled.pdf
//     inspection_context.json photos/<photo id>.jpg
//
// Env: MOCK_PYTHON (python with python-docx), MOCK_FILL_SCRIPT (path to
// fill_template.py), MOCK_PDF_SCRIPT (docx -> pdf script, optional),
// MOCK_SPEED (1 = ~45 s per run, higher is faster).

import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((pairs, arg, i, all) => (arg.startsWith('--') ? [...pairs, [arg.slice(2), all[i + 1]]] : pairs), []),
);
const FIXTURES = path.resolve(args.fixtures || process.env.MOCK_FIXTURES || '.');
const PORT = Number(args.port || process.env.PORT || 8787);
const SPEED = Number(process.env.MOCK_SPEED || 1);
const PYTHON = process.env.MOCK_PYTHON || 'python';
const FILL_SCRIPT = process.env.MOCK_FILL_SCRIPT || '';
const PDF_SCRIPT = process.env.MOCK_PDF_SCRIPT || path.join(path.dirname(fileURLToPath(import.meta.url)), 'docx_to_pdf_word.py');
const WORK = path.join(FIXTURES, '.mock-work');
fs.mkdirSync(WORK, { recursive: true });

const TEMPLATE_DIR = path.join(FIXTURES, 't1');
const now = () => new Date().toISOString();
const id = (prefix) => `${prefix}_${Date.now().toString(36)}${randomBytes(3).toString('hex')}`;
const readJson = (file, fallback = null) => {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
};

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

const users = readJson(path.join(FIXTURES, 'mock-users.json'), []);
const user = {
  id: 'user_mock_1',
  email: users[0]?.email || 'inspector@example.test',
  first_name: 'Maya',
  last_name: 'Chen',
  company_id: 'company_mock_1',
  company: { id: 'company_mock_1', name: 'Northline Structural Engineers' },
};
const project = {
  id: 'project_675',
  name: '675 Street',
  description: 'Parapet reconstruction and facade repairs',
  client_id: 'client_1',
  client: { name: 'Bronxdale Masonry' },
  create_time: '2026-09-01T14:00:00.000Z',
};
const inspections = [
  { id: 'insp_16sep', name: 'Level 3 walkthrough', create_time: '2026-09-16T13:00:00.000Z', creator_id: user.id },
  { id: 'insp_09sep', name: 'Level 1 and 2 walkthrough', create_time: '2026-09-09T13:00:00.000Z', creator_id: user.id },
];
const spec = readJson(path.join(TEMPLATE_DIR, 'template-spec.json'), {});
const templates = [
  {
    id: 'tmpl_facade',
    name: 'Facade progress report',
    createdAt: '2026-09-27T10:00:00.000Z',
    examples: [
      { name: 'Progress report 5.docx', pathname: 'examples/progress-5.docx', size: 2400000 },
      { name: 'Progress report 6.docx', pathname: 'examples/progress-6.docx', size: 2600000 },
    ],
    profile: { status: 'ready', jobId: 'pjob_facade', builtAt: '2026-09-27T10:12:00.000Z' },
    dir: TEMPLATE_DIR,
  },
];
const reports = [
  // A report from before Span (HTML/PDF flow): must keep opening the old way.
  { id: 'report_legacy', name: 'August walkthrough summary', create_time: '2026-08-12T15:00:00.000Z', report_format: null },
];
const runs = []; // generate jobs
const profileJobs = []; // profile jobs
const storage = new Map(); // key -> { file?, bytes?, type }

function addStorage(file, type) {
  const key = `${id('obj')}/${path.basename(file)}`;
  storage.set(key, { file, type });
  return `http://localhost:${PORT}/storage/${key}`;
}

const TYPES = {
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.pdf': 'application/pdf',
  '.json': 'application/json',
  '.md': 'text/markdown',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};
const typeOf = (file) => TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream';

// A seeded run that is already finished, so the report screen opens at once.
function seedRun() {
  const run = newRun({ inspectionId: 'insp_16sep', templateId: 'tmpl_facade', seconds: 0 });
  run.status = 'ready';
  run.finishedAt = now();
  finishRunFiles(run);
}

function newRun({ inspectionId, templateId }) {
  const inspection = inspections.find((i) => i.id === inspectionId) || inspections[0];
  const template = templates.find((t) => t.id === templateId) || templates[0];
  const jobId = id('job');
  const reportId = id('report');
  const dir = path.join(WORK, jobId);
  fs.mkdirSync(path.join(dir, 'edits', 'photos'), { recursive: true });
  const run = {
    jobId,
    reportId,
    status: 'running',
    templateId: template.id,
    templateName: template.name,
    inspectionId: inspection.id,
    inspectionName: inspection.name,
    createdAt: now(),
    startedMs: Date.now(),
    dir,
    template,
    edit: null,
  };
  runs.unshift(run);
  reports.unshift({
    id: reportId,
    name: `Word report ${run.createdAt.slice(0, 10)}`,
    create_time: run.createdAt,
    report_format: 'docx',
  });
  return run;
}

function finishRunFiles(run) {
  for (const name of ['fill_map.json', 'filled.docx', 'filled.pdf']) {
    const src = path.join(run.template.dir, name);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(run.dir, name));
  }
}

const RUN_PHASES = ['starting', 'reading', 'writing', 'filling', 'qa', 'visual', 'finishing'];
const RUN_SECONDS = 45 / SPEED;

function tickRun(run) {
  if (run.status !== 'running') return;
  const elapsed = (Date.now() - run.startedMs) / 1000;
  if (elapsed >= RUN_SECONDS) {
    run.status = 'ready';
    run.finishedAt = now();
    finishRunFiles(run);
  }
}

function runPhase(run) {
  const elapsed = (Date.now() - run.startedMs) / 1000;
  const index = Math.min(RUN_PHASES.length - 1, Math.floor((elapsed / RUN_SECONDS) * RUN_PHASES.length));
  const started = {};
  RUN_PHASES.slice(0, index + 1).forEach((key, i) => {
    started[key] = new Date(run.startedMs + (i * RUN_SECONDS * 1000) / RUN_PHASES.length).toISOString();
  });
  return { key: RUN_PHASES[index], index, started };
}

function runSummary(run) {
  tickRun(run);
  return {
    jobId: run.jobId,
    status: run.status,
    templateId: run.templateId,
    templateName: run.templateName,
    inspectionId: run.inspectionId,
    inspectionName: run.inspectionName,
    projectId: project.id,
    reportId: run.reportId,
    createdAt: run.createdAt,
    updatedAt: run.finishedAt || run.createdAt,
    durationSeconds: run.finishedAt ? Math.round(RUN_SECONDS) : null,
    qaResult: run.status === 'ready' ? 'PASS' : null,
    note: run.status === 'ready' ? 'PASS: report written from the inspection' : null,
    error: null,
  };
}

function runFiles(run) {
  return fs.existsSync(run.dir) ? fs.readdirSync(run.dir).filter((f) => fs.statSync(path.join(run.dir, f)).isFile()) : [];
}

function runDetail(run) {
  const files = runFiles(run);
  const edited = run.edit?.status === 'rebuilt' && files.includes('filled.edited.docx');
  const report = edited ? 'generated/filled.edited.docx' : files.includes('filled.docx') ? 'generated/filled.docx' : null;
  const pdf = edited
    ? files.includes('filled.edited.pdf') ? 'generated/filled.edited.pdf' : null
    : files.includes('filled.pdf') ? 'generated/filled.pdf' : null;
  return {
    run: runSummary(run),
    timing: { typicalMinutes: 3, maxMinutes: 15 },
    inspection: { documents: 1, pages: 2, findings: 6, photos: album(run).length },
    stats: {},
    qa: { result: run.status === 'ready' ? 'PASS' : null, checks: [], fixed: [], open: [], visualReview: [] },
    questions: [],
    notes: null,
    files: files.map((f) => ({ path: `generated/${f}` })),
    report,
    pdf,
    edit: run.edit,
  };
}

function album(run) {
  const context = readJson(path.join(run.template.dir, 'inspection_context.json'), {});
  const out = [];
  const seen = new Set();
  const visit = (node, inPhotos) => {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) return node.forEach((n) => visit(n, inPhotos));
    if (inPhotos && typeof node.id === 'string' && !seen.has(node.id)) {
      seen.add(node.id);
      out.push({ path: `/workspace/inspection/photos/${node.id}.jpg`, caption: node.caption || null });
    }
    for (const [k, v] of Object.entries(node)) visit(v, k === 'photos');
  };
  visit(context, false);
  // Extra photos taken on the visit that the report doesn't use yet.
  const photoDir = path.join(run.template.dir, 'photos');
  for (const f of fs.existsSync(photoDir) ? fs.readdirSync(photoDir) : []) {
    const stem = f.replace(/\.[a-z]+$/i, '');
    if (!seen.has(stem)) {
      seen.add(stem);
      out.push({ path: `/workspace/inspection/photos/${f}`, caption: null });
    }
  }
  return out;
}

function photoFile(run, p) {
  if (p.startsWith('generated/edits/photos/')) return path.join(run.dir, 'edits', 'photos', path.basename(p));
  if (p.startsWith('/workspace/inspection/photos/')) {
    const stem = path.basename(p).replace(/\.[a-z]+$/i, '');
    const dir = path.join(run.template.dir, 'photos');
    const match = fs.readdirSync(dir).find((f) => f.replace(/\.[a-z]+$/i, '') === stem);
    return match ? path.join(dir, match) : null;
  }
  return null;
}

function currentFillMap(run) {
  return readJson(path.join(run.dir, 'fill_map.edited.json')) || readJson(path.join(run.dir, 'fill_map.json'));
}

/** Save an edit and rebuild the Word file with the agent's fill_template.py. */
function rebuild(run) {
  const fill = currentFillMap(run);
  const local = JSON.parse(JSON.stringify(fill), (key, value) => {
    if ((key === 'image' || key === 'path') && typeof value === 'string' && value) return photoFile(run, value) || value;
    return value;
  });
  const mapFile = path.join(run.dir, 'fill_map.local.json');
  fs.writeFileSync(mapFile, JSON.stringify(local, null, 1));
  const out = path.join(run.dir, 'filled.edited.docx');
  const started = Date.now();
  const done = (ok, error) => {
    run.edit = { ...run.edit, status: ok ? 'rebuilt' : 'rebuild_failed', report: ok ? 'generated/filled.edited.docx' : null, error: error || null };
    log(`rebuild ${run.jobId}: ${run.edit.status} in ${Date.now() - started} ms${error ? ` (${error})` : ''}`);
  };
  if (!FILL_SCRIPT) return setTimeout(() => done(false, 'MOCK_FILL_SCRIPT not set'), 500);
  const child = spawn(PYTHON, [FILL_SCRIPT, path.join(run.template.dir, 'template.docx'), mapFile, out], { stdio: ['ignore', 'pipe', 'pipe'] });
  let stderr = '';
  child.stderr.on('data', (d) => (stderr += d));
  child.on('close', (code) => {
    if (code !== 0) return done(false, stderr.slice(-400));
    const pdf = spawn(PYTHON, [PDF_SCRIPT, out, path.join(run.dir, 'filled.edited.pdf')], { stdio: 'ignore' });
    pdf.on('close', () => done(true));
    pdf.on('error', () => done(true));
  });
  child.on('error', (e) => done(false, String(e)));
}

// --- profile jobs -----------------------------------------------------------

const PROFILE_PHASES = ['starting', 'reading', 'building', 'checking', 'writing', 'packaging'];
const PROFILE_SECONDS = 50 / SPEED;

function tickProfile(template) {
  const job = profileJobs.find((j) => j.jobId === template.profile?.jobId);
  if (!job || job.status !== 'running') return;
  if ((Date.now() - job.startedMs) / 1000 >= PROFILE_SECONDS) {
    job.status = 'ready';
    template.profile = { status: 'ready', jobId: job.jobId, builtAt: now() };
    template.dir = TEMPLATE_DIR;
  }
}

function templateJson(t) {
  tickProfile(t);
  const { dir: _dir, ...rest } = t;
  return rest;
}

function profilePhase(job) {
  const elapsed = (Date.now() - job.startedMs) / 1000;
  const index = Math.min(PROFILE_PHASES.length - 1, Math.floor((elapsed / PROFILE_SECONDS) * PROFILE_PHASES.length));
  const started = {};
  PROFILE_PHASES.slice(0, index + 1).forEach((key, i) => {
    started[key] = new Date(job.startedMs + (i * PROFILE_SECONDS * 1000) / PROFILE_PHASES.length).toISOString();
  });
  return { key: PROFILE_PHASES[index], index, started };
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

function log(message) {
  process.stdout.write(`[mock] ${message}\n`);
}

function send(res, status, body, headers = {}) {
  const isBuffer = Buffer.isBuffer(body);
  res.writeHead(status, {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    ...(status === 204 ? {} : { 'Content-Type': isBuffer ? headers['Content-Type'] || 'application/octet-stream' : 'application/json' }),
    ...headers,
  });
  // 204 must not carry a body (a body here can wedge the browser's connection).
  res.end(status === 204 ? undefined : isBuffer ? body : JSON.stringify(body));
}

const ok = (data) => ({ success: true, data });

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

const routes = [];
const route = (method, pattern, handler) => {
  const keys = [];
  const re = new RegExp(`^${pattern.replace(/:(\w+)/g, (_, k) => (keys.push(k), '([^/]+)'))}$`);
  routes.push({ method, re, keys, handler });
};

// --- auth
route('POST', '/user/signin', ({ body }) => {
  const match = users.find((u) => u.email?.toLowerCase() === String(body.email || '').toLowerCase() && u.password === body.password);
  if (!match) return [400, { message: 'Incorrect username or password.' }];
  return [200, { AccessToken: 'mock-access', IdToken: 'mock-id-token', RefreshToken: 'mock-refresh', ExpiresIn: 86400, TokenType: 'Bearer' }];
});
route('POST', '/user/refresh-token', () => [200, { AccessToken: 'mock-access', IdToken: 'mock-id-token', RefreshToken: 'mock-refresh', ExpiresIn: 86400, TokenType: 'Bearer' }]);
route('POST', '/user/auth', () => [200, user]);

// --- projects and reports (existing app routes)
route('GET', '/project/user/:id', () => [200, ok([project])]);
route('GET', '/project/:id', () => [200, ok(project)]);
route('GET', '/inspection/project/:id', () => [200, ok(inspections)]);
route('GET', '/projectDocument/project/:id', () => [200, ok([])]);
route('GET', '/presignedurl/project-media/:id', () => [200, []]);
route('GET', '/report/getByProjectId/:id', () => [200, ok(reports.map((r) => ({ ...r, project_id: project.id })))]);
route('GET', '/reportTemplate/getByCompanyId', () => [
  200,
  ok([
    ...templates.map((t) => {
      tickProfile(t);
      return {
        id: t.id,
        name: t.name,
        create_time: t.createdAt,
        profile_status: t.profile?.status || 'none',
        profile_job_id: t.profile?.jobId || null,
        user: { first_name: user.first_name, last_name: user.last_name },
      };
    }),
    // A template from the older PDF / skill flow.
    { id: 'tmpl_skill_daily', name: 'Daily site report', create_time: '2026-06-12T15:00:00.000Z', profile_status: null, user: { first_name: user.first_name, last_name: user.last_name } },
  ]),
]);

// --- span-report: writing reports
route('GET', '/span-report/report-templates', () => [200, { templates: templates.filter((t) => t.profile?.status === 'ready').map(templateJson) }]);
route('GET', '/span-report/inspections', () => [
  200,
  {
    inspections: inspections.map((i) => ({
      id: i.id,
      name: i.name,
      projectName: project.name,
      inspectionDate: i.create_time,
      inspectorName: 'Maya Chen',
      documents: 1,
      pages: 2,
      findings: 6,
      photos: 4,
    })),
  },
]);
route('GET', '/span-report/runs', () => [200, { runs: runs.map(runSummary) }]);
route('POST', '/span-report/runs', ({ body }) => {
  const run = newRun({ inspectionId: body.inspectionId, templateId: body.templateId });
  log(`run started ${run.jobId}`);
  return [201, { run: runSummary(run) }];
});
const findRun = (jobId) => runs.find((r) => r.jobId === jobId);
route('GET', '/span-report/runs/:jobId', ({ jobId }) => {
  const run = findRun(jobId);
  return run ? [200, runDetail(run)] : [404, { error: 'Run not found' }];
});
route('GET', '/span-report/runs/:jobId/events', ({ jobId }) => {
  const run = findRun(jobId);
  if (!run) return [404, { error: 'Run not found' }];
  tickRun(run);
  const phase = runPhase(run);
  return [200, { status: run.status, nextIndex: phase.index + 1, activities: [], phase: { key: phase.key }, phaseStartedAt: phase.started, lastEventAt: now() }];
});
route('GET', '/span-report/runs/:jobId/file', ({ jobId, query }) => {
  const run = findRun(jobId);
  const rel = String(query.get('path') || '');
  if (!run || !rel.startsWith('generated/')) return [404, { error: 'Not found' }];
  const file = path.join(run.dir, rel.slice('generated/'.length));
  if (!fs.existsSync(file)) return [404, { error: `${rel} not found` }];
  return [200, { url: addStorage(file, typeOf(file)) }];
});
route('GET', '/span-report/runs/:jobId/fill-map', ({ jobId }) => {
  const run = findRun(jobId);
  if (!run || run.status !== 'ready') return [404, { error: 'This report has no fill map yet' }];
  const edited = fs.existsSync(path.join(run.dir, 'fill_map.edited.json'));
  return [
    200,
    {
      jobId: run.jobId,
      templateId: run.templateId,
      templateName: run.templateName,
      source: edited ? 'edited' : 'generated',
      fillMap: currentFillMap(run),
      edit: edited ? run.edit : null,
      layout: { title: spec.report_type || null, sections: [], labels: {} },
      blanks: [],
      photos: [],
      album: album(run),
    },
  ];
});
route('POST', '/span-report/runs/:jobId/edit', ({ jobId, body }) => {
  const run = findRun(jobId);
  if (!run) return [404, { error: 'Run not found' }];
  if (run.edit?.status === 'rebuilding') return [409, { error: 'The previous save is still being applied; try again in a moment' }];
  fs.writeFileSync(path.join(run.dir, 'fill_map.edited.json'), JSON.stringify(body.fillMap, null, 2));
  run.edit = { status: 'rebuilding', savedAt: now(), basedOn: 'generated/fill_map.json', report: null, error: null };
  rebuild(run);
  return [200, { ...run.edit, fillMap: 'generated/fill_map.edited.json' }];
});
route('GET', '/span-report/runs/:jobId/photo', ({ jobId, query }) => {
  const run = findRun(jobId);
  const file = run ? photoFile(run, String(query.get('path') || '')) : null;
  return file && fs.existsSync(file) ? [200, { url: addStorage(file, typeOf(file)) }] : [404, { error: 'Photo not found' }];
});
route('POST', '/span-report/runs/:jobId/photo/upload-url', ({ jobId, body }) => {
  const run = findRun(jobId);
  if (!run) return [404, { error: 'Run not found' }];
  const ext = String(body.contentType).includes('png') ? '.png' : '.jpg';
  const name = `photo_${Date.now()}${ext}`;
  const key = `upload/${run.jobId}/${name}`;
  storage.set(key, { file: path.join(run.dir, 'edits', 'photos', name), type: body.contentType, writable: true });
  return [200, { upload: { url: `http://localhost:${PORT}/storage/${key}`, headers: { 'Content-Type': body.contentType } }, path: `generated/edits/photos/${name}` }];
});
route('POST', '/span-report/jobs/:jobId', ({ jobId, body }) => {
  const run = findRun(jobId);
  if (run && body.action === 'cancel') run.status = 'cancelled';
  const job = profileJobs.find((j) => j.jobId === jobId);
  if (job && body.action === 'cancel') job.status = 'cancelled';
  return [200, { ok: true }];
});

// --- span-report: building templates
route('GET', '/span-report/templates', () => [200, { templates: templates.map(templateJson) }]);
route('POST', '/span-report/templates', ({ body }) => {
  const t = { id: id('tmpl'), name: body.name || 'Untitled template', createdAt: now(), examples: [], profile: { status: 'none' }, dir: null };
  templates.unshift(t);
  return [201, { template: templateJson(t) }];
});
const findTemplate = (tid) => templates.find((t) => t.id === tid);
route('GET', '/span-report/templates/:tid', ({ tid }) => {
  const t = findTemplate(tid);
  if (!t) return [404, { error: 'Template not found' }];
  tickProfile(t);
  const job = profileJobs.find((j) => j.jobId === t.profile?.jobId);
  const ready = t.profile?.status === 'ready';
  return [
    200,
    {
      template: templateJson(t),
      job: job ? { jobId: job.jobId, status: job.status, createdAt: job.createdAt, clarifications: [] } : null,
      pack: ready
        ? { template: 'template.docx', instructions: 'instructions.md', styleGuide: 'style-guide.md', uncertaintyReport: 'uncertainty-report.md', referencePages: [] }
        : {},
      timing: { typicalMinutes: 12, maxMinutes: 30 },
    },
  ];
});
route('POST', '/span-report/templates/:tid/examples/upload-url', ({ tid, body }) => {
  const key = `upload/${tid}/${id('example')}-${String(body.name || 'example').replace(/[^\w.-]/g, '_')}`;
  storage.set(key, { file: path.join(WORK, key.replace(/\//g, '_')), type: body.contentType, writable: true });
  return [200, { upload: { url: `http://localhost:${PORT}/storage/${key}`, headers: { 'Content-Type': body.contentType || 'application/octet-stream' } }, pathname: key }];
});
route('POST', '/span-report/templates/:tid/examples', ({ tid, body }) => {
  const t = findTemplate(tid);
  if (!t) return [404, { error: 'Template not found' }];
  t.examples.push({ name: body.name, pathname: body.pathname, size: body.size || 0 });
  return [200, { template: templateJson(t) }];
});
route('DELETE', '/span-report/templates/:tid/examples', ({ tid, query }) => {
  const t = findTemplate(tid);
  if (t) t.examples = t.examples.filter((e) => e.pathname !== query.get('pathname'));
  return [200, { ok: true }];
});
route('POST', '/span-report/templates/:tid/profile', ({ tid }) => {
  const t = findTemplate(tid);
  if (!t) return [404, { error: 'Template not found' }];
  const job = { jobId: id('pjob'), status: 'running', createdAt: now(), startedMs: Date.now() };
  profileJobs.push(job);
  t.profile = { status: 'running', jobId: job.jobId };
  log(`profile started ${job.jobId} for ${t.name}`);
  return [201, { job: { jobId: job.jobId, status: 'running', createdAt: job.createdAt, clarifications: [] } }];
});
route('GET', '/span-report/jobs/:jobId/events', ({ jobId }) => {
  const job = profileJobs.find((j) => j.jobId === jobId);
  if (!job) return [404, { error: 'Job not found' }];
  const t = templates.find((x) => x.profile?.jobId === jobId);
  if (t) tickProfile(t);
  const phase = profilePhase(job);
  return [200, { status: job.status, sessionStarted: true, nextIndex: phase.index + 1, activities: [], phase: { key: phase.key }, phaseStartedAt: phase.started, lastEventAt: now() }];
});
route('GET', '/span-report/templates/:tid/files', ({ tid, query }) => {
  const t = findTemplate(tid);
  const rel = String(query.get('path') || '');
  if (!t?.dir || rel.includes('..')) return [404, { error: 'Not found' }];
  const editedFile = path.join(WORK, `${tid}-${rel}`);
  const file = fs.existsSync(editedFile) ? editedFile : path.join(t.dir, rel);
  return fs.existsSync(file) ? [200, { url: addStorage(file, typeOf(file)) }] : [404, { error: `${rel} not found` }];
});
route('PUT', '/span-report/templates/:tid/files', ({ tid, query, body }) => {
  const rel = String(query.get('path') || '');
  fs.writeFileSync(path.join(WORK, `${tid}-${rel}`), Buffer.from(String(body.contentBase64 || ''), 'base64'));
  return [200, { ok: true, path: rel }];
});

const server = http.createServer(async (req, res) => {
  const started = Date.now();
  if (process.env.MOCK_LOG) res.on('finish', () => log(`${req.method} ${req.url.slice(0, 120)} ${res.statusCode} ${Date.now() - started}ms`));
  try {
    if (req.method === 'OPTIONS') return send(res, 204, {});
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const pathname = url.pathname.replace(/\/+$/, '') || '/';

    if (pathname.startsWith('/storage/')) {
      const key = decodeURIComponent(pathname.slice('/storage/'.length));
      const entry = storage.get(key);
      if (!entry) return send(res, 404, { error: 'No such object' });
      if (req.method === 'PUT' && entry.writable) {
        fs.mkdirSync(path.dirname(entry.file), { recursive: true });
        fs.writeFileSync(entry.file, await readBody(req));
        return send(res, 200, { ok: true });
      }
      if (!fs.existsSync(entry.file)) return send(res, 404, { error: 'Missing file' });
      return send(res, 200, fs.readFileSync(entry.file), { 'Content-Type': entry.type });
    }

    const raw = await readBody(req);
    let body = {};
    try {
      body = raw.length ? JSON.parse(raw.toString('utf8')) : {};
    } catch {
      body = {};
    }
    for (const r of routes) {
      if (r.method !== req.method) continue;
      const m = r.re.exec(pathname);
      if (!m) continue;
      const params = Object.fromEntries(r.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])]));
      const [status, payload] = await r.handler({ ...params, body, query: url.searchParams });
      return send(res, status, payload);
    }
    log(`unmocked ${req.method} ${pathname}`);
    return send(res, 200, req.method === 'GET' ? ok([]) : ok({}));
  } catch (error) {
    log(`error ${req.method} ${req.url}: ${error.stack || error}`);
    return send(res, 500, { error: String(error.message || error) });
  }
});

seedRun();
server.listen(PORT, () => log(`Span mock API on http://localhost:${PORT} (fixtures ${FIXTURES})`));

// Optional: serve a `flutter build web` output too (--static build/web).
if (args.static) {
  const root = path.resolve(args.static);
  const staticPort = Number(args['static-port'] || 5180);
  http
    .createServer((req, res) => {
      const url = new URL(req.url, `http://localhost:${staticPort}`);
      let file = path.join(root, decodeURIComponent(url.pathname));
      if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, 'index.html');
      res.writeHead(200, { 'Content-Type': typeOf(file) === 'application/octet-stream' ? staticType(file) : typeOf(file), 'Cache-Control': 'no-store' });
      fs.createReadStream(file).pipe(res);
    })
    .listen(staticPort, () => log(`App (static ${root}) on http://localhost:${staticPort}`));
}

function staticType(file) {
  return (
    {
      '.html': 'text/html; charset=utf-8',
      '.js': 'text/javascript',
      '.mjs': 'text/javascript',
      '.css': 'text/css',
      '.wasm': 'application/wasm',
      '.svg': 'image/svg+xml',
      '.ttf': 'font/ttf',
      '.otf': 'font/otf',
      '.ico': 'image/x-icon',
      '.map': 'application/json',
    }[path.extname(file).toLowerCase()] || 'application/octet-stream'
  );
}
