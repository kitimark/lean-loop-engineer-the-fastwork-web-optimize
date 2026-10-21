// Keeping the raw input of each event window beside the leg file, so a change of the reduction (reduce.mjs, Lean WebKitProfile) re-reduces
// without a new CI run. I/O only: one gzipped JSON file per leg, `<leg>.raw.json.gz`, `{ leg, windows: [{ arm, window, rep, raw }] }`.
import { writeFileSync, readFileSync } from 'node:fs';
import { gzipSync, gunzipSync } from 'node:zlib';
import { join } from 'node:path';

/** Write the raws of a leg result (`res.raws`) and return the result without them (the leg file keeps profiles only). */
export function writeRaws(out, name, res) {
  const { raws, ...rest } = res;
  writeFileSync(join(out, `${name}.raw.json.gz`), gzipSync(JSON.stringify({ leg: res.leg, windows: raws ?? [] })));
  return rest;
}

/** Read the raw windows of a leg file. */
export const readRaws = (file) => JSON.parse(gunzipSync(readFileSync(file)).toString('utf8'));
