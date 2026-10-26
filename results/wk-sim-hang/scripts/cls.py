import json, os, re
base = os.path.dirname(os.path.abspath(__file__))
jobs = {str(j['job']): j for j in json.load(open(os.path.join(base, 'jobs.json')))}
TS = re.compile(r'(\d{4}-\d\d-\d\dT[\d:.]+)Z\s(.*)')
rows = []
for jid, j in jobs.items():
    if j['concl'] != 'failure':
        continue
    f = os.path.join(base, 'logs', jid + '.log')
    if not os.path.exists(f):
        rows.append((j['run'], jid, 'nolog')); continue
    txt = open(f).read()
    tags = []
    if 'event loop blocked' in txt and re.search(r'event loop blocked [1-9]', txt): tags.append('blocked')
    if 'error: stalled' in txt: tags.append('stalled')
    if 'measuring step bound' in txt: tags.append('stepbound')
    if re.search(r'Determinism sessions.*(cancel|timed out)', txt): tags.append('jobcancel')
    if 'the operation was canceled' in txt.lower() or 'has exceeded the maximum execution time' in txt.lower(): tags.append('timeout')
    m = [l for l in txt.split('\n') if ('error:' in l or 'Error:' in l) and '::error::' not in l]
    last = TS.search(m[-1]).group(2)[:110] if m and TS.search(m[-1]) else ''
    rows.append((j['run'], jid, ','.join(tags) or 'other', last))
for r in sorted(rows):
    print(*r, sep=' | ')
