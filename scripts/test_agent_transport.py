#!/usr/bin/env python3
import importlib.util
import io
import json
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('agent_transport', ROOT / 'one-agent.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


class TransportTest(unittest.TestCase):
    def integration(self, provider, allow, cancel=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            fixture = root/'provider'; shutil.copyfile(ROOT/'approval-fixture.py', fixture); fixture.chmod(0o700)
            prompt = 'cancel approval' if cancel else 'test approval'
            config = dict(provider=provider, executable=str(fixture), directory=folder, prompt=prompt,
                          claudeInput=dict(type='user', message=dict(role='user', content=[dict(type='text', text=prompt)])))
            (root/'config.json').write_text(json.dumps(config))
            process = subprocess.Popen(['/usr/bin/python3', str(ROOT/'one-agent.py'), folder], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            events = queue.Queue()
            def read():
                for line in process.stdout:
                    events.put(json.loads(line))
                events.put(None)
            threading.Thread(target=read, daemon=True).start()
            observed = []
            try:
                while True:
                    event = events.get(timeout=10)
                    if event is None: break
                    observed.append(event)
                    if event.get('type') == 'openone.approval':
                        self.assertFalse((root/'approval-receipt.json').exists(), 'provider waits for a real decision')
                        self.assertIn('printf fixture', event['details'])
                        if not cancel:
                            temporary = root/'decision.tmp'
                            temporary.write_text(json.dumps(dict(id=event['id'], allow=allow)))
                            temporary.rename(root/(event['id']+'.json'))
                process.wait(timeout=5)
                self.assertEqual(process.returncode, 0, process.stderr.read())
                self.assertEqual(sum(e['type']=='openone.approval' for e in observed), 1)
                self.assertEqual(sum(e['type']=='openone.approvalResolved' for e in observed), 1)
                if cancel:
                    self.assertFalse((root/'approval-receipt.json').exists())
                else:
                    result = json.loads((root/'approval-receipt.json').read_text())
                    decision = result['result']['decision'] if provider == 'Codex' else result['response']['response']['behavior']
                    self.assertEqual(decision, ('accept' if allow else 'decline') if provider=='Codex' else ('allow' if allow else 'deny'))
            finally:
                if process.poll() is None: process.terminate(); process.wait(timeout=5)
                process.stdout.close(); process.stderr.close()

    def test_codex_approve_once(self): self.integration('Codex', True)
    def test_codex_deny(self): self.integration('Codex', False)
    def test_claude_approve_exact_input(self): self.integration('Claude', True)
    def test_claude_deny(self): self.integration('Claude', False)
    def test_codex_cancellation(self): self.integration('Codex', False, cancel=True)
    def test_claude_cancellation(self): self.integration('Claude', False, cancel=True)

    def test_wrong_thread_and_unsupported_requests_never_approve(self):
        with tempfile.TemporaryDirectory() as folder:
            transport = module.Transport(dict(provider='Codex'), Path(folder))
            transport.thread_id='expected'; transport.turn_id='turn'
            writes=[]; transport.write=writes.append
            transport.codex(dict(id=1,method='item/commandExecution/requestApproval',params=dict(threadId='wrong',turnId='turn',command='test')))
            transport.codex(dict(id=2,method='item/commandExecution/requestApproval',params=dict(threadId='expected',turnId='stale',command='test')))
            self.assertEqual(transport.pending,{})
            self.assertTrue(all('error' in w for w in writes))

    def test_request_identity_and_boolean_are_required(self):
        with tempfile.TemporaryDirectory() as folder:
            transport=module.Transport(dict(provider='Claude'),Path(folder))
            transport.pending['local-id']=dict(wire_id='wire',request=dict(input={}),allow_enabled=True)
            writes=[]; transport.write=writes.append
            path=Path(folder)/'local-id.json'
            for bad in [dict(id='wrong',allow=True),dict(id='local-id',allow='true')]:
                path.write_text(json.dumps(bad))
                with self.assertRaises(RuntimeError):transport.decisions()
                self.assertEqual(writes,[])

    def test_repeated_decision_is_not_forwarded(self):
        with tempfile.TemporaryDirectory() as folder:
            transport=module.Transport(dict(provider='Codex'),Path(folder))
            transport.pending['local-id']=dict(wire_id=42,request={},allow_enabled=True)
            writes=[]; transport.write=writes.append
            path=Path(folder)/'local-id.json'
            for _ in range(2):
                path.write_text(json.dumps(dict(id='local-id',allow=True)));transport.decisions()
            self.assertEqual(writes,[dict(id=42,result=dict(decision='accept'))])


if __name__=='__main__':unittest.main()
