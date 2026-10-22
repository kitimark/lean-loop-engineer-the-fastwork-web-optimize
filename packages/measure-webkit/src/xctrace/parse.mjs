// Reads of `xctrace` output for the local probe: the table of contents of a trace and the rows of one exported table. Text parsing only.
import { hitchesRecorded } from '../safari-local-reduce.mjs';

/** `xctrace export --toc` XML: whether the trace holds a run with data, and the table schemas it lists. */
export function parseToc(xml) {
  const s = String(xml ?? '');
  const schemas = [...new Set([...s.matchAll(/<table\b[^>]*\bschema="([^"]+)"/g)].map((m) => m[1]))];
  return { finalized: /<run\b/.test(s) && schemas.length > 0, schemas };
}

/** Rows of an exported table (`<row>` elements). */
export const countRows = (xml) => (String(xml ?? '').match(/<row\b/g) ?? []).length;

/** The first lines of an xctrace message that carry an error, for the record (no paths: a trace file name is reduced to its base). */
export function errorLines(text, max = 3) {
  return String(text ?? '').split('\n').map((l) => l.trim()).filter((l) => /error|not supported|fail|unable|cannot|denied|no devices/i.test(l)).slice(0, max).map((l) => l.replace(/\/[^\s'"]*\//g, '').slice(0, 220));
}

/** One probe result: Lean's `hitchesRecorded` over whether the trace finalized and how many hitch rows it holds. */
export const verdictOf = ({ toc, rows }) => ({ recorded: hitchesRecorded(toc.finalized, rows), finalized: toc.finalized, schemas: toc.schemas.length, hitchRows: rows });
