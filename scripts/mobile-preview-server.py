#!/usr/bin/env python3
"""Loopback-only fixture using the production Open One bridge. No real user state."""
import argparse, importlib.util, os, pathlib, signal, time
workspace = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('remote', workspace/'scripts/one-remote.py')
remote = importlib.util.module_from_spec(spec); spec.loader.exec_module(remote)
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=pathlib.Path, default=workspace/'.build/mobile-preview')
parser.add_argument('--port', type=int, default=8088)
parser.add_argument('--command-response-delay', type=float, default=0)
args = parser.parse_args()
if not 0 <= args.command_response_delay <= 10: parser.error('Fixture response delay must be 0–10 seconds')
public_base = os.environ.get('OPEN_ONE_PREVIEW_ORIGIN', '')
server = remote.make_server(args.root, port=args.port, public_base=public_base, web_root=workspace/'mobile/dist')
class PreviewHandler(remote.Handler):
    def respond(self, value, code=200, content_type='application/json'):
        # Fixture-only: model a slow POST acknowledgement while delivery
        # receipts arrive over independent connections.
        if self.command == 'POST' and self.path == '/api/commands' and code == 202:
            time.sleep(args.command_response_delay)
        return super().respond(value, code, content_type)
server.RequestHandlerClass = PreviewHandler
# Local development keeps a known fixture link. Off-device tests get a fresh random token.
if not public_base:
    server.token = 'open-one-isolated-preview-0000000000000000'
remote.atomic_json(server.root/'remote-connection.json', dict(port=server.server_port,token=server.token,generation=server.generation,pid=os.getpid()))
def stop(*_): raise KeyboardInterrupt()
signal.signal(signal.SIGTERM, stop)
try: server.serve_forever(poll_interval=.2)
except KeyboardInterrupt: pass
finally:
    server.server_close()
    connection = server.root/'remote-connection.json'
    if (remote.read_json(connection, {}) or {}).get('generation') == server.generation:
        connection.unlink(missing_ok=True)
