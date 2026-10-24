// Prints the searches of the morph end arms that the default site build does not prerender, one per line; the site job of
// toolbar-throttle.yml passes each to `build.mjs --config` when the commit asks for [throttle:morph-end].
import { EXTRA_SEARCHES } from './morph-end.mjs';

for (const s of EXTRA_SEARCHES) console.log(s);
