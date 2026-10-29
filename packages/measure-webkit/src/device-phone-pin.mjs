import { loadState, saveState } from './device-phone-run.mjs';
import { PIN, clearWait, closeAct, conditionSetDrop, endVerdictDrop, profileOf } from './device-thermal-pin.mjs';

const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));

export async function pinnedSession({ target, dir, log, owner, sense, body, signals = true, now = Date.now, sleep = sleepMs }) {
  const profile = profileOf(target);
  if (!profile) throw new Error(`target ${target} cannot be induced (Fair or Serious)`);
  const onSig = (sig) => {
    log(`${sig}: stopping the condition owner`);
    owner.stop().finally(() => process.exit(130));
  };
  const onExit = () => owner.termSync();
  if (signals) { process.once('SIGINT', onSig); process.once('SIGTERM', onSig); process.on('exit', onExit); }
  const note = (patch) => {
    const st = loadState(dir);
    st.pin = { ...st.pin, ...patch };
    saveState(dir, st);
  };
  let result;
  let failure = null;
  try {
    note({ target, profile, source: 'pymobiledevice3 developer dvt condition set --userspace' });
    let b;
    try { b = sense(); } catch (e) { b = { state: null, error: e.message }; }
    note({ before: { at: new Date(now()).toISOString(), state: b.state ?? null, ...(b.error ? { error: b.error } : {}) } });
    await owner.recover({ read: () => sense().state ?? null });
    const rec = await owner.start({ profile, target, before: b.state ?? null });
    note({ owner: { pid: rec.pid, start: rec.start, spawnedAt: rec.spawnedAt } });
    result = await body({ target, held: () => owner.alive(), onHeld: () => { owner.phase = 'held'; } });
  } catch (e) {
    failure = e;
  }
  const close = closeAct(owner.phase);
  let stopped = { gone: close === 'nothing', acked: close === 'nothing' && (owner.rec === null || owner.rec.acked === true), signals: [] };
  try { if (close === 'stopOwner') stopped = await owner.stop(); } catch (e) { log(`stopping the owner failed: ${e.message}`); }
  const readbacks = [];
  const t0 = now();
  for (;;) {
    let r;
    try { r = sense(); } catch (e) { r = { state: null, error: e.message }; }
    readbacks.push({ at: new Date(now()).toISOString(), state: r.state ?? null, ...(r.error ? { error: r.error } : {}) });
    if (!stopped.gone || !stopped.acked || !clearWait(target, r.state ?? null, Math.round((now() - t0) / 1000))) break;
    await sleep(PIN.pinPollS * 1000);
  }
  const back = readbacks[readbacks.length - 1].state;
  const before = owner.rec?.before ?? null;
  const usbDropped = stopped.usbDropped === true || (owner.rec !== null && owner.usbDropped());
  const end = endVerdictDrop(target, usbDropped, stopped.gone, stopped.acked, before, back);
  note({ stoppedAt: new Date(now()).toISOString(), signals: stopped.signals, acked: stopped.acked, usbDropped, readback: readbacks, after: readbacks[readbacks.length - 1], end, conditionSet: conditionSetDrop(target, usbDropped, stopped.gone, stopped.acked, before, back) });
  log(`condition owner ${stopped.gone ? (stopped.acked ? 'gone, clear confirmed' : end === 'clearedDrop' ? 'gone after a USB drop, the phone reads its pre-pin state' : 'gone, clear NOT confirmed') : 'STILL RUNNING'}; reported state after: ${back ?? 'unreadable'}; end ${end}`);
  if (signals) { process.off('SIGINT', onSig); process.off('SIGTERM', onSig); process.off('exit', onExit); }
  if (failure) throw failure;
  if (end === 'stuck') throw new Error(`the condition owner (pid ${owner.rec?.pid}) did not exit; stop it by hand with kill -TERM`);
  if (end === 'unconfirmed') throw new Error(`the condition owner ended without confirming its clear${usbDropped ? ' (the phone is not on USB: plug it in and unlock it)' : ''}; the induced state may remain on the phone, the next run clears it (pin-stop does the same)`);
  return { ...result, pin: { end, readback: readbacks } };
}
