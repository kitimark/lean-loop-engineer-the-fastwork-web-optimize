import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { plan } from "./slot-self.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const top = join(here, "..");
const helper = join(here, "slot-self.mjs");

test("plan: bare call routes through slot run with its kind, in this process", () => {
  const p = plan({}, ["test", "--", "pnpm", "run", "test:run"]);
  assert.equal(p.routed, true);
  assert.deepEqual(p.slot, ["run", "--kind", "test", "--", "pnpm", "run", "test:run"]);
  assert.equal(p.argv, undefined);
});

test("plan: nested (FW_SLOT_HELD), CI and FW_SLOT_SELF=off run the command directly", () => {
  for (const env of [{ FW_SLOT_HELD: "1" }, { CI: "true" }, { FW_SLOT_SELF: "off" }]) {
    assert.deepEqual(plan(env, ["check", "--", "sh", "x"]), { argv: ["sh", "x"], routed: false });
  }
});

test("plan: bad usage is an error", () => {
  for (const a of [[], ["test"], ["lint", "--", "x"], ["test", "--"]]) assert.ok(plan({}, a).error);
});

test("nested call starts at once and runs the command (no deadlock)", () => {
  const env = { ...process.env, FW_SLOT_HELD: "1" };
  delete env.CI;
  const r = spawnSync(process.execPath, [helper, "test", "--", process.execPath, "-e", "console.log('ran', process.env.FW_SLOT_HELD); process.exit(4)"],
    { env, encoding: "utf8" });
  assert.equal(r.status, 4);
  assert.match(r.stdout, /ran 1/);
});

test("bare call queues: it goes through the slot (state written, child sees FW_SLOT_HELD)", () => {
  const dir = mkdtempSync(join(tmpdir(), "slot-self-"));
  const env = { ...process.env, FW_SLOT_DIR: dir, FW_LOCK_EVENTS: "off", FW_SLOT_OWNER: "slot-self-test" };
  delete env.FW_SLOT_HELD; delete env.CI; delete env.FW_SLOT_SELF;
  const r = spawnSync(process.execPath, [helper, "test", "--", process.execPath, "-e", "console.log('held', process.env.FW_SLOT_HELD, process.env.FW_SLOT_OWNER)"],
    { env, encoding: "utf8", cwd: top });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /held 1 slot-self-test/);
  assert.ok(readdirSync(dir).length > 0, "slot state written");
});

test("waiter: one node process, no second fw process, starts only after the holder releases", async () => {
  const dir = mkdtempSync(join(tmpdir(), "slot-wait-"));
  const env = { ...process.env, FW_SLOT_DIR: dir, FW_LOCK_EVENTS: "off", FW_SLOT_OWNER: "wait-test" };
  delete env.FW_SLOT_HELD; delete env.CI; delete env.FW_SLOT_SELF;
  const fw = join(top, "apps", "runner", "src", "fw-entry.ts");
  const held = spawnSync(process.execPath, [fw, "slot", "acquire", "--kind", "test", "--lease", "120"], { env: { ...env, FW_SLOT_OWNER: "holder" }, encoding: "utf8", cwd: top });
  assert.equal(held.status, 0, held.stderr);
  const token = held.stdout.trim();
  const w = spawn(process.execPath, [helper, "test", "--", process.execPath, "-e", "console.log('started')"], { env, cwd: top });
  let out = "", err = "";
  w.stdout.on("data", (b) => { out += b; });
  w.stderr.on("data", (b) => { err += b; });
  const exited = new Promise((res) => w.on("close", res));
  try {
    await new Promise((r) => setTimeout(r, 3000));
    assert.equal(out, "", "the command must not start while the slot is held");
    assert.match(err, /slot test: waiting/);
    const kids = spawnSync("pgrep", ["-P", String(w.pid)], { encoding: "utf8" }).stdout.trim();
    assert.equal(kids, "", "the waiting process has no child process");
  } finally {
    spawnSync(process.execPath, [fw, "slot", "release", "--token", token], { env: { ...env, FW_SLOT_OWNER: "holder" }, cwd: top });
  }
  assert.equal(await exited, 0);
  assert.match(out, /started/);
});

test("fw-entry slot: usage error exits 64 with the usage text, like fw.ts", () => {
  const fw = join(top, "apps", "runner", "src", "fw-entry.ts");
  const r = spawnSync(process.execPath, [fw, "slot", "run", "--kind", "test"], { encoding: "utf8", cwd: top, env: { ...process.env, FW_LOCK_EVENTS: "off" } });
  assert.equal(r.status, 64);
  assert.match(r.stderr, /usage: fw slot run/);
});
