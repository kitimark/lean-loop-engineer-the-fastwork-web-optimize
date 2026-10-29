// The shape rule of the findings ledger's notes (task ledger-note-check, mistake class c-late-check). One rule, three callers:
// the commit check (`scripts/checkmap.mjs file ledger`, planned by Lean Fw.Ops.CheckMap `ledgerNotes`), the dry land
// (`ledgerNoteKeyCheck` in land.ts) and the ledger tests (test/ledger-merge.test.ts). The remote land suite stays the last line.
// TS stand-in: no Lean spec of the rule yet; when it runs is Lean (CheckMap.ledgerInput, LandTier.ledgerNotesReads).

const NOTE_KEYS = ["entry", "field", "task", "text"];

/** The problems of a findings ledger's notes, one line each; none when every note names a finding by its candidate, names a findings field, carries a text and no (entry, task) repeats. */
export function noteShapeProblems(text: string): string[] {
  let doc: { findings?: unknown; notes?: unknown };
  try { doc = JSON.parse(text) as typeof doc; } catch { return ["not valid JSON"]; }
  if (doc.notes === undefined) return [];
  if (!Array.isArray(doc.notes)) return ["notes is not an array"];
  const findings = (Array.isArray(doc.findings) ? doc.findings : []) as Record<string, unknown>[];
  const candidates = new Set(findings.map((f) => f.candidate));
  const fields = new Set(Object.keys(findings[0] ?? {}));
  const out: string[] = [];
  const seen = new Set<string>();
  doc.notes.forEach((n: unknown, i: number) => {
    const at = `note ${i}`;
    if (n === null || typeof n !== "object" || Array.isArray(n)) { out.push(`${at}: not an object`); return; }
    const o = n as Record<string, unknown>;
    const keys = Object.keys(o).sort();
    if (keys.join(",") !== NOTE_KEYS.join(",")) out.push(`${at}: keys are [${keys.join(", ")}], want [${NOTE_KEYS.join(", ")}]`);
    if (!candidates.has(o.entry)) out.push(`${at}: entry ${JSON.stringify(o.entry)} is not the candidate of a finding`);
    if (!fields.has(o.field as string)) out.push(`${at}: field ${JSON.stringify(o.field)} is not a findings field (${[...fields].join(", ")})`);
    if (typeof o.text !== "string" || o.text.length === 0) out.push(`${at}: text is empty`);
    const k = JSON.stringify([o.entry, o.task]);
    if (seen.has(k)) out.push(`${at}: (entry, task) ${k} repeats`);
    seen.add(k);
  });
  return out;
}
