# personal-ui-taste

可迁移、持续演化的 UI 设计伙伴：从内容推导结构、叙事与动效，主动提出更直观、更好看的形式，用有范围的个人反馈校准。旧样板是参考，不是设计上限。

## 安装与调用

推荐重跑套件 setup：同步本 skill，并安装/更新四个外部设计依赖。只手工复制本目录时，还需按文末安装依赖；入口必须是：

```text
~/.agents/skills/personal-ui-taste/SKILL.md
```

OpenCode 支持扫描该全局目录（外部 skill 扫描需开启）。新建/修改后**退出并重启 OpenCode**以重新发现/加载。其他 agent 按其 skill 目录约定安装，或明确让它读取 `SKILL.md`。

可直接对 agent 说：

> 使用 personal-ui-taste，按照我的个人品味优化这个项目的前端，并用浏览器检查主要交互。

或在项目现有 `AGENTS.md` 中按需加入：

> 涉及前端设计、表单、图表或管理面板时，先加载 personal-ui-taste；按其演化协议记录明确确认的新偏好。

后续训练：

> 这次的移动端设计我认可，把这个场景的新偏好补充进 personal-ui-taste，并保留已有规则的适用范围。

按场景维护时也可以直接说：

- **查**：“列出这个 skill 对移动端表单已确认的偏好。”
- **增**：“新增阅读界面场景，把这轮确认的排版偏好保存进去。”
- **改**：“将这个场景的圆角规则改成我们刚确认的版本，其他场景不变。”
- **删**：“删除这条我不再喜欢的动效规则，并清理对应引用。”

当前已收录 S01「浅色信息密集界面」、S02「冷灰蓝预览型工作台」、S03「科研指标绘图」、S04「分析排查工作台」。按任务选读，不把某个场景变成所有页面的固定模板。

S04适合联合排行、维度汇总、分层展开等分析交互；其指标汇总、快照采集、历史留存和重启恢复约定放在 `references/data-and-runtime.md`，按任务选读，不再单独安装另一个工程 skill。

## 跨服务器

复制整个目录迁移个人记录；内部引用均为相对路径，外部依赖在目标机重新安装：

```sh
# 先确认目标机器存在 ~/.agents/skills，再复制；目标已有同名目录时先比较并合并。
scp -r ~/.agents/skills/personal-ui-taste USER@HOST:~/.agents/skills/
```

复制是手动同步，不会自动传播之后的修改。可把该目录纳入自己的 dotfiles/skills Git 仓库管理；不要把旧版本直接覆盖另一台机器中新积累的规则。

## 文件

- [assets/ui-lab/index.html](assets/ui-lab/index.html)：直接打开的离线实验室，默认 shadcn-neutral；八套主题与两个对照，可交互比较。
- [assets/ui-lab/structures.html](assets/ui-lab/structures.html)：四种工作型骨架样本，可叠加切主题；不是结构全集。
- [assets/ui-lab/design-exploration.html](assets/ui-lab/design-exploration.html)：内容驱动的构图与动效候选——非对称开篇、同对象重排、滚动章节、原生详情；中性/米色可对比。
- [assets/ui-lab/README.md](assets/ui-lab/README.md)：组件 → CSS/JS 索引、token 约定、复用边界；素材版本与许可证见同目录 `SOURCES.md`。
- [SKILL.md](SKILL.md)：主动设计流程——读题、查证、推荐、设计、实证；已确认场景只做索引。
- [references/preferences.md](references/preferences.md)：T01–T15、症状索引与工作控件起点；明确反馈按范围保留。
- [references/design-philosophy.md](references/design-philosophy.md)：内容立意、设计机会、按需三拨盘、概念与反 AI 味审查。
- [references/external-skills.md](references/external-skills.md)：四个外部 skill 的触发、组合工作流、真实安装名、路径与缺失处理。
- [references/style-menu.md](references/style-menu.md)：内容 → 正向设计模式、叙事构图、外部检索、工作骨架与风格参考。
- [references/motion.md](references/motion.md)：操作反馈、对象连续性、比较与滚动叙事，及减少动态效果退化。
- [patterns.md](patterns.md)：S01 的图表、浮层、筛选、状态时间轴、响应式模式和踩坑。
- [themes/README.md](themes/README.md)：美术风格层——皮肤索引、场景倾向、通用美术偏好与反感清单；确定界面结构后在此选皮肤。
- [themes/shadcn-neutral.md](themes/shadcn-neutral.md)：用户强烈认可的现代简洁方向，与亮蓝等既有主题并列选择；具体实现按项目目验。
- [themes/paper-cream.md](themes/paper-cream.md)：暖白纸面 + 陶土强调 + 衬线标题，取值来自 code.claude.com/docs 线上实测。
- [evolution.md](evolution.md)：按场景增删改查、处理冲突、记录证据与版本。
- [scenarios/preview-workbench.md](scenarios/preview-workbench.md)：S02 的主题配对、字体、矩形面板、按钮、预览卡片与稀疏状态。
- [scenarios/research-charts.md](scenarios/research-charts.md)：S03 的数据形态、曲线、比较维度和参考线。
- [scenarios/analytical-workbench.md](scenarios/analytical-workbench.md)：S04 的关系问题、联合排行、维度汇总、分层展开和语义筛选。
- [references/data-and-runtime.md](references/data-and-runtime.md)：分析界面的指标合并、快照采集、时间/留存边界和运行恢复约定，按任务选读。
- [references/visual-craft.md](references/visual-craft.md)：六个参考源的组件、配色、摘要卡、图标、字体与标签做法，供各主题共同吸收。

不需要提前设计所有未来场景：明确反馈 → 当前场景落地 → 认可后沉淀 → 在下一项目复用。

## 外部依赖与工作流

三个 setup 共用 `skills-sync.sh` → `skills-external.sh`：默认补装 UI/UX Pro Max、Huashu Design、Taste 的新建与改造两个 skill，已登记第三方随上游更新。名单和命令只在套件根脚本维护，不把整个仓库全装进宿主。

本 skill 读题与个人校准 → 按任务读取外部 skill 的最新入口/参考/脚本 → 适配实现 → 真实审查 → 用户反馈回到本 skill。完整分工、独立安装命令、执行依赖和缺失处理见 [external-skills.md](references/external-skills.md)。

第三方副本允许自动覆盖；个人修改保存到本 skill，不直接改上游副本。同名本地/其他源由套件告警、保留并交回确认。安装 skill 不自动安装 GSAP、浏览器环境或上游 hooks。
