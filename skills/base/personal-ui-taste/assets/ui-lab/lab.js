/* UI Taste Lab: deterministic demo data, shared components and interactions. */
"use strict";

const $ = (s, e = document) => e.querySelector(s);
const $$ = (s, e = document) => [...e.querySelectorAll(s)];
const ce = (t, c, h) => { const n = document.createElement(t); if (c) n.className = c; if (h != null) n.innerHTML = h; return n; };
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ---------- 演示数据：科研实验工作台 ---------- */
const SERVERS = ["全部节点", "gpu-01", "gpu-02", "gpu-03"];
let currentServer = SERVERS[0], currentMetric = "eval_loss";
const SERIES = [
  { name: "baseline", color: "var(--c3)" },
  { name: "ours-r1", color: "var(--c1)" },
  { name: "ours-r2", color: "var(--c2)" },
];
const XN = 24;
let seriesData = SERIES.map((s, i) =>
  Array.from({ length: XN }, (_, x) => 2.4 - x * 0.055 - i * 0.12 + Math.sin(x * (0.7 + i * 0.23)) * 0.09 + (i === 0 ? 0.05 : 0)));
const BARS = [["A100-80G", 71], ["H800", 92], ["L40S", 48], ["4090", 39], ["Ascend-910B", 64]];
const STRIP = Array.from({ length: 72 }, (_, i) => (i % 17 === 5 ? 2 : i % 11 === 4 ? 1 : 0)); // 0 ok 1 warn 2 bad
const RUNS = [
  ["exp-0912-swa", "eval_loss 1.208 · 6.2h", 0], ["exp-0910-moe", "eval_loss 1.226 · 11.4h", 0],
  ["exp-0908-base", "eval_loss 1.301 · 8.1h", 1], ["exp-0905-dpo", "eval_loss 1.244 · 3.7h", 0],
  ["exp-0902-sft", "eval_loss 1.352 · 9.5h", 2], ["exp-0830-pre", "eval_loss 1.418 · 21.2h", 0],
];
const TABLE = [
  ["Alex", "exp-0912-swa", "训练", "6×A100", "37.2 GPU·h", "¥ 1,860", "gpu-01", "c4-zh", "运行中"],
  ["Robin", "exp-0910-moe", "训练", "8×H800", "91.2 GPU·h", "¥ 5,472", "gpu-02", "fineweb", "已完成"],
  ["Alex", "exp-0908-base", "评估", "2×L40S", "3.1 GPU·h", "¥ 93", "gpu-03", "c4-zh", "排队中"],
  ["Casey", "exp-0905-dpo", "训练", "4×A100", "14.8 GPU·h", "¥ 740", "gpu-01", "wiki-zh", "已完成"],
  ["Queue", "exp-0902-sft", "训练", "6×4090", "57.0 GPU·h", "¥ 1,140", "gpu-02", "fineweb", "失败"],
  ["Robin", "exp-0830-pre", "训练", "8×Ascend", "169.6 GPU·h", "¥ 6,784", "gpu-03", "code-parrot", "已完成"],
  ["Casey", "exp-0908-base", "导出", "1×L40S", "0.4 GPU·h", "¥ 12", "gpu-03", "c4-zh", "已完成"],
];
const icon = (n) => `<span class="ic" aria-hidden="true">${ICONS[n] || ""}</span>`;
const brand = (n) => `<span class="brand-icon" aria-hidden="true">${BRANDS[n]}</span>`;
const esc = (s) => String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const THEMES = [
  ["shadcn-neutral", "Shadcn Neutral", "中性主操作、精细边界、统一控件比例 · 新实现待目验"],
  ["modern-saas", "Modern SaaS · 亮蓝", "深色导航、电光蓝、鲜艳状态灯带"],
  ["bespoke", "Bespoke · 观测站", "蓝图网格、仪器铭牌、IBM Plex 字体"],
  ["bento", "Bento · 预览卡片", "大圆角表面、紧凑元信息、轻盈预览"],
  ["swiss", "Swiss · 网格", "直角、发丝线、对齐与字重层次"],
  ["aurora-glass", "Glass · 平色玻璃", "去渐变，保留透明材质与清楚的文字层次"],
  ["soft-ui", "Soft UI · 降亮版", "低亮画布、Nunito 圆润字形、柔和层次 · 待复验"],
  ["baseline", "旧基线 · 对照", "历史视觉 tokens，在同一骨架上比较"],
  ["layered", "海拔阴影 · 技法样本", "四级阴影对照，不列入正式主题选择"],
];

