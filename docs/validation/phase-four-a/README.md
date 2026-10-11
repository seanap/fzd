# Executed Phase 4A validation

See ../../phase-four-a.md for interpretation, limits, source revisions and
performance comparisons. These records are executions, not proposed tests.

- fzf-0.44-tests.tap and fzf-0.65-tests.tap: complete 209-test suites against the
  extracted Debian runtime from host-tests-source.txt.
- packaging-tests.tap: final eight package/immutable-build checks; the version
  ordering assertion follows VERSION so it also works for later final releases.
- Per-distro tests.tap: original 201 tests against /usr/bin/fzd in actual
  userspaces. image.json records image identity; validation.log records real
  dependency transactions, upgrades/removal and unchanged user-file checksums.
- candidate-source.txt/SHA256SUMS/PKGBUILD: immutable local review candidate.
- arch/SRCINFO and package.sha256: generated makepkg metadata and checksum of the
  actual package, reproduced byte-for-byte before installation.
- frozen-runtime.sha256: source executable/modules/integration match 026ad23;
  Debian's package changes only the interpreter line.

Package-manager logs normalize carriage returns to newlines and remove trailing
horizontal whitespace for Git readability. Original logs and binary artifacts
remain in .test-work/phase-four-a/. TAP transcripts and OCI metadata are copied
unchanged. All home content belongs to disposable fixtures; no real-home
configuration, file contents or credentials are included.
