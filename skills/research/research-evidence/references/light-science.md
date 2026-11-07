# Light-Science 的安装与调用边界

首批只用 `literature-search` 和 `light-chart`。基线为 [Light0305/Light-Science@6597430](https://github.com/Light0305/Light-Science/tree/6597430ad09d8f7c3518ec4cb08829be2b417e18)，核对日期 2026-11-08；上游更新后重查接口，不把这一基线当未来兼容保证。

## 安装与发现

先通过套件 setup 选择 research 组，再选择默认 N 的 `light-science` 可选模块。安装／更新／退出见[模块说明](https://github.com/brilliantrough/agent-skills/blob/main/modules/light-science/README.md)。缺技能时给用户该入口，不擅自执行整套安装。

| 技能名 | 源码子目录 | 主要依赖 |
| --- | --- | --- |
| `literature-search` | `light-literature/` | Python ≥3.11、requests、pypdfium2、Pillow；全文判断依赖宿主实际阅读能力 |
| `light-chart` | `light-chart/skills/light-chart/` | `figure_job.py` 任务准备需 NumPy、Pandas、Matplotlib；其它 Python／R 包按路线选择，资源检索不等于出图 |

安装不配置凭据、不安装全部 Python／R 生态。先核对解释器与当前可用依赖，不往共享训练环境批量装包。

- 新建环境用显式 venv，不继承 system-site-packages；不要把新 NumPy 叠加到系统旧 Matplotlib。`figure_job.py` 即使只准备 CSV 任务也会导入 Matplotlib。
- 固定基线的 Chart 使用 **`pandas==2.3.3`**：Pandas 3.1.1 已复现 `ValueError: output array is read-only`，源于 `chart_plan.py` 原地修改 NumPy 掩码。升级前重查该契约，不修改共享上游副本。
- 2026-11-08 的最小任务准备组合：Python 3.12.3、NumPy 2.5.4、Pandas 2.3.3、Matplotlib 3.11.2；仅验证 CSV → decision JSON，不代表所有图型或科研效果已验证。
- 需要密钥的来源沿用本地配置，不把凭据写入项目记录。

## 文献入口

以下占位符替换为实际绝对路径；`<PYTHON>` 是已具备依赖的解释器，`<LIT>` 是技能安装目录，不是研究项目根。

```text
<PYTHON> <LIT>/run_litsearch.py plan init --direction "研究问题" --domain general --out <检索工作区>/query_plan.json
<PYTHON> <LIT>/run_litsearch.py plan validate --plan <检索工作区>/query_plan.json
<PYTHON> <LIT>/run_litsearch.py search --plan <检索工作区>/query_plan.json --run <检索工作区>
<PYTHON> <LIT>/run_litsearch.py literature add --pdf <真实论文.pdf> --out <专用文献库工作区>
<PYTHON> <LIT>/run_litsearch.py literature verify --out <专用文献库工作区>
```

- `plan init` 只生成骨架；填好实际问题、查询、来源与预算后再 validate／search。不为单篇阅读强制跑检索。
- `literature build --run <检索工作区> --out <文献库工作区>` 默认处理 `include` 记录；下载 PDF 需显式 `--fetch-pdfs`，且只用合法 OA／已有授权。
- `MODEL_PARSE.md`／`AGENT_TASKS.md` 是阅读准备材料，不是已完成的转录或精读。按上游阅读指引实际看页、生成本次需要的内容。
- 库根 `README.md`、`manifest.json` 和文章内部元数据由工具维护；续作前先查现有内容，不向项目根写库索引。
- 默认缓存为 `~/.cache/litsearch`，可用 `LITSEARCH_CACHE_DIR` 改；上游还会查找技能目录、当前目录及用户配置位置的 `.env`／`litsearch.toml`，运行前确认采用的配置范围。

## Chart 入口

先读真实数据及 `light-chart/SKILL.md`。`<CHART>` 为实际技能目录：

```text
<PYTHON> <CHART>/scripts/library.py route --query "budget sweep" --backend python
```

这只返回候选实现路径与输入契约；不是按一句话自动画完图。随后读取匹配脚本／函数，明确列映射、独立单位、缺失与不确定性，沿用项目生成代码调用；需要任务 spec 时再用 `figure_job.py --data <数据> --spec <任务.json> --out <图件工作区>/decision.json`；`--out` 是 JSON 文件，会覆盖同名文件，迭代时保留旧版。它准备任务与证据绑定，不能把准备状态当作出图、目视审核或科学验证。

## 权利与能力边界

- 原始工作 MIT 不覆盖整包所有材料。Chart 的 [THIRD_PARTY_NOTICES.md](https://github.com/Light0305/Light-Science/blob/6597430ad09d8f7c3518ec4cb08829be2b417e18/light-chart/skills/light-chart/THIRD_PARTY_NOTICES.md) 区分 MIT、Apache-2.0、figures4papers 的 CC BY-NC 4.0 与仅链接资源。商业使用／复制前逐项核对，不把图库存在等同于获准再分发。
- 未接入 Write、Review、Journal、Crawl、Diagram、Patent、Software Copyright、Leader、Memory；当前任务需要时另评估，不因上游交接表提及就自动安装。
- 上游本身允许已有布局优先；我们改变的是工作区选择和交接归属，不修改共享第三方源码或原生数据 schema。
- `exp-*` 的主张—对照、独立单位、有效阴性与分析边界吸收了上游 Idea／Design／Experiment／Analysis 的方法，按本套件流程重新组织；不复制上游脚本、模板或另一套记忆台账。
