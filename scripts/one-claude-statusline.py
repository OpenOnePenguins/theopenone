#!/usr/bin/env python3
"""Opt-in quota tap that preserves the existing Claude status-line command."""
import argparse, importlib.util, json, os, pathlib, shlex, subprocess, sys, uuid


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary=path.with_name('.open-one-'+uuid.uuid4().hex+'.tmp')
    fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as handle: json.dump(data,handle,indent=2)
    os.replace(temporary,path)


def configure(root, settings, install=True):
    root=pathlib.Path(root); settings=pathlib.Path(settings)
    current=json.loads(settings.read_text()) if settings.exists() else {}
    if not isinstance(current,dict): raise ValueError('Claude settings must be a JSON object.')
    record=root/'claude-statusline-integration.json'
    saved=json.loads(record.read_text()) if record.exists() else None
    if not install:
        if not saved: return 'No Open One integration is installed.'
        if current.get('statusLine') != saved['installed']: raise ValueError('Your status line changed after setup. It was left untouched; restore it manually from the saved integration record.')
        if saved['previous'] is None: current.pop('statusLine',None)
        else: current['statusLine']=saved['previous']
        write(settings,current); record.unlink(); return 'Previous status line restored.'
    if saved and current.get('statusLine') == saved['installed']: return 'Claude usage is already connected.'
    if saved: raise ValueError('A previous integration record exists. Restore that setup before reconnecting.')
    previous=current.get('statusLine')
    if previous is not None and (not isinstance(previous,dict) or previous.get('type')!='command' or not isinstance(previous.get('command'),str)):
        raise ValueError('This status-line configuration needs manual integration; it was left unchanged.')
    command=f'{shlex.quote(sys.executable)} {shlex.quote(str(pathlib.Path(__file__).resolve()))} capture --root {shlex.quote(str(root))}'
    installed=dict(previous or {},type='command',command=command)
    write(record,dict(previous=previous,installed=installed,settings=str(settings)))
    current['statusLine']=installed
    try: write(settings,current)
    except Exception:
        record.unlink(missing_ok=True); raise
    return 'Connected. Quotas appear after Claude Code next updates its status line.'


def capture(root):
    root=pathlib.Path(root); raw=sys.stdin.buffer.read(1_048_577)
    try:
        spec=importlib.util.spec_from_file_location('one_usage',pathlib.Path(__file__).with_name('one-usage.py')); usage=importlib.util.module_from_spec(spec); spec.loader.exec_module(usage)
        value=usage.capture_claude(json.loads(raw))
        if value['windows']: write(root/'claude-usage.json',value)
    except (ValueError,OSError): pass
    try: previous=json.loads((root/'claude-statusline-integration.json').read_text()).get('previous')
    except (OSError,ValueError): previous=None
    if previous:
        # This is the user's pre-existing status-line command, preserved verbatim.
        result=subprocess.run(previous['command'],shell=True,input=raw,timeout=8)
        return result.returncode
    print('Open One · usage connected'); return 0


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('action',choices=['install','restore','capture']); parser.add_argument('--root',required=True)
    parser.add_argument('--settings',default=str(pathlib.Path(os.environ.get('CLAUDE_CONFIG_DIR',str(pathlib.Path.home()/'.claude')))/'settings.json'))
    args=parser.parse_args()
    try:
        if args.action=='capture': return capture(args.root)
        print(configure(args.root,args.settings,args.action=='install')); return 0
    except (ValueError,OSError,subprocess.TimeoutExpired) as error:
        print(str(error)); return 1
if __name__=='__main__': sys.exit(main())
