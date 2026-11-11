# PyTorch 性能排查清单

本页是按证据选手段的工具索引，不替代[主入口](../SKILL.md)的连续决策闭环。**一次改动有收益，只代表候选通过；必须回看剩余关键路径并继续，达到主入口第6节出口才结束本轮。** 不逐工具打卡，也不许以“少量尝试”省掉定位、实施和复核。

长时全量前先按[主入口第1节](../SKILL.md#1-全量前先加速已验路径持续复用)判断：新路径先完成有界加速与验收，已验路径直接复用，主流程变化只补受影响项。不能只查完清单就启动全量，也不要求每次全量重跑这份清单。

训练先读[training](training.md)：新增算法的融合／求导边界、反向与optimizer、单卡／DDP／分层分别判断；不能套用eval关梯度或纯前向buffer复用。

## 1. 症状 → 先查什么

| 症状 | 先查 | 常见处置 |
|---|---|---|
| 设备利用率低、时间线有空白 | 下发准备、隐式同步、I/O、跨流／跨卡依赖 | 看全窗＋局部放大，区分微间隔与长等待；不把全部空窗当CPU计算 |
| 单步很多小kernel夹微空窗 | 循环，或没有Python循环的连续eager表达式 | 复用／批量后主动试完整稳定片段graph，计copy／输出；不先优化小核Duration |
| 已有小图或融合核仍慢 | 图间调用／copy／graph break与剩余关键路径 | 有界扩大稳定片段，不能把“已用了graph”当完成 |
| 数学上只多一步却慢数倍 | 统计→参数→变换及hook／搬运放大 | 按`execution-chain.md`做能区分假设的整链消融 |
| 大GEMM能满、模型不满，且HBM带宽也低 | 小矩阵与下发／依赖可能并存 | 看实际M/N/K、阶段任务并集及同输入对照，不判整段已memory-bound |
| batch 1 就 OOM 或余量很小 | 权重重复、全量 logits、KV | 去重、切片；纯似然可`use_cache=False`，生成保留KV |
| batch 增大吞吐不涨 | 已饱和、CPU 瓶颈、padding | 测 tokens/s、分桶、profiler |
| 首次慢、后续快 | 编译/warmup/缓存 | 预热、缓存、分开计时 |
| 多卡扩展差 | 真实放置、阶段顺序、共同空白与传输 | 按证据分片／流水线；分层驻留不等于并行调度 |
| 大GEMM能满载、模型不满 | 实际batch/长度、专家行数、向量与访存 | 必要时做有界规模对照，不把压测当整模目标 |
| 只有 eval 慢，训练正常 | eval 路径/hook/指标 | 关 hook、离线准备、批量指标 |
| 训练算法接入后变慢 | 哪部分融合／编译失效，前反向与更新的剩余关键路径 | 保住未受影响部分，按training场景分流，不默认全网eager或全网graph |

## 2. 同步点、重复构造和调用放大

```bash
rg -n '\.item\(\)|\.cpu\(\)|\.tolist\(\)|\.numpy\(\)|nonzero\(\)|synchronize\(\)|empty_cache\(\)' src
rg -n 'as_tensor\(|torch\.tensor\(|\.to\(|\.contiguous\(|new_tensor\(|torch\.(ones|zeros|full)\(' src
rg -n 'for .* in .*expert|for .* in .*head|for .* in .*layer|for .* in .*segment' src
```

- 单参数 `torch.where(mask)` 是动态索引，通常触发同步；三参数 `torch.where(cond, a, b)` 不是。
- `mask.sum(...) > 0` 后接 `.nonzero().tolist()` 是典型逐层/逐专家同步。
- 日志、assert、tqdm 里的 tensor 取值也算。
- 先判断是否在热循环；热路径外的 `.cpu()` 不处理。
- 无命中不证明无同步；常量→设备tensor、复制／分配可在后端等待。区分静态规则与动态统计，前者复用、后者不能缓存。
- 按层／专家／步数核调用放大；完整组的count／mask、重复position／mask搬运都看真实路径，不按行数或FLOP判断便宜。

## 3. 普通Event计时示例：首尾标记包围一批调用

以下是plain微基准起点，默认100次可按任务调整；先复用项目可信计时器。专业dummy覆盖、profiler交叉验证和平台计量按独立领域库处理，不把此示例当唯一验收合同。

```python
import statistics
import torch

def bench(fn, backend, warmup=10, repeat=5, iterations=100):
    for _ in range(warmup):
        fn()
    backend.synchronize()
    times = []
    for _ in range(repeat):
        start = backend.Event(enable_timing=True)
        end = backend.Event(enable_timing=True)
        start.record()
        for _ in range(iterations):
            fn()
        end.record()
        end.synchronize()
        times.append(start.elapsed_time(end) / iterations)
    return statistics.median(times), times  # milliseconds per call
```

- `backend=torch.cuda` 或 `torch.npu`，先选择实际设备；当前流上记录事件。多流工作须显式汇合依赖后记录 end。
- 计时循环内不插 Event、同步、日志或 `.item()`；编译、一次性数据准备和正确性校验在外面。每次真实调用必需的输入copy／输出消费不能删，片段／模型host对照须计入。除以`iterations`得批内摊销均值，不是单次延迟分布。
- 小核的 Event 区间可能含 Python 喂不满队列的空隙；这不是纯 kernel 时长。可把 100 次调用捕获成图，预热后用一对 Event 包围一次 replay，再除以 100。
- 图捕获、编译不计入稳态，但保留冷启动完整成本；核对图输出仍与参考一致。eager/plain与graph分别比较，禁止混算加速比。
- 训练 step 若有权重更新，应准备等价状态再重放，不能直接套固定输入的纯前向模板。

## 4. 显存模板

```python
torch.cuda.reset_peak_memory_stats()   # NPU: torch.npu.reset_peak_memory_stats()
# run
print("allocated", torch.cuda.memory_allocated() / 2**30)
print("peak     ", torch.cuda.max_memory_allocated() / 2**30)
print("reserved ", torch.cuda.memory_reserved() / 2**30)
```

- `allocated` 是活张量；`reserved` 是缓存池；`max_allocated` 是峰值。
- 权重去重：按 `(device, untyped_storage().data_ptr())` 计一次 `storage.nbytes()`；tensor 切片偏移不是新 allocation。
- 会再次原位量化的持久packed张量在`inference_mode(False)`下创建、绑定；共享切片不能意外成为仅限inference上下文写入的tensor。
- 阶段之间按需释放无用引用／`empty_cache()`，再测下一阶段峰值；不把清缓存当每批必做项。
- `reserved - allocated` 不能解释成另一份模型或全部临时张量。

## 5. Profiler

新一轮优化必须取得或复用代表性应用timeline并分析，不因便宜改动已有收益就省掉；已有同口径证据不重采。先暖机、选短真实窗口，另留未采集计时，不默认启用重型shape／memory／stack记录。

```python
from torch.profiler import profile, ProfilerActivity

with profile(activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA]) as prof:
    fn()  # 已暖机的真实代表片段
prof.export_chrome_trace("trace.json")
print(prof.key_averages().table(sort_by="self_cuda_time_total", row_limit=30))
```

- NPU 用厂商 profiler 或 `torch_npu.profiler`；活动名按实际后端。
- 热点表仅作辅助；打开或解析导出的timeline，主动看全窗＋代表性放大，区分长等待、持续微间隔和跨卡轮流忙。按host launch／sync与设备任务关联选择下一动作，不停在`self_*_time_total`排序。
- 多卡用同窗区间并集，不把kernel和当wall／MFU；低层入口可能有设备任务却无host flow起点，分别核覆盖，不把缺记录当零成本。
- `record_shapes`／`profile_memory`／`with_stack`按当前问题启用，尤其stack较重；不要为了诊断下发空窗默认全开。
- profiler 本身会同步/加开销；不要用它产出的总时间当加速结论。

## 6. 少量 Batch 候选

```python
for batch in (1, 2, 4, 8, 16):
    try:
        ms, _ = bench(lambda: step(batch), backend=torch.npu)
        print(batch, batch * 1000 / ms, peak_memory())
    except torch.OutOfMemoryError as e:
        print(batch, "OOM", e)
        break
```

- 示例候选按实际预算缩减，不要求全跑；batch选择完成后回看整链，不以batch吞吐改善宣布整轮完成。`step`、`peak_memory` 为工作负载自己的函数；只捕获明确的 OOM，其他错误原样抛出。
- 指标用有效 tokens/s 或 samples/s，不把 padding token 计入吞吐。
- 变长输入固定同一组样本，按长度排序后再切 batch。
- 先选batch／后端等setting，再同组统一；不以跨setting逐题等价作门槛。原统计分组、实现数值及评分有效性仍验。

## 7. 无用张量审计

按阶段列出活张量，逐项问“下一步还需要吗”：

- 权重：原权重、转换/量化权重、FP32 master、打包副本、转置副本。
- 优化器：eval 时的 optimizer state、梯度。
- 输入：padding 到 max_length、未截断的长样本、重复 tokenize。
- 中间：KV cache、全词表 logits、hidden states、attention 矩阵、mask。
- 输出：持有 cache 的 output 对象、逐样本大张量、profiler trace。
- 缓存：response cache、dataset encoding、编译产物。
- 训练显存：需要时用activation checkpointing以计算换显存；纯eval不默认增加重算。

处置优先级：不创建 > 复用 > 原地覆盖 > 共享 storage > 阶段边界释放。

纯评测优先`eval()`与合适的推理上下文；训练／需梯度校准、后续恢复权重或修改持久buffer时保留所需状态。打包／转置权重尽量共享storage；确认冗余后才释放或原位替换。

## 8. 串行/并行审计

- 画依赖图：哪些计算只依赖输入，不依赖前一步？
- 可合并：同一输入的 QKV、gate_up、多个 head 的投影。
- 可分组：逐 expert/segment 的 GEMM → grouped GEMM。
- 可批处理：独立请求/样本 → 一个 batch。
- 可重叠：数据加载/预处理→计算、独立分支→多stream、不同完整batch→跨卡阶段流水线。
- DataLoader按实际瓶颈选workers、pin_memory、non_blocking和prefetch，保留正确依赖；CPU准备不能饿住设备，异步标志本身不证明重叠。
- 同一batch的层有严格顺序，不代表不同batch不能重叠；小算子并行可能被下发成本抵消，按端到端结果取舍。
- 线程的设备／inference／AMP／样本上下文、跨流依赖、tensor寿命和在途数量须正确；同阶段切分串行对照＋真实trace见`multi-device-pipeline.md`。
- 任务允许模型副本时，eval可按独立样本分片；训练的DDP／FSDP按容量与同步成本选。不在单实例任务中自动扩成多副本，分层驻留也不等于FSDP。

## 9. Batch 语义检查

- 动态量化/定标是否按 batch 统计？padding 是否进入统计？
- BatchNorm 训练态用 batch 统计；eval 态用 running stats。
- 同算法归约改写是否满足事先数值契约？不同setting则不强求逐题输出相同。
- dropout/RNG 是否在 eval 关闭？数据顺序是否影响结果？
- 响应缓存 key 是否包含 batch/协议/源码版本？

## 10. 现成 fast path 清单

- `torch.nn.functional.scaled_dot_product_attention` / flash attention。
- `torch._grouped_mm`（按实际 PyTorch 版本确认）；厂商 grouped matmul。
- 下发受限优先CUDA／NPU Graph、已适配`torch.compile`；图边界可包含库算子／GEMM，不限于自定义小核。
- fused optimizer / fused layernorm / rmsnorm。
- varlen attention / sequence packing。
- 上游模型的 optimized forward（例如 HF 的 grouped MoE 实现）。
- 在既定dtype下核布局：channels-last／连续布局按算子支持实测，避免热路径反复transpose＋contiguous；不为提速静默改计算精度。
- 先查版本、实际设备dispatch与实现，再在目标设备测数值/性能；grouped/fused接口可能仍逐项展开，不能只凭函数名或导入成功。
- 已有最终kernel不代表外围链高效；下发证据支持时主动保计算图对照，不仅列菜单。真实调用暖机、输入copy、输出alias／寿命、stream及冷启动见[graph-replay](graph-replay.md)。

## 11. 报告模板

| 项 | 值 |
|---|---|
| 设备 / 版本 | ... |
| 输入 / batch / dtype | ... |
| 物理卡 / PID / 观测阶段与窗口 | ...；其他作业及缺失字段明确标注 |
| 设备忙碌度 / 功率W / 温度或限制 | 同阶段均值／范围；保留字段定义 |
| 有效 tokens/s 或 samples/s | ...；不计 padding |
| load | ... |
| offline prepare | ... |
| warmup | ... |
| scoring loop | ... |
| prefill / decode | 真实shape、步数；teacher诊断与官方生成分开 |
| total | ... |
| 峰值 allocated / reserved | ... |
| 设备内存 / 必要驻留 / 可确认冗余 | 按 storage 去重；不把缓存池全算死内存 |
| 实现与setting | 本setting数值／分组／覆盖／cache／评分检查，不要求跨setting输出一致 |
| 协议变化 | 无 / batch 定标变化 / ... |
| 判断与证据 | 原关键路径→为何选此动作→实测结果→新关键路径；继续下一轮或有据收口，不能只写“已有提速” |
| timeline结论（深调优时） | 阶段／窗口、长等待或微间隔、host/runtime/device关系及缺项；为何选graph、调度或设备优化 |

扩大前给已处理的浪费、所选setting和整批预算，并完成主入口第6节的整轮复核；smoke或首个提速不算效率就绪。验收核匹配源码／输入的新鲜日志和本轮实测，不以计时器／退出／残留状态代替。
