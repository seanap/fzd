#!/usr/bin/env bash
# fzd.sh — Omarchy-optimized TUI (fzf + preview + editor + Ctrl-F global search)
# Keys:
#  - Left  : up (preselect child)
#  - Right : into dir
#  - Enter : dir -> print & exit; file -> open in editor then resume
#  - Esc   : exit
#  - Ctrl+F: global search overlay (locate/fd)
#
# Design goals for Omarchy:
# - XDG paths only (no ~/.fzd): config in ~/.config/fzd, state in ~/.local/state/fzd, cache in ~/.cache/fzd,
#   tmp in $XDG_RUNTIME_DIR/fzd if set, else ~/.cache/fzd/tmp.
# - Do NOT clobber FZF_DEFAULT_OPTS so Omarchy/Hyprland/Alacritty themes are inherited.
# - Optional per-entry color via FZD_COLOR_DIR / FZD_COLOR_FILE (hex like #aabbcc). Default: no extra color.

set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
export LC_ALL=C

# ----------------- XDG + PATHS -----------------
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
# tmp: prefer runtime dir (per-session), else cache
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
  : "${FZD_TMP_DIR:=$XDG_RUNTIME_DIR/fzd}"
else
  : "${FZD_TMP_DIR:=$XDG_CACHE_HOME/fzd/tmp}"
fi
: "${FZD_STATE_DIR:=$XDG_STATE_HOME/fzd}"
: "${FZD_CACHE_DIR:=$XDG_CACHE_HOME/fzd}"

mkdir -p "$FZD_STATE_DIR" "$FZD_CACHE_DIR" "$FZD_TMP_DIR" 2>/dev/null || true
# Encourage mktemp to use our tmp dir
export TMPDIR="$FZD_TMP_DIR"

# ----------------- CONFIG DEFAULTS -----------------
# Load user config from XDG (no legacy ~/.fzd)
FZD_CONF_FILE="${FZD_CONF_FILE:-$XDG_CONFIG_HOME/fzd/fzd.conf}"
[[ -f "$FZD_CONF_FILE" ]] && source "$FZD_CONF_FILE"

: "${FZD_GLOBAL_BACKEND:=auto}"           # auto|locate|cache|live (auto prefers locate if present)
: "${FZD_GLOBAL_MINLEN:=2}"
: "${FZD_GLOBAL_MAXDEPTH:=6}"
: "${FZD_GLOBAL_MAXRESULTS:=1200}"
: "${FZD_GLOBAL_PATHS:=/etc /opt /srv /mnt /home/$USER}"
: "${FZD_GLOBAL_FULLPATH:=0}"
: "${FZD_LOCATE_DBS:=}" 
: "${FZD_GLOBAL_XEXCLUDES:=proc,sys,dev,run,proc/*,sys/*,dev/*,run/*,snap,lost+found,var/lib/docker}"

: "${FZD_DEBUG:=0}"
: "${FZD_GLOBAL_ROOT:=/}"                 # filesystem root label for overlay prompt
: "${FZD_EXCLUDES:=.git,node_modules,.cache,.venv,__pycache__}"
: "${FZD_PREVIEW_DEPTH:=2}"
: "${FZD_PREVIEW_MAX_LINES:=200}"
: "${FZD_PREVIEW_TIMEOUT:=2}"

