import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";

// The reports of the Reviews tab (Lean Fw.Console.Report through `console.report`). Everything is posted into a temporary console
// directory; the live log is never touched.
const EXAMPLE = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../../../results/review-reports/example.json"), "utf8"));
const ID = EXAMPLE.id as string;

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

async function rig() {
  const root = mkdtempSync(join(tmpdir(), "fw-report-"));
  const store = await Store.open(join(root, ".fw-console"), selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  return { store, app: createApp(store, undefined, undefined, undefined, undefined, undefined, undefined, root) };
}
type App = Awaited<ReturnType<typeof rig>>["app"];
const json = { "content-type": "application/json" };
const post = (app: App, report: unknown) => app.request("/api/reports", { method: "POST", headers: json, body: JSON.stringify({ report }) });
const answer = (app: App, word: string, comment?: string, id = ID) =>
  app.request(`/api/reports/${id}/answer`, { method: "POST", headers: json, body: JSON.stringify({ word, ...(comment === undefined ? {} : { comment }) }) });
const list = async (app: App) => (await (await app.request("/api/reports")).json()) as any;
const withCell = (tag: unknown) => {
  const r = structuredClone(EXAMPLE);
  const cell = r.lanes[0].rows[0].cells[0];
  if (tag === undefined) delete cell.tag; else cell.tag = tag;
  return r;
};

describe("reports (Lean Fw.Console.Report)", () => {
  it("the example report is shown with its arms, metric rows and an open step", async () => {
    const { app, store } = await rig();
    expect(await (await post(app, EXAMPLE)).json()).toMatchObject({ ok: true, id: ID, duplicate: false });
    const l = await list(app);
    expect(l.open).toBe(1);
    expect(l.invalid).toEqual([]);
    expect(l.options).toEqual(["approve", "hold", "reject"]);
    expect(l.items[0]).toMatchObject({ id: ID, step: `report-${ID}`, state: "open", feedback: { flag: `report:${ID}`, open: 0 } });
    expect(l.items[0].report.arms.map((a: any) => a.name)).toEqual(["original", "rewrite"]);
    expect(l.items[0].report.lanes[0].rows.length).toBeGreaterThanOrEqual(5);
    const step = (await store.board()).steps.find((s) => s.id === `report-${ID}`);
    expect(step).toMatchObject({ status: "waiting", kind: "choice", audience: "user" });
  });

  it("a number without a tag is refused with its place, and nothing is posted", async () => {
    const { app, store } = await rig();
    const res = await post(app, withCell(undefined));
    expect(res.status).toBe(422);
    const b = (await res.json()) as any;
    expect(b.reason).toContain("frame interval p50");
    expect(b.reason).toContain("no MEASURED run id or INFERRED tag");
    expect((await store.board()).steps.some((s) => s.id.startsWith("report-"))).toBe(false);
    expect((await list(app)).items).toEqual([]);
  });

  it("MEASURED without a run id, a run that is not digits, INFERRED without a reason and a tag of another kind are refused", async () => {
    const { app } = await rig();
    for (const [tag, why] of [
      [{ kind: "measured", run: "" }, "MEASURED needs a CI run id"],
      [{ kind: "measured", run: "local-run" }, "MEASURED needs a CI run id"],
      [{ kind: "inferred", why: " " }, "INFERRED needs its reason"],
      [{ kind: "guessed" }, "measured or inferred"],
    ] as const) {
      const res = await post(app, withCell(tag));
      expect(res.status).toBe(422);
      expect(((await res.json()) as any).reason).toContain(why);
    }
  });

  it("a value that is no number is refused", async () => {
    const { app } = await rig();
    const r = structuredClone(EXAMPLE);
    r.lanes[0].rows[0].cells[0].value = "fast";
    const res = await post(app, r);
    expect(res.status).toBe(422);
    expect(((await res.json()) as any).reason).toContain("not a number");
  });

  it("posting the same report again is a duplicate; another report under the same id is refused", async () => {
    const { app } = await rig();
    await post(app, EXAMPLE);
    expect(await (await post(app, EXAMPLE)).json()).toMatchObject({ ok: true, duplicate: true });
    const changed = structuredClone(EXAMPLE);
    changed.title = "A different report";
    const res = await post(app, changed);
    expect(res.status).toBe(409);
    expect((await list(app)).items).toHaveLength(1);
  });

  it("approve with a comment records the step answer and an open review.feedback on report:<id>", async () => {
    const { app, store } = await rig();
    await post(app, EXAMPLE);
    const res = await answer(app, "approve", "please also check the phone");
    expect(await res.json()).toMatchObject({ ok: true, word: "approve" });
    const l = await list(app);
    expect(l.open).toBe(0);
    expect(l.items[0].state).toBe("approve");
    expect(l.items[0].feedback).toMatchObject({ flag: `report:${ID}`, open: 1 });
    expect(l.items[0].feedback.comments[0]).toMatchObject({ text: "please also check the phone", status: "open" });
    const ev = (await store.readEvents()).filter((e) => e.type === "review.feedback");
    expect(ev).toHaveLength(1);
    expect(ev[0]).toMatchObject({ actor: "user", flag: `report:${ID}` });
  });

  it("hold and reject are answers too; no comment writes no feedback", async () => {
    for (const word of ["hold", "reject"]) {
      const { app, store } = await rig();
      await post(app, EXAMPLE);
      expect(await (await answer(app, word)).json()).toMatchObject({ ok: true, word });
      expect((await list(app)).items[0].state).toBe(word);
      expect((await store.readEvents()).filter((e) => e.type === "review.feedback")).toHaveLength(0);
    }
  });

  it("an answered report refuses a second answer; a word outside approve, hold, reject is refused; a missing report is refused", async () => {
    const { app } = await rig();
    await post(app, EXAMPLE);
    const bad = await answer(app, "keep");
    expect(bad.status).toBe(422);
    expect(((await bad.json()) as any).reason).toContain("approve, hold or reject");
    await answer(app, "hold");
    const again = await answer(app, "approve", "x");
    expect(again.status).toBe(422);
    expect(((await again.json()) as any).reason).toContain("already answered");
    expect((await answer(app, "approve", "", "nope")).status).toBe(422);
    expect((await list(app)).items[0].state).toBe("hold");
  });

  it("a comment over the feedback cap refuses the whole answer, so no answer is recorded without its comment", async () => {
    const { app } = await rig();
    await post(app, EXAMPLE);
    const res = await answer(app, "approve", "x".repeat(2001));
    expect(res.status).toBe(422);
    expect((await list(app)).items[0].state).toBe("open");
  });
});
