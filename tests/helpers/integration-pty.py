#!/usr/bin/env python3
"""Real fzf integration acceptance, using direct PTYs (no tmux server required)."""
import base64
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

repo, work, case = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
work.mkdir(parents=True, exist_ok=True)
home = work / 'home'
home.mkdir()
root = work / 'files'
root.mkdir()
chosen = root / 'directory-z'
chosen.mkdir()
(chosen / 'example.rs').write_text('fn main() {}\n')
(chosen / 'node_modules').mkdir()
(chosen / 'node_modules' / 'excluded-marker').touch()
runtime = home / 'runtime'
runtime.mkdir(mode=0o700)
env = {k: v for k, v in os.environ.items()
       if not k.startswith(('FZD_', 'FZF_', '_ZO_', 'XDG_'))}
env.update(HOME=str(home), XDG_CONFIG_HOME=str(home/'config'),
           XDG_DATA_HOME=str(home/'data'), XDG_STATE_HOME=str(home/'state'),
           XDG_CACHE_HOME=str(home/'cache'), XDG_RUNTIME_DIR=str(runtime),
           FZD_CONF_FILE=str(home/'fzd.conf'), _ZO_DATA_DIR=str(home/'zoxide'),
           TERM='xterm-256color', BASH_ENV='/dev/null', ENV='/dev/null',
           FZF_DEFAULT_OPTS='', FZF_DEFAULT_OPTS_FILE='/dev/null',
           SHELL='/bin/bash')
(home/'fzd.conf').write_text('FZD_EXCLUDES=node_modules\nFZD_PREVIEW_TIMEOUT=2\n')
if case == 'launcher':
    tools = work / 'bin'
    tools.mkdir()
    for name in ('omarchy-launch-editor', 'omarchy-tui-install'):
        path = tools / name
        path.write_bytes((repo/'tests/fixtures/omarchy'/name).read_bytes())
        path.chmod(0o755)
    plocate = tools/'plocate'
    plocate.write_text('#!/bin/sh\ncase "$1" in --version) echo "plocate 1.1.19" ;; *) echo 1 ;; esac\n')
    plocate.chmod(0o755)
    env['PATH'] = str(tools) + ':' + env['PATH']
    env['WSL_DISTRO_NAME'] = 'fixture'
    (home/'.bashrc').write_text("PS1='FZD_LAUNCH_PROMPT> '\n")
    subprocess.run(['bash', str(repo/'install.sh'), '--deps', 'none', '--shell', 'bash',
                    '--enhanced', '--no-inline-suggestions', '--omarchy-launcher', 'float'],
                   env=env, check=True, stdout=subprocess.DEVNULL)
    args = ['bash', '--noprofile', '--rcfile', str(home/'.local/share/fzd/launcher.bash'), '-i']
else:
    if case == 'actions':
        tools = work / 'bin'
        tools.mkdir()
        for name, content in {
            'wl-copy': '#!/bin/sh\ncat >"$HOME/copied"\n',
            'lazygit': '#!/bin/sh\nprintf "FZD_LAZYGIT_READY\\n"\nread answer\n',
        }.items():
            (tools/name).write_text(content)
            (tools/name).chmod(0o755)
        env['PATH'] = str(tools) + ':' + env['PATH']
        env['WAYLAND_DISPLAY'] = 'fixture-wayland'
        subprocess.run(['git', 'init', '-q', str(chosen)], check=True)
        with (home/'fzd.conf').open('a') as config:
            config.write('FZD_GLOBAL_BACKEND=live\nFZD_GLOBAL_ROOTS=(' + repr(str(root)) + ')\n')
    env.update(FZD_BIN=str(repo/'fzd.sh'), FZD_SOURCE=str(repo/'shell/integration.sh'))
    args = ['bash', '--noprofile', '--norc', '-c',
            'source "$FZD_SOURCE"; lf; printf "\\nFZD_DONE:%s\\n" "$?"']

pid, master = pty.fork()
if pid == 0:
    os.chdir(root)
    os.execvpe(args[0], args, env)
fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 120, 0, 0))
captured = bytearray()
ansi = re.compile(rb'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)')


def wait(marker, start=0):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if marker in ansi.sub(b'', bytes(captured[start:])):
            return
        if select.select([master], [], [], .05)[0]:
            try:
                data = os.read(master, 65536)
            except OSError:
                data = b''
            if not data:
                break
            captured.extend(data)
    raise AssertionError(f'PTY missing {marker!r}; inspect {work}/terminal.log')


try:
    wait(b'2/2')
    os.write(master, b'directory-z')
    wait(b'example.rs')
    if case == 'actions':
        for scope in ('local', 'global'):
            start = len(captured)
            os.write(master, b'\x1by')
            wait(b'Path copied', start)
            wait(b'example.rs', start)
            assert (home/'copied').read_bytes() == os.fsencode(chosen)
            start = len(captured)
            os.write(master, b'\x1bg')
            wait(b'FZD_LAZYGIT_READY', start)
            start = len(captured)
            os.write(master, b'\r')
            wait(b'Returned from Lazygit', start)
            if scope == 'local':
                start = len(captured)
                os.write(master, b'\x06')
                wait(b'global:', start)
                os.write(master, b'directory-z')
                wait(b'example.rs', start)
        os.write(master, b'\x1b')
        time.sleep(.15)
        os.write(master, b'\x1b')
        wait(b'FZD_DONE:0')
    elif case == 'icons':
        text = bytes(captured).decode('utf-8', errors='replace')
        assert any(0xe000 <= ord(c) <= 0xf8ff or 0xf0000 <= ord(c) <= 0xffffd for c in text), 'eza emitted no Nerd glyphs inside fzf'
        assert b'excluded-marker' not in captured
        assert b'\x1b[' in captured
        os.write(master, b'\x1b')
        wait(b'FZD_DONE:0')
    else:
        os.write(master, b'\r')
        wait(b'FZD_LAUNCH_PROMPT> ')
        start = len(captured)
        os.write(master, b'printf "FZD_CWD:%s\\n" "$PWD"\r')
        wait(b'FZD_CWD:' + os.fsencode(chosen), start)
        os.write(master, b'exit\r')
    _, status = os.waitpid(pid, 0)
    assert os.waitstatus_to_exitcode(status) == 0
    pid = 0
    print(f'{case}: real fzf PTY passed')
finally:
    (work/'terminal.log').write_bytes(captured)
    if pid:
        os.killpg(pid, signal.SIGTERM)
        os.waitpid(pid, 0)
    os.close(master)
