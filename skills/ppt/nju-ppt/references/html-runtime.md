# HTML：南大固定模板与 Dashi 内置主题

## 先选正确分支

| 请求 | 执行 |
| --- | --- |
| 明确南大模板＋HTML | 本页南大适配；银杏金、11 页型、每页一个方案 |
| 明确不使用南大模板＋HTML | 加载外部 `dashi-ppt`，沿用其主题选择、媒体、3＋1 与验收 |
| 已说 HTML，没说是否南大 | 只问是否使用南大模板，不默认走 Dashi |
| 已选南大／非南大，没给格式 | 只问 HTML 还是 PPTX |
| 只说做 PPT，两项都没给 | 一次询问是否使用南大模板，以及 HTML 还是 PPTX；等答复后制作 |
| 内容提到南京大学或只点名 nju-ppt | 不据此选定模板；模板意图未明则询问 |

是否南大与输出格式是两个独立选择；只补问缺失项，不重复已明确项。用户已指定其他模板时尊重该选择。南大模式已固定视觉，不再询问 Dashi 内置主题；明确非南大后才走普通模式，不能把南大容量、品牌、页型或文案限制强加到 Dashi。

## 环境与边界

- Node.js 20+；使用宿主实际 Node 路径，不需要 Python 或 ppt-master
- 运行 setup 并选择 PPT 组：新用户安装 Dashi，老用户缺失时补装；随后自动准备南大独立 Node 环境。不静默换引擎
- 查找：`--dashi <实际skill根目录>` → `DASHI_PPT_ROOT` → `~/.agents/skills/dashi-ppt`
- 当前本机兼容基线：Dashi `0.4.14`；不是最新版保证。不同版本明确报错，先复验适配再更新基线
- 普通生成与检查不联网安装；安装器调用 `prepare_html.mjs --install`，仅在独立缓存执行 `npm ci`，不修改日常 Dashi／ppt-master
- 默认缓存：`~/.local/share/agent-skills/nju-ppt/html/<指纹>/project`；`--work-dir` 指定全新隔离目录，已有不同基线不覆盖
- 安装模式只复制源码再装锁定依赖；已有完整环境直接复用。失败清理本次临时目录，可重跑 setup；上游与适配改变后使用新指纹目录

外部来源：`chuspeeism/dashi-ppt-skill`，固定提交 `21dc7e5fc8c3a0d7f6a94948153dd1ee954f4e64`（0.4.14）；不自动追随最新版本。不同源或未登记的同名副本保留并告警，由用户确认后处理。

仓库不内置 Dashi 源码；该提交根 LICENSE 为 GNU AGPL v3，第三方许可仍适用，不能把适配或生成物推定为当前仓库许可。公开发布前核对组合分发要求；跨平台与完整线上入口验收另记。

## 内容与输入

完整读取用户材料，在独立项目归档。按 `style-contract.md` 凝练内容与分配页型，保留事实、来源、单位与删减说明；不编造数据。

输入 `deck.json`：

```json
{
  "title": "研究进展",
  "slides": [
    {"id":"cover", "type":"cover", "fields":{"PAGE_TITLE":"南京大学", "TITLE":"研究进展", "SUBTITLE":"本次汇报范围"}},
    {"id":"results", "type":"chart_column", "fields":{"PAGE_TITLE":"实验结果", "SOURCE":"来源：用户提供；单位：秒", "TAKEAWAY":"结论须依据真实数据"}, "chart":{"categories":["方案甲","方案乙"],"series":[{"name":"耗时","values":[24,18]}]}}
  ]
}
```

