#!/usr/bin/env python3
"""Opt-in, authenticated LAN phone bridge; loopback is available for local tests."""
import argparse, base64, hmac, http.server, ipaddress, json, mimetypes, os, pathlib, secrets, signal, socket, threading, time, urllib.parse, uuid

HTML = '''<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Open One</title><link rel="icon" type="image/png" sizes="64x64" href="/favicon.png"><link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png"><link rel="stylesheet" href="/style.css"></head><body><header><h1><img src="/logo.png" width="40" height="40" alt="">Open One</h1><button id="disconnect">Disconnect</button></header><p id="status">Connecting…</p><main id="agents"></main><script src="/app.js"></script></body></html>'''
CSS = '''body{color:#eee;background:#111;font:15px system-ui;margin:auto;max-width:720px;padding:22px}header,.row{display:flex;align-items:center;justify-content:space-between;gap:12px}h1{font-size:25px}article{background:#202124;border:1px solid #ffffff30;border-radius:20px;padding:20px;margin:18px 0}p{white-space:pre-wrap;overflow-wrap:anywhere}.muted,#status{color:#aaa;font-size:13px}button,textarea{font:inherit;color:inherit;border:1px solid #ffffff40;border-radius:12px;background:#303136;padding:12px}button{cursor:pointer}button:disabled{opacity:.4}textarea{box-sizing:border-box;width:100%;min-height:85px;margin:10px 0}h2{font-size:17px;margin:0}details{margin:15px 0}.answer{display:flex;flex-wrap:wrap;gap:8px}'''
JS = r'''let token=location.hash.slice(1)||sessionStorage.getItem('openone-token');history.replaceState(null,'',location.pathname);if(token)sessionStorage.setItem('openone-token',token);const status=document.querySelector('#status'),agents=document.querySelector('#agents');document.querySelector('#disconnect').onclick=()=>{token=null;sessionStorage.removeItem('openone-token');agents.replaceChildren();status.textContent='Disconnected on this browser. Stop remote access on your Mac to revoke all links.'};async function api(path,body){let r=await fetch(path,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+token,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,cache:'no-store'});let value=await r.json();if(!r.ok)throw Error(value.error||'Request failed');return value}function el(tag,text,cls){let n=document.createElement(tag);n.textContent=text||'';if(cls)n.className=cls;return n}async function send(a,text,choice,button){button.disabled=true;try{let v=await api('/api/commands',{agentID:a.id,requestID:a.requestID||null,conversationKey:a.conversationKey,text,choiceIndex:choice??null});status.textContent='Waiting for your Mac…';setTimeout(async()=>{try{let r=await api('/api/receipts/'+v.id);status.textContent=r.message||r.status}catch(e){status.textContent=e.message}},750)}catch(e){status.textContent=e.message}finally{button.disabled=false}}async function refresh(){if(!token){status.textContent='Open the connection link from your Mac.';return}try{let state=await api('/api/state');if(document.activeElement?.tagName==='TEXTAREA')return;agents.replaceChildren();status.textContent=state.agents.length?'Connected to your Mac':'No conversations yet.';for(let a of state.agents){let card=el('article'),head=el('div',null,'row');head.append(el('h2',a.name),el('span',a.state,'muted'));card.append(head,el('p',a.title,'muted'));let history=el('details');history.append(el('summary','Conversation'));for(let m of a.messages)history.append(el('p',m.role+': '+m.text));card.append(history);if(a.canReceive){let choices=el('div',null,'answer');a.choices.forEach((v,i)=>{let b=el('button',v);b.onclick=()=>send(a,v,i,b);choices.append(b)});let input=el('textarea');input.placeholder='Reply to '+a.name;input.setAttribute('aria-label','Reply to '+a.name);let b=el('button','Send');b.onclick=()=>{if(input.value.trim())send(a,input.value,null,b)};card.append(choices,input,b)}else card.append(el('p',a.state==='working'?'Agent is working.':'Read-only observed conversation. Continue in its terminal or fork it on your Mac.','muted'));agents.append(card)}}catch(e){status.textContent=e.message}}refresh();setInterval(refresh,3000);'''


