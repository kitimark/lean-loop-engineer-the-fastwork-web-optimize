import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { OwnerAuth } from "../src/preview/owner.ts";
import { LoginGuard } from "../src/preview/login.ts";
import { fileLines, readExcerpt, type ExcerptSpec, type Ops } from "../src/review/info.ts";

const ROOT = join(import.meta.dirname, "../../..");
const FLAG = "nav:earn-no-transition";
const url = (f: string) => `/api/reviews/${encodeURIComponent(f)}/info`;
const LAN = { incoming: { socket: { remoteAddress: "198.51.100.50" } } };
let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

async function rig(root = ROOT) {
  const dir = join(mkdtempSync(join(tmpdir(), "fw-info-")), ".fw-console");
  const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  const app = createApp(store, undefined, undefined, undefined, undefined, undefined, undefined, root);
  return { app, store };
}
async function info(): Promise<any> {
  const { app } = await rig();
  const r = await app.request(url(FLAG));
  expect(r.status).toBe(200);
  return r.json();
}
const jsonl = (p: string) => readFileSync(join(ROOT, p), "utf8").trim().split("\n").map((l) => JSON.parse(l));
const rng = (s: string): [number, number] => { const [a, b] = s.trim().split("-").map(Number); return [a!, b ?? a!]; };

