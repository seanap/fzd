# Omarchy integration performance

The [implementation/validation report](../../../docs/validation/omarchy/README.md#performance)
contains measured before/after tables and platform limitations. `normal-trials.json`
and `theme-trials.json` retain every observation, including warmups; the summary
files contain medians after dropping warmups. See `provenance.json` for exact
revisions, versions and workload details.

The normal run has 11 measured trials per revision/size; the theme fixture has
five. Sizes are 10, 1,000 and 10,000 entries. The baseline is `28a483a` and measured
runtime is `b74e477`, identical to the final runtime. Both use real Bash `lf`,
real fzf 0.44.1 and eza 0.18.2 in direct PTYs on Ubuntu 24.04 / WSL2. The theme
fixture uses the current upstream utility with Tokyo Night data; this is not a
native Omarchy desktop benchmark.

Normal median startup differences are +8/0/+8 ms and next-preview differences
are −1/−8/+4 ms. The themed startup differences are +3/+37/+61 ms; next previews
are unchanged or faster. Shared-host variation prevents interpreting these as
cross-platform guarantees. Active terminal fonts and physical rendering were
not measured. Tests/builds were stopped during measured runs.
