# 用户查看timeline：生成文件，下载后打开

**用户说“我想看timeline／导出Perfetto／给我可视化文件”时触发。** Agent日常仍按性能流程自动分析trace；为人生成下载文件是按需交付，不把可视化变成每次优化的必做步骤。

## 1. 选对本次产物

- 优先复用目标版本已有的原始timeline，确认模型／算子、输入／batch、设备、阶段和采集窗口。多次采集列出候选，按模型、阶段与窗口选择，不按修改时间取最新文件。
- Ascend PyTorch优先`ASCEND_PROFILER_OUTPUT/trace_view.json`；原生msprof优先`mindstudio_profiler_output/msprof_*.json`。NVIDIA PyTorch可用`export_chrome_trace`结果。
- 只有汇总CSV不能还原完整时间线。带起时／耗时的逐任务表最多恢复实际覆盖的轨道；不要补造host活动、flow或设备任务。
- 没有timeline时说明缺项，按已有授权和预算补一个代表性短窗口。已有产物够用时不重新加载模型／跑评测，不为查看启动全量。
- PPU／MUSA通过Chrome Trace查看已有用户实践确认；取得当前版本的实际导出入口和样本后接入，不把方法记录缺失说成不可行，也不猜命令。

## 2. 生成可下载文件

原本可被查看器读取的Chrome Trace或原生Perfetto文件可直接交付。Ascend旧版本存在字符串`ts`、绝对时间戳精度和大flow ID问题，使用本包[随包脚本](../assets/normalize_ascend_trace.py)：

```bash
python "$SKILL_ROOT/assets/normalize_ascend_trace.py" \
  "$SOURCE_TRACE" "$RUN_DIR/model-decode4-candidate.perfetto.json"
```

`SKILL_ROOT`是当前加载Skill的真实目录，`SOURCE_TRACE`是明确选定的单份原始JSON，`RUN_DIR`是消费项目本轮结果目录；输出文件必须尚不存在。脚本仅依赖Python标准库，单独复制也能运行，不要求安装另一套Skill或知识库。

- 数值口径：`ts`／`dur`为微秒；先在Decimal域统一做`t'=t-t0`，再转数值。所有卡与线程共用一个原点；原点保存在输出中。
- 保留事件、轨道和参数；flow按原category／scope／ID映射小整数，不补缺失端点。原始文件不覆盖。
- 范围：单份Ascend Chrome风格JSON，支持数组根或`traceEvents`根。不是任意厂商报告转换器；不拼接多机时钟；遇到`id2` flow明确报错，另做对应适配。
- 验收分为格式核对、实际解析和用户打开：先核事件数、目标轨道／范围和时间单位；文件生成或JSON语法通过仅属于格式核对。

## 3. 交给用户

交付下载附件或明确可下载的文件链接，并用一句话说明身份，例如：

> `model-decode4-candidate.perfetto.json`：某模型、batch16、双卡、候选graph版本，包含prefill＋4步decode；下载后在 https://ui.perfetto.dev/ 点击Open trace file。

- 文件名尽量含目标、阶段与版本，不只交一个含义不明的`graph.json`。说明是单核、模型片段还是整段应用；短采集不称完整生成／全量评测。
- 默认流程就是**下载文件 → 打开 https://ui.perfetto.dev/ → Open trace file**；不用要求安装TensorBoard、厂商桌面客户端或另一套Skill。
- 用户明确要免下载时，再介绍VS Code Perfetto扩展或远程TraceProcessor；不默认安装扩展、启动HTTP服务、开放端口或要求用户使用VS Code。
- 引导先看阶段、相关设备stream和空窗；紧凑不等于硬件满载，空白不自动等于CPU慢。缺失flow须保留未知。

## 4. 需要新采集时的最小入口

Ascend PyTorch程序使用`torch_npu.profiler`；模型／输入／暖机在采集窗外，`run_step()`替换为真实工作片段：

```python
import torch
import torch_npu

torch.npu.synchronize()
with torch_npu.profiler.profile(
    activities=[torch_npu.profiler.ProfilerActivity.CPU,
                torch_npu.profiler.ProfilerActivity.NPU],
    on_trace_ready=torch_npu.profiler.tensorboard_trace_handler(run_dir),
    record_shapes=False, profile_memory=False, with_stack=False,
    experimental_config=torch_npu.profiler._ExperimentalConfig(
        profiler_level=torch_npu.profiler.ProfilerLevel.Level0,
        aic_metrics=torch_npu.profiler.AiCMetrics.AiCoreNone,
        export_type=torch_npu.profiler.ExportType.Text,
    ),
):
    for step in range(4):
        with torch.profiler.record_function(f"iteration_{step}"):
            run_step()
    torch.npu.synchronize()
```

多卡在首尾等待全部相关设备；不在每个算子后插入同步。需要更细CANN／runtime信息再提高采集等级，不默认开启stack／memory等附加项。

不方便改PyTorch代码时，可在已激活的CANN环境使用应用级msprof；以下开关经CANN 9.0.0帮助信息核对，驱动脚本只跑短窗口：

```bash
msprof --output="$RUN_DIR/profile" --task-time=l1 \
  --ascendcl=on --runtime-api=on python short_driver.py
```

只剩原始采集目录时，按实际`PROF_*`位置执行`msprof --export=on --output="$PROF_DIR"`。当前torch-npu自身的解析阶段也会调用该导出器；`tensorboard_trace_handler`不要求启动TensorBoard。

## 验证范围与同步

- 2026-11-09，Ascend 910B2／CANN 9.0.0的真实msprof文件规范化后，455,321个事件和29,152组flow关系保持，按JSON序列化值核对时间偏差0µs；用户确认本地可以查看。不是所有厂商、版本或VS Code扩展的验收。
- 两侧随包脚本一致，并在同一真实输入上生成与用户已打开文件逐字节一致的输出；未新增设备采集或随包存放历史大trace。
- 本工具在`pytorch-perf-tuning`与`kernel-knowledge`两侧独立随包提供；发布时保持脚本一致，消费者不依赖另一侧。两侧入口各自维护流程关联，不另造框架或安装前置条件。
- 来源：[Ascend兼容问题与修复PR](https://github.com/Ascend/pytorch/pull/156)、[Perfetto格式支持](https://perfetto.dev/docs/getting-started/other-formats)、[大文件与远端解析](https://perfetto.dev/docs/visualization/large-traces)。