CSS += 'h1{display:flex;align-items:center;gap:10px}h1 img{object-fit:contain;flex-shrink:0}'


def logo_path(filename='open-one-logo.png'):
    directory = pathlib.Path(__file__).resolve().parent
    bundled = directory / filename
    return bundled if bundled.is_file() else directory.parent / 'Sources' / 'OpenOne' / 'Assets' / filename


def atomic_json(path, value):
    path = pathlib.Path(path); path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_name('.' + uuid.uuid4().hex + '.tmp')
    fd = os.open(temp, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w') as out: json.dump(value, out)
    os.replace(temp, path)


def read_json(path, default=None):
    try:
        if path.stat().st_size > 8_000_000: return default
        return json.loads(path.read_text())
    except (OSError, ValueError): return default


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'
    def log_message(self, *_): pass
    def setup(self):
        super().setup(); self.connection.settimeout(5)
    def respond(self, value, code=200, content_type='application/json'):
        data = value if isinstance(value, bytes) else json.dumps(value).encode() if content_type == 'application/json' else value.encode()
        self.send_response(code); self.send_header('Content-Type', content_type); self.send_header('Content-Length', str(len(data)))
        style_policy = "'self' 'unsafe-inline'" if self.server.web_root else "'self'"
        for k,v in [('Cache-Control','no-store'),('X-Content-Type-Options','nosniff'),('Referrer-Policy','no-referrer'),('Content-Security-Policy',f"default-src 'self'; script-src 'self'; style-src {style_policy}; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")]: self.send_header(k,v)
        self.end_headers(); self.wfile.write(data)
    def authorized(self):
        host = self.headers.get('Host','').lower()
        if host not in self.server.hosts:
            self.respond({'error':'Host not allowed'},403); return False
        origin = self.headers.get('Origin')
        if origin and origin not in self.server.origins:
            self.respond({'error':'Origin not allowed'},403); return False
        token = self.headers.get('Authorization','').removeprefix('Bearer ')
        if not hmac.compare_digest(token.encode(), self.server.token.encode()):
            self.respond({'error':'Connection expired. Open a new connection link from your Mac.'},401); return False
        return True
    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if self.server.web_root and not path.startswith('/api/'):
            if self.headers.get('Host','').lower() not in self.server.hosts: return self.respond({'error':'Host not allowed'},403)
            name = 'index.html' if path in ('/', '/conversations', '/chat') else urllib.parse.unquote(path).lstrip('/')
            target = (self.server.web_root / name).resolve()
            if not target.is_relative_to(self.server.web_root) or not target.is_file(): return self.respond({'error':'Not found'},404)
            return self.respond(target.read_bytes(), content_type=mimetypes.guess_type(str(target))[0] or 'application/octet-stream')
        brand_assets = {'/logo.png':'open-one-logo.png', '/favicon.png':'open-one-favicon.png', '/apple-touch-icon.png':'open-one-touch-icon.png'}
        if path in brand_assets:
            if self.headers.get('Host','').lower() not in self.server.hosts: return self.respond({'error':'Host not allowed'},403)
            try: data = logo_path(brand_assets[path]).read_bytes()
            except OSError: return self.respond({'error':'Not found'},404)
            return self.respond(data, content_type='image/png')
        public = {'/':(HTML,'text/html; charset=utf-8'),'/style.css':(CSS,'text/css'),'/app.js':(JS,'application/javascript')}
        if path in public:
            if self.headers.get('Host','').lower() not in self.server.hosts: return self.respond({'error':'Host not allowed'},403)
            return self.respond(*[public[path][0]],content_type=public[path][1])
        if not self.authorized(): return
        if path == '/api/info': return self.respond({'app':'open-one','protocolVersion':2,'generation':self.server.generation})
        if path == '/api/state': return self.respond(read_json(self.server.root/'remote-state.json', {'agents':[]}))
        if path.startswith('/api/conversations/'):
            ident = urllib.parse.unquote(path[len('/api/conversations/'):])
            state = read_json(self.server.root/'remote-state.json', {'agents':[]})
            agent = next((a for a in state['agents'] if a['id'] == ident), None)
            if not agent: return self.respond({'error':'This conversation is no longer tracked. Return to conversations.'},404)
            return self.respond(agent)
        if path.startswith('/api/receipts/'):
            try: ident = str(uuid.UUID(path.rsplit('/',1)[1]))
            except ValueError: return self.respond({'error':'Invalid request ID'},400)
            return self.respond(read_json(self.server.root/'remote-receipts'/f'{ident}.json', {'status':'unknown','message':'No receipt yet. Check your Mac before trying again.'}))
        if path.startswith('/api/replies/'):
            request = urllib.parse.unquote(path[len('/api/replies/'):])
            if len(request)>256: return self.respond({'error':'Invalid request ID'},400)
            filename = base64.urlsafe_b64encode(request.encode()).decode().rstrip('=') + '.json'
            reply = read_json(self.server.root/'replies'/filename)
            return self.respond(reply if reply else {'pending':True})
        self.respond({'error':'Not found'},404)
    def do_POST(self):
        if not self.authorized(): return
        if self.headers.get('Content-Type','').split(';')[0] != 'application/json': return self.respond({'error':'JSON required'},415)
        try:
            size = int(self.headers.get('Content-Length','0'))
            if not 0 < size <= 65536: return self.respond({'error':'Request too large or empty'},413)
            body = json.loads(self.rfile.read(size))
            if not isinstance(body,dict): raise ValueError()
        except (ValueError, socket.timeout): return self.respond({'error':'Invalid request'},400)
        path = urllib.parse.urlsplit(self.path).path
        # Browser preconnects and reads can proceed independently. Serialize
        # validation + durable writes so concurrent sends cannot race dedup.
        with self.server.command_lock:
            return self.accept_post(path, body)
    def accept_post(self, path, body):
        if path == '/api/commands':
            # Client-generated IDs allow a lost HTTP response to be reconciled without replaying a send.
            try: ident = str(uuid.UUID(body['operationID'])) if 'operationID' in body else str(uuid.uuid4())
            except (ValueError, TypeError, AttributeError): return self.respond({'error':'Invalid operation ID'},400)
            canonical = {key: body.get(key) for key in ['agentID','requestID','text','choiceIndex','conversationKey']}
            operation = self.server.root/'remote-operations'/f'{ident}.json'
            previous = read_json(operation)
            if previous:
                if previous.get('generation') != self.server.generation or previous.get('request') != canonical:
                    return self.respond({'error':'Operation ID already used for another message.'},409)
                return self.respond({'id':ident,'status':'queued'},202)
            state = read_json(self.server.root/'remote-state.json', {'agents':[]})
            agent = next((a for a in state['agents'] if a['id']==body.get('agentID')),None)
            if not agent or not agent.get('canReceive'): return self.respond({'error':'This agent cannot receive a reply now.'},409)
            if agent.get('conversationKey') and agent.get('conversationKey') != body.get('conversationKey'): return self.respond({'error':'This conversation changed. Reopen it before replying.'},409)
            if agent.get('requestID') != body.get('requestID'): return self.respond({'error':'That question has changed. Refresh before replying.'},409)
            if not isinstance(body.get('text'),str) or not body['text'].strip() or len(body['text'])>32000: return self.respond({'error':'Enter a message of at most 32,000 characters.'},400)
            choice = body.get('choiceIndex')
            if choice is not None and (type(choice) is not int or not 0<=choice<len(agent.get('choices',[])) or agent['choices'][choice]!=body['text']): return self.respond({'error':'That choice is no longer available.'},409)
            commands = self.server.root/'remote-commands'
            if sum(1 for _ in commands.glob('*.json')) >= 20: return self.respond({'error':'Too many pending replies. Wait for the Mac.'},429)
            atomic_json(operation, {'generation':self.server.generation,'request':canonical})
            atomic_json(self.server.root/'remote-receipts'/f'{ident}.json', {'status':'queued','message':'Waiting for your Mac.'})
            atomic_json(commands/f'{ident}.json', dict(id=ident, agentID=agent['id'], requestID=body.get('requestID'), text=body['text'], choiceIndex=choice, conversationKey=agent.get('conversationKey'), createdAt=time.time(), generation=self.server.generation))
            return self.respond({'id':ident,'status':'queued'},202)
        if path == '/api/events':
            if body.get('kind') not in ['register','working','question','message','done','offline']: return self.respond({'error':'Invalid event kind'},400)
            if not isinstance(body.get('agentID'),str) or not 0<len(body['agentID'])<=100: return self.respond({'error':'Invalid agent'},400)
            if not isinstance(body.get('text',''),str) or len(body.get('text',''))>32000: return self.respond({'error':'Invalid text'},400)
            request = body.get('requestID')
            if body['kind']=='question' and (not isinstance(request,str) or not 0<len(request)<=256 or not body.get('text','').strip()): return self.respond({'error':'Question needs text and a request ID'},400)
            choices = body.get('choices',[])
            if not isinstance(choices,list) or len(choices)>20 or any(not isinstance(x,str) or len(x)>2000 for x in choices): return self.respond({'error':'Invalid choices'},400)
            if sum(1 for _ in (self.server.root/'events').glob('*.json')) >= 100: return self.respond({'error':'Event queue full'},429)
            event = dict(id=str(uuid.uuid4()),agentID='remote:'+body['agentID'],kind=body['kind'],text=body.get('text',''),choices=choices,requestID=request)
            for key in ['name','provider']:
                if isinstance(body.get(key),str): event[key]=body[key][:100]
            atomic_json(self.server.root/'events'/f"remote-{uuid.uuid4()}.json",event)
            return self.respond({'accepted':True},202)
        self.respond({'error':'Not found'},404)


def make_server(root, port=0, public_base='', web_root=None, lan_address=''):
    root = pathlib.Path(root); root.mkdir(parents=True, exist_ok=True, mode=0o700)
    for child in ['remote-commands','remote-receipts','remote-operations','events','replies']: (root/child).mkdir(exist_ok=True, mode=0o700)
    base = urllib.parse.urlsplit(public_base)
    if public_base and (base.scheme!='https' or not base.hostname or base.username or base.password or base.path not in ('','/') or base.query or base.fragment): raise ValueError('Expected an HTTPS origin')
    if lan_address:
        address = ipaddress.IPv4Address(lan_address)
        if not any(address in ipaddress.IPv4Network(network) for network in ['10.0.0.0/8','172.16.0.0/12','192.168.0.0/16']):
            raise ValueError('Expected a LAN IPv4 address')
        if public_base: raise ValueError('Use either a LAN address or an HTTPS origin')
    server = http.server.ThreadingHTTPServer((lan_address or '127.0.0.1',port),Handler)
    server.command_lock = threading.Lock()
    server.web_root = pathlib.Path(web_root).resolve() if web_root else None
    server.root=root; server.token=secrets.token_urlsafe(32); server.generation=secrets.token_hex(16)
    port=server.server_port; server.hosts={f'127.0.0.1:{port}',f'localhost:{port}'}
    server.origins={f'http://{host}' for host in server.hosts}
    if public_base:
        server.hosts.add(urllib.parse.urlsplit(public_base).netloc.lower()); server.origins.add(public_base.rstrip('/'))
    if lan_address:
        public_base = f'http://{lan_address}:{port}'
        server.hosts = {f'{lan_address}:{port}'}
        server.origins = {public_base}
    atomic_json(root/'remote-state.json', {'agents':[]})
    connection = dict(port=port,token=server.token,generation=server.generation,pid=os.getpid())
    if lan_address: connection.update(publicBase=public_base, transport='lan', listenHost=lan_address)
    atomic_json(root/'remote-connection.json',connection)
    return server


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--root',required=True); parser.add_argument('--port',type=int,default=0); parser.add_argument('--web-root'); parser.add_argument('--lan-address',default='')
    args=parser.parse_args(); server=make_server(args.root,args.port,web_root=args.web_root,lan_address=args.lan_address)
    def stop(*_): raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM,stop)
    try: server.serve_forever(poll_interval=.2)
    except KeyboardInterrupt: pass
    finally:
        server.server_close()
        connection=pathlib.Path(args.root)/'remote-connection.json'
        if (read_json(connection,{}) or {}).get('generation')==server.generation: connection.unlink(missing_ok=True)
if __name__=='__main__': main()
