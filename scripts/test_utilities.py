import concurrent.futures, importlib.util, json, pathlib, socket, tempfile, threading, time, unittest, urllib.request, urllib.error

def module(name, filename):
    spec=importlib.util.spec_from_file_location(name,pathlib.Path(__file__).with_name(filename)); value=importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value
remote=module('remote','one-remote.py'); usage=module('usage','one-usage.py'); statusline=module('statusline','one-claude-statusline.py')

class UtilityTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=pathlib.Path(self.temp.name)
        self.server=remote.make_server(self.root); self.thread=threading.Thread(target=self.server.serve_forever,daemon=True); self.thread.start()
        self.base=f'http://127.0.0.1:{self.server.server_port}'
        self.agent=dict(id='qa',name='QA',title='Test question',state='waiting',canReceive=True,requestID='r1',choices=['Yes','No'],messages=[])
        remote.atomic_json(self.root/'remote-state.json',{'agents':[self.agent]})
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.temp.cleanup()
    def test_public_logo_serves_png_and_checks_host(self):
        for route, filename in [('/logo.png','open-one-logo.png'), ('/favicon.png','open-one-favicon.png'), ('/apple-touch-icon.png','open-one-touch-icon.png')]:
            with self.subTest(route=route):
                with urllib.request.urlopen(self.base+route, timeout=3) as response:
                    self.assertEqual(response.headers['Content-Type'], 'image/png')
                    data = response.read()
                    self.assertTrue(data.startswith(b'\x89PNG\r\n\x1a\n'))
                    self.assertEqual(data, remote.logo_path(filename).read_bytes())
                self.assertEqual(self.request(route, token=False, headers={'Host':'other.test'})[0], 403)
    def request(self,path,body=None,token=True,headers=None):
        h={'Content-Type':'application/json'}
        if token: h['Authorization']='Bearer '+self.server.token
        h.update(headers or {})
        req=urllib.request.Request(self.base+path,data=json.dumps(body).encode() if body is not None else None,headers=h)
        try:
            with urllib.request.urlopen(req,timeout=3) as result: return result.status,json.load(result)
        except urllib.error.HTTPError as error:
            with error: return error.code,json.load(error)
    def test_loopback_and_private_token(self):
        self.assertEqual(self.server.server_address[0],'127.0.0.1')
        self.assertEqual((self.root/'remote-connection.json').stat().st_mode & 0o777,0o600)
    def test_missing_token_rejected(self): self.assertEqual(self.request('/api/state',token=False)[0],401)
    def test_wrong_token_rejected(self): self.assertEqual(self.request('/api/state',headers={'Authorization':'Bearer wrong'})[0],401)
    def test_cross_origin_rejected(self): self.assertEqual(self.request('/api/commands',{},headers={'Origin':'https://other.test'})[0],403)
    def test_dns_rebinding_host_rejected(self): self.assertEqual(self.request('/api/state',headers={'Host':'evil.test'})[0],403)
    def test_state_read(self): self.assertEqual(self.request('/api/state')[1]['agents'][0]['id'],'qa')
    def test_single_conversation_read_is_exact_and_authenticated(self):
        self.agent['id']='observed:worktree/session'
        other=dict(self.agent,id='other',messages=[dict(text='Other history')])
        remote.atomic_json(self.root/'remote-state.json',dict(agents=[other,self.agent]))
        path='/api/conversations/'+urllib.parse.quote(self.agent['id'],safe='')
        self.assertEqual(self.request(path),(200,self.agent))
        self.assertEqual(self.request(path,token=False)[0],401)
        self.assertEqual(self.request('/api/conversations/missing')[0],404)
    def test_entire_conversation_list_survives_http_transport(self):
        agents = [dict(self.agent, id=f'conversation-{index}', conversationKey=f'session-{index}') for index in range(75)]
        remote.atomic_json(self.root/'remote-state.json', {'agents': agents})
        self.assertEqual(self.request('/api/state'), (200, {'agents': agents}))
    def test_lan_binding_refuses_public_or_wildcard_interfaces(self):
        for address in ['0.0.0.0', '8.8.8.8', '127.0.0.1', '100.64.0.1', '100.127.255.254', '192.168.1.1.evil']:
            with self.subTest(address=address), self.assertRaises(ValueError):
                remote.make_server(self.root/'refused', lan_address=address)
    def test_question_reply_queues(self):
        code,value=self.request('/api/commands',dict(agentID='qa',requestID='r1',text='Yes',choiceIndex=0)); self.assertEqual(code,202)
        queued=json.loads((self.root/'remote-commands'/f"{value['id']}.json").read_text()); self.assertEqual(queued['generation'],self.server.generation)
        self.assertFalse((self.root/'replies'/'r1.json').exists())
    def test_open_one_protocol_identity(self):
        code, info = self.request('/api/info')
        self.assertEqual((code, info['app'], info['protocolVersion']), (200, 'open-one', 2))
        self.assertEqual(self.request('/api/info',token=False)[0],401)
    def test_same_operation_is_not_queued_twice(self):
        import uuid
        body = dict(operationID=str(uuid.uuid4()), agentID='qa',requestID='r1',text='Yes')
        code, first = self.request('/api/commands',body)
        code, second = self.request('/api/commands',body)
        self.assertEqual(first['id'],second['id'])
        self.assertEqual(len(list((self.root/'remote-commands').glob('*.json'))),1)
        body['text']='Different'
        self.assertEqual(self.request('/api/commands',body)[0],409)
    def test_idle_browser_preconnect_cannot_block_api(self):
        with socket.create_connection(self.server.server_address,timeout=3):
            time.sleep(.05)
            start=time.monotonic()
            self.assertEqual(self.request('/api/info')[0],200)
            self.assertLess(time.monotonic()-start,1)
    def test_concurrent_repeated_operations_are_atomic(self):
        import uuid
        body=dict(operationID=str(uuid.uuid4()),agentID='qa',requestID='r1',text='Yes')
        barrier=threading.Barrier(8)
        def send(_):
            barrier.wait(timeout=3)
            return self.request('/api/commands',body)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            replies=list(pool.map(send,range(8)))
        self.assertTrue(all(code==202 and result['id']==body['operationID'] for code,result in replies))
        self.assertEqual(len(list((self.root/'remote-commands').glob('*.json'))),1)
        self.assertEqual(len(list((self.root/'remote-operations').glob('*.json'))),1)
        self.assertEqual(self.request('/api/commands',dict(body,text='Different'))[0],409)
    def test_changed_conversation_identity_rejected(self):
        self.agent['conversationKey']='current';remote.atomic_json(self.root/'remote-state.json',{'agents':[self.agent]})
        body=dict(agentID='qa',requestID='r1',text='Yes',conversationKey='old')
        self.assertEqual(self.request('/api/commands',body)[0],409)
        body['conversationKey']='current'
        self.assertEqual(self.request('/api/commands',body)[0],202)
    def test_receipt_lifecycle_not_fabricated(self):
        import uuid
        self.assertEqual(self.request('/api/receipts/'+str(uuid.uuid4()))[1]['status'],'unknown')
        _, command=self.request('/api/commands',dict(agentID='qa',requestID='r1',text='Yes'))
        self.assertEqual(self.request('/api/receipts/'+command['id'])[1]['status'],'queued')
        remote.atomic_json(self.root/'remote-receipts'/(command['id']+'.json'), {'status':'delivered','message':'Accepted'})
        self.assertEqual(self.request('/api/receipts/'+command['id'])[1]['status'],'delivered')
    def test_web_export_served_without_exposing_parent_files(self):
        web=self.root/'web';web.mkdir();(web/'index.html').write_text('<html>Open One</html>')
        (self.root/'secret.txt').write_text('secret')
        self.server.web_root=web.resolve()
        with urllib.request.urlopen(self.base+'/chat',timeout=3) as response:
            self.assertIn('Open One',response.read().decode())
        self.assertEqual(self.request('/%2e%2e/secret.txt',token=False)[0],404)
    def test_stale_question_rejected(self): self.assertEqual(self.request('/api/commands',dict(agentID='qa',requestID='old',text='Yes'))[0],409)
    def test_mismatched_choice_rejected(self): self.assertEqual(self.request('/api/commands',dict(agentID='qa',requestID='r1',text='No',choiceIndex=0))[0],409)
    def test_observed_conversation_readonly(self):
        self.agent['canReceive']=False; remote.atomic_json(self.root/'remote-state.json',{'agents':[self.agent]})
        self.assertEqual(self.request('/api/commands',dict(agentID='qa',requestID='r1',text='Hi'))[0],409)
    def test_old_token_revoked(self):
        old=self.server.token; self.server.token='new-token'; self.assertEqual(self.request('/api/state',headers={'Authorization':'Bearer '+old})[0],401)
    def test_remote_agent_event_namespaced(self):
        code,_=self.request('/api/events',dict(agentID='build',kind='question',requestID='remote-r1',text='Deploy?',choices=['No']))
        self.assertEqual(code,202); event=json.loads(next((self.root/'events').glob('*.json')).read_text()); self.assertEqual(event['agentID'],'remote:build')
    def test_remote_question_requires_request_id(self): self.assertEqual(self.request('/api/events',dict(agentID='build',kind='question',text='Deploy?'))[0],400)
    def test_reply_path_cannot_traverse(self):
        self.assertEqual(self.request('/api/replies/..%2F..%2Fsecret')[1],{'pending':True})
    def test_plaintext_remote_origin_rejected(self):
        with self.assertRaises(ValueError): remote.make_server(self.root,public_base='http://outside.test')
    def test_quota_dedup_and_optional_windows(self):
        bucket={'primary':{'usedPercent':25,'windowDurationMins':300,'resetsAt':100},'secondary':None}
        result=usage.codex_windows({'rateLimits':bucket,'rateLimitsByLimitId':{'codex':bucket}})
        self.assertEqual(len(result),1); self.assertEqual(result[0]['label'],'Session'); self.assertEqual(result[0]['used'],25)
    def test_missing_quota_never_fabricated(self): self.assertEqual(usage.codex_windows({'rateLimits':None}),[])
    def test_claude_capture_excludes_private_payload(self):
        result=usage.capture_claude({'rate_limits':{'seven_day':{'used_percentage':35,'resets_at':123}},'cwd':'/private/project','token':'secret'})
        self.assertEqual(result['windows'][0]['used'],35); self.assertNotIn('secret',json.dumps(result)); self.assertNotIn('cwd',result)

