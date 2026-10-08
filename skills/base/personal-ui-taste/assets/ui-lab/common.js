/* Shared theme catalogue and short, user-triggered content feedback. */
"use strict";
const THEMES = [
  ["shadcn-neutral", "Shadcn Neutral", "浅色中性、开放式读数、克制边界"],
  ["paper-cream", "Paper Cream · 暖白纸面", "暖白纸面、陶土强调、衬线页标题"],
  ["modern-saas", "Modern SaaS · 浅色亮蓝", "浅色导航、亮蓝主操作、鲜明状态信号"],
  ["bespoke", "Bespoke · 观测站", "蓝图网格、仪器铭牌、IBM Plex 字体"],
  ["bento", "Bento · 预览卡片", "大圆角表面、紧凑元信息、轻盈预览"],
  ["swiss", "Swiss · 网格", "直角、发丝线、对齐与字重层次"],
  ["aurora-glass", "Glass · 平色玻璃", "平色画布、透明材质、清楚文字层次"],
  ["soft-ui", "Soft UI · 降亮版", "低亮画布、圆润字形、柔和层次"],
  ["baseline", "旧基线 · 对照", "历史视觉 tokens，不作为默认方向"],
  ["layered", "海拔阴影 · 技法样本", "四级阴影对照，不列入正式主题选择"],
];
function updateNav(fallback) {
  document.querySelectorAll(".nav-item").forEach(a => {
    const active = a.getAttribute("href") === (location.hash || fallback);
    a.classList.toggle("is-active", active);
    if (active) a.setAttribute("aria-current", "location"); else a.removeAttribute("aria-current");
  });
}
function revealChange(el) {
  el.getAnimations().forEach(a => a.cancel());
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  el.animate([{ opacity: .45, transform: "translateY(4px)" }, { opacity: 1, transform: "translateY(0)" }],
    { duration: 180, easing: "cubic-bezier(.16, 1, .3, 1)" });
}
Object.assign(window, { THEMES, updateNav, revealChange });
