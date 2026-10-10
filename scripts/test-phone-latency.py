#!/usr/bin/env python3
"""Time the production bridge + Store + isolated provider. No real chats or API calls."""
import argparse, importlib.util, json, pathlib, socket, statistics, subprocess, tempfile, threading, time, urllib.request, uuid

workspace = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('remote', workspace/'scripts/one-remote.py')
remote = importlib.util.module_from_spec(spec); spec.loader.exec_module(remote)
parser = argparse.ArgumentParser()
parser.add_argument('--receipt-ms', type=int, default=250)
parser.add_argument('--preflight', action='store_true')
parser.add_argument('--samples', type=int, default=5)
parser.add_argument('--address', default='')
parser.add_argument('--output', type=pathlib.Path)
parser.add_argument('--probe-idle', action='store_true')
args = parser.parse_args()
samples = []
with tempfile.TemporaryDirectory(prefix='open-one-phone-latency-') as folder:
    root = pathlib.Path(folder)
    server = remote.make_server(root, lan_address=args.address)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    origin = f'http://{args.address or "127.0.0.1"}:{server.server_port}'
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def request(path, body=None):
        req = urllib.request.Request(origin+path, data=None if body is None else json.dumps(body).encode(),
            headers={'Authorization':'Bearer '+server.token, 'Content-Type':'application/json'})
        with opener.open(req, timeout=5) as response: return json.load(response)
    if args.probe_idle:
        try:
            with socket.create_connection(server.server_address,timeout=5):
                time.sleep(.05)
                start=time.monotonic();request('/api/info')
                result=dict(fixtureOnly=True, idleBrowserConnectionMs=round((time.monotonic()-start)*1000,1))
                if args.output: args.output.write_text(json.dumps(result,indent=2)+'\n')
                print(json.dumps(result,indent=2))
        finally:
            server.shutdown();server.server_close();thread.join()
        raise SystemExit(0)
    host = subprocess.Popen([str(workspace/'.build/phone-latency/host'), str(root)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        for index in range(args.samples):
            end = time.monotonic()+15
            while time.monotonic()<end:
                agents = request('/api/state')['agents']
                if agents and agents[0]['canReceive']: break
                assert host.poll() is None, 'Fixture host exited'
                time.sleep(.05)
            else: raise AssertionError('Fixture did not become ready')
            selected = agents[0]
            # Vary arrival within the desktop polling period.
            time.sleep(.07 * index)
            start = time.monotonic()
            if args.preflight: selected = request('/api/state')['agents'][0]
            ident = str(uuid.uuid4())
            body = dict(operationID=ident, agentID=selected['id'], conversationKey=selected['conversationKey'],
                requestID=selected['requestID'], text=f'Isolated latency sample {index}', choiceIndex=None)
            assert request('/api/commands',body)['id'] == ident
            accepted = time.monotonic()
            observed = None
            next_receipt = start
            while time.monotonic()-start<12:
                now = time.monotonic()
                if now>=next_receipt:
                    receipt = request('/api/receipts/'+ident)
                    assert receipt['status'] not in ('rejected','uncertain'), receipt
                    if receipt['status']=='delivered': observed = time.monotonic(); break
                    next_receipt = now+args.receipt_ms/1000
                time.sleep(.01)
            assert observed is not None, 'Delivery was not confirmed'
            assert len(list((root/'remote-operations').glob('*.json'))) == index+1
            # A repeat operation cannot run the provider again after delivery.
            assert request('/api/commands',body)['id'] == ident
            assert not list((root/'remote-commands').glob('*.json'))
            samples.append(dict(httpAcceptedMs=round((accepted-start)*1000,1), confirmedMs=round((observed-start)*1000,1)))
        result = dict(fixtureOnly=True, physicalPhoneVerified=False, transport='LAN' if args.address else 'loopback',
            desktopPollMs=500, receiptPollMs=args.receipt_ms, preflight=args.preflight, samples=samples,
            medianConfirmedMs=round(statistics.median(x['confirmedMs'] for x in samples),1),
            maxConfirmedMs=max(x['confirmedMs'] for x in samples), duplicateCommands=0)
        if args.output: args.output.write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result,indent=2))
    finally:
        host.terminate(); host.wait(timeout=10)
        server.shutdown(); server.server_close(); thread.join()
