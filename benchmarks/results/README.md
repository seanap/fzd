# Recorded phase-one baseline

Date: 2026-10-11. Environment: Ubuntu 24.04.5, WSL2, account htpc,
Linux checkout `/home/htpc/projects/fzd`, branch `revamp/audit`.

- Audit revision: `4dabc1259eb6c9aad88fe57d19b5dfaf7124c8e6`.
- Candidate measurements: `414a699`. The measured function block is byte-identical
  to the completed runtime revision `3cadebe`; verified by extracting and diffing
  the same marked block.
- Search/preview/locate measurements: `3cadebe`.
- Hyperfine 1.18.0, one warmup and five measured runs per command.
- Bash 5.2.21, fdfind 9.0.0, batcat 0.24.0, private plocate 1.1.19.
- Filesystem workload: 1,000 small text files in ten directories, ten `needle`
  matches, depth six, limit 2,000. Private databases cover only that tree.

JSON includes individual samples, CPU timings and exit codes. CSV contains summary
statistics. Results are warm-cache observations on this machine; query and preview
variance should inform later benchmark design. Candidate formatting excludes fzf
and filesystem enumeration. The startup workload does not launch the TUI.

Reproduce with `bash benchmarks/hyperfine.sh 5`. Fresh output is written to
`.test-work/results/`, leaving these reviewable reference measurements unchanged.
See [the phase report](../../docs/phase-one.md) for interpretation and limitations.
