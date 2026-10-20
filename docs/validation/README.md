# Validation and historical evidence

The [GitHub validation workflow](../../.github/workflows/validate.yml) runs static
checks, the complete regression suite with fzf 0.44.1 and 0.65.2, deterministic
double builds, checksums, Debian package linting, and installed lifecycle tests
on Ubuntu, Debian, Arch and Fedora. It rejects skipped regression checks.

The pre-cleanup source snapshot
[`5fe42c0`](https://github.com/seanap/fzd/commit/5fe42c07874fe7a1ca5377c548ce6170c0a34c95)
passed all six jobs, including 354 regression tests with each fzf version:
[recorded main validation](https://github.com/seanap/fzd/actions/runs/39338692940).
See [current workflow runs](https://github.com/seanap/fzd/actions/workflows/validate.yml)
for validation of later revisions. Local reproduction commands are in the
[test guide](../../tests/README.md) and [packaging guide](../packaging.md).

Distribution checks exercise actual userspaces and package managers in
disposable containers. Fedora coverage is staged-runtime compatibility rather
than an RPM lifecycle test. Native desktop appearance, terminal interception,
SELinux and ARM64 remain separate coverage limits.

New logs, TAP output, checksums and provenance are GitHub Actions artifacts,
retained for 14 days by the workflow. Local generated output belongs under the
ignored `.test-work/` directory. Current performance findings are summarized in
the [search performance report](../../benchmarks/results/README.md).

## Historical development evidence

The original development reports and raw measurements are preserved in one
archive attached to the existing v2.1.1 release:

- [Download development-evidence-5fe42c0.tar.gz](https://github.com/seanap/fzd/releases/download/v2.1.1/development-evidence-5fe42c0.tar.gz)
- [Download its SHA256 checksum](https://github.com/seanap/fzd/releases/download/v2.1.1/development-evidence-5fe42c0.sha256)
- [Browse the complete pre-cleanup source](https://github.com/seanap/fzd/tree/5fe42c07874fe7a1ca5377c548ce6170c0a34c95)

Archive SHA256:
`a41e3db19253e62ab0597419971f2c03a624cda79ee1c6fe0426c83d57dda6f9`.

The archive preserves 359 original tracked files at their existing relative
paths: all benchmark results, validation records, the five development-phase
reports, the obsolete v0.1.0-rc.2 draft, and the original benchmark instructions.
Its `SOURCE.json` records the actual source commit
`5fe42c07874fe7a1ca5377c548ce6170c0a34c95` and each original file's SHA256.
The release attachment is identified by that source commit, independently of the
release's installation assets.

After downloading both attachments, verify and extract them:

```bash
sha256sum -c development-evidence-5fe42c0.sha256
tar -xzf development-evidence-5fe42c0.tar.gz
cd development-evidence-5fe42c0
sha256sum -c SHA256SUMS
```

Historical reports describe their recorded revisions and environments. The
archive retains the raw samples, incremental candidate hashes, discarded timing
experiments and administrative failure logs for provenance. Current installation
and configuration instructions live in the [technical guide](../TECHNICAL.md).
