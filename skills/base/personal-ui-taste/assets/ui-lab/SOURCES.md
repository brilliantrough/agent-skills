# 素材来源

此实验室吸收公开设计做法，页面结构与交互为本仓实现。以下版本对应实际随包素材；不依赖在线 CDN。

| 随包内容 | 来源 / 版本 | 许可证 |
| --- | --- | --- |
| Inter variable latin woff2 | `@fontsource-variable/inter` 5.3.0 | [SIL OFL 1.1](licenses/inter.txt) |
| Nunito variable latin woff2 | `@fontsource-variable/nunito` 5.3.0 | [SIL OFL 1.1](licenses/nunito.txt) |
| IBM Plex Sans latin 400/600 woff2 | `@fontsource/ibm-plex-sans` 5.3.0 | [SIL OFL 1.1](licenses/ibm-plex-sans.txt) |
| Noto Sans SC variable 切片 ×101 | [`@fontsource-variable/noto-sans-sc`](https://github.com/fontsource/fontsource) 5.3.0 | [SIL OFL 1.1](licenses/noto-sans-sc.txt) |
| Noto Serif SC variable 切片 ×101 | [`@fontsource-variable/noto-serif-sc`](https://github.com/fontsource/fontsource) 5.3.0 | [SIL OFL 1.1](licenses/noto-serif-sc.txt) |
| Gray / Blue 十二阶样本 | [`@radix-ui/colors`](https://github.com/radix-ui/colors) 3.0.0 | [MIT](licenses/radix-colors.txt) |
| Python / PyTorch / Docker / GitHub SVG | [`simple-icons`](https://github.com/simple-icons/simple-icons) 16.34.0 | [CC0](licenses/simple-icons.txt)；商标及品牌使用规则仍适用 |
| 19 个操作图标 | [`lucide`](https://github.com/lucide-icons/lucide) 1.52.0 | [ISC / 上游完整声明](licenses/lucide.txt) |

字体包与字体本身的许可证不同，随包保留的是字形文件对应的上游许可。中文字体已随包携带 Noto Sans SC（思源黑体）与 Noto Serif SC（思源宋体）变量切片，页面按 unicode-range 只下载用到的字集；宋体切片只服务 paper-cream 的标题与数字。配对与自托管方式见 [视觉做法](../../references/visual-craft.md)。

## 设计参考

| 来源 | 本例借用的方面 |
| --- | --- |
| [shadcn/ui](https://github.com/shadcn-ui/ui) | 中性主操作、统一控件比例、边界、状态与层次；本例不是其 React 组件实例 |
| [GitHub Readme Stats](https://github.com/anuraghazra/github-readme-stats) | 摘要标题、数字与次要信息的排列；无远端数据请求，未复制其实现 |
| [Markdown Badges](https://github.com/ileriayo/markdown-badges) | 图标加短标签的构成；本例为原生 HTML/CSS，未使用 Shields.io 图片 |
| [Fontsource](https://github.com/fontsource/fontsource) | 本地字体交付；仅携带实际使用的字重和子集 |
| [code.claude.com/docs](https://code.claude.com/docs) | paper-cream 主题的暖白纸面、暖灰文字、陶土强调与衬线标题；取线上实测的色值与字体角色，页面结构仍是本仓实现 |
| [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)、[alchaincyf/huashu-design](https://github.com/alchaincyf/huashu-design) | 页面模式、内容立意、关键帧构图、叙事/动画与视觉 QA 方法；可按独立 skill 使用，本目录不含其代码 |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | §10 正向模式词汇与改造审查；设计探索采用非对称开篇、对象连续性和滚动章节思路，原生实现为本仓原创 |

其余主题的初始方向与参考链接见 [主题目录](../../themes/README.md)。旧 baseline 和 layered 仅供对照。素材许可不等于参考网站的全部代码、品牌和插画可直接复制。
