// The flag sets of the combo-scroll-fight replay (task combo-scroll-fight). `bisect`: the user's eight flags, each dropped once,
// and the morph subsets; `fix`: the same replay on the two sets that matter after the fix. A search is the `?fw=` query the page loads.

export const USER_FLAGS = [
  'nav:earn-logical', 'hero.countdown:strip', 'morph.countdown:strip', 'morph.end.clamp:on', 'morph.end.flip:on',
  'morph.end.release:on', 'morph.mount:arm-late', 'engine.scroll:unthrottle',
];

const q = (flags) => (flags.length === 0 ? '' : `?fw=${flags.join(',')}`);

const without = (f) => USER_FLAGS.filter((x) => x !== f);
const END3 = ['morph.end.clamp:on', 'morph.end.flip:on', 'morph.end.release:on'];

export const BISECT = [
  { name: 'default', search: '' },
  { name: 'user', search: q(USER_FLAGS) },
  ...USER_FLAGS.map((f) => ({ name: `user-minus-${f.split(':')[0]}`, search: q(without(f)) })),
  { name: 'end3', search: q(END3) },
  { name: 'clamp', search: q(['morph.end.clamp:on']) },
  { name: 'flip', search: q(['morph.end.flip:on']) },
  { name: 'release', search: q(['morph.end.release:on']) },
  { name: 'end3+arm-late', search: q([...END3, 'morph.mount:arm-late']) },
  { name: 'end3+unthrottle', search: q([...END3, 'engine.scroll:unthrottle']) },
  { name: 'end3+arm-late+unthrottle', search: q([...END3, 'morph.mount:arm-late', 'engine.scroll:unthrottle']) },
];

export const FIX = BISECT.filter((a) => ['default', 'user', 'end3', 'release'].includes(a.name));

export const SETS = { bisect: BISECT, fix: FIX };

/** `name=search;name=search` for combo-cli --arms. */
export const armsArg = (set) => SETS[set].map((a) => `${a.name}=${a.search}`).join(';');

if (process.argv[1] && process.argv[1].endsWith('combo-arms.mjs')) {
  const [cmd, set] = process.argv.slice(2);
  if (!SETS[set]) { console.error('usage: combo-arms.mjs configs|arms bisect|fix'); process.exit(2); }
  if (cmd === 'configs') process.stdout.write(`${SETS[set].filter((a) => a.search !== '').map((a) => a.search).join('\n')}\n`);
  else if (cmd === 'arms') process.stdout.write(`${armsArg(set)}\n`);
  else { console.error('usage: combo-arms.mjs configs|arms bisect|fix'); process.exit(2); }
}
