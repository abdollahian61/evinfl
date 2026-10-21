#!/usr/bin/env python3
"""Offline checks; never connects to managed hosts or deploys resources."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import yaml

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--ansible', action='store_true')
args = parser.parse_args()
files = [p for p in root.rglob('*') if p.is_file() and not any(x in p.relative_to(root).parts for x in ['private', '.git', '.tools'])]
for path in files:
    if path.suffix == '.sh':
        subprocess.run(['bash', '-n', str(path)], check=True)
    elif path.suffix in ['.yaml', '.yml'] or path.name.endswith('.yml.example'):
        list(yaml.safe_load_all(path.read_text()))
versions = dict(line.split('=', 1) for line in (root / 'config/versions.env').read_text().splitlines() if line and not line.startswith('#'))
assert {k.lower(): v for k, v in versions.items()} == yaml.safe_load((root / 'ansible/vars/versions.yml').read_text()), 'Version files differ'
if args.ansible:
    cli = shutil.which('ansible-playbook')
    if not cli:
        raise SystemExit('Install the pinned Kubespray Ansible requirements first')
    env = dict(os.environ, ANSIBLE_CONFIG=str(root / 'ansible/ansible.cfg'))
    for playbook in ['ansible/site.yml', 'ansible/playbooks/addons.yml', 'ansible/playbooks/agents.yml', 'vms/kerio01/verify.yml', 'vms/mssql01/verify.yml']:
        subprocess.run([cli, '-i', str(root / 'ansible/inventory.ini'), '--syntax-check', str(root / playbook)], env=env, cwd=root, check=True)
print(f'PASS: {len(files)} files checked; Bash, YAML and version consistency. No deployment performed.')
