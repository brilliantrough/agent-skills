---
name: kb-accel-sdk
description: 公共知识库：各大加速计算平台（CUDA/MUSA/Ascend CANN/ROCm/阿里PPU/沐曦MACA）的 SDK 组成、安装方式、triton 与 tilelang 生态、vllm 与 sglang 推理框架生态速查。Use when working on any accelerator server, choosing SDK/wheel/inference-framework versions, or when a platform-specific package/behavior surprises you. 知识类 skill：可被覆盖刷新，不做本机特化；新事实经 writing-skill 流程回流仓库。触发词：SDK 组成、装 CANN、torch_npu、vllm 昇腾、sglang 国产卡、triton fork、tilelang、PPU。
---

# 加速平台 SDK 与生态知识库

> 知识类 skill：内容为跨平台公共知识（调研日期 2026-09-27，易过期条目附重查入口）。本机特有事实不写这里（宿主机层管）。**结论与实机冲突时以实机为准，并回流更新本库。**

## 平台总览

| 平台 | 厂商 | 软件栈 | smi | torch 后端 | 通信库 | wheel 来源 |
| --- | --- | --- | --- | --- | --- | --- |
| CUDA | NVIDIA | 驱动 + CUDA Toolkit（nvcc/cuBLAS/cuDNN/NCCL/TensorRT） | nvidia-smi | 原生 | NCCL | PyPI / download.pytorch.org/whl/cuXXX |
| MUSA | 摩尔线程 | mtgpu 驱动 + MUSA SDK（musart/toolkit/muDNN/MCCL） | mthreads-gmi | torch_musa | MCCL | dl.mthreads.com 厂商 index |
| Ascend | 华为 | 驱动+固件 + CANN（toolkit/kernels/NNAL，含 HCCL、ATB；推理另有 MindIE） | npu-smi | torch_npu | HCCL | PyPI(torch_npu) + hiascend.com 离线包 |
| ROCm | AMD | amdgpu 驱动 + ROCm（HIP/hipBLAS/MIOpen/RCCL） | rocm-smi | 原生（HIP 转译，device 仍叫 cuda） | RCCL | download.pytorch.org/whl/rocmX.Y |
| PPU | 阿里平头哥 | 真武 810/810E，GPGPU 路线；公开 SDK 文档极少（2026-01 才官方证实存在） | (未验证) | (未验证) | (未验证) | 阿里云渠道，无公共源 |
| 沐曦 MACA | 沐曦 | MXMACA（mcBLAS/mcDNN/mcFlashAttention） | mx-smi | mcPytorch | mcCL(未验证) | 沐曦开发者社区镜像/发布包 |

寒武纪 MLU（Neuware/torch_mlu）、海光 DCU（DTK，ROCm 系）也常遇到，速记备查。

## 生态矩阵（关键防坑表）

| 框架 | CUDA | ROCm | Ascend | MUSA | PPU |
| --- | --- | --- | --- | --- | --- |
| triton | 上游原生 | 上游原生 | **triton-ascend**（triton-lang org 的 fork） | **Triton-MUSA**（fork，已至 3.6；PyPI 与上游同名，装错不报错） | 未验证 |
| tilelang | 上游原生 | 上游(HIP) | **tilelang-ascend**（tile-ai org） | **tilelang_musa**（厂商 index） | 未验证 |
| vllm | 上游原生 | 上游原生 | **vllm-ascend**（vllm-project org 官方插件，版本号对齐上游 vllm） | **vLLM-MUSA**（官方后端，开源 fork） | 未验证 |
| sglang | 上游原生 | 未验证 | 官方支持（2025-08 起，`--device npu --attention-backend ascend`，sgl-kernel-npu 仓库） | 已合入主线（2026-05，源码装 + sgl-kernel） | 未验证 |

规律：**推理/编译生态正在从"厂商自维护 fork"转向"官方仓库插件化"**（vllm hardware plugin 机制、sglang 合入主线），查版本时先看官方仓库的硬件支持矩阵，再看厂商 fork 的 release 行。

## 各平台要点与坑

### CUDA（基准）
- pip 装 torch 默认即 CUDA 版；只有源码编译扩展才需系统 toolkit，运行只需驱动。
- 驱动版本 ≥ wheel 的 CUDA runtime 版本即可（向前兼容）；nvidia-smi 右上角就是驱动支持的 CUDA 上限。
- 容器路线最省心：nvidia-container-toolkit + 官方 NGC 镜像。

