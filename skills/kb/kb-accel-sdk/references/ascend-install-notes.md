# Ascend 软件源与 TileLang 安装经验

记录日期：2026-10-23～24，2026-10-25 回流。已验实例：910B2 / aarch64 / Ubuntu 22.04 / CANN 9.0.0 / Python 3.11 / torch 2.9.0 / torch-npu 2.9.0.post2。其他SDK、芯片或宿主未验。

## 软件源：包本身与依赖分开取

- 服务器曾在`https://triton-ascend.osinfra.cn/pypi/simple`解析依赖时遇到`expected distribution for pybind11, got distribution for triton-ascend`。这是当时的源行为，不宣称源永久失效。
- 对这种专用源，只从明确的源或wheel取得目标包，使用`--no-deps`；按实际METADATA从可信公共源补依赖，并先钉住torch/torch-npu兼容组合。`--no-deps`不证明依赖已齐。
- uv多索引解析还受索引优先级约束；先核对目标包命中哪个索引，再选择明确wheel或包级来源。不要把`unsafe-best-match`设为全局解决方案：跨源选择更高版本会扩大依赖混淆风险。见[uv索引说明](https://docs.astral.sh/uv/concepts/indexes/)。

## TileLang：区分后端与安装组合

2026-10-24服务器记录：`tile-ai/TileLang-Ascend`默认分支为`ascendc_pto`（AscendC/PTO）；另有`npuir`（NPU IR/MLIR）。两条后端路线各有版本线，替换前先确认路线。

| Release / wheel标识 | 已知条件 | 使用边界 |
|---|---|---|
| `v0.1.1.010-release` / `0.1.1.10+ubuntu.20.4.cann900-cp311-cp311-linux_aarch64` | 上述Ubuntu 22.04、CANN 9.0.0环境已有真实运行记录 | 这是一条已验组合；wheel本地标签之外的兼容性未验 |
| `TileLang-ascend-v0.1.2.000-release` / `0.1.4+ubuntu.24.3.cann910-cp312-…-linux_aarch64` | 服务器记录为CANN 9.1.0、cp312路线 | 不能装进cp311；OS/SDK支持另查该release，不把标签直接译成发行版名称 |
| `v0.1.1.030-pre-release` / `0.1.1.30+ubuntu.22.4.npuir-cp311-…-linux_aarch64` | NPU IR路线 | 与上述AscendC/PTO组合是不同路线，未验 |

- 从[官方Releases](https://github.com/tile-ai/TileLang-Ascend/releases)取得匹配CANN、Python ABI、架构与系统依赖的wheel；公共PyPI的同名包先核对是否为昇腾后端。
- 当时wheel对`torch`/`torch-npu`未约束版本；在隔离环境先固定匹配版本，再用`--no-deps`装wheel并补齐其余依赖，避免改变评测环境。
- 编译前加载目标CANN环境，确认`ASCEND_HOME_PATH`与bisheng。`cstdint file not found`曾因bisheng选择gcc-12而主机缺g++-12/libstdc++头文件；补同版本C++工具链，非所有主机都要安装g++-12。
- 新示例可能依赖旧wheel没有的API。提交数、文件数或star数不能证明编译器未变或旧版足够；核对所需接口与最小真实运行，再决定是否按官方说明源码构建。

## 重查与专业入口

- [仓库元信息](https://api.github.com/repos/tile-ai/TileLang-Ascend)：当前默认分支。
- [分支](https://api.github.com/repos/tile-ai/TileLang-Ascend/branches)与[发布](https://api.github.com/repos/tile-ai/TileLang-Ascend/releases)：路线、wheel和依赖；注意分页，有限文件列表不证明没有其他改动。
- 语法、编译pass、profiling与实测配方交给独立[kernel-knowledge](https://git.nju.edu.cn/iscl/kernel-knowledge)的`tilelang-ascend`等技能；本库只维护安装/生态导航。按需自行安装，先读领域仓库`INSTALL.md`；装有本套件research组时，交接细节见`kernel-worker/references/kernel-knowledge.md`。
- 来源：服务器回流包中的`kb-accel-sdk`；领域库`cases/quantization/docs/handbook/tilelang-ascend.md`与`tools/setup_tilelang_env.sh`保存安装实例，`cases/quantization/curated/full-gemm-timings.json`保存相关运行环境。领域库维护自己的复现环境，本页不复制其安装脚本。
