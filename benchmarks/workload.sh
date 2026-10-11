#!/usr/bin/env bash
# Fixed filesystem workload; prepare once, then time independent app processes.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-prepare}
app=${FZD_BENCH_SCRIPT:-$repo/fzd.sh}
work="$repo/.test-work/benchmarks/workload-1000"
locate_tools() {
  # Reuse prepared executables: optional-tool discovery is setup, not query time.
  if [[ -x "$work/bin/plocate" && -x "$work/bin/updatedb" ]]; then
    locate_bin="$work/bin/plocate"
    updatedb_bin="$work/bin/updatedb"
  else
    locate_bin=$(command -v plocate 2>/dev/null || true)
    updatedb_bin=$(command -v updatedb.plocate 2>/dev/null || command -v updatedb 2>/dev/null || true)
  fi
  local tools="$repo/.test-work/tools/root" library
  if [[ -z "$locate_bin" && -x "$tools/usr/bin/plocate" ]]; then
    locate_bin="$tools/usr/bin/plocate"
    updatedb_bin="$tools/usr/sbin/updatedb.plocate"
  fi
  if [[ -x "$tools/usr/bin/plocate" ]]; then
    for library in "$tools"/usr/lib/*-linux-gnu*; do
      [[ -d "$library" ]] || continue
      export LD_LIBRARY_PATH="$library${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    done
  fi
  [[ -x "$locate_bin" && -x "$updatedb_bin" ]] || return 1
}
if [[ "$mode" == prepare ]]; then
  mkdir -p "$work/files" "$work/config" "$work/runtime"
  for ((group = 0; group < 10; group++)); do
    mkdir -p "$work/files/group-$group"
    for ((entry = 0; entry < 100; entry++)); do
      printf -v name 'entry-%04d.txt' "$((group * 100 + entry))"
      [[ "$entry" == 0 ]] && name="needle-$group.txt"
      printf 'FZD benchmark text\n' >"$work/files/group-$group/$name"
    done
  done
  printf '\000\001\002binary\377' >"$work/binary.bin"
  printf 'FZD_GLOBAL_ROOTS=(%q)\nFZD_GLOBAL_MAXRESULTS=2000\n' "$work/files" >"$work/config/fzd.conf"
  exit 0
fi
[[ -f "$work/config/fzd.conf" ]] || {
  echo 'Run benchmarks/workload.sh prepare first' >&2
  exit 1
}
if [[ "$mode" == prepare-locate ]]; then
  locate_tools || {
    echo 'Private locate tools are unavailable' >&2
    exit 1
  }
  mkdir -p "$work/bin"
  if [[ "$locate_bin" != "$work/bin/plocate" ]]; then ln -sf -- "$locate_bin" "$work/bin/plocate"; fi
  if [[ "$updatedb_bin" != "$work/bin/updatedb" ]]; then ln -sf -- "$updatedb_bin" "$work/bin/updatedb"; fi
  "$updatedb_bin" --database-root "$work/files" --output "$work/locate.db" \
    --require-visibility no --prunepaths '' --prunenames '' --prunefs '' --prune-bind-mounts no
  exit 0
fi
export XDG_CONFIG_HOME="$work/config" XDG_STATE_HOME="$work/state"
export XDG_CACHE_HOME="$work/cache" XDG_RUNTIME_DIR="$work/runtime"
export FZD_STATE_DIR="$work/state/fzd" FZD_CACHE_DIR="$work/cache/fzd" FZD_TMP_DIR="$work/runtime/fzd"
export FZD_CONF_FILE="$work/config/fzd.conf" FZD_GLOBAL_BACKEND=live
unset FZD_GLOBAL_ROOTS FZD_LOCATE_DBS
export FZD_GLOBAL_MINLEN=2 FZD_GLOBAL_MAXDEPTH=6 FZD_GLOBAL_FULLPATH=0
export FZD_EXCLUDES=.git,node_modules FZD_GLOBAL_XEXCLUDES=proc,sys,dev,run
case "$mode" in
startup) exec bash "$app" --_global_list --q '' ;;
index) exec bash "$app" --_global_index ;;
query) exec bash "$app" --_global_list --q needle ;;
query-locate)
  locate_tools || exit 1
  export PATH="$work/bin:$PATH" FZD_LOCATE_DBS="$work/locate.db" FZD_GLOBAL_BACKEND=locate
  exec bash "$app" --_global_list --q needle
  ;;
preview)
  encoded=$(printf '%s' "$work/files/group-0/entry-0001.txt" | base64 | tr -d '\n')
  exec bash "$app" --_preview "$encoded"
  ;;
preview-dir | preview-binary)
  path=${FZD_BENCH_PREVIEW_PATH:-$work/files}
  [[ "$mode" == preview-binary ]] && path="$work/binary.bin"
  encoded=$(printf '%s' "$path" | base64 -w 0)
  exec bash "$app" --_preview "$encoded"
  ;;
*)
  printf 'Unknown benchmark mode: %s\n' "$mode" >&2
  exit 2
  ;;
esac