/* ---------- 页面骨架 ---------- */
document.body.innerHTML = `
<a class="skip-link" href="#overview">跳到工作台内容</a>
<div class="lab-bar" aria-label="实验室主题切换">
  <a class="lab-title" href="#overview" style="text-decoration:none">${icon("palette")}<span>UI Taste Lab</span></a>
  <span class="lab-version">同一内容 · 切换风格</span>
   <div class="lab-theme"><button class="btn icon-btn" id="prevTheme" aria-label="上一个主题" title="上一个主题">${icon("left")}</button>
  <select class="inp" id="themeSelect" aria-label="选择主题">${THEMES.map(t=>`<option value="${t[0]}">${t[1]}</option>`).join("")}</select>
   <button class="btn icon-btn" id="nextTheme" aria-label="下一个主题" title="下一个主题">${icon("arrow")}</button></div>
</div>
<div class="app">
  <aside class="side">
    <div class="brand"><span class="brand-dot">${icon("layers")}</span><span class="brand-name">Orbit</span></div>
    <div class="workspace"><span class="avatar">R</span><div>Research workspace<small>个人工作空间 · 演示</small></div></div>
    <nav class="nav" aria-label="工作台导航">
      <p class="nav-caption">Workspace</p>
      <a class="nav-item is-active" href="#overview" aria-current="location" aria-label="概览">${icon("grid")}<span>概览</span></a>
      <a class="nav-item" href="#metrics" aria-label="实验指标">${icon("chart")}<span>实验指标</span><span class="nav-count">03</span></a>
      <a class="nav-item" href="#runs" aria-label="运行记录">${icon("list")}<span>运行记录</span><span class="nav-count">07</span></a>
      <a class="nav-item" href="#previews" aria-label="实验预览">${icon("layers")}<span>实验预览</span></a>
      <a class="nav-item" href="#components" aria-label="组件样本">${icon("gear")}<span>组件样本</span></a>
      <a class="nav-item" href="#design" aria-label="字体与色阶">${icon("palette")}<span>字体与色阶</span></a>
    </nav>
    <div class="side-foot"><span class="dot ok"></span>worker · 已连接</div>
    <div class="profile"><span class="avatar">A</span><div>Alex Chen<div class="hint">Research team</div></div></div>
  </aside>
  <main class="main">
    <header class="top">
      <div class="crumb">Workspace &nbsp; / &nbsp; <b>Overview</b></div>
      <label class="search">${icon("search")}<input id="runSearch" aria-label="搜索运行记录" placeholder="搜索运行记录…" type="search" /></label>
      <span class="avatar">AC</span>
    </header>
    <div class="page-heading" id="overview"><div><h1>实验工作台</h1><p>从趋势到运行记录，观察每一次进展。</p></div><div class="btn-row"><button class="btn" id="exportBtn">${icon("down")}导出记录</button><button class="btn primary" id="newExp">${icon("plus")}新建实验</button></div></div>
    <div class="overview-toolbar"><div class="seg" id="serverSeg" aria-label="节点筛选"></div><span class="hint">${icon("clock")} 固定演示数据 · 过去 24 小时</span></div>
    <div class="kpis" id="kpis"></div>
    <div class="grid">
      <section class="panel span8" id="metrics"><header><h2>训练指标</h2><div class="seg sm" id="metricSeg" aria-label="曲线指标"></div></header><div class="chart-meta"><span id="chartScope">全部节点 · eval_loss</span><span>100–2,400 steps</span></div><div class="chart" id="lineChart"></div><div class="legend" id="legend"></div></section>
      <section class="panel span4"><header><h2>硬件吞吐参考</h2><span class="hint">samples / s</span></header><div class="chart" id="barChart"></div><div class="hint">相同演示负载下的设备吞吐，不代表真实测评。</div></section>
      <section class="panel span8"><header><h2>Worker uptime</h2><span class="badge ok">稳定运行</span></header><p class="hint" style="margin-bottom:16px">最近 72 小时 · 每小时采样</p><div class="strip" id="strip" tabindex="0" role="group" aria-label="72 小时状态，左右方向键查看"></div><div class="status-caption"><span>72 小时前</span><span>正常 · 降速 · 中断</span><span>现在</span></div></section>
      <section class="panel span4"><header><h2>运行队列</h2></header><ul class="sort" id="sortList"></ul></section>
      <section class="panel span8" id="runs"><header><h2>运行记录</h2><span class="hint">用户 · 实验 · 资源</span></header><div class="badges" id="activeFilters" style="margin-bottom:12px"></div><div class="table-wrap"><table class="tbl" id="tbl" aria-label="实验资源明细"></table></div><div class="table-summary" id="tableSummary" aria-live="polite"></div></section>
      <section class="panel span4"><header><h2>筛选与运行设置</h2></header><form class="form" id="form"></form></section>
      <section class="panel span12" id="previews"><header><h2>实验预览</h2><span class="hint">4 个实验</span></header><div class="cards" id="cards"></div></section>
      <section class="panel span12" id="components"><header><h2>组件细节</h2><span class="hint">按钮、字段、标签、摘要</span></header><div class="specimens" id="specimens"></div></section>
      <section class="panel span12" id="design"><header><h2>字体与色阶</h2><span class="hint">比例、层次与状态关系</span></header><div class="specimens" id="designSamples"></div></section>
      <footer class="panel span12 sources"><div class="theme-description" id="themeDescription"></div><p><a href="README.md">组件与源码索引</a> · <a href="SOURCES.md">来源与许可证</a> · <a id="themeSource" href="themes/shadcn-neutral.css">主题 CSS</a></p></footer>
    </div>
  </main>
</div>
<div class="tooltip" id="tip" hidden></div>
<div class="toast" id="toast" role="status" hidden></div>
<dialog id="newDialog" aria-labelledby="newTitle"><button class="btn ghost icon-btn close-dialog" aria-label="关闭" type="button">${icon("close")}</button><h2 id="newTitle">新建实验</h2><p class="dialog-desc">创建本次演示的运行记录，刷新页面恢复初始数据。</p><form id="newForm" class="form"><label class="fld">实验名称<input class="inp" name="name" required maxlength="48" placeholder="例如 exp-attention-r3" autofocus></label><label class="fld">数据集<select class="inp" name="dataset"><option>c4-zh</option><option>fineweb</option><option>wiki-zh</option><option>code-parrot</option></select></label><label class="fld">运行节点<select class="inp" name="server">${SERVERS.slice(1).map(s=>`<option>${s}</option>`).join("")}</select></label><div class="btn-row"><button class="btn cancel-dialog" type="button">取消</button><button class="btn primary" type="submit">创建实验 ${icon("arrow")}</button></div></form></dialog>
<dialog id="detailDialog" aria-labelledby="detailTitle"><button class="btn ghost icon-btn close-dialog" aria-label="关闭" type="button">${icon("close")}</button><h2 id="detailTitle"></h2><p class="dialog-desc" id="detailDesc"></p><div id="detailBody"></div><div class="btn-row"><button class="btn cancel-dialog" type="button">关闭</button></div></dialog>`;

/* ---------- 顶部：服务器分段选择 ---------- */
SERVERS.forEach((s, i) => {
  const b = ce("button", "seg-item" + (i === 0 ? " is-on" : ""), s);
  b.setAttribute("aria-pressed", i === 0);
  b.onclick = () => {
    currentServer = s;
    $$(".seg-item", $("#serverSeg")).forEach(x => { x.classList.toggle("is-on", x === b); x.setAttribute("aria-pressed", x === b); });
    renderTable(); refreshChart(); renderKpis();
  };
  $("#serverSeg").append(b);
});

