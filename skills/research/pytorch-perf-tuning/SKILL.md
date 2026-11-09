---
name: pytorch-perf-tuning
description: PyTorch训练与评测效率优化：长任务前有界加速，已验路径持续复用；算法接入后核高效路径与真实timeline，按下发、设备、显存或通信瓶颈选graph/compile、现成融合与并行组织。Use before long training, evaluations or sweeps, or when PyTorch is slow；触发词：训练加速、算法破坏SDPA、反向很慢、梯度累积、DDP、双卡训练、小数据微调、跑全量、评测太慢、QDQ、CPU下发、stream空窗、小kernel、timeline、导出Perfetto、下载trace、memory bound、torch.compile、CUDA Graph、NPU Graph、流水线、显存不够。目标是加速算法迭代，不追求满载；kernel-knowledge仅作已定位热点的最后一级外援。环境用accel-pytorch-python，平台移植用accel-pytorch-code-porting，单点故障用diagnosing-bugs。
---

# PyTorch加速：先判关键路径，再选优化层次

遵循`goal-first`：减少算法研究的实际等待。**先清明显浪费；仍慢时读timeline；下发受限优先graph／compile，设备执行受限再改算子。** 不从“能写什么kernel”出发，也不把工具全部试遍当验收。

## 0. 目标、契约与预算

- 固定研究任务、可接受等待和本轮预算；按剩余运行次数×每次可省时间，衡量开发、验证、冷启动和维护成本。达到研究需要即停，不设统一利用率／功率／倍数门槛。
- 保留算法、dtype、样本和评分协议；先选setting，再在同一方法比较组统一batch、后端、attention和调度。不要求跨setting的logits／生成／逐题分数相同；实现数值、统计轴／padding、覆盖与评分仍须有效。
- 设置变化另记，不混旧setting基线。改变定标定义、伪量化换真低位计算属于语义变化，不能冒充执行优化。
- 本skill管理PyTorch执行组织、接口、graph／compile和模型接入；DSL、tile、片上流水与专业kernel迭代由`kernel-knowledge`负责。推理引擎研发另立目标。

**训练入口**：涉及forward→backward→optimizer时先读[训练分支](references/training.md)。先固定算法和梯度契约，核算法接入后哪些高效路径仍在，再按数据／前向／反向／通信／更新的关键路径行动。训练数据多、高功率或利用率高都不能代替timeline；长kernel已覆盖下发时不强推Graph。推理的关梯度／输出复用经验不直接用于训练。

## 1. 全量前先加速，已验路径持续复用

**用户要求长训练、全量／批量评测时，主动先查加速证据。新路径完成实际尝试和真实调用验收后才启动长任务；不能先跑起来再补优化。** 只做正确性smoke、采profile或列建议不算完成。高效路径未受破坏且已有适用证据时直接复用，不强制再跑Graph或工具矩阵。

| 当前情况 | 应做什么 |
|---|---|
| 首次执行，或没有适用的已验加速路径 | 代表性短测建立基线，沿第2–5节选适用手段做有界加速，第6节验收后再全量；不是每项工具都试 |
| 已完成加速，执行路径和覆盖仍有效 | 核对实际入口／配置后直接复用；不因每次全量、换会话、重启、换题或扩大题量重复短测／profile／调优 |
| 主流程方法改变，或执行／shape超出覆盖 | 沿同一方法只补受影响阶段的加速与验收，其余复用；完成后继续已授权全量 |

