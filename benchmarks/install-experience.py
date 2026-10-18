#!/usr/bin/env python3
"""Alternating real-fzf PTY observations, without a tmux socket.

Usage: python3 benchmarks/install-experience.py BASELINE_CHECKOUT OUTPUT [TRIALS]
Run sequentially on an otherwise idle host. Results include shell integration,
initial list readiness, and captured text preview changes; not font rendering.
Set FZD_BENCH_OMARCHY=1 to include the current upstream theme utility fixture.
"""
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import statistics
import struct
import sys
import termios
import time

ANSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)")
REPO = Path(__file__).resolve().parent.parent


def observe(checkout, root, private, log):
    private.mkdir()
    runtime = private / "runtime"
    runtime.mkdir(mode=0o700)
    config = private / "fzd.conf"
    config.write_text("FZD_GLOBAL_BACKEND=live\nFZD_PREVIEW_TIMEOUT=2\n")
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("FZD_", "FZF_", "_ZO_", "XDG_"))}
    env.update(HOME=str(private), XDG_RUNTIME_DIR=str(runtime),
               XDG_CONFIG_HOME=str(private / "config"),
               XDG_DATA_HOME=str(private / "data"),
               XDG_STATE_HOME=str(private / "state"),
               XDG_CACHE_HOME=str(private / "cache"),
               _ZO_DATA_DIR=str(private / "zoxide"), FZD_CONF_FILE=str(config),
               BASH_ENV="/dev/null", ENV="/dev/null", TERM="xterm-256color",
               FZF_DEFAULT_OPTS="", FZF_DEFAULT_OPTS_FILE="/dev/null",
               FZD_BENCH_SOURCE=str(checkout / "shell/integration.sh"),
               FZD_BIN=str(checkout / "fzd.sh"))
    # Optional current-upstream fixture measures the real adapter/utility cost.
    # This remains a compatibility workload, not a native Omarchy benchmark.
    if os.environ.get("FZD_BENCH_OMARCHY") == "1":
        theme = private / ".local/state/omarchy/current/theme"
        theme.mkdir(parents=True)
        shutil.copyfile(REPO / "tests/fixtures/omarchy/tokyo-night.toml",
                        theme / "colors.toml")
        tools = private / "tools"
        tools.mkdir()
        utility = tools / "omarchy-theme-color"
        shutil.copyfile(REPO / "tests/fixtures/omarchy/omarchy-theme-color", utility)
        utility.chmod(0o755)
        env["PATH"] = str(tools) + ":" + env["PATH"]
    script = ('source "$FZD_BENCH_SOURCE"; lf; '
              'result=$?; printf "\\nFZD_PTY_FINISHED:%s\\n" "$result"; exit "$result"')
    started = time.perf_counter_ns()
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execvpe("bash", ["bash", "--noprofile", "--norc", "-c", script], env)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 120, 0, 0))
    captured = bytearray()
    offset = 0
    exited = False

    def wait_for(marker):
        nonlocal offset
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if marker in ANSI.sub(b"", bytes(captured[offset:])):
                offset = len(captured)
                return time.perf_counter_ns()
            ready, _, _ = select.select([master], [], [], 0.05)
            if ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    data = b""
                if not data:
                    break
                captured.extend(data)
        raise RuntimeError(f"PTY did not render {marker!r}; inspect {log}")

    def event(keys, marker):
        then = time.perf_counter_ns()
        os.write(master, keys)
        return (wait_for(marker) - then) / 1e6

    try:
        count = len(list(root.iterdir())) + 1
        startup = (wait_for(f"{count}/{count}".encode()) - started) / 1e6
        first = event(b"preview-", b"FZD_PREVIEW_ONE")
        change = event(b"\x1b[B", b"FZD_PREVIEW_TWO")
        close = event(b"\x1b", b"FZD_PTY_FINISHED:0")
        _, status = os.waitpid(pid, 0)
        exited = True
        if os.waitstatus_to_exitcode(status) != 0:
            raise RuntimeError(f"Shell exited with {status}; inspect {log}")
        return dict(startup_ms=startup, preview_first_ms=first,
                    preview_change_ms=change, exit_ms=close)
    finally:
        log.write_bytes(captured)
        if not exited:
            try:
                os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        os.close(master)


def main():
    baseline = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]).resolve()
    trials = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    if output.exists() or trials < 1:
        raise SystemExit("Choose a fresh output directory and positive trial count")
    output.mkdir(parents=True)
    records = []
    for size in (10, 1000, 10000):
        root = output / f"files-{size}"
        root.mkdir()
        (root / "child").mkdir()
        for index in range(size):
            name = ("preview-one.txt" if index == 0 else "preview-two.txt"
                    if index == 1 else f"entry-{index:05d}.txt")
            content = ("FZD_PREVIEW_ONE" if index == 0 else "FZD_PREVIEW_TWO"
                       if index == 1 else "FZD benchmark text")
            (root / name).write_text(content + "\n")
        for trial in range(trials + 1):
            order = ("before", "after") if trial % 2 == 0 else ("after", "before")
            for revision in order:
                checkout = baseline if revision == "before" else REPO
                label = f"{size}-{trial}-{revision}"
                timings = observe(checkout, root, output / label,
                                  output / f"{label}.terminal.log")
                record = dict(size=size, trial=trial, warmup=trial == 0,
                              revision=revision, **timings)
                records.append(record)
                print(json.dumps(record), flush=True)
                (output / "trials.json").write_text(json.dumps(records, indent=2) + "\n")
    summary = []
    for size in (10, 1000, 10000):
        for revision in ("before", "after"):
            group = [r for r in records if r["size"] == size and
                     r["revision"] == revision and not r["warmup"]]
            summary.append(dict(size=size, revision=revision,
                                **{key: statistics.median(r[key] for r in group)
                                   for key in ("startup_ms", "preview_first_ms",
                                               "preview_change_ms", "exit_ms")}))
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