/* ---------- 导航点击 ---------- */
$$(".nav-item").forEach((a) => (a.onclick = (e) => {
  $$(".nav-item").forEach((x) => { x.classList.remove("is-active"); x.removeAttribute("aria-current"); });
  a.classList.add("is-active");
  a.setAttribute("aria-current", "location");
}));
$$(".nav-item").forEach(a => a.title = a.getAttribute("aria-label"));

/* ---------- KPI 卡片 ---------- */
function renderKpis() {
$("#kpis").replaceChildren();
const rows = TABLE.filter(r => currentServer === SERVERS[0] || r[6] === currentServer);
const cost = rows.reduce((n, r) => n + Number(r[5].replace(/[^\d.]/g, "")), 0);
[["实验记录", String(rows.length), "当前节点 · 全部数据集", 0], ["运行中", String(rows.filter(r=>r[8] === "运行中").length), "当前节点 · 全部数据集", 1], ["排队中", String(rows.filter(r=>r[8] === "排队中").length), "等待资源分配", 0], ["累计费用", "¥ " + cost.toLocaleString("en-US"), "当前节点 · 演示记录", 0]].forEach(([k, v, d, up]) => {
  const c = ce("div", "kpi");
  c.innerHTML = `<div class="kpi-k">${k}</div><div class="kpi-v">${v}</div><div class="kpi-d ${up ? "up" : ""}">${d}</div><svg class="spark" viewBox="0 0 80 24" preserveAspectRatio="none"><path d="M0 ${14 + up * 4} Q 20 ${6 + up * 6}, 40 ${12 - up * 2} T 80 ${8 - up * 3}"/></svg>`;
  $("#kpis").append(c);
});
}
renderKpis();

/* ---------- 折线图：焦点联动（T05） ---------- */
const LW = 720, LH = 260, PAD = 34;
let yMin = Math.min(...seriesData.flat()) - 0.05, yMax = Math.max(...seriesData.flat()) + 0.05;
const px = (i) => PAD + (i / (XN - 1)) * (LW - PAD * 2);
const py = (v) => LH - PAD - ((v - yMin) / (yMax - yMin)) * (LH - PAD * 2);
const svgNS = "http://www.w3.org/2000/svg";
const svg = document.createElementNS(svgNS, "svg");
svg.setAttribute("viewBox", `0 0 ${LW} ${LH}`);
svg.classList.add("line-svg");
svg.setAttribute("tabindex", "0");
svg.setAttribute("role", "group");
svg.setAttribute("aria-label", "训练曲线：左右选时间，上下选系列，回车锁定，Esc 解除");
for (let g = 0; g <= 4; g++) { // 网格
  const y = PAD + (g / 4) * (LH - PAD * 2);
  const ln = document.createElementNS(svgNS, "line");
  ln.setAttribute("x1", PAD); ln.setAttribute("x2", LW - PAD); ln.setAttribute("y1", y); ln.setAttribute("y2", y);
  ln.setAttribute("class", "grid-ln"); svg.append(ln);
  const label = document.createElementNS(svgNS, "text");
  label.setAttribute("x", PAD - 7); label.setAttribute("y", y + 3); label.setAttribute("text-anchor", "end");
  label.setAttribute("class", "axis-label y-tick"); svg.append(label);
}
for (let i = 0; i < XN; i += 5) {
  const label = document.createElementNS(svgNS, "text");
  label.setAttribute("x", px(i)); label.setAttribute("y", LH - 12); label.setAttribute("text-anchor", "middle");
  label.setAttribute("class", "axis-label"); label.textContent = String((i + 1) * 100); svg.append(label);
}
const seriesEls = SERIES.map((s, si) => {
  const g = document.createElementNS(svgNS, "g");
  g.setAttribute("class", "series");
  g.dataset.s = si;
  const path = document.createElementNS(svgNS, "path");
  path.setAttribute("d", seriesData[si].map((v, i) => `${i ? "L" : "M"}${px(i).toFixed(1)} ${py(v).toFixed(1)}`).join(" "));
  path.setAttribute("class", "line-path");
  path.style.stroke = s.color;
  g.append(path);
  const dots = seriesData[si].map((v, i) => {
    const c = document.createElementNS(svgNS, "circle");
    c.setAttribute("cx", px(i)); c.setAttribute("cy", py(v)); c.setAttribute("r", 3);
    c.setAttribute("class", "line-dot"); c.style.fill = s.color; g.append(c); return c;
  });
  svg.append(g);
  return { g, dots, path };
});
const focusLn = document.createElementNS(svgNS, "line");
focusLn.setAttribute("class", "focus-ln"); focusLn.setAttribute("y1", PAD); focusLn.setAttribute("y2", LH - PAD); focusLn.setAttribute("visibility", "hidden");
svg.append(focusLn);
const hit = document.createElementNS(svgNS, "rect");
hit.setAttribute("x", PAD); hit.setAttribute("y", 0); hit.setAttribute("width", LW - PAD * 2); hit.setAttribute("height", LH);
hit.setAttribute("fill", "transparent");
svg.append(hit);
$("#lineChart").append(svg);

