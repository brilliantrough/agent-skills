# personal-ui-taste

可迁移、可持续演化的个人前端品味 skill：保存喜欢什么、拒绝什么，以及真实交互问题的解决办法。

## 安装与调用

将整个 `personal-ui-taste/` 放到 `~/.agents/skills/` 下，入口必须是：

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

当前已收录 S01「浅色信息密集界面」与 S02「冷灰蓝预览型工作台」。共享柔和主题与基础元素语言；密集灯带和稀疏可跳转状态块按场景共存。

## 跨服务器

复制整个目录即可；所有内部引用均为相对路径：

```sh
# 先确认目标机器存在 ~/.agents/skills，再复制；目标已有同名目录时先比较并合并。
scp -r ~/.agents/skills/personal-ui-taste USER@HOST:~/.agents/skills/
```

复制是手动同步，不会自动传播之后的修改。可把该目录纳入自己的 dotfiles/skills Git 仓库管理；不要把旧版本直接覆盖另一台机器中新积累的规则。

## 文件

- [SKILL.md](SKILL.md)：入口、通用品味、场景索引与工作方式。
- [patterns.md](patterns.md)：S01 的图表、浮层、筛选、状态时间轴、响应式模式和踩坑。
- [evolution.md](evolution.md)：按场景增删改查、处理冲突、记录证据与版本。
- [scenarios/preview-workbench.md](scenarios/preview-workbench.md)：S02 的主题配对、字体、矩形面板、按钮、预览卡片与稀疏状态。

不需要提前设计所有未来场景：明确反馈 → 当前场景落地 → 认可后沉淀 → 在下一项目复用。
