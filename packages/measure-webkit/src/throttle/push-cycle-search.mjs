// node src/throttle/push-cycle-search.mjs [arms]   one ?fw= search per line, for the site build's `--config` (arms default: original,rewrite,user)
import { searchesOf } from './push-cycle.mjs';

for (const s of searchesOf((process.argv[2] ?? 'original,rewrite,user').split(','))) console.log(s);
