# `<platform>-<os>-install` 系统层模板

> 使用：复制本骨架到 `~/.agents/skills/<platform>-<os>-install/SKILL.md`，填入已验证内容，删掉不适用的节。`{{...}}` 为占位符。落盘规则见 accel-skill-template/SKILL.md。

---
name: {{platform}}-{{os}}-install
description: Use when installing, upgrading, or troubleshooting {{厂商全名}} {{平台名}}（{{工具链名}}、驱动、SDK、{{通信库}}） on {{OS 发行版}} {{架构}}; covers {{用户态安装 / 系统安装}}、Python 兼容性、动态库与验证。
---

# {{平台名}} on {{OS}} {{arch}}

## Operating principles

- 只装本项目需要的层；每步先检查现状再动手。
- {{用户态优先 / 需要 root 的部分}}约定：{{驱动是否已由管理员装好；本 skill 覆盖哪些层}}。
- 破坏性动作（卸载、覆盖系统库、改内核模块）必须先向用户确认。

## Architecture

{{层次图：驱动 → 运行时 → SDK/工具链 → 通信库 → Python 绑定，各层版本互相约束什么}}

## Inspect before changing anything

```bash
{{检测命令：厂商 smi / 版本查询工具 / lsmod / dpkg -l | grep ...}}
```

{{每条命令的预期输出与含义；已装/未装/版本不匹配三种判定}}

## Choose a compatibility set

- 兼容三元组/矩阵：{{OS ↔ 驱动 ↔ SDK 版本 ↔ 加速卡型号}}，来源 {{官方矩阵链接或文档章节}}。
- 当前选型：{{版本}}，原因：{{最新稳定 / 与已有驱动匹配 / Python ABI 可用}}。

## Versioned user-space layout

```text
{{安装根目录约定，如 $HOME/opt/<platform>-X.Y/}}
```

- {{路径内容：bin/lib/include 各在哪；多版本共存规则；LD_LIBRARY_PATH 约定}}。

## Download and integrity

{{下载渠道：官方离线包 / 厂商 apt(yum) 仓库 / 直接 URL；验签步骤（keyring、Release.gpg、哈希）；下载闭包命令}}

## Manual environment configuration

{{环境变量清单（PATH/LD_LIBRARY_PATH/厂商变量）、写入哪个 shell 配置、激活脚本}}

## {{平台特有依赖}}

{{如 MPI、MKL、固件、内核头、容器运行时；只列真实遇到的}}

## Install Python packages

{{指向 <platform>-pytorch-python；本层只装与 Python 无关的部分}}

## Validation ladder

从低风险到高风险逐级验证，每级通过再上一级：

```bash
{{L1 工具链：which + 版本查询}}
{{L2 动态库：ldd ... | awk '/not found/'}}
```

```bash
{{L3 单设备：python 内设备可见 + 小 matmul + synchronize}}
```

{{L4 单进程通信库 → L5 双进程 torchrun all-reduce → L6 短真实 workload → L7 全设备}}

## Failure patterns

| 症状 | 原因 | 处置 |
| --- | --- | --- |
| {{真实踩过的}} | | |

## Completion criteria

{{什么状态算装完：哪些命令通过、哪些文件存在、哪级阶梯走完；明确写"未验证项"如算 }}
