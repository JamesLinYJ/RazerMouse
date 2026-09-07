#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Remove build-machine debug maps and toolchain search paths before signing."""
from pathlib import Path
import os
import subprocess
import sys

binary = Path(sys.argv[1])
subprocess.run(['strip', '-S', str(binary)], check=True)
commands = subprocess.check_output(['otool', '-l', str(binary)], text=True).splitlines()
for index, line in enumerate(commands):
    if line.strip() == 'cmd LC_RPATH':
        path = commands[index + 2].strip().removeprefix('path ').rsplit(' (offset ', 1)[0]
        if '.xctoolchain/' in path:
            subprocess.run(['install_name_tool', '-delete_rpath', path, str(binary)], check=True)
if os.fsencode(str(Path.home())) in binary.read_bytes():
    raise SystemExit('Packaged executable still contains the build user home directory')
