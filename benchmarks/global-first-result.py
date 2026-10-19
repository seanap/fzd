#!/usr/bin/env python3
"""Sequential before/after measurements of actual lf/lff first results.

python3 benchmarks/global-first-result.py BASELINE_SCRIPT OUTPUT [TRIALS]
Every PTY starts with fresh application state; kernel caches are not dropped.
Only private fixture databases are built. The real host index is read only.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import signal
import statistics
import struct
import subprocess
import tempfile
import termios
import time

REPO = Path(__file__).resolve().parent.parent
ANSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)")


def observe(app, private, cwd, config, output, label, seeded, fzf, snapshot_total=None, omarchy=False):
    private.mkdir()
    runtime = private / "runtime"
    runtime.mkdir(mode=0o700)
    conf = private / "fzd.conf"
    conf.write_text(config)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("FZD_", "FZF_", "XDG_", "_ZO_"))}
    env.update(HOME=str(private), XDG_RUNTIME_DIR=str(runtime),
               XDG_CONFIG_HOME=str(private/"config"),
               XDG_DATA_HOME=str(private/"data"),
               XDG_STATE_HOME=str(private/"state"),
               XDG_CACHE_HOME=str(private/"cache"),
               _ZO_DATA_DIR=str(private/"zoxide"), FZD_CONF_FILE=str(conf),
               FZD_BIN=str(app), FZD_SOURCE=str(REPO/"shell/integration.sh"),
               TERM="xterm-256color", SHELL="/bin/bash", LC_ALL="C",
               BASH_ENV="/dev/null", ENV="/dev/null", FZF_DEFAULT_OPTS="",
               FZF_DEFAULT_OPTS_FILE="/dev/null")
    if fzf:
        env["PATH"] = str(fzf.parent)+":"+env["PATH"]
    if omarchy:
        theme = private/".local/state/omarchy/current/theme"
        theme.mkdir(parents=True)
        shutil.copyfile(REPO/"tests/fixtures/omarchy/tokyo-night.toml", theme/"colors.toml")
        tools = private/"tools"
        tools.mkdir()
        real = tools/"theme-real"
        shutil.copyfile(REPO/"tests/fixtures/omarchy/omarchy-theme-color", real)
        real.chmod(0o755)
        wrapper = tools/"omarchy-theme-color"
        wrapper.write_text('#!/bin/bash\nprintf "called\\n" >>"$FZD_BENCH_THEME_LOG"\nexec "$FZD_BENCH_THEME_REAL" "$@"\n')
        wrapper.chmod(0o755)
        env.update(PATH=str(tools)+":"+env["PATH"],
                   FZD_BENCH_THEME_LOG=str(private/"theme-calls"),
                   FZD_BENCH_THEME_REAL=str(real))
    command = 'source "$FZD_SOURCE"; ' + ("lff needle-1" if seeded else "lf")
    started = time.perf_counter_ns()
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execvpe("bash", ["bash", "--noprofile", "--norc", "-c", command], env)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 120, 0, 0))
    captured = bytearray()
    offset = 0
    timings = {}

    def wait(marker):
        deadline = time.monotonic()+30
        while time.monotonic() < deadline:
            text = ANSI.sub(b"", bytes(captured[offset:]))
            if isinstance(marker, re.Pattern):
                matched = marker.search(text)
            else:
                matched = (re.search(rb"(?<![0-9])"+re.escape(marker)+rb"(?![0-9])", text)
                           if re.fullmatch(rb"[0-9]+/[0-9]+", marker) else marker in text)
            if matched:
                return time.perf_counter_ns()
            if select.select([master], [], [], .03)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    data = b""
                if not data:
                    break
                captured.extend(data)
        raise RuntimeError(f"Missing {marker!r}; inspect {output}/{label}.terminal.log")

    def event(name, keys, marker):
        nonlocal offset
        offset = len(captured)
        then = time.perf_counter_ns()
        os.write(master, keys)
        timings[name] = (wait(marker)-then)/1e6
        return then

    try:
        if seeded:
            timings["launch_first_result_ms"] = (wait(b"needle-1-one.txt")-started)/1e6
            timings["launch_complete_ms"] = (wait(f"1/{snapshot_total or 1}".encode())-started)/1e6
        else:
            timings["lf_ready_ms"] = (wait(b"11/11")-started)/1e6
            event("local_query_ms", b"local-01", b"1/11")
            event("global_prompt_ms", b"\x06", b"global:/ >")
            then = event("first_query_first_result_ms", b"needle", b"needle-")
            timings["first_query_complete_ms"] = (wait(f"3/{snapshot_total or 3}".encode())-then)/1e6
            if snapshot_total:
                # A matching row may already be visible in the unfiltered list.
                # Require the new filtered count before crediting its result.
                timings["first_query_first_result_ms"] = timings["first_query_complete_ms"]
            # Finish a prefix outside timing, then measure just ONE key that
            # reduces three matches to one in both fuzzy and literal modes.
            os.write(master, b"-")
            time.sleep(.3)
            while select.select([master], [], [], .01)[0]:
                captured.extend(os.read(master, 65536))
            event("single_key_narrow_ms", b"1", f"1/{snapshot_total or 1}".encode())
            # A new broad query verifies first-result latency remains bounded
            # separately from preparing the complete matching result set.
            broad = b"\x15"+(b"'" if snapshot_total else b"")+b"entry-000"
            then = event("broad_first_result_ms", broad, re.compile(rb"entry-000[0-9]{3}\.txt"))
            timings["broad_complete_ms"] = (wait(f"1000/{snapshot_total or 1000}".encode())-then)/1e6
        if omarchy:
            timings["theme_calls"] = len((private/"theme-calls").read_text().splitlines())
        return timings
    finally:
        (output/(label+".terminal.log")).write_bytes(captured)
        try:
            os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
        # The wrapper can exit before FZD's signal/EXIT traps finish writing
        # private state. Reap the session before removing its fixture home.
        deadline = time.monotonic()+1
        while True:
            try:
                os.killpg(pid, 0)
            except ProcessLookupError:
                break
            if time.monotonic() >= deadline:
                os.killpg(pid, signal.SIGKILL)
                break
            time.sleep(.01)
        os.close(master)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("trials", type=int, nargs="?", default=7)
    parser.add_argument("--fzf", type=Path)
    parser.add_argument("--backend", choices=["auto", "cache", "live"], default="auto")
    parser.add_argument("--skip-host", action="store_true")
    parser.add_argument("--omarchy", action="store_true")
    parser.add_argument("--sizes", type=int, nargs="+", default=[10000, 100000])
    args = parser.parse_args()
    if args.fzf:
        args.fzf = args.fzf.resolve()
    before, output = args.baseline.resolve(), args.output.resolve()
    if output.exists() or args.trials < 1 or min(args.sizes) < 1005:
        raise SystemExit("Use a fresh output directory, positive trials and sizes >=1005")
    output.mkdir(parents=True)
    apps = {"before": before, "after": REPO/"fzd.sh"}
    records = []

    def save(record):
        records.append(record)
        with (output/"trials.jsonl").open("a") as file:
            file.write(json.dumps(record)+"\n")
        print(json.dumps(record), flush=True)

    metadata = dict(date_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    platform=list(os.uname()), trials=args.trials, backend=args.backend, omarchy=args.omarchy,
                    fzf=subprocess.check_output([str(args.fzf or shutil.which("fzf")), "--version"], text=True).strip(),
                    fzf_executable=str(args.fzf or shutil.which("fzf")),
                    apps={label: dict(path=str(app), sha256=hashlib.sha256(app.read_bytes()).hexdigest()) for label, app in apps.items()},
                    limitations=["Fresh private application state every PTY session; warm OS caches.",
                                 "No dropped caches, reboot or native-Linux measurement.",
                                 "Actual wrapper and terminal bytes, not physical screen paint.",
                                 "Broad first-result probe identifies the visible query result row."])
    (output/"environment.json").write_text(json.dumps(metadata, indent=2)+"\n")
    with tempfile.TemporaryDirectory(prefix="fzd-first-result-") as temp:
        work = Path(temp)
        cwd = work/"local"
        cwd.mkdir()
        for index in range(10):
            (cwd/f"local-{index:02d}.txt").write_text("LOCAL_PREVIEW\n")
        for size in args.sizes:
            root = work/f"files-{size}"
            root.mkdir()
            for index in range(size-3):
                (root/f"entry-{index:06d}.txt").touch()
            for name in ("needle-1-one.txt", "needle-2-two.txt", "needle-3-three.txt"):
                (root/name).write_text("TARGET_PREVIEW\n")
            db = work/f"index-{size}.db"
            subprocess.run([shutil.which("updatedb.plocate") or shutil.which("updatedb"),
                            "--database-root", str(root), "--output", str(db),
                            "--require-visibility", "no", "--prunepaths", "",
                            "--prunenames", "", "--prunefs", "", "--prune-bind-mounts", "no"], check=True)
            config = (f"FZD_GLOBAL_ROOTS=({shlex.quote(str(root))})\n"
                      f"FZD_LOCATE_DBS={shlex.quote(str(db))}\n"
                      f"FZD_GLOBAL_BACKEND={args.backend}\nFZD_GLOBAL_MAXRESULTS={max(5000, size)}\n")
            for trial in range(args.trials+1):
                for revision in (("before", "after") if trial%2 == 0 else ("after", "before")):
                    for seeded in (False, True):
                        label = f"{size}-{trial}-{revision}-{'lff' if seeded else 'lf'}"
                        values = observe(apps[revision], work/label, cwd, config,
                                         output, label, seeded, args.fzf,
                                         size if args.backend == "cache" else None, args.omarchy)
                        save(dict(scope="terminal", size=size, trial=trial,
                                  warmup=trial == 0, revision=revision,
                                  workflow="lff" if seeded else "lf", **values))
        # Actual host queries: preserve the roots/exclusions in the supplied
        # configuration. Only runtime/cache/state writes go to private storage.
        original = Path(os.environ.get("FZD_CONF_FILE", str(Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home()/".config")))/"fzd/fzd.conf")))
        config = work/"host.conf"
        config.write_text(original.read_text()+"\nFZD_GLOBAL_BACKEND=locate\n")
        env = os.environ.copy()
        env.update(FZD_CONF_FILE=str(config), FZD_TMP_DIR=str(work/"host-temp"),
                   FZD_STATE_DIR=str(work/"host-state"), FZD_CACHE_DIR=str(work/"host-cache"))
        identities = {}
        for query in (() if args.skip_host else ("immich", "docker", "co", "fzd", "__snapshot")):
            for trial in range(args.trials+1):
                for revision in (("before", "after") if trial%2 == 0 else ("after", "before")):
                    started = time.perf_counter_ns()
                    command = ([str(apps[revision]), "--_global_index"] if query == "__snapshot"
                               else [str(apps[revision]), "--_global_list", "--q", query])
                    process = subprocess.Popen(command,
                                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, bufsize=0)
                    first = process.stdout.readline()
                    first_ms = (time.perf_counter_ns()-started)/1e6
                    rest, errors = process.communicate(timeout=30)
                    assert process.returncode == 0 and not errors, errors
                    ids = sorted(line.split(b"\t", 1)[0] for line in (first+rest).splitlines())
                    identity = hashlib.sha256(b"\n".join(ids)).hexdigest()
                    key = (query, trial)
                    if key in identities:
                        assert identities[key] == identity, (query, "result identities changed")
                    identities[key] = identity
                    save(dict(scope="host", query=query, revision=revision,
                              trial=trial, warmup=trial == 0,
                              first_result_ms=first_ms,
                              complete_ms=(time.perf_counter_ns()-started)/1e6,
                              matches=(first+rest).count(b"\n"), identity_sha256=identity))
    summary = []
    groups = {}
    for record in records:
        if not record["warmup"]:
            key = tuple(record.get(k) for k in ("scope", "size", "workflow", "query", "revision"))
            groups.setdefault(key, []).append(record)
    for (scope, size, workflow, query, revision), rows in groups.items():
        values = {key: dict(median=statistics.median(r[key] for r in rows),
                            min=min(r[key] for r in rows), max=max(r[key] for r in rows))
                  for key in rows[0] if key.endswith("_ms")}
        summary.append(dict(scope=scope, size=size, workflow=workflow, query=query,
                            revision=revision, samples=len(rows), **values))
    (output/"summary.json").write_text(json.dumps(summary, indent=2)+"\n")


if __name__ == "__main__":
    main()
