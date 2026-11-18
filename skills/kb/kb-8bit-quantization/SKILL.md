---
name: kb-8bit-quantization
description: 8-bit量化知识库：用真实配置、掉点数据和误差诊断指导INT8、E4M3、E5M2、HiF8、W8A8KV8及分组量化的选型、实现和研究。Use when choosing quantization recipes, estimating accuracy loss, reviewing scale/reduction axes, debugging quantization degradation, or comparing SmoothQuant/QuaRot/GPTQ and MXFP8/MXFP4/NVFP4. 触发：量化能做到多好、掉点、clip/scale搜索、per-token/channel/group/block、激活离群值、逐层诊断、量化经验。知识与判断用本skill；实验执行沿用项目工作流，性能专项用pytorch-perf-tuning，平台安装用accel-*。
---

# 8-bit量化：有数据的判断底座

经验演化型；更新日2026-10-25。整目录可迁移，无本机环境依赖；已验案例与待复核回流分开标注。

## 先建立合理预期

- **联合8-bit做到平均掉点小于1pp有学术和部署实例；0.5pp可以争取，不能预先保证。** 分开看最差任务、领域和长上下文。
- 本地GLM-4.7-Flash HIF8伪量化：粗粒度Amax约掉4.36pp；固定σ约掉1.04pp；最终融合SQ＋W/A group128约掉0.13pp。阶段间还改变了粒度、规则和后端，不能把整段收益全算给SQ。
- 最终0.13pp来自三任务各512的重复使用研发集；单项ARC-Easy仍掉1.17pp。用户接受的是研发结果，独立确认和统计非劣尚未做。
- W8 per-output-channel RTN常是强基线，但不能默认权重无害；优化局部W-MSE也可能让整模更差。
- Amax/minmax是必要的廉价对照。格式、实际定标组、中心、校准数据与后端共同决定效果。

## 1. 先写清数值合同

完成标志：W/A/K/V/Q/P各自的格式、轴、定标与实际计算节点能在源码中对上。

```text
Y[M,O] = X[M,I] @ W[O,I].T
A per-token:        保留M，沿I归约，scale[M,1]
W per-output:       保留O，沿I归约，scale[O,1]
A token-group G:    [B,T,ceil(I/G),G]，只归约最后G
W row-group G:      [O,ceil(I/G),G]，只归约最后G
KV token/head:      [B,H,T,D]，scale[B,H,T,1]
```

- **保留轴≠归约轴**。per-token与per-output-channel均沿矩阵乘法inner dimension统计，各自保留外侧索引。
- A per-channel是另一种合法配方：保留I、沿token归约，与per-token是两种配方。旧实现若按此运行，沿用原标签。
- token指实际`(b,t)`；不跨batch共享相同位置的动态scale。padding、mask、空专家不进统计。
- W8A8KV8不要求Q8/P8。先把KV8写入、读出与历史不重定标做好，Q/P可留BF16。
- QDQ后BF16 GEMM只测输入舍入误差，不证明真8-bit计算、缓存压缩或部署提速。
- 查[格式与轴](references/formats-and-axes.md)：包括FP8变体、HiF8码点、group/block/MX差异。

## 2. 选择最短的有效配方路线

完成标志：候选有对应问题、对照与停止条件。

1. 复用同协议高精度基线；确认目标引擎支持的格式、粒度、豁免层。
2. 通常从W per-output-channel、A per-token、KV token/head及Q/P高精度起步；以目标引擎实际能力为准。
3. 不够好时，按误差证据选scale/center优化、group、SQ或旋转；无需机械跑W/A/KV全开关矩阵。
4. 静态W可离线搜索并缓存；动态A用离线确定的简单在线规则。搜索目标需在训练校准集上选，评测集不调参。
5. SQ/QuaRot改变W后，重新量化W并采集变换后A；规则与缓存绑定实际W摘要。
6. 有足够收益、精度与等待时间可接受即回主线。近零收益或阴性结果也可结束分支。

详见[配方与搜索](references/recipes-and-search.md)与[尺度代理协议](references/scale-proxy-protocol.md)：选样、候选网格、目标函数及结论边界；案例参数只适用于该案例。8-bit不默认需要GPTQ；4-bit的收益和成本不能直接外推。

