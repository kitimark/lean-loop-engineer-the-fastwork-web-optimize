// The lock: exclusive, dead holders are taken over, no lost updates across processes.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { lockSync, tryLock } from "../src/lock.ts";

const here = dirname(fileURLToPath(import.meta.url));
const lockSrc = join(here, "..", "src", "lock.ts");

test("exclusive, released, re-acquirable", () => {
  const p = join(mkdtempSync(join(tmpdir(), "ghb-lock-")), "l");
  const a = tryLock(p);
  assert.ok(a);
  assert.equal(tryLock(p), null);
  a.release();
  const b = tryLock(p);
  assert.ok(b);
  a.release(); // releasing a stale handle must not drop b's lock
  assert.equal(tryLock(p), null);
  b.release();
  assert.ok(tryLock(p));
});

test("a lock whose holder was killed is taken over", () => {
  const d = mkdtempSync(join(tmpdir(), "ghb-lock-"));
  const p = join(d, "l");
  const child = spawnSync(process.execPath, ["-e", `import(${JSON.stringify(lockSrc)}).then(m => { if (!m.tryLock(${JSON.stringify(p)})) process.exit(2); console.log(process.pid); process.kill(process.pid, "SIGKILL"); })`], { encoding: "utf8" });
  assert.equal(child.signal, "SIGKILL");
  assert.ok(existsSync(p), "the dead holder left its lock");
  assert.ok(tryLock(p), "taken over");
});

test("8 processes increment one counter under the lock: no lost update", async () => {
  const d = mkdtempSync(join(tmpdir(), "ghb-lock-"));
  const p = join(d, "l");
  const counter = join(d, "n");
  writeFileSync(counter, "0");
  const code = `import(${JSON.stringify(lockSrc)}).then(m => { const fs = require("node:fs");
    for (let i = 0; i < 10; i++) { const l = m.lockSync(${JSON.stringify(p)}, 60000); const n = Number(fs.readFileSync(${JSON.stringify(counter)}, "utf8")); fs.writeFileSync(${JSON.stringify(counter)}, String(n + 1)); l.release(); } })`;
  const kids = Array.from({ length: 8 }, () => new Promise<number | null>((res) => spawn(process.execPath, ["-e", code], { stdio: "inherit" }).on("close", res)));
  assert.deepEqual(await Promise.all(kids), Array(8).fill(0));
  assert.equal(readFileSync(counter, "utf8"), "80");
});

test("lockSync gives up with an error when a live process holds the lock", () => {
  const p = join(mkdtempSync(join(tmpdir(), "ghb-lock-")), "l");
  tryLock(p);
  assert.throws(() => lockSync(p, 100), /held by a live process/);
});