- 变化按实际影响判断：模型结构、在线算子链、生成／cache路径、后端／设备放置或未覆盖shape可能使证据失效；仅数据值、种子、题量或不影响执行链的代码修改不自动重开。正常编译／暖机、缓存更新和必要正确性检查仍保留。
- 训练另核反向／loss归一化、optimizer／AMP、重计算与并行方式；变化只补相关证据。数据量少与每步计算少分开，短训练先算冷构建能否回本。
- 在已有报告／任务记录保存采用的入口／配置、执行与shape覆盖、实测前后耗时、冷成本和结论。**全量必须实际使用已验路径**；只在别的脚本试过候选、知道通用思路或持有旧似然成绩，不证明当前生成路径已加速。
- 有界尝试无净收益时，保留实测与停止理由，采用当前最快可靠路径；不设必达倍数、不穷尽工具，任务预算仍有效。已有方案够用就复用，不新增审批或管理文件。
- 需要新短测时，用真实代表输入分列加载、离线／冻结准备、冷编译／预热、在线评分；生成另拆prefill／decode，记录实际shape、步数及有效吞吐。复用时直接引用已有测量，按本批规模更新预计成本，不把外推写成全量实测。
- 先记host阶段wall和内存峰值；功率、忙碌度和HBM旁路采样作辅助，缺项明示，不为填满指标延长实验。累计kernel Duration不能当wall。
- 沿热调用展开数据准备→统计／参数→变换→库算子→输出／cache，记层／专家／步数的调用放大。一个Python函数或算法步骤可能下发几十个kernel；已有最终核不代表整链高效。
- 放行判据：有当前执行路径的加速尝试与真实调用验收证据，或适用的既有证据；实际采用选定setting、明确整批预算后按授权全量。仅建立基线不等于完成加速。

## 2. 先做便宜且确定的改进

按证据命中项处理，不逐行打卡；详细搜索与计时模板见[checklist](references/checklist.md)。

| 先查什么 | 优先动作／保留条件 |
|---|---|
| 不需要的工作 | eval关梯度／无用hidden、attention和全词表输出；纯似然不用KV，生成保留；训练／校准所需图不删 |
| 重复准备／常量 | 离线在线分开，缓存tokenize／权重量化／静态规则与mask；绑定版本、device、dtype，动态统计不能缓存 |
| 冗余驻留／临时量 | 按storage去重权重与packed副本，缩短引用寿命，安全复用buffer；保留训练master／恢复需要，reserved不是冗余活内存 |
| 同步击穿流水 | 热循环取值、日志、标量上传、动态索引、重复copy移出／合批；后端内部同步以trace定因，保留正确依赖 |
| 无效batch／padding | 少量batch对照、长度分桶和动态padding，看有效tokens/s及峰值；不改变独立定标组或把batch1当容量上限 |
| 独立工作被串行化 | 向量化、batched／grouped、合并共享输入投影、预取；核实际dispatch，不因接口叫fused就认作融合 |
| 阶段间可重叠 | 数据准备与计算、独立分支、跨设备不同完整batch；保持Event／tensor寿命，复杂流水线按证据另作有界候选 |
| 现成高效接口 | 核目标设备的上游／Torch／厂商实现和fallback，按算法契约短验；不把CUDA文档当其他平台能力结论 |

- `model.eval()`与推理上下文按用途使用；会跨inference／no_grad原位更新的持久buffer须冷建普通张量或约束上下文。
- Batch／layout优化计copy、cast、contiguous和临时内存，不为占满设备增加无用输入。显式同步清理完，仍可能有逐操作下发空窗。
- 完成判据：同口径端到端可靠变快，或没有对应浪费。等待已够用可收口；仍慢或准备做高成本改动时进入第3步。

## 3. 读timeline：把“空闲很多”变成可行动判断

**决定进一步融合、优化kernel Duration或调用外援前，先取得／复用代表性应用timeline。** 主动完成分析，不等用户要求画图；只报“75%空闲”“很多小kernel”不算定位。

**人类查看按用户触发**：用户说想看timeline／导出Perfetto时，按[下载查看流程](references/timeline-viewing.md)用本包脚本生成兼容文件，交付下载链接并说明模型／算子、版本和采集范围。默认让用户下载后在Perfetto打开；不默认启动可视化服务，也不要求安装kernel-knowledge。Agent日常自动分析照常。

- 同窗对齐host线程、runtime launch／graph replay／copy／sync，以及全部相关设备stream；核进程、物理卡、采集边界和缺失关系。生成分阶段读，另留未插桩计时锚点。
- 看全窗确定阶段，再放大代表性空窗：长块等待，还是每两个短kernel之间的密集微间隔？核首尾与窗内分布；需要展示时给真实timeline总览＋局部放大，不用示意图充证据。
- 单卡看相关stream并集，多卡另看共同无任务区间；一张卡等另一张与所有卡一起空白分开。设备无记录任务不自动等于CPU计算，host API时间也可能与设备工作重叠。