## 3. 掉点时按证据定位

完成标志：能区分实现错误、局部量化误差和任务因果；结论可由原始X/Xq复算。

- 先排除：选题错标、漏量化、统计轴/中心错、padding混入、cache未读、变换补偿漏分支、后端或batch改变。
- 再看真实定标组：分层/投影/专家，记录峰值、分位数、尾部能量、饱和/归零率、还原MSE与输出误差。
- 代理同时看均值、最坏10%、最坏token/query及正常对照。整体NMSE可掩盖单行灾难。
- 层组恢复需保持路由、batch、后端不变；记录救回多少退步题、又伤害多少原正确题。
- `存在outlier`不等于`它导致掉点`；需要同输入回放及有针对性的干预。不要默认跑47层全矩阵。
- 近零舍入是否重要看累计误差、下游权重、残差/路由与答案margin；“小数很多/看着像高斯”时照样检查。

查[诊断与反例](references/diagnostics.md)，包含本项目反复踩过的统计口径、因果与缓存陷阱。

## 4. 用经验数值，而非口头排名

| 要回答的问题 | 读取 |
|---|---|
| 本地各配方掉多少、哪些改进失败 | [本地实测账本](references/local-evidence.md) |
| 逐配置/任务的可计算记录 | [本地结果CSV](assets/local-results.csv) |
| 学界/工业界具体schema、精度与速度 | [外部证据摘要](references/external-evidence.md) |
| 原论文表、源码固定版本与所有URL | [2026-10-17原资料](references/external-reference-2026-10-17.md)、[2026-10-19增补](references/external-supplement-2026-10-19.md) |
| 下一次实验该记录什么 | [配方记录模板](assets/recipe-record.yaml) |
| 最终本地配方的完整参数实例 | [GLM SQ＋group128](assets/glm-hif8-sq-group128.yaml) |

外部表不合成“行业均值”。原资料有后续修正时以增补中的边界为准；文献数值不表示本机已复现。

## 5. 精度与效率验收

- 小样本只放行链路。方法比较固定题目内容/提示/评分、batch、无padding策略、量化节点和计算后端。
- 同题配对报告每项、等权或业务均值、得失题和区间；总分相同时仍看逐题得失。
- 报告掉点统一`BF16−候选`，pp是绝对百分点；PPL、相对百分比和准确率pp不可混算。
- 正式结论使用未参与选配方的数据/协议；反复复用512题得到的最好分数仍是研发结果。
- 搜索慢先检查向量化与host小循环。本地130候选不变，批量化将热态完整投影搜索2–13秒降至0.16–0.34秒，额外allocated约0.4GiB。
- 分别计模型加载、离线准备、评分、评测入口与端到端；局部kernel倍数不连乘成整模倍数。
- 真GMM需查dispatch/trace。伪量化可能比BF16慢，即使使用“8-bit”名字。
- 后台完成只认真实进程归属、新鲜完整日志、原始结果和复算；启动、timer、exit、残留running文件均不能单独证明成功。
- **INT8的σ尺度不能照搬浮点配方**：若对称码范围为±127、`scale=α·σ/127`，还原范围就是中心附近±α·σ。用真实激活检查截断、舍入与输出误差；α须依数据和目标选择，不设“≥4即安全”的通用阈值。Amax是必要对照，收益仍取决于实际实现。
- **实现自洽不等于精度可用**：实现与参考共用同一截断公式，只证明公式对齐；另与未量化结果比较，再验整模。HiF8与E4M3是不同格式，两者在给定尺度下也都有有限范围；详见格式参考。
- 原生INT8还受算子shape/版本限制，词表等大输出维度先查目标API并做有界验证；服务器新增数字及缺口见[回流观察](references/local-evidence.md#8-2026-10-25-int8回流观察待复核)，不作为通用精度或速度保证。

## 演化

- 触发：新模型/格式/引擎、可重复反例、同协议正式结果、旧来源更正。
- 更新：保留日期、完整schema、任务/样本、baseline、单项结果、限制及来源；新增CSV行时同步说明比较组。
- 撤销无效统计要标明原因，原始失败记录保留；经验不因一个新例子变成普遍规律。
- 通用知识回流本skill；机器路径、运行中状态、待办放项目记录。新数据补参考文件，入口保持短。
