#!/usr/bin/env python3
"""Check resource structure/references/placeholders; this does not grade translation quality."""
from __future__ import annotations
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

LOCALES=('base','zh_Hant','bo','en_US','ja','ko','ru','ar','ug')
PLACEHOLDER=re.compile(r'(?<!%)%(?:\d+\$)?([sdfi])')
REFERENCE=re.compile(r'''\$r\(['"]app\.string\.([^'"]+)['"]\)''')

def strings(file:Path)->dict[str,str]:
    rows=json.loads(file.read_text(encoding='utf-8'))['string']
    result={}
    for row in rows:
        name,value=row['name'],row['value']
        if name in result:raise ValueError(f'{file}: duplicate {name}')
        if not isinstance(value,str) or not value:raise ValueError(f'{file}: empty/non-string {name}')
        result[name]=value
    return result

def audit(root:Path)->list[str]:
    issues=[]; base_dir=root/'entry/src/main/resources'
    base=strings(base_dir/'base/element/string.json')
    app_strings=root/'AppScope/resources/base/element/string.json'
    available=set(base)|set(strings(app_strings))
    for file in (root/'entry/src/main/ets').rglob('*'):
        if file.suffix not in ('.ets','.ts'):continue
        missing=set(REFERENCE.findall(file.read_text(encoding='utf-8')))-available
        if missing:issues.append(f'{file.relative_to(root)}: undefined strings {sorted(missing)}')
    for locale in LOCALES:
        values=strings(base_dir/locale/'element/string.json')
        missing=set(base)-set(values);extra=set(values)-set(base)
        if missing:issues.append(f'{locale}: missing keys {sorted(missing)}')
        if extra:issues.append(f'{locale}: unexpected keys {sorted(extra)}')
        for name in set(base)&set(values):
            if Counter(PLACEHOLDER.findall(base[name]))!=Counter(PLACEHOLDER.findall(values[name])):
                issues.append(f'{locale}/{name}: placeholder mismatch')
    package=json.loads((root/'renderer/package.json').read_text())
    locked=json.loads((root/'renderer/package-lock.json').read_text())['packages']['']
    for key in ('dependencies','devDependencies','engines'):
        if package.get(key)!=locked.get(key):issues.append(f'package/lock root {key} mismatch')
    return issues

def main()->int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('checkout',nargs='?',type=Path,default=Path.cwd())
    args=p.parse_args();issues=audit(args.checkout.resolve())
    if issues:
        print('\n'.join(issues),file=sys.stderr);return 1
    print('Resource keys, references, placeholders, and lockfile root checked. Translation quality/RTL still need review.')
    return 0
if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,KeyError,TypeError) as error:
        print(f'ERROR: {error}',file=sys.stderr);raise SystemExit(1)
