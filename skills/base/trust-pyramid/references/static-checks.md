# 静态约束的实现选择

工具能力按 2026-11-17 官方文档核对；接入时核实目标项目实际版本。以下是条件化示例，套件安装时不下发任何默认禁令。

## 先判断要检查什么

| 要保证的事情 | 合适落点 | 判定边界 |
| --- | --- | --- |
| 易错参数组合、隐含调用顺序、旧范例被照抄 | Codebase：改类型或签名，迁移旧调用 | 从源头去掉错误写法，不需要额外规则 |
| 未定义变量、常见误用、类型不匹配 | Ruff／ESLint、项目已有类型检查器 | 静态检查；业务行为另行验证 |
| 某目录不得导入某模块或使用旧 API | linter 内置限制规则；复杂依赖图用 Import Linter 等 | 只覆盖工具实际能解析的导入／访问方式 |
| YAML/JSON 字段、技能元数据、目录与引用结构 | 现有 schema 或小型结构检查脚本 | 检查源文件而不启动目标程序，属于静态约束 |
| 修改配置后仍保留用户密钥，连续执行仍幂等 | 运行真实合并／安装逻辑并对照输出 | 行为验证；语法检查给不出这类证据 |
| 梯度、数值误差、实际加速、样本独立性 | 参考对照、运行检查、实验协议 | 运行／科学验证，lint 覆盖不到 |

形式化验证依据明确的模型或规格证明性质，可以不运行目标程序；静态类型系统也能保证部分性质。这里的分层用于选择证据，各层的工具可以重叠。

`pytest` 是测试执行框架。用它调用函数、启动服务、比较结果，是动态测试；用它承载纯 AST／配置检查，检查本身仍是静态的。项目已经用 pytest 时可以复用，没有时不为几条静态规则引入它。

CI、pre-commit、Make、npm scripts 负责“什么时候运行”，Ruff、ESLint 或项目脚本负责“检查什么”。把它们连起来用项目现有入口即可，不需要套件级 runner。

## 报错信息怎么写

给 Agent 看的检查报错同时包含三项，让它看到报错就能改对，不必再搜全仓：

1. 具体位置与违规项：哪个文件、哪一行、违反哪条约束；
2. 正确替代：改调哪个模块或函数，或改用什么结构；
3. 合法例外的位置：确属底层适配时，代码应放在哪个受管文件。

## 六类配方如何选工具

| 配方 | 可机械检查的部分 | 仍需的证据 |
| --- | --- | --- |
| 注释与临时补丁 | 确定范围内的禁用 API／语法，用 Ruff 或 ESLint 已有规则 | 语义审查注释与根因；“自我辩护”无法用关键词判定 |
| 依赖与模块边界 | Python 用 Import Linter；JS/TS 可用 dependency-cruiser；简单直接导入用 ESLint | 核对解析覆盖、合法通信路径；实际加载与运行环境行为 |
| API 与状态设计 | 项目类型检查器、禁用旧 API、外部配置 schema | 调用方是否更易用；状态转换、外部输入和失败路径 |
| 重复与维护归属 | 已声明的唯一入口、生成源和非法依赖可做结构检查 | 重复检测仅提示候选；语义是否相同、是否应共同演化靠审查 |
| 副作用与错误处理 | linter 的空捕获／异步误用规则；TS 可选 `no-floating-promises` | 取消、释放、重试及真实失败传播 |
| 工作区与产物管理 | 项目已约定的目录、元数据、引用及入库产物约束 | 文件归属和证据价值靠审查；输出／清理行为需运行确认 |

工具是候选映射。每次只接入当前规则需要的工具，沿用项目锁定的版本与执行环境。

## Python：优先用已有规则表达

假设项目已经有带统一超时策略的 `project.http.get`，并明确要求业务代码不再直接调用 `requests.get`。可在现有 `pyproject.toml` 的对应表中合入：

```toml
[tool.ruff.lint]
extend-select = ["TID251"]

[tool.ruff.lint.flake8-tidy-imports.banned-api]
"requests.get".msg = "请使用 project.http.get，沿用项目统一超时策略；底层封装仅限 src/project/http.py。"

[tool.ruff.lint.per-file-ignores]
"src/project/http.py" = ["TID251"]
```

在项目已有环境中运行 `ruff check .`，沿用原有规则，不覆盖已有配置。这条规则只限制 `requests.get`，其它调用形态（如 `requests.request("GET", ...)`）按实际需要另定范围；动态导入和反射不在覆盖之内。适配层豁免会忽略该文件的全部 TID251 诊断，多个禁用 API 共用规则时要重新判断这个粒度是否合适。

新项目若还没有这个共享 API，先判断是否真的需要它，不为写一条禁用规则先造一个没有实际价值的包装层。

截至上述核对日期，Ruff **不支持用户自定义／第三方规则插件**。需要它无法表达的规则时：

