#!/usr/bin/env python3
"""Bidirectional provider transport for one Open One managed turn.

Speaks Codex app-server JSON-RPC and Claude's stream-json control protocol.
Approval decisions come only from owner-private, exact-request response files.
No permission bypass flags, persistent allow rules, or terminal injection.
"""
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import threading
import time
import uuid

MAX_EVENT = 8 * 1024 * 1024


def emit(kind, **fields):
    print(json.dumps(dict(type=kind, **fields)), flush=True)


class Transport:
    def __init__(self, config, root):
        self.config, self.root = config, root
        self.provider = config['provider']
        self.process = None
        self.events = queue.Queue(maxsize=128)
        self.pending = {}
        self.items = {}
        self.thread_id = None
        self.turn_id = None
        self.ready = False
        self.ended = False
        self.failed = False
        self.sequence = 0
        self.rpcs = {}
        self.result_seen = False
        self.tasks = set()
        self.session_state = None

    def write(self, value):
        self.process.stdin.write((json.dumps(value) + '\n').encode())
        self.process.stdin.flush()

    def rpc(self, method, params, tag):
        self.sequence += 1
        key = 'openone-' + str(self.sequence)
        self.rpcs[key] = tag
        self.write(dict(id=key, method=method, params=params))

    def reader(self):
        try:
            while True:
                data = self.process.stdout.readline(MAX_EVENT + 1)
                if not data:
                    break
                if len(data) > MAX_EVENT:
                    raise RuntimeError('The provider returned an oversized event.')
                try:
                    value = json.loads(data)
                except (ValueError, UnicodeError):
                    continue
                if isinstance(value, dict):
                    self.events.put(value)
        except Exception as error:
            self.events.put(dict(type='transport_error', message=str(error)))
        finally:
            self.events.put(None)

    def approve_request(self, wire_id, request, title, details, allow_enabled=True):
        if any(p['wire_id'] == wire_id for p in self.pending.values()):
            raise RuntimeError('The provider reused an outstanding approval ID.')
        local_id = str(uuid.uuid4())
        # Keep the complete request for the response; never reconstruct tool input
        # from displayed text or from a model-generated answer.
        self.pending[local_id] = dict(wire_id=wire_id, request=request, allow_enabled=allow_enabled)
        emit('openone.approval', id=local_id, title=title,
             details=details if isinstance(details, str) else json.dumps(details, indent=2, ensure_ascii=False), allowEnabled=allow_enabled)

    def cancel_request(self, wire_id):
        for local_id, pending in list(self.pending.items()):
            if pending['wire_id'] == wire_id:
                del self.pending[local_id]
                emit('openone.approvalResolved', id=local_id)

    def decisions(self):
        for local_id, pending in list(self.pending.items()):
            path = self.root / (local_id + '.json')
            if not path.exists():
                continue
            if path.is_symlink() or path.stat().st_size > 4096:
                raise RuntimeError('Invalid approval response file.')
            result = json.loads(path.read_text())
            path.unlink()
            if result.get('id') != local_id or type(result.get('allow')) is not bool:
                raise RuntimeError('Approval identity did not match the pending request.')
            allow = result['allow'] and pending['allow_enabled']
            if self.provider == 'Codex':
                self.write(dict(id=pending['wire_id'], result=dict(decision='accept' if allow else 'decline')))
            else:
                response = (dict(behavior='allow', updatedInput=pending['request']['input']) if allow
                            else dict(behavior='deny', message='The user denied this request in Open One.'))
                self.write(dict(type='control_response', response=dict(subtype='success',
                           request_id=pending['wire_id'], response=response)))
            del self.pending[local_id]
            emit('openone.approvalResolved', id=local_id)

    def codex(self, event):
        method, params = event.get('method'), event.get('params') or {}
        if 'id' in event and method:
            if params.get('threadId') != self.thread_id:
                self.write(dict(id=event['id'], error=dict(code=-32602, message='Unexpected approval thread.')))
                return
            if self.turn_id and params.get('turnId') != self.turn_id:
                self.write(dict(id=event['id'], error=dict(code=-32602, message='Expired approval turn.')))
                return
            if method in ('item/commandExecution/requestApproval', 'item/fileChange/requestApproval'):
                item = self.items.get(params.get('itemId'), {})
                command = method == 'item/commandExecution/requestApproval'
                if command:
                    details = str(params.get('command') or 'Network access request')
                    if params.get('cwd'): details += '\n\nWorking directory: ' + params['cwd']
                    if params.get('reason'): details += '\n\nWhy permission is needed:\n' + params['reason']
                    for key in ('additionalPermissions', 'networkApprovalContext'):
                        if params.get(key): details += '\n\nRequested access:\n' + json.dumps(params[key], indent=2)
                else:
                    details = dict(files=item.get('changes', []), reason=params.get('reason'), requestedRoot=params.get('grantRoot'))
                available = params.get('availableDecisions')
                allowed = (bool(params.get('command') or params.get('networkApprovalContext')) if command else bool(item.get('changes')))
                if available is not None:
                    allowed = allowed and 'accept' in available
                self.approve_request(event['id'], params,
                                     'Run command?' if command else 'Allow file changes?', details, allowed)
            else:
                self.write(dict(id=event['id'], error=dict(code=-32601, message='This approval type is not supported in Open One.')))
                emit('error', message='Codex requested an unsupported interaction: ' + str(method) + '. Continue in its CLI if needed.')
            return
        if 'id' in event and event['id'] in self.rpcs:
            tag = self.rpcs.pop(event['id'])
            if 'error' in event:
                raise RuntimeError(str(event['error'].get('message', event['error'])))
            result = event.get('result') or {}
            if tag == 'initialize':
                self.write(dict(method='initialized'))
                params = dict(cwd=self.config['directory'])
                if self.config.get('sessionID'):
                    params['threadId'] = self.config['sessionID']
                    method = 'thread/resume'
                elif self.config.get('forkSessionID'):
                    params['threadId'] = self.config['forkSessionID']
                    method = 'thread/fork'
                else:
                    method = 'thread/start'
                self.rpc(method, params, 'thread')
            elif tag == 'thread':
                self.thread_id = result['thread']['id']
                expected = self.config.get('sessionID')
                if expected and expected != self.thread_id:
                    raise RuntimeError('Codex resumed a different conversation.')
                emit('thread.started', thread_id=self.thread_id)
                inputs = [dict(type='text', text=self.config['prompt'], text_elements=[])]
                if self.config.get('image'):
                    inputs.append(dict(type='localImage', path=self.config['image']))
                self.rpc('turn/start', dict(threadId=self.thread_id, input=inputs), 'turn')
            elif tag == 'turn':
                self.turn_id = result['turn']['id']
                self.ready = True
            return
        if params.get('threadId') != self.thread_id:
            return
        if method == 'item/started':
            item = params.get('item') or {}
            self.items[item.get('id')] = item
            if item.get('type') == 'commandExecution':
                emit('item.completed', item=dict(type='activity', command=item.get('command', 'Running command')))
        elif method == 'item/completed':
            item = params.get('item') or {}
            if item.get('type') == 'agentMessage':
                emit('item.completed', item=dict(type='agent_message', text=item.get('text', '')))
        elif method == 'serverRequest/resolved':
            self.cancel_request(params.get('requestId'))
        elif method == 'turn/completed':
            turn = params.get('turn') or {}
            if self.turn_id and turn.get('id') != self.turn_id:
                return
            if turn.get('status') != 'completed':
                self.failed = True
                emit('error', message=str((turn.get('error') or {}).get('message') or 'Codex did not complete the turn.'))
            self.ended = True
        elif method == 'error' and not params.get('willRetry', False):
            raise RuntimeError(str((params.get('error') or {}).get('message') or 'Codex reported an error.'))

    def claude(self, event):
        kind = event.get('type')
        if kind == 'control_response':
            response = event.get('response') or {}
            if response.get('request_id') == 'openone-init':
                if response.get('subtype') != 'success':
                    raise RuntimeError(str(response.get('error') or 'Claude could not initialize approvals.'))
                self.ready = True
                self.write(self.config['claudeInput'])
        elif kind == 'control_request':
            request = event.get('request') or {}
            if request.get('subtype') == 'can_use_tool' and isinstance(request.get('input'), dict):
                details = dict(input=request['input'])
                for key in ('decision_reason', 'blocked_path', 'description'):
                    if request.get(key): details[key] = request[key]
                if request.get('tool_name') == 'Bash' and isinstance(request['input'].get('command'), str):
                    extra = {key: value for key, value in request['input'].items() if key != 'command'}
                    details = request['input']['command']
                    if extra: details += '\n\n' + json.dumps(extra, indent=2, ensure_ascii=False)
                    for key in ('decision_reason', 'blocked_path'):
                        if request.get(key): details += '\n\n' + key.replace('_', ' ').capitalize() + ': ' + str(request[key])
                self.approve_request(event['request_id'], request, 'Allow ' + str(request.get('tool_name', 'tool')) + '?',
                                     details, request.get('tool_name') != 'AskUserQuestion')
            else:
                self.write(dict(type='control_response', response=dict(subtype='error', request_id=event.get('request_id'),
                           error='This interaction is not supported in Open One. Ask the user in a normal message.')))
        elif kind == 'control_cancel_request':
            self.cancel_request(event.get('request_id'))
        else:
            print(json.dumps(event), flush=True)
            if kind == 'system':
                subtype = event.get('subtype')
                if subtype == 'session_state_changed':
                    self.session_state = event.get('state')
                elif subtype == 'task_started' and event.get('task_type') in ('local_agent', 'local_workflow'):
                    self.tasks.add(event.get('task_id'))
                elif subtype == 'task_notification' and event.get('status') in ('completed', 'failed', 'stopped'):
                    self.tasks.discard(event.get('task_id'))
            if kind == 'result':
                self.result_seen = True
                self.failed = bool(event.get('is_error'))
            if self.result_seen and not self.tasks and not self.pending and self.session_state in (None, 'idle'):
                self.ended = True

    def run(self):
        if self.provider == 'Codex':
            args = [self.config['executable'], 'app-server', '--listen', 'stdio://']
        elif self.provider == 'Claude':
            args = [self.config['executable'], '-p', '--verbose', '--input-format', 'stream-json',
                    '--output-format', 'stream-json', '--permission-prompt-tool', 'stdio']
            if self.config.get('sessionID'):
                args += ['--resume', self.config['sessionID']]
            elif self.config.get('forkSessionID'):
                args += ['--resume', self.config['forkSessionID'], '--fork-session']
        else:
            raise ValueError('Unsupported provider.')
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=sys.stderr, cwd=self.config['directory'])
        threading.Thread(target=self.reader, daemon=True).start()
        if self.provider == 'Codex':
            self.rpc('initialize', dict(clientInfo=dict(name='openone', version='0.7.16'),
                                       capabilities=dict(experimentalApi=True)), 'initialize')
        else:
            self.write(dict(type='control_request', request_id='openone-init', request=dict(subtype='initialize', hooks=None)))
        deadline = time.monotonic() + 120
        while not self.ended:
            try:
                event = self.events.get(timeout=0.05)
            except queue.Empty:
                event = {}
            if event is None:
                raise RuntimeError('The provider closed its approval connection before completing the turn.')
            if event.get('type') == 'transport_error':
                raise RuntimeError(event['message'])
            if event:
                (self.codex if self.provider == 'Codex' else self.claude)(event)
            # Process queued cancellations before decisions, so stale clicks are
            # never applied to a request the provider has already withdrawn.
            if self.events.empty() and not self.ended:
                self.decisions()
            if not self.ready and time.monotonic() > deadline:
                raise RuntimeError('The provider did not initialize within two minutes.')
        return 1 if self.failed else 0

    def close(self):
        for key in list(self.pending):
            emit('openone.approvalResolved', id=key)
        self.pending.clear()
        if self.process:
            try:
                self.process.stdin.close()
            except (OSError, ValueError):
                pass
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()


def main():
    os.umask(0o077)
    root = Path(sys.argv[1])
    config = json.loads((root / 'config.json').read_text())
    transport = Transport(config, root)
    def stop(_signum, _frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, stop)
    try:
        return transport.run()
    except KeyboardInterrupt:
        return 130
    except Exception as error:
        emit('error', message=str(error))
        return 1
    finally:
        transport.close()


if __name__ == '__main__':
    sys.exit(main())
