# 平台注册表（accel-init 阶段 0/3 用）

用途：给"检测 → 官方入口 → 已知生态结论"一张速查表。**不是安装教程**——安装知识在验证后按 accel-skill-template 落盘的平台层 skill。未在本仓库验证过的条目标 `(未验证)`，使用前先查上游。

## NVIDIA CUDA

| 项 | 内容 |
| --- | --- |
| 检测 | `nvidia-smi -L`；`ls /dev/nvidia*`；`lspci` NVIDIA vendor `10de` |
| 驱动/工具 | 驱动 `nvidia-smi` 报版本；CUDA toolkit `/usr/local/cuda*`（仅编译扩展需要——**pip wheel 自带 CUDA runtime**，纯训练/推理不需系统 toolkit） |
| PyTorch | 官方轮子 `download.pytorch.org/whl/cu{{XXX}}`；`pip install torch --index-url ...` 或直接 PyPI（默认即 CUDA 版） |
| triton/tilelang | 上游 PyPI 原生支持 |
| transformers 生态 | 上游原生支持（基准平台，无 fork 问题） |
| 已落盘 skill | 无需（官方矩阵足够；首次初始化仍改写三件套为 CUDA 版） |

## Moore Threads MUSA

| 项 | 内容 |
| --- | --- |
| 检测 | `mthreads-gmi`；`musa_version_query`；`lspci` Moore Threads |
| 驱动/工具 | mtgpu 驱动 + MUSA SDK（musart/toolkit/muDNN/MCCL） |
| PyTorch | 厂商 index `dl.mthreads.com/repo/api/pypi/pypi/simple`；`torch`+`torch_musa`（本地版本带 `+musa` 后缀） |
| triton/tilelang | 厂商 triton（PyPI 同名！）、`tilelang_musa` |
| transformers 生态 | transformers/accelerate 上游支持（torch_musa README 列明）；pytorch3d/pytorch_sparse 等为厂商 fork |
| 已落盘 skill | `accel-*` 三件套（当前实例即 MUSA，无需改写） |

## 华为 Ascend NPU

| 项 | 内容 |
| --- | --- |
| 检测 | `npu-smi info`；`ls /dev/davinci*`；`lspci` Huawei；多为主机 aarch64（`uname -m`，aarch64 上部分生态包无预编译 wheel） |
| 驱动/工具 | 驱动+固件（root）→ CANN Toolkit（版本与驱动强绑定，官方兼容矩阵为准）(未验证) |
| PyTorch | `torch_npu`（PyPI 有发布，或厂商下载页匹配 CANN 版本的 wheel）；torch 版本须与 torch_npu 匹配 (未验证) |
| triton/tilelang | 平台自有编译栈，上游 triton 不适用 (未验证) |
| transformers 生态 | 上游 transformers 支持 `npu` device（device_map/accelerate 有 NPU 路径）；vllm-ascend 为独立 fork (未验证) |
| 已落盘 skill | 首次走完即改写 `accel-*` 三件套为 CANN 版 |

## AMD ROCm

| 项 | 内容 |
| --- | --- |
| 检测 | `rocm-smi`；`amd-smi`；`ls /dev/kfd /dev/dri` |
| 驱动/工具 | ROCm 栈（amdgpu 驱动 + HIP runtime + rocPRIM/RCCL 等），官方支持矩阵限定发行版与内核 (未验证) |
| PyTorch | 官方轮子 `download.pytorch.org/whl/rocm{{X.Y}}`；device 名仍为 `cuda`（HIP 转译）——代码层与 CUDA 几乎同源 |
| triton/tilelang | 上游 triton 原生支持 AMD backend |
| transformers 生态 | 上游原生支持 |
| 已落盘 skill | 首次走完即改写 `accel-*` 三件套为 ROCm 版 |

## 其他/新平台（含 PPU 等）

通法，不预设知识：

1. `lspci` 拿 vendor/device ID + 厂商名 → 官网文档找 smi 工具与 SDK 名。
2. 查"{{厂商}} pytorch"：官方 index / fork 仓库 / 兼容声明，三者必居其一。
3. 装完走 accel-init 阶段 4 验证阶梯，结论落盘成新平台行 + 平台层 skill。
4. 首次走完按 accel-skill-template 改写 `accel-*` 三件套，回流前跑 `platform-environment-skill-audit`。

## 检测命令速查

```bash
for c in nvidia-smi mthreads-gmi npu-smi rocm-smi amd-smi mx-smi ixsmi; do command -v $c >/dev/null && echo "HIT: $c"; done
lsmod | grep -iE 'nvidia|mthreads|davinci|amdgpu'
ls /usr/local/ 2>/dev/null | grep -iE 'cuda|musa|ascend|cann|rocm'
```
