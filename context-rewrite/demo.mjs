// 运行：node context-rewrite/demo.mjs（先在本目录 npm ci --ignore-scripts）。
import assert from "node:assert/strict";
import { indexOperations, makeRecord, isRecord, artifact } from "./core.mjs";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createOutputStore } from "./output-store.mjs";

const raw = Array.from({ length: 12 }, (_, i) => ({ key: "call-" + i, tool: "read", finished: true, text: "raw output " + i }));
const original = structuredClone(raw);
const first = indexOperations(raw, []);
const visible = new Map(first.operations.map((op) => [op.id, op.key]));
assert.throws(() => makeRecord(first, visible, [2], "过旧", 10));
assert.throws(() => makeRecord(first, visible, [12], " ", 10));
assert.throws(() => makeRecord(first, new Map(), [12], "未展示", 10));
assert.throws(() => makeRecord(first, visible, [12, 999], "整批应失败", 10));
assert.equal(first.state.absorbed.length, 0);
const record = makeRecord(first, visible, [11, 12, 12], "改用定向读取", 10);
assert.equal(record.targets.length, 2);
assert.ok(isRecord(record));
const restored = indexOperations(raw, structuredClone([record]));
assert.deepEqual([...restored.removed], ["call-10", "call-11"]);
assert.equal(restored.byKey.get("call-9").id, 10);
assert.throws(() => makeRecord(restored, visible, [12], "已处理", 10));
assert.throws(() => makeRecord(restored, visible, [2], "窗口不后移", 10));
assert.equal(indexOperations(raw, []).removed.size, 0); // 回到记录之前的分支。
assert.deepEqual(raw, original);
assert.ok(artifact(record).includes("改用定向读取"));
assert.ok(!artifact(record, false).includes("改用定向读取"));
const directory = await mkdtemp(join(tmpdir(), "context-output-demo-"));
try {
  const store = createOutputStore({ directory, bytes: 16384 });
  const source = "源码🙂\r\n".repeat(12000);
  const saved = await store.capture([source], { tool: "read" });
  assert.equal(await readFile(saved.path, "utf8"), source);
  assert.equal((await store.capture([source], { tool: "read" })).id, saved.id);
  assert.equal((await readdir(directory)).length, 1);
  assert.equal(await store.capture(["短输出"], { tool: "bash" }), undefined);
  assert.equal(await store.capture([source], { tool: "context_output_read" }), undefined);
  assert.equal(await store.capture([source], { tool: "ctx_expand" }), undefined);
  const body = (text) => text.slice(text.indexOf("\n", text.indexOf("\n") + 1) + 1);
  const reopened = createOutputStore({ directory, bytes: 16384 });
  assert.equal(body(await reopened.retrieve({ id: saved.id, full: true })), source);
  let offset = 0, combined = "";
  do {
    const page = await reopened.retrieve({ id: saved.id, offset });
    combined += body(page);
    offset = Number(page.match(/next_offset=(\d+)/)[1]);
  } while (offset < saved.bytes);
  assert.equal(combined, source);
  await assert.rejects(() => reopened.retrieve({ id: "../../outside", full: true }));
  await assert.rejects(() => reopened.retrieve({ id: saved.id, offset: 1 }));
} finally { await rm(directory, { recursive: true, force: true }); }
console.log("通过：近期纠错；外置阈值、去重、完整取回、UTF-8 分页、重开、路径边界。");
