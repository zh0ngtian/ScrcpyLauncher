#!/usr/bin/env python3
"""Launch an isolated copy using a synthetic scrcpy protocol stream (no phone)."""
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
fixture = root / '.build/Integration'
fixture.mkdir(parents=True, exist_ok=True)
(fixture / 'bin').mkdir(exist_ok=True)
python = shutil.which('python3')
source = (root / 'Tests/Integration/adb_fixture.py').read_text().splitlines()
source[0] = '#!' + python
adb = fixture / 'bin/adb'
adb.write_text('\n'.join(source) + '\n')
adb.chmod(0o755)
subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
                'testsrc2=size=360x780:rate=10', '-t', '1', '-c:v', 'libx264',
                '-preset', 'ultrafast', '-tune', 'zerolatency', '-x264-params',
                'keyint=1:aud=1', '-f', 'h264', '-y', str(fixture / 'video.h264')], check=True)
with (fixture / 'packets.json').open('w') as packets:
    subprocess.run(['ffprobe', '-v', 'quiet', '-show_packets', '-show_entries',
                    'packet=pos,size', '-of', 'json', str(fixture / 'video.h264')], stdout=packets, check=True)
app = fixture / 'Scrcpy Integration Test.app'
process = subprocess.run(['pgrep', '-f', '^' + re.escape(str(app / 'Contents/MacOS/ScrcpyLauncher')) + '$'], capture_output=True)
if process.returncode == 0:
    raise SystemExit('Quit the existing integration test app before preparing another copy.')
if app.exists():
    shutil.rmtree(app)
shutil.copytree(root / 'dist/Scrcpy Launcher.app', app)
plist = app / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
identifier = 'dev.playphone.ScrcpyLauncher.integration.20261111'
info.update(CFBundleIdentifier=identifier, CFBundleName='Scrcpy Integration Test',
            CFBundleDisplayName='Scrcpy Integration Test')
plist.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
for key, value in [('defaultDeviceSerial', 'fixture-one'), ('defaultDeviceName', 'Fixture One')]:
    subprocess.run(['defaults', 'write', identifier, key, value], check=True)
subprocess.run(['open', '-n', '--env', 'PATH=' + str(fixture / 'bin') + ':/opt/homebrew/bin:/usr/bin:/bin', str(app)], check=True)
print('Test app:', app)
print('Production preferences and devices are untouched.')
