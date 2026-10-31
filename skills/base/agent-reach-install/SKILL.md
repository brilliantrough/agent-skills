---
name: agent-reach-install
description: 安装与使用 Agent Reach（agent-reach CLI），只读检索各平台内容：小红书、B站、Twitter/X、Reddit、YouTube、GitHub、V2EX、雪球、LinkedIn/Boss直聘、Instagram、Facebook、小宇宙。Use when 需要安装/升级 agent-reach，或要搜索、读帖、看评论、取字幕、查行情职位，而自带网页搜索/读取拿不到正文。不自动执行安装，本文只给官方命令与用法；不做发帖、评论、点赞等写操作，不替用户登录。
---

# Agent Reach 安装与用法

上游官方包，**不要在本仓复制它的源码，也不要给上游打补丁**。
上游自带一份 skill，`agent-reach setup` 会写到 `~/.agents/skills/agent-reach/`，
所以本文件叫 `agent-reach-install`，避免与那个目录冲突。

## 安装

**可选**：`pi-setup.sh` / `opencode-setup.sh` 在 skills 同步后会询问（默认 N），确认后才调用
`scripts/install.sh`，缺 `agent-reach` 才装，已装则跳过（与 strictdoc 同一规则）。

手工安装等价于：

```bash
uv tool install --python 3.12 https://github.com/Panniantong/Agent-Reach/releases/latest/download/agent-reach.zip
agent-reach setup
```

缺 `uv` 时先装：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

`setup` 会装默认渠道、放置官方 skill，并启动专用无头浏览器。
服务器没有桌面也能用；只有 `agent-reach login <channel>` 需要人工窗口。
重复运行不会重装，也不会触碰 `~/.agent-reach/` 里的凭据与登录态。

## 升级与卸载

```bash
agent-reach update      # 程序 + 渠道工具 + 官方 skill 一起升
agent-reach uninstall
```

因为本仓不打补丁，升级不需要重新合并任何东西。

## 基本用法

```bash
agent-reach channels                       # 看渠道与可用动作
agent-reach doctor                         # 体检：哪些渠道可用、缺什么
agent-reach <channel> <action> [args]      # 统一入口
agent-reach read <url>                     # 按 URL 自动选渠道
```

常用例子：

```bash
agent-reach twitter search "关键词" --limit 5
agent-reach bilibili hot --limit 5
agent-reach xiaohongshu search "关键词" --limit 5
agent-reach reddit search "关键词" --limit 5
agent-reach github search "关键词"
```

## 已知边界（上游行为，本仓修不了）

| 现象 | 原因 | 应对 |
|---|---|---|
| `reddit read` 返回 342 字 `You've been blocked by network security` | 默认先走 Jina，Reddit 封了 Jina 出口；上游的反爬识别漏掉这种页 | `agent-reach web read "<url>" --backend exa` |
| `reddit subreddit` 恒为 `UPSTREAM_BROKEN` | 该动作没有 `public_web` 回退，唯一后端要 `.json`，匿名请求被 403 | 改用 `agent-reach reddit search "关键词"` |
| 不要执行 `agent-reach add reddit` | 加上之后 `search` 会从 public-web 切到 opencli，立即失败，且状态持续 | 保持 reddit 未添加 |
| 小红书需要登录一次 | `agent-reach login xiaohongshu` 要人工扫码窗口 | 无桌面机器把 cookie 注入 `~/.agent-reach/browser/profile` 后可复用 |
| Reddit/小红书搜索偏慢或偶发空结果 | 走 Exa 免费托管服务，无 key、无 SLA | 重试即可，不要当成"必须登录" |

## 凭据放哪

- X：`~/.agent-reach/config.yaml` 里的 `twitter_auth_token` / `twitter_ct0`
- 浏览器登录态：`~/.agent-reach/browser/profile/`
- **不要把真实凭据提交进本仓。** 本仓只放安装逻辑，不放任何账号信息。

### 让 X 装完即可用

**安装本身不强制任何 cookie。** 没有凭据时只提示一句，不影响安装；
想用时再放文件并重跑一次 `install.sh` 即可，不必重装。

`scripts/install.sh` 在安装后会自动播种 X 凭据，来源按优先级：

1. 环境变量 `X_AUTH_TOKEN` / `X_CT0`
2. 本地私密文件 `~/.config/agent-reach/x-cookies.env`（权限 600，两行同名校验）

```bash
# 方式一：临时环境变量
X_AUTH_TOKEN=... X_CT0=... bash scripts/install.sh

# 方式二：本机长期保存（不进仓库）
mkdir -p ~/.config/agent-reach && chmod 700 ~/.config/agent-reach
printf 'X_AUTH_TOKEN=%s\nX_CT0=%s\n' '你的token' '你的ct0' > ~/.config/agent-reach/x-cookies.env
chmod 600 ~/.config/agent-reach/x-cookies.env
```

已存在的凭据**永不覆盖**；没有提供时只提示，不影响安装。
其他人装这份 skill 时需要用**他们自己的** X cookie——把账号 cookie 提交到公开仓库等于公开账号。

### 让小红书装完即可用（无桌面，不需要扫码窗口）

把 cookie 存到本机私密文件：

```bash
mkdir -p ~/.config/agent-reach && chmod 700 ~/.config/agent-reach
cp /path/to/xhs-cookies.json ~/.config/agent-reach/xhs-cookies.json
chmod 600 ~/.config/agent-reach/xhs-cookies.json
```

格式为 JSON 数组或 `{"cookies":[...]}`，每条含 `name` / `value` / `domain` / `path`。

`install.sh` 检测到该文件后会调用 `scripts/inject-cookies.sh`，通过 CDP 把 cookie 写进
Agent Reach 的无头浏览器；之后官方查询路径 `agent-reach xiaohongshu search` 直接复用，
**不需要桌面，也不需要 `agent-reach login`**。也可用 `XHS_COOKIE=<路径>` 指定别的文件。
