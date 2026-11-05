import fs from 'node:fs';
import path from 'node:path';
import { prepareHtml, run, args, SKILL } from './prepare_html.mjs';

try {
  const options = args(process.argv.slice(2));
  if (!options.input || !options.out) throw new Error('Usage: node render_html.mjs --input deck.json --out <new-deck-directory> [--dashi <skill-root>] [--work-dir <isolated-directory>]');
  const input = path.resolve(options.input), out = path.resolve(options.out);
  if (fs.existsSync(out)) throw new Error('Output already exists; use a new deck directory to preserve browser edits.');
  const templates = JSON.parse(fs.readFileSync(path.join(SKILL, 'assets/html/templates.json'), 'utf8'));
  const spec = JSON.parse(fs.readFileSync(input, 'utf8'));
  if (!spec.title?.trim() || !Array.isArray(spec.slides) || !spec.slides.length) throw new Error('A title and nonempty slides array are required');
  const ids = new Set();
  const slides = spec.slides.map((slide, i) => {
    const template = templates.find(page => page.name === slide.type);
    if (!template) throw new Error(`Unknown NJU page type: ${slide.type}`);
    const id = slide.id || `page-${i + 1}`;
    if (typeof id !== 'string' || !/^[a-z][a-z0-9-]{0,79}$/i.test(id)) throw new Error(`Page id must be 1–80 ASCII letters, numbers or hyphens: ${id}`);
    if (ids.has(id)) throw new Error(`Duplicate page id: ${id}`);
    ids.add(id);
    const allowed = new Set(template.fields.map(field => field.key));
    const props = Object.fromEntries([...allowed].map(key => [key, '']));
    for (const [key, value] of Object.entries(slide.fields || {})) {
      if (!allowed.has(key) || typeof value !== 'string') throw new Error(`Invalid text field ${key} on ${id}`);
      props[key] = value;
    }
    if (!props.PAGE_TITLE.trim()) throw new Error(`Missing PAGE_TITLE on ${id}`);
    if (allowed.has('PAGE_NUM')) props.PAGE_NUM = String(i + 1);
    if (slide.type.startsWith('chart_')) {
      const chart = slide.chart;
      if (!chart || !Array.isArray(chart.categories) || chart.categories.length < 1 || chart.categories.length > 6 || !chart.categories.every(value => typeof value === 'string' && value.trim())) throw new Error(`Chart requires 1–6 category labels on ${id}`);
      if (!Array.isArray(chart.series) || chart.series.length < 1 || chart.series.length > 3 || (slide.type === 'chart_combo' && chart.series.length !== 2)) throw new Error(`Invalid chart series on ${id}`);
      props.categoryCount = chart.categories.length;
      props.seriesCount = chart.series.length;
      chart.categories.forEach((value, c) => { props[`CHART_CAT_${c + 1}`] = value; });
      chart.series.forEach((series, s) => {
        if (typeof series.name !== 'string' || !series.name.trim() || !Array.isArray(series.values) || series.values.length !== chart.categories.length || !series.values.every(Number.isFinite)) throw new Error(`Chart series must have a name and aligned finite numeric values on ${id}`);
        props[`CHART_SERIES_${s + 1}`] = series.name;
        series.values.forEach((value, c) => { props[`CHART_VALUE_${s + 1}_${c + 1}`] = String(value); });
      });
      if (!props.SOURCE.trim() || (slide.type === 'chart_combo' && (!props.AXIS_Y.trim() || !props.AXIS_Y2.trim()))) throw new Error(`Chart requires a source and combo axis units on ${id}`);
    }
    if (slide.type === 'table') {
      const table = slide.table;
      if (!table || !Array.isArray(table.headers) || table.headers.length < 1 || table.headers.length > 5 || !table.headers.every(value => typeof value === 'string' && value.trim()) || !Array.isArray(table.rows) || table.rows.length < 1 || table.rows.length > 6) throw new Error(`Table requires 1–5 headers and 1–6 rows on ${id}`);
      props.columnCount = table.headers.length;
      props.rowCount = table.rows.length;
      table.headers.forEach((value, c) => { props[`TABLE_HEAD_${c + 1}`] = value; });
      table.rows.forEach((row, r) => {
        if (!Array.isArray(row) || row.length !== table.headers.length || !row.every(value => typeof value === 'string' || (typeof value === 'number' && Number.isFinite(value)))) throw new Error(`Invalid table row on ${id}`);
        row.forEach((value, c) => { props[`TABLE_CELL_${r + 1}_${c + 1}`] = String(value); });
      });
    }
    if (slide.image) {
      if (slide.type !== 'two_col' || typeof slide.image !== 'string') throw new Error(`Images are supported only on two_col pages: ${id}`);
      const image = path.resolve(path.dirname(input), slide.image);
      if (!/\.(png|jpe?g|webp)$/i.test(image) || !fs.statSync(image).isFile()) throw new Error(`Unsupported local image: ${image}`);
      props.FIGURE_SRC = `assets/user-media/${id}${path.extname(image).toLowerCase()}`;
      slide.stagedImage = image;
    }
    return { id, key: id, layout: `nju_${slide.type}`, props };
  });
  if (spec.slides.filter(slide => slide.type === 'cover').length !== 1) throw new Error('An NJU deck must contain exactly one cover');
  console.error('Preparing isolated Dashi runtime…');
  const runtime = prepareHtml({ dashi: options.dashi, home: options.home, workDir: options['work-dir'] });
  const inDashi = path.relative(runtime.dashi_root, out);
  if (!path.isAbsolute(inDashi) && inDashi !== '..' && !inDashi.startsWith('..' + path.sep)) throw new Error('Output must be outside the installed Dashi skill.');
  fs.mkdirSync(out, { recursive: true });
  fs.copyFileSync(input, path.join(out, 'source-deck.json'));
  const goal = path.join(out, 'goal.json');
  // shortcut: Dashi v2 requires four variants; use its existing single-layout path until it supports fixed single variants.
  fs.writeFileSync(goal, JSON.stringify({ title: spec.title, goal: spec.title, themePack: 'nju', language: spec.language || 'zh', slides }, null, 2));
  const html = path.join(out, 'ppt/index.html');
  console.error('Rendering NJU HTML…');
  console.log(run(process.execPath, [path.join(runtime.project, 'node_modules/tsx/dist/cli.mjs'), path.join(runtime.project, 'scripts/render-goal-deck.jsx'), goal, html], { cwd: out }));
  const nju = path.join(out, 'ppt/assets/nju');
  for (const name of ['images', 'icons']) fs.cpSync(path.join(SKILL, 'assets/nju-academic-ginkgo', name), path.join(nju, name), { recursive: true });
  for (let i = 0; i < spec.slides.length; i++) {
    const slide = spec.slides[i];
    if (!slide.stagedImage) continue;
    const target = path.join(out, 'ppt', slides[i].props.FIGURE_SRC);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(slide.stagedImage, target);
  }
  for (const script of ['validate-swiss-deck.mjs', 'validate-goal-copy.mjs']) console.log(run(process.execPath, [path.join(runtime.project, 'scripts', script), ...(script.includes('goal-copy') ? [goal, html] : [html])], { cwd: runtime.project }));
  fs.writeFileSync(path.join(out, 'runtime.json'), JSON.stringify(runtime, null, 2) + '\n');
  console.log(JSON.stringify({ html, runtime: runtime.project, preview: `node "${path.join(runtime.project, 'scripts/start-preview-server.mjs')}" "${path.dirname(html)}" 5200` }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