let locked = null, focused = null, visible = SERIES.map(() => true);
function setFocus(si, xi) {
  focused = si == null ? null : { series: SERIES[si].name, x: xi };
  seriesEls.forEach((el, i) => {
    el.g.classList.toggle("is-dim", si != null && i !== si);
    el.g.classList.toggle("is-focus", i === si);
    el.dots.forEach((d, x) => d.classList.toggle("is-hot", i === si && x === xi));
  });
  $$(".legend-chip").forEach((ch, i) => {
    ch.classList.toggle("is-dim", si != null && i !== si);
    ch.classList.toggle("is-focus", i === si);
  });
  if (si == null) { $("#tip").hidden = true; focusLn.setAttribute("visibility", "hidden"); return; }
  focusLn.setAttribute("visibility", "visible");
  focusLn.setAttribute("x1", px(xi)); focusLn.setAttribute("x2", px(xi));
  const rows = SERIES.map((s, i) => !visible[i] ? "" :
    `<div class="tip-row ${i === si ? "hot" : ""}"><i style="background:${s.color}"></i>${s.name}<b>${seriesData[i][xi].toFixed(3)}</b></div>`).join("");
  const tip = $("#tip");
  tip.innerHTML = `<div class="tip-t">step ${(xi + 1) * 100}</div>${rows}`;
  tip.hidden = false;
  const r = svg.getBoundingClientRect();
  const cx = r.left + (px(xi) / LW) * r.width, cy = r.top + (py(seriesData[si][xi]) / LH) * r.height;
  placeTip(cx, cy);
}
function pointAt(e) {
  const r = svg.getBoundingClientRect();
  const xi = Math.round(((e.clientX - r.left) / r.width * LW - PAD) / (LW - PAD * 2) * (XN - 1));
  const xc = Math.max(0, Math.min(XN - 1, xi));
  let best = null, bd = Infinity;
  // 按纵向距离选最近可见系列
  SERIES.forEach((s, i) => {
    if (!visible[i]) return;
    const cy = r.top + (py(seriesData[i][xc]) / LH) * r.height;
    if (Math.abs(e.clientY - cy) < bd) { bd = Math.abs(e.clientY - cy); best = i; }
  });
  return [best, xc];
}
hit.addEventListener("mousemove", (e) => {
  if (!locked) setFocus(...pointAt(e));
});
hit.addEventListener("mouseleave", () => { if (!locked) setFocus(null); });
function toggleLock(si, xi) {
  if (si == null) return;
  const same = locked?.series === SERIES[si].name && locked.x === xi;
  locked = same ? null : { series: SERIES[si].name, x: xi };
  setFocus(same ? null : si, xi);
}
hit.addEventListener("click", e => toggleLock(...pointAt(e)));
svg.addEventListener("keydown", e => {
  const keys = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Enter", " ", "Escape"];
  if (!keys.includes(e.key)) return;
  e.preventDefault();
  const shown = SERIES.map((s, i) => i).filter(i => visible[i]);
  if (!shown.length) return;
  let si = focused ? SERIES.findIndex(s => s.name === focused.series) : shown[0];
  let xi = focused?.x ?? XN - 1;
  if (e.key === "Escape") { locked = null; setFocus(null); return; }
  if (e.key === "Enter" || e.key === " ") { toggleLock(si, xi); return; }
  if (e.key === "ArrowLeft") xi = Math.max(0, xi - 1);
  if (e.key === "ArrowRight") xi = Math.min(XN - 1, xi + 1);
  if (e.key === "ArrowUp" || e.key === "ArrowDown") si = shown[(shown.indexOf(si) + (e.key === "ArrowDown" ? 1 : shown.length - 1)) % shown.length];
  locked = null; setFocus(si, xi);
});
SERIES.forEach((s, i) => {
  const ch = ce("button", "legend-chip", `<i style="background:${s.color}"></i>${s.name}`);
  ch.setAttribute("aria-pressed", "true");
  ch.onclick = () => {
    locked = null; setFocus(null);
    visible[i] = !visible[i];
    seriesEls[i].g.style.display = visible[i] ? "" : "none";
    ch.classList.toggle("is-off", !visible[i]);
    ch.setAttribute("aria-pressed", visible[i]);
  };
  ch.onmouseenter = () => { if (!locked && visible[i]) setFocus(i, XN - 1); };
  ch.onmouseleave = () => { if (!locked) setFocus(null); };
  $("#legend").append(ch);
});
function refreshChart() {
  locked = null; setFocus(null);
  const factor = currentMetric === "train_loss" ? .76 : currentMetric === "grad_norm" ? .36 : 1;
  const offset = Math.max(0, SERVERS.indexOf(currentServer)) * .12;
  seriesData = SERIES.map((s, i) => Array.from({length: XN}, (_, x) =>
    (2.4 - x * .055 - i * .12 + Math.sin(x * (.7 + i * .23)) * .09 + offset) * factor));
  yMin = Math.min(...seriesData.flat()) - .05; yMax = Math.max(...seriesData.flat()) + .05;
  seriesEls.forEach((el, si) => {
    el.path.setAttribute("d", seriesData[si].map((v, i) => `${i ? "L" : "M"}${px(i)} ${py(v)}`).join(" "));
    el.dots.forEach((dot, i) => dot.setAttribute("cy", py(seriesData[si][i])));
  });
  $$(".y-tick").forEach((el, i) => el.textContent = (yMax - i / 4 * (yMax - yMin)).toFixed(1));
  $("#chartScope").textContent = `${currentServer} · ${currentMetric}`;
}
function placeTip(x, y) {
  const tip = $("#tip");
  const left = x + 14 + tip.offsetWidth > innerWidth - 12 ? x - tip.offsetWidth - 14 : x + 14;
  tip.style.left = Math.max(12, Math.min(left, innerWidth - tip.offsetWidth - 12)) + "px";
  tip.style.top = Math.max(8, Math.min(y - tip.offsetHeight - 12, innerHeight - tip.offsetHeight - 12)) + "px";
}
document.addEventListener("pointerdown", e => {
  if (!e.composedPath().includes($("#lineChart")) && !e.composedPath().includes($("#legend"))) { locked = null; setFocus(null); }
});
document.addEventListener("keydown", e => { if (e.key === "Escape") { locked = null; setFocus(null); } });
addEventListener("scroll", () => $("#tip").hidden = true, {passive: true});
addEventListener("resize", () => $("#tip").hidden = true);
refreshChart();

