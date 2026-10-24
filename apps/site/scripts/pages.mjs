// Which prerendered page answers a request: dist/<engine>/configs.json maps the exact search string to a page.
// Unknown search -> index.html (the client then renders on the client: __fw.mode === 'client-render').
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { canonSearch } from '../../../packages/contracts/src/flag-key.mjs';

export function pageFor(dir, search) {
  try {
    const { bySearch, byHash } = JSON.parse(readFileSync(path.join(dir, 'configs.json'), 'utf8'));
    const hash = bySearch[canonSearch(search)];
    return hash ? byHash[hash] : 'index.html';
  } catch {
    return 'index.html';
  }
}
