---
name: accel-skill-template
description: 深度学习平台初始化完成后的落盘模板套装：把验证过的平台知识固化为四层 skill（系统安装 / PyTorch wheel / 代码移植 / 宿主机环境）。Use when an accelerator platform setup just finished and needs to be distilled into reusable skills, when filling or updating platform skill templates, or when asked to 落盘/沉淀/固化为 skill/回流入仓库. 模板填空、增删改查都从这里走；不在初始化执行期读模板细节（那是 accel-init 的事）。
---

# accel-skill-template：四层落盘模板

## 何时落盘

- 一轮平台初始化**全部走完且验证阶梯通过**后（通常由 accel-init 最后一步交棒到这里）。
- 事后补充/修订：某条规则被新事实推翻、版本行过期、新增 fork 兼容结论时。
- 不在方案还没跑通时预写——模板里只允许出现**已验证**的内容，未验证的写 `(未验证)` 或不写。

## 四层槽位与命名

| 层 | skill 名（固定模式） | 装什么 | 落在哪 |
| --- | --- | --- | --- |
| 系统层 | `<platform>-<os>-install` | 驱动/SDK/工具链安装：兼容集选取、用户态布局、下载验签、验证阶梯 | 本机 `~/.agents/skills/`；脱敏后可回流仓库 |
| Python 层 | `<platform>-pytorch-python` | 双 index 纪律、版本匹配矩阵、环境变量、安装流程、验证、常见失败 | 同上 |
| 代码层 | `<platform>-pytorch-code-porting` | API 映射表、设备探测、AMP、分布式、第三方包兼容、迁移清单 | 同上 |
| 宿主机层 | `<host>-environment`（如 `local-python-environment`） | 本机 conda/uv 路径、命名法、缓存、已装栈的事实记录 | **只留本机**，永不回流仓库 |

`<platform>` 用官方短名（musa/cuda/ascend/rocm…），`<os>` 如 `ubuntu2204`。已填好的参考实例：`musa-ubuntu2204-install`、`musa-pytorch-python`、`musa-pytorch-code-porting`。

## 填写规则

1. 按模板骨架逐节填；对当下平台无意义的节**整节删掉**，不要留空标题。
2. 平台事实（型号、SDK 版本、index URL、版本行）与宿主机事实（用户名、路径、IP、主机名）严格分开：前者留在前三层，后者只进宿主机层。
3. 版本匹配矩阵写"查到的当前行 + 查询命令"，不要只写死结果；附来源链接与查询日期。
4. 验证节贴真实命令与关键输出行（脱去 PID/作业名/私有数据），并写明"预期无输出/预期某行出现"。
5. 失败模式只收录真实踩过的，每条带症状→原因→处置。
6. frontmatter description 写清触发词（平台名、包名、工具名、场景词），并指明与相邻 skill 的分工（如"装环境用 xxx，写代码用本 skill"）。

## 回流仓库流程

1. 用 `platform-environment-skill-audit` 审计候选文件：用户名/路径/IP/凭据/验证产物泄露、"本机当通用"的越界。
2. 修正后拷入本仓库 `skills/<name>/`，更新仓库 AGENTS.md 的 skill 计数。
3. `git commit && git push`；各机器 `npx skills add brilliantrough/agent-skills --all -g -y` 生效。
4. 宿主机层文件即使被审计通过也**不回流**——它的价值就是绑定本机。

## 模板文件

- [templates/platform-install.md](templates/platform-install.md)：系统层骨架（源自 musa-ubuntu2204-install 的 12 节结构）。
- [templates/platform-pytorch.md](templates/platform-pytorch.md)：Python 层骨架（双源纪律 + 匹配矩阵 + 防串）。
- [templates/platform-porting.md](templates/platform-porting.md)：代码层骨架（14 节结构，含 API 映射表位）。
- [templates/host-environment.md](templates/host-environment.md)：宿主机层骨架（conda/uv 事实 + 命名法 + 已装栈记录）。
