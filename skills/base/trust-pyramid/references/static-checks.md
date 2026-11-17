# 静态约束的实现选择

工具能力按 2026-11-17 官方文档核对；接入时核实目标项目实际版本。以下是条件化示例，不是套件安装时下发的默认禁令。

## 先判断要检查什么

| 要保证的事情 | 合适落点 | 判定边界 |
| --- | --- | --- |
| 未定义变量、常见误用、类型不匹配 | Ruff／ESLint、项目已有类型检查器 | 静态检查；不能证明业务行为正确 |
| 某目录不得导入某模块或使用旧 API | linter 内置限制规则；复杂依赖图用 Import Linter 等 | 只覆盖工具实际能解析的导入／访问方式 |
| YAML/JSON 字段、技能元数据、目录与引用结构 | 现有 schema 或小型结构检查脚本 | 检查源文件而不启动目标程序，属于静态约束 |
| 修改配置后仍保留用户密钥，连续执行仍幂等 | 运行真实合并／安装逻辑并对照输出 | 行为验证；语法检查无法证明 |
| 梯度、数值误差、实际加速、样本独立性 | 参考对照、运行检查、实验协议 | 运行／科学验证，不能仅用 lint 解决 |

`pytest` 是测试执行框架，不是静态分析器。用它调用函数、启动服务、比较结果，通常是动态测试；用它承载纯 AST／配置检查，检查本身仍是静态的。项目已经用 pytest 时可以复用，没有时不为几条静态规则引入它。

CI、pre-commit、Make、npm scripts 负责“什么时候运行”，Ruff、ESLint 或项目脚本负责“检查什么”。不需要另建一个套件级 runner 才能把它们连起来。

## Python：优先用已有规则表达

假设项目已经有带统一超时策略的 `project.http.get`，并明确要求业务代码不再直接调用 `requests.get`。可在现有 `pyproject.toml` 的对应表中合入：

```toml
[tool.ruff.lint]
extend-select = ["TID251"]

[tool.ruff.lint.flake8-tidy-imports.banned-api]
"requests.get".msg = "请使用 project.http.get，沿用项目统一超时策略。"

[tool.ruff.lint.per-file-ignores]
"src/project/http.py" = ["TID251"]
```

在项目已有环境中运行 `ruff check .`，沿用原有规则，不覆盖已有配置。这只限制 `requests.get`，并非“所有网络请求都受控”；其它调用形态要按实际需要另定范围。适配层豁免会忽略该文件的全部 TID251 诊断，多个禁用 API 共用规则时要重新判断该粒度是否合适。动态导入、反射等也不在完整保证之内。

新项目若还没有这个共享 API，先判断是否真的需要它；不能为写一条禁用规则，先创造一个无实际价值的包装层。

截至上述核对日期，Ruff **不支持用户自定义／第三方规则插件**。需要它无法表达的规则时：

- 模块之间的分层／禁止依赖：优先评估 [Import Linter](https://import-linter.readthedocs.io/en/stable/contract_types/layers/)；它通过导入关系检查约定，而不执行目标业务逻辑。
- 项目已有 Pylint／Flake8：复用其扩展能力。
- 简单、局部且边界清晰：Python `ast` 或配置解析脚本可以胜任；AST 不自动提供完整名称、别名和跨文件解析，复杂规则不要用几条正则假装解决。
- 跨语言结构模式：按需要评估 Semgrep 等现成工具，而不是在套件中自建多语言解析器。

官方依据：[TID251](https://docs.astral.sh/ruff/rules/banned-api/) · [配置](https://docs.astral.sh/ruff/settings/#lint_flake8-tidy-imports_banned-api) · [Ruff 插件限制](https://docs.astral.sh/ruff/faq/#can-i-write-my-own-linter-plugins-for-ruff)。

## JavaScript／TypeScript：配置规则或本地扩展

- 禁止指定静态导入：ESLint `no-restricted-imports`；按配置中的 `files` 范围限定业务目录，保留合法适配入口。
- 禁止特定语法模式：先看已有规则与 `no-restricted-syntax` 是否够用。
- 需要项目专用判定：写本地 ESLint rule，使用它的 AST／诊断能力；不必先发布 npm 包。
- 类型兼容：复用项目 TypeScript 检查；宿主动态行为仍须实际加载验证。

`no-restricted-imports` 只针对静态 `import`，不覆盖动态 `import()`；CommonJS 的 `require()` 要选择相应规则。规则命中一个入口不等于整个依赖边界已经封闭。

官方依据：[导入限制](https://eslint.org/docs/latest/rules/no-restricted-imports) · [自定义规则教程](https://eslint.org/docs/latest/extend/custom-rule-tutorial)。

## Shell 和混合套件

`bash -n` 检查 shell 语法，ShellCheck 检查常见 shell 误用；二者都不能证明部署后文件正确或敏感值得到保留。目录、元数据、相对引用等跨文件约定，可由项目现有 `scripts/check.*` 检查。需要 shell 语义时用解析器或现成工具，不用正则扫描冒充完整分析。

## 一条规则最少需要什么

例如“共享核心不得导入宿主适配代码”：先明确哪些目录属于核心和适配层，再选依赖检查工具，配置不允许的方向，并保留一个合法导入例和一个违规例。检查的错误应指向依赖位置，并提示把宿主调用移回适配层或使用已有接口。

这几项放在项目原有配置、规则说明和测试位置即可：**目的、范围、例外、替代路径、执行入口**。如果实现还依赖大量不稳定特判，先回头审视代码边界或规则是否成熟，不把工具本身发展成新项目。
