#!/usr/bin/env python3
"""Publish a remote agent to Open One through HTTPS or an SSH loopback tunnel."""
import argparse, json, os, sys, time, urllib.error, urllib.parse, urllib.request, uuid

def main():
    p=argparse.ArgumentParser(); p.add_argument('--url',required=True); p.add_argument('--agent',required=True); p.add_argument('--name'); p.add_argument('--provider',default='Remote agent'); p.add_argument('--kind',choices=['register','working','question','message','done','offline'],default='message'); p.add_argument('--text',default=''); p.add_argument('--option',action='append',default=[]); p.add_argument('--timeout',type=int,default=300)
    a=p.parse_args(); parsed=urllib.parse.urlsplit(a.url)
    if parsed.scheme!='https' and not(parsed.scheme=='http' and parsed.hostname in ('127.0.0.1','localhost')): p.error('Use HTTPS or an SSH-forwarded localhost URL.')
    if parsed.username or parsed.password or parsed.fragment or parsed.query: p.error('Use a base URL without credentials; put the token in OPEN_ONE_REMOTE_TOKEN.')
    token=os.environ.get('OPEN_ONE_REMOTE_TOKEN');
    if not token: p.error('Set OPEN_ONE_REMOTE_TOKEN to the token from your connection link.')
    def request(path,body=None):
        req=urllib.request.Request(a.url.rstrip('/')+path,data=json.dumps(body).encode() if body else None,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=10) as response: return json.load(response)
    request_id=str(uuid.uuid4()) if a.kind=='question' else None
    request('/api/events',dict(agentID=a.agent,name=a.name or a.agent,provider=a.provider,kind=a.kind,text=a.text,choices=a.option,requestID=request_id))
    if request_id:
        deadline=time.monotonic()+max(1,a.timeout)
        while time.monotonic()<deadline:
            value=request('/api/replies/'+urllib.parse.quote(request_id,safe=''))
            if not value.get('pending'): print(json.dumps(value)); return 0
            time.sleep(1)
        print('Timed out without a reply. No decision was made.',file=sys.stderr); return 2
    print('Event accepted by Open One.'); return 0
if __name__=='__main__':
    try: sys.exit(main())
    except (OSError,ValueError) as e: print('Remote connection failed: '+str(e),file=sys.stderr); sys.exit(1)