### MUSA
- MUSA SDK 5.1.0 对标 CUDA 12.8（2026-05 发布）；安装=官方 apt 仓库/离线包，用户态版本化目录。
- torch+torch_musa 从 `dl.mthreads.com` 厂商 index 装，本地版本带 `+musa` 后缀。
- 坑：`pip install torch` 会用公共 CUDA 版顶掉 `+musa` 版（静默失败，重查 `pip list | grep torch`）。
- CUDA 兼容层：torchada（`import torchada` 让 99% CUDA 代码跑 MUSA）+ MATE 算子库（FlashAttention/FlashMLA/DeepGEMM 接口）。

### Ascend CANN
- 版本强绑定链：驱动+固件 ↔ CANN ↔ torch_npu ↔ triton-ascend，以 hiascend 支持矩阵为准（未验证具体行，查官方矩阵）。
- triton-ascend 约束：Python 3.9–3.11；需先 source CANN 的 `set_env.sh`；与 torch_npu 版本配对（如某版要求 torch_npu==2.7.1，实查为准）。
- tilelang-ascend：CANN ≥ 8.3.RC1、torch_npu ≥ 2.6.0；wheel 从 GitHub Releases 按 CANN/Python/架构匹配下载。
- 硬件差异（写 kernel 必踩）：AI Core 分 Cube/Vector；每核 UB 仅 192KB（BLOCK_SIZE 大了溢出）；**越界访问无容错，直接 Device Hang——mask 必须严格**。
- vllm-ascend 用法：pip 装 `vllm-ascend==<对齐 vllm 版本>`；关键 env 如 `ASCEND_RT_VISIBLE_DEVICES`、`PYTORCH_NPU_ALLOC_CONF=expandable_segments:True`。
- 官方自有推理引擎 MindIE 与 vllm-ascend 并存，选型看场景（MindIE 商用闭源、vllm-ascend 社区开源）。

### ROCm
- 官方支持矩阵限定发行版+内核版本，装前必查（rocm.docs.amd.com）。
- device 名仍是 `cuda`（HIP 转译），CUDA 代码基本零改动；rccl 代替 nccl。
- 上游 triton/tilelang/vllm/sglang 原生支持（版本矩阵看 pytorch.org 与各框架 release notes）。

### PPU（阿里平头哥）
- 真武 810E：GPGPU 路线（非 ASIC），大规模部署在阿里云，出货一年以上（2026-01 官方证实）。
- 公开 SDK/文档极少：装环境不靠公共源（搜不到不是不存在），主路径=阿里云实例/容器镜像 + 阿里云文档与工单。
- 首次接触：先查实例规格文档里给出的镜像与运行时说明，把"有哪些预装、怎么用"问清再动手。

### 沐曦 MACA（速记）
- 轮子带 `+metax`/`+maca` 后缀（torch 2.6.0+metax、vllm 0.8.5+maca、triton 3.0.0+metax）；防串规则同 MUSA：公共源 `pip install torch` 会顶掉适配版。
- 安装主路径=沐曦开发者社区的 docker 镜像/发布包（容器要挂 `/dev/mxcd /dev/dri`）；MACA 版本号形如 mc2.32.0.3，与发布包严格配套。
- MACA 3.3 适配 PyTorch 2.8 全算子；推理支持 vllm/SGLang/Transformers。

## 通用防坑（全平台）

- 版本四元组：驱动 ↔ SDK ↔ torch 后端 ↔ 编译器 fork（triton/tilelang），任何一环升级都要重查整链兼容矩阵。
- `pip list | grep -E 'torch|triton|vllm'` 看**本地版本后缀**（+musa/+metax/+npu…）判断是不是平台适配版；无后缀≈公共版，多半是顶掉了。
- 公共源找不到平台 wheel 是常态，不是平台不支持——去厂商文档/下载中心（见 accel-init 阶段 3 调研路径）。
- 各平台可见设备变量不同：CUDA_VISIBLE_DEVICES / MUSA_VISIBLE_DEVICES / ASCEND_RT_VISIBLE_DEVICES / HIP_VISIBLE_DEVICES(ROCm)。

## 演化（本库随时准备被更新）

定位：经验流入点＝真实服务器上的实验与踩坑（装过、跑通、报错、版本不匹配都是素材）。流程：

1. 实机经验 → 找本库对应条目；没有就在正确的表/小节补一行，不新开孤儿小节。
2. 更新规则：结论带日期与证据（命令输出/官方文档链接）；`(未验证)` 条目实机验证后**转正或删掉**；被推翻的结论直接改写为当前正确版本（git 留痕，不保留过时叙述）。
3. 结构不变量：总览表 / 生态矩阵 / 平台小节 / 通用防坑四层形态保持；新平台＝总览一行＋小节一节；单平台专属的坑不上升为通用防坑。
4. 更新可以直接改在服务器本机副本上（演化发生地＝真机），改完走固定回路：下载到开发机 → 合入仓库 push → 本机重装拉新版。坑：本机修改未回流前别重跑 setup 的 kb 覆盖刷新（会冲掉它）。
