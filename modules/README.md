# 可选模块

一个模块 = 一个可选能力。根 `*-setup.sh` 不再为每个能力各写一份，只调用 `modules/run.sh` 统一分发；新增能力只需加一个目录。

```bash
bash modules/run.sh --list                      # 看有哪些模块、默认装不装
bash modules/run.sh --host pi                   # 逐个询问后安装(默认 N)
bash modules/run.sh --host opencode --only agent-reach
```

## 目录结构

```text
modules/<名>/
  setup.sh         必须。实现安装，文件头声明元数据
  README.md        建议。装什么、怎么退、怎么验
  AGENTS.block.md  可选。仅当确实需要每轮注入时才写（见下）
```

`setup.sh` 文件头（`run.sh` 只读这四行）：

```bash
# module: <名>          与目录名一致
# desc: <一句话说明>      提问时显示
# default: N            默认 N；写 Y 必须说明理由
# hosts: any            或 pi,opencode,codex,dsh
```

## 契约

| 要求 | 说明 |
| --- | --- |
| 接收 `--host <宿主>` | 宿主无关的模块直接忽略它；只有确实要分叉时才 `case "$host"` |
| 自身不提问 | 问一次由 `run.sh` 负责；`-y` 下默认 N 的模块自动跳过 |
| 幂等 | 重跑结果一致：已装就跳过并说明，不重复下载、不重复写配置 |
| 只改自己负责的东西 | 不动别人的配置、不删用户数据、不迁移已有安装 |
| 失败可重跑 | 中断后重跑能自愈，不留下让下次直接报错的半成品 |
| 输出可读 | 说明做了什么、跳过了什么、失败时给出手动命令 |

违反这些的模块会被 `scripts/check.sh` 或评审挡下。

## 什么时候不写 AGENTS.block.md

`AGENTS.tail.md` 的内容会进**每个项目、每次会话**的提示。所以只有"每轮都在起作用"的约定才配占这个位置——记忆系统的三件套、技术写作口径、上下文纪律。

显式调用的工具**不写**：`ppt-master` 做 PPT、`image_gen` 画图、`agent-reach` 读帖，靠 skill 的 `description` 就能被选中，写进 AGENTS 只是让所有人每一轮都为它付 token。

判定：**这东西是"每轮都在起作用"还是"被叫到时才起作用"？** 后者不写。

## 已有模块

| 模块 | 默认 | 说明 |
| --- | --- | --- |
| `agent-reach` | N | 官方只读检索 CLI + 无头浏览器；安装器来自 base 组的 `agent-reach-install` skill |

## 迁移节奏

现有内联块（codegraph、strictdoc、notify 插件等）暂时留在各 `*-setup.sh` 里。**改到它时顺手搬一个**，不做一次性大迁移：这四个脚本共 3900 行，其中大部分是宿主特有的配置合并，整体重写等于重写分发链路。

新能力一律走 `modules/`。
