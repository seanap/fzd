#!/usr/bin/env python3
"""Compare filename acquisition, matching quality, and real-fzf response.

Usage: python3 benchmarks/global-search-options.py OUTPUT [TRIALS]
Uses a private fixture/database; reads but never updates the system database.
Host timings use a copied configuration with explicit backend overrides. All
commands run sequentially. Raw samples and terminal output remain in OUTPUT.
"""
import argparse
import base64
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
import sys
import tempfile
import termios
import time

REPO = Path(__file__).resolve().parent.parent
ANSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)")
FD = shutil.which("fd") or shutil.which("fdfind")
APP = REPO / "fzd.sh"


class Experiment:
    def __init__(self, output, private, trials):
        self.output, self.private, self.trials = output, private, trials
        self.records = []
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("FZD_", "FZF_", "XDG_", "_ZO_"))}
        runtime = private / "runtime"
        runtime.mkdir(mode=0o700)
        self.env.update(XDG_RUNTIME_DIR=str(runtime),
                        XDG_CONFIG_HOME=str(private / "config"),
                        XDG_DATA_HOME=str(private / "data"),
                        XDG_STATE_HOME=str(private / "state"),
                        XDG_CACHE_HOME=str(private / "cache"),
                        _ZO_DATA_DIR=str(private / "zoxide"),
                        TERM="xterm-256color", SHELL="/bin/bash",
                        FZF_DEFAULT_OPTS="", FZF_DEFAULT_OPTS_FILE="/dev/null",
                        BASH_ENV="/dev/null", ENV="/dev/null", LC_ALL="C")

    def save(self, record):
        self.records.append(record)
        with (self.output / "trials.jsonl").open("a") as out:
            out.write(json.dumps(record) + "\n")

    def config(self, name, root=None, backend="cache", cap=200000, host=False, db=None):
        path = self.private / (name + ".conf")
        content = ""
        if host:
            default = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home()/".config"))) / "fzd/fzd.conf"
            source = Path(os.environ.get("FZD_CONF_FILE", str(default)))
            content = source.read_text()
        else:
            content = (f"FZD_GLOBAL_ROOTS=({shlex.quote(str(root))})\n"
                       "FZD_GLOBAL_MAXDEPTH=6\nFZD_GLOBAL_MINLEN=2\n"
                       "FZD_GLOBAL_FULLPATH=0\nFZD_EXCLUDES=.git,node_modules,.cache\n"
                       "FZD_GLOBAL_XEXCLUDES=proc,sys,dev,run\n")
        content += f"\nFZD_GLOBAL_BACKEND={backend}\nFZD_GLOBAL_MAXRESULTS={cap}\n"
        if db:
            content += f"FZD_LOCATE_DBS={shlex.quote(str(db))}\n"
        path.write_text(content)
        return dict(self.env, FZD_CONF_FILE=str(path))

    def run(self, command, env=None, data=None, timeout=30):
        start = time.perf_counter_ns()
        process = subprocess.Popen([str(c) for c in command], env=env or self.env,
                                   stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True)
        try:
            stdout, stderr = process.communicate(data, timeout=timeout)
            return dict(ms=(time.perf_counter_ns()-start)/1e6,
                        status=process.returncode, stdout=stdout,
                        stderr=stderr.decode(errors="replace"))
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            return dict(ms=timeout*1000, status="timeout", stdout=stdout,
                        stderr=stderr.decode(errors="replace"))

    def measure(self, scope, name, command, env=None, data=None, query="", size=None):
        last = None
        for trial in range(self.trials + 1):
            last = self.run(command, env, data)
            self.save(dict(scope=scope, name=name, query=query, size=size,
                           trial=trial, warmup=trial == 0, ms=last["ms"],
                           status=last["status"], stderr=last["stderr"],
                           bytes=len(last["stdout"])))
            if last["status"] == "timeout":
                break
        print(scope, size, name, query, round(last["ms"], 1), last["status"], flush=True)
        return last["stdout"]

    def helper(self, env, query=None):
        args = [APP, "--_global_index"] if query is None else [APP, "--_global_list", "--q", query]
        return args, env

    def filter(self, data, query, exact=False):
        args = ["fzf", "--ansi", "--delimiter=\t", "--nth=2..", "--filter="+query]
        if exact:
            args += ["--exact"]
        return self.run(args, data=data)

    def host(self):
        print("Host measurements (system database is read only)", flush=True)
        snapshot_env = self.config("host-cache", host=True, cap=5000)
        snapshot = self.measure("host", "cache-build-5000", *self.helper(snapshot_env))
        (self.output / "host-snapshot-count.json").write_text(json.dumps({
            "records": snapshot.count(b"\n"), "cap": 5000,
            "note": "Counts only; private host filenames are not retained."}, indent=2)+"\n")
        for query in ("immich", "docker", "co", "imch"):
            for backend in ("live", "locate"):
                env = self.config("host-"+backend, host=True, backend=backend, cap=5000)
                result = self.measure("host", backend, *self.helper(env, query), query=query)
                self.save(dict(scope="host-count", name=backend, query=query,
                               matches=result.count(b"\n")))
            for exact in (False, True):
                name = "cached-fzf-" + ("exact" if exact else "fuzzy")
                result = self.measure("host", name,
                    ["fzf", "--ansi", "--delimiter=\t", "--nth=2..", "--filter="+query]
                    + (["--exact"] if exact else []), data=snapshot, query=query)
                self.save(dict(scope="host-count", name=name, query=query,
                               matches=result.count(b"\n")))

    def terminal(self, label, env, total, backend, trial, size, source=None, exact=False):
        # Source is a prototype preformatted snapshot; acquisition is timed
        # separately. Otherwise launch the actual unchanged FZD global overlay.
        args = (["fzf", "--ansi", "--height=100%", "--layout=reverse", "--border",
                 "--delimiter=\t", "--with-nth=2..", "--prompt=global:/ > "]
                if source else [str(APP), "--global"])
        if exact:
            args += ["--exact"]
        start = time.perf_counter_ns()
        pid, master = pty.fork()
        if pid == 0:
            if source:
                fd = os.open(source, os.O_RDONLY)
                os.dup2(fd, 0)
                os.close(fd)
            os.execvpe(args[0], args, env)
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 120, 0, 0))
        captured = bytearray()
        log = self.output / f"terminal-{size}-{label}-{trial}.log"

        def wait_for(marker, offset=0):
            deadline = time.monotonic()+30
            while time.monotonic() < deadline:
                if marker in ANSI.sub(b"", bytes(captured[offset:])):
                    return (time.perf_counter_ns()-start)/1e6
                if select.select([master], [], [], .05)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        data = b""
                    if not data:
                        break
                    captured.extend(data)
            raise RuntimeError(f"Missing {marker!r}; inspect {log}")

        try:
            marker = f"{total}/{total}".encode() if backend == "cache" else b"global:/ >"
            opened = wait_for(marker)
            self.save(dict(scope="terminal", size=size, name=label, query="open",
                           trial=trial, warmup=trial == 0, ms=opened))
            # Observe the persistent matcher's resident memory after list load.
            pending = [pid]
            while pending:
                child = pending.pop()
                try:
                    status = Path(f"/proc/{child}/status").read_text()
                    children = Path(f"/proc/{child}/task/{child}/children").read_text()
                    pending.extend(int(x) for x in children.split())
                    if re.search(r"^Name:\s+fzf$", status, re.M):
                        rss = re.search(r"^VmRSS:\s+(\d+)", status, re.M)
                        self.save(dict(scope="memory", size=size, name=label,
                                       trial=trial, warmup=trial == 0,
                                       fzf_rss_kib=int(rss.group(1))))
                except (FileNotFoundError, ProcessLookupError):
                    pass
            # Drain output before each new query; use distinct result counts so
            # an old frame cannot satisfy the new completion condition.
            for query, count in (("needle", 3), ("immich", 2), ("imch", 2)):
                while select.select([master], [], [], .03)[0]:
                    captured.extend(os.read(master, 65536))
                offset = len(captured)
                start = time.perf_counter_ns()
                os.write(master, b"\x15"+query.encode())
                expected = count if (backend == "cache" and not exact) or query != "imch" else 0
                denominator = total if backend == "cache" else expected
                latency = wait_for(f"{expected}/{denominator}".encode(), offset)
                self.save(dict(scope="terminal", size=size, name=label, query=query,
                               trial=trial, warmup=trial == 0, ms=latency))
        finally:
            log.write_bytes(captured)
            try:
                os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
            os.close(master)

    def fixture(self, size):
        print("Preparing fixture", size, flush=True)
        root = self.private / f"files-{size}"
        root.mkdir()
        specials = ["immich-server.conf", "immich-client.yaml", "needle-one.txt",
                    "needle-two.txt", "needle-three.txt", "docker-compose.yaml",
                    "annual-report.pdf", "annual-report-final.pdf"]
        for index in range(size-len(specials)):
            (root / f"entry-{index:06d}.txt").touch()
        for name in specials:
            (root / name).touch()
        db = self.private / f"files-{size}.db"
        updatedb = shutil.which("updatedb.plocate") or shutil.which("updatedb")
        prepare = self.run([updatedb, "--database-root", root, "--output", db,
                            "--require-visibility", "no", "--prunepaths", "",
                            "--prunenames", "", "--prunefs", "",
                            "--prune-bind-mounts", "no"])
        if prepare["status"] != 0:
            raise RuntimeError(prepare["stderr"])
        envs = {b: self.config(f"fixture-{size}-{b}", root, b, db=db)
                for b in ("cache", "live", "locate")}
        # All acquisition methods below see the same files, roots and depth.
        raw_fd = [FD, "-H", "-i", "--color=never", "-a", "--print0", "-d", "6",
                  "--fixed-strings", "--", "", root]
        self.measure("acquire", "fd-raw", raw_fd, size=size)
        self.measure("acquire", "find-raw", ["find", root, "-mindepth", "1",
                     "-maxdepth", "6", "-type", "f", "-print0"], size=size)
        self.measure("acquire", "plocate-snapshot-raw", ["plocate", "-d", db,
                     "-0", "--", str(root)+"/"], size=size)
        snapshot = self.measure("acquire", "fd-snapshot-formatted",
                                *self.helper(envs["cache"]), size=size)
        # A prototype database-backed fuzzy snapshot uses the same formatter.
        # This is an experiment, not an available FZD backend.
        prototype = self.private / f"db-snapshot-{size}.sh"
        prototype.write_text('''#!/usr/bin/env bash
set -euo pipefail
source "$1"
_fzd_paths
source "$FZD_CONF_FILE"
_fzd_init --_global_index
FZD_TEMP_FILES=(); FZD_ZOXIDE_PENDING=(); RECENT_PENDING=()
trap _cleanup EXIT
_global_live_candidates() {
  plocate -d "$FZD_LOCATE_DBS" -0 -- "${GLOBAL_ROOTS[0]}/"
}
_global_index
''')
        db_snapshot = self.measure("acquire", "plocate-snapshot-formatted",
                        ["bash", prototype, APP], env=envs["cache"], size=size)
        fd_paths = {line.split(b"\t", 1)[0] for line in snapshot.splitlines()}
        db_paths = {line.split(b"\t", 1)[0] for line in db_snapshot.splitlines()}
        if len(fd_paths) != size or fd_paths != db_paths:
            raise RuntimeError(f"Unfair fixture coverage: fd={len(fd_paths)} db={len(db_paths)} expected={size}")
        # Acquisition and fzf process startup are outside the persistent-UI query
        # timings, but included in these separate process-per-query controls.
        quality_cases = [("immich", "immich-server.conf"),
                         ("imch", "immich-server.conf"),
                         ("imm server", "immich-server.conf"),
                         ("immcih", "immich-server.conf"),
                         ("dcomp", "docker-compose.yaml"),
                         ("an rpt", "annual-report.pdf"),
                         ("i", "immich-server.conf")]
        for query in ("needle", "entry-000", "imch"):
            for backend in ("live", "locate"):
                self.measure("query", backend, *self.helper(envs[backend], query),
                             query=query, size=size)
            for exact in (False, True):
                self.measure("query", "cached-fzf-"+("exact" if exact else "fuzzy"),
                    ["fzf", "--ansi", "--delimiter=\t", "--nth=2..", "--filter="+query]
                    + (["--exact"] if exact else []), data=snapshot, query=query, size=size)
        if size == 1000:
            for query, target in quality_cases:
                for backend in ("live", "locate", "cached-fzf-fuzzy", "cached-fzf-exact"):
                    if backend in envs:
                        result = self.run(*self.helper(envs[backend], query))
                    else:
                        result = self.filter(snapshot, query, backend.endswith("exact"))
                    paths = [base64.b64decode(line.split(b"\t", 1)[0]).decode()
                             for line in result["stdout"].splitlines()]
                    ranks = [i+1 for i, path in enumerate(paths) if Path(path).name == target]
                    self.save(dict(scope="quality", name=backend, query=query,
                                   target=target, matches=len(paths),
                                   target_rank=ranks[0] if ranks else None))
                    expected = query == "immich"
                    if backend == "cached-fzf-fuzzy":
                        expected = query != "immcih"
                    if backend == "cached-fzf-exact":
                        expected = query in ("immich", "imm server", "i")
                    if bool(ranks) != expected:
                        raise RuntimeError(f"Unexpected matching probe: {backend} {query!r} {ranks}")
        source = self.private / f"snapshot-{size}.txt"
        source.write_bytes(db_snapshot)
        for trial in range(self.trials+1):
            order = ("cache", "live", "locate") if trial % 2 == 0 else ("locate", "live", "cache")
            for backend in order:
                self.terminal(backend, envs[backend], size, backend, trial, size)
            self.terminal("plocate-snapshot-prototype", envs["cache"], size,
                          "cache", trial, size, source)
            print("terminal", size, trial, "complete", flush=True)
        if size == 1000:
            self.coverage(root, db, envs)

    def coverage(self, root, db, envs):
        # Add files only after building the database, demonstrating freshness.
        session_snapshot = self.run(*self.helper(envs["cache"]))["stdout"]
        cases = [(root/"fresh-after-index.txt", "fresh-after-index"),
                 (root/".gitignore", None),
                 (root/"ignored-dir/hidden-by-gitignore.txt", "hidden-by-gitignore"),
                 (root/"a/b/c/d/e/f/deeper-than-six.txt", "deeper-than-six")]
        (root/".git").mkdir()  # fd applies .gitignore inside a repository.
        (root/".gitignore").write_text("ignored-dir/\n")
        for path, query in cases:
            if query:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
        # Reindex a separate database to distinguish stale from coverage rules.
        coverage_db = self.private/"coverage.db"
        updatedb = shutil.which("updatedb.plocate") or shutil.which("updatedb")
        result = self.run([updatedb, "--database-root", root, "--output", coverage_db,
                          "--require-visibility", "no", "--prunepaths", "",
                          "--prunenames", "", "--prunefs", "", "--prune-bind-mounts", "no"])
        if result["status"] != 0:
            raise RuntimeError(result["stderr"])
        new_env = self.config("coverage-locate", root, "locate", db=coverage_db)
        limited = self.config("coverage-cap", root, "cache", cap=10)
        limited_snapshot = self.run(*self.helper(limited))["stdout"]
        all_snapshot = self.run(*self.helper(envs["cache"]))["stdout"]
        all_names = {Path(base64.b64decode(x.split(b"\t",1)[0]).decode()).name
                     for x in all_snapshot.splitlines()}
        capped_names = {Path(base64.b64decode(x.split(b"\t",1)[0]).decode()).name
                        for x in limited_snapshot.splitlines()}
        self.save(dict(scope="coverage-cap", name="cache-cap-10",
                       all_candidates=len(all_names), retained=len(capped_names),
                       omitted=len(all_names-capped_names)))
        for _, query in cases:
            if not query:
                continue
            for backend, env in [("live", envs["live"]), ("locate-stale", envs["locate"]),
                                 ("locate-fresh", new_env)]:
                result = self.run(*self.helper(env, query))
                self.save(dict(scope="coverage", name=backend, query=query,
                               matches=result["stdout"].count(b"\n")))
            result = self.filter(all_snapshot, query)
            self.save(dict(scope="coverage", name="cache-rebuilt", query=query,
                           matches=result["stdout"].count(b"\n")))
            result = self.filter(session_snapshot, query)
            self.save(dict(scope="coverage", name="cache-already-open", query=query,
                           matches=result["stdout"].count(b"\n")))

    def matchers(self, size):
        """Isolate fuzzy vs exact CPU/UI cost, excluding all acquisition work."""
        names = [f"entry-{n:06d}.txt" for n in range(size-5)] + [
            "needle-one.txt", "needle-two.txt", "needle-three.txt",
            "immich-server.conf", "immich-client.yaml"]
        source = self.private / f"matcher-{size}.txt"
        source.write_bytes(b"".join(base64.b64encode(("/fixture/"+n).encode())
                                   + b"\t" + n.encode()+b"\n" for n in names))
        for trial in range(self.trials+1):
            for exact in ((False, True) if trial%2 == 0 else (True, False)):
                self.terminal("matcher-exact" if exact else "matcher-fuzzy",
                              self.env, size, "cache", trial, size, source, exact)
            print("matchers", size, trial, "complete", flush=True)

    def host_coverage(self):
        env = self.config("host-coverage", host=True, backend="locate", cap=5000)
        setup = '''source "$1"
_fzd_paths
source "$FZD_CONF_FILE"
_fzd_init --_global_list
FZD_TEMP_FILES=(); FZD_ZOXIDE_PENDING=(); RECENT_PENDING=()
trap _cleanup EXIT
_global_prepare
printf '%s\\0' "${GLOBAL_ROOTS[@]}" EXCLUDES "${GLOBAL_EXCLUDES[@]}"
'''
        result = self.run(["bash", "-c", setup, "_", APP], env)
        fields = result["stdout"].decode().split("\0")
        split = fields.index("EXCLUDES")
        roots, excludes = fields[:split], fields[split+1:]
        for query in ("immich", "docker"):
            found = self.run(*self.helper(env, query))["stdout"].splitlines()
            indexed = {base64.b64decode(x.split(b"\t", 1)[0]).decode() for x in found}
            depths = [min(len(Path(p).relative_to(r).parts) for r in roots
                          if Path(p).is_relative_to(r)) for p in indexed]
            self.save(dict(scope="host-coverage", query=query, name="locate",
                           matches=len(indexed), depths=sorted(depths)))
            for depth, no_ignore in ((6, False), (6, True), (64, False), (64, True)):
                args = [FD, "-H", "-i", "--color=never", "-a", "--print0", "-d", str(depth)]
                if no_ignore:
                    args += ["--no-ignore"]
                for pattern in excludes:
                    if pattern:
                        args += ["--exclude", pattern]
                args += ["--fixed-strings", "--", query]+roots
                result = self.run(args)
                paths = {p.rstrip("/") or "/" for p in
                         result["stdout"].decode().split("\0") if p}
                self.save(dict(scope="host-coverage", query=query,
                               name=f"fd-depth-{depth}-no-ignore-{no_ignore}",
                               matches=len(paths), recovered_indexed=len(paths & indexed),
                               status=result["status"], ms=result["ms"], warmup=False))
                print("host coverage", query, depth, no_ignore,
                      len(paths), "recovered", len(paths & indexed), flush=True)

    def summary(self):
        groups = {}
        for record in self.records:
            if "ms" not in record or record["warmup"]:
                continue
            key = tuple(record.get(k) for k in ("scope", "size", "name", "query"))
            groups.setdefault(key, []).append(record)
        result = []
        for (scope, size, name, query), rows in groups.items():
            times = [r["ms"] for r in rows]
            result.append(dict(scope=scope, size=size, name=name, query=query,
                               samples=len(times), median_ms=statistics.median(times),
                               min_ms=min(times), max_ms=max(times)))
        (self.output/"summary.json").write_text(json.dumps(result, indent=2)+"\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("trials", type=int, nargs="?", default=3)
    parser.add_argument("--skip-host", action="store_true")
    parser.add_argument("--matching-only", action="store_true")
    parser.add_argument("--host-coverage-only", action="store_true")
    parser.add_argument("--sizes", type=int, nargs="+", default=[1000, 10000, 100000])
    args = parser.parse_args()
    output, trials = args.output.resolve(), args.trials
    if output.exists() or trials < 1:
        raise SystemExit("Choose a fresh output directory and positive trial count")
    output.mkdir(parents=True)
    metadata = dict(date_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    platform=os.uname()._asdict() if hasattr(os.uname(), "_asdict") else list(os.uname()),
                    trials=trials, script_sha256=hashlib.sha256(APP.read_bytes()).hexdigest(),
                    executable=str(APP), fd=FD,
                    limitations=["Warm filesystem caches; no cache dropping or privileged writes.",
                                 "PTY observations measure bytes emitted, not physical screen paint.",
                                 "Fixture is flat; host and coverage probes address different layouts.",
                                 "FZF snapshot prototype acquisition and UI load are reported separately.",
                                 "Host result lists are not saved; private terminal fixtures are retained as logs."])
    for command in (["fzf", "--version"], ["plocate", "--version"], [FD, "--version"]):
        metadata[command[0]] = subprocess.check_output(command, text=True).splitlines()[0]
    (output/"environment.json").write_text(json.dumps(metadata, indent=2)+"\n")
    with tempfile.TemporaryDirectory(prefix="fzd-global-options-") as private:
        experiment = Experiment(output, Path(private), trials)
        try:
            if args.host_coverage_only:
                experiment.host_coverage()
                return
            if not args.skip_host and not args.matching_only:
                experiment.host()
            for size in args.sizes:
                if args.matching_only:
                    experiment.matchers(size)
                else:
                    experiment.fixture(size)
        finally:
            experiment.summary()


if __name__ == "__main__":
    main()
