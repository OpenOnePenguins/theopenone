#!/usr/bin/env python3
"""Installed provider CLIs + production transport, isolated homes + local models.

Only writes a marker inside its temporary directory. No credentials, paid models,
user sessions, or desktop input. Requires localhost socket permission.
"""
import argparse
import http.server
import json
import os
from pathlib import Path
import queue
import shlex
import shutil
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]


class Model(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        if 'count_tokens' in self.path:
            data = json.dumps(dict(input_tokens=1)).encode()
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
            return
        command = 'printf OPEN_ONE_APPROVAL_PROBE > ' + shlex.quote(str(self.server.marker))
        if '/responses' in self.path:
            prior = any(item.get('type')=='function_call_output' for item in body.get('input',[]) if isinstance(item,dict))
            if prior:
                item=dict(id='msg_probe',type='message',role='assistant',status='completed',content=[dict(type='output_text',text='Approval probe finished.',annotations=[])])
            else:
                names=[t.get('name') for t in body.get('tools',[])]
                if 'exec_command' in names: name='exec_command'; args=dict(cmd=command)
                elif 'shell_command' in names: name='shell_command'; args=dict(command=command)
                else:
                    self.server.error='No supported shell tool: '+repr(names)
                    self.send_error(400,self.server.error);return
                args.update(sandbox_permissions='require_escalated',justification='Write the disposable Open One approval test marker?')
                item=dict(id='fc_probe',type='function_call',call_id='probe_call',name=name,arguments=json.dumps(args))
            events=[('response.created',dict(response=dict(id='resp_probe',status='in_progress',output=[]))),
                    ('response.output_item.done',dict(output_index=0,item=item)),
                    ('response.completed',dict(response=dict(id='resp_probe',status='completed',output=[item],usage=dict(input_tokens=1,output_tokens=1,total_tokens=2))))]
        else:
            prior=any(block.get('type')=='tool_result' for msg in body.get('messages',[]) for block in msg.get('content',[]) if isinstance(block,dict))
            block=dict(type='text',text='') if prior else dict(type='tool_use',id='tool_probe',name='Bash',input={})
            delta=dict(type='text_delta',text='Approval probe finished.') if prior else dict(type='input_json_delta',partial_json=json.dumps(dict(command=command,description='Write a disposable approval marker')))
            message=dict(id='msg_probe',type='message',role='assistant',model=body.get('model','fixture'),content=[],stop_reason=None,stop_sequence=None,usage=dict(input_tokens=1,output_tokens=1))
            events=[('message_start',dict(message=message)),('content_block_start',dict(index=0,content_block=block)),('content_block_delta',dict(index=0,delta=delta)),
                    ('content_block_stop',dict(index=0)),('message_delta',dict(delta=dict(stop_reason='end_turn' if prior else 'tool_use',stop_sequence=None),usage=dict(output_tokens=1))),('message_stop',{})]
        data=''.join('event: '+kind+'\ndata: '+json.dumps(dict(type=kind,**value))+'\n\n' for kind,value in events).encode()
        self.send_response(200);self.send_header('Content-Type','text/event-stream');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)


def run(provider, allow):
    executable=shutil.which('codex' if provider=='Codex' else 'claude')
    assert executable, provider+' CLI must be installed'
    with tempfile.TemporaryDirectory(prefix='open-one-approval-e2e-') as folder:
        root=Path(folder); project=root/'project';project.mkdir(); home=root/'provider-home';home.mkdir();bridge=root/'bridge';bridge.mkdir()
        subprocess.run(['git','init','-q',str(project)],check=True)
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Model);server.marker=root/'approved-marker';server.error=None
        threading.Thread(target=server.serve_forever,daemon=True).start()
        env=dict(os.environ)
        # Local model only, no inherited model-provider credentials.
        for key in list(env):
            if key.startswith(('ANTHROPIC_','OPENAI_','CLAUDE_CODE_')):env.pop(key)
        if provider=='Codex':
            env['CODEX_HOME']=str(home)
            (home/'config.toml').write_text('model_provider="fixture"\nmodel="fixture"\napproval_policy="on-request"\nsandbox_mode="workspace-write"\ncheck_for_update_on_startup=false\n'
              '[features]\ncode_mode=false\n[model_providers.fixture]\nname="Local fixture"\nwire_api="responses"\nrequires_openai_auth=false\nrequest_max_retries=0\nstream_max_retries=0\n'
              f'base_url="http://127.0.0.1:{server.server_port}/v1"\n[projects.{json.dumps(str(project))}]\ntrust_level="trusted"\n')
        else:
            env.update(CLAUDE_CONFIG_DIR=str(home),ANTHROPIC_API_KEY='isolated-test-key',ANTHROPIC_BASE_URL=f'http://127.0.0.1:{server.server_port}',
                       CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1',DISABLE_AUTOUPDATER='1')
            (home/'settings.json').write_text(json.dumps(dict(permissions=dict(defaultMode='default'))))
        prompt='Run the disposable approval test.'
        config=dict(provider=provider,executable=executable,directory=str(project),prompt=prompt,
                    claudeInput=dict(type='user',parent_tool_use_id=None,message=dict(role='user',content=[dict(type='text',text=prompt)])))
        (bridge/'config.json').write_text(json.dumps(config))
        errors=root/'stderr.log'
        with errors.open('w') as error_file:
            process=subprocess.Popen(['/usr/bin/python3',str(ROOT/'scripts/one-agent.py'),str(bridge)],stdout=subprocess.PIPE,stderr=error_file,text=True,env=env)
        events=queue.Queue(); observed=[]
        def read():
            for line in process.stdout: events.put(json.loads(line))
            events.put(None)
        threading.Thread(target=read,daemon=True).start()
        try:
            while True:
                event=events.get(timeout=90)
                if event is None:break
                observed.append(event)
                if event.get('type')=='openone.approval':
                    assert not server.marker.exists(),'command ran before explicit approval'
                    assert 'approved-marker' in event['details'],event
                    assert event['allowEnabled'],event
                    response=bridge/'response.tmp';response.write_text(json.dumps(dict(id=event['id'],allow=allow)));response.rename(bridge/(event['id']+'.json'))
            process.wait(timeout=5)
            assert process.returncode==0, str(observed)+errors.read_text()[-3000:]
            assert sum(e['type']=='openone.approval' for e in observed)==1, str(observed)+str(server.error)+errors.read_text()[-3000:]
            assert server.marker.exists()==allow, 'command outcome must match exact decision'
            print(f'PASS: installed {provider}, {"approve once" if allow else "deny"}, real command permission round-trip, local model only',flush=True)
        except queue.Empty:
            raise AssertionError('Provider timed out: '+str(observed)+str(server.error)+errors.read_text()[-3000:])
        finally:
            if process.poll() is None:process.terminate();process.wait(timeout=5)
            process.stdout.close();server.shutdown();server.server_close()


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--provider',choices=['Codex','Claude'],required=True);args=parser.parse_args()
    run(args.provider,True);run(args.provider,False)
