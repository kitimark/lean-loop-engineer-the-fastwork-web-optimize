// The part of the preview e2e suite that needs no browser: the detector of double module evaluation, and the rig itself over
// plain HTTP (grant, gate, the script redirect on a request without Sec-Fetch-Dest). The browser half is src/run.mjs, run by the
// preview-e2e lane (.github/workflows/preview-e2e.yml) on Chromium and WebKit.
import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { PREVIEW_ID, startRig } from "../src/rig.mjs";
import { evalReport, PATHS } from "../src/suite.mjs";

describe("evalReport", () => {
  it("a module evaluated once per file is clean", () => {
    const r = evalReport(["http://h/preview/x/o/_app/immutable/entry/start.A.js", "http://h/preview/x/o/_app/immutable/chunks/b.js"]);
    assert.deepEqual(r, { total: 2, files: 2, duplicates: [] });
  });
  it("the same file under the root URL and under the preview prefix is two instances (the failure the suite looks for)", () => {
    const r = evalReport(["http://h/_app/immutable/entry/start.A.js", "http://h/preview/x/o/_app/immutable/entry/start.A.js"]);
    assert.equal(r.total, 2);
    assert.equal(r.files, 1);
    assert.equal(r.duplicates.length, 1);
    assert.match(r.duplicates[0], /start\.A\.js x2/);
  });
});

describe("the suite covers /r, /o and /compare", () => {
  it("paths", () => assert.deepEqual(PATHS.map((p) => p.id), ["r", "o", "compare"]));
});

describe("rig over plain HTTP", () => {
  let rig;
  before(async () => { rig = await startRig(); });
  after(async () => { await rig?.close(); });

  it("a preview path without a grant is refused", async () => {
    const r = await fetch(`${rig.hosts.loopback.origin}/preview/${PREVIEW_ID}/o/`, { headers: { accept: "text/html" } });
    assert.equal(r.status, 401);
  });

  it("a grant link opens the original and the rewrite; a root-absolute module request is moved below the preview", async () => {
    const link = await rig.grantUrl(rig.hosts.loopback.origin, "o");
    const red = await fetch(link, { redirect: "manual" });
    assert.equal(red.status, 302);
    const cookie = (red.headers.get("set-cookie") ?? "").split(";")[0];
    assert.match(cookie, /^fw_grant=/);
    const get = (path, headers = {}) => fetch(`${rig.hosts.loopback.origin}${path}`, { redirect: "manual", headers: { cookie, ...headers } });
    for (const arm of ["o", "r"]) {
      const doc = await get(`/preview/${PREVIEW_ID}/${arm}/`);
      assert.equal(doc.status, 200, arm);
      assert.match(await doc.text(), new RegExp(`/preview/${PREVIEW_ID}/${arm}/_app/`));
    }
    assert.equal((await get(`/preview/${PREVIEW_ID}/compare`)).status, 200);
    // the phone case: no Sec-Fetch-Dest, the Referer names the preview page
    const mod = await get("/_app/immutable/entry/start.fix1.js", { referer: `${rig.hosts.loopback.origin}/preview/${PREVIEW_ID}/r/` });
    assert.equal(mod.status, 302);
    assert.equal(mod.headers.get("location"), `/preview/${PREVIEW_ID}/r/_app/immutable/entry/start.fix1.js`);
    const moved = await get(mod.headers.get("location"));
    assert.equal(moved.status, 200);
    assert.match(await moved.text(), /__fwEvals/); // the evaluation counter is in front of every module
  });

  it("a grant link is single use", async () => {
    const link = await rig.grantUrl(rig.hosts.loopback.origin, "r");
    assert.equal((await fetch(link, { redirect: "manual" })).status, 302);
    assert.equal((await fetch(link, { redirect: "manual" })).status, 403);
  });
});
