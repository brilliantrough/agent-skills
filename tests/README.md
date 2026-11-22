# 项目验证

本目录是项目的 Verification 层：用真实生产入口和固定输入验证行为，不用 Agent 当次编写的假设证明实现正确。静态检查仍归 `scripts/check.sh` 的公开体检；需求、取舍和宿主语义审查不能由测试全绿替代。

## 日常入口

```bash
bash scripts/check.sh              # 快速公开检查
bash scripts/check.sh --with-tests # 公开检查 + 全部可离线行为回归
```

`--with-tests` 是提交前的统一门禁。快速检查也执行大输出退役静态契约：`output-store`／`context_output_read` 不得恢复，`context_rewrite` 与原生门控说明必须保留；该断言由 `tests/source-bench.py --context-output-static` 统一提供。测试必须实际执行并输出 `PASS`；外部前置条件不满足时明确输出 `SKIP` 和原因。应由本仓提供的测试文件缺失、测试失败或运行器自身异常均为 `FAIL`，不能当成跳过。退出码为 0 只表示已执行部分没有失败，不消除 SKIP 的未验证范围；最终报告必须列出它们，需要完整覆盖时不得接受相关 SKIP。

需要定位单项时可直接运行对应脚本，但最终仍须回到统一入口验收。私有 selfcheck 检查本机 live 配置漂移，不属于这套可移植行为测试，按 `AGENTS.md` 的本机命令单独运行。

本机 Sub Agent 安装状态另有显式入口，不混入默认离线门禁：

```bash
bash scripts/verify-subagents.sh           # 只读检查，漏装或漂移返回非零
bash scripts/verify-subagents.sh --apply   # 调用现有 setup，集中确认后更新
```

`--apply --yes` 表示明确接受各 setup 的默认升级与共享 worker 副作用。Reviewer 不执行更新；安装后还要按下面的真实宿主入口复核，文件存在不等于加载或委派成功。

## 测试准入

新增行为回归必须接入 `--with-tests`，不能只留在命令记录、会话或 `/tmp`。临时探针可用于诊断，但不能作为最终验收证据。

每个测试默认满足：

- 使用本地 fixture，不联网，不读取或修改真实 `HOME`、live 配置、凭据或共享运行时。Bun 测试显式使用 `--no-install`，缓存由统一入口放入临时目录，缺依赖明确 SKIP。仓库 `node_modules` 若链接到仓外 live runtime，相关测试明确 SKIP，不跟随执行；`PI_HOST_DIR` 只允许显式指定一次性隔离宿主。
- 写入只发生在独立临时目录；结束清理进程和文件，外部源保持不变。
- 调用真实生产函数、脚本或宿主官方接口，不复制生产实现做平行校验。
- 断言可观察行为、状态与必要的零写入条件，不以退出 0 或 `PASS` 文本代替行为断言。
- 失败返回非零并给出可定位原因；长进程必须有超时，不能留下后台工作。

修复重复出现或高代价缺陷时，先把最小复现固化为正式回归，再修实现。变异测试从当前源码生成并断言替换锚点存在，不维护生产文件的手工副本。

## 模拟与真实宿主的边界

DSH 安装期校验复用 rc.2 的官方 schema、表达式和配置接口时，结论只能是“拒绝”或“未发现拒绝”。它不能证明宿主已经加载，也不应为复杂 Group／Include 行为另造一套语义推断；无法确定的结果应保守拒绝或交给真实宿主。

OpenCode 的原生角色加载可用本机二进制单独验收，配置与缓存均在测试临时目录，`--standalone` 不连接或抢占 live 服务；默认明确报告 HOST SKIP：

```bash
OPENCODE_TEST_BIN=opencode node tests/verification-agent.mjs
```

DSH 的完整部署事务场景需要显式注入**一次性隔离运行时**，默认只跑离线场景并明确报告 HOST SKIP：

```bash
DSH_TEST_RUNTIME=/path/to/isolated-dsh-runtime bash scripts/check.sh --with-tests
```

不得把该变量指向 live runtime。测试只读引用其包内容，会把会打补丁的包复制到临时目录；隔离运行时不再使用后可整体删除。

同一个隔离 runtime 还应运行真实子代理验收；它使用本地 dummy SSE，不联网或发送真实模型请求：

```bash
DSH_TEST_RUNTIME=/path/to/isolated-dsh-runtime node tests/dsh-subagent-host.mjs
```

该测试实际启动 headless，验证 `verification_review` 的工具 schema、真实委派与子会话收尾、执行层权限和平台白名单；还验证 `read → context_rewrite → 下一次请求` 会撤下原读取内容并保留纠正记录，且退役的 `context_output_read` 不出现在真实工具表。`--dump-config` 只作为前置定位，不作为加载证据。web／tui 内委派和真实审查模型路由仍未覆盖。

以下结论需要真实宿主证据，不能由离线模拟替代：

- 异步插件挂载顺序和运行时 `cwd`；
- TUI／PTY 交互、web 启动及 HTTP 响应；
- headless 请求、流式响应和真实插件树加载；
- Pi／OpenCode 的实际加载与用户操作路径。

真实宿主验收按各宿主 README 的维护说明执行，使用隔离配置、虚拟凭据和本地 dummy 服务，不发真实模型请求。`--dump-config`、进程仍存在、帮助信息或静态导出都不是加载成功证据。

## 功能复核与整理审查分开

Verification 回答“用户要求的功能是否正确”。功能复核依据验收条件、真实使用路径、可复现证据和高风险场景；跨模块、高风险、发布或证据存疑时使用 `verification` 技能并委派 `verification-reviewer`，让它确认关键测试确实能因旧缺陷失败。角色未注册时必须披露；临时 `general` 审查不算角色安装验收。`consolidation-reviewer` 只服务显式整理任务，检查语义保持、简洁性及误删／该删未删，不作功能验收或发布签收。

本机专项检查、真实宿主验收和离线门禁分别报告，不能合并成一句“全部验证通过”。
