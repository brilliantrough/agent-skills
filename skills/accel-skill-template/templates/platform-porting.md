# `<platform>-pytorch-code-porting` 代码层模板

> 使用：复制本骨架到 `~/.agents/skills/<platform>-pytorch-code-porting/SKILL.md`。核心是"API 映射表 + 设备探测 + 生态兼容结论"，参考实例 musa-pytorch-code-porting（14 节结构）。宿主机事实不写这里，去 host 层。

---
name: {{platform}}-pytorch-code-porting
description: Use ONLY when writing, porting, reviewing, debugging, or running application code for {{平台名/型号}}，especially CUDA-to-{{平台}} migration、{{torch 设备名}}、{{可见设备变量}}、{{通信库}}、AMP、Transformers、distributed training、numerical parity、CUDA extension compatibility. Python 环境/包装机用 {{platform}}-pytorch-python。
---

# {{平台名}} PyTorch Development

## 1. Platform Facts

{{平台级事实：设备类型字符串、后端包名与导入方式、通信库名、可见设备变量、驱动查询工具、已验证的 SDK/torch 版本行（引用 Python 层 skill）、算力/显存特征。只写平台共性，不写本机路径}}

## 2. Core Migration Policy

{{移植总原则：如"新代码一律设备中立（.to(device)），旧代码按映射表最小替换"；哪些改动禁止（如不许用 hostname 选后端）}}

## 3. Environment Check Before Coding

```bash
{{写码前环境自检：后端包版本、设备可见、ldd、python -m pip check}}
```

## 4. Device Detection and Backend Abstraction

{{设备探测 helper 代码：accelerator_type()/accelerator_device() 模式}}

### CUDA-to-{{platform}} API map

| CUDA 写法 | 本平台等价 |
| --- | --- |
| `torch.device("cuda", i)` | {{}} |
| `torch.cuda.is_available()` | {{}} |
| `torch.cuda.synchronize()` / `empty_cache()` / `memory_*` | {{}} |
| `torch.cuda.Stream/Event` / `manual_seed` | {{}} |
| `backend="nccl"` | {{}} |
| `CUDA_VISIBLE_DEVICES` | {{}} |
| `nvidia-smi` | {{厂商 smi}} |
| {{CUDA allocator 环境变量}} | {{是否有效；无效则注明无效}} |

## 5. Minimal Single-Device Program

{{最小可跑程序：设备可见 → 分配 → matmul → autocast → synchronize，含预期输出}}

## 6. AMP and Numerical Stability

{{autocast 设备类型与 dtype、已知数值差异、梯度/稳定性坑；已验证的算子限制逐条列}}

## 7. Transformers and {{生态}}

{{逐库结论：上游原生支持 / 厂商 fork（分支+版本）/ 不支持；from_pretrained 的 device_map/accelerate 行为；已验证模型清单}}

## 8. Multi-GPU with {{通信库}}

{{init_process_group 用法、torchrun 启动、已知限制（如某 all_gather 形态）、先双进程再全卡}}

## 9. Memory, Timing, and Performance

{{显存查询 API 映射、计时代码、性能基线数字（带版本与日期）}}

## 10. CUDA Extensions and Third-Party Packages

{{原生平台扩展怎么编（编译器/头文件）、常见扩展（flash-attn/xformers/bitsandbytes 等）在本平台的替代品或 fork、不兼容清单}}

## 11. Debugging Backend Failures

{{错误分类→排查路径：import 崩（版本/缺库）、首次 kernel 失败（驱动/SDK）、数值异常（dtype/算子）、分布式挂起（通信库/网络）。日志与环境变量开关}}

## 12. Migration Audit Checklist

{{迁移完成前的逐条检查：设备字符串残留、.cuda() 残留、nccl 残留、可见设备变量、requirements 防串、最小程序通过、双进程通过}}

## 13. Agent Working Rules

{{agent 在本平台写码的纪律：先查环境再动手、静态检查先行、逐级运行阶梯、不臆断算子可用、执行成功≠数值对齐、贵重运行交用户}}

## 14. Sources and Freshness

- {{官方文档/仓库链接清单}}
- 本平台迭代快：依赖可用性/算子支持/性能结论使用前重查上游与本机环境。
