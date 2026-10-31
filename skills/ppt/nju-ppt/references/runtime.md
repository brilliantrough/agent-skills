# 环境准备与平台边界

## 正常安装

在套件完整setup中选择 `ppt` 组，或使用 `bash skills-sync.sh ppt`。同步器会精确补装 `hugohe3/ppt-master` 中的 `ppt-master`，再创建独立venv；不复制引擎源码，不接管不同源的同名skill。

仅通过其它skill管理器复制本包时，不假定依赖钩子已运行；先确认 `ppt-master` 已安装，再按下面步骤准备环境。

## 手动准备或检查

1. 找到实际的 `nju-ppt` skill目录，选Python 3.10+，不要照抄他人的解释器路径
2. 检查：`<python> <skill>/scripts/prepare.py`
3. 同意创建环境和联网补缺后：`<python> <skill>/scripts/prepare.py --install`
4. 引擎不在共享目录时加 `--engine <ppt-master-skill根目录>`，或设 `PPT_MASTER_ROOT`

成功输出JSON：`python`供后续所有Python／pip命令使用，`ppt_master_root`供加载引擎与查脚本，`template_root`作为exact root。输出仅代表核心包可导入、模板契约通过，不代表PPT已生成或软件预览通过。

| 项目 | 位置／要求 |
| --- | --- |
| 常规skill入口 | `~/.agents/skills/nju-ppt`、`~/.agents/skills/ppt-master` |
| 模板 | 本包 `assets/nju-academic-ginkgo`，含同级templates/images/icons |
| 独立环境 | `~/.local/share/agent-skills/nju-ppt/venv` |
| 解释器 | Windows为venv下 `Scripts/python.exe`；macOS/Linux为 `bin/python` |
| 指定安装解释器 | 同步器环境变量 `NJU_PPT_PYTHON`，值是单个Python可执行文件，不含命令行参数 |
| 临时HOME | 手动脚本加 `--home <原生路径>`；Windows原生Python使用Windows路径，不传Git Bash的 `/c/...` |

`--install`只用独立venv的 `python -m pip` 安装核心包，无系统包管理、无sudo、无模型密钥。没有Python、venv/ensurepip或网络时报告失败，不改系统Python。更新模板或引擎后重跑检查。

## 生成边界

- 完整生成由真实 `ppt-master` 执行；脚本不接管选题、排版或导出
- 默认 .md/.txt不需要AI图像密钥；DOCX、PDF、旁白等沿用上游按需依赖与许可
- 模板无需注册到引擎全局索引；用 `apply_template.py <project> --root <template_root>` 安装后只读项目副本
- 引擎兼容基线：`hugohe3/ppt-master` 提交 `8070d3df1f6f54b5fb60a9ae66e79c664f050212`；这是已测基线，不是安装锁版本
- 引擎升级后如契约失败，报告错误与当前版本；不静默换模板、降级或修改上游源码

## 平台验证

安装、原生导出、真实软件预览分开记录，不能从一个推导另一个。

- Windows：安装器使用Git Bash，生成使用Windows Python；本包新增分发链的实测见仓库README
- macOS/Linux：提供相同Python路径，无现成实测证据前标未测；WSL按Linux处理
- 缺微软雅黑：先说明并选已安装中文字体，重新测量换行；不分发商业字体
- Office不是原生导出的硬依赖；没有实际打开时，不声称PowerPoint/WPS已验证
- 不自动安装Office、字体或修改系统代理；投影效果另测
