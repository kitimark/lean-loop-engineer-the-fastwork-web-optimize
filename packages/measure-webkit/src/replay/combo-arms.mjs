
export const USER_FLAGS = [
  'nav:earn-logical', 'hero.countdown:strip', 'morph.countdown:strip', 'morph.end.clamp:on', 'morph.end.flip:on',
  'morph.end.release:on', 'morph.mount:arm-late', 'engine.scroll:unthrottle',
];

const q = (flags) => (flags.length === 0 ? '' : `?fw=${flags.join(',')}`);

const without = (...fs) => USER_FLAGS.filter((x) => !fs.includes(x));
const END3 = ['morph.end.clamp:on', 'morph.end.flip:on', 'morph.end.release:on'];

export const BISECT = [
  { name: 'default', search: '' },
  { name: 'user', search: q(USER_FLAGS) },
  ...USER_FLAGS.filter((f) => f !== 'hero.countdown:strip').map((f) => ({ name: `user-minus-${f.split(':')[0]}`, search: q(without(f)) })),
  { name: 'user-minus-countdown-pair', search: q(without('hero.countdown:strip', 'morph.countdown:strip')) },
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

export const armsArg = (set) => SETS[set].map((a) => `${a.name}=${a.search}`).join(';');

if (process.argv[1] && process.argv[1].endsWith('combo-arms.mjs')) {
  const [cmd, set] = process.argv.slice(2);
  if (!SETS[set]) { console.error('usage: combo-arms.mjs configs|arms bisect|fix'); process.exit(2); }
  if (cmd === 'configs') process.stdout.write(`${SETS[set].filter((a) => a.search !== '').map((a) => a.search).join('\n')}\n`);
  else if (cmd === 'arms') process.stdout.write(`${armsArg(set)}\n`);
  else { console.error('usage: combo-arms.mjs configs|arms bisect|fix'); process.exit(2); }
}
