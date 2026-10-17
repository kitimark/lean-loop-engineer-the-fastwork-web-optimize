# Upkeep turns with blocking waits split out (class W). Reads calls.jsonl (made by scan.py); prints counts only.
import json, collections, sys
A = {'status_write','progress_write','lock_repair','step_runner','ledger_edit:fixes/PROGRESS.json','ledger_edit:ops-handover.md','incident_write_lead'}
B = {'lock_status','status_read','thread_read','step_read','incident_read','idle','usage','progress_read','proposal_read','finding_read','console_status_read'}
W = {'step_wait','thread_wait'}
c = collections.Counter()
for l in open(sys.argv[1] if len(sys.argv) > 1 else 'calls.jsonl'):
    r = json.loads(l); ctx = r['cr'] + r['cw']
    kinds = []
    for x in r['calls']:
        s = set()
        for k in x['cats']:
            if k == 'incident_write' and r['role'] == 'lead': k = 'incident_write_lead'
            s.add('A' if k in A else 'W' if k in W else 'B' if k in B else 'C')
        if not s: s = {'C'}
        kinds.append(s)
    c['turns'] += 1
    allk = set().union(*kinds) if kinds else {'C'}
    if 'C' in allk: continue
    c['upkeep_incl_wait'] += 1; c['ctx_incl_wait'] += ctx
    if 'A' in allk: c['A_turns'] += 1; c['A_ctx'] += ctx
    elif allk <= {'B'}: c['B_turns'] += 1; c['B_ctx'] += ctx
    elif allk <= {'W'}: c['W_turns'] += 1; c['W_ctx'] += ctx
    else: c['BW_turns'] += 1; c['BW_ctx'] += ctx
    if 'W' not in allk: c['upkeep_excl_wait'] += 1; c['ctx_excl_wait'] += ctx
for k, v in c.items(): print(k, round(v/1e9, 3), 'B' if 'ctx' in k else '') if 'ctx' in k else print(k, v)
