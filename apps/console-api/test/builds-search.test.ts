import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { readRegistry, type Registry } from "../src/preview/builds.ts";
import { resolve, hashConfig } from "../../site/src/registry/resolve.ts";
import type { PartDef, PresetDef } from "../../site/src/registry/types.ts";

/** The Lean validator (`console.buildsSearch`, Fw.Console.BuildsOpen.validate) agrees with the site's resolve.ts: same verdict, same
 *  reasons in the same order, and the canonical search resolves to the same config. The charset and the length cap are Lean-only (stricter by design). */
const GOLDEN = join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden/console");
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
type Case = { name: string; request: { registry?: Registry; search: string }; response: { ok?: boolean; canonical?: string | null; reasons?: string[]; error?: string } };
const cases = (op: string) => readFileSync(join(GOLDEN, `${op}.jsonl`), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Case);

/** The registry facts as the site's own types (only the fields resolve reads are real). */
function siteOf(r: Registry): { parts: PartDef[]; presets: Record<string, PresetDef> } {
  const parts = r.parts.map((p) => ({ id: p.id, slot: "", anchors: [], experiment: false, impls: p.impls, muiStates: [], requires: p.requires ?? {}, conflicts: p.conflicts ?? {},
    variants: Object.fromEntries(p.variants.map((v) => [v, { kind: "faithful" as const }])) })) as PartDef[];
  const presets: Record<string, PresetDef> = {};
  for (const p of r.presets) presets[p.name] = { name: p.name, ...(p.extends ? { extends: p.extends } : {}), fw: p.fw };
  return { parts, presets };
}
const lexical = (c: Case) => (c.response.reasons ?? []).some((x) => x.startsWith("search "));

describe("console.buildsSearch golden: Lean validate agrees with apps/site resolve.ts", () => {
  const all = cases("console.buildsSearch").filter((c) => c.response.error === undefined);
  it("the vector set has the cases the task names", () => {
    const names = all.map((c) => c.name).join("|");
    for (const w of ["long search", "v2-proved alone", "unknown part", "unknown variant", "two presets", "requires violation", "conflicts violation", "percent escape"]) expect(names).toContain(w);
  });
  for (const c of all.filter((x) => !lexical(x))) {
    it(c.name, () => {
      const { parts, presets } = siteOf(c.request.registry!);
      const site = resolve(c.request.search, parts, presets);
      expect(c.response.ok).toBe(site.ok);
      if (!site.ok) expect(c.response.reasons).toEqual(site.errors);
      else {
        const again = resolve(c.response.canonical!, parts, presets);
        expect(again.ok && hashConfig(again.config)).toBe(hashConfig(site.config));
      }
    });
  }
  it("the charset and length refusals are Lean-only and never reach resolve", () => {
    const lex = all.filter(lexical);
    expect(lex.length).toBeGreaterThanOrEqual(6);
    for (const c of lex) { expect(c.response.ok).toBe(false); expect(c.response.canonical).toBeNull(); }
  });
});

describe("console.buildsSearch live: fwcore over the real registry agrees with resolve.ts", () => {
  const reg = readRegistry(ROOT);
  const parts = readdirSync(join(ROOT, "apps/site/src/parts")).filter((d) => existsSync(join(ROOT, "apps/site/src/parts", d, "part.json"))).map((d) => JSON.parse(readFileSync(join(ROOT, "apps/site/src/parts", d, "part.json"), "utf8")) as PartDef);
  const presets: Record<string, PresetDef> = {};
  for (const p of reg.presets) presets[p.name] = p as PresetDef;
  const searches = [
    "?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped",
    "?preset=v2-proved", "", "?fw=nope.part:x", "?fw=hero.countdown:nope", "?preset=a&preset=b", "?preset=nope",
  ];
  for (const s of searches) {
    it(`agrees on ${s || "(empty)"}`, async () => {
      const core = selectCore();
      const v = await core.ops("console.buildsSearch", { registry: reg, search: s });
      const site = resolve(s, parts, presets);
      expect(v.ok).toBe(site.ok);
      if (!site.ok) expect(v.reasons).toEqual(site.errors);
    });
  }
});
