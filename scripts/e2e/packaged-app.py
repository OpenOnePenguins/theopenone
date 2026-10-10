#!/usr/bin/env python3
"""Exercise the packaged app's real event loop and bundled bridge with fixture data.
Does not send mouse/keyboard input, run models, or read the user's app data.
"""
import json, os, pathlib, plistlib, shutil, subprocess, sys, tempfile, time, uuid
repo = pathlib.Path(__file__).resolve().parents[2]
run = repo / '.build' / 'e2e' / ('packaged-' + time.strftime('%Y%m%d-%H%M%S'))
run.mkdir(parents=True)
app = run / 'OpenOneFixture.app'
shutil.copytree(repo / 'dist' / 'Open One.app', app)
info = app / 'Contents' / 'Info.plist'
p = plistlib.loads(info.read_bytes()); p['CFBundleIdentifier'] = 'local.openone.fixture.' + uuid.uuid4().hex
info.write_bytes(plistlib.dumps(p))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True,stdout=subprocess.DEVNULL)
root = run / 'data'; root.mkdir()
(root/'preferences.json').write_text(json.dumps({'discoveryEnabled':False}))
env = dict(os.environ, OPEN_ONE_HOME=str(root))
checks=[]; proc=None

def check(name, value):
    checks.append({'name':name,'passed':bool(value)})
    print(('PASS: ' if value else 'FAIL: ')+name,flush=True)
    if not value: raise AssertionError(name)

def wait(fn):
    deadline=time.monotonic()+6
    while time.monotonic()<deadline:
        try:
            if fn(): return True
        except (FileNotFoundError, json.JSONDecodeError, KeyError, IndexError): pass
        time.sleep(.05)
    return False

def state(): return json.loads((root/'state.json').read_text())
def agent(): return next(a for a in state()['agents'] if a['id']=='fixture-agent')
def cli(*args): return subprocess.run([sys.executable,str(app/'Contents/Resources/one'),*args],env=env,capture_output=True,text=True,check=True)
def start(): return subprocess.Popen([str(app/'Contents/MacOS/OpenOne')],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
def stop():
    if proc and proc.poll() is None:
        proc.terminate()
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait()
def publish(event, name):
    target=root/'events'/name
    temp=target.with_suffix('.pending'); temp.write_text(json.dumps(event)); temp.replace(target)

try:
    proc=start()
    check('Packaged app creates isolated bridge folders',wait(lambda:(root/'events').is_dir()))
    cli('register','--agent','fixture-agent','--provider','Claude','--name','Packaged fixture')
    check('Bundled CLI registration reaches running app',wait(lambda:agent()['provider']=='Claude'))
    cli('working','--agent','fixture-agent','--text','Fixture work in progress')
    check('Working event reaches persisted app state',wait(lambda:agent()['state']=='working'))
    event={'id':'fixture-dedup','agentID':'fixture-agent','kind':'message','text':'Exactly one message'}
    publish(event,'message.json')
    check('Message reaches packaged app',wait(lambda:any(m['text']=='Exactly one message' for m in agent()['messages'])))
    publish(event,'duplicate.json')
    check('Duplicate event acknowledged',wait(lambda:not(root/'events/duplicate.json').exists()))
    check('Duplicate event does not duplicate content',sum(m['text']=='Exactly one message' for m in agent()['messages'])==1)
    (root/'events/invalid.json').write_text('{invalid')
    check('Malformed event quarantined by packaged app',wait(lambda:len(list((root/'rejected').glob('*.json')))==1))
    cli('done','--agent','fixture-agent','--text','Fixture complete')
    check('Bridge continues after invalid event',wait(lambda:agent()['state']=='done'))
    stop(); proc=start()
    check('Restart preserves conversation state',wait(lambda:proc.poll() is None and agent()['state']=='done'))
    cli('message','--agent','fixture-agent','--text','After restart')
    check('Restart resumes real bridge consumption',wait(lambda:any(m['text']=='After restart' for m in agent()['messages'])))
    check('Discovery stays disabled in isolated installation',len(state()['agents'])==1)
    stop()
    original=b'{corrupt fixture state'
    (root/'state.json').write_bytes(original)
    proc=start()
    check('Corrupt state is backed up on startup',wait(lambda:any(f.read_bytes()==original for f in root.glob('state-recovery-*.json'))))
    cli('register','--agent','fixture-agent','--provider','Codex')
    check('App accepts new events after recovery',wait(lambda:agent()['provider']=='Codex'))
finally:
    stop()
    (run/'results.json').write_text(json.dumps({'checks':checks,'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks)},indent=2))
    print('Report: '+str(run/'results.json'),flush=True)