/* ---------- 柱状图 ---------- */
const bsvg = document.createElementNS(svgNS, "svg");
const BW = 320, BH = 220, bMax = Math.max(...BARS.map((b) => b[1]));
bsvg.setAttribute("viewBox", `0 0 ${BW} ${BH}`);
BARS.forEach(([n, v], i) => {
  const w = (BW - 60) / BARS.length, x = 40 + i * w + 6, h = (v / bMax) * (BH - 56);
  const r = document.createElementNS(svgNS, "rect");
  r.setAttribute("x", x); r.setAttribute("y", BH - 30 - h); r.setAttribute("width", w - 12); r.setAttribute("height", h);
  r.setAttribute("class", "bar"); r.style.fill = `var(--c${(i % 5) + 1})`;
  const t = document.createElementNS(svgNS, "text");
  t.setAttribute("x", x + (w - 12) / 2); t.setAttribute("y", BH - 12); t.setAttribute("class", "bar-lb"); t.textContent = n;
  const val = document.createElementNS(svgNS, "text");
  val.setAttribute("x", x + (w - 12) / 2); val.setAttribute("y", BH - 36 - h); val.setAttribute("class", "bar-val"); val.textContent = v;
  r.onmouseenter = r.onfocus = () => { const tip = $("#tip"); tip.innerHTML = `<div class="tip-t">${n}</div><div class="tip-row hot"><b>${v} samples/s</b></div>`; tip.hidden = false; const rr = r.getBoundingClientRect(); placeTip(rr.left, rr.top); };
  r.setAttribute("tabindex", "0"); r.setAttribute("role", "img"); r.setAttribute("aria-label", `${n}: ${v} samples/s`);
  r.onmouseleave = () => ($("#tip").hidden = true);
  r.onblur = r.onmouseleave;
  bsvg.append(r, t, val);
});
$("#barChart").append(bsvg);

/* ---------- 状态灯带 ---------- */
const ST = [["ok", "正常"], ["warn", "降速"], ["bad", "中断"]];
STRIP.forEach((s, i) => {
  const seg = ce("i", `seg ${ST[s][0]}`);
  seg.dataset.hour = i;
  seg.setAttribute("aria-label", `${72 - i} 小时前：${ST[s][1]}`);
  seg.onmouseenter = () => { const tip = $("#tip"); tip.innerHTML = `<div class="tip-t">${String(72 - i).padStart(2, "0")} 小时前</div><div class="tip-row hot"><b>${ST[s][1]}</b></div>`; tip.hidden = false; const r = seg.getBoundingClientRect(); placeTip(r.left, r.top); };
  seg.onmouseleave = () => ($("#tip").hidden = true);
  $("#strip").append(seg);
});
let stripIndex = 71;
$("#strip").onkeydown = e => {
  if (!["ArrowLeft", "ArrowRight"].includes(e.key)) return;
  e.preventDefault(); stripIndex = Math.max(0, Math.min(71, stripIndex + (e.key === "ArrowRight" ? 1 : -1)));
  const seg = $("#strip").children[stripIndex]; seg.onmouseenter();
  $("#strip").setAttribute("aria-label", `${seg.getAttribute("aria-label")}，左右方向键查看`);
};
$("#strip").onblur = () => $("#tip").hidden = true;

/* ---------- 拖拽排序列表 ---------- */
RUNS.forEach(([name, meta, st]) => {
  const li = ce("li", "sort-item");
  li.draggable = true;
   li.innerHTML = `<span class="handle" title="拖拽排序">${icon("drag")}</span><span class="sort-main"><b>${name}</b><small>${meta}</small></span><span class="badge ${ST[st][0]}">${ST[st][1]}</span><span class="queue-tools"><button type="button" aria-label="上移 ${name}" title="上移" data-move="up">${icon("up")}</button><button type="button" aria-label="下移 ${name}" title="下移" data-move="down">${icon("moveDown")}</button></span>`;
  $$("[data-move]", li).forEach(b => b.onclick = () => {
    const sibling = b.dataset.move === "up" ? li.previousElementSibling : li.nextElementSibling;
    if (!sibling) return;
    if (b.dataset.move === "up") sibling.before(li); else sibling.after(li);
    b.focus(); toast(`${name} 已${b.dataset.move === "up" ? "上" : "下"}移`);
  });
  $("#sortList").append(li);
});
let dragEl = null;
$$(".sort-item").forEach((li) => {
  li.addEventListener("dragstart", () => { dragEl = li; li.classList.add("is-drag"); });
  li.addEventListener("dragend", () => { dragEl = null; li.classList.remove("is-drag"); $$(".sort-item").forEach((x) => x.classList.remove("is-over")); });
  li.addEventListener("dragover", (e) => { e.preventDefault(); if (!dragEl || li === dragEl) return; const r = li.getBoundingClientRect(); li.parentNode.insertBefore(dragEl, e.clientY < r.top + r.height / 2 ? li : li.nextSibling); li.classList.add("is-over"); setTimeout(() => li.classList.remove("is-over"), 160); });
});

/* ---------- 表单 ---------- */
$("#form").innerHTML = `
  <label class="fld"><span>配置名称</span><input class="inp" name="configName" required value="daily-evaluation" /><small class="field-help">仅保存当前演示中的运行设置</small></label>
  <div class="fld"><span id="datasetLabel">记录筛选 · 数据集</span><div class="msel" id="msel"><button type="button" class="inp msel-btn" aria-expanded="false" aria-controls="datasetPop">全部数据集 ${icon("chev")}</button><div class="msel-pop" id="datasetPop" role="group" aria-labelledby="datasetLabel" hidden><input class="inp msel-search" type="search" aria-label="搜索数据集" placeholder="搜索数据集…"><span class="msel-empty" hidden>无匹配数据集</span></div></div></div>
  <div class="fld"><span>每日运行时间</span><div class="timepick"><select class="inp" id="tpH" aria-label="小时"></select><em>:</em><select class="inp" id="tpM" aria-label="分钟"></select><span class="hint">24 小时制</span></div></div>
  <label class="chk"><input name="archive" type="checkbox" checked />完成后自动归档</label>
  <label class="chk"><input name="notify" type="checkbox" />失败时通知</label>
  <div class="btn-row"><button class="btn primary" id="saveBtn" type="submit">保存设置</button><button class="btn ghost" type="button" id="resetFilters">重置筛选</button></div>`;
