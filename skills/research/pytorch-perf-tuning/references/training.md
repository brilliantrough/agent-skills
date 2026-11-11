# 训练：保留算法，按失效边界与关键路径优化

**先回答“算法接入后失去了什么”，再问“用哪个工具”。** 高效训练框架不是全有或全无：attention融合失效，不等于MLP、optimizer、编译和通信优化都得放弃。目标是缩短研究迭代，不是另造训练引擎。

## 1. 固定训练契约，检查兼容边界

先看真实训练入口与已验方案。记录算法改动位置、必须保留的中间量／梯度、loss归一化、精度、有效batch、更新频率及并行方式；不要求额外管理文件。

| 算法接入位置／条件 | 先核什么 | 有界动作 |
|---|---|---|
| attention外的变换、辅助loss、adapter | SDPA／融合attention的实际前反向是否仍在；新增链有无同步 | 保留未受影响的高效路径，仅优化新增链 |
| 只改attention分数／mask | 现有接口是否精确表达算法，且目标后端支持反向 | 契约吻合才接入；API存在不证明实际走融合 |
| 必须读取或修改softmax概率等内部量 | 融合接口能否暴露该节点；自定义梯度如何定义 | 无法表达就保留显式attention，优化周边和稳定链，不删除算法来恢复速度 |
| 动态分支、hook、数据相关shape、自定义Autograd | graph break、CPU取值、保存张量及反向支持 | 动态部分留外面，局部compile／graph；不把整个模型退回最慢路径 |
| 冻结、QAT、截断梯度或高阶导数 | 哪些参数／输入需梯度，STE及重计算语义 | 推理QDQ核／固定输出包装不会自动获得正确反传 |

用**同算法未经优化的实现**作数值和速度参考。未加算法的快模型只说明附加成本，不能作为删算法后的“优化成绩”。布局、mask、dtype变化须同时核前向和反向后端。

完成：知道保留哪些高效部分、失效在哪里、不可消除的算法工作是什么。已有适用证据直接复用；新链只补受影响部分。

## 2. 按阶段与规模定位，不从功率读数选工具

真实窗口：`数据供给 → forward → loss → backward → 梯度通信 → optimizer`。通信可与反向重叠，host可与设备重叠，不能把各项Duration相加当wall。

- 先去重复预处理、热循环取值／日志同步、无用中间量和逐参数／逐样本Python循环；保留研究所需统计与梯度。
- 看全部相关设备timeline、长kernel和局部间隙；CPU阶段标注是host耗时，不是该阶段设备耗时。`EVENT_WAIT`／`CAPTURE_WAIT`等等待条不能计作计算忙碌。
- 高功率／高busy只作线索：检查padding、重复计算、重计算、流量及通信。没有明显浪费、已有高效证据且等待可接受，就停。
- 数据量大决定步数；每卡microbatch／序列／宽度决定单步形状。有效batch通常为`microbatch × 累积次数 × 数据并行规模`；增加累积次数不扩大单次GEMM。
- 小数据集不等于小kernel；小模型也不一定下发受限。改变batch时固定目标有效batch和loss权重，不能把不同优化问题混为一组。

## 3. 场景分流：只选命中的一条

| 真实证据 | 优先尝试 | 停止／换方向 |
|---|---|---|
| 高效路径保留，长kernel连续覆盖下发 | 复用；核有效token比例、供给及剩余设备热点 | 无明显浪费且等待够用就停，Graph不是必做项 |
| 算法新增稳定短算子链、密集微空窗 | 连贯片段的训练Graph或适配的compile | 无收益保留最快可靠路径，不无限扩大图 |
| 显式attention／loss中间量占内存与设备时间 | 可微接口、向量化、去冗余cast／copy、有界compile融合 | Graph不消除算法必须的矩阵与流量 |
| 前反向已快，逐参数optimizer成为主导 | 目标设备支持的foreach／fused optimizer | 比较更新与状态、实测净收益，不先手写optimizer |
| 显存迫使microbatch过小 | 去无用保存、布局／混合精度、选择性checkpoint，再选microbatch | checkpoint以计算换显存，计重算及吞吐，不能直接称提速 |
| padding多、长度很散 | 分桶、合理shape桶、按语义packing | 保留attention样本隔离、位置与loss mask；padding不计有效吞吐 |
| 数据读取／预处理断供 | 缓存tokenize、适量workers、预取与有依赖保证的异步搬运 | 数据驻设备的step测量不代替完整数据循环 |
| 步数少、频繁换结构 | 优先便宜改动，估冷编译／捕获回本 | 冷成本超过累计节省就用eager，不从总等待中删除准备 |