describe("GET /api/reviews/:flag/info", () => {
  it("gives the three parts for nav:earn-no-transition", async () => {
    const j = await info();
    expect(j.ok).toBe(true);
    expect(j.flag).toBe(FLAG);
    expect(j.gains).toHaveLength(20);
    expect(j.excerpts).toHaveLength(5);
    expect(j.mechanism.length).toBeGreaterThan(4);
    expect(j.sources).toHaveLength(4);
    expect(j.summary).toContain("40 fewer");
    expect(j.summary).toContain("WebKit: unknown");
  });

  it("the console-web fixture is the Lean reply (regenerate it from fwcore when this fails)", async () => {
    const j = await info();
    const fx = JSON.parse(readFileSync(join(ROOT, "apps/console-web/test/fixtures/review-info.earn.json"), "utf8"));
    const strip = ({ id: _id, ...x }: any) => ({ ...x, excerpts: x.excerpts.map(({ ok: _o, first: _f, last: _z, lines: _l, reason: _r, ...e }: any) => e) });
    expect(strip(j)).toEqual(strip(fx));
  });

  it("every row has a status, and a shown gain never has an unknown status", async () => {
    const j = await info();
    for (const g of j.gains) {
      expect(["measured", "modelled", "unknown"]).toContain(g.status.kind);
      if (g.shown.kind === "gain") expect(g.status.kind).not.toBe("unknown");
      if (g.status.kind === "measured") { expect(g.status.runs.length).toBeGreaterThan(0); expect(g.status.aa.length).toBeGreaterThan(0); }
      if (g.status.kind === "modelled") expect(g.status.theorem).toBe("Fw.Parts.NavEarnOpt.work_le");
      if (g.status.kind === "unknown") { expect(g.status.why.length).toBeGreaterThan(10); expect(g.shown.kind).toBe("unknown"); }
    }
  });

  it("model rows equal the nav-earn golden work counts at both viewports", async () => {
    const j = await info();
    const work = jsonl("packages/contracts/golden/parts/nav-earn.jsonl").filter((l) => l.fn === "work");
    const prop: Record<string, string> = { "earn max-width": "maxW", "earn padding-inline": "pad", "earn opacity": "opacity" };
    const rows = j.gains.filter((g: any) => g.status.kind === "modelled");
    expect(rows).toHaveLength(6);
    for (const g of rows) {
      for (const vp of ["desktop", "phone"]) {
        const w = work.find((l) => l.in.property === prop[g.metric] && l.in.push === g.push && l.in.viewport === vp && l.in.frames === 91);
        expect(w, `${g.metric} ${g.push} ${vp}`).toBeTruthy();
        expect(g.before).toEqual([w.out.faithful, w.out.faithful]);
        expect(g.after).toEqual([w.out.arm, w.out.arm]);
      }
    }
    const open = rows.filter((g: any) => g.push === "open").map((g: any) => g.shown.text);
    expect(open).toEqual(["40 fewer", "40 fewer", "26 fewer"]);
    expect(rows.filter((g: any) => g.push === "close").map((g: any) => g.shown.text)).toEqual(["no saving", "no saving", "no saving"]);
  });

  it("measured rows equal the research note's table and name its runs", async () => {
    const j = await info();
    const note = readFileSync(join(ROOT, "research/notes/2026/10-20-earn-transition-retarget.md"), "utf8");
    const table = note.split("\n").filter((l) => /^\| (390|640|641|1280) \| (open|close) \|/.test(l)).map((l) => l.split("|").map((c) => c.trim()));
    const rows = j.gains.filter((g: any) => g.status.kind === "measured");
    expect(rows).toHaveLength(12);
    for (const g of rows) {
      const t = table.find((c) => c[1] === g.viewport && c[2] === g.push);
      expect(t, `${g.viewport} ${g.push}`).toBeTruthy();
      const cell = (g.metric.includes("opacity") ? t![3] : t![4])!;
      const [f, a] = cell.split("/").map((s) => rng(s));
      expect(g.before).toEqual(f);
      expect(g.after).toEqual(a);
      expect(g.engine).toBe("chromium");
      for (const run of [...g.status.runs, ...g.status.aa]) expect(note).toContain(run);
    }
    expect(rows[0].status.runs).toEqual(["39463486725", "39464309993"]);
    expect(rows[0].status.aa).toEqual(["39464294630", "39464322751"]);
  });

  it("open gains beat the noise; a loss uses the highest faithful and lowest flag count; overlapping ranges say so", async () => {
    const j = await info();
    const m = j.gains.filter((g: any) => g.status.kind === "measured");
    expect(m.filter((g: any) => g.push === "open").every((g: any) => g.shown.kind === "gain")).toBe(true);
    expect(m.filter((g: any) => g.push === "close").every((g: any) => g.shown.kind !== "gain")).toBe(true);
    const at = (metric: string, vp: string, push: string) => m.find((g: any) => g.metric.includes(metric) && g.viewport === vp && g.push === push);
    expect(at("max-width", "390", "close").shown).toEqual({ kind: "overlap", text: "no difference shown (ranges overlap)" });
    expect(at("opacity", "390", "close").shown).toEqual({ kind: "worse", n: 13, text: "13 more" });
    expect(at("opacity", "1280", "close").shown).toEqual({ kind: "worse", n: 3, text: "3 more" });
    for (const g of m) {
      const gain = g.before[0] - g.after[1], loss = g.before[1] - g.after[0], shared = g.after[0] <= g.before[1] && g.before[0] <= g.after[1];
      if (g.shown.kind === "gain") expect(gain).toBeGreaterThan(g.noise);
      if (g.shown.kind === "worse") expect(loss).toBeLessThan(-g.noise);
      if (g.shown.kind === "overlap") expect(shared).toBe(true);
      if (shared) expect(["overlap", "noSaving"]).toContain(g.shown.kind);
    }
  });

  it("the noise of a measured row is the A/A value-change noise of the note", async () => {
    const j = await info();
    const note = readFileSync(join(ROOT, "research/notes/2026/10-20-earn-transition-retarget.md"), "utf8");
    const aa = note.split("\n").filter((l) => /^\| (opacity|max-width) \|/.test(l)).map((l) => l.split("|").map((c) => c.trim()));
    expect(aa).toHaveLength(2);
    for (const g of j.gains.filter((x: any) => x.status.kind === "measured")) {
      const row = aa.find((c) => c[1] === (g.metric.includes("opacity") ? "opacity" : "max-width"))!;
      expect(g.noise).toBe(Number(row[5]));
    }
  });

  it("the ledger's verdicts agree: chromium wins on open and not on close, webkit is unknown", async () => {
    const j = await info();
    const row = JSON.parse(readFileSync(join(ROOT, "research/findings/ledger.json"), "utf8")).findings.find((f: any) => f.id === "nav.earn.noTransition");
    expect(row.chromium).toBe("win on the open push; no saving on the close push");
    expect(row.webkit).toBe("unknown");
    const wk = j.gains.filter((g: any) => g.engine === "webkit");
    expect(wk).toHaveLength(2);
    expect(wk.every((g: any) => g.status.kind === "unknown" && g.before === null)).toBe(true);
  });

  it("every code excerpt starts at the one line holding its anchor and holds its span", async () => {
    const j = await info();
    expect(j.excerpts.every((e: any) => e.ok === true)).toBe(true);
    for (const e of j.excerpts) {
      const lines = readFileSync(join(ROOT, e.file), "utf8").split("\n");
      const at = lines.flatMap((l, i) => (l.includes(e.anchor) ? [i + 1] : []));
      expect(at, `${e.id} anchor "${e.anchor}"`).toEqual([e.first]);
      expect(e.lines).toHaveLength(e.span);
      expect(e.last).toBe(e.first + e.span - 1);
    }
    const text = (id: string) => j.excerpts.find((e: any) => e.id === id).lines.map((l: any) => l.text).join("\n");
    expect(text("css-rule")).toContain("max-width 0.68s");
    expect(text("css-flag")).toContain("transition: none");
    expect(text("js-decision")).toContain("return !(flag && morphing)");
    expect(text("js-apply")).toContain("earnTransitionOn(");
  });

  it("every formula names a Lean declaration that is on its line", async () => {
    const j = await info();
    expect(j.formulas.length).toBeGreaterThanOrEqual(11);
    for (const f of j.formulas) {
      const line = readFileSync(join(ROOT, f.file), "utf8").split("\n")[f.line - 1] ?? "";
      expect(line, `${f.decl} at ${f.file}:${f.line}`).toMatch(new RegExp(`^(theorem|def|private def) ${f.decl}\\b|#guard .*\\b${f.decl}\\b`));
      if (f.kind === "theorem") expect(line.startsWith(`theorem ${f.decl} `)).toBe(true);
      expect(f.tex.length).toBeGreaterThan(5);
    }
    const names = j.formulas.map((f: any) => f.decl);
    for (const n of ["shown_off", "faithful_lags", "shown_settled", "visSame_settled", "work_le", "trace_eq", "settled3_same"]) expect(names).toContain(n);
  });

  it("a flag with no table is a 404 with a reason; a bad name is no error", async () => {
    const { app } = await rig();
    const r = await app.request(url("nav:other"));
    expect(r.status).toBe(404);
    expect(((await r.json()) as any).reason).toContain("no information table");
    expect((await app.request(url("x"))).status).toBe(404);
  });

  it("is behind the owner gate: on the LAN without a token the route answers 401", async () => {
    const dir = join(mkdtempSync(join(tmpdir(), "fw-info-")), ".fw-console");
    const store = await Store.open(dir, selectCore());
    stores.push(store);
    const owner = new OwnerAuth(); owner.setPorts(4000, 4001); owner.setLanHosts(["198.51.100.9:4000"]);
    const app = createApp(store, undefined, undefined, undefined, owner, undefined, { login: new LoginGuard(store.core, "fake-pass-for-tests-only"), lan: true }, ROOT);
    const r = await app.request(url(FLAG), { headers: { host: "198.51.100.9:4000" } }, LAN);
    expect(r.status).toBe(401);
  });
});

