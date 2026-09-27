# `<platform>-pytorch-python` Python 层模板

> 使用：复制本骨架到 `~/.agents/skills/<platform>-pytorch-python/SKILL.md`。核心是"双源纪律 + 匹配矩阵 + 防串"，参考实例 musa-pytorch-python。

---
name: {{platform}}-pytorch-python
description: Use when creating or repairing a Python environment for {{平台名}} PyTorch（{{torch 后端包名}}、厂商 torchvision/torchaudio、{{平台 triton 名}}、{{通信库}}）；explains {{厂商}} versus public Python indexes, supported upstream libraries, version matching, and validation. 写代码/移植用 {{platform}}-pytorch-code-porting，装系统层用 {{platform}}-{{os}}-install。
---

# Python and PyTorch on {{平台名}}

## Two package indexes

```bash
export {{VENDOR}}_PIP_INDEX={{厂商 pip index URL}}
export PYPI_INDEX={{公共源，含镜像，如清华 pypi}}
```

- 厂商 index 含平台二进制包**和**大量普通镜像包；"厂商源里有"不等于"必须从厂商源装"。
- 公共源走镜像（`pip config set global.index-url` / conda channels / `UV_DEFAULT_INDEX`，见宿主机层 skill）。

## 哪些包族从哪个源装

| 包族 | 安装源 |
| --- | --- |
| `torch` | 厂商源的 {{平台标记}} wheel（本地版本号带 `{{+platform 标记}}` 后缀） |
| `{{torch 后端包，如 torch_musa}}` | 厂商源；版本必须与 torch 匹配 |
| `torchvision` / `torchaudio` | 厂商源匹配 wheel（若存在） |
| `triton`（平台版）/ `{{tilelang 类}}` | 厂商源专用构建（包名可能与上游同名！） |
| `{{vllm/flash-attn/deep-gemm 等推理与 kernel 族}}` | 厂商或项目 fork；逐个验证发行兼容性 |
| transformers / accelerate / numpy / scipy 等纯 Python 生态 | 公共源（若上游原生支持本平台） |

{{已确认的 fork 清单：哪些库无上游支持、须用厂商 fork 及其分支/版本要求；只列真实查证的}}

## Never mix indexes casually

简单模式（日常）：{{普通依赖默认源、平台包显式 --index-url 厂商源}}。

严格模式（需要证明每个包来源时）：

```bash
python -m pip install --no-deps --index-url "$VENDOR_PIP_INDEX" "torch==<匹配版本>" "{{torch 后端包}}==<匹配版本>"
python -m pip install --index-url "$PYPI_INDEX" <按 pip check 补齐的普通依赖>
```

装任何 requirements 前先审查其中 `torch / torchvision / triton / flash-attn / bitsandbytes / nvidia-* / NCCL 约束 / CUDA 扩展`——普通 CUDA requirements 会静默顶掉平台 torch。

## Select matching versions

```bash
python -V
python -m pip index versions torch --index-url "$VENDOR_PIP_INDEX"
{{同上逐包查 torch 后端包/torchvision/torchaudio/triton}}
```

匹配矩阵一行 = `Python ABI ↔ SDK 版本 ↔ torch ↔ torch 后端包 ↔ triton`。
当前验证行（{{查询日期}}）：{{行}}。换 SDK 必须重查，不得跨 SDK 复制版本行。

## Required environment variables

| 变量 | 作用 | 写在哪 |
| --- | --- | --- |
| {{如 MUSA_VISIBLE_DEVICES / 厂商 LD_LIBRARY_PATH / torch 后端加载变量}} | | |

## Installation workflow

{{从建环境到装完的有序步骤；每步的预期输出}}

## Validation

```bash
python -m pip show torch {{torch 后端包}}   # 版本须带平台后缀
python -m pip check                          # 依赖一致
```

```bash
{{ldd 检查 torch 后端 .so 与 libtorch_global_deps.so，awk '/not found/' 无输出}}
```

```python
# 设备可见 + 小 matmul + autocast + synchronize 的最小脚本
```

分布式：先单进程 {{通信库}}，再双进程 `torchrun` all-reduce；别人占用的卡上不测试。

## Common failures

| 症状 | 原因 | 处置 |
| --- | --- | --- |
| {{真实踩过的：如公共源 torch 顶掉平台 torch、版本错配 import 崩、ldd 缺库}} | | |
