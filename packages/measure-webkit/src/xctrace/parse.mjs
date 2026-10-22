import { hitchesRecorded } from '../safari-local-reduce.mjs';

export function parseToc(xml) {
  const s = String(xml ?? '');
  const schemas = [...new Set([...s.matchAll(/<table\b[^>]*\bschema="([^"]+)"/g)].map((m) => m[1]))];
  return { finalized: /<run\b/.test(s) && schemas.length > 0, schemas };
}

export const countRows = (xml) => (String(xml ?? '').match(/<row\b/g) ?? []).length;

export function errorLines(text, max = 3) {
  return String(text ?? '').split('\n').map((l) => l.trim()).filter((l) => /error|not supported|fail|unable|cannot|denied|no devices/i.test(l)).slice(0, max).map((l) => l.replace(/\/[^\s'"]*\//g, '').slice(0, 220));
}

export const verdictOf = ({ toc, rows }) => ({ recorded: hitchesRecorded(toc.finalized, rows), finalized: toc.finalized, schemas: toc.schemas.length, hitchRows: rows });
