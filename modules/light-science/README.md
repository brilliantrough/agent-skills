# Light-Science 精选接入

仅接文献检索与科研数据图，不装整包。研究设计／执行沿用 `exp-*`，项目布局与三层记忆不变。自有入口为 research 组的 `research-evidence`；第三方源码与资源仍由上游维护。

## 安装

在完整宿主 setup 中先选 `research` 组，再选默认 **N** 的 `light-science` 模块。已有克隆也可分别运行：

```bash
bash skills-sync.sh base research
bash modules/run.sh --host pi --only light-science
```

第二条交互询问；`--host` 可换成 `opencode`、`codex`、`dsh`。确认范围后，非交互只安装本模块：

```bash
bash modules/light-science/setup.sh --host pi
```

- `skills-sync.sh` 始终从 GitHub 拉取套件，不以本地克隆作为技能源。
- 模块要求 `research-evidence` 已安装，缺失就提示并停止；不连带安装整个 research 组。
- 需要 Git、Node/npx（上游 CLI 当前要求 Node ≥22.20）。复用 `skills-external.sh --light-science`，只处理下表两项，不安装／更新设计或其它依赖。

| 实际技能名 | 上游子目录 |
| --- | --- |
| `literature-search` | `light-literature/` |
| `light-chart` | `light-chart/skills/light-chart/` |

两项均固定至 `Light0305/Light-Science@6597430ad09d8f7c3518ec4cb08829be2b417e18`。完整技能落在 `~/.agents/skills/`，有 Claude Code 时同步其入口；保留脚本、资源与许可。重开宿主会话后检查技能列表。

## 保留与更新

- 同名本地／其它来源、不同固定版本、Claude 同名差异副本：告警、保留、不覆盖；各项独立处理，冲突使模块返回非零。
- 同源同版本已安装时跳过；缺项可重跑。未登记的同名目录即使没有 `SKILL.md` 也保留，失败后遗留此类目录时先核对、备份再处理，不自动清空。安装副本不承载个人改动，适配规则回本仓。
- 套件的通用第三方更新不升级这两个固定入口；升级前核对上游路径／契约／许可、真实任务，再一起调整基线与适配。已有不同基线需先比较、备份并由用户确认处理。
- 不初始化研究项目，不写 `Memory/`、`Workflow/`、`project.json`，不安装上游 hooks、其它 skills 或 Python／R 包。

## 首次使用与验收

说“用 research-evidence 为当前项目查文献”或“用 research-evidence 把现有结果做成数据图”。入口先确定工作区，再读对应上游 `SKILL.md`。

- 文献运行依赖 Python ≥3.11、requests、pypdfium2、Pillow；按上游 README 在合适的独立环境准备，不改训练环境。来源可尝试无密钥调用，但不保证额度、全文或数据库覆盖。
- Chart 的 `figure_job.py` 任务准备需要 NumPy、Pandas、Matplotlib；固定版的 Pandas 版本约束见[适配参考](../../skills/research/research-evidence/references/light-science.md)。其它库按 Python／R 路线选用，新建独立 venv，不与系统旧包混装，不默认装全部绘图生态。
- 首次选择一篇真实 PDF／一个有边界的查询，以及一份已有实验数据；检查产物只落在指定工作区、原始材料未覆盖、引用能定位、图的统计口径与实际导出正确。
- 文献 `--out` **不能直接指向项目根或含手工 README 的目录**：工具会写库索引 README。工作区内部仍保留上游原生文件契约。

安装／重复安装成功不证明论文阅读、统计分析或图件质量；这些由真实任务验收。

## 许可与退出

上游不是统一 MIT：Chart 含 figures4papers 的 **CC BY-NC 4.0** 材料，另有 MIT／Apache-2.0 组件。商业使用、抽取或再分发前，检查实际所用资源的 `THIRD_PARTY_NOTICES.md` 和 `licenses/`；本仓 MIT 不授予额外权利。

卸载前用 `npx skills list -g` 核对两项来源及安装位置，再用上游 `npx skills remove literature-search light-chart -g` 选择相应宿主。不要删研究项目中的文献、图件或独立环境。保留 `research-evidence` 时可继续用其它可信工具；不再调用上游专用接口。
