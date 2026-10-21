// node --test scripts/slot-self.test.mjs (task heavy-self-route): nested starts at once, bare queues, CI runs directly.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { plan } from "./slot-self.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const top = join(here, "..");
const helper = join(here, "slot-self.mjs");
const FW = "/x/fw.ts";

test("plan: bare call routes through fw slot run with its kind", () => {
  const p = plan({}, ["test", "--", "pnpm", "run", "test:run"], FW);
  assert.equal(p.routed, true);
  assert.deepEqual(p.argv.slice(1), [FW, "slot", "run", "--kind", "test", "--", "pnpm", "run", "test:run"]);
});

test("plan: nested (FW_SLOT_HELD), CI and FW_SLOT_SELF=off run the command directly", () => {
  for (const env of [{ FW_SLOT_HELD: "1" }, { CI: "true" }, { FW_SLOT_SELF: "off" }]) {
    assert.deepEqual(plan(env, ["check", "--", "sh", "x"], FW), { argv: ["sh", "x"], routed: false });
  }
});

test("plan: bad usage is an error", () => {
  for (const a of [[], ["test"], ["lint", "--", "x"], ["test", "--"]]) assert.ok(plan({}, a, FW).error);
});

test("nested call starts at once and runs the command (no deadlock)", () => {
  const env = { ...process.env, FW_SLOT_HELD: "1" };
  delete env.CI;
  const r = spawnSync(process.execPath, [helper, "test", "--", process.execPath, "-e", "console.log('ran', process.env.FW_SLOT_HELD); process.exit(4)"],
    { env, encoding: "utf8", timeout: 20000 });
  assert.equal(r.status, 4);
  assert.match(r.stdout, /ran 1/);
});

test("bare call queues: it goes through the slot (state written, child sees FW_SLOT_HELD)", () => {
  const dir = mkdtempSync(join(tmpdir(), "slot-self-"));
  const env = { ...process.env, FW_SLOT_DIR: dir, FW_LOCK_EVENTS: "off", FW_SLOT_OWNER: "slot-self-test" };
  delete env.FW_SLOT_HELD; delete env.CI; delete env.FW_SLOT_SELF;
  const r = spawnSync(process.execPath, [helper, "test", "--", process.execPath, "-e", "console.log('held', process.env.FW_SLOT_HELD, process.env.FW_SLOT_OWNER)"],
    { env, encoding: "utf8", timeout: 60000, cwd: top });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /held 1 slot-self-test/);
  assert.ok(readdirSync(dir).length > 0, "slot state written");
});