| 时间线与调用证据 | 下一有效动作 |
|---|---|
| 密集短kernel＋持续微空窗，稳定高频eager链 | **主动做完整稳定片段的graph保计算对照**；或用已适配compile。计输入copy与输出消费，不先抠单核Duration |
| host等同步／取值／复制，或数据供给断档 | 定位真实依赖、重复搬运／准备；回第2步，graph不能消掉必要依赖 |
| 一卡工作、另一卡等待 | 核阶段调度；有独立batch才考虑流水线，不把device_map当并行 |
| 长kernel／中间流量实占关键路径 | 先现成接口／compile融合，再有界kernel外援；不是所有阶段都下发受限 |
| 设备连续有工作但算力低 | 核实际shape、带宽、访存延迟与批量；低算力不直接等于HBM饱和 |
| host关系缺失／因果仍不清 | 明示未知，用最小保计算对照区分；不据缺项认零成本，也不无限追因阻塞低成本验证 |

- 下发主导须有host关联或“保持计算、减少逐操作下发”的对照支持；按证据强度表述，不把共同空窗直接换算可兑现加速。
- 机制、区间口径、放大图与消融见[execution-chain](references/execution-chain.md)；设备监控及平台工具入口见[device-observation](references/device-observation.md)。
- 完成判据：明确阶段、主要成本、待证假设及一个有界动作。基于当前关键路径选层次，不以已有加速倍数宣称足够，也不因剩余空窗自动无限优化。

## 4. 下发受限：graph是优先验证的执行方式

Graph缓存设备工作及依赖图，重放时减少重复经过Python／框架／runtime的逐操作下发；**输入值可变，kernel数量与单核Duration未必减少**。不保证每个Torch kernel已最优，也不是把任意Python控制流一次录下永久执行。

- 触发第3步的稳定链／微空窗信号后，主动检查CUDA／NPU后端能力并做小对照；无需用户点名graph。不能只把graph列为“可考虑”后直接写核；不适用须给具体动态状态、后端或成本证据。
- 选**连贯、足够大的稳定片段**，可含Norm→变换／QDQ→Linear及相邻逐元素操作，不限于自定义核。动态cache增长、I/O、停止控制可留图外；不强求全模型捕获。
- 已有A／KV小图或融合核，若仍有同类空窗，检查图间调用／copy／graph break并有界扩大捕获范围；“已经用了graph”不是整段下发已解决的证据。
- Graph与compile分开判断：前者优先降低重复下发，后者还可能融合计算／减少中间量；依赖实际后端。可以组合，但不假定跨stream或嵌套capture可行，不把一次失败泛化为平台不支持。
- 通过真实调用暖机，核shape／stride／dtype／device／stream与执行上下文；teacher、手造输入、prefill不替代真实generate／decode。窗内无新capture／编译，冷成本单列。
- 变输入验证数值、统计组、输出alias／寿命与cache历史；固定输入地址不等于固定值。按调用者／stream隔离持久状态，不能为捕获关闭必要KV或修改算法。
- 完成判据：真实片段／模型host更快、量化或其他算法工作完整、冷成本可接受；新timeline解释变化。无需为每个微改动重复采集；选定代表候选和关键阶段复核即可。

具体接入与失败分支见[graph-replay](references/graph-replay.md)。Graph通常比手写融合核便宜，适合作为下发受限的首个候选；收益与适配成本仍须实测。

## 5. 设备受限或框架方案不足：再选融合与kernel外援