- 模块之间的分层／禁止依赖：优先评估 [Import Linter](https://import-linter.readthedocs.io/en/stable/contract_types/layers/)；它通过导入关系检查约定，包含间接依赖，不执行目标业务逻辑。
- 项目已有 Pylint／Flake8：复用其扩展能力。
- 简单、局部且边界清晰：Python `ast` 或配置解析脚本可以胜任；AST 不自动提供完整的名称、别名和跨文件解析，复杂规则换用能解析的工具，不用几条正则顶替。
- 跨语言结构模式：按需要评估 Semgrep 等现成工具，不在套件中自建多语言解析器。

官方依据：[TID251](https://docs.astral.sh/ruff/rules/banned-api/) · [配置](https://docs.astral.sh/ruff/settings/#lint_flake8-tidy-imports_banned-api) · [Ruff 插件限制](https://docs.astral.sh/ruff/faq/#can-i-write-my-own-linter-plugins-for-ruff)。

## JavaScript／TypeScript：配置规则或本地扩展

- 禁止指定静态导入：ESLint `no-restricted-imports`；按配置中的 `files` 范围限定业务目录，保留合法适配入口，`message` 里写明替代模块。
- 禁止特定语法模式：先看已有规则与 `no-restricted-syntax` 是否够用。
- 跨文件依赖方向与循环：可用 [dependency-cruiser 的规则](https://github.com/sverweij/dependency-cruiser/blob/main/doc/rules-reference.md)，按实际源码根和模块解析配置检查；字符串路径匹配达不到完整依赖分析。
- 需要项目专用判定：写本地 ESLint rule，使用它的 AST／诊断能力；不必先发布 npm 包。
- 类型兼容：复用项目 TypeScript 检查；宿主动态行为仍须实际加载验证。
- Promise 处理：[`@typescript-eslint/no-floating-promises`](https://typescript-eslint.io/rules/no-floating-promises/) 需要类型信息。某些配置允许 `void promise` 通过，但 `void` 不会处理 rejection；后台任务仍需明确的错误出口。

`no-restricted-imports` 只针对静态 `import`，不覆盖动态 `import()`；CommonJS 的 `require()` 要选择相应规则。规则命中一个入口时，其余入口仍要逐个确认，依赖边界才算封闭。

官方依据：[导入限制](https://eslint.org/docs/latest/rules/no-restricted-imports) · [自定义规则教程](https://eslint.org/docs/latest/extend/custom-rule-tutorial)。

## Shell 和混合套件

`bash -n` 检查 shell 语法，ShellCheck 检查常见 shell 误用；部署后文件是否正确、敏感值是否保留，要靠运行验证。目录、元数据、相对引用等跨文件约定，可由项目现有 `scripts/check.*` 检查。需要 shell 语义时用解析器或现成工具，正则扫描达不到完整分析。

混合仓库里，小型结构检查加最小行为回归通常比引入重型框架有效。以“安装脚本合并配置时保留用户私密值”为例，四层各有分工：

| 层 | 落点 | 作用 |
| --- | --- | --- |
| Codebase | 合并函数对敏感键和占位符值默认保留本机值 | 正确行为是默认路径，调用方不需要记住哪些键要保护 |
| Static analysis | `bash -n`，加项目检查脚本扫描公开模板 | 拦语法错误，以及模板里出现的真实私密 URL 或主机名 |
| Verification | 用固定输入实际执行合并函数并断言输出 | 证明私密值确实保留、重复执行结果不变 |
| Prose | 项目说明里一句规则和回归命令入口 | 说明为什么有这条规则；敏感键清单留在代码里 |

## 从配方到项目检查

以“共享核心不得导入宿主适配代码”为例：

1. 确定核心、适配层和共享契约的实际路径；声明约束的是直接导入还是包括间接依赖。已有的合法跨边界行为先找到正确承载位置，推荐替代可用之后再启用规则。
2. 合入现有检查配置，保留已有规则；报错包含位置、依赖边及建议替代。无法解析的路径要报错，不能静默算通过。
3. 用最小合法例和违规例实际运行，确认一个通过、一个失败；覆盖项目使用的别名、重导出与合法例外。Import Linter 的 layers 合同包含间接依赖，ESLint 的静态导入限制不包含，两者不能互换。
4. 接到现有 lint/check 命令；项目已有 CI 时接入同一入口。当前只做到手动检查就如实报告，不为这一条规则另建通用执行平台。
5. 核对行为证据：插件真实加载、配置写入回读、UI 用户路径或研究数值对照，按改动选择。Agent 或既有自动流程可执行；有生产副作用或超出预算时按项目约定处理。

规则说明留在配置注释、模块说明或项目已有规范即可，不新增独立台账。豁免指向具体范围和原因；需要大量不稳定特判时，先重审边界与规则。临时验证输入用完清理，值得保留的回归放进现有测试位置。