["eval_loss", "train_loss", "grad_norm"].forEach((m, i) => {
  const b = ce("button", "seg-item" + (i === 0 ? " is-on" : ""), m);
  b.setAttribute("aria-pressed", i === 0);
  b.onclick = () => { currentMetric = m; $$(".seg-item", $("#metricSeg")).forEach(x => { x.classList.toggle("is-on", x === b); x.setAttribute("aria-pressed", x === b); }); refreshChart(); };
  $("#metricSeg").append(b);
});
const DS = ["c4-zh", "fineweb", "wiki-zh", "code-parrot"];
const sel = new Set(DS.map((d, i) => i));
const pop = $(".msel-pop");
DS.forEach((d, i) => {
  const l = ce("label", "msel-item", `<input type="checkbox" ${sel.has(i) ? "checked" : ""}/>${d}`);
  $("input", l).onchange = (e) => { e.target.checked ? sel.add(i) : sel.delete(i); updateDatasets(); };
  pop.append(l);
});
function closeMenu(focus = false) { pop.hidden = true; $(".msel-btn").setAttribute("aria-expanded", "false"); if (focus) $(".msel-btn").focus(); }
$(".msel-btn").onclick = (e) => { e.stopPropagation(); pop.hidden = !pop.hidden; $(".msel-btn").setAttribute("aria-expanded", !pop.hidden); if (!pop.hidden) $(".msel-search").focus(); };
document.addEventListener("click", () => closeMenu());
document.addEventListener("keydown", e => { if (e.key === "Escape" && !pop.hidden) { e.preventDefault(); closeMenu(true); } });
$("#msel").addEventListener("focusout", e => { if (!e.currentTarget.contains(e.relatedTarget)) closeMenu(); });
pop.onclick = (e) => e.stopPropagation();
$(".msel-search").oninput = e => {
  $$(".msel-item").forEach(l => l.hidden = !l.textContent.toLowerCase().includes(e.target.value.toLowerCase()));
  $(".msel-empty").hidden = $$(".msel-item").some(l => !l.hidden);
};
for (let h = 0; h < 24; h++) $("#tpH").append(ce("option", "", String(h).padStart(2, "0")));
["00", "15", "30", "45"].forEach((m) => $("#tpM").append(ce("option", "", m)));
$("#tpH").value = "03";

/* ---------- Table filtering and removable conditions ---------- */
function filteredRows() {
  const query = $("#runSearch").value.toLowerCase().trim();
  return TABLE.filter(r => (currentServer === SERVERS[0] || r[6] === currentServer) && sel.has(DS.indexOf(r[7])) && r.join(" ").toLowerCase().includes(query));
}
function renderTable() {
  const rows = filteredRows();
  $("#tbl").innerHTML = `<thead><tr><th scope="col">用户</th><th scope="col">实验 / 数据集</th><th scope="col">状态</th><th scope="col">资源</th><th scope="col" class="num">时长</th><th scope="col" class="num">费用</th></tr></thead><tbody>${rows.length ? rows.map(r => `<tr><td><span class="row-user"><span class="avatar">${esc(r[0].slice(0, 1))}</span>${esc(r[0])}</span></td><td>${esc(r[1])}<div class="field-help">${esc(r[7])} · ${esc(r[6])} · ${esc(r[2])}</div></td><td><span class="badge ${r[8] === "失败" ? "bad" : r[8] === "排队中" ? "warn" : "ok"}">${r[8]}</span></td><td>${esc(r[3])}</td><td class="num">${esc(r[4])}</td><td class="num">${esc(r[5])}</td></tr>`).join("") : '<tr><td colspan="6" class="empty-cell">没有匹配记录。调整搜索条件或重置筛选。</td></tr>'}</tbody>`;
  $("#tableSummary").textContent = `显示 ${rows.length} / ${TABLE.length} 条记录 · 数据集筛选仅作用于此表`;
  $("#activeFilters").replaceChildren();
  if (sel.size < DS.length) DS.forEach((d, i) => {
    if (!sel.has(i)) return;
    const tag = ce("span", "filter-tag", `${d}<button type="button" aria-label="移除 ${d} 筛选">×</button>`);
    $("button", tag).onclick = () => { sel.delete(i); updateDatasets(); };
    $("#activeFilters").append(tag);
  });
  $('[href="#runs"] .nav-count').textContent = String(TABLE.length).padStart(2, "0");
}
function updateDatasets() {
  $(".msel-btn").innerHTML = `${sel.size === DS.length ? "全部数据集" : `已选 ${sel.size} 项`} ${icon("chev")}`;
  $$(".msel-item input").forEach((c, i) => c.checked = sel.has(i));
  renderTable();
}
$("#runSearch").oninput = renderTable;
$("#resetFilters").onclick = () => { $("#runSearch").value = ""; DS.forEach((d, i) => sel.add(i)); updateDatasets(); $("#serverSeg button").click(); };
renderTable();

/* ---------- 卡片画廊 ---------- */
[["exp-0912-swa", "Swin 注意力改造 · 训练中", "ok", "1.208"], ["exp-0910-moe", "MoE 路由实验 · 已完成", "info", "1.226"], ["exp-0908-base", "基线复现 · 已完成", "info", "1.301"], ["exp-0902-sft", "SFT 数据消融 · 失败", "bad", "1.352"]].forEach(([t, m, st, v], i) => {
  const c = ce("button", "card"); c.type = "button";
  c.innerHTML = `<div class="card-thumb"><svg viewBox="0 0 160 60" preserveAspectRatio="none" aria-hidden="true"><path d="M0 48 Q 30 ${34 + i * 2}, 60 40 T 120 30 T 160 22"/></svg></div><div class="card-body"><h3>${t}</h3><p>${m}</p><div class="card-foot"><span class="badge ${st}">${st === "ok" ? "训练中" : st === "bad" ? "失败" : "完成"}</span><span class="hint">eval_loss <b class="num" style="color:var(--text)">${v}</b></span></div></div>`;
  c.onclick = () => showDetail(t, m, `<div class="summary-rows"><div><span>最终 eval_loss</span><b class="num">${v}</b></div><div><span>观察范围</span><b>2,600 steps</b></div><div><span>训练环境</span><b>PyTorch · Python</b></div></div><p class="hint" style="margin-top:16px">固定演示数据，用于比较卡片与详情层次。</p>`);
  $("#cards").append(c);
});

