---
name: nju-ppt
description: "用南京大学银杏金模板制作 HTML 网页演示或原生可编辑 PPTX。Use when the user says 用南大模板、南京大学模板、南大 PPT、南大 HTML PPT，或明确使用 nju-ppt。是否使用南大模板与 HTML/PPTX 格式分别确认，缺哪项问哪项，两项均明确才制作；明确不使用南大的 HTML 请求交给外部 dashi-ppt 内置主题。HTML 依赖 dashi-ppt；PPTX 依赖 ppt-master，不互相替代。"
---

# Nanjing University fixed-style presentations

This skill owns content compression, the fixed NJU template, and acceptance checks. HTML reuses external Dashi through an isolated NJU adapter; PPTX uses the actual `ppt-master`. Do not build another engine.

## 0. 模板与格式分别确认

- 两项互不推导：①是否使用南大模板；②输出 HTML／网页还是 PPTX／PowerPoint。两项均明确后才制作
- 已明确的照做，不重复问；只缺模板选择就问“是否使用南大模板”，只缺格式就问“HTML 还是 PPTX”，两项都缺就一次问清并等待答复
- 仅说“PPT”不算明确文件格式；仅说“HTML”不算选定非南大模板，不能直接交给 Dashi
- 明确选择南大模板＋HTML：走 `references/html-runtime.md`；每页一个固定方案，不另选视觉主题
- 明确不使用南大模板＋HTML：加载实际 `dashi-ppt`，按它的内置主题与标准流程制作；主题未定时按其规则展示风格图并询问
- 内容提到南京大学、仅点名 `nju-ppt` 均不等于选择南大模板；用户已明确指定其他模板时尊重该选择，不再询问是否南大
- 明确南大＋PPTX：继续下面现有流程。普通 PPTX 不自动附加南大品牌
- 格式或模板要求冲突时，只追问冲突项。不修改第三方 skill 来强占触发
- HTML 分支不运行 Python/PPTX 环境检查；不要因缺少 ppt-master 阻断 HTML

**以下第 1–5 节仅用于南大 PPTX。** HTML 的环境、内容格式、编辑保存与验收只按 `references/html-runtime.md`。

## 1. Resolve the runtime

Use this loaded skill's actual directory as `NJU_SKILL_DIR`; never guess a username or drive. Run `scripts/prepare.py` as described in `references/runtime.md`. Read the absolute `python`, `ppt_master_root`, and `template_root` paths from its successful JSON output.

- Missing engine: ask the user to select the repository installer's `ppt` group; never silently substitute another PPT tool
- Checks do not install packages. Use `--install` only with permission to prepare dependencies; copied files or a failed check are not a ready runtime
- The complete template root is this package's `assets/nju-academic-ginkgo`, not its inner `templates/`
- Do not modify engine source, its global template directory, or `decks_index.json`. Report missing files, not paths to the author's private backups

## 2. Read the full source and create a separate project

- Read complete `.md / .txt` files. For DOCX/PDF, use the engine's `source_to_md.py` and prepare conversion dependencies only as needed
- Let the engine create a new task project and archive the source; do not overwrite the source, an adjacent brief, or an existing project
- Default: defense/academic report, 12–15 pages, maximum 18. Adapt to an explicitly requested teaching or other use
- Use ginkgo gold with pale blue accents and concise prose, **not mandatory four-character phrases**. Read `references/style-contract.md` for the 11 prototypes, type sizes, and safe areas
- Do not redraw/recolor the original marks, ginkgo leaf, or campus skyline. Preserve the visible anniversary combination without adding celebration text

## 3. Write and validate the brief

Follow `references/content-brief.md` and write `brief.md` in **the new project root**.

```text
<python> <NJU_SKILL_DIR>/scripts/check_brief.py <project>/brief.md
```

- Fix a nonzero validation result before generation. After two unsuccessful rounds, list the cuts, page splits, or constraints needing a user decision
- Ask only about material ambiguity or a requested statistical chart without data; never invent measurements
- The archived full source remains the authority for facts, long commands, and speaker notes. The brief controls selection and page order, not permission to discard important conditions

## 4. Hand off to ppt-master

Load `ppt-master`, use its **Default** route, and explicitly provide:

```text
template selection: explicit exact root = <template_root>
content: <project>/brief.md + archived full source
style contract: <NJU_SKILL_DIR>/references/style-contract.md
```

- Use the user's fixed selection; do not reopen visual direction or pass only the bare name “南大模板”
- Respect the engine's confirmation rules. Use its delegated branch only with this user's explicit current or applicable standing authorization; never fabricate a confirmation receipt
- Apply the complete workspace with the engine's `apply_template.py`, then consume only project-local templates and assets
- Only use `cover / toc / chapter / points3 / pillars4 / two_col / timeline / chart_column / chart_combo / table / ending`
- Keep the brief's conclusions and cuts. Notes may recover conditions from the source, not introduce unsupported conclusions
- Replace all chart/table demonstration content in the carrier JSON; export with `--native-charts-and-tables`. Without statistical data, use flows or qualitative tables instead
- Stop and report missing prototypes or incompatible contracts. Do not silently change templates, alter shared Layout contracts, or rasterize charts
- Keep the pale-blue takeaway rectangle, accent rectangle, and text as separate unlocked Slide-local objects. Do not group them or move the rectangles into Master/Layout; users must be able to move and edit each independently

## 5. Check and deliver

Read `references/qa-checklist.md`: no text overflow, gold titles and matching numbers, unchanged base artwork, editable native objects, complete notes.

- If Microsoft YaHei is unavailable, name the installed Chinese replacement and remeasure line breaks; do not automatically install or redistribute commercial fonts
- Deliver the PPTX, an overview, and the cuts list; disclose untested applications and projection conditions
- Never leave demonstration data, placeholder prompts, or old blue-template elements in the final deck

## References

- `references/html-runtime.md`: HTML 路由、隔离 Dashi、单方案生成与编辑保存
- `references/style-contract.md`: palette, typography, grid, and prototype capacity
- `references/content-brief.md`: brief format, page budget, selection, and sources
- `references/qa-checklist.md`: content, native objects, and actual software checks
- `references/runtime.md`: initial setup, path resolution, and platform boundaries
- `ASSETS-NOTICE.md`: pending artwork redistribution rights; no university endorsement
