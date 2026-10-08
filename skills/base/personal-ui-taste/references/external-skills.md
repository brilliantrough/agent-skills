# 外部设计能力：安装完整，按任务调用

本 skill 维护个人反馈、适配判断与工作流；专业方法、配方、脚本和资源由上游维护。**整装依赖不等于每轮加载四套规则**，也不等于把落地页规范套进数据工作台。

## 依赖与触发

| 来源仓库 | 实际 skill 名 | 何时读取 | 接入当前任务 |
| --- | --- | --- | --- |
| [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | `ui-ux-pro-max` | 缺产品结构/UX/图表/动效依据，或新建视觉体系 | 读其 SKILL.md，再按问题检索 product/landing/ux/chart/gsap/技术栈；核对结果的语义适配 |
| [Huashu Design](https://github.com/alchaincyf/huashu-design) | `huashu-design` | 高保真原型、章节叙事、PPT、复杂动画或视觉 QA | 读其入口与需要的构图/动画/critique 参考，使用原版配方和工具；生产工程约束仍由项目决定 |
| [Taste Skill](https://github.com/Leonxlnx/taste-skill) | `design-taste-frontend` | 新产品页、作品页、解释页需要立意、构图与更好的视觉表达 | 读其当前设计方法，结合内容推断；不照搬落地页字体禁令、滚动劫持或不适用的框架要求 |
| 同上 | `redesign-existing-projects` | 审查/改造已有页面，或用户指出不直观、不好看、AI 味 | 先读实现与真实页面，按其审查方法定位高收益改动，再由当前范围与个人反馈排序 |

小修明确时只读取相关条目；整页需要时可组合一位设计方法源与一位审查方法源，不要求每次全部遍历。不为读取 skill 自动启动子 Agent、改变执行工作流或复制第三方目录进项目。

## 每轮怎样接起来

1. **本 skill 读题**：当前任务、已有品牌与适用反馈，指出一个值得改善的内容表达。
2. **选专业入口**：根据上表，读取实际安装路径下的最新 SKILL.md；再沿其相对路径读必要参考/脚本，不凭仓库名猜 skill 名。
3. **适配后落地**：保留有效方法，依据内容作构图和交互取舍；当前明确要求、项目约束和有范围的认可反馈优先。原生/已有组件能完成时不因外部配方换框架。
4. **真实审查**：按任务检查关键静态画面、实际操作、窄屏、键盘和减少动态效果；明确哪些脚本真的跑过，不把技术检查当审美认可。
5. **只回流差异**：把用户反馈、适配经验和路由改进写回本 skill；目录、脚本、配方继续用上游，不逐版抄成内置副本。

## 安装与路径

三个 setup 的共用同步器默认补装这四个 skill，随后用 `npx skills update` 更新已登记第三方；精确名单与命令在仓库根 `skills-external.sh`。

单独安装也可使用：

```bash
npx -y skills@latest add nextlevelbuilder/ui-ux-pro-max-skill --skill ui-ux-pro-max -g -y --agent pi
npx -y skills@latest add alchaincyf/huashu-design --skill huashu-design -g -y --agent pi
npx -y skills@latest add Leonxlnx/taste-skill --skill design-taste-frontend redesign-existing-projects -g -y --agent pi
```

这里 `--agent pi` 使用 CLI 的全局共享目录 `~/.agents/skills/`；不要求安装 Pi 本体。Pi/OpenCode/Codex 通过各自扫描机制读取该目录；装了 Claude Code 时套件也添加其入口。重开会话刷新 skill 发现。

- **定位**：优先宿主提供的 skill 列表/实际加载路径；共享安装通常为 `~/.agents/skills/<实际名>/SKILL.md`。相对路径按该入口目录解析，不按当前项目目录。
- **技能不等于执行环境**：安装不会替你配置浏览器、Python 包、GSAP 或 hooks。用外部脚本前读其依赖和副作用；按任务补件，不为了获得文字参考运行上游安装器。
- **缺失/失效**：说明具体缺项，给上面的精确安装命令；有安装授权时补装，否则使用可用方法并标明降级。没有读到不冒称已调用，脚本不可用不冒称已验收。
- **更新与冲突**：第三方副本由上游管理，update 可覆盖直接修改。个人偏好保存在本 skill；同名本地/其他源、Claude 中有差异的同名副本保留并告警，逐个处理不连带阻止其他依赖。
- **更新确认**：沿用 CLI 原始输出；skills@1.7.1 的部分网络检查失败仍退出 0，遇到检查错误重跑，不能只凭退出码声称全部最新。

复制 personal-ui-taste 到另一台机器只迁移我们的记录；外部依赖在目标机重新安装，不连带复制整份上游资源库。
