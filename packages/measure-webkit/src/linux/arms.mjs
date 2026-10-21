// Arms of the Linux WebKit frame-cause probe (task linux-webkit-probe). One arm = one page kind, one viewport width,
// one device pixel ratio and a set of environment variables for the WebKit process. The matrix separates the causes
// of the ~150 ms frames Playwright's headless WPE shows on a CI VM: how much page there is (blank / full repaint /
// our original page), how many device pixels (width x dpr), and which paint or GL switch is set.
//
// TS stand-in: nothing here decides a verdict; the arms are a plan and the probe only describes (no gate reads it).

/** Page kinds. `blank`: an empty tall page. `paint`: an empty tall page whose body colour changes in every rAF (a full-viewport
 * repaint per frame, so raster and composite cost show up per frame). `orig`: the committed snapshot of the original site. */
export const PAGES = ['blank', 'paint', 'orig'];

/** The env switches under test (each one changes one thing; WebKit source cited in research/notes/2026/10-2x-linux-webkit.md). */
export const ENV_SWITCHES = {
  msaa0: { WEBKIT_SKIA_MSAA_SAMPLE_COUNT: '0' },
  cpu: { WEBKIT_SKIA_ENABLE_CPU_RENDERING: '1' },
  lp1: { LP_NUM_THREADS: '1' },
  fps: { WEBKIT_SHOW_FPS: '1' },
};

const WIDTHS = [390, 1280];
const DPRS = [1, 3];

/** The arm id: `<page>-w<width>-d<dpr>[-<switch>]`. */
export function armId({ page, width, dpr, sw }) {
  return `${page}-w${width}-d${dpr}${sw ? `-${sw}` : ''}`;
}

/** The whole matrix. Base arms: every page x width x dpr with no switch. Switch arms: each switch on the `paint` and `orig`
 * pages at the phone-like cell (width 390, dpr 3), where the device pixel count is largest per CSS pixel. */
export function armList() {
  const arms = [];
  for (const page of PAGES) for (const width of WIDTHS) for (const dpr of DPRS) arms.push({ page, width, dpr, sw: null });
  for (const sw of Object.keys(ENV_SWITCHES)) for (const page of ['paint', 'orig']) arms.push({ page, width: 390, dpr: 3, sw });
  return arms.map((a) => ({ ...a, id: armId(a), env: a.sw ? ENV_SWITCHES[a.sw] : {} }));
}

/** Arms named in `ids` (comma separated), or all when `ids` is empty. Unknown ids throw. */
export function selectArms(ids) {
  const all = armList();
  if (!ids) return all;
  const want = ids.split(',').map((s) => s.trim()).filter(Boolean);
  const byId = new Map(all.map((a) => [a.id, a]));
  return want.map((id) => {
    if (!byId.has(id)) throw new Error(`unknown arm ${id}; known: ${all.map((a) => a.id).join(' ')}`);
    return byId.get(id);
  });
}

/** Run order: round `A` over every arm, then round `B` over every arm, so slow drift on the VM shows between the two rounds of an arm. */
export function schedule(arms, rounds = ['A', 'B']) {
  return rounds.flatMap((round) => arms.map((arm) => ({ round, arm })));
}
