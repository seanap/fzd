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

# ----------------- PREVIEW (early exit; no debug) -----------------
_have() { command -v "$1" >/dev/null 2>&1; }
_timeout_wrap() { local s="$1"; shift; if (( s > 0 )) && _have timeout; then timeout "${s}s" "$@"; else "$@"; fi; }

_preview_dir() {
  local dir="$1" depth="${2:-2}"

  # Prefer eza for previews.
  # We want the preview to follow the same dir/file colors as the left pane when possible.
  # eza uses LS_COLORS. We'll generate Catppuccin Mocha LS_COLORS via vivid when available,
  # then override just di/fi using the user's FZD_COLOR_DIR/FZD_COLOR_FILE.
  if command -v eza >/dev/null 2>&1; then
    local IFS=','; read -ra _ex <<<"$FZD_EXCLUDES"
    local ig=(); for g in "${_ex[@]}"; do [[ -n "$g" ]] && ig+=( --ignore-glob "$g" ); done

    _lscolors_override() {
      # Output LS_COLORS string to stdout.
      # If vivid exists, start from its catppuccin-mocha preset; else start from current LS_COLORS.
      local base="${LS_COLORS:-}"
      if command -v vivid >/dev/null 2>&1; then
        base="$(vivid generate catppuccin-mocha 2>/dev/null || true)"
      fi

      # If user provided hex colors, translate to SGR for LS_COLORS.
      # LS_COLORS expects codes like: di=38;2;R;G;B; fi=38;2;R;G;B
      # (works with GNU dircolors/ls; eza follows LS_COLORS too.)
      local di="" fi=""
      if [[ -n "${FZD_COLOR_DIR:-}" && "${FZD_COLOR_DIR}" =~ ^#?[0-9A-Fa-f]{6}$ ]]; then
        local h="${FZD_COLOR_DIR#\#}"
        local r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))
        di="di=38;2;${r};${g};${b}"
      fi
      if [[ -n "${FZD_COLOR_FILE:-}" && "${FZD_COLOR_FILE}" =~ ^#?[0-9A-Fa-f]{6}$ ]]; then
        local h="${FZD_COLOR_FILE#\#}"
        local r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))
        fi="fi=38;2;${r};${g};${b}"
      fi

      # Strip existing di/fi and append overrides.
      # This is intentionally simple: keep whatever vivid/system provides for other file types.
      local out="$base"
      out="$(printf '%s' "$out" | sed -E 's/(^|:)di=[^:]*:?//g; s/(^|:)fi=[^:]*:?//g; s/^:+|:+$//g')"
      [[ -n "$out" && ( -n "$di" || -n "$fi" ) ]] && out+="${out:+:}"
      [[ -n "$di" ]] && out+="$di"
      [[ -n "$di" && -n "$fi" ]] && out+=':'
      [[ -n "$fi" ]] && out+="$fi"
      printf '%s' "$out"
    }

    local lsc; lsc="$(_lscolors_override)"
    if [[ -n "$lsc" ]]; then
      LS_COLORS="$lsc" _timeout_wrap "$FZD_PREVIEW_TIMEOUT" eza --tree -L "$depth" --group-directories-first --color=always --icons \
        "${ig[@]}" -- "$dir"
    else
      _timeout_wrap "$FZD_PREVIEW_TIMEOUT" eza --tree -L "$depth" --group-directories-first --color=always --icons \
        "${ig[@]}" -- "$dir"
    fi
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
# Expand variable references in legacy root strings without evaluating shell code.
# Config files remain trusted shell code; FZD_GLOBAL_ROOTS is the lossless array form.
_global_expand_vars() {
  local rest="$1" out="" prefix name token
  while [[ "$rest" =~ ^([^\$]*)\$(\{([a-zA-Z_][a-zA-Z_0-9]*)\}|([a-zA-Z_][a-zA-Z_0-9]*)) ]]; do
    prefix=${BASH_REMATCH[1]}
    token=${BASH_REMATCH[0]}
    name=${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}
    out+="$prefix${!name-}"
    rest=${rest:${#token}}
  done
  REPLY="$out$rest"
}

_global_prepare() {
  local declaration root expanded name
  GLOBAL_ROOTS=(); GLOBAL_EXCLUDES=()
  declaration=$(declare -p FZD_GLOBAL_ROOTS 2>/dev/null || true)
  if [[ "$declaration" == 'declare -a '* ]]; then
    # shellcheck disable=SC2153 # Optional Bash array supplied by user configuration.
    GLOBAL_ROOTS=("${FZD_GLOBAL_ROOTS[@]}")
  else
    _global_expand_vars "$FZD_GLOBAL_PATHS"
    expanded=$REPLY
    read -r -a GLOBAL_ROOTS <<< "$expanded"
  fi
  local valid=()
  for root in "${GLOBAL_ROOTS[@]}"; do
    [[ "$root" == /* ]] || root="$PWD/$root"
    [[ "$root" == / ]] || root=${root%/}
    [[ -d "$root" && -r "$root" && -x "$root" ]] && valid+=("$root")
  done
  GLOBAL_ROOTS=("${valid[@]}")
  if ((${#GLOBAL_ROOTS[@]} == 0)); then
    printf 'fzd: no accessible global search roots configured\n' >&2
    return 1
  fi
  local first=() second=()
  IFS=',' read -r -a first <<< "$FZD_EXCLUDES"
  IFS=',' read -r -a second <<< "$FZD_GLOBAL_XEXCLUDES"
  GLOBAL_EXCLUDES=("${first[@]}" "${second[@]}")
  for name in FZD_GLOBAL_MINLEN FZD_GLOBAL_MAXDEPTH; do
    if [[ ! ${!name} =~ ^(0|[1-9][0-9]*)$ ]]; then
      printf 'fzd: %s must be a nonnegative integer\n' "$name" >&2
      return 1
    fi
  done
  if [[ ! $FZD_GLOBAL_MAXRESULTS =~ ^[1-9][0-9]*$ ]]; then
      name=FZD_GLOBAL_MAXRESULTS
      printf 'fzd: %s must be a positive integer\n' "$name" >&2
      return 1
  fi
  if [[ "$FZD_GLOBAL_FULLPATH" != 0 && "$FZD_GLOBAL_FULLPATH" != 1 ]]; then
    printf 'fzd: FZD_GLOBAL_FULLPATH must be 0 or 1\n' >&2
    return 1
  fi
  case "$FZD_GLOBAL_BACKEND" in
    auto|locate|cache|live) ;;
    *) printf 'fzd: unknown global backend: %s\n' "$FZD_GLOBAL_BACKEND" >&2; return 1 ;;
  esac
}

_global_allowed() {
  local path=$1 root pattern inside=0
  for root in "${GLOBAL_ROOTS[@]}"; do
    if [[ "$root" == / || "$path" == "$root" || "$path" == "$root/"* ]]; then
      inside=1
      break
    fi
  done
  ((inside)) || return 1
  for pattern in "${GLOBAL_EXCLUDES[@]}"; do
    pattern=${pattern%/}
    [[ -z "$pattern" ]] && continue
    # Deliberate glob matching against complete path components, never shell code.
    if [[ "$path/" == */$pattern/* ]]; then return 1; fi
  done
  return 0
}

_global_format() {
  local query=$1 path base candidate encoded color suffix count=0
  while IFS= read -r -d '' path; do
    [[ "$path" == / ]] || path=${path%/}
    _global_allowed "$path" || continue
    base=${path##*/}
    [[ -n "$base" ]] || base=/
    candidate=$base
    [[ "$FZD_GLOBAL_FULLPATH" == 1 ]] && candidate=$path
    [[ "${candidate,,}" == *"${query,,}"* ]] || continue
    if [[ -d "$path" ]]; then
      color=$c_dir; suffix=/
    elif [[ -f "$path" ]]; then
      color=$c_file; suffix=""
    else
      continue
    fi
    encoded=$(b64 "$path") || return 1
    # Encode identity independently; control characters must not create records.
    base=${base//\\/\\\\}
    base=${base//$'\n'/\\n}; base=${base//$'\r'/\\r}; base=${base//$'\t'/\\t}
    base=${base//$'\033'/\\e}
    printf '%s\t%s%s%s%s\n' "$encoded" "$color" "$base" "$suffix" "$c_reset" || return 1
    ((count += 1))
    if ((count >= FZD_GLOBAL_MAXRESULTS)); then break; fi
  done
  return 0
}

_global_live_candidates() {
  local query=$1 fd_bin pattern
  fd_bin=$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || true)
  local command=()
  if [[ -n "$fd_bin" ]]; then
    command=("$fd_bin" -H -i --color=never -a --print0 -d "$FZD_GLOBAL_MAXDEPTH")
    [[ "$FZD_GLOBAL_FULLPATH" == 1 ]] && command+=(--full-path)
    for pattern in "${GLOBAL_EXCLUDES[@]}"; do
      [[ -n "$pattern" ]] && command+=(--exclude "$pattern")
    done
    command+=(--fixed-strings -- "$query" "${GLOBAL_ROOTS[@]}")
  else
    command=(find -H "${GLOBAL_ROOTS[@]}" -mindepth 1 -maxdepth "$FZD_GLOBAL_MAXDEPTH" '(' -false)
    for pattern in "${GLOBAL_EXCLUDES[@]}"; do
      pattern=${pattern%/}
      [[ -n "$pattern" ]] && command+=(-o -path "*/$pattern" -o -path "*/$pattern/*")
    done
    command+=(')' -prune -o '(' -type d -o -type f -o -type l ')' -print0)
  fi
  "${command[@]}"
}

_global_live_list() {
  local rc=0
  _global_live_candidates "$1" | _global_format "$1" || rc=$?
  # A consumer reaching its result cap can close GNU find's output pipe.
  if ((rc != 0 && rc != 141)); then
    printf 'fzd: filesystem search failed (status %s)\n' "$rc" >&2
    return "$rc"
  fi
  return 0
}

_global_index() {
  _global_prepare || return
  _global_live_list ""
}

_global_list() {
  local query=$* locate_bin source_file pattern rc=0
  _global_prepare || return
  ((${#query} >= FZD_GLOBAL_MINLEN)) || return 0
  locate_bin=$(command -v plocate 2>/dev/null || command -v locate 2>/dev/null || true)
  if [[ "$FZD_GLOBAL_BACKEND" != live && "$FZD_GLOBAL_BACKEND" != cache && -n "$locate_bin" ]]; then
    local arguments=() statuses=()
    [[ -n "$FZD_LOCATE_DBS" ]] && arguments+=(-d "$FZD_LOCATE_DBS")
    [[ "$FZD_GLOBAL_FULLPATH" == 0 ]] && arguments+=(-b)
    # Locate glob syntax is escaped so every backend searches a literal substring.
    pattern=${query//\\/\\\\}; pattern=${pattern//\*/\\*}; pattern=${pattern//\?/\\?}
    pattern=${pattern//\[/\\[}; pattern=${pattern//\]/\\]}
    source_file=$(mktemp) || return 1
    if env -u LOCATE_PATH "$locate_bin" "${arguments[@]}" -0 -i -e -- "*$pattern*" | _global_format "$query" > "$source_file"; then
      rc=0
    else
      statuses=("${PIPESTATUS[@]}")
      if ((statuses[1] == 0 && (statuses[0] == 1 || statuses[0] == 141))); then
        rc=0
      else
        rc=1
      fi
    fi
    if ((rc == 0)); then
      cat -- "$source_file"
      rm -f -- "$source_file"
      return 0
    fi
    rm -f -- "$source_file"
    printf 'fzd: locate unavailable; falling back to filesystem search\n' >&2
  fi
  _global_live_list "$query"
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

case "${1:-}" in
  --_global_index) _global_index; exit $? ;;
  --_global_list)
    shift
    if [[ "${1:-}" == --q ]]; then shift; fi
    _global_list "$@"; exit $?
    ;;
esac

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