class StatuslineTests(unittest.TestCase):
    def test_preserve_restore_other_settings_and_previous_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory); settings=root/'settings.json'
            original={'model':'fixture','statusLine':{'type':'command','command':'printf original','padding':3}}
            settings.write_text(json.dumps(original))
            statusline.configure(root,settings)
            installed=json.loads(settings.read_text()); self.assertEqual(installed['model'],'fixture'); self.assertEqual(installed['statusLine']['padding'],3)
            self.assertIn('capture',installed['statusLine']['command'])
            statusline.configure(root,settings,False)
            self.assertEqual(json.loads(settings.read_text()),original)
    def test_restore_does_not_overwrite_later_user_edit(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory); settings=root/'settings.json'
            statusline.configure(root,settings)
            edited={'statusLine':{'type':'command','command':'new-user-choice'}}; settings.write_text(json.dumps(edited))
            with self.assertRaises(ValueError): statusline.configure(root,settings,False)
            self.assertEqual(json.loads(settings.read_text()),edited)
    def test_corrupt_settings_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory); settings=root/'settings.json'; settings.write_text('invalid-json')
            with self.assertRaises(ValueError): statusline.configure(root,settings)
            self.assertEqual(settings.read_text(),'invalid-json')

if __name__=='__main__': unittest.main()
