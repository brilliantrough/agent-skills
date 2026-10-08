/* 结构菜单：切换骨架与主题。主题清单从 lab.js 的 THEMES 生成，避免两页漂移。 */
"use strict";
const THEMES = [
  ["shadcn-neutral", "Shadcn Neutral"],
  ["modern-saas", "Modern SaaS · 亮蓝"],
  ["bespoke", "Bespoke · 观测站"],
  ["bento", "Bento · 预览卡片"],
  ["swiss", "Swiss · 网格"],
  ["aurora-glass", "Glass · 平色玻璃"],
  ["soft-ui", "Soft UI · 降亮版"],
  ["paper-cream", "Paper Cream · 暖白纸面"],
  ["baseline", "旧基线 · 对照"],
  ["layered", "海拔阴影 · 技法样本"],
];
const STRUCTURES = ["sidebar", "doc", "workbench", "master"];
const $ = (s, e = document) => e.querySelector(s);
const params = new URLSearchParams(location.search);

$("#themeSelect").innerHTML = THEMES.map(([id, label]) => `<option value="${id}">${label}</option>`).join("");

function applyTheme(id) {
  const hit = THEMES.some(t => t[0] === id) ? id : "paper-cream";
  $("#themeSelect").value = hit; document.documentElement.dataset.theme = hit;
  $("#themeCss").href = `themes/${hit}.css`;
  params.set("theme", hit); history.replaceState(null, "", "?" + params + location.hash);
}
function applyStructure(id) {
  const hit = STRUCTURES.includes(id) ? id : "doc";
  document.body.dataset.structure = hit;
  document.querySelectorAll("#structureSeg .seg-item").forEach(b => {
    const on = b.dataset.structure === hit;
    b.classList.toggle("is-on", on); b.setAttribute("aria-selected", String(on));
  });
  params.set("structure", hit); history.replaceState(null, "", "?" + params + location.hash);
}

$("#themeSelect").onchange = () => applyTheme($("#themeSelect").value);
$("#structureSeg").onclick = e => { const b = e.target.closest(".seg-item"); if (b) applyStructure(b.dataset.structure); };

/* 运行列表选中：只更新详情文案，不重排布局。 */
const RUNS = [["exp-0912-swa", "c4-zh · 6×A100 · 6.2h"], ["exp-0910-moe", "fineweb · 8×H800 · 11.4h"],
  ["exp-0908-base", "c4-zh · 2×L40S · 3.1h"], ["exp-0905-dpo", "wiki-zh · 4×A100 · 3.7h"],
  ["exp-0902-sft", "fineweb · 6×4090 · 9.5h"]];
document.addEventListener("click", e => {
  const row = e.target.closest(".run-row"); if (!row) return;
  document.querySelectorAll(".run-row").forEach(r => r.classList.toggle("is-active", r === row));
  const [name, meta] = RUNS[Number(row.dataset.run)] || RUNS[0];
  $("#detailTitle").textContent = name; $("#detailMeta").textContent = meta;
  if (document.body.dataset.structure !== "master") applyStructure("master");
});

/* 演示用的假筛选：分段选择与搜索只做视觉反馈，不改数据。 */
document.addEventListener("click", e => {
  const b = e.target.closest(".seg-item"); if (!b || b.closest("#structureSeg")) return;
  b.parentElement.querySelectorAll(".seg-item").forEach(x => x.classList.toggle("is-on", x === b));
});

applyTheme(params.get("theme") || "paper-cream");
applyStructure(params.get("structure") || "doc");