# ----------------- THEME (inherit system unless user opts-in) -----------------
# If the user sets FZD_COLOR_DIR/FILE to hex (#RRGGBB), use that; else leave empty to inherit fzf theme.
c_reset=$'\033[0m'
hex_to_ansi() {
  local h="${1#\#}"
  [[ ${#h} -eq 6 ]] || return 0
  printf '\033[38;2;%d;%d;%dm' $((16#${h:0:2})) $((16#${h:2:2})) $((16#${h:4:2}))
}
c_dir=""; c_file=""
[[ -n "${FZD_COLOR_DIR:-}"  ]] && c_dir="$(hex_to_ansi "$FZD_COLOR_DIR")"
[[ -n "${FZD_COLOR_FILE:-}" ]] && c_file="$(hex_to_ansi "$FZD_COLOR_FILE")"

# ----------------- FZF hardening -----------------
FZF_BIN="$(type -P fzf 2>/dev/null || command -v fzf || true)"
[[ -x "$FZF_BIN" ]] || { echo "fzd: ERROR: fzf not found" >&2; exit 1; }

# Preserve FZF_DEFAULT_OPTS so system theme applies;
# but neutralize default picker commands that could interfere with our UI.
unset FZF_CTRL_T_COMMAND FZF_ALT_C_COMMAND FZF_DEFAULT_COMMAND 2>/dev/null || true

# ----------------- DEBUG -----------------
dbg() { (( FZD_DEBUG == 1 )) && printf 'fzd: %s\n' "$*" > /dev/tty || true; }
ppath() { printf '%s' "${1/#$HOME/~}"; }

# ----------------- COMMON HELPERS -----------------
DELIM=$'\t'
declare -A LAST_CHILD=()   # parent_abs -> child_basename
START_POS=""
CUR=""

normalize_path() {
  local p="${1//\/\//\/}"
  [[ "$p" != "/" ]] && p="${p%/}"
  printf '%s' "$p"
}
get_cwd() { ( CDPATH= cd -L -- "${1:-$PWD}" 2>/dev/null && pwd -L ) || pwd -L; }
join_path() { local base="$1" child="${2#/}"; [[ "$base" == "/" ]] && printf '/%s' "$child" || printf '%s/%s' "$base" "$child"; }
b64()   { printf '%s' "$1" | base64 | tr -d '\n'; }
deb64() { printf '%s' "$1" | base64 -d 2>/dev/null || true; }

remember_child() { local parent="$1" child="$2"; [[ -n "$parent" && -n "$child" ]] && LAST_CHILD["$parent"]="$child" && dbg "remember_child: [$parent]='$child'"; }
go_up() {
  local parent child
  parent="$(normalize_path "$(dirname "$CUR")")"
  child="$(basename "$CUR")"
  remember_child "$parent" "$child"
  CUR="$parent"
  dbg "LEFT -> CUR=$CUR (preselect child='$child')"
}
enter_dir_from_raw() {
  local parent; parent="$(normalize_path "$(dirname "$CUR")")"
  [[ -z "${RAW:-}" || ! -d "$RAW" || "$RAW" == "$parent" ]] && { dbg "RIGHT ignored (RAW='$RAW')"; return; }
  remember_child "$CUR" "$(basename "$RAW")"
  CUR="$(normalize_path "$RAW")"
  dbg "RIGHT -> into '$CUR'"
}
print_cd_target() { printf '%s\n' "$RAW"; }

# ----------------- LISTING (no duplicates) -----------------
list_entries() {
  DIRS=(); FILES=()

  local oldopt; oldopt="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob

  local path base
  # dirs (include dot dirs; not using dotglob)
  for path in "$CUR"/*/ "$CUR"/.[!.]*/ "$CUR"/..?*/; do
    [[ -d "$path" ]] || continue
    base="${path%/}"; base="${base##*/}"
    DIRS+=("${base}/")
  done
  # files
  for path in "$CUR"/* "$CUR"/.[!.]* "$CUR"/..?*; do
    [[ -f "$path" ]] || continue
    base="${path##*/}"
    FILES+=("$base")
  done

  if (( ${#DIRS[@]} > 1 )); then
    IFS=$'\n' read -r -d '' -a DIRS < <(printf '%s\n' "${DIRS[@]}" | sort -f && printf '\0')
  fi
  if (( ${#FILES[@]} > 1 )); then
    IFS=$'\n' read -r -d '' -a FILES < <(printf '%s\n' "${FILES[@]}" | sort -f && printf '\0')
  fi

  eval "$oldopt" 2>/dev/null || true
}

build_lines() {
  LINES=(); START_POS=""
  local parent; parent="$(normalize_path "$(dirname "$CUR")")"
  LINES+=("$(b64 "$parent")${DELIM}${c_dir}../${c_reset}")

  local want_child="${LAST_CHILD[$CUR]:-}"
  local idx=0
  for d in "${DIRS[@]}"; do
    local name="${d%/}"
    local p; p="$(normalize_path "$(join_path "$CUR" "$name")")"
    LINES+=("$(b64 "$p")${DELIM}${c_dir}${d}${c_reset}")
    if [[ -n "$want_child" && "$name" == "$want_child" ]]; then
      START_POS=$(( 2 + idx ))   # 1=../, dirs start at 2; idx is 0-based
    fi
    ((idx+=1))
  done
  for f in "${FILES[@]}"; do
    local p; p="$(normalize_path "$(join_path "$CUR" "$f")")"
    LINES+=("$(b64 "$p")${DELIM}${c_file}${f}${c_reset}")
  done
}

# ---- Build a one-shot index (fd) for cache backend ----
if [[ "${1:-}" == "--_global_index" ]]; then
  : "${FZD_GLOBAL_MAXDEPTH:=7}"
  mapfile -d '' roots  < <(_global_roots_array)
  mapfile -d '' ex     < <(_global_excludes_array)

  FD_BIN="$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || true)"
  if [[ -n "$FD_BIN" ]]; then
    # list dirs + files up to depth, include hidden, case-insensitive, no follow
    cmd=( "$FD_BIN" -H -i --color=never -a -d "$FZD_GLOBAL_MAXDEPTH" . )
    for g in "${ex[@]}"; do [[ -n "$g" ]] && cmd+=( --exclude "$g" ); done
    for r in "${roots[@]}"; do cmd+=( "$r" ); done

    "${cmd[@]}" 2>/dev/null \
    | head -n "${FZD_GLOBAL_MAXRESULTS:-12000}" \
    | awk -v cd="$c_dir" -v cf="$c_file" -v cr="$c_reset" '
        {
          p=$0; n=split(p,a,"/"); base=a[n];
          cmd = "printf %s \"" p "\" | base64 | tr -d \"\n\""; cmd | getline b64; close(cmd);
          if (system("[ -d \"" p "\" ]")==0) printf "%s\t%s%s/%s\n", b64, cd, base, cr;
          else if (system("[ -f \"" p "\" ]")==0) printf "%s\t%s%s%s\n", b64, cf, base, cr;
        }'
    exit 0
  fi
  exit 0
fi

# ----------------- PREVIEW (early exit; no debug) -----------------
_have() { command -v "$1" >/dev/null 2>&1; }
_timeout_wrap() { local s="$1"; shift; if (( s > 0 )) && _have timeout; then timeout "${s}s" "$@"; else "$@"; fi; }

_preview_dir() {
  local dir="$1" depth="${2:-2}"
  if command -v eza >/dev/null 2>&1; then
    local IFS=','; read -ra _ex <<<"$FZD_EXCLUDES"
    local ig=(); for g in "${_ex[@]}"; do [[ -n "$g" ]] && ig+=( --ignore-glob "$g" ); done
    _timeout_wrap "$FZD_PREVIEW_TIMEOUT" eza --tree -L "$depth" --group-directories-first --color=always --icons \
      "${ig[@]}" -- "$dir"
    return
  fi
  if command -v tree >/dev/null 2>&1; then
    local IFS=','; read -ra _ex <<<"$FZD_EXCLUDES"
    local patt=""; for g in "${_ex[@]}"; do [[ -n "$patt" ]] && patt+='|'; patt+="$g"; done
    if [[ -n "$patt" ]]; then _timeout_wrap "$FZD_PREVIEW_TIMEOUT" tree -a -C -L "$depth" -I "$patt" -- "$dir"
    else _timeout_wrap "$FZD_PREVIEW_TIMEOUT" tree -a -C -L "$depth" -- "$dir"; fi
    return
  fi
  ls -A -- "$dir"
}
_preview_file() {
  local file="$1"
  local is_text=0
  if command -v file >/dev/null 2>&1; then
    file -b --mime-type -- "$file" | grep -qE '^text/|json|xml|x-sh|javascript' && is_text=1
  else
    head -c 4096 -- "$file" | tr -d '\000' | grep -q $'\n' && is_text=1
  fi
  if (( is_text )); then
    local batbin=""; command -v bat >/dev/null 2>&1 && batbin="bat"; [[ -z "$batbin" ]] && command -v batcat >/dev/null 2>&1 && batbin="batcat"
    if [[ -n "$batbin" ]]; then
      _timeout_wrap "$FZD_PREVIEW_TIMEOUT" "$batbin" --color=always --pager=never --line-range ":$FZD_PREVIEW_MAX_LINES" -- "$file"
    else
      _timeout_wrap "$FZD_PREVIEW_TIMEOUT" head -n "$FZD_PREVIEW_MAX_LINES" -- "$file"
    fi
  else
    printf '⚙ %s\n' "$(file -b -- "$file" 2>/dev/null || echo binary)"
    ls -lh -- "$file" 2>/dev/null || true
    command -v hexdump >/dev/null 2>&1 && { echo; hexdump -C -- "$file" | head -n 64; }
  fi
}
if [[ "${1:-}" == "--_preview" ]]; then
  FZD_DEBUG=0
  b64_in="$2"; sel_path="$(printf '%s' "$b64_in" | base64 -d 2>/dev/null || true)"
  [[ -z "$sel_path" ]] && exit 0
  if [[ -d "$sel_path" ]]; then _preview_dir "$sel_path" "$FZD_PREVIEW_DEPTH"
  elif [[ -f "$sel_path" ]]; then _preview_file "$sel_path"
  else echo "(missing)"; fi
  exit 0
fi

# ----------------- GLOBAL LIST SUBCOMMAND (for Ctrl+F overlay reload) -----------------
if [[ "${1:-}" == "--_global_list" ]]; then
  shift
  [[ "${1:-}" == "--q" ]] && shift || true
  q="$*"

  # ---- knobs (env overridable; safe with set -u via :=) ----
  : "${FZD_GLOBAL_MINLEN:=3}"
  : "${FZD_GLOBAL_MAXRESULTS:=3000}"
  : "${FZD_GLOBAL_PATHS:=/etc /opt /srv /mnt /home/$USER}"
  : "${FZD_GLOBAL_XEXCLUDES:=proc,sys,dev,run,proc/*,sys/*,dev/*,run/*,mnt/c,mnt/d,snap,lost+found,var/lib/docker}"
  : "${FZD_GLOBAL_FULLPATH:=0}"
  : "${FZD_LOCATE_DBS:=}"

  [[ ${#q} -lt ${FZD_GLOBAL_MINLEN} ]] && exit 0

  # expand shell vars in roots (e.g. $USER)
  # shellcheck disable=SC2016
  read -r -a roots <<<"$(eval echo "$FZD_GLOBAL_PATHS")"

  roots_re=""
  for r in "${roots[@]}"; do
    r="${r%/}"; [[ -z "$r" ]] && r="/"
    esc="$(printf '%s' "$r" | sed 's/[.[\()*^$+?{}|]/\\&/g')"
    roots_re+="${roots_re:+|}${esc}(/|$)"
  done
  [[ -n "$roots_re" ]] && roots_re="^(${roots_re})"

  IFS=',' read -ra ex1 <<<"${FZD_EXCLUDES:-.git,node_modules,.cache,.venv,__pycache__}"
  IFS=',' read -ra ex2 <<<"$FZD_GLOBAL_XEXCLUDES"
  ex_re=""
  for g in "${ex1[@]}" "${ex2[@]}"; do
    [[ -z "$g" ]] && continue
    g="${g%/}"
    escg="$(printf '%s' "$g" | sed 's/[.[\()*^$+?{}|]/\\&/g')"
    ex_re+="${ex_re:+|}/${escg}(/|$)"
  done
  [[ -n "$ex_re" ]] && ex_re="(${ex_re})"

  # prefer plocate/locate
  LOC="$(command -v plocate 2>/dev/null || command -v locate 2>/dev/null || true)"
  if [[ -n "$LOC" ]]; then
    _max="${FZD_GLOBAL_MAXRESULTS:-3000}"
    db_args=()
    [[ -n "$FZD_LOCATE_DBS" ]] && db_args=(-d "$FZD_LOCATE_DBS")

    env -u LOCATE_PATH "$LOC" "${db_args[@]}" -i -e -l "$_max" -- "$q" 2>/dev/null \
    | awk -v rr="$roots_re" -v xr="$ex_re" '
        BEGIN{IGNORECASE=1}
        { p=$0; if (rr != "" && p !~ rr) next; if (xr != "" && p ~ xr) next; print p }
      ' 2>/dev/null \
    | awk -v cd="$c_dir" -v cf="$c_file" -v cr="$c_reset" '
        {
          p=$0; n=split(p,a,"/"); base=a[n]
          if (system("[ -d \"" p "\" ]")==0) { cmd="printf %s \"" p "\" | base64 | tr -d \"\n\""; cmd|getline b64; close(cmd); printf "%s\t%s%s/%s\n", b64, cd, base, cr }
          else if (system("[ -f \"" p "\" ]")==0) { cmd="printf %s \"" p "\" | base64 | tr -d \"\n\""; cmd|getline b64; close(cmd); printf "%s\t%s%s%s\n", b64, cf, base, cr }
        }
      ' 2>/dev/null
    exit 0
  fi

  # fd / find fallback
  IFS=',' read -ra ex1 <<<"${FZD_EXCLUDES:-.git,node_modules,.cache,.venv,__pycache__}"
  IFS=',' read -ra ex2 <<<"$FZD_GLOBAL_XEXCLUDES"
  ex=("${ex1[@]}" "${ex2[@]}")

  FD_BIN="$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || true)"
  if [[ -n "$FD_BIN" ]]; then
    cmd=( "$FD_BIN" -H -i --color=never -a -d "${FZD_GLOBAL_MAXDEPTH:-6}" )
    if [[ "$FZD_GLOBAL_FULLPATH" == "1" ]]; then
      cmd+=( --full-path --fixed-strings "$q" )
    else
      cmd+=( --fixed-strings "$q" )
    fi
    for g in "${ex[@]}"; do [[ -n "$g" ]] && cmd+=( --exclude "$g" ); done
    cmd+=( "${roots[@]}" )

    "${cmd[@]}" 2>/dev/null | while IFS= read -r p; do
      base="$(basename -- "$p")"
      b64="$(printf '%s' "$p" | base64 | tr -d '\n')"
      if [[ -d "$p" ]]; then
        printf '%s\t%s%s/%s\n' "$b64" "$c_dir" "$base" "$c_reset"
      elif [[ -f "$p" ]]; then
        printf '%s\t%s%s%s\n' "$b64" "$c_file" "$base" "$c_reset"
      fi
    done
    exit 0
  fi

  # POSIX find fallback
  prune=()
  for g in "${ex[@]}"; do [[ -n "$g" ]] && prune+=( -o -path "*/$g/*" ); done

  if [[ "$FZD_GLOBAL_FULLPATH" == "1" ]]; then
    # shellcheck disable=SC2046
    find "${roots[@]}" \( -false $(printf ' %s' "${prune[@]}") \) -prune -o \
         -type d -o -type f -print 2>/dev/null |
    grep -F "$q" | while IFS= read -r p; do
      base="$(basename -- "$p")"
      b64="$(printf '%s' "$p" | base64 | tr -d '\n')"
      if [[ -d "$p" ]]; then printf '%s\t%s%s/%s\n' "$b64" "$c_dir" "$base" "$c_reset"
      elif [[ -f "$p" ]]; then printf '%s\t%s%s%s\n' "$b64" "$c_file" "$base" "$c_reset"
      fi
    done
  else
    # shellcheck disable=SC2046
    find "${roots[@]}" \( -false $(printf ' %s' "${prune[@]}") \) -prune -o \
         -type d -o -type f -print 2>/dev/null |
    awk -v q="$q" -v cd="$c_dir" -v cf="$c_file" -v cr="$c_reset" '
      BEGIN{IGNORECASE=1}
      {
        p=$0; n=split(p,a,"/"); base=a[n]
        if (index(base,q) > 0) {
          cmd="printf %s \"" p "\" | base64 | tr -d \"\n\""; cmd|getline b64; close(cmd)
          if (system("[ -d \"" p "\" ]")==0) printf "%s\t%s%s/%s\n", b64, cd, base, cr;
          else if (system("[ -f \"" p "\" ]")==0) printf "%s\t%s%s%s\n", b64, cf, base, cr;
        }
      }' 2>/dev/null
  fi
  exit 0
fi

# ----------------- caret support probe -----------------
HAS_POS=0
if printf 'x\n' | "$FZF_BIN" --bind='start:pos(1)' --select-1 --exit-0 >/dev/null 2>&1; then HAS_POS=1; fi
dbg "start:pos supported: $HAS_POS"

# ----------------- EDITOR -----------------
EDITOR_CMD="${EDITOR:-${VISUAL:-micro}}"
command -v "$EDITOR_CMD" >/dev/null 2>&1 || EDITOR_CMD="micro"

_open_in_editor() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  "$EDITOR_CMD" -- "$file" </dev/tty >/dev/tty 2>&1 || true
}

# ----------------- GLOBAL OVERLAY -----------------
_has() { command -v "$1" >/dev/null 2>&1; }

_global_roots_array() {
  local -a roots; read -r -a roots <<<"$FZD_GLOBAL_PATHS"
  printf '%s\0' "${roots[@]}"
}

_global_excludes_array() {
  local IFS=','; read -ra ex1 <<<"${FZD_EXCLUDES:-.git,node_modules,.cache,.venv,__pycache__}"
  local IFS=','; read -ra ex2 <<<"${FZD_GLOBAL_XEXCLUDES}"
  printf '%s\0' "${ex1[@]}" "${ex2[@]}"
}

_run_global_overlay() {
  dbg "GLOBAL overlay start (backend=${FZD_GLOBAL_BACKEND:-auto})"
  local backend="${FZD_GLOBAL_BACKEND:-auto}"
  local have_loc
  have_loc="$(command -v plocate 2>/dev/null || command -v locate 2>/dev/null || true)"

  # auto-pick: prefer locate, else cache
  [[ "$backend" == "auto" ]] && { if [[ -n "$have_loc" ]]; then backend="locate"; else backend="cache"; fi; }

  local CTRL SRC
  if [[ "$backend" == "locate" ]]; then
    CTRL="$(mktemp)"
    "$FZF_BIN" \
      --ansi --height=100% --layout=reverse --border --no-mouse \
      --delimiter "$DELIM" --with-nth=2.. \
      --prompt "global:${FZD_GLOBAL_ROOT%/}/ > " \
      --disabled \
      --preview "$0 --_preview {1}" \
      --preview-window=right,60%:wrap \
      --bind "change:reload:$0 --_global_list --q {q}" \
      --bind "esc:abort" \
      --bind "enter:execute-silent(echo A:G_ENTER:{1} > $CTRL)+abort" \
      --bind "left:execute-silent(echo A:G_LEFT:{1} > $CTRL)+abort" \
      --bind "right:execute-silent(echo A:G_RIGHT:{1} > $CTRL)+abort" \
      >/dev/null || true

  elif [[ "$backend" == "cache" ]]; then
    CTRL="$(mktemp)"
    SRC="$(mktemp)"
    "$0" --_global_index > "$SRC"
    cat "$SRC" | "$FZF_BIN" \
      --ansi --height=100% --layout=reverse --border --no-mouse \
      --delimiter "$DELIM" --with-nth=2.. \
      --prompt "global:${FZD_GLOBAL_ROOT%/}/ > " \
      --preview "$0 --_preview {1}" \
      --preview-window=right,60%:wrap \
      --bind "esc:abort" \
      --bind "enter:execute-silent(echo A:G_ENTER:{1} > $CTRL)+abort" \
      --bind "left:execute-silent(echo A:G_LEFT:{1} > $CTRL)+abort" \
      --bind "right:execute-silent(echo A:G_RIGHT:{1} > $CTRL)+abort" \
      >/dev/null || true
    rm -f "$SRC"

  else
    "$FZF_BIN" --prompt "global:${FZD_GLOBAL_ROOT%/}/ > " --disabled \
      --bind "esc:abort" >/dev/null || true
    return
  fi

  # read the overlay action
  sleep 0.005
  local action_line raw_b64 action sel_path
  action_line="$(grep -m1 '^A:' "$CTRL" || true)"
  raw_b64="$(printf '%s' "$action_line" | cut -d: -f3-)"
  action="$(printf '%s' "$action_line" | cut -d: -f2)"
  sel_path="$(normalize_path "$(deb64 "$raw_b64")")"
  rm -f "$CTRL"

  [[ -z "${action:-}" ]] && { dbg "GLOBAL overlay cancelled"; return; }

  case "$action" in
    G_RIGHT)
      [[ -d "$sel_path" ]] && { RAW="$sel_path"; enter_dir_from_raw; }
      ;;
    G_ENTER)
      if [[ -d "$sel_path" ]]; then
        RAW="$sel_path"; print_cd_target; exit 0
      elif [[ -f "$sel_path" ]]; then
        _open_in_editor "$sel_path"
        CUR="$(normalize_path "$(dirname -- "$sel_path")")"
        remember_child "$(dirname -- "$CUR")" "$(basename -- "$CUR")"
      fi
      ;;
  esac
}

# ----------------- MAIN LOOP -----------------
main() {
  CUR="$(normalize_path "$(get_cwd)")"
  dbg "cwd=$CUR"

  local HIST_FILE="$FZD_STATE_DIR/query-history"
  mkdir -p "$(dirname "$HIST_FILE")" 2>/dev/null || true

  while :; do
    list_entries
    build_lines

    local START_OPT=()
    if (( HAS_POS == 1 )) && [[ -n "${START_POS:-}" ]]; then
      dbg "apply caret: pos(${START_POS})"
      START_OPT+=( --bind "start:pos(${START_POS}),load:pos(${START_POS})" )
    else
      dbg "no caret this frame"
    fi
    START_POS=""

    local CTRL; CTRL="$(mktemp)"
    mapfile -t FZF_OUT < <(
      printf '%s\n' "${LINES[@]}" | "$FZF_BIN" \
        --ansi --height=100% --layout=reverse --border --no-mouse \
        --delimiter "$DELIM" --with-nth=2.. \
        --prompt "$(ppath "$CUR")/ > " \
        --print-query --history="$HIST_FILE" --history-size=4000 \
        "${START_OPT[@]}" \
        --preview "$0 --_preview {1}" \
        --preview-window=right,60%:wrap \
        --expect=ctrl-f \
        --bind "esc:abort" \
        --bind "ctrl-f:abort" \
        --bind "enter:execute-silent(echo A:ENTER:{1} > $CTRL)+abort" \
        --bind "left:execute-silent(echo A:LEFT:{1} > $CTRL)+abort" \
        --bind "right:execute-silent(echo A:RIGHT:{1} > $CTRL)+abort" \
        || true
    )

    sleep 0.005

    # If Ctrl-F was pressed (with --print-query + --expect order ambiguity)
    if [[ "${FZF_OUT[0]:-}" == "ctrl-f" || "${FZF_OUT[1]:-}" == "ctrl-f" ]]; then
      (( FZD_DEBUG == 1 )) && printf 'fzd: ctrl-f detected via expect\n' > /dev/tty
      _run_global_overlay
      rm -f "$CTRL"
      continue
    fi

    # Wait briefly for the temp-file write
    for _i in {1..20}; do
      [[ -s "$CTRL" ]] && break
      sleep 0.01
    done

    local action_line raw_b64 action
    action_line="$(grep -m1 '^A:' "$CTRL" || true)"
    raw_b64="$(printf '%s' "$action_line" | cut -d: -f3-)"
    action="$(printf '%s' "$action_line" | cut -d: -f2)"
    RAW="$(normalize_path "$(deb64 "$raw_b64")")"
    rm -f "$CTRL"

    [[ -z "${action:-}" ]] && { dbg "fzf aborted (Esc/close)"; exit 130; }

    case "$action" in
      LEFT)
        go_up
        ;;
      RIGHT)
        enter_dir_from_raw
        ;;
      ENTER)
        if [[ -n "$RAW" && -d "$RAW" ]]; then
          local parent; parent="$(normalize_path "$(dirname "$CUR")")"
          local target="$RAW"
          if [[ "$RAW" == "$parent" ]]; then
            target="$CUR"
            dbg "ENTER on ../ -> cd '$target'"
          else
            dbg "ENTER dir -> $target"
          fi
          RAW="$target"
          print_cd_target; exit 0

        elif [[ -n "$RAW" && -f "$RAW" ]]; then
          dbg "ENTER file -> editor"
          _open_in_editor "$RAW"
          # stay in current CUR; refresh
        fi
        ;;
      *)
        dbg "unknown action '$action' (ignored)"
        ;;
    esac
  done
}

main "$@"
