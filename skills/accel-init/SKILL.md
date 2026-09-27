---
name: accel-init
description: 深度学习算力平台初始化主入口：探测（或由用户直说）加速器平台与现状，搭 Python 双栈底座（miniconda+uv+清华源），按平台调研 wheel 矩阵/fork/生态兼容，出方案、执行、走验证阶梯，最后交棒 accel-skill-template 落盘。Use when setting up a fresh compute server for deep learning（CUDA/MUSA/Ascend/ROCm 等驱动、SDK、PyTorch、triton、transformers 生态），when asked 初始化算力环境/装平台栈/新服务器配置深度学习环境，or when a platform stack needs repair and re-validation. 只做 Python 环境不涉平台时直接按常规流程；落盘模板细节看 accel-skill-template。
---

# accel-init：算力平台初始化编排

线性六阶段，每阶段产出明确再进下一阶段；任何一步实况与预期不符，停下对齐而不是硬走。

## 阶段 0：确定平台与现状

先探测，用户已直说平台时也抽查验证：

```bash
# 厂商 smi 工具（命中任一即强信号）
nvidia-smi -L 2>/dev/null; mthreads-gmi 2>/dev/null; npu-smi info 2>/dev/null; rocm-smi --showproductname 2>/dev/null
lspci | grep -iE 'nvidia|display|3d|accelerator|processor.*musa|huawei|amd/ati'   # vendor ID 交叉确认
ls /dev/nvidia* /dev/davinci* /dev/musa* 2>/dev/null
# 驱动/SDK/运行时现状
lsmod | grep -E 'nvidia|mthreads|davinci|amdgpu'; ls /usr/local/ | grep -iE 'cuda|musa|ascend|rocm|CANN'
```

对照 [platforms.md](platforms.md) 的注册表：平台、检测命令、官方入口、已知生态结论。
探测不清或多种加速器并存 → 问用户，不猜。

**现状分级**（决定后面阶段的范围）：驱动+SDK 全有 / 只有驱动 / 裸机。共享集群通常是第一种。

## 阶段 1：访谈（只问影响行为的）

- root/sudo 有无 → 决定驱动层装不装（无 root 且无驱动 → 停，交回用户找管理员）。
- 装到哪层：最小 torch 栈，还是 +transformers/vllm/分布式。
- 独占还是共享机 → 命名规范、缓存位置、测试卡位（别人占用的卡不测）。
- SDK/版本有无指定（无指定则调研后给推荐行让用户拍板）。

## 阶段 2：Python 双栈底座（与平台无关，先搭）

约定：**miniconda 与 uv 都装好，用户爱用哪个用哪个**；三处默认源配清华：

- miniconda 安装到 `{{用户认可的目录}}`（共享机放大容量盘；装官方版，安装包可走清华 anaconda 镜像）。
- uv：官方安装脚本或 pip 装，任一可用方式。
- 源配置三处：pip（`pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple`）、conda（`~/.condarc` 清华 channels）、uv（`UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple`，写进 `~/.config/uv/uv.toml` 或 shell 配置）。
- apt 源**只提醒不改**：告知清华/中科大镜像地址与手动换法，是否换由用户决定（发行版格式差异大，改错会搞坏 apt）。
- 底座事实全部记入宿主机层（阶段 5 落盘）。

已有 conda/uv/pip 配置的，逐项查实况后只补缺，不覆盖既有配置（尤其已有私密/内网源时保留本机值）。

**数据底座**（算力服务器必做，与平台无关）：按 [model-datasets](../model-datasets/SKILL.md) skill 落地——/data 大盘准备（按现状决策：直接用/软链/初始化 LVM+fstab）、`/data/models|datasets|hub` 目录、uv tool 装 `hf`/`modelscope` CLI、镜像环境变量（HF_ENDPOINT=hf-mirror、HF_HOME、HF_HUB_DISABLE_XET=1）、`dl` 脚本与验证清单（下个 tiny 模型试通后清理）。/data 初始化含分区/格式化，动手前先向用户确认盘是空的。

## 阶段 3：平台调研

按 platforms.md 注册表的入口逐项查证（web 可用则查上游文档/发布矩阵/issue；不可用则让用户提供资料，不臆断）：

1. **兼容集**：OS ↔ 驱动 ↔ SDK ↔ 工具链版本约束（官方矩阵）。
2. **wheel 矩阵**：厂商 pip index 上 `torch / torch 后端包 / torchvision / torchaudio / triton(平台版) / tilelang 类` 的可用版本行 × Python ABI；`python -m pip index versions <pkg> --index-url <厂商源>` 实查。
3. **生态兼容**：transformers/accelerate/vllm 等是上游原生支持、厂商 fork（分支+版本）还是不支持——逐库记录证据链接。
4. **防串要点**：公共 CUDA wheel 哪些包会顶掉平台 torch（torch/torchvision/triton/flash-attn/bitsandbytes/nvidia-*）。
5. 现状检查：已装 SDK 的版本、用户态目录、LD_LIBRARY_PATH 约定。

产出：候选方案（通常 1–2 个版本行）+ 步骤清单 + 风险点，给用户拍板。

## 阶段 4：执行与验证阶梯

- 用户态优先；root 操作（驱动、内核模块、系统包）逐条列出并取得明确确认再动。
- 验证阶梯逐级走，每级通过再上一级：
  L1 工具链/版本查询 → L2 ldd 无缺库 → L3 单设备可见+小 matmul+autocast+synchronize → L4 单进程通信库 → L5 双进程 torchrun all-reduce → L6 短真实 workload。
- 任何一级失败：回阶段 3 重查兼容集，不重复硬装。
- 全程记录：确切版本、命令、路径、输出摘要（脱 PID/作业名）——阶段 5 落盘要用。

## 阶段 5：落盘交棒

按 [accel-skill-template](../accel-skill-template/SKILL.md) 把验证过的知识固化为四层 skill：
平台三层（install / pytorch-python / code-porting）落本机 `~/.agents/skills/`，宿主机事实进 host 层。
平台层若对其他机器普适，跑 `platform-environment-skill-audit` 脱敏后回流 `brilliantrough/agent-skills` 仓库。

## 边界

- 本 skill 不写代码、不移植项目——那是 `<platform>-pytorch-code-porting` 的事。
- CPU-only 工作站配 Python 底座：阶段 2 单独适用，其余阶段跳过。
- 每台机器的平台栈事实只在宿主机层，平台通用知识只在平台三层，两层不混。
