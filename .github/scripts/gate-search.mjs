// The search string of the gate's rewrite arm from the `fw` and `preset` workflow inputs. Twin of Fw.Gate.Search.pick
// (lean/Fw/Gate/Search.lean), checked against packages/contracts/golden/gate/search.jsonl by gate-search.test.mjs.
//   node .github/scripts/gate-search.mjs --fw '<flags>' --preset '<name>'   prints the search string; exit 1 when refused
const presetChar = /^[a-z0-9-]+$/;
const fwChar = /^[A-Za-z0-9.:,\-_@]+$/;

export function pick(fw, preset) {
  if (fw === '' && preset === '') return { ok: true, search: '' };
  if (fw !== '' && preset !== '') return { ok: false, refusal: 'bothSet' };
  if (fw === '') return presetChar.test(preset) ? { ok: true, search: `?preset=${preset}` } : { ok: false, refusal: 'badPreset' };
  return fwChar.test(fw) ? { ok: true, search: `?fw=${fw}` } : { ok: false, refusal: 'badFw' };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const arg = (name) => {
    const i = process.argv.indexOf(name);
    return i < 0 ? '' : (process.argv[i + 1] ?? '');
  };
  const r = pick(arg('--fw'), arg('--preset'));
  if (!r.ok) {
    console.error(`gate-search: refused (${r.refusal}): fw and preset are exclusive; names are [a-z0-9-], flag sets [A-Za-z0-9.:,-_@]`);
    process.exit(1);
  }
  process.stdout.write(r.search);
}
