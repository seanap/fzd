# Regression checks

Run `bash tests/run.sh` from the Linux checkout. Bats and Bash are required.
Fixtures, XDG directories, backend stubs and transient output stay underneath
the ignored `.test-work/` directory. Tests never run the installer or modify the
real user's configuration. Backends are removed from the test PATH deliberately
when exercising the GNU find fallback.

The filename-injection test uses a filename containing a shell substitution
that can only write the text `hit` to a marker in its disposable fixture.
It must never create that marker with the repaired application.

The initial suite is intentionally committed before the fixes. At the audit
revision it exposes the known defects; it is not a passing release checkpoint.

For repeatable candidate-preparation timings:

```bash
bash benchmarks/run.sh 4dabc1259eb6c9aad88fe57d19b5dfaf7124c8e6 3
bash benchmarks/run.sh WORKTREE 3
```

The historical benchmark adapter extracts the marked listing/formatting function
block without executing startup. These measurements include Bash startup but
exclude fzf, previews, keyboard input and global filesystem enumeration. Keep
the machine and workload constant when comparing results. No performance target
or optimization is part of the first reliability phase.
