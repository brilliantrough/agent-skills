/* Fixed demo snapshot; layout changes keep the same stage elements. */
"use strict";
const stages = [
  { title: "等待处理 · 18 条", body: "先核对资源与优先级，再决定要启动哪一项。快照只说明数量，不足以推断等待是否异常。", label: "先确认条件", count: "18", caption: "等待处理的任务" },
  { title: "正在运行 · 8 条", body: "进度、日志与异常在当前任务附近查看。快照不含速度信息，不能把演示动画当作任务性能。", label: "让变化就近可见", count: "8", caption: "正在执行的任务" },
  { title: "已经完成 · 6 条", body: "核对结果后再比较或归档。完成是任务状态，不等于结果质量已经通过检验。", label: "从结果继续判断", count: "6", caption: "可继续查看结果的任务" },
];
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const queue = document.querySelector("#queueItems");
const cards = Array.from(queue.querySelectorAll(".queue-stage"));
const viewButtons = Array.from(document.querySelectorAll("button[data-view]"));
const sceneButtons = Array.from(document.querySelectorAll("button[data-scene]"));
const dialog = document.querySelector("#detailDialog");
let selectedStage = 0;
let selectedScene = 0;

cards.forEach((card, i) => card.addEventListener("click", () => {
  selectedStage = i;
  cards.forEach((el, index) => {
    el.classList.toggle("is-current", index === i);
    el.setAttribute("aria-pressed", String(index === i));
  });
  document.querySelector("#stageTitle").textContent = stages[i].title;
  document.querySelector("#stageBody").textContent = stages[i].body;
  revealChange(document.querySelector("#stageDetail"));
}));

viewButtons.forEach(button => button.addEventListener("click", () => {
  const view = button.dataset.view;
  if (queue.dataset.view === view) return;
  const before = cards.map(el => el.getBoundingClientRect());
  cards.forEach(el => el.getAnimations().forEach(a => a.cancel()));
  queue.dataset.view = view;
  viewButtons.forEach(el => {
    el.classList.toggle("is-on", el === button);
    el.setAttribute("aria-pressed", String(el === button));
  });
  if (reduced.matches) return;
  cards.forEach((el, i) => {
    const after = el.getBoundingClientRect();
    el.animate([{ transform: `translate(${before[i].left - after.left}px, ${before[i].top - after.top}px)` },
      { transform: "translate(0, 0)" }], { duration: 360, easing: "cubic-bezier(.16, 1, .3, 1)" });
  });
}));

function showScene(index) {
  if (index === selectedScene) return;
  selectedScene = index;
  sceneButtons.forEach((el, i) => {
    el.classList.toggle("is-current", i === index);
    el.setAttribute("aria-pressed", String(i === index));
  });
  document.querySelector("#sceneLabel").textContent = stages[index].label;
  document.querySelector("#sceneCount").textContent = stages[index].count;
  document.querySelector("#sceneBody").textContent = stages[index].caption;
  revealChange(document.querySelector("#sceneReadout"));
}
sceneButtons.forEach((el, i) => el.addEventListener("click", () => showScene(i)));
const visibleScenes = new Map();
const observer = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (entry.isIntersecting) visibleScenes.set(entry.target, entry.intersectionRatio);
    else visibleScenes.delete(entry.target);
  });
  const visible = Array.from(visibleScenes).sort((a, b) => b[1] - a[1]);
  if (visible.length) showScene(Number(visible[0][0].dataset.scene));
}, { rootMargin: "-25% 0px -25% 0px", threshold: [0, .25, .5, .75, 1] });
document.querySelectorAll(".story-scene").forEach(el => observer.observe(el));

const themeSelect = document.querySelector("#themeSelect");
const params = new URLSearchParams(location.search);
if (Array.from(themeSelect.options).some(option => option.value === params.get("theme"))) themeSelect.value = params.get("theme");
function setTheme() {
  document.querySelector("#themeCss").href = `themes/${themeSelect.value}.css`;
  params.set("theme", themeSelect.value);
  history.replaceState(null, "", `?${params}${location.hash}`);
}
themeSelect.addEventListener("change", setTheme);
setTheme();
document.querySelector("#openDetail").addEventListener("click", () => {
  document.querySelector("#dialogTitle").textContent = stages[selectedStage].title;
  document.querySelector("#dialogBody").textContent = stages[selectedStage].body;
  dialog.showModal();
  revealChange(dialog);
});
reduced.addEventListener("change", () => {
  if (reduced.matches) document.getAnimations().forEach(a => a.cancel());
});
const sections = Array.from(document.querySelectorAll("#form, #journey, #craft"));
function updateSectionNav() {
  const section = sections.filter(el => el.getBoundingClientRect().top <= innerHeight * .45).at(-1);
  if (!section) return;
  document.querySelectorAll(".explore-nav a").forEach(link => {
    const active = link.hash === `#${section.id}`;
    link.classList.toggle("is-active", active);
    if (active) link.setAttribute("aria-current", "location"); else link.removeAttribute("aria-current");
  });
}
addEventListener("scroll", updateSectionNav, { passive: true });
addEventListener("resize", updateSectionNav);
addEventListener("hashchange", () => updateNav("#form"));
updateNav("#form");
updateSectionNav();
