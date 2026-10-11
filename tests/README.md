# Regression checks

From the Linux checkout:

```bash
bash tests/run.sh
```

Use Bash 4.4 or later, Bats-core 1.5 or later, and GNU utilities. Real backend
tests additionally use fd/fdfind and plocate. Terminal tests use tmux and fzf;
shell integration tests use zsh when available. Missing optional tools produce
explicit skips. The phase-one environment uses Bash 5.2 and Bats 1.10.

Fixtures, XDG directories, private databases, sockets and transient output stay
under the ignored `.test-work/` directory. Tests never execute the installer or
write to the user's home configuration. Backend tests deliberately restrict PATH
to exercise find and controlled failures. Native tests also call actual fd and
plocate, and assert that successful locate checks did not silently fall back.

| Suite | Coverage |
| --- | --- |
| configuration.bats | Explicit/XDG configuration, environment expansion, root arrays, validation |
| filesystem.bats | NUL-safe local listing, byte-exact paths, previews, permissions, root navigation |
| global-search.bats | Injection, scope, excludes, labels, limits, fallback, symlinks, unusual names |
| native-backends.bats | Real fd and private plocate databases, literal queries, depth, failures |
| navigation.bats | Deterministic action sequences, stale results, selection restoration, exit codes |
| recovery.bats | Failed runtime creation, failed mktemp, normal cleanup, interrupted search |
| shell-integration.bats | Literal Bash/zsh init blocks extracted as data from install.sh |
| terminal.bats | Real fzf keyboard input, all global backend modes, editor arguments, resize, signals |

The terminal harness creates its own tmux server and socket, observes rendered
text or output files, and uses bounded polling. It never connects to existing
tmux sessions. A Codex sandbox can deny Unix sockets; run those checks with the
appropriate tool approval. This restriction is separate from WSL compatibility.

For a subset, pass Bats paths or options to the runner:

```bash
bash tests/run.sh tests/global-search.bats
bash tests/run.sh --filter 'root' tests/filesystem.bats
```

To obtain private locate tools on Ubuntu/Debian without installing a service:

```bash
bash dev/prepare-locate-tests.sh
bash tests/run.sh tests/native-backends.bats
```

That optional preparation command downloads repository packages with apt and
extracts plocate/liburing under `.test-work/tools/`. Tests build databases rooted
only at disposable fixtures, with all system pruning policies explicitly
overridden. They never rebuild the system locate database. A system installation
of plocate/updatedb also works; preparation is not run automatically.

The filename-injection regression uses `$(printf hit > FZD_INJECTION_MARKER)` in
a filename. The original indexer created that marker in its disposable working
directory. The repaired application treats the entire filename as data. The
first regression commit intentionally records failures before their fixes.

One test explicitly skips the existing shell wrappers' trailing-newline directory
limitation. FZD's internal identities and stdout preserve these bytes, but the
installer-generated `dest="$(fzd ...)"` strips them. This remains visible rather
than being counted as a passing regression.

Static checks used for this phase:

```bash
bash -n fzd.sh
shellcheck fzd.sh tests/run.sh tests/helpers/common.bash \
  tests/helpers/fzf-stub tests/helpers/backend-stub tests/helpers/pty-session \
  benchmarks/*.sh dev/*.sh
shfmt -d -i 2 tests/run.sh tests/helpers/common.bash \
  tests/helpers/fzf-stub tests/helpers/backend-stub tests/helpers/pty-session \
  benchmarks/*.sh dev/*.sh
shfmt -d -i 2 -ln bats tests/*.bats
git diff --check
```

The legacy application file is not reformatted wholesale, and the unchanged
installer is not included in the passing ShellCheck claim.

For a manual, isolated application baseline, run `bash dev/run.sh`. It copies the
example configuration once to `.test-work/manual/config/fzd/fzd.conf` and directs
FZD's state/cache/runtime there. It preserves later edits to that private config.
Its selected directory is printed to stdout; your existing shell wrapper remains
responsible for changing the parent shell's directory.

For warm-cache performance measurements on an otherwise idle machine:

```bash
bash benchmarks/hyperfine.sh 5
```

This prepares 1,000 files in ten directories, uses one warmup and five measured
runs, and exports JSON/CSV under `.test-work/results/`. Historical listing
functions are materialized before timing to avoid charging Git extraction to the
old revision. Candidate tests measure formatting from arrays, not filesystem
enumeration or fzf rendering. Other commands measure helper startup, live
index/query, text preview and optionally private locate queries. The `startup`
workload does not launch the TUI. No installation, theme generation or system
indexing is timed. The simpler `benchmarks/run.sh REVISION RUNS` remains available,
but arbitrary historical revisions include per-run extraction overhead.

Fresh distribution installation, system updatedb services, package lifecycle,
native terminal emulators and wider fzf-version coverage require the next
disposable/native Linux validation phase. They were not tested here.