/* ---------- Component specimens ---------- */
$("#specimens").innerHTML = `
<div class="specimen"><h3>按钮层级与状态</h3><div class="btn-row"><button class="btn primary" id="samplePrimary">${icon("check")}确认操作</button><button class="btn secondary" id="sampleSecondary">次要操作</button><button class="btn" id="sampleOutline">描边</button></div><div class="btn-row"><button class="btn ghost" id="sampleGhost">轻操作 ${icon("arrow")}</button><button class="btn danger" id="sampleDanger">移除标签</button><button class="btn" disabled>不可用</button></div><label class="fld" style="margin-top:18px">实验编号<input class="inp" id="invalidSample" value="exp demo" aria-invalid="true" aria-describedby="sampleError"><span class="error-text" id="sampleError">使用字母、数字与连字符，不含空格。</span></label><p>点击确认可看加载态；字段修改为 exp-demo 可看校验恢复。</p></div>
<div class="specimen"><h3>身份、状态与筛选</h3><div class="badges" style="margin-bottom:14px">${["python", "pytorch", "docker", "github"].map((b,i)=>`<span class="identity">${brand(b)}${["Python", "PyTorch", "Docker", "GitHub"][i]}</span>`).join("")}</div><div class="badges"><span class="badge ok">${icon("check")}已完成</span><span class="badge warn">${icon("clock")}排队中</span><span class="badge bad">${icon("close")}失败</span></div><div class="badges" id="sampleTags" style="margin-top:14px"><span class="filter-tag">GPU 节点<button aria-label="移除 GPU 节点示例标签">×</button></span><span class="filter-tag">最近 24h<button aria-label="移除最近 24h 示例标签">×</button></span></div><button class="btn ghost" id="restoreTags" style="margin-top:12px">恢复标签</button><p>品牌表示身份，颜色表示状态；示例标签可移除。</p></div>
<div class="specimen"><h3>批次摘要</h3><div class="summary-card"><div class="summary-title">${icon("layers")}Attention sweep <span class="badge info" style="margin-left:auto">Batch 07</span></div><div class="summary-body"><svg class="summary-ring" viewBox="0 0 100 100" role="img" aria-label="完成率 75%，12 个实验中完成 9 个"><circle class="track" cx="50" cy="50" r="40" fill="none" stroke-width="6"/><circle class="value" cx="50" cy="50" r="40" fill="none" stroke-width="6" stroke-dasharray="188.5 251.3" transform="rotate(-90 50 50)" stroke-linecap="round"/><text x="50" y="57">75%</text></svg><div class="summary-rows"><div><span>已完成</span><b>9 / 12</b></div><div><span>运行中</span><b>2</b></div><div><span>待运行</span><b>1</b></div></div></div><div class="status-caption"><span>最近 24 小时 · 完成率</span><button class="btn ghost" id="batchDetail">查看批次 ${icon("arrow")}</button></div></div><p>标题、范围、主要数字与明细互相解释；环形进度对应明确分母。</p></div>`;

