---
name: nju-ppt
description: "用南京大学固定银杏金模板把 Markdown/TXT 文档做成 PPT；凝练文案，固定页型，生成原生可编辑图表表格。Use when the user says 用南大模板、南京大学模板、南大 PPT，或要求按南京大学风格制作演示文稿。Requires the external ppt-master skill; this skill supplies the NJU template and content rules, not a separate PPT engine."
---

# Nanjing University fixed-style presentations

This skill owns content compression, the fixed NJU template, and acceptance checks. **Load the actual `ppt-master` skill for authoring and export.** Do not build another engine or duplicate its workflow.

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

- `references/style-contract.md`: palette, typography, grid, and prototype capacity
- `references/content-brief.md`: brief format, page budget, selection, and sources
- `references/qa-checklist.md`: content, native objects, and actual software checks
- `references/runtime.md`: initial setup, path resolution, and platform boundaries
- `ASSETS-NOTICE.md`: pending artwork redistribution rights; no university endorsement
