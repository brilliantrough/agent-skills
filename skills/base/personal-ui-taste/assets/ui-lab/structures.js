/* Structure comparison: shared themes, local filtering, complete run details. */
"use strict";
const STRUCTURES = {
  sidebar: "侧栏负责定位，主区按阅读顺序排列。适合跨页面工作；避免让导航占据内容的重心。",
  doc: "一个主阅读方向：概览 → 趋势 → 记录。适合说明与复盘；不追求同时塞进所有面板。",
  workbench: "趋势为主，记录为辅，筛选就近。适合反复比较；不要让所有面板拥有相同权重。",
  master: "左侧选对象，中间看趋势，右侧看证据。适合在运行之间反复切换；窄屏详情移到下方。",
};
const RUNS = [
  { name: "exp-0912-swa", dataset: "c4-zh", resource: "6×A100", hours: "6.2h", loss: "1.208", cost: 1860, node: "gpu-01", status: "已完成", tone: "ok", age: 1 },
  { name: "exp-0910-moe", dataset: "fineweb", resource: "8×H800", hours: "11.4h", loss: "1.226", cost: 5472, node: "gpu-02", status: "已完成", tone: "ok", age: 3 },
  { name: "exp-0908-base", dataset: "c4-zh", resource: "2×L40S", hours: "3.1h", loss: "1.301", cost: 93, node: "gpu-03", status: "排队中", tone: "warn", age: 5 },
  { name: "exp-0905-dpo", dataset: "wiki-zh", resource: "4×A100", hours: "3.7h", loss: "1.244", cost: 740, node: "gpu-01", status: "已完成", tone: "ok", age: 6 },
  { name: "exp-0902-sft", dataset: "fineweb", resource: "6×4090", hours: "9.5h", loss: "1.352", cost: 1140, node: "gpu-02", status: "失败", tone: "bad", age: 12 },
];
const $ = (s, e = document) => e.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const params = new URLSearchParams(location.search);
let dataset = "all", days = 30, selected = 0;
THEMES.forEach(([id, label]) => $("#themeSelect").add(new Option(label, id)));
function saveParams() { history.replaceState(null, "", "?" + params + location.hash); }
function applyTheme(id) {
  const hit = THEMES.some(t => t[0] === id) ? id : "shadcn-neutral";
  $("#themeSelect").value = hit; document.documentElement.dataset.theme = hit;
  $("#themeCss").href = `themes/${hit}.css`;
  params.set("theme", hit); saveParams();
}
function applyStructure(id, animate = true) {
  const hit = Object.hasOwn(STRUCTURES, id) ? id : "doc";
  document.body.dataset.structure = hit;
  $$("#structureSeg button").forEach(b => {
    const on = b.dataset.structure === hit;
    b.classList.toggle("is-on", on); b.setAttribute("aria-pressed", on);
  });
  $("#structureDescription").textContent = STRUCTURES[hit];
  params.set("structure", hit); saveParams(); if (animate) revealChange($(".page"));
}
function showDetail(index, animate = true) {
  selected = index;
  const run = RUNS[index];
  $$(".run-row").forEach(r => { const on = Number(r.dataset.run) === index; r.classList.toggle("is-active", on); r.setAttribute("aria-pressed", on); });
  $("#detailTitle").textContent = run ? run.name : "没有匹配运行";
  $("#detailMeta").textContent = run ? `${run.dataset} · ${run.resource} · ${run.hours}` : "调整筛选后继续查看。";
  $(".detail-list").hidden = !run; $("#exportRun").disabled = !run;
  if (run) {
    $("#detailStatus").textContent = run.status; $("#detailStatus").className = `badge ${run.tone}`;
    $("#detailLoss").textContent = run.loss; $("#detailCost").textContent = `¥ ${run.cost.toLocaleString("en-US")}`;
    $("#detailNode").textContent = run.node;
    $("#detailNote").textContent = run.tone === "bad" ? "执行失败，请检查运行日志。" : run.tone === "warn" ? "等待资源分配，当前展示此前评估值。" : "指标已归档，可查看曲线与资源记录。";
  }
  if (animate) revealChange($(".detail"));
}
const records = $$("#runs tbody tr:not(#emptyRecords)");
function filterRuns() {
  const query = $("#q").value.trim().toLowerCase();
  const indexes = RUNS.map((r, i) => (dataset === "all" || r.dataset === dataset) && r.age <= days && r.name.includes(query) ? i : -1).filter(i => i >= 0);
  records.forEach((r, i) => r.hidden = !indexes.includes(i));
  $$(".run-row").forEach(r => r.hidden = !indexes.includes(Number(r.dataset.run)));
  $("#emptyRecords").hidden = indexes.length > 0;
  $("#recordCount").textContent = `${indexes.length} / ${RUNS.length} 条 · 演示数据`;
  const rows = indexes.map(i => RUNS[i]);
  $("#statLoss").textContent = rows.length ? Math.min(...rows.map(r => Number(r.loss))).toFixed(3) : "—";
  $("#statCount").textContent = rows.length;
  $("#statPending").textContent = rows.filter(r => r.tone === "warn").length;
  $("#statCost").textContent = "¥ " + rows.reduce((n, r) => n + r.cost, 0).toLocaleString("en-US");
  if (!indexes.includes(selected)) showDetail(indexes[0] ?? -1, false);
  $$("#chart [data-dataset]").forEach(el => {
    const shown = dataset === "all" || el.dataset.dataset === dataset;
    if (el.tagName.toLowerCase() === "path") el.style.display = shown ? "" : "none";
    else el.hidden = !shown;
  });
}
$("#themeSelect").onchange = () => applyTheme($("#themeSelect").value);
$("#structureSeg").onclick = e => { const b = e.target.closest("button"); if (b) applyStructure(b.dataset.structure); };
$$("#dsSeg button, #rangeSeg button").forEach(b => b.onclick = () => {
  [...b.parentElement.children].forEach(x => { x.classList.toggle("is-on", x === b); x.setAttribute("aria-pressed", x === b); });
  if (b.dataset.dataset) dataset = b.dataset.dataset; else days = Number(b.dataset.days);
  filterRuns(); revealChange($("#chart"));
});
$$("#dsSeg button, #rangeSeg button").forEach(b => b.setAttribute("aria-pressed", b.classList.contains("is-on")));
$("#q").oninput = filterRuns;
$$(".run-row, .record-open").forEach(row => row.onclick = () => {
  if (document.body.dataset.structure !== "master") applyStructure("master");
  showDetail(Number(row.dataset.run));
});
$("#exportRun").onclick = () => {
  const r = RUNS[selected];
  const csv = ["实验,数据集,状态,资源,时长,eval_loss,费用,节点", [r.name, r.dataset, r.status, r.resource, r.hours, r.loss, r.cost, r.node].join(",")].join("\r\n");
  const url = URL.createObjectURL(new Blob(["\ufeff" + csv], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a"); a.href = url; a.download = r.name + ".csv"; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
applyTheme(params.get("theme"));
applyStructure(params.get("structure"), false);
showDetail(0, false); filterRuns();
addEventListener("hashchange", () => updateNav("#lead"));
updateNav("#lead");