const GRAY = ["#fcfcfc","#f9f9f9","#f0f0f0","#e8e8e8","#e0e0e0","#d9d9d9","#cecece","#bbbbbb","#8d8d8d","#838383","#646464","#202020"];
const BLUE = ["#fbfdff","#f4faff","#e6f4fe","#d5efff","#c2e5ff","#acd8fc","#8ec8f6","#5eb1ef","#0090ff","#0588f0","#0d74ce","#113264"];
function swatches(colors) { return `<div class="swatches">${colors.map((c,i)=>`<div class="swatch" style="background:${c};color:${i > 9 ? "#fff" : "#202020"}" title="Step ${i+1} · ${c}">${i+1}</div>`).join("")}</div>`; }
$("#designSamples").innerHTML = `
<div class="specimen type-sample"><h3>清楚，看见每一次变化。</h3><div style="font-weight:600">Research workspace / 实验工作台</div><p>中文明确回退至本机字体；英文和数字使用随页携带的 Inter、Nunito 或 IBM Plex Sans。</p><div class="type-numbers">12,840.68 <span style="font-size:13px;color:var(--text-2);font-weight:400">GPU·h</span></div><div class="hint" id="fontLabel"></div></div>
<div class="specimen"><h3>Radix Gray / Blue · 12 阶</h3>${swatches(GRAY)}${swatches(BLUE)}<div class="scale-roles"><span>1–2 背景</span><span>3–5 状态</span><span>6–8 边界</span><span>9–10 实色</span><span>11–12 文字</span></div><p>灰阶、强调、状态各司其职；色阶样本来自 Radix，页面主题有独立语义映射。</p></div>
<div class="specimen"><h3>工具与环境</h3>${[["github","Source repository","已同步"],["pytorch","Training engine","运行中"],["docker","Container runtime","就绪"]].map(([b,t,s])=>`<div class="integration-row">${brand(b)}<div>${b === "github" ? "GitHub" : b === "pytorch" ? "PyTorch" : "Docker"}<br><small>${t}</small></div><span class="badge ok">${s}</span></div>`).join("")}<p>品牌图标统一尺寸，保留独立的状态文字与色彩。</p></div>`;

/* ---------- Dialogs, controls and downloads ---------- */
function showDetail(title, desc, html) {
  $("#detailTitle").textContent = title; $("#detailDesc").textContent = desc;
  $("#detailBody").innerHTML = html; $("#detailDialog").showModal();
}
$$("dialog").forEach(d => {
  $$(".close-dialog, .cancel-dialog", d).forEach(b => b.onclick = () => d.close());
  d.addEventListener("click", e => { const r = d.getBoundingClientRect(); if (e.target === d && (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom)) d.close(); });
});
$("#newExp").onclick = () => $("#newDialog").showModal();
$("#newForm").onsubmit = e => {
  e.preventDefault(); const data = new FormData(e.currentTarget);
  const name = data.get("name").trim(); if (!name) return;
  TABLE.unshift(["Alex", name, "训练", "待分配", "0 GPU·h", "¥ 0", data.get("server"), data.get("dataset"), "排队中"]);
  $("#newDialog").close(); e.currentTarget.reset(); $("#resetFilters").click(); renderKpis();
  toast(`已创建 ${name}，可在运行记录中查看`);
};
$("#form").onsubmit = e => {
  e.preventDefault(); const data = new FormData(e.currentTarget);
  toast(`已保存 ${data.get("configName")} · 每日 ${$("#tpH").value}:${$("#tpM").value}`);
};
$("#exportBtn").onclick = () => {
  const rows = [["用户","实验","动作","资源","时长","费用","节点","数据集","状态"], ...filteredRows()];
  const csv = rows.map(r => r.map(v => `"${String(v).replace(/^[=+@-]/, "'$&").replaceAll('"','""')}"`).join(",")).join("\r\n");
  const url = URL.createObjectURL(new Blob(["\ufeff" + csv], {type:"text/csv;charset=utf-8"}));
  const a = document.createElement("a"); a.href = url; a.download = "orbit-demo-runs.csv"; a.click();
  setTimeout(()=>URL.revokeObjectURL(url), 1000);
};
$("#samplePrimary").onclick = async e => {
  const b = e.currentTarget, html = b.innerHTML; b.disabled = true; b.setAttribute("aria-busy", "true");
  b.innerHTML = `${icon("loader")}确认操作`;
  await new Promise(resolve => setTimeout(resolve, 800));
  b.innerHTML = html; b.disabled = false; b.removeAttribute("aria-busy"); toast("示例操作完成");
};
["sampleSecondary", "sampleOutline", "sampleGhost"].forEach(id => $("#"+id).onclick = e => toast(`${e.currentTarget.textContent.trim()} · 已触发`));
const tagHTML = $("#sampleTags").innerHTML;
$("#sampleTags").onclick = e => { const b = e.target.closest("button"); if (b) { const next = b.parentElement.nextElementSibling?.querySelector("button"); b.parentElement.remove(); (next || $("#restoreTags")).focus(); } };
$("#sampleDanger").onclick = () => { const tag = $("#sampleTags .filter-tag"); if (tag) { tag.remove(); toast("已移除一个示例标签"); } else toast("标签已全部移除，可点击恢复"); };
$("#restoreTags").onclick = () => $("#sampleTags").innerHTML = tagHTML;
$("#invalidSample").oninput = e => { const invalid = !/^[a-zA-Z0-9-]+$/.test(e.target.value); e.target.setAttribute("aria-invalid", invalid); $("#sampleError").textContent = invalid ? "使用字母、数字与连字符，不含空格。" : "编号格式正确。"; $("#sampleError").className = invalid ? "error-text" : "field-help"; };
$("#batchDetail").onclick = () => showDetail("Attention sweep · Batch 07", "过去 24 小时 · 固定演示批次", '<div class="summary-rows"><div><span>已完成</span><b>9</b></div><div><span>运行中</span><b>2</b></div><div><span>待运行</span><b>1</b></div><div><span>总计</span><b>12</b></div></div>');

/* ---------- Theme selection preserves current controls and data ---------- */
const themeSelect = $("#themeSelect");
function applyTheme(id) {
  const entry = THEMES.find(t => t[0] === id) || THEMES[0];
  themeSelect.value = entry[0]; document.documentElement.dataset.theme = entry[0];
  $("#themeCss").href = `themes/${entry[0]}.css`;
  $("#themeSource").href = `themes/${entry[0]}.css`;
  $("#themeDescription").textContent = `${entry[1]} — ${entry[2]}`;
  document.title = `UI Taste Lab · ${entry[1]}`;
  history.replaceState(null, "", `?theme=${entry[0]}${location.hash}`);
  $("#themeCss").onload = () => { $("#fontLabel").textContent = "当前字体栈：" + getComputedStyle(document.body).fontFamily; $("#tip").hidden = true; };
}
themeSelect.onchange = () => applyTheme(themeSelect.value);
function stepTheme(d) { applyTheme(THEMES[(THEMES.findIndex(t => t[0] === themeSelect.value) + d + THEMES.length) % THEMES.length][0]); }
$("#prevTheme").onclick = () => stepTheme(-1);
$("#nextTheme").onclick = () => stepTheme(1);
document.addEventListener("keydown", e => {
  if (e.altKey && ["ArrowLeft", "ArrowRight"].includes(e.key) && !e.target.closest("input, select, textarea, dialog")) { e.preventDefault(); stepTheme(e.key === "ArrowRight" ? 1 : -1); }
});
applyTheme(new URLSearchParams(location.search).get("theme"));

/* Ripple belongs only to themes that call for it. */
document.addEventListener("pointerdown", (e) => {
  const b = e.target.closest(".btn"); if (!b || reduced || !["modern-saas", "bespoke"].includes(themeSelect.value)) return;
  const r = b.getBoundingClientRect(), s = ce("i", "ripple");
  s.style.left = e.clientX - r.left + "px"; s.style.top = e.clientY - r.top + "px";
  b.append(s); setTimeout(() => s.remove(), 500);
});
function toast(msg) { const t = $("#toast"); t.textContent = msg; t.hidden = false; clearTimeout(t._h); t._h = setTimeout(() => (t.hidden = true), 1800); }