Graph主要减重复下发，compile还可能减设备工作与流量；两者不能互相推断收益。关键路径中可消除占比为`f`时，纯移除该部分的理想上限为`1/(1-f)`，不是全部Python耗时占比。

净收益先看`N × (T_reference − T_candidate) > T_extra_setup`。分列数据准备、首轮库初始化／编译、图构建、暖机和稳态；热库上的capture时间不是完整冷启动。节省≤0则不存在回本步数。

## 4. 单卡、DDP和分层双卡分别处理

| 执行方式 | 先看 | 动作与条件 |
|---|---|---|
| 单卡 | 每卡shape、前反向／更新比例、显存与供给 | 调microbatch／累积组合，局部融合／compile／graph，按完整成本选 |
| DDP | 每rank有效token、梯度桶、通信重叠、慢rank | 累积前`K-1`次`no_sync()`须包住forward和backward，末次正常同步；核更新前同步及rank一致性 |
| 简单分层驻留 | 跨卡激活／梯度、阶段不均、两卡轮流工作 | 分别优化阶段、减少重复搬运；局部捕获并保留跨卡依赖；放置不是流水线 |
| 真正流水线训练 | 多microbatch、激活寿命、反向顺序、bubble和更新边界 | 已有调度器优先；有需要才做GPipe／1F1B等有界适配，更新前梯度聚合完整 |
| FSDP／ZeRO／TP等 | 参数／梯度分片、通信和容量约束 | 查框架契约，不照搬DDP的`no_sync`／Graph配方；容量方案不保证提速 |

- 不等长样本时，平均各microbatch／rank的loss不自动等于全局token平均。保留既定样本或token权重，再处理累积／DDP平均系数。
- DDP记录各rank同步后最慢rank的完整更新步；分层计时在边界等全部参与设备。多卡扩展比须固定总样本／有效batch与更新数。
- Graph不会自动重叠两阶段或消除必要跨卡等待；多个未反传microbatch不能共用会被下次forward覆盖的静态激活。

## 5. 训练Graph：反传可行，状态必须正确

执行图与Autograd图不同。可捕获前向、反向，或在后端支持时加入optimizer；固定地址不冻结输入、参数、梯度和优化器状态。

低成本起点：稳定模块的autograd-aware `make_graphed_callables`，optimizer／scheduler／动态控制留图外。完整step捕获另核capturable optimizer、AMP及通信；不直接复用推理的`no_grad`／`inference_mode`包装。

| 边界 | 必须处理 |
|---|---|
| 输入与参数 | sample输入用专属buffer／clone，不把数据池第一批当可写静态存储；参数原位更新，不无声替换storage |
| 梯度累积 | 查`.grad`是否别名图静态梯度输出；replay不得覆盖已有累积。必要时为确实参与求导的参数预分配独立grad并原位清零 |
| 未使用参数 | 保留`grad=None`与零梯度区别；给全部参数分配零grad可能改变optimizer跳过／weight-decay行为 |
| 激活／输出寿命 | 下次覆盖前消费；两个forward后统一backward、流水线、多stream须独立状态或后端保证 |
| 暖机 | 可能推进权重、optimizer、RNG与可变buffer；配对起点恢复完整状态，不只重置模型权重 |
| RNG／Dropout | 核掩码随replay推进及梯度；不同随机流不强求掩码逐位相同。断点复现另验RNG保存／恢复 |
| AMP／GradScaler | autocast条件与实际一致，按后端禁用不兼容cast缓存；动态溢出检测／跳步可留图外 |
| LR／optimizer | 学习率、step计数、momentum／二阶矩正常推进；CPU控制值可能被捕获成常量，核实际更新方式 |
| 多卡／模式 | 捕获流、device及train/eval匹配；shape／stride／分支变化核覆盖。DDP＋Graph另验，单卡不背书 |
| 高阶导数 | 查后端约束；PyTorch／torch-npu的该局部图接口不支持double backward，不用于需二阶导的算法 |

2026-11-09 Ascend 910B2、torch2.9.0／torch-npu2.9.0.post2实测：图返回梯度被参数`.grad`接管后，`set_to_none=True`下第二次累积可覆盖第一份。单次正常、双次出错；独立grad＋`zero_grad(set_to_none=False)`修复，最小对照最大差`4.66e-10`。这是该路径实测，不推断所有CUDA／NPU版本都有同一缺陷。

