import json, collections
rows = [json.loads(l) for l in open('calls.jsonl')]
def role2(r):
    n=r['name'].lower(); ro=r['role']
    if ro!='other': return ro
    for p,x in [('int-','integrator'),('wi-','integrator'),('wave','integrator'),('art-','capture/artifact'),('cap-','capture/artifact'),('ver-','verifier'),('apple-verify','verifier'),('ops-','mgmt-ops'),('agent-a','unnamed')]:
        if n.startswith(p): return x
    return 'other'
A = {'status_write','progress_write','lock_repair','step_runner','ledger_edit:fixes/PROGRESS.json','ledger_edit:ops-handover.md','incident_write_lead'}
B = {'lock_status','status_read','thread_read','step_read','incident_read','idle','usage','progress_read','proposal_read','finding_read','step_wait','thread_wait','console_status_read'}
def cls(cats, role):
    s=set()
    for c in cats:
        if c=='incident_write' and role=='lead': c='incident_write_lead'
        if c in A: s.add('A')
        elif c in B: s.add('B')
        else: s.add('C')
    return s
agg = collections.defaultdict(lambda: collections.Counter())
for r in rows:
    ro = role2(r); n=len(r['calls'])
    per = [cls(c['cats'], r['role']) for c in r['calls']]
    a = sum(1 for p in per if 'A' in p); b = sum(1 for p in per if 'B' in p and 'A' not in p and 'C' not in p)
    book = sum(1 for p in per if p and p<= {'A','B'})
    g=agg[ro]; g['turns']+=1; g['out']+=r['out']; g['ctx']+=r['cr']+r['cw']
    g['A_calls']+=a; g['AB_calls']+=book
    if book==n:  # pure bookkeeping turn
        g['book_turns']+=1; g['book_out']+=r['out']; g['book_ctx']+=r['cr']+r['cw']
        if a: g['bookA_turns']+=1; g['bookA_ctx']+=r['cr']+r['cw']; g['bookA_out']+=r['out']
tot=collections.Counter()
print(f"{'role':18s} turns  A-calls  AB-calls  book-turns(%)  bookA-turns  book-out  book-ctx(M) ctx-all(M) ctx%")
for ro,g in sorted(agg.items(), key=lambda x:-x[1]['turns']):
    tot.update(g)
    print(f"{ro:18s} {g['turns']:6d} {g['A_calls']:6d} {g['AB_calls']:7d} {g['book_turns']:7d} ({100*g['book_turns']/g['turns']:4.1f}%) {g['bookA_turns']:7d} {g['book_out']:9d} {g['book_ctx']/1e6:9.1f} {g['ctx']/1e6:9.1f} {100*g['book_ctx']/max(1,g['ctx']):5.1f}")
g=tot; print(f"{'TOTAL':18s} {g['turns']:6d} {g['A_calls']:6d} {g['AB_calls']:7d} {g['book_turns']:7d} ({100*g['book_turns']/g['turns']:4.1f}%) {g['bookA_turns']:7d} {g['book_out']:9d} {g['book_ctx']/1e6:9.1f} {g['ctx']/1e6:9.1f} {100*g['book_ctx']/g['ctx']:5.1f}  bookA_ctx {g['bookA_ctx']/1e6:.1f}M bookA_out {g['bookA_out']}")
