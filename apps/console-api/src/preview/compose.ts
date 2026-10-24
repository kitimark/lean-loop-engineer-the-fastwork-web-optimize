import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Hono } from "hono";
import type { Core } from "../core/index.ts";

export type ComposeVariant = { name: string; kind: string; limit: string };
export type ComposeRegistry = {
  parts: { id: string; slot: string; impls: string[]; variants: ComposeVariant[]; requires: Record<string, string[]>; conflicts: Record<string, string[]> }[];
  presets: { name: string; extends?: string; fw: Record<string, string> }[];
};
export type LedgerRow = {
  part: string; candidate: string; status: string; flag?: string | null; chromium?: string; webkit?: string; visual?: string; mechanism?: string;
  leanFor?: string[]; leanAgainst?: string[]; missingWhy?: string[]; premises?: string[]; v1Evidence?: string; lesson?: string; next?: string; id?: string; evidence?: string;
  supersededBy?: string; flags?: string[];
};
export type LedgerNote = { entry: string; task: string; field: string; text: string };
export type ComposePick = { part: string; variant: string };

export function readComposeRegistry(root: string): ComposeRegistry {
  const parts: ComposeRegistry["parts"] = [];
  const pdir = join(root, "apps/site/src/parts");
  if (existsSync(pdir)) {
    for (const d of readdirSync(pdir).sort()) {
      const f = join(pdir, d, "part.json");
      if (!existsSync(f)) continue;
      const p = JSON.parse(readFileSync(f, "utf8")) as {
        id: string; slot?: string; impls?: string[];
        variants?: Record<string, { kind?: string; provenance?: { limit?: string } }>;
        requires?: Record<string, string[]>; conflicts?: Record<string, string[]>;
      };
      parts.push({
        id: p.id, slot: p.slot ?? "", impls: p.impls ?? [], requires: p.requires ?? {}, conflicts: p.conflicts ?? {},
        variants: Object.entries(p.variants ?? {}).map(([name, v]) => ({ name, kind: v.kind ?? "optimized", limit: v.provenance?.limit ?? "" })),
      });
    }
  }
  const presets: ComposeRegistry["presets"] = [];
  const rdir = join(root, "apps/site/src/registry/presets");
  if (existsSync(rdir)) {
    for (const n of readdirSync(rdir).filter((x) => x.endsWith(".json")).sort()) {
      const p = JSON.parse(readFileSync(join(rdir, n), "utf8")) as { name?: string; extends?: string; fw?: Record<string, string> };
      presets.push({ name: p.name ?? n.slice(0, -5), ...(p.extends ? { extends: p.extends } : {}), fw: p.fw ?? {} });
    }
  }
  return { parts, presets };
}

export function readLedger(root: string): { findings: LedgerRow[]; notes: LedgerNote[] } {
  const f = join(root, "research/findings/ledger.json");
  if (!existsSync(f)) return { findings: [], notes: [] };
  const j = JSON.parse(readFileSync(f, "utf8")) as { findings?: LedgerRow[]; notes?: LedgerNote[] };
  return { findings: j.findings ?? [], notes: j.notes ?? [] };
}

export function runIdsIn(texts: (string | string[] | undefined)[]): string[] {
  const out = new Set<string>();
  for (const t of texts) for (const m of [t ?? ""].flat().join("\n").matchAll(/\b\d{10,12}\b/g)) out.add(m[0]);
  return [...out];
}

export function explainRow(row: LedgerRow, index: number, notes: LedgerNote[]) {
  const mine = notes.filter((n) => n.entry === row.candidate);
  return {
    index, part: row.part, candidate: row.candidate, status: row.status, chromium: row.chromium ?? "", webkit: row.webkit ?? "", visual: row.visual ?? "",
    mechanism: row.mechanism ?? "", leanFor: row.leanFor ?? [], leanAgainst: row.leanAgainst ?? [], lesson: row.lesson ?? "", next: row.next ?? "",
    evidence: row.evidence ?? "",
    notes: mine.map((n) => ({ task: n.task, field: n.field, text: n.text })),
    runs: runIdsIn([row.visual, row.mechanism, row.leanFor, row.leanAgainst, row.lesson, row.next, row.evidence, ...mine.map((n) => n.text)]),
  };
}

export type ComposeReply = Record<string, unknown> & {
  parts: { variants: { rows: number[]; gpu: string | null; gpuEngines: string | null }[]; other: number[] }[];
  decision: { ok: boolean; link: string | null; reasons: string[]; notes: string[] };
};

export async function composeReply(root: string, core: Pick<Core, "ops">, picks: ComposePick[]): Promise<Record<string, unknown>> {
  const registry = readComposeRegistry(root);
  const ledger = readLedger(root);
  const r = (await core.ops("console.compose", {
    registry, picks,
    ledger: ledger.findings.map((x) => ({
      part: x.part, candidate: x.candidate, status: x.status, ...(x.flag ? { flag: x.flag } : {}), ...(x.flags !== undefined ? { flags: x.flags } : {}),
      ...(x.id !== undefined ? { id: x.id } : {}), ...(x.supersededBy !== undefined ? { supersededBy: x.supersededBy } : {}),
    })),
  })) as unknown as ComposeReply;
  const want = new Set<number>();
  for (const p of r.parts) { p.other.forEach((i) => want.add(i)); for (const v of p.variants) v.rows.forEach((i) => want.add(i)); }
  const rows: Record<string, ReturnType<typeof explainRow>> = {};
  for (const i of [...want].sort((a, b) => a - b)) { const row = ledger.findings[i]; if (row) rows[String(i)] = explainRow(row, i, ledger.notes); }
  return { ok: true, ...r, rows };
}

export function parsePicks(q: string | undefined): ComposePick[] | null {
  if (q === undefined || q === "") return [];
  const out: ComposePick[] = [];
  for (const e of q.split(",")) {
    const m = /^([A-Za-z0-9._-]{1,60}):([A-Za-z0-9._-]{1,60})$/.exec(e);
    if (!m || out.length >= 80) return null;
    out.push({ part: m[1]!, variant: m[2]! });
  }
  return out;
}

export function mountCompose(app: Hono, core: Pick<Core, "ops">, root: string, session: (authorization: string | undefined) => Record<string, unknown> = () => ({})) {
  app.get("/api/compose", async (c) => {
    c.header("Cache-Control", "no-store");
    const picks = parsePicks(c.req.query("pick"));
    if (!picks) return c.json({ ok: false, reason: "pick must be part:variant,part:variant (letters, digits, . - _)" }, 400);
    return c.json({ ...(await composeReply(root, core, picks)), ...session(c.req.header("authorization")) });
  });
  app.get("/api/compose/decision", async (c) => {
    c.header("Cache-Control", "no-store");
    const picks = parsePicks(c.req.query("pick"));
    if (!picks) return c.json({ ok: false, reason: "pick must be part:variant,part:variant (letters, digits, . - _)" }, 400);
    const r = await composeReply(root, core, picks);
    return c.json({ ok: true, decision: r.decision });
  });
}
