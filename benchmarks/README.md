# Performance measurements

Run on an otherwise idle Linux host from the checkout. Fixtures, sockets and
temporary results stay under `.test-work/`. No installer or system index runs.
Use Bash, GNU utilities and hyperfine; PTY measurements also need tmux/fzf.
Prepare private locate tools with `bash dev/prepare-locate-tests.sh` if needed.

```bash
bash benchmarks/phase-two.sh before 3
bash benchmarks/phase-two.sh after 3
```

`before` materializes `385868a:fzd.sh`; `after` reads the working tree. Git
extraction and fixture preparation happen outside timed commands. Both use one
warmup and the requested sample count. JSON/CSV files go to
`.test-work/phase-two/`. The matrix includes:

- Array-to-record serialization at 10, 100, 1,000 and 10,000 entries.
- Real directory enumeration plus record preparation, enumeration alone, and
  NUL sorting alone at each size. Each command includes Bash and adapter startup.
- Helper startup (no TUI), a 1,010-entry global index, ten-match fd and private
  locate queries, text/directory/binary previews.

The private locate executables and database are prepared before timing. Query
timings include the application, but exclude repeated benchmark tool discovery.
Very small measurements approach hyperfine's shell-calibration precision.

Run terminal measurements **sequentially**, separate from component benchmarks
and tests:

```bash
for size in 10 100 1000 10000; do
  bash benchmarks/terminal.sh "$PWD/.test-work/phase-two/phase-one.sh" "$size" 3 \
    > ".test-work/phase-two/before-terminal-$size.csv"
  bash benchmarks/terminal.sh "$PWD/fzd.sh" "$size" 3 \
    > ".test-work/phase-two/after-terminal-$size.csv"
done
```

The recorded 10,000-entry Phase One PTY baseline uses **one sample** because its
navigation is slow. The final version uses three. Smaller sizes use three for
each revision. Do not treat these small samples as distributions or percentiles.
These are warm cache observations in
WSL, with the same inherited PATH for both revisions; native Linux timings are
not implied. All published samples, including outliers, are retained.

The harness starts its private 120×32 tmux server before releasing an input gate,
then timestamps with Linux `/proc/uptime`, a monotonic boot clock with **10 ms
resolution**. It polls captured screen text every 5 ms plus tmux/process overhead.
Render latencies are coarse observation bounds rather than physical display
measurements; a recorded zero means below clock resolution. Startup waits for the complete candidate
count; Right/Left wait for distinct new counts. Local matching, global overlay
open/query/close, preview content changes and Esc-to-exit are measured separately.
Preview-first includes the file query; preview-change includes changing queries.
Set `FZD_BENCH_PREVIEW_MOVE=1` to add a separate Down-arrow-to-preview measurement
after filtering to ten files. The recorded `*-preview-terminal.csv` files use
this extended sequence at 1,000 entries; the main matrix uses the default.
Global queries use the live backend and find two matches in root/child.
Set `FZD_BENCH_BACKEND=cache` for the separate cache-overlay comparison. Its
snapshot contains `2 * size + 1` entries, and filtering retains that total count.

The root contains the requested file count plus one child directory and the
parent row; the child has the same file count plus its parent row. Screen-gap rows
are emitted only when the original shell screen marker is actually observed
between fzf frames. Their absence does not prove there was no sub-poll-interval
flash. Cleanup kills only this harness's server.

For isolated component work, prepare with `bash benchmarks/local.sh SCRIPT SIZE
prepare`, then choose `full`, `enumerate` or `sort`. The historical
`candidates.sh SCRIPT SIZE format-only` control retains command substitutions and
substitutes a builtin encoder. It applies to Phase One, not the batched version.

`display-only` and `display-noop` isolate the display-escaping function and a
builtin no-op on the same short names, including adapter startup. For a larger
directory preview, set `FZD_BENCH_PREVIEW_PATH` to a prepared fixture and run
`workload.sh preview-dir`.

`tests/encoding.bats` provides deterministic performance guards: one encoder for
1,001 local records and three encoders for 257 global records. It also verifies
exact byte identities, failures, descriptor cleanup and producer reaping. These
protect the important process budget without fragile CI wall-clock thresholds.
Global output emits its first match immediately, then batches up to 128 records.
A gated producer verifies that the first result does not wait for scan EOF.

The first terminal harness used `EPOCHREALTIME`. A negative elapsed result
exposed a WSL wall-clock adjustment; all those measurements were discarded from
performance conclusions. Raw trials remain in `results/phase-two/discarded-wall-clock/`.
The main terminal matrix and direct-preview comparison were rerun with uptime.

Phase-one artifacts remain in `results/`. Phase-two measurements and process
profiles are in `results/phase-two/`; the engineering report is
[../docs/phase-two.md](../docs/phase-two.md).
