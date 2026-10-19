// The browser-free half of the WebKit cancelled-preload signature, the attribution and the start() counter: pure functions of
// the suite and the rig's tap, exercised on both sides of every branch (accepts the exact signature, refuses each deviation).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { instrumentModule, SNAPSHOT } from "../src/rig.mjs";
import { attribution, cancelSignature, CANCEL_SIGNATURE } from "../src/suite.mjs";
import { join } from "node:path";

const host = { origin: "http://127.0.0.1:9" };
const rej = ["Unhandled Promise Rejection: TypeError: Importing a module script failed.", "Unhandled Promise Rejection: Error: Unable to preload CSS for x", "Unhandled Promise Rejection: TypeError: Importing a module script failed."];
const paths = Array.from({ length: CANCEL_SIGNATURE.cancelled }, (_, i) => `/_app/immutable/chunks/m${i}.js`);
const failed = paths.map((p, i) => `GET ${i === 0 ? `/preview/e2e/o${p}` : p} Load request cancelled`);
const seen = paths.map((p) => ({ host: "127.0.0.1:9", path: p, status: 302 }));

describe("cancelSignature", () => {
  it("accepts exactly 3 preload rejections and 13 cancelled /_app/ requests that each had a root 302", () => {
    assert.equal(cancelSignature(rej, failed, seen, host).ok, true);
  });
  it("refuses another rejection count, a non-preload error, another cancel count, a non-/_app/ cancel, a cancel without a root 302", () => {
    assert.equal(cancelSignature(rej.slice(0, 2), failed, seen, host).ok, false);
    assert.equal(cancelSignature([...rej.slice(0, 2), "TypeError: x is not a function"], failed, seen, host).ok, false);
    assert.equal(cancelSignature(rej, failed.slice(1), seen, host).ok, false);
    assert.equal(cancelSignature(rej, [...failed.slice(1), "GET /api/x Load request cancelled"], seen, host).ok, false);
    assert.equal(cancelSignature(rej, failed, seen.slice(1), host).ok, false);
    assert.equal(cancelSignature(rej, failed, seen.map((r, i) => (i === 3 ? { ...r, status: 200 } : r)), host).ok, false);
    assert.equal(cancelSignature(rej, failed, seen.map((r) => ({ ...r, host: "other:1" })), host).ok, false);
  });
  it("refuses errors with no cancelled request (a real module failure is not noise)", () => {
    assert.equal(cancelSignature(rej, [], seen, host).ok, false);
  });
});

describe("attribution", () => {
  const arm = (a, r, c) => [1, 2, 3].map(() => ({ arm: a, ok: true, rejections: r, cancelled: c }));
  it("names the arm that shows the signature", () => {
    assert.match(attribution([...arm("raw", 0, 0), ...arm("tap-only", 3, 13), ...arm("proxy-only", 0, 0)], true).cause, /the tap/);
    assert.match(attribution([...arm("raw", 0, 0), ...arm("tap-only", 0, 0), ...arm("proxy-only", 3, 13)], true).cause, /proxy path/);
    assert.match(attribution([...arm("raw", 3, 13), ...arm("tap-only", 3, 13), ...arm("proxy-only", 3, 13)], true).cause, /engine/);
    assert.match(attribution([...arm("raw", 0, 0), ...arm("tap-only", 0, 0), ...arm("proxy-only", 0, 0)], true).cause, /combination/);
    assert.match(attribution([...arm("raw", 0, 0)], false).cause, /no signature/);
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
  it("false hands the proxy the raw preview ports (no counter in a module), true restores the tap", async () => {
    const { startRig, PREVIEW_ID } = await import("../src/rig.mjs");
    const rig = await startRig();
    try {
      const get = async () => {
        const link = await rig.grantUrl(rig.hosts.loopback.origin, "r");
        const cookie = ((await fetch(link, { redirect: "manual" })).headers.get("set-cookie") ?? "").split(";")[0];
        return await (await fetch(`${rig.hosts.loopback.origin}/preview/${PREVIEW_ID}/r/_app/immutable/entry/start.fix1.js`, { headers: { cookie } })).text();
      };
      assert.match(await get(), /__fwEvals/);
      rig.useTap(false);
      assert.doesNotMatch(await get(), /__fwEvals/);
      rig.useTap(true);
      assert.match(await get(), /__fwEvals/);
    } finally { await rig.close(); }
  });
});