- 页型：`cover / toc / chapter / points3 / pillars4 / two_col / timeline / chart_column / chart_combo / table / ending`
- 全套恰好一个 `cover`；稳定 `id` 为 1–80 位英文字母、数字、连字符，首位字母
- `fields` 键沿用本包对应 SVG 的 `{{PLACEHOLDER}}`；值只写普通文本，不写 HTML／JS
- 每页必填 `PAGE_TITLE`；`PAGE_NUM` 自动生成，其余未使用字段置空。查 `assets/html/templates.json` 的 `fields`，或直接查看原 SVG
- 图表：1–6 类别、1–3 系列、数值有限且对齐；`chart_combo` 恰好两系列，第一组柱、第二组线，必填 `AXIS_Y / AXIS_Y2 / SOURCE`
- 柱图单位写入系列名或 `SOURCE`；数值必须来自材料，验收示例不得留在正式稿
- 表格：`table: {"headers":["项目","值"], "rows":[["方案甲",24]]}`，最多 6 数据行×5 列；长表先拆页
- `two_col` 可加 `image: "相对输入JSON的本地.png"`；支持 PNG/JPEG/WebP，生成时复制到本次 deck。先保留原图，不填远程 URL 或临时失效链接
- 两栏图片页将 `FIGURE_TITLE / FIGURE_DESC` 置空，保留 `FIG_CAPTION` 作为图片说明
- 完整 4 页验收输入见 `examples/html-pilot.json`，只作字段参考，不沿用其中示例数据

## 生成与预览

把 `<skill>` 展开为当前加载 skill 的实际根目录；输出必须是不存在的新目录，避免重生成覆盖浏览器编辑。

```text
node <skill>/scripts/render_html.mjs --input <project>/deck.json --out <project>/html-deck
```

成功时输出 `html`、独立 `runtime` 与预览命令。运行该返回命令启动 Dashi 服务；端口用空闲的 5200–5999，不用 4178／4300／4400。只用 Dashi 自带服务，静态服务器没有其保存／导出接口。

```text
node <runtime>/scripts/start-preview-server.mjs <project>/html-deck/ppt 5200
```

交付目录：`html-deck/ppt/index.html`＋完整 `assets/`；保留 `source-deck.json / goal.json / runtime.json` 供追溯。用户预览地址只给 `http://127.0.0.1:<port>/`。离线复制整个 `ppt/`；不能只拿走 HTML。

适配复用 Dashi 现有单版式运行路径，不走强制四方案的 v2 scaffold。普通 Dashi 分支仍执行其标准流程；不要伪造四个相同候选来凑校验。

## 编辑与保存

- 编辑模式点击标题、正文、图表数值／标签、表格单元格，直接改字
- 柱图／柱线图的图形随数值更新；图表值须保持有限数字，不把单位写进数值槽
- HTTP 服务在编辑停止约 2 秒后自动保存到落盘 HTML；等待保存成功后再关闭，用新会话重开并核对。只看到 localStorage 内容不算保存通过
- `file://` 可离线演示，但不承诺自动保存；要保存请使用 Dashi 服务或其导出 HTML
- 浏览器编辑后的 HTML 是交付依据，`deck.json` 不自动双向同步；需要重新生成时另建目录，先归档编辑稿
- PPTX 原生交付继续用 ppt-master；Dashi 的导出按钮不代表与原有南大原生图表／表格验收等价

## 验收与停止

- 脚本执行 Dashi goal 校验、渲染、Swiss 校验和文案校验；通过不代表视觉与编辑验收完成
- 逐页实际打开：标题、正文、结论、图表、素材无明显遮挡溢出；原校徽、叶片、建筑均可见
- 真实修改标题、正文、柱图／柱线图值、表格值；确认图形变化，保存后在全新浏览器会话重开
- 复制整个 `ppt/` 到另一位置，断网打开并验证翻页；检查全屏、首尾页与窗口缩放
- 无操作浏览器能力时明确写“编辑回读未测”，不以静态校验充数；未测 WPS、投影或其他系统如实披露
- 上游契约变化、保存失败、品牌资产缺失时报告阻塞，不切普通金色主题或栅格整页来冒充完成

维护模板时，只修改原 SVG 与 `scripts/build_html_templates.py`，用开发机 Python 3.10+ 重建 `assets/html/templates.json`；不要手改生成的几何数据。最终生成 HTML 只需要 Node。
