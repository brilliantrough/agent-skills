# 可选领域能力：kernel-knowledge

[独立仓库](https://git.nju.edu.cn/iscl/kernel-knowledge)。需要相应仓库访问权限；本套件不假定它对所有用户公开，不复制其知识正文，不自动安装或接管更新。

## 什么时候交接

| 本套件负责 | 领域库负责 |
|---|---|
| `pytorch-perf-tuning`选热点、采集负载、接回整模 | 算子工程、硬件/DSL、计量、优化机制与证据 |
| `kernel-worker`约定输入/数值/预算、隔离资源、接收交付 | `kernel-optimization-pipeline`与平台技能组织专业实现和验证 |
| `distill-project-kb`识别跨项目知识价值 | 按领域入库规范维护技术事实、代码、案例与发布 |

领域库支持直接阅读，也发布六个常用技能：`kernel-optimization-pipeline`、`ascend-910b-arch`、`tilelang-ascend`、`triton-ascend`、`msprof-ascend`、`ascend-kernel-roofline`（2026-10-25；以后以其发布清单为准）。跨平台方法不等于所有平台已有实测。

## 定位与安装

- 复用用户已登记的`KERNEL_KB_ROOT`，核对仓库及revision；未登记时询问或由用户提供，不猜服务器路径。机器路径进入项目/host记忆，不回写可迁移正文。
- 先读该库`README.md`、`INSTALL.md`；由需要者按上游说明克隆与安装。可以直接读`INDEX.md`及目标skill，不必为了查一条知识安装全部包。
- 发布入口为`tools/install_skills.py`；先用`--dry-run`比较，已有同名内容先确认归属并回流本地修改。单装一个包可能缺相邻技能资产，按实际依赖选择。
- 安装器备份替换文件，但不自动删除源端已撤回的旧文件；删除/改名遵循上游`CONTRIBUTING.md`。备份不等于已合并本地经验。
- 不把此库登记进本套件`skills-external.sh`。该脚本会更新锁表内符合条件的其他第三方，不能将“未代装”误认为“绝不代更新”；不要擅自另用npx登记同一批技能。

## 使用与降级

- 从`INDEX.md`找到当前维护入口；通用流程在`skills/kernel-optimization-pipeline/SKILL.md`，按任务读取工程基础、计量及目标平台内容。
- brief记录已核对的来源/版本、支持范围、数值和计量契约。eager/plain、dummy、graph与端到端分别报告；不因知识库中有旧成绩就视作本次已通过。
- 未安装但仓库可读：直接引用仓库。仓库不可用：说明能力缺口，可用项目现有正确参考、计时器及官方资料完成有界任务；依赖专用工具/证据而缺失时返回阻塞，不臆造内容或自动部署平台。
- Atrex/KLineage是可选方法资源；按领域库导读及实际版本使用。完整Atrex引擎只有在后端、evaluator和预算均就绪时才可启动，不与外层worker竞争写入。

## 回流与维护源

- 项目内保留实验过程和原始工件；成熟领域经验回`KERNEL_KB_ROOT`。写前读取其`AGENTS.md`、`ADMISSION.md`与当前知识维护流程，再按其发布规则更新安装副本。
- 主体只修交接方法、触发与一般判断；专业规则在领域库更正，主体摘要/引用同步复核。已有领域选材与验收无需再走一遍通用制库流程。
- 领域库`sources/local-skills/`是来源快照，不是主体技能的第二维护源；安装副本也不是独立分支。保留历史证据，不把旧快照当当前推荐。
