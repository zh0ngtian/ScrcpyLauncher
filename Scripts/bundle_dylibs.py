#!/usr/bin/env python3
"""Bundle the client's complete non-system dylib graph and rewrite its load paths."""
from pathlib import Path
import json
import plistlib
import re
import shutil
import subprocess
import sys

source, destination, notices = map(Path, sys.argv[1:])
destination.mkdir(parents=True, exist_ok=True)
notices.mkdir(parents=True, exist_ok=True)
visited = {}
manifest = []

def command(*args):
    return subprocess.check_output(args, text=True)

def bundle(path):
    path = path.resolve(strict=True)
    if path in visited:
        return visited[path]
    name = 'libscrcpy-client.dylib' if path == source.resolve() else path.name
    target = destination / name
    if target.exists():
        raise SystemExit(f'Conflicting bundled library: {name}')
    visited[path] = name
    shutil.copy2(path, target)
    target.chmod(0o755)
    lines = command('otool', '-L', str(path)).splitlines()[2:]
    changes = []
    for line in lines:
        dependency = line.strip().split(' (compatibility version', 1)[0]
        if dependency.startswith(('/usr/lib/', '/System/Library/')):
            continue
        resolved = dependency.replace('@loader_path', str(path.parent))
        if resolved.startswith('@'):
            raise SystemExit(f'Unresolved dependency {dependency} in {path}')
        dependency_name = bundle(Path(resolved))
        changes.extend(['-change', dependency, '@loader_path/' + dependency_name])
    subprocess.run(['install_name_tool', '-id', '@rpath/' + name, *changes, str(target)], check=True)
    manifest.append({'library': name, 'source': str(path)})
    parts = path.parts
    if 'Cellar' in parts:
        index = parts.index('Cellar')
        prefix = Path(*parts[:index + 3])
        formula = parts[index + 1]
        formula_notices = notices / formula
        formula_notices.mkdir(exist_ok=True)
        for pattern in ('LICENSE*', 'COPYING*', 'NOTICE*'):
            for notice in prefix.glob(pattern):
                if notice.is_file():
                    shutil.copy2(notice, formula_notices / notice.name)
        recipe = prefix / '.brew' / (formula + '.rb')
        if recipe.exists():
            shutil.copy2(recipe, formula_notices / recipe.name)
    return name

bundle(source)
(notices / 'BundledLibraries.json').write_text(json.dumps(sorted(manifest, key=lambda item: item['library']), indent=2) + '\n')
for target in destination.glob('*.dylib'):
    if '/opt/homebrew/' in command('otool', '-L', str(target)):
        raise SystemExit(f'External Homebrew dependency remains: {target}')
print(f'Bundled {len(visited)} native libraries')

# Homebrew libraries can require a newer macOS than the Swift UI target.
# Record their actual minimum instead of claiming this bundle runs on older OSes.
plist = destination.parent / 'Info.plist'
info = plistlib.loads(plist.read_bytes())
minimum = tuple(map(int, info['LSMinimumSystemVersion'].split('.')))
for binary in destination.glob('*.dylib'):
    load_commands = command('otool', '-l', str(binary))
    versions = re.findall(r'\bminos (\d+\.\d+(?:\.\d+)?)', load_commands)
    versions += re.findall(r'LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version (\d+\.\d+(?:\.\d+)?)', load_commands)
    for version in versions:
        minimum = max(minimum, tuple(map(int, version.split('.'))))
info['LSMinimumSystemVersion'] = '.'.join(map(str, minimum))
plist.write_bytes(plistlib.dumps(info))
print('Bundle minimum macOS:', info['LSMinimumSystemVersion'])
