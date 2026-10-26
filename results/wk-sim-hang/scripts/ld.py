import json,sys,os
base=os.path.dirname(os.path.abspath(__file__))
for f in sys.argv[1:]:
    d=json.load(open(os.path.join(base,f,'telemetry.json')))
    t0=d['times']['startedMs']
    boot=[s for s in d['steps'] if s['name'].startswith('Boot')][0]
    det=[s for s in d['steps'] if s['name'].startswith('Determinism sessions (start')][0]
    pr=d['probes']
    def at(sec):
        c=min(pr,key=lambda p:abs((p['atMs']-t0)/1000-sec)); return c['loadCenti']/100
    be=(boot['startMs']-t0)/1000
    print(f, d['ident']['runId'], d['ident']['job'], 'boot start',round(be),'end',round((boot['endMs']-t0)/1000),
      'load@bootstart',at(be),'@bootend',at((boot['endMs']-t0)/1000),'@det+300',at((det['startMs']-t0)/1000+300), 'max',max(p['loadCenti'] for p in pr)/100)
