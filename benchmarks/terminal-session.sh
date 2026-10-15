#!/usr/bin/env bash
set -uo pipefail
if [[ -n ${FZD_BENCH_INTEGRATION:-} ]]; then
  export FZD_BIN=$FZD_BENCH_SCRIPT
  # shellcheck source=/dev/null
  source "$FZD_BENCH_INTEGRATION"
fi
printf 'FZD_BENCH_PRIMARY_SCREEN\n'
printf ready >"$FZD_BENCH_READY"
IFS= read -r _ <"$FZD_BENCH_GATE"
if [[ -n ${FZD_BENCH_INTEGRATION:-} ]]; then
  lf >"$FZD_BENCH_RESULT"
else
  bash "$FZD_BENCH_SCRIPT" >"$FZD_BENCH_RESULT"
fi
printf '%s\n' "$?" >"$FZD_BENCH_STATUS"
exec sleep 300
