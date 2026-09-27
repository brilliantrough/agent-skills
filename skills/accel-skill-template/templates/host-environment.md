# `<host>-environment` 宿主机层模板

> 使用：复制本骨架到**本机** `~/.agents/skills/local-python-environment/SKILL.md`（或带主机名的名字，如昇腾机上常见的 `system-profile` 式档案）。只装本机事实，永不回流仓库。参考实例：服务器上的 local-python-environment / musa-local-server / system-profile（昇腾机）。

---
name: local-python-environment
description: Use ONLY on this host when creating, repairing, inspecting, or naming Conda/uv Python environments; documents 本机硬件与存储布局、Python 底座安装位置、shell 行为、共享环境位置、缓存与命名规范，以及已装加速器平台栈的事实记录。触发词：{{模型放哪、大文件放哪、python 环境、装依赖、本机是什么硬件}}。
---

# Local Environment Profile（{{主机标识}}）

## 硬件与系统

| 项 | 值 |
| --- | --- |
| 主机 | {{主机名/架构/发行版}} |
| 加速器 | {{数量×型号、驱动/固件版本、查看命令}} |
| 厂商 SDK | {{版本、安装路径}} |
| 根盘 | {{设备→挂载点，只放系统，别堆数据}} |
| 数据卷 | {{LVM/直挂、容量、fstab 状态；扩容流程（pvcreate→vgextend→lvextend→resize2fs）与禁止事项（如别对已组卷的裸盘 fdisk/mkfs）}} |

## 目录与存储规则

{{大文件（模型/数据集）的统一入口与规则指针（通用约定见 model-datasets skill）；本机特有的目录/软链/挂载事实}}

## Python 底座事实（多套环境别搞混）

| 环境 | 路径 | 用途 | 包管理 |
| --- | --- | --- | --- |
| {{厂商 venv（如 CANN venv311）}} | {{}} | {{厂商库专用}} | {{禁止 pip install/升级（版本与 SDK 绑定）；需要厂商库时用它的 venv，而不是把厂商库装进项目}} |
| 系统 | {{}} | 系统工具 | apt |
| {{conda / uv 托管}} | {{}} | 按项目 | {{}} |

- conda 安装：{{路径/版本}}；激活方式；`auto_activate_base` 当前值。
- uv 安装：{{路径/版本}}；镜像源配置位置（`~/.config/uv/uv.toml`）。
- 镜像源现状（查实况，不假设）：

```bash
which conda && conda --version && conda env list
which uv && uv --version
python -m pip config list
conda config --show channels
```

- pip index：{{实际生效的源}}；conda channels：{{}}；uv：{{}}。

## 环境命名规范

{{共享机：`<用户标识>_<用途>`；独占机：{{约定}}。新建环境一律遵守；删除他人环境须所有者确认}}

## Creating an environment / Installing packages

{{本机建环境的命令习惯（conda create / uv venv 各自的触发场景）、装包时的 index 纪律要点（细节在平台层 skill）}}

## Environment records

{{环境清单记录在哪（如一张 manifest 表）：env 名 ↔ 用途 ↔ 平台栈 ↔ 创建日期}}

## Cache and storage

{{conda pkgs 缓存、pip 缓存、uv 缓存的位置与清理边界；`conda clean --all` 的禁用条件（他人环境/缓存使用中）}}

## Repair and cleanup

```bash
which python pip && python -m pip check
```

{{损坏环境优先重建而非反复混装；可删/不可删边界}}

## Installed platform stacks（factbook）

{{每装好一套平台栈追加一条：平台、SDK/用户态目录、验证过的 Python 栈（env 名+版本行）、验证阶梯通过日期、验证时输出摘要（脱 PID/作业名）}}

{{权威本地文件指引：本机若有 manifest/README 记录安装布局，先读哪个文件}}

## Coordination with platform skills

{{本文件只管宿主机事实；平台知识在 {{platform}}-{{os}}-install / {{platform}}-pytorch-python / {{platform}}-pytorch-code-porting；分工索引}}

## Safety boundaries

{{本机禁改清单：不动系统包、不动他人目录、sudo 类操作须用户确认、{{主机特有的边界}}}}
