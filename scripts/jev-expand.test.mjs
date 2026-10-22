import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";
import { fwcoreBin, fwcoreCall } from "../packages/gh-budget/src/core.ts";
import { blobAt, datasets, droppedIds, expandOne, pinOf, recordOf, withFiles } from "./jev-expand.mjs";

const golden = readFileSync(new URL("../packages/contracts/golden/oracle/expand.jsonl", import.meta.url), "utf8")
  .split("\n").filter(Boolean).map((l) => JSON.parse(l));

let core = null;
try { core = existsSync(fwcoreBin(process.cwd())) ? fwcoreCall(process.cwd()) : null; } catch { core = null; }

for (const c of golden) {
  test(`golden: ${c.name}`, { skip: core ? false : "fwcore not built" }, () => {
    assert.deepEqual(core(c.request), c.response);
  });
}

test("the golden covers every op of the module", () => {
  assert.deepEqual([...new Set(golden.map((c) => c.request.op))].sort(),
    ["oracle.adopt", "oracle.expand", "oracle.expandPaths", "oracle.paired"]);
});

function fakeGit(objects, revs = {}) {
  return (args) => {
    const [cmd, ...rest] = args;
    if (cmd === "rev-parse") { const k = rest.at(-1); return objects[k] ? Buffer.from(`id-${k}\n`) : null; }
    const id = rest.at(-1);
    const k = id.replace(/^id-/, "");
    if (cmd === "cat-file" && rest[0] === "-t") return objects[k] ? Buffer.from("blob\n") : null;
    if (cmd === "cat-file" && rest[0] === "-s") return Buffer.from(String(objects[k].length));
    if (cmd === "cat-file" && rest[0] === "blob") return objects[k];
    if (cmd === "rev-list") return revs[rest[1]] ? Buffer.from(`${revs[rest[1]]}\n`) : Buffer.from("");
    return null;
  };
}

test("blobAt: text, binary, missing", () => {
  const git = fakeGit({ "s:a.mjs": Buffer.from("x\n"), "s:b.bin": Buffer.from([1, 0, 2]) });
  assert.deepEqual(blobAt(git, "s", "a.mjs"), { id: "id-s:a.mjs", text: "x\n" });
  assert.deepEqual(blobAt(git, "s", "b.bin"), { id: "id-s:b.bin", text: null });
  assert.deepEqual(blobAt(git, "s", "c.mjs"), { id: null, text: null });
});

test("pinOf: the commit rev-list gives, or null", () => {
  const git = fakeGit({}, { "--before=2026-10-01T00:00Z": "abc" });
  assert.equal(pinOf(git, "src", "2026-10-01T00:00Z"), "abc");
  assert.equal(pinOf(git, "src", "2026-09-01T00:00Z"), null);
});

test("withFiles: only an expanded result adds the files field", () => {
  const row = { id: "r", title: "t" };
  assert.deepEqual(withFiles(row, { result: "expanded", filesText: "file: a\nx" }), { ...row, files: "file: a\nx" });
  assert.deepEqual(withFiles(row, { result: "refused", esc: 9 }), row);
  assert.deepEqual(withFiles(row, { result: "same" }), row);
});

test("datasets: the naive set changes only the rows the safe set expanded", () => {
  const rows = [{ id: "a" }, { id: "b" }, { id: "c" }];
  const results = [
    { id: "a", safe: { result: "expanded", filesText: "A", files: [] }, naive: { result: "expanded", filesText: "NA", files: [] } },
    { id: "b", safe: { result: "same", files: [] }, naive: { result: "expanded", filesText: "NB", files: [] } },
    { id: "c", safe: { result: "expanded", filesText: "C", files: [{ verdict: "vocab" }] }, naive: { result: "refused", files: [] } }];
  const d = datasets(rows, results);
  assert.deepEqual(d.expand, [{ id: "a", files: "A" }, { id: "b" }, { id: "c", files: "C" }]);
  assert.deepEqual(d.naive, [{ id: "a", files: "NA" }, { id: "b" }, { id: "c" }]);
  assert.deepEqual(d.ids, ["a", "c"]);
  assert.deepEqual(droppedIds(results), ["c"]);
});

test("expandOne: safe reads at the pin, naive at the source commit; the record holds no text", () => {
  const calls = [];
  const fake = (req) => {
    calls.push(req);
    if (req.op === "oracle.expandPaths") return { paths: [{ path: "scripts/a.mjs", allowed: true }] };
    return { result: "expanded", esc: 1, filesText: `file: scripts/a.mjs\n${req.blobs["scripts/a.mjs"]}`,
      files: [{ path: "scripts/a.mjs", verdict: "kept", bytes: 1, esc: 1 }] };
  };
  const git = fakeGit({ "pin:scripts/a.mjs": Buffer.from("old"), "src:scripts/a.mjs": Buffer.from("new") }, { "--before=t": "pin" });
  const x = expandOne(fake, git, "src", "t", { id: "r", label: "c-quota", title: "t", symptom: "s", cause: "scripts/a.mjs" });
  assert.equal(x.safe.filesText, "file: scripts/a.mjs\nold");
  assert.equal(x.naive.filesText, "file: scripts/a.mjs\nnew");
  assert.deepEqual(calls.filter((c) => c.op === "oracle.expand").map((c) => [c.cfg, c.rowId]), [["safe", "r"], ["naive", "r"]]);
  const rec = recordOf(x);
  assert.equal(JSON.stringify(rec).includes("old"), false);
  assert.deepEqual(rec.safe.files, [{ path: "scripts/a.mjs", verdict: "kept", bytes: 1, esc: 1, blob: "id-pin:scripts/a.mjs" }]);
  const none = expandOne(fake, git, "src", undefined, { id: "q", label: "c-quota", title: "", symptom: "", cause: "" });
  assert.deepEqual([none.safe.result, none.naive.result], ["same", "same"]);
});
