import { searchesOf } from './push-cycle.mjs';

for (const s of searchesOf((process.argv[2] ?? 'original,rewrite,user').split(','))) console.log(s);
