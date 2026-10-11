#!/usr/bin/env bash
# Real tmux/fzf timings: bounded screen observations, no application instrumentation.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script=${1:-$repo/fzd.sh}
count=${2:-1000}
runs=${3:-3}
[[ "$script" == /* && -f "$script" && "$count" =~ ^[1-9][0-9]*$ && "$runs" =~ ^[1-9][0-9]*$ ]] || exit 2
work="$repo/.test-work/phase-two/terminal-$count"
root="$work/root"
mkdir -p "$root/zz-nav-child" "$work/config" "$work/runtime"
for ((entry = 0; entry < count; entry++)); do
  printf -v name 'file-%05d.txt' "$entry"
  printf 'FZD_PREVIEW_%05d\n' "$entry" >"$root/$name"
  printf 'FZD_CHILD_%05d\n' "$entry" >"$root/zz-nav-child/$name"
done
printf 'FZD_GLOBAL_ROOTS=(%q)\nFZD_GLOBAL_MAXRESULTS=30000\n' "$root" >"$work/config/fzd.conf"
export XDG_CONFIG_HOME="$work/config" XDG_STATE_HOME="$work/state" XDG_CACHE_HOME="$work/cache" XDG_RUNTIME_DIR="$work/runtime"
export FZD_CONF_FILE="$work/config/fzd.conf" FZD_TMP_DIR="$work/runtime/fzd" FZD_STATE_DIR="$work/state/fzd" FZD_CACHE_DIR="$work/cache/fzd"
export FZD_GLOBAL_BACKEND=live FZD_PREVIEW_DEPTH=2 FZD_PREVIEW_TIMEOUT=2 FZD_PREVIEW_MAX_LINES=200
export FZD_GLOBAL_MINLEN=2 FZD_GLOBAL_MAXDEPTH=6 FZD_GLOBAL_FULLPATH=0 FZD_EXCLUDES=.git,node_modules FZD_GLOBAL_XEXCLUDES=proc,sys,dev,run
export BASH_ENV=/dev/null FZD_BENCH_SCRIPT="$script"
unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZD_GLOBAL_ROOTS FZD_LOCATE_DBS FZD_COLOR_DIR FZD_COLOR_FILE
socket=""
cleanup() { if [[ -n "$socket" ]]; then tmux -S "$socket" kill-server 2>/dev/null || true; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
now() { REPLY=${EPOCHREALTIME/./}; }
wait_screen() {
  local deadline=$((SECONDS + 90))
  while ((SECONDS < deadline)); do
    screen=$(tmux -S "$socket" capture-pane -p -t fzd:0.0)
    [[ "$screen" == *"$1"* ]] && {
      now
      observed=$REPLY
      return 0
    }
    sleep 0.005
  done
  printf 'Timeout waiting for %s\n%s\n' "$1" "$screen" >&2
  return 1
}
record() { awk -v script="$script" -v count="$count" -v run="$iteration" -v event="$1" -v elapsed="$((observed - start))" 'BEGIN { printf "%s,%d,%d,%s,%.3f\n", script,count,run,event,elapsed/1000 }'; }
printf 'script,entries,run,event,milliseconds\n'
for ((iteration = 1; iteration <= runs; iteration++)); do
  cleanup
  session=$(mktemp -d "$work/session.XXXXXX")
  socket="$session/tmux.sock"
  export FZD_BENCH_GATE="$session/gate" FZD_BENCH_READY="$session/ready"
  export FZD_BENCH_RESULT="$session/result" FZD_BENCH_STATUS="$session/status"
  mkfifo "$FZD_BENCH_GATE"
  printf -v command 'exec bash --noprofile --norc %q' "$repo/benchmarks/terminal-session.sh"
  tmux -S "$socket" -f /dev/null new-session -d -x 120 -y 32 -s fzd -c "$root" "$command"
  deadline=$((SECONDS + 10))
  until [[ -s "$FZD_BENCH_READY" ]]; do
    ((SECONDS < deadline)) || exit 1
    sleep 0.005
  done
  now
  start=$REPLY
  printf 'go\n' >"$FZD_BENCH_GATE"
  wait_screen "$((count + 2))/$((count + 2))"
  record startup
  now
  start=$REPLY
  tmux -S "$socket" send-keys -l zz-nav-child
  wait_screen "1/$((count + 2))"
  record local-query
  now
  start=$REPLY
  tmux -S "$socket" send-keys Right
  wait_screen "$((count + 1))/$((count + 1))"
  record right
  now
  start=$REPLY
  tmux -S "$socket" send-keys Left
  wait_screen "$((count + 2))/$((count + 2))"
  record left
  now
  start=$REPLY
  tmux -S "$socket" send-keys -l file-00001.txt
  wait_screen "1/$((count + 2))"
  record file-query
  wait_screen FZD_PREVIEW_00001
  record preview-first
  now
  start=$REPLY
  tmux -S "$socket" send-keys C-u
  tmux -S "$socket" send-keys -l file-00002.txt
  wait_screen FZD_PREVIEW_00002
  record preview-change
  now
  start=$REPLY
  tmux -S "$socket" send-keys C-f
  wait_screen 'global:/ >'
  record global-open
  now
  start=$REPLY
  tmux -S "$socket" send-keys -l file-00001.txt
  wait_screen '2/2'
  record global-query
  now
  start=$REPLY
  tmux -S "$socket" send-keys Escape
  wait_screen "$((count + 2))/$((count + 2))"
  record global-close
  now
  start=$REPLY
  tmux -S "$socket" send-keys Escape
  deadline=$((SECONDS + 10))
  until [[ -s "$FZD_BENCH_STATUS" ]]; do
    ((SECONDS < deadline)) || exit 1
    sleep 0.005
  done
  now
  observed=$REPLY
  record exit
  [[ $(cat "$FZD_BENCH_STATUS") == 130 && ! -s "$FZD_BENCH_RESULT" ]]
done
