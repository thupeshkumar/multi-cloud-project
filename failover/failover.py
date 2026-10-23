"""Single-controller lab DNS failover. No external Python packages required."""
import argparse, json, os, time, urllib.request, ipaddress
from pathlib import Path

def request(url, method='GET', data=None, token=None):
    headers={'User-Agent':'multicloud-student-lab/1.0'}
    if token: headers['Authorization']='Bearer '+token
    if data is not None: headers['Content-Type']='application/json'
    req=urllib.request.Request(url, data=None if data is None else json.dumps(data).encode(),headers=headers,method=method)
    with urllib.request.urlopen(req,timeout=5) as r:
        return r.status, r.read()

def choose(origins, counts, threshold):
    return next((o for o in origins if counts[o['name']]>=threshold),None)

def run():
    p=argparse.ArgumentParser()
    p.add_argument('--origins',default='origins.json')
    p.add_argument('--interval',type=int,default=30)
    p.add_argument('--threshold',type=int,default=3)
    p.add_argument('--cooldown',type=int,default=180)
    p.add_argument('--dry-run',action='store_true')
    a=p.parse_args()
    if min(a.interval,a.threshold,a.cooldown)<1: p.error('Use positive values')
    origins=json.loads(Path(a.origins).read_text())
    if len({o['name'] for o in origins})!=len(origins): raise ValueError('Duplicate origin names')
    for o in origins: ipaddress.IPv4Address(o['ip'])
    counts={o['name']:0 for o in origins}; failures={o['name']:0 for o in origins}
    token=os.environ.get('CF_API_TOKEN','')
    endpoint='https://api.cloudflare.com/client/v4/zones/'+os.environ.get('CF_ZONE_ID','')+'/dns_records/'+os.environ.get('CF_RECORD_ID','')
    if not a.dry_run and not all(os.environ.get(k) for k in ['CF_API_TOKEN','CF_ZONE_ID','CF_RECORD_ID','CF_RECORD_NAME']):
        raise ValueError('Set CF_API_TOKEN, CF_ZONE_ID, CF_RECORD_ID, CF_RECORD_NAME')
    active=None; changed=0
    while True:
        for o in origins:
            try:
                status,body=request(o['url'])
                healthy=status==200 and body.decode().strip()=='healthy '+o['name']
            except Exception: healthy=False
            counts[o['name']]=counts[o['name']]+1 if healthy else 0
            failures[o['name']]=0 if healthy else failures[o['name']]+1
        try:
            if not a.dry_run:
                _,body=request(endpoint,token=token); response=json.loads(body)
                if not response.get('success'): raise RuntimeError('Cloudflare GET failed')
                record=response['result']
                if record['type']!='A' or record['name']!=os.environ['CF_RECORD_NAME'] or record['proxied']:
                    raise RuntimeError('Require the expected DNS only A record')
                active=record['content']
            candidate=choose(origins,counts,a.threshold)
            current=next((o for o in origins if o['ip']==active),None)
            # Keep current until three failed probes; stable preference enables delayed failback.
            current_bad=current is None or failures[current['name']]>=a.threshold
            current_good=current is not None and counts[current['name']]>=a.threshold
            if candidate and candidate['ip']!=active and (current_bad or current_good) and time.monotonic()-changed>=a.cooldown:
                if not a.dry_run:
                    _,body=request(endpoint,'PATCH',{'content':candidate['ip'],'ttl':60},token)
                    if not json.loads(body).get('success'): raise RuntimeError('Cloudflare PATCH failed')
                active=candidate['ip']; changed=time.monotonic()
                print(time.strftime('%Y-%m-%dT%H:%M:%S%z'),'selected',candidate['name'],active,'dry_run',a.dry_run,flush=True)
            if candidate is None: print('No confirmed healthy origin; DNS unchanged',flush=True)
            print('health_streaks',counts,'failure_streaks',failures,'active',active,flush=True)
        except Exception as e:
            print('DNS update/read failed:',type(e).__name__,str(e),flush=True)
        time.sleep(a.interval)

if __name__=='__main__': run()