describe("readExcerpt", () => {
  const APPLY = "apps/site/src/parts/nav/index.tsx";
  const spec = (over: Partial<ExcerptSpec> = {}): ExcerptSpec => ({ id: "js-apply", side: "flag", file: APPLY, anchor: "nav.classList.toggle(EARN_STILL_CLASS", span: 1, note: "", ...over });
  function checkout(lines: string[]) {
    const root = mkdtempSync(join(tmpdir(), "fw-exc-"));
    mkdirSync(join(root, "apps/site/src/parts/nav"), { recursive: true });
    writeFileSync(join(root, APPLY), lines.join("\n"));
    return root;
  }
  const apply = "    nav.classList.toggle(EARN_STILL_CLASS, !on);";
  async function core(): Promise<Ops> { const { store } = await rig(); return (op, f) => store.core.ops(op, f); }
  it("finds the anchor line, and a line move above it moves the range with it", async () => {
    const ops = await core();
    const r = await readExcerpt(ops, checkout(["a", "b", apply, "c"]), FLAG, spec());
    expect(r).toMatchObject({ ok: true, first: 3, last: 3, lines: [{ n: 3, text: apply }] });
    const moved = await readExcerpt(ops, checkout([...Array.from({ length: 20 }, (_, i) => `// ${i}`), "a", "b", apply, "c"]), FLAG, spec());
    expect(moved).toMatchObject({ ok: true, first: 23, last: 23, lines: [{ n: 23, text: apply }] });
  });
  it("refuses by name an anchor on two lines, on no line, a span past the end, an unknown excerpt", async () => {
    const ops = await core();
    const twice = await readExcerpt(ops, checkout(["a", apply, "b", apply]), FLAG, spec());
    expect(twice.ok).toBe(false);
    if (!twice.ok) expect(twice.reason).toBe(`the anchor "nav.classList.toggle(EARN_STILL_CLASS" is on 2 lines of ${APPLY} (2, 4); the Lean excerpt needs an anchor that occurs once`);
    const missing = await readExcerpt(ops, checkout(["a", "b"]), FLAG, spec());
    if (!missing.ok) expect(missing.reason).toBe(`the anchor "nav.classList.toggle(EARN_STILL_CLASS" is on no line of ${APPLY}; the Lean excerpt needs a new anchor`);
    expect(missing.ok).toBe(false);
    const css = "apps/site/src/parts/nav/nav.module.css";
    const root = checkout([]);
    writeFileSync(join(root, css), "x\n  .nav:global(.is-earn-still) .btn.earn {\n    transition: none;");
    const past = await readExcerpt(ops, root, FLAG, spec({ id: "css-flag", file: css, anchor: ".nav:global(.is-earn-still) .btn.earn {", span: 3 }));
    expect(past.ok).toBe(false);
    if (!past.ok) expect(past.reason).toContain(`do not fit the file (3 lines)`);
    const unknown = await readExcerpt(ops, checkout([apply]), FLAG, spec({ id: "nope" }));
    if (!unknown.ok) expect(unknown.reason).toBe(`${FLAG} has no excerpt nope`);
    expect(unknown.ok).toBe(false);
  });
  it("refuses a missing file and a path outside the checkout before asking the core", async () => {
    const root = checkout([apply]);
    const never: Ops = async () => { throw new Error("not asked"); };
    expect(fileLines(root, "a/none.txt")).toEqual({ reason: "a/none.txt does not exist in the checkout" });
    expect(await readExcerpt(never, root, FLAG, spec({ file: "../etc/passwd" }))).toMatchObject({ ok: false, reason: "the file is outside the checkout" });
    expect(await readExcerpt(never, root, FLAG, spec({ file: "/etc/passwd" }))).toMatchObject({ ok: false, reason: "the file is outside the checkout" });
  });
});
