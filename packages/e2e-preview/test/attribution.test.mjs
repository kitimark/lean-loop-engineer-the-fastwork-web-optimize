// The browser-free half of the strict attribution and the start() counter: pure functions of the suite and the rig's tap,
// exercised on both sides of every branch. (There is no accepted noise: any rejection or cancelled request in a control fails.)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { join } from "node:path";
import { instrumentModule, SNAPSHOT, startRig, PREVIEW_ID } from "../src/rig.mjs";
import { attribution } from "../src/suite.mjs";

describe("attribution (strict)", () => {
  const arm = (a, r, c, ok = true) => [1, 2, 3].map(() => ({ arm: a, ok, rejections: r, cancelled: c }));
  const clean = [...arm("raw", 0, 0), ...arm("tap-only", 0, 0), ...arm("arm-only", 0, 0)];
  it("passes only when every control load of every arm is clean", () => {
    assert.deepEqual(attribution(clean), { shown: [], ok: true });
  });
  it("names an arm that shows a rejection or a cancelled request, and fails", () => {
    assert.deepEqual(attribution([...arm("raw", 0, 0), ...arm("tap-only", 0, 0), ...arm("arm-only", 3, 13)]), { shown: ["arm-only"], ok: false });
    assert.deepEqual(attribution([...arm("raw", 1, 0), ...arm("tap-only", 0, 0), ...arm("arm-only", 0, 0)]), { shown: ["raw"], ok: false });
    assert.deepEqual(attribution([...arm("raw", 0, 0), ...arm("tap-only", 0, 2), ...arm("arm-only", 0, 0)]), { shown: ["tap-only"], ok: false });
  });
  it("a load that did not complete fails, and so does a missing arm", () => {
    assert.equal(attribution([...arm("raw", -1, -1, false), ...arm("tap-only", 0, 0), ...arm("arm-only", 0, 0)]).ok, false);
    assert.equal(attribution(clean.filter((c) => c.arm !== "arm-only")).ok, false);
  });
});

describe("the tap's start() counter", () => {
  it("is added to SvelteKit's client start and nowhere else", () => {
    const chunk = readFileSync(join(SNAPSHOT, "_app/immutable/chunks/CzkAa0og.js"), "utf8");
    const out = instrumentModule(chunk);
    assert.match(out, /^\(globalThis\.__fwEvals/);
    assert.match(out, /async function \w+\(\w+,\w+,\w+\)\{\(globalThis\.__fwStarts=\(globalThis\.__fwStarts\|\|0\)\+1\);if\(globalThis\.__sveltekit_\w+\.data\)/);
    assert.equal(out.split("__fwStarts=").length - 1, 1);
    assert.doesNotMatch(instrumentModule("export const a = 1;"), /__fwStarts/);
  });
});

describe("rig.useTap", () => {
  it("false makes the evaluation counter a pass-through (no counter in a module), true restores it", async () => {
    const rig = await startRig();
    try {
      const link = await rig.grantUrl(rig.hosts.loopback.origin, "r");
      const cookie = ((await fetch(link, { redirect: "manual" })).headers.get("set-cookie") ?? "").split(";")[0];
      const get = async () => await (await fetch(`${rig.hosts.loopback.arm.r}/_app/immutable/entry/start.fix1.js`, { headers: { cookie } })).text();
      assert.match(await get(), /__fwEvals/);
      rig.useTap(false);
      assert.doesNotMatch(await get(), /__fwEvals/);
      rig.useTap(true);
      assert.match(await get(), /__fwEvals/);
      assert.ok(PREVIEW_ID);
    } finally { await rig.close(); }
  });
});
