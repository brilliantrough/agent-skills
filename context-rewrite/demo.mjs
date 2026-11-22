import assert from "node:assert/strict";
import { indexOperations, makeRecord } from "./core.mjs";

const ops = [
  { key: "a1", tool: "bash", text: "A1", finished: true },
  { key: "a2", tool: "read", text: "A2", finished: true },
  { key: "b1", tool: "read", text: "B1", finished: true },
  { key: "c1", tool: "bash", text: "C1", finished: true },
];
const index = indexOperations(ops, []);
const visible = new Map(index.operations.map((op) => [op.id, op.key]));
const one = makeRecord(index, visible, [2], "already read", 20);
assert.equal(one.version, 1);
assert.equal(one.targets.length, 1);
assert.equal(one.targets[0].id, 2);
assert.deepEqual([...indexOperations(ops, [one]).removed].sort(), ["a2"]);
assert.throws(() => makeRecord(index, visible, [99], "bad", 20), /不在最近/);
const used = indexOperations(ops, [one]);
assert.throws(() => makeRecord(used, visible, [2], "repeat", 20), /不在最近/);

const all = makeRecord(index, visible, [1, 2, 3], "clear", 20);
assert.equal(all.targets.length, 3);
assert.deepEqual([...indexOperations(ops, [all]).removed].sort(), ["a1", "a2", "b1"]);
const single = makeRecord(index, new Map([[1, "a1"]]), [1], "single", 20);
assert.equal(single.targets[0].toolCallId, "a1");
console.log("PASS: context_rewrite 核心索引、批量撤下与重复拒绝");
