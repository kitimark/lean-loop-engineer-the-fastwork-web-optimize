import json, collections, sys
rows = [json.loads(l) for l in open('calls.jsonl')]
C = collections.Counter(); R = collections.defaultdict(collections.Counter); names=collections.Counter()
tot_calls = 0; tot_out = 0; tot_turns = len(rows)
role_calls = collections.Counter(); role_turns = collections.Counter(); role_out=collections.Counter()
cons_calls = collections.Counter(); cons_turns_any=collections.Counter(); cons_turns_only=collections.Counter()
cons_out_share=collections.Counter(); cons_res=collections.Counter(); cons_cr_only=collections.Counter(); role_cr=collections.Counter()
WRITE = lambda c: c.endswith('_write') or c in ('step_runner','lock_repair') or c.startswith('ledger_edit')
POLL = lambda c: c.endswith('_read') or c.endswith('_wait') or c in ('lock_status','usage','idle')
cat_role = collections.defaultdict(collections.Counter)
for r in rows:
    role = r['role']; n = len(r['calls']); role_turns[role]+=1; role_out[role]+=r['out']; role_cr[role]+=r['cr']
    k = sum(1 for c in r['calls'] if c['cats'])
    role_calls[role]+=n
    for c in r['calls']:
        for cat in c['cats']:
            C[cat]+=1; cat_role[cat][role]+=1
        if c['cats']:
            cons_calls[role]+=1; cons_res[role]+=c['res']
    if k: 
        cons_turns_any[role]+=1; cons_out_share[role]+= r['out']*k/n
        if k==n: cons_turns_only[role]+=1; cons_cr_only[role]+=r['cr']+r['cw']
print('categories (calls; a call can be in >1):')
for cat,v in C.most_common(): print(f'  {cat:40s} {v:6d}  ', dict(cat_role[cat].most_common(5)))
print('\nrole: tool-turns, tool-calls, console-calls, turns-with-console, turns-only-console, out tokens all, out share console, result chars console, ctx tokens (cacheRead+write) of only-console turns, ctx all')
for role in sorted(role_turns, key=lambda x:-role_turns[x]):
    print(f'  {role:12s} {role_turns[role]:6d} {role_calls[role]:7d} {cons_calls[role]:6d} {cons_turns_any[role]:6d} {cons_turns_only[role]:6d} {role_out[role]:10d} {int(cons_out_share[role]):9d} {cons_res[role]:10d} {cons_cr_only[role]:13d} {role_cr[role]:14d}')
T=lambda d: sum(d.values())
print('TOTAL', T(role_turns), T(role_calls), T(cons_calls), T(cons_turns_any), T(cons_turns_only), T(role_out), int(T(cons_out_share)), T(cons_res), T(cons_cr_only), T(role_cr))