- 先复用框架／厂商算子、批量组织、已有kernel或编译器融合，不要求全部试遍。只处理仍实占关键路径、能减少研究等待的热点。
- 区分三个收益来源：**减少下发次数、减少中间读写、改善设备执行**。融合可同时贡献三者；单核Event快不证明模型快，单靠kernel数也不选优。
- 需要手写时，交`kernel-knowledge`真实完整片段、shape族、dtype／stride／归约／mask、数值契约、当前最佳基线（含已验graph）、频次和预算；说明希望省哪段成本及为何框架方案不足。交接见[kernel-decision](references/kernel-decision.md)。
- 专业DSL实现、设备计时、SOL和profile由外援负责；本skill不另造迭代引擎。确需独立委派才用`kernel-worker`；外援不可用时保留可信路径，不自动装平台。
- 接回计入包装、绑定、输入输出copy、冷编译、buffer寿命及stream依赖；局部快、真实调用无收益则不晋升，不继续因沉没成本追单核排名。
- 完成判据：与当前最佳可用路径同输入端到端对照，数值与覆盖通过，净收益值得维护。

## 6. 验收、回看与停止

- 同输入／warmup，少量交错复测（如ABBA），保留原值和失败；小时级全量不为形式反复跑。单层、独立graph／融合／流水线倍数不能相乘，组合须在共同入口测。
- Host计时包含真实输出消费并在边界等待相关设备；加载、准备、冷编译与稳态分列。一次性JIT不混稳态，也不能从完整eval中偷偷删除；padding token不计有效吞吐。
- 实现按数值契约核对，评测另验身份／覆盖／cache写读／官方评分；总分相同或有限logits不足，跨setting答案不强求一致。图重放的Python hook不一定重跑，覆盖用绑定／重放与实际目标任务互证。
- 训练验变输入、多步梯度、参数与optimizer状态，必要时验累积、随机性和跨rank一致性；涉及精度／有效batch／loss语义变化另验收敛。完整训练step计数据供给、反向、更新与通信，纯前向结果不能放行训练。
- 验收只认匹配源码／输入的新鲜日志、本轮实测及真实进程信息；启动、退出码、计时器、报告非空、残留completed均不能单独证明完成。
- **每次实质优化后，若等待仍不满足目标，重看剩余关键路径。** 设备热点可能变为下发热点；移除同步后也可能仍有eager微空窗。下一轮由新证据选，不机械沿原工具继续调。
- 已知明显浪费处理、收益可信、等待支持研究：冻结版本／setting回算法主线。预算耗尽或下一步成本不值也可明确收口；未达目标就写缺口，不用“PyTorch天然慢／已有核／已两倍”代替判断。
- 多卡只作放置时不能宣称流水线；若实施重叠，另验stage串行→重叠、真实设备交叠与净吞吐，见[multi-device-pipeline](references/multi-device-pipeline.md)。Graph压阶段内下发，流水线处理独立工作调度，两者不互相替代。

交付在现有报告／记录内说清：**慢在哪→证据→为何选该层→实测改善→剩余主导成本／停止理由**。不新增管理表、审批层或为完整性跑矩阵。

## 参考与演化

- [checklist](references/checklist.md)：便宜优化、搜索／计时／内存模板，按需查。
- [execution-chain](references/execution-chain.md)：timeline、关键路径、保计算消融与带条件案例；深调优前读。
- [graph-replay](references/graph-replay.md)：图边界、真实暖机、状态／寿命及与compile／融合的对照；下发受限时读。
- [training](references/training.md)：研究算法接入、场景分流、单卡／DDP／分层、训练Graph状态与有界实测。
- [device-observation](references/device-observation.md)：GPU／NPU旁路监控、工具及指标定义，不代替timeline。
- [timeline-viewing](references/timeline-viewing.md)：用户想看时生成可下载trace；兼容脚本随本包提供。
- [multi-device-pipeline](references/multi-device-pipeline.md)：多batch跨阶段、线程上下文与依赖；[case-moe-eval](references/case-moe-eval.md)：历史MoE阶段案例。
- [kernel-decision](references/kernel-decision.md)：最后一级外援的证据、交接与模型接回，不在此维护底层教程。
- 经验演化型：一般判断回本体，操作细节回对应reference，案例保留平台／日期／边界，原始证据留来源项目；专业平台与kernel知识回领域维护源。更新时同时清理冲突旧措辞，不只往文尾加提醒。
