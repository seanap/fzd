#!/usr/bin/env bash
set -uo pipefail
printf ready >"$FZD_BENCH_READY"
IFS= read -r _ <"$FZD_BENCH_GATE"
bash "$FZD_BENCH_SCRIPT" >"$FZD_BENCH_RESULT"
printf '%s\n' "$?" >"$FZD_BENCH_STATUS"
exec sleep 300
