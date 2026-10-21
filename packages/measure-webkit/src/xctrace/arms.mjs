// xctrace-ci-probe: the recording arms. One arm = one `xctrace record` of one scripted scroll. Pure data and argument building.
//   hitches        Animation Hitches template, every process of the Simulator device (Apple: tech talk 10857 lists the tracks it records).
//                  Probed on a Mac with a GPU: "Hitches is not supported on this platform", the trace has no run data
//   hitches-host   the same template on the host Mac (no --device): the Simulator's processes are host processes, so the host recording can see them
//   signposts      no template; the os_signpost and Points of Interest instruments over all processes. WebKit's os_signposts are emitted
//                  only while the DBG_APPS kdebug class is enabled (wtf/SystemTracing.h `WTFSignpostsEnabled`, WebKit 862f17d, lines 316-326)
//   systrace       System Trace template: it records kdebug (the tracePoint codes of SystemTracing.h, WEBKIT_COMPONENT 47) in the kdebug table
// `-host` arms record the host Mac instead of the Simulator device. `sudo` is tried by the harness only when an arm fails without it.

/** @typedef {{id:string, device:'sim'|'host', template:string|null, instruments:string[], target:'all'|{attach:string}}} Arm */

/** @type {readonly Arm[]} */
export const ARMS = Object.freeze([
  { id: 'hitches', device: 'sim', template: 'Animation Hitches', instruments: [], target: 'all' },
  { id: 'hitches-host', device: 'host', template: 'Animation Hitches', instruments: [], target: 'all' },
  { id: 'signposts', device: 'sim', template: null, instruments: ['os_signpost', 'Points of Interest'], target: 'all' },
  { id: 'signposts-host', device: 'host', template: null, instruments: ['os_signpost', 'Points of Interest'], target: 'all' },
  { id: 'systrace', device: 'sim', template: 'System Trace', instruments: [], target: 'all' },
  { id: 'systrace-host', device: 'host', template: 'System Trace', instruments: [], target: 'all' },
].map((a) => Object.freeze(a)));

export const armById = (id) => {
  const a = ARMS.find((x) => x.id === id);
  if (!a) throw new Error(`unknown arm "${id}"; known: ${ARMS.map((x) => x.id).join(', ')}`);
  return a;
};

/** The `xctrace record` argument list of an arm (no `sudo`, no `xcrun`). `limitS` is the backstop; the harness stops the recording itself. */
export function recordArgs(arm, { udid, out, limitS = 300, notify = null }) {
  const a = ['xctrace', 'record'];
  if (arm.template) a.push('--template', arm.template);
  for (const i of arm.instruments) a.push('--instrument', i);
  if (arm.device === 'sim') a.push('--device', udid);
  if (arm.target === 'all') a.push('--all-processes');
  else a.push('--attach', arm.target.attach);
  a.push('--time-limit', `${limitS}s`, '--no-prompt', '--output', out);
  if (notify) a.push('--notify-tracing-started', notify);
  return a;
}

/** Table schemas worth exporting: everything about hitches, hangs, signposts, kdebug, commits, renders and frames. */
export const WANTED_SCHEMA = /hitch|hang|signpost|kdebug|commit|render|frame|display|vsync|gpu|animation|point|interval|life/i;
