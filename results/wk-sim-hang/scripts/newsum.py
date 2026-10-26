import json, os, re, sys
from datetime import datetime
base = os.path.dirname(os.path.abspath(__file__))
d = os.path.join(base, 'new')
TS = re.compile(r'(\d{4}-\d\d-\d\dT[\d:.]+)Z\s(.*)')
def ts(s): return datetime.strptime(s[:26], '%Y-%m-%dT%H:%M:%S.%f').timestamp()
out = []
for fn in sorted(os.listdir(d)):
    if not fn.endswith('.log'): continue
    ev = {}; att = []; loads = []; nofit = 0; hostrep = 0; stall = 0; blocked = []
    for ln in open(os.path.join(d, fn)):
        m = TS.search(ln)
        if not m: continue
        t = ts(m.group(1)); x = m.group(2).strip()
        if 'serving the' in x: ev.setdefault('serving', t)
        if 'proxy up:' in x: ev.setdefault('proxyUp', t)
        if x.startswith('warm-up 1/1'): ev.setdefault('warmDone', t)
        m2 = re.match(r'pass (\d)/2$', x)
        if m2: ev.setdefault('s' + m2.group(1), t)
        m3 = re.match(r'pass (\d)/2 written', x)
        if m3: ev['e' + m3.group(1)] = t
        if re.search(r'attempt \d failed', x) and 'no retry fits' not in x: att.append(x[:90])
        if 'no retry fits' in x: nofit += 1
        if 'is past the ceiling' in x: hostrep += 1
        if 'error: stalled' in x: stall += 1
        m4 = re.search(r'host load1 ([\d.]+) -> ([\d.]+)', x)
        if m4 and 'ceiling' not in x: loads.append((float(m4.group(1)), float(m4.group(2))))
        m5 = re.search(r'event loop blocked: the .* tick came (\d+) s late', x)
        if m5: blocked.append(int(m5.group(1)))
    g = lambda a, b: round(ev[b] - ev[a]) if a in ev and b in ev else None
    out.append(dict(job=fn[:-4], startS=g('serving', 'proxyUp'), warmS=g('proxyUp', 'warmDone'), pass1S=g('s1', 'e1'), pass2S=g('s2', 'e2'),
                    stepS=g('serving', 'e2'), retries=len(att), noRetryFits=nofit, hostRepeats=hostrep, stalls=stall, loads=loads,
                    blockedTicks=len(blocked), blockedMaxS=max(blocked) if blocked else 0))
for o in out: print(json.dumps(o))
json.dump(out, open(os.path.join(base, 'new-jobs.json'), 'w'))
