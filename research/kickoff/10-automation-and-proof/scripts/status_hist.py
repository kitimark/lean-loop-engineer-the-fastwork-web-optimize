import json, glob, collections, sys
d = sys.argv[1]
rows = [json.load(open(f)) for f in glob.glob(d+'/status/*.json')]
H = []; trunc=0
for r in rows:
    h = r.get('history', [])
    if len(h) >= 100: trunc += 1
    for e in h: H.append((r, e))
print('rows', len(rows), 'history entries', len(H), 'rows at 100-entry cap', trunc)
act = collections.Counter(e.get('action') for _, e in H); print('actions', act)
def who(r, e):
    b = e.get('by') or '?'
    if b == r.get('owner') or b in (r.get('aliases') or []) : return 'owner'
    if b == 'lead': return 'lead'
    if b.startswith('mgmt'): return 'mgmt'
    if b in ('sync','system','auto') or e.get('action')=='sync': return 'tool'
    return 'other-agent'
W = collections.Counter(who(r, e) for r, e in H); print('writer', W)
keys = collections.Counter(); 
klass = collections.Counter()
wk = collections.Counter()
for r, e in H:
    ch = e.get('changes') or {}
    ks = frozenset(ch.keys()); keys[tuple(sorted(ks))] += 1
    w = ch.get('waitingOn')
    if 'waitingOn' in ch: wk[(w or {}).get('kind') if isinstance(w, dict) else ('none' if w is None else str(w))] += 1
    # derivability classification of this write
    st = ch.get('state'); a = e.get('action')
    if a in ('created',): klass['create (title/kind/owner once)'] += 1; continue
    if a == 'priority': klass['priority (lead judgement)'] += 1; continue
    if a == 'sync' or (e.get('by')=='lead' and st in ('landed','done') ): klass['landed/done (git event)'] += 1; continue
    if isinstance(w, dict) and w.get('kind') in ('chrome','phone'): klass['wait chrome/phone (lock queue event)'] += 1; continue
    if isinstance(w, dict) and w.get('kind') in ('user','incident','item','review'): klass['wait user/incident/item/review (store event)'] += 1; continue
    if isinstance(w, dict) and w.get('kind') == 'lead': klass['wait lead (land request: event if a record)'] += 1; continue
    if st in ('measuring','testing'): klass['measuring/testing (hold event)'] += 1; continue
    if st in ('landed','done','closed-no-fix','dropped','parked','ready-to-land'): klass[f'terminal/park {st}'] += 1; continue
    if isinstance(w, dict) and w.get('kind') == 'agent': klass['wait agent (partly: wait record)'] += 1; continue
    if st: klass[f'state {st} (judgement)'] += 1; continue
    if set(ch) <= {'note','next'}: klass['note/next only (judgement text)'] += 1; continue
    klass['other: '+','.join(sorted(ch))[:60]] += 1
print('\nkey sets top'); [print(' ',v,k) for k,v in keys.most_common(15)]
print('\nwaitingOn kinds', wk.most_common())
print('\nclassification'); tot=sum(klass.values())
for k,v in klass.most_common(): print(f'  {v:5d} {100*v/tot:5.1f}%  {k}')
# per-day writes
day = collections.Counter(e['at'][:10] for _, e in H); print('\nper day', sorted(day.items()))