## 6. 验收与停止

1. **同起点变输入、多步更新**：逐参数看梯度、参数、optimizer状态和loss；核需要输入梯度的节点，不能只看loss有限或下降。
2. **按真实使用覆盖**：未使用参数、累积清零、Dropout、rank一致性及必要mask；不为完整性补未使用的AMP／分片矩阵。
3. **先分数值来源**：重复eager建立波动锚。非确定性微差可经BF16边界和Adam多步放大；诊断可固定确定性setting，不以放宽门槛掩盖buffer错误。验收与测速setting不同则分别披露。
4. **完整step计时与profile**：未插桩交错复测，另采目标前反向／通信／更新。设备常驻数据探针不包括加载、保存和验证。
5. **收敛边界**：先过梯度／更新检查；精度、有效batch、loss或近似算法变化后，按科学目标补收敛／目标精度验证。几步正确不是长期效果证明。

**一个前向／反向图通过，不代表完整训练已优化。** 每次实质改动后必须重看数据供给、前反向、通信和optimizer；下一个主导阶段有可行候选且目标未达，就在授权预算内继续。高忙碌下Graph无收益只关闭该候选；缺依赖写具体阻塞，不宣称平台不支持。整轮仅按[主入口第6节](../SKILL.md#6-验收回看与停止)达标收口、明确阶段暂停或用户停止，不把预算到冒充充分优化。

## 7. 有条件的实测锚

2026-11-09，Ascend 910B2／CANN9.0／torch2.9.0／torch-npu2.9.0.post2；6层byte Transformer、真实WikiText训练文本、FP32参数＋BF16 autocast、确定性setting。同算法短训练step的ABBA中位数，不是完整训练或跨机器承诺。

| 场景 | 对照（ms／更新步） | 可复用判断 |
|---|---:|---|
| attention外变换，宽512，B2×S128 | eager46.959 → 前反向图23.151 | 融合SDPA前反向仍在，算法不必破坏全部高效路径 |
| 概率裁剪／重归一化，宽512，B2×S128 | eager48.500 → 图22.889 | 显式attention可减下发，图不恢复融合算法 |
| 同概率算法，已验图基线 | 图23.264 → 图＋AdamW foreach9.424 | 回看剩余阶段，optimizer成为下一瓶颈；不乘跨轮倍数 |
| 外部变换，宽2048，B8×S1024 | eager117.183 → 图118.673 | 采集窗设备执行并集约99.4%，Graph无净收益，保留eager |
| 两卡3＋3层串行分层，B2×S128 | eager55.325 → 两段图33.444 | 阶段内加速有效，不是流水线或优于单卡的证明 |
| 两卡DDP，microbatch2、累积4、全局16 | 每次同步135.941 → no_sync121.866 | 梯度、参数、momentum通过；每rank每3步all-reduce48→12 |

单卡／分层图4步loss、梯度、参数与AdamW状态在确定性setting逐位相同；DDP最大梯度差`1.86e-9`，跨rank参数相同。独立Dropout探针4次重放、相邻mask不同，解析输入／参数梯度最大差`1.19e-7`。DDP＋Graph、FP16溢出、高阶导和长期收敛未验。

单卡热库上的图构建约0.15–0.44秒；分层捕获区间1.09秒含准备hidden与暖机，口径不同，均非完整冷启动。TorchAir整链compile在局部补protobuf后仍缺`decorator`，未进入GE编译，无数值／性能结论。原始证据标识：来源项目`docs/experiments/pytorch-training-perf.stage1.report.md`与`artifacts/runs/20261109_training_perf/`；通用方法不依赖访问该项目。

## 参考

- [PyTorch CUDA Graph训练与局部捕获](https://docs.pytorch.org/docs/2.9/notes/cuda.html#cuda-graphs)
- [PyTorch性能调优指南](https://docs.pytorch.org/tutorials/recipes/recipes/tuning_guide.html)
- [DDP no_sync](https://docs.pytorch.org/docs/2.9/generated/torch.nn.parallel.DistributedDataParallel.html#torch.nn.parallel.DistributedDataParallel.no_sync)
- [torch-npu v2.9.0图接口源码](https://github.com/Ascend/pytorch/blob/v2.9.0/torch_npu/npu/graphs.py)
