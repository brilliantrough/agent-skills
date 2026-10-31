import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import { existsSync, mkdtempSync, writeFileSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

// 会话切换后 pretty-tui 的补丁必须还在：Pi 在 /new、/resume、/fork、/reload
// 时先发 session_shutdown 再发 session_start，而扩展模块只加载一次。
const root = process.cwd();

// 定位 Pi 安装目录：PI_HOST_DIR 显式指定，否则在常见位置找；找不到就跳过（不硬编码个人路径）。
function findHost() {
  const pkg = '@earendil-works/pi-coding-agent';
  const cands = [];
  if (process.env.PI_HOST_DIR) cands.push(process.env.PI_HOST_DIR);
  cands.push(join(homedir(), '.pi', 'agent', 'npm', 'node_modules', pkg));
  const shared = join(homedir(), '.local', 'share', 'pi-node');
  if (existsSync(shared)) {
    for (const d of readdirSync(shared)) cands.push(join(shared, d, 'lib', 'node_modules', pkg));
  }
  try {
    cands.push(join(execSync('npm root -g', { encoding: 'utf8' }).trim(), pkg));
  } catch {}
  return cands.find((p) => existsSync(join(p, 'dist', 'core', 'extensions', 'loader.js')));
}
const host = findHost();
if (!host) {
  console.log('SKIP: 未找到 @earendil-works/pi-coding-agent；用 PI_HOST_DIR=<安装目录> 指定后重跑');
  process.exit(0);
}
const agent = mkdtempSync(join(tmpdir(), 'probe-cycle-'));
process.env.PI_CODING_AGENT_DIR = agent;
writeFileSync(join(agent, 'pretty-tui.json'), JSON.stringify({ mode: 'clean' }));
const asURL = (path) => pathToFileURL(path).href;
let entries = [];
let pretty;
let ctx;

try {
  const { loadExtensions } = await import(asURL(join(host, 'dist/core/extensions/loader.js')));
  const loaded = await loadExtensions([resolve(root, 'pi/extensions/pretty-tui/index.ts')], root);
  assert.deepEqual(loaded.errors, []);
  pretty = loaded.extensions[0];
  const { initTheme, getThemeByName } = await import(asURL(join(host, 'dist/modes/interactive/theme/theme.js')));
  initTheme('dark', false);
  const theme = getThemeByName('dark');
  const { AssistantMessageComponent } = await import(asURL(join(host, 'dist/modes/interactive/components/assistant-message.js')));
  const { ToolExecutionComponent } = await import(asURL(join(host, 'dist/modes/interactive/components/tool-execution.js')));
  const { stripTerminalSequences } = await import(asURL(join(host, 'node_modules/@earendil-works/pi-tui/dist/index.js')));
  const tui = { mode: 'fullscreen', terminal: { columns: 120, rows: 40 }, requestRender() {} };
  ctx = {
    cwd: root, hasUI: true,
    ui: { theme, getToolsExpanded: () => false, requestRender() {} },
    sessionManager: { getBranch: () => entries.slice(), getEntries: () => entries.slice(), buildContextEntries: () => entries.slice() },
  };
  loaded.runtime.appendEntry = (customType, data) => entries.push({ type: 'custom', id: `entry:${entries.length}`, customType, data });
  const emit = async (type, data = {}) => { for (const fn of pretty.handlers.get(type) ?? []) await fn({ type, ...data }, ctx); };

  const runTurn = async () => {
    const views = [];
    let toolIndex = 0;
    await emit('message_start', { message: { role: 'user', content: 'go' } });
    await emit('agent_start');
    for (const round of [0, 1]) {
      const call = { type: 'toolCall', id: `call:${++toolIndex}`, name: 'bash', arguments: { command: 'echo hi' } };
      const message = {
        role: 'assistant', api: 'openai-completions', provider: 'deepseek', model: 'deepseek-flash', timestamp: Date.now() + round,
        content: [{ type: 'thinking', thinking: `Reasoning ${round}` }, call],
        stopReason: 'toolUse', usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      };
      const streaming = { ...message, content: [] };
      await emit('message_start', { message: streaming });
      const view = new AssistantMessageComponent(undefined, true, theme, 'Thinking...', 1, []);
      views.push(view);
      for (const item of message.content) {
        streaming.content.push(item);
        view.updateContent(streaming, true);
        await emit('message_update', { message: streaming });
      }
      view.updateContent(message, false);
      await emit('message_end', { message });
      const tool = new ToolExecutionComponent('bash', call.id, call.arguments, {}, pretty.tools.get('bash').definition, tui, root);
      views.push(tool);
      await emit('tool_execution_start', { toolCallId: call.id, toolName: 'bash', args: call.arguments });
      tool.markExecutionStarted();
      tool.setArgsComplete();
      const result = { content: [{ type: 'text', text: 'ok' }], details: {}, isError: false };
      tool.updateResult(result, false);
      await emit('tool_execution_end', { toolCallId: call.id, toolName: 'bash', result, isError: false });
    }
    await emit('agent_end');
    await emit('agent_settled');
    return views.flatMap((view) => view.render(120)).map(stripTerminalSequences);
  };

  const check = (label, lines) => {
    const summaries = lines.filter((line) => line.includes('●')).length;
    const native = lines.filter((line) => /^\s*Thinking\.\.\.\s*$/.test(line)).length;
    console.log(`${label}: ● 汇总行 ${summaries} | 原生 Thinking... ${native}`);
    return { summaries, native };
  };

  await emit('session_start');
  const first = check('首个会话', await runTurn());
  assert.equal(first.summaries, 1, '首个会话应有 1 行汇总');
  assert.equal(first.native, 0, '首个会话不应有原生 Thinking...');

  // 模拟 /new 或 /resume：shutdown → start，扩展模块不重新执行
  await emit('session_shutdown');
  await emit('session_start');
  const second = check('切换会话后', await runTurn());
  assert.equal(second.summaries, 1, '切换会话后汇总行丢失(补丁被 session_shutdown 摘掉却没重装)');
  assert.equal(second.native, 0, '切换会话后出现原生 Thinking... 行');
  console.log('PASS: 会话切换后 clean 渲染仍然有效');
} finally {
  if (pretty && ctx) for (const fn of pretty.handlers.get('session_shutdown') ?? []) await fn({ type: 'session_shutdown' }, ctx);
  rmSync(agent, { recursive: true, force: true });
}
