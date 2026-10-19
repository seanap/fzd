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

_fzd_paths() {
  local variable value fallback
  for variable in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME; do
    case $variable in
      XDG_CONFIG_HOME) fallback=$HOME/.config ;;
      XDG_DATA_HOME) fallback=$HOME/.local/share ;;
      XDG_STATE_HOME) fallback=$HOME/.local/state ;;
      XDG_CACHE_HOME) fallback=$HOME/.cache ;;
    esac
    value=${!variable:-}
    # Ignore relative XDG values; reject traversal before accessing any files.
    [[ $value == /* ]] || value=$fallback
    [[ /$value/ != */../* ]] || { printf 'fzd: %s contains unsafe .. components\n' "$variable" >&2; return 1; }
    printf -v "$variable" '%s' "$value"
  done
  : "${FZD_STATE_DIR:=$XDG_STATE_HOME/fzd}"
  : "${FZD_CACHE_DIR:=$XDG_CACHE_HOME/fzd}"
  : "${FZD_CONF_FILE:=$XDG_CONFIG_HOME/fzd/fzd.conf}"
  [[ $FZD_CONF_FILE == /* && /$FZD_CONF_FILE/ != */../* ]] || {
    printf 'fzd: FZD_CONF_FILE must be absolute without .. components\n' >&2; return 1;
  }
}

_fzd_temp_no_symlinks() {
  local path=${1#/} component current=''
  while [[ -n $path ]]; do
    component=${path%%/*}
    current+=/$component
    [[ ! -L $current ]] || return 1
    [[ $path == */* ]] || break
    path=${path#*/}
  done
}
_fzd_temp_base_safe() {
  local path=$1 mode
  REPLY=''
  [[ ! -e $path ]] && return 0
  [[ -d $path && -O $path && -w $path && -x $path ]] || return 1
  mode=$(stat -c %a -- "$path") || return 1
  REPLY=$mode
  (( (8#$mode & 0022) == 0 ))
}

_fzd_temp_init() {
  local runtime=${XDG_RUNTIME_DIR:-} mode=''
  if [[ -z ${FZD_TMP_DIR:-} ]]; then
    if [[ $runtime == /* && /$runtime/ != */../* && -d $runtime && ! -L $runtime && -O $runtime && -w $runtime && -x $runtime ]] &&
      [[ $(stat -c %a -- "$runtime" 2>/dev/null) == 700 ]] &&
      _fzd_temp_no_symlinks "$runtime/fzd" && _fzd_temp_base_safe "$runtime/fzd"; then
      FZD_TMP_DIR=$runtime/fzd
      mode=$REPLY
    else
      FZD_TMP_DIR=$FZD_CACHE_DIR/tmp
      # No per-preview stderr noise; interactive entry points give the guidance.
      case ${1:-} in --_*) ;; *) printf 'fzd: XDG_RUNTIME_DIR unavailable or unsafe; using private cache temporary storage\n' >&2 ;; esac
    fi
  fi
  [[ $FZD_TMP_DIR == /* && /$FZD_TMP_DIR/ != */../* ]] || {
    printf 'fzd: FZD_TMP_DIR must be absolute without .. components\n' >&2; return 1;
  }
  # Never traverse symlinks in temporary storage, including dangling links.
  _fzd_temp_no_symlinks "$FZD_TMP_DIR" || { printf 'fzd: unsafe temporary directory symlink: %s\n' "$FZD_TMP_DIR" >&2; return 1; }
  (umask 077; mkdir -p -- "$FZD_STATE_DIR" "$FZD_CACHE_DIR" "$FZD_TMP_DIR") || {
    printf 'fzd: cannot create state, cache or temporary directories\n' >&2; return 1;
  }
  [[ -d $FZD_TMP_DIR && -O $FZD_TMP_DIR && -w $FZD_TMP_DIR && -x $FZD_TMP_DIR ]] || return 1
  if [[ -z $mode ]]; then mode=$(stat -c %a -- "$FZD_TMP_DIR") || return 1; fi
  (( (8#$mode & 0022) == 0 )) || { printf 'fzd: temporary directory is writable by other users\n' >&2; return 1; }
  FZD_SESSION_TMP=$(mktemp -d "$FZD_TMP_DIR/session.XXXXXXXX") || { printf 'fzd: cannot create private temporary directory\n' >&2; return 1; }
  export TMPDIR="$FZD_SESSION_TMP"
}

_fzd_init() {
  local path
  for path in "$FZD_STATE_DIR" "$FZD_CACHE_DIR"; do
    [[ $path == /* && /$path/ != */../* ]] || { printf 'fzd: state/cache overrides must be absolute without .. components\n' >&2; return 1; }
  done
  # Captured previews never allocate control files or persistent state. Avoid
  # directory creation and security probes on this frequent rendering path.
  if [[ ${1:-} != --_preview ]]; then _fzd_temp_init "${1:-}"; fi

  # ----------------- CONFIG DEFAULTS -----------------
  : "${FZD_GLOBAL_BACKEND:=cache}" # cache (in-memory fuzzy)|auto|locate|live
  : "${FZD_GLOBAL_MINLEN:=2}"
  : "${FZD_GLOBAL_MAXDEPTH:=6}"
  : "${FZD_GLOBAL_MAXRESULTS:=5000}"
  : "${FZD_GLOBAL_PATHS:=/etc /opt /srv /home/$USER}"
  : "${FZD_GLOBAL_FULLPATH:=0}"
  : "${FZD_LOCATE_DBS:=}"
  : "${FZD_GLOBAL_XEXCLUDES:=mnt,proc,sys,dev,run,proc/*,sys/*,dev/*,run/*,snap,lost+found,var/lib/docker}"
  : "${FZD_DEBUG:=0}"
  : "${FZD_GLOBAL_ROOT:=/}" # filesystem root label for overlay prompt
  : "${FZD_EXCLUDES:=.git,node_modules,.cache,.venv,.tox,dist,build,__pycache__,.DS_Store}"
  : "${FZD_ICONS:=1}" # 1 forces eza icons in captured previews; 0 disables them
  [[ $FZD_ICONS == 0 || $FZD_ICONS == 1 ]] || { printf 'fzd: FZD_ICONS must be 0 or 1\n' >&2; return 1; }
  : "${FZD_PREVIEW_DEPTH:=2}"
  : "${FZD_PREVIEW_MAX_LINES:=200}"
  : "${FZD_PREVIEW_TIMEOUT:=2}"

  FZD_THEME_OPTS=()
  # A parent session exports its resolved entry colors. Data/preview helpers
  # need no palette construction or module discovery on each keystroke.
  if [[ ${FZD_THEME_READY:-0} != 1 || ( ${1:-} != --_preview && ${1:-} != --_global_list && ${1:-} != --_global_index ) ]]; then
    if [[ -n ${FZD_OMARCHY_THEME_FILE:-}${FZD_THEME_SNAPSHOT:-}${FZD_COLOR_BORDER:-}${FZD_COLOR_HIGHLIGHT:-}${FZD_COLOR_FG:-}${FZD_COLOR_BG:-} ]] ||
      [[ -f $XDG_STATE_HOME/omarchy/current/theme/colors.toml || -f $HOME/.local/state/omarchy/current/theme/colors.toml || -f $XDG_CONFIG_HOME/omarchy/current/theme/colors.toml ]]; then
      if _explorer_load theme; then _fzd_theme_init "${1:-}"; fi
    fi
  fi
  c_dir=""; c_file=""
  if [[ -n "${FZD_COLOR_DIR:-}" ]]; then c_dir="$(hex_to_ansi "$FZD_COLOR_DIR")"; fi
  if [[ -n "${FZD_COLOR_FILE:-}" ]]; then c_file="$(hex_to_ansi "$FZD_COLOR_FILE")"; fi
  export FZD_CONF_FILE
}

# ----------------- THEME (inherit system unless user opts-in) -----------------
# If the user sets FZD_COLOR_DIR/FILE to hex (#RRGGBB), use that; else leave empty to inherit fzf theme.
c_reset=$'\033[0m'
hex_to_ansi() {
  local h="${1#\#}"
  [[ $h =~ ^[0-9A-Fa-f]{6}$ ]] || return 0
  printf '\033[38;2;%d;%d;%dm' $((16#${h:0:2})) $((16#${h:2:2})) $((16#${h:4:2}))
}
# ----------------- DEBUG -----------------
dbg() { if (( ${FZD_DEBUG:-0} == 1 )); then printf 'fzd: %s\n' "$*" > /dev/tty || true; fi; }
ppath() { printf '%s' "${1/#$HOME/~}"; }

# ----------------- COMMON HELPERS -----------------
DELIM=$'\t'
FZD_ZOXIDE_PENDING=()
declare -A LAST_CHILD=()   # parent_abs -> child_basename
START_POS=""
CUR=""

normalize_path() {
  local p="${1//\/\//\/}"
  [[ "$p" != "/" ]] && p="${p%/}"
  printf '%s' "$p"
}
get_cwd() { ( CDPATH='' cd -L -- "${1:-$PWD}" 2>/dev/null && printf '%s' "$PWD" ) || printf '%s' "$PWD"; }
join_path() { local base="$1" child="${2#/}"; [[ "$base" == "/" ]] && printf '/%s' "$child" || printf '%s/%s' "$base" "$child"; }
b64()   { printf '%s' "$1" | base64 -w 0; }
deb64() { base64 -d 2>/dev/null <<< "$1" || true; }

# Encode a batch with one encoder, retaining exactly the existing base64 IDs.
# NUL padding aligns each input to three bytes; it travels only through the pipe.
# Read fixed-size encoded records incrementally to avoid quadratic string slicing.
_b64_paths() {
  local LC_ALL=C path width encoded fd producer rc=0
  B64_PATHS=()
  (($#)) || return 0
  exec {fd}< <(
    set -o pipefail
    for path; do
      case $((${#path} % 3)) in
        0) printf '%s' "$path" ;;
        1) printf '%s\0\0' "$path" ;;
        2) printf '%s\0' "$path" ;;
      esac
    done | base64 -w 0
  )
  producer=$!
  for path; do
    # shellcheck disable=SC2017 # Round up to whole base64 quanta before multiplying.
    width=$(( (${#path} + 2) / 3 * 4 ))
    encoded=''
    if ((width)) && ! IFS= read -r -u "$fd" -N "$width" encoded; then
      rc=1
      break
    fi
    case $((${#path} % 3)) in
      1) encoded=${encoded:0:width-2}'==' ;;
      2) encoded=${encoded:0:width-1}'=' ;;
    esac
    B64_PATHS+=("$encoded")
  done
  exec {fd}<&-
  wait "$producer" || rc=1
  if ((rc)); then
    B64_PATHS=()
    printf 'fzd: pathname encoding failed\n' >&2
    return 1
  fi
}

# Return paths through REPLY: command substitution strips trailing newlines.
_parent_path() {
  local path=${1%/}
  REPLY=${path%/*}
  [[ -n "$REPLY" ]] || REPLY=/
}
_decode_path() {
  REPLY="$(deb64 "$1"; printf '.')"
  REPLY=${REPLY%.}
  [[ "$REPLY" == / ]] || REPLY=${REPLY%/}
}
_display_name() {
  local LC_ALL=C
  REPLY=$1
  # Ordinary names need no rewriting. Match bytes, retaining UTF-8 unchanged.
  [[ "$REPLY" == *[$'\001'-$'\037'$'\177\\']* ]] || return 0
  REPLY=${REPLY//\\/\\\\}
  REPLY=${REPLY//$'\n'/\\n}; REPLY=${REPLY//$'\r'/\\r}; REPLY=${REPLY//$'\t'/\\t}
  REPLY=${REPLY//$'\033'/\\e}
  if [[ "$REPLY" == *[$'\001'-$'\037'$'\177']* ]]; then
    local code byte escaped
    for ((code=1; code<32; code++)); do
      printf -v escaped '\\x%02x' "$code"
      printf -v byte '%b' "$escaped"
      REPLY=${REPLY//"$byte"/"$escaped"}
    done
    REPLY=${REPLY//$'\177'/\\x7f}
  fi
}
_make_temp() {
  REPLY=$(mktemp) || { printf 'fzd: cannot create temporary file\n' >&2; return 1; }
  FZD_TEMP_FILES+=("$REPLY")
}
_remove_temp() {
  local tracked path remaining=()
  rm -f -- "$@" || return
  for tracked in "${FZD_TEMP_FILES[@]}"; do
    for path in "$@"; do
      [[ "$tracked" == "$path" ]] && continue 2
    done
    remaining+=("$tracked")
  done
  FZD_TEMP_FILES=("${remaining[@]}")
}
_cleanup() {
  _restore_screen
  if [[ -n ${FZD_GLOBAL_PRODUCER:-} ]]; then
    kill "$FZD_GLOBAL_PRODUCER" 2>/dev/null || true
    wait "$FZD_GLOBAL_PRODUCER" 2>/dev/null || true
    FZD_GLOBAL_PRODUCER=''
  fi
  # One upstream database transaction per session, outside the redraw loop.
  local zoxide_offset
  for ((zoxide_offset=0; zoxide_offset<${#FZD_ZOXIDE_PENDING[@]}; zoxide_offset+=128)); do
    command zoxide add -- "${FZD_ZOXIDE_PENDING[@]:zoxide_offset:128}" || true
  done
  if [[ ${FZD_STATE_HELD:-0} == 1 ]]; then _state_unlock; fi
  if declare -F _operations_cleanup >/dev/null; then _operations_cleanup; fi
  if ((${#RECENT_PENDING[@]})); then
    if ! _explorer_load state || ! _recents_flush; then
      printf 'fzd: %s\n' "${FZD_STATUS:-Could not save recent directories}" >&2
    fi
  fi
  if ((${#FZD_TEMP_FILES[@]})); then rm -f -- "${FZD_TEMP_FILES[@]}"; fi
  if [[ -n ${FZD_SESSION_TMP:-} ]]; then rmdir -- "$FZD_SESSION_TMP" 2>/dev/null || true; fi
}
_restore_screen() {
  if [[ ${FZD_SCREEN_ACTIVE:-0} == 1 ]]; then
    printf '%s' "$FZD_SCREEN_RESTORE" >&2 || true
    FZD_SCREEN_ACTIVE=0
  fi
}

remember_child() {
  local parent="$1" child="$2"
  if [[ -n "$parent" && -n "$child" ]]; then
    LAST_CHILD["$parent"]="$child"
    dbg "remember_child: [$parent]='$child'"
  fi
}
go_up() {
  local parent child
  _parent_path "$CUR"; parent=$REPLY
  child=${CUR##*/}
  remember_child "$parent" "$child"
  CUR="$parent"
  dbg "LEFT -> CUR=$CUR (preselect child='$child')"
}
enter_dir_from_raw() {
  local parent; _parent_path "$CUR"; parent=$REPLY
  [[ -z "${RAW:-}" || ! -d "$RAW" || "$RAW" == "$parent" ]] && { dbg "RIGHT ignored (RAW='${RAW:-}')"; return 0; }
  if [[ ! -r "$RAW" || ! -x "$RAW" ]]; then
    printf 'fzd: cannot access directory: %q\n' "$RAW" >&2
    return 0
  fi
  remember_child "$CUR" "${RAW##*/}"
  CUR=$RAW
  [[ "$CUR" == / ]] || CUR=${CUR%/}
  dbg "RIGHT -> into '$CUR'"
}
print_cd_target() { printf '%s\n' "$RAW"; }

# ----------------- LISTING (no duplicates) -----------------
list_entries() {
  DIRS=(); FILES=()

  local had_nullglob=0 had_dotglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -q dotglob && had_dotglob=1
  shopt -s nullglob
  shopt -u dotglob

  local path base
  # Enumerate once, including hidden names without overlapping glob patterns.
  for path in "$CUR"/* "$CUR"/.[!.]* "$CUR"/..?*; do
    base="${path##*/}"
    if [[ -d "$path" ]]; then DIRS+=("$base/")
    elif [[ -f "$path" || -L "$path" ]]; then FILES+=("$base"); fi
  done

  if (( ${#DIRS[@]} > 1 )); then
    mapfile -d '' -t DIRS < <(printf '%s\0' "${DIRS[@]}" | sort -zf)
  fi
  if (( ${#FILES[@]} > 1 )); then
    mapfile -d '' -t FILES < <(printf '%s\0' "${FILES[@]}" | sort -zf)
  fi

  if ((had_nullglob == 0)); then shopt -u nullglob; fi
  if ((had_dotglob)); then shopt -s dotglob; fi
}

build_lines() {
  LINES=(); START_POS=""
  local parent; _parent_path "$CUR"; parent=$REPLY
  local paths=("$parent") labels=("${c_dir}../${c_reset}")

  local want_child="${FZD_SELECT_NAME:-${LAST_CHILD[$CUR]:-}}"
  local idx=0
  for d in "${DIRS[@]}"; do
    local name="${d%/}"
    local p="${CUR%/}/$name"
    _display_name "$d"
    paths+=("$p"); labels+=("${c_dir}${REPLY}${c_reset}")
    if [[ -n "$want_child" && "$name" == "$want_child" ]]; then
      START_POS=$(( 2 + idx ))   # 1=../, dirs start at 2; idx is 0-based
    fi
    ((idx+=1))
  done
  for f in "${FILES[@]}"; do
    local p="${CUR%/}/$f"
    _display_name "$f"
    paths+=("$p"); labels+=("${c_file}${REPLY}${c_reset}")
  done
  # File restoration is needed only on history/operation returns. Directory
  # highlights found above and ordinary visits need no additional file scan.
  if [[ -n "$want_child" && -z "$START_POS" ]]; then
    for ((idx=0; idx<${#FILES[@]}; idx++)); do
      if [[ ${FILES[idx]} == "$want_child" ]]; then
        START_POS=$((2 + ${#DIRS[@]} + idx)); break
      fi
    done
  fi
  _b64_paths "${paths[@]}" || return 1
  for ((idx=0; idx<${#paths[@]}; idx++)); do
    LINES+=("${B64_PATHS[idx]}${DELIM}${labels[idx]}")
  done
}

# ---- Build a one-shot index (fd) for cache backend ----
# The implementation is below; all subcommands dispatch after definitions.

# ----------------- PREVIEW (early exit; no debug) -----------------
_have() { command -v "$1" >/dev/null 2>&1; }
_timeout_wrap() { local s="$1"; shift; if (( s > 0 )) && _have timeout; then timeout --kill-after=1 "${s}s" "$@"; else "$@"; fi; }

_lscolors_override() {
  # Output LS_COLORS string to stdout.
  local base="${1-${LS_COLORS:-}}"

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

  if [[ -z "$di" && -z "$fi" ]]; then printf '%s' "$base"; return; fi

  # Replace whole entries, retaining separators and all unrelated bytes.
  # An odd trailing backslash escapes a colon inside a filename pattern.
  local palette_tail="$base" entry suffix out="" separator="" seen_di=0 seen_fi=0
  while :; do
    entry=${palette_tail%%:*}
    while [[ "$palette_tail" == *:* ]]; do
      suffix=${entry##*[^\\]}
      (( ${#suffix} % 2 )) || break
      palette_tail=${palette_tail#*:}
      entry+=":${palette_tail%%:*}"
    done
    case "$entry" in
      di=*) if [[ -n "$di" ]]; then entry=$di; seen_di=1; fi ;;
      fi=*) if [[ -n "$fi" ]]; then entry=$fi; seen_fi=1; fi ;;
    esac
    out+="$separator$entry"
    [[ "$palette_tail" == *:* ]] || break
    palette_tail=${palette_tail#*:}
    separator=:
  done
  [[ -n "$di" && $seen_di == 0 ]] && out+="${out:+:}$di"
  [[ -n "$fi" && $seen_fi == 0 ]] && out+="${out:+:}$fi"
  printf '%s' "$out"
}

_preview_dir() {
  local dir="$1" depth="${2:-2}"

  # Both renderers apply the same explicit dir/file colors as the left pane.
  # Preserve each renderer's inherited palette for all other entries.
  if command -v eza >/dev/null 2>&1; then
    local IFS=','; read -ra _ex <<<"$FZD_EXCLUDES"
    local ig=(); for g in "${_ex[@]}"; do [[ -n "$g" ]] && ig+=( --ignore-glob "$g" ); done

    local icons=always
    [[ ${FZD_ICONS:-1} != 0 ]] || icons=never
    local lsc; lsc="$(_lscolors_override)"
    local eza_palette=${EZA_COLORS-${EXA_COLORS:-}}
    eza_palette=$(_lscolors_override "$eza_palette")
    if [[ -n "$lsc" ]]; then
      EZA_COLORS="$eza_palette" LS_COLORS="$lsc" _timeout_wrap "$FZD_PREVIEW_TIMEOUT" eza --tree -L "$depth" --group-directories-first --color=always --icons="$icons" \
        "${ig[@]}" -- "$dir"
    else
      EZA_COLORS="$eza_palette" _timeout_wrap "$FZD_PREVIEW_TIMEOUT" eza --tree -L "$depth" --group-directories-first --color=always --icons="$icons" \
        "${ig[@]}" -- "$dir"
    fi
    return
  fi

  if command -v tree >/dev/null 2>&1; then
    local IFS=','; read -ra _ex <<<"$FZD_EXCLUDES"
    local patt=""; for g in "${_ex[@]}"; do [[ -n "$patt" ]] && patt+='|'; patt+="$g"; done
    # tree gives TREE_COLORS precedence over LS_COLORS, including an empty value.
    local palette="${TREE_COLORS-${LS_COLORS:-}}" TREE_COLORS
    TREE_COLORS="$(_lscolors_override "$palette")"
    export TREE_COLORS
    if [[ -n "$patt" ]]; then _timeout_wrap "$FZD_PREVIEW_TIMEOUT" tree -a -C -L "$depth" -I "$patt" -- "$dir"
    else _timeout_wrap "$FZD_PREVIEW_TIMEOUT" tree -a -C -L "$depth" -- "$dir"; fi
    return
  fi
  ls -A -- "$dir"
}
_glow_render() {
  local width=$1 file=$2 style=${FZD_GLOW_STYLE:-${GLOW_STYLE:-auto}}
  # Glow replaces even a configured theme with its plain "notty" style when
  # stdout is captured unless --style is explicit. Keep auto light/dark choice,
  # with an explicit user override for a built-in theme or JSON style file.
  # Glow validates its pager even with paging disabled. Captured previews use
  # cat so minimal installations do not need less just to render Markdown.
  # Ignore piped picker/launcher input: the selected file is the preview source.
  PAGER='cat' _timeout_wrap "$FZD_PREVIEW_TIMEOUT" glow --style "$style" --width "$width" --pager=false -- "$file" </dev/null
}

_preview_file() {
  local file="$1" mime=''
  local is_text=0
  if command -v file >/dev/null 2>&1; then
    mime=$(file -b --mime-type -- "$file") || mime=''
    case "$mime" in text/*|*json*|*xml*|*x-sh*|*javascript*) is_text=1 ;; esac
  else
    head -c 4096 -- "$file" | tr -d '\000' | grep -q $'\n' && is_text=1
  fi
  local width=${FZF_PREVIEW_COLUMNS:-80} height=${FZF_PREVIEW_LINES:-24} rendered chafa_help
  local -a chafa_probe=()
  [[ $width =~ ^[1-9][0-9]{0,2}$ ]] && ((width <= 500)) || width=80
  [[ $height =~ ^[1-9][0-9]{0,2}$ ]] && ((height <= 200)) || height=24
  case $mime in
    image/png|image/jpeg|image/gif|image/webp|image/bmp|image/tiff|image/avif|image/x-icon|image/vnd.microsoft.icon)
      if _have chafa; then
        # Older distro releases predate probing and do not accept --probe.
        chafa_help=$(_timeout_wrap 1 chafa --help 2>/dev/null) || chafa_help=''
        [[ $chafa_help != *--probe* ]] || chafa_probe=(--probe=off)
        if rendered=$(_timeout_wrap "$FZD_PREVIEW_TIMEOUT" chafa --format=symbols --polite=on --animate=off "${chafa_probe[@]}" --size="${width}x${height}" -- "$file" 2>/dev/null); then
          printf '%s\n' "$rendered"; return 0
        fi
      fi ;;
  esac
  if (( is_text )); then
    case ${file,,} in *.md|*.markdown|*.mdown|*.mkd)
      if _have glow && [[ $(stat -c %s -- "$file" 2>/dev/null) =~ ^[0-9]+$ ]] &&
        (( $(stat -c %s -- "$file") <= 1048576 )) &&
        rendered=$(_glow_render "$width" "$file" 2>/dev/null); then
        printf '%s\n' "$rendered"; return 0
      fi ;;
    esac
    local batbin=""; command -v bat >/dev/null 2>&1 && batbin="bat"; [[ -z "$batbin" ]] && command -v batcat >/dev/null 2>&1 && batbin="batcat"
    if [[ -n "$batbin" ]]; then
      _timeout_wrap "$FZD_PREVIEW_TIMEOUT" "$batbin" --color=always --pager=never --line-range ":$FZD_PREVIEW_MAX_LINES" -- "$file"
    else
      _timeout_wrap "$FZD_PREVIEW_TIMEOUT" head -n "$FZD_PREVIEW_MAX_LINES" -- "$file"
    fi
  else
    printf '⚙ %s\n' "$(file -b -- "$file" 2>/dev/null || echo binary)"
    ls -lh -- "$file" 2>/dev/null || true
    if command -v hexdump >/dev/null 2>&1; then echo; hexdump -C -- "$file" | head -n 64; fi
  fi
}
_preview() {
  FZD_DEBUG=0
  local sel_path; _decode_path "$1"; sel_path=$REPLY
  [[ -z "$sel_path" ]] && return 0
  if [[ -d "$sel_path" ]]; then _preview_dir "$sel_path" "$FZD_PREVIEW_DEPTH"
  elif [[ -f "$sel_path" ]]; then _preview_file "$sel_path"
  else echo "(missing)"; fi
  return 0
}

_terminal_run() {
  _restore_screen
  "$@" </dev/tty >/dev/tty 2>&1
}

_open_in_editor() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  _explorer_load command || return 0
  if ! _fzd_editor_command; then FZD_STATUS='Configured editor unavailable; install micro or set EDITOR'; return 0; fi
  # Omarchy's wrapper adds its own separator before dispatching to the editor.
  if [[ ${FZD_COMMAND[0]##*/} != omarchy-launch-editor && ${FZD_COMMAND[-1]} != -- ]]; then FZD_COMMAND+=(--); fi
  _terminal_run "${FZD_COMMAND[@]}" "$file" || true
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
  # shellcheck disable=SC2153 # Optional array can be declared by configuration.
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
    # Retain the common legacy ~/ form without eval or pathname expansion.
    if [[ "$declaration" != 'declare -a '* ]]; then
      # shellcheck disable=SC2088 # Match literal tilde syntax before expanding it.
      case "$root" in
        '~') root=$HOME ;;
        '~/'*) root="$HOME/${root:2}" ;;
      esac
    fi
    [[ "$root" == /* ]] || root="$PWD/$root"
    [[ "$root" == / ]] || root=${root%/}
    [[ -d "$root" && -r "$root" && -x "$root" ]] || continue
    # fd canonicalizes roots; use the same scope for fd, find and locate.
    root=$( (CDPATH='' cd -P -- "$root" && printf '%s.' "$PWD") 2>/dev/null) || continue
    valid+=("${root%.}")
  done
  GLOBAL_ROOTS=("${valid[@]}")
  if ((${#GLOBAL_ROOTS[@]} == 0)); then
    printf 'fzd: no accessible global search roots configured\n' >&2
    return 1
  fi
  GLOBAL_SCOPE_PATTERN=''
  for root in "${GLOBAL_ROOTS[@]}"; do
    _global_glob_quote "$root"
    REPLY=${REPLY//|/\\|}; REPLY=${REPLY//\(/\\(}; REPLY=${REPLY//\)/\\)}
    [[ -z $GLOBAL_SCOPE_PATTERN ]] || GLOBAL_SCOPE_PATTERN+='|'
    if [[ $root == / ]]; then GLOBAL_SCOPE_PATTERN+='/*'; else GLOBAL_SCOPE_PATTERN+="$REPLY|$REPLY/*"; fi
  done
  GLOBAL_SCOPE_PATTERN="@($GLOBAL_SCOPE_PATTERN)"
  local first=() second=()
  IFS=',' read -r -a first <<< "$FZD_EXCLUDES"
  IFS=',' read -r -a second <<< "$FZD_GLOBAL_XEXCLUDES"
  GLOBAL_EXCLUDES=("${first[@]}" "${second[@]}")
  # Compile the common exclusion list once. [[ ... == pattern ]] supports
  # extglob without changing the caller's shell options. Keep arbitrary user
  # patterns on the original path rather than changing their grouping syntax.
  GLOBAL_EXCLUDE_PATTERN=''
  for root in "${GLOBAL_EXCLUDES[@]}"; do
    root=${root%/}
    [[ -n $root ]] || continue
    if [[ $root == *['|()']* ]]; then GLOBAL_EXCLUDE_PATTERN='fallback'; break; fi
    [[ -z $GLOBAL_EXCLUDE_PATTERN ]] || GLOBAL_EXCLUDE_PATTERN+='|'
    GLOBAL_EXCLUDE_PATTERN+=$root
  done
  if [[ -n $GLOBAL_EXCLUDE_PATTERN && $GLOBAL_EXCLUDE_PATTERN != fallback ]]; then
    GLOBAL_EXCLUDE_PATTERN="*/@($GLOBAL_EXCLUDE_PATTERN)/*"
  fi
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
  local path=$1 pattern
  # shellcheck disable=SC2053 # Compiled pathname patterns, not literal strings.
  [[ $path == $GLOBAL_SCOPE_PATTERN ]] || return 1
  if [[ ${GLOBAL_EXCLUDE_PATTERN:-fallback} != fallback ]]; then
    # shellcheck disable=SC2053 # Apply the compiled exclusion alternatives.
    [[ -z $GLOBAL_EXCLUDE_PATTERN || "$path/" != $GLOBAL_EXCLUDE_PATTERN ]]
    return
  fi
  for pattern in "${GLOBAL_EXCLUDES[@]}"; do
    pattern=${pattern%/}
    [[ -z "$pattern" ]] && continue
    # Deliberate glob matching against complete path components, never shell code.
    if [[ "$path/" == */$pattern/* ]]; then return 1; fi
  done
  return 0
}

_global_print_batch() {
  local -n batch_paths=$1 batch_labels=$2
  local idx records=()
  _b64_paths "${batch_paths[@]}" || return 1
  for ((idx=0; idx<${#batch_paths[@]}; idx++)); do
    records+=("${B64_PATHS[idx]}${DELIM}${batch_labels[idx]}")
  done
  printf '%s\n' "${records[@]}"
}

_global_format() {
  local query=${1,,} path base candidate color suffix count=0
  local paths=() labels=()
  while IFS= read -r -d '' path; do
    [[ "$path" == / ]] || path=${path%/}
    _global_allowed "$path" || continue
    base=${path##*/}
    [[ -n "$base" ]] || base=/
    candidate=$base
    [[ "$FZD_GLOBAL_FULLPATH" == 1 ]] && candidate=$path
    [[ "${candidate,,}" == *"$query"* ]] || continue
    if [[ -d "$path" ]]; then
      color=$c_dir; suffix=/
    elif [[ -f "$path" || -L "$path" ]]; then
      color=$c_file; suffix=""
    else
      continue
    fi
    # Encode identity independently; control characters must not create records.
    _display_name "$base"; base=$REPLY
    paths+=("$path"); labels+=("$color$base$suffix$c_reset")
    ((count += 1))
    # Show the first hit immediately even if a rare query keeps scanning.
    # Batch subsequent records to bound memory without per-path encoders.
    if ((count == 1 || ${#paths[@]} == 128)); then
      _global_print_batch paths labels || return 1
      paths=(); labels=()
    fi
    if ((count >= FZD_GLOBAL_MAXRESULTS)); then break; fi
  done
  if ((${#paths[@]})); then _global_print_batch paths labels || return 1; fi
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
  # A launcher can pass down ignored SIGPIPE. Restore its normal disposition
  # so reaching the result cap terminates find cleanly rather than producing
  # a write-error diagnostic/status 1. Older env versions keep the old path.
  if env --default-signal=PIPE --version >/dev/null 2>&1; then
    command=(env --default-signal=PIPE "${command[@]}")
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
  local python pattern simple=1 rc=0
  local statuses=(0 0)
  # Python is an optional accelerator for whole snapshots, never a startup
  # requirement. Leave arbitrary Bash glob syntax on the original formatter.
  for pattern in "${GLOBAL_EXCLUDES[@]}"; do
    if [[ $pattern == *['[]\|()']* ]]; then simple=0; break; fi
  done
  python=$(command -v python3 2>/dev/null || true)
  if ((simple)) && [[ -n $python ]] && _explorer_load state && [[ -r $FZD_EXPLORER_LIB/global_format.py ]]; then
    _global_live_candidates "" | "$python" "$FZD_EXPLORER_LIB/global_format.py" \
      "$FZD_GLOBAL_MAXRESULTS" "$c_dir" "$c_file" "$c_reset" \
      "${#GLOBAL_ROOTS[@]}" "${GLOBAL_ROOTS[@]}" "${GLOBAL_EXCLUDES[@]}" || statuses=("${PIPESTATUS[@]}")
    # fd versions differ on a closed output pipe (0, 1 or SIGPIPE). Only
    # tolerate status 1 when the formatter explicitly reached the requested cap.
    if ((statuses[1] == 10)); then
      rc=${statuses[0]}
      ((rc != 1)) || rc=0
    else
      rc=${statuses[1]}
      ((rc != 0)) || rc=${statuses[0]}
    fi
    if ((rc != 0 && rc != 141)); then
      printf 'fzd: filesystem snapshot failed (status %s)\n' "$rc" >&2
      return "$rc"
    fi
    return 0
  fi
  _global_live_list ""
}

_global_glob_quote() {
  REPLY=${1//\\/\\\\}
  REPLY=${REPLY//\*/\\*}; REPLY=${REPLY//\?/\\?}
  REPLY=${REPLY//\[/\\[}; REPLY=${REPLY//\]/\\]}
}

_global_regex_quote() {
  local value=$1 char index
  REPLY=''
  for ((index=0; index<${#value}; index++)); do
    char=${value:index:1}
    case "$char" in '.'|'['|']'|'('|')'|'{'|'}'|'*'|'+'|'?'|'^'|'$'|'|'|\\) REPLY+=\\ ;; esac
    REPLY+=$char
  done
}

_global_locate_regex() {
  local locate_bin=$1 query=$2 root scope='' pattern
  shift 2
  for root in "${GLOBAL_ROOTS[@]}"; do
    _global_regex_quote "$root"
    [[ -z $scope ]] || scope+='|'
    if [[ $root == / ]]; then scope+='/'; else scope+="$REPLY($|/)"; fi
  done
  _global_regex_quote "$query"; pattern=$REPLY
  [[ $FZD_GLOBAL_FULLPATH == 1 ]] || pattern="(^|/)[^/]*${pattern}[^/]*$"
  env -u LOCATE_PATH "$locate_bin" "$@" -0 -i --regex -- "^($scope)" "$pattern"
}

_global_locate_read() {
  # Bounded candidate probes must reap their producer and preserve its status.
  local fd producer rc=0
  exec {fd}< <(env -u LOCATE_PATH "$@") || return 2
  producer=$!
  FZD_GLOBAL_PRODUCER=$producer
  mapfile -d '' -t hits <&"$fd" || rc=2
  exec {fd}<&-
  wait "$producer" || rc=$?
  FZD_GLOBAL_PRODUCER=''
  ((rc <= 1)) || return 2
  return 0
}

_global_locate_candidates() {
  local locate_bin=$1 query=$2 root other pattern candidate covered
  local arguments=() roots=() hits=() candidates=()
  [[ -z $FZD_LOCATE_DBS ]] || arguments+=(-d "$FZD_LOCATE_DBS")
  _global_glob_quote "$query"; pattern=$REPLY
  if [[ ${locate_bin##*/} != plocate ]]; then
    [[ $FZD_GLOBAL_FULLPATH != 0 ]] || arguments+=(-b)
    env -u LOCATE_PATH "$locate_bin" "${arguments[@]}" -0 -i -- "*$pattern*"
    return
  fi
  # Two/three-byte queries are often broad; keep the single scoped scan. Probe
  # longer strings with a ceiling so a common parent name cannot make Bash
  # inspect hundreds of thousands of irrelevant descendant filenames.
  if ((${#query} < 4)); then _global_locate_regex "$locate_bin" "$query" "${arguments[@]}"; return; fi
  # One anchored glob per disjoint root lets plocate use its trigram index.
  # The scope is part of the producer's pattern, before visibility checks; a
  # broad system query followed by shell filtering can stall on Windows mounts.
  for root in "${GLOBAL_ROOTS[@]}"; do
    covered=0
    for other in "${GLOBAL_ROOTS[@]}"; do
      [[ $root == "$other" ]] && continue
      if [[ $other == / || $root == "$other/"* ]]; then covered=1; break; fi
    done
    ((covered)) && continue
    for other in "${roots[@]}"; do [[ $root != "$other" ]] || covered=1; done
    ((covered)) || roots+=("$root")
  done
  for root in "${roots[@]}"; do
    _global_glob_quote "${root%/}/"; candidate="$REPLY*$pattern*"
    _global_locate_read "$locate_bin" "${arguments[@]}" -0 -i -l 129 -- "$candidate" || return 2
    if ((${#candidates[@]} + ${#hits[@]} > 128)); then
      _global_locate_regex "$locate_bin" "$query" "${arguments[@]}"
      return
    fi
    candidates+=("${hits[@]}")
    # A root itself can be indexed too. [/] forces exact glob matching rather
    # than plocate's implicit substring search when no metacharacters occur.
    candidate=${root##*/}
    [[ -n $candidate ]] || candidate=/
    [[ $FZD_GLOBAL_FULLPATH != 1 ]] || candidate=$root
    if [[ ${candidate,,} == *"${query,,}"* ]]; then
      _global_glob_quote "${root#/}"
      _global_locate_read "$locate_bin" "${arguments[@]}" -0 -i -- "[/]$REPLY" || return 2
      candidates+=("${hits[@]}")
    fi
  done
  if ((${#candidates[@]})); then printf '%s\0' "${candidates[@]}"; fi
  return 0
}

_global_list() {
  local query=$* locate_bin='' source_file error_file rc=0
  _global_prepare || return
  ((${#query} >= FZD_GLOBAL_MINLEN)) || return 0
  if [[ "$FZD_GLOBAL_BACKEND" != live && "$FZD_GLOBAL_BACKEND" != cache ]]; then
    locate_bin=$(command -v plocate 2>/dev/null || command -v locate 2>/dev/null || true)
  fi
  if [[ "$FZD_GLOBAL_BACKEND" != live && "$FZD_GLOBAL_BACKEND" != cache && -n "$locate_bin" ]]; then
    _make_temp || return 1; source_file=$REPLY
    _make_temp || return 1; error_file=$REPLY
    # Do not ask locate to stat every match across the system. In particular,
    # Windows/network mounts can stall WSL before we discard out-of-scope paths.
    # Validate the producer first, then stream formatting; _global_format checks
    # existence only after roots/exclusions have been applied.
    if _global_locate_candidates "$locate_bin" "$query" > "$source_file" 2> "$error_file"; then
      rc=0
    else
      rc=$?
      # plocate uses 1 for both no matches and database errors. Diagnostics
      # distinguish an empty search from a failed producer requiring fallback.
      if ((rc == 1)) && [[ ! -s "$error_file" ]]; then
        rc=0
      else
        rc=1
      fi
    fi
    # plocate reports both no matches and a database failure with status 1.
    [[ ! -s $error_file ]] || rc=1
    cat -- "$error_file" >&2
    _remove_temp "$error_file"
    if ((rc == 0)); then
      _global_format "$query" < "$source_file"
      _remove_temp "$source_file"
      return 0
    fi
    _remove_temp "$source_file"
    printf 'fzd: locate unavailable; falling back to filesystem search\n' >&2
  fi
  _global_live_list "$query"
}

_run_global_overlay() {
  local FZD_GLOBAL_RESUME=1 FZD_GLOBAL_QUERY=${1:-}
  while ((FZD_GLOBAL_RESUME)); do
    FZD_GLOBAL_RESUME=0
    _global_overlay_once "$FZD_GLOBAL_QUERY"
  done
}

_global_overlay_once() {
  dbg "GLOBAL overlay start (backend=${FZD_GLOBAL_BACKEND:-cache})"
  local backend="${FZD_GLOBAL_BACKEND:-cache}"
  _global_prepare || return 0
  local have_loc=''
  if [[ "$backend" == auto ]]; then
    have_loc="$(command -v plocate 2>/dev/null || command -v locate 2>/dev/null || true)"
  fi

  # auto-pick: prefer locate, else cache
  [[ "$backend" == "auto" ]] && { if [[ -n "$have_loc" ]]; then backend="locate"; else backend="cache"; fi; }

  local CTRL SRC query_file self_command control_command
  _make_temp || return 0; query_file=$REPLY
  local query=${1:-}
  self_command=$(_shell_quote "$FZD_SELF")
  if [[ "$backend" == "locate" || "$backend" == "live" ]]; then
    _make_temp || return 0; CTRL=$REPLY
    control_command=$(_shell_quote "$CTRL")
    _explorer_bindings "$control_command" global
    FZD_SCREEN_ACTIVE=${#FZD_SCREEN_OPTS[@]}
    "$FZF_BIN" \
      "${FZD_SCREEN_OPTS[@]}" "${FZD_THEME_OPTS[@]}" \
      --ansi --height=100% --layout=reverse --border --no-mouse --no-multi --no-expect \
      --delimiter "$DELIM" --with-nth=2.. \
      --border-label="${FZD_STATUS:-FZD}" \
      --prompt "global:${FZD_GLOBAL_ROOT%/}/ > " \
      --query="$query" \
      --disabled \
      --preview "$self_command --_preview {1}" \
      --preview-window=right,60%:wrap \
      --bind "change:reload:$self_command --_global_list --q {q} || true" \
      --bind "esc:abort" \
      --bind "f1:execute($self_command --_help global)" \
      "${EXPLORER_BINDS[@]}" \
      --bind "enter:execute-silent(echo A:G_ENTER:{1} > $control_command)+abort" \
      --bind "left:execute-silent(echo A:G_LEFT:{1} > $control_command)+abort" \
      --bind "right:execute-silent(echo A:G_RIGHT:{1} > $control_command)+abort" \
      < <("$FZD_SELF" --_global_list --q "$query" || true) >"$query_file" || true

  elif [[ "$backend" == "cache" ]]; then
    _make_temp || return 0; CTRL=$REPLY
    _make_temp || return 0; SRC=$REPLY
    control_command=$(_shell_quote "$CTRL")
    _explorer_bindings "$control_command" global
    if ! "$FZD_SELF" --_global_index > "$SRC"; then
      _remove_temp "$SRC" "$CTRL"
      return 0
    fi
    FZD_SCREEN_ACTIVE=${#FZD_SCREEN_OPTS[@]}
    "$FZF_BIN" \
      "${FZD_SCREEN_OPTS[@]}" "${FZD_THEME_OPTS[@]}" \
      --ansi --height=100% --layout=reverse --border --no-mouse --no-multi --no-expect \
      --delimiter "$DELIM" --with-nth=2.. \
      --border-label="${FZD_STATUS:-FZD}" \
      --prompt "global:${FZD_GLOBAL_ROOT%/}/ > " \
      --query="$query" \
      --preview "$self_command --_preview {1}" \
      --preview-window=right,60%:wrap \
      --bind "esc:abort" \
      --bind "f1:execute($self_command --_help global)" \
      "${EXPLORER_BINDS[@]}" \
      --bind "enter:execute-silent(echo A:G_ENTER:{1} > $control_command)+abort" \
      --bind "left:execute-silent(echo A:G_LEFT:{1} > $control_command)+abort" \
      --bind "right:execute-silent(echo A:G_RIGHT:{1} > $control_command)+abort" \
      < "$SRC" >"$query_file" || true
    _remove_temp "$SRC"

  fi

  # execute-silent is synchronous: its write is complete before fzf returns.
  local tag='' raw_b64='' action='' sel_path
  IFS=: read -r tag action raw_b64 < "$CTRL" || true
  [[ "$tag" == A ]] || action=''
  IFS= read -r FZD_GLOBAL_QUERY <"$query_file" || true
  _remove_temp "$CTRL" "$query_file"

  [[ -z "${action:-}" ]] && { dbg "GLOBAL overlay cancelled"; return; }
  _decode_path "$raw_b64"; sel_path=$REPLY

  case "$action" in
    COPY_PATH|LAZYGIT)
      if _explorer_load integrations; then _integration_action "$action" "$sel_path"; fi
      FZD_GLOBAL_RESUME=1
      ;;
    COPY|CUT)
      if _explorer_load state && _explorer_load operations; then
        _explorer_action "$action" "$sel_path" global || true
      fi
      ;;
    G_RIGHT)
      if [[ -d "$sel_path" ]]; then RAW="$sel_path"; enter_dir_from_raw; fi
      ;;
    G_LEFT)
      # Preserve the existing Left behavior: dismiss the global overlay.
      ;;
    G_ENTER)
      if [[ -d "$sel_path" ]]; then
        _recent_queue "$sel_path"
        RAW="$sel_path"; print_cd_target; exit 0
      elif [[ -f "$sel_path" ]]; then
        _open_in_editor "$sel_path"
        _parent_path "$sel_path"; CUR=$REPLY
        _parent_path "$CUR"
        remember_child "$REPLY" "${CUR##*/}"
      fi
      ;;
  esac
  return 0
}

_shell_quote() {
  local value=${1//\'/\'\\\'\'}
  printf "'%s'" "$value"
}

# ----------------- SESSION HISTORY (no disk I/O during navigation) -----------------
_recent_queue() {
  local path=$1 previous queued=("$1")
  FZD_ZOXIDE_PENDING+=("$path")
  for previous in "${RECENT_PENDING[@]}"; do
    [[ "$previous" == "$path" ]] || queued+=("$previous")
    ((${#queued[@]} < 25)) || break
  done
  RECENT_PENDING=("${queued[@]}")
}
_history_init() {
  H_PATHS=("$CUR"); H_SELECTIONS=(""); H_INDEX=0
  RECENT_PENDING=("$CUR"); FZD_SELECT_NAME=''; FZD_STATUS=''
}
_history_remember() {
  local parent
  _parent_path "$CUR"; parent=$REPLY
  if [[ -n ${RAW:-} && $RAW != "$parent" && ${RAW%/*} == "${CUR%/}" ]]; then
    H_SELECTIONS[H_INDEX]=${RAW##*/}
    FZD_SELECT_NAME=${RAW##*/}
  fi
}
_history_visit() {
  [[ $CUR != "${H_PATHS[H_INDEX]}" ]] || return 0
  FZD_QUERY=''
  H_PATHS=("${H_PATHS[@]:0:H_INDEX+1}" "$CUR")
  H_SELECTIONS=("${H_SELECTIONS[@]:0:H_INDEX+1}" "")
  if ((${#H_PATHS[@]} > 100)); then
    H_PATHS=("${H_PATHS[@]:1}"); H_SELECTIONS=("${H_SELECTIONS[@]:1}")
  fi
  H_INDEX=$((${#H_PATHS[@]} - 1)); FZD_SELECT_NAME=''
  _recent_queue "$CUR"
}
_history_step() {
  local step=$1 next=$((H_INDEX + $1)) path
  while ((next >= 0 && next < ${#H_PATHS[@]})); do
    path=${H_PATHS[next]}
    if [[ -d $path && -r $path && -x $path ]]; then
      H_INDEX=$next; CUR=$path; FZD_SELECT_NAME=${H_SELECTIONS[next]}
      if ((step < 0)); then FZD_STATUS='Back'; else FZD_STATUS='Forward'; fi
      _recent_queue "$CUR"
      return 0
    fi
    next=$((next + step))
  done
  FZD_STATUS='No accessible directory in that direction'
}
_explorer_load() {
  local module=${1:-state} flag script=${FZD_SELF:-${BASH_SOURCE[0]}} directory candidate
  case "$module" in state|operations|ui|command|theme|integrations) ;; *) return 1 ;; esac
  flag=FZD_MODULE_$module
  [[ ${!flag:-0} == 1 ]] && return 0
  # Resolve only on first feature use, including launches through symlinks.
  if [[ -z ${FZD_EXPLORER_LIB:-} ]]; then
    if ! IFS= read -r -d '' script < <(realpath -ze -- "$script"); then
      FZD_STATUS='Cannot locate Explorer helpers'; return 1
    fi
    directory=${script%/*}
    for candidate in "$directory/lib" "$directory/../share/fzd/lib"; do
      [[ ! -r $candidate/state.bash ]] || { FZD_EXPLORER_LIB=$candidate; break; }
    done
  fi
  if [[ -r ${FZD_EXPLORER_LIB:-}/$module.bash ]]; then
    # shellcheck source=/dev/null
    source "$FZD_EXPLORER_LIB/$module.bash"
    printf -v "$flag" 1
    return 0
  fi
  FZD_STATUS='Explorer helpers missing; reinstall FZD'
  return 1
}
_explorer_bindings() {
  local control=$1 scope=${2:-local} pair key action
  EXPLORER_BINDS=()
  local pairs=('ctrl-c:COPY' 'alt-c:COPY' 'ctrl-x:CUT' 'alt-x:CUT' 'alt-y:COPY_PATH' 'alt-g:LAZYGIT')
  if [[ $scope == local ]]; then
    pairs+=('alt-left:BACK' 'alt-right:FORWARD' 'alt-h:RECENTS' 'f1:HELP' 'ctrl-v:PASTE' 'alt-v:PASTE'
      'ctrl-r:RENAME' 'f2:RENAME' 'f7:MKDIR' 'ctrl-n:MKDIR' 'f8:TRASH')
  fi
  for pair in "${pairs[@]}"; do
    key=${pair%%:*}; action=${pair#*:}
    EXPLORER_BINDS+=(--bind "$key:execute-silent(echo A:$action:{1} > $control)+print-query")
  done
}

# ----------------- MAIN LOOP -----------------
main() {
  CUR="$(get_cwd "$PWD"; printf '.')"; CUR=${CUR%.}
  [[ "$CUR" == / ]] || CUR=${CUR%/}
  _history_init
  FZD_ZOXIDE_PENDING+=("$CUR")
  dbg "cwd=$CUR"

  if [[ ${1:-} == --global ]]; then
    _run_global_overlay "${2:-}"
    _history_visit
  fi

  local HIST_FILE="$FZD_STATE_DIR/query-history"

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
    local QUERY_OPT=()
    [[ ! ${FZD_QUERY+x} ]] || QUERY_OPT=(--query="$FZD_QUERY")

    local CTRL self_command control_command prompt
    _make_temp || return 1; CTRL=$REPLY
    self_command=$(_shell_quote "$FZD_SELF")
    control_command=$(_shell_quote "$CTRL")
    _explorer_bindings "$control_command"
    _display_name "${CUR/#$HOME/~}"; prompt=$REPLY
    FZD_SCREEN_ACTIVE=${#FZD_SCREEN_OPTS[@]}
    mapfile -t FZF_OUT < <(
      printf '%s\n' "${LINES[@]}" | "$FZF_BIN" \
        "${FZD_SCREEN_OPTS[@]}" "${FZD_THEME_OPTS[@]}" \
        --ansi --height=100% --layout=reverse --border --no-mouse --no-multi --no-expect \
        --delimiter "$DELIM" --with-nth=2.. \
        --prompt "$prompt/ > " --border-label " F1 help ${FZD_STATUS:+· $FZD_STATUS }" \
        --print-query --history="$HIST_FILE" --history-size=4000 \
        "${QUERY_OPT[@]}" \
        "${START_OPT[@]}" \
        --preview "$self_command --_preview {1}" \
        --preview-window=right,60%:wrap \
        "${EXPLORER_BINDS[@]}" \
        --bind "esc:abort" \
        --bind "ctrl-f:execute-silent(echo A:GLOBAL:{1} > $control_command)+abort" \
        --bind "enter:execute-silent(echo A:ENTER:{1} > $control_command)+abort" \
        --bind "left:execute-silent(echo A:LEFT:{1} > $control_command)+abort" \
        --bind "right:execute-silent(echo A:RIGHT:{1} > $control_command)+abort" \
        || true
    )

    # If Ctrl-F was pressed (with --print-query + --expect order ambiguity)
    if [[ "${FZF_OUT[0]:-}" == "ctrl-f" || "${FZF_OUT[1]:-}" == "ctrl-f" ]]; then
      (( FZD_DEBUG == 1 )) && printf 'fzd: ctrl-f detected via expect\n' > /dev/tty
      _run_global_overlay
      _history_visit
      _remove_temp "$CTRL"
      continue
    fi

    local tag='' raw_b64='' action=''
    IFS=: read -r tag action raw_b64 < "$CTRL" || true
    [[ "$tag" == A ]] || action=''
    _remove_temp "$CTRL"

    [[ -z "${action:-}" ]] && { dbg "fzf aborted (Esc/close)"; exit 130; }
    _decode_path "$raw_b64"; RAW=$REPLY
    _history_remember
    FZD_STATUS=''
    FZD_QUERY=''
    case "$action" in HELP|RECENTS|COPY|CUT|PASTE|RENAME|MKDIR|TRASH|COPY_PATH|LAZYGIT) FZD_QUERY=${FZF_OUT[0]:-} ;; esac

    case "$action" in
      COPY_PATH|LAZYGIT) if _explorer_load integrations; then _integration_action "$action" "$RAW"; fi ;;
      BACK) _history_step -1 ;;
      FORWARD) _history_step 1 ;;
      GLOBAL) _run_global_overlay ;;
      RECENTS) if _explorer_load ui; then _ui_recents || true; fi ;;
      HELP) if _explorer_load ui; then _ui_help; fi ;;
      COPY|CUT|PASTE|RENAME|MKDIR|TRASH)
        if _explorer_load state && _explorer_load operations; then
          if [[ $action == COPY || $action == CUT || $action == PASTE ]] || _explorer_load ui; then
            _explorer_action "$action" "$RAW" local || true
          fi
        fi
        ;;
      LEFT)
        go_up
        ;;
      RIGHT)
        enter_dir_from_raw
        ;;
      ENTER)
        if [[ -n "$RAW" && -d "$RAW" ]]; then
          local parent; _parent_path "$CUR"; parent=$REPLY
          local target="$RAW"
          if [[ "$RAW" == "$parent" ]]; then
            target="$CUR"
            dbg "ENTER on ../ -> cd '$target'"
          else
            dbg "ENTER dir -> $target"
          fi
          RAW="$target"
          _recent_queue "$target"
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
    _history_visit
  done
}

_fzd_entry() {
  set -euo pipefail
  shopt -s lastpipe 2>/dev/null || true
  export LC_ALL=C
  FZD_TEMP_FILES=()
  RECENT_PENDING=()
  FZD_ZOXIDE_PENDING=()
  FZD_SESSION_TMP=''
  FZD_GLOBAL_PRODUCER=''
  FZD_SCREEN_OPTS=(); FZD_SCREEN_ACTIVE=0; FZD_SCREEN_RESTORE=''
  trap _cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  _fzd_init "${1:-}"
  FZD_SELF=${BASH_SOURCE[0]}
  [[ "$FZD_SELF" == /* ]] || FZD_SELF="$PWD/$FZD_SELF"
  case "${1:-}" in
    --_global_index) _global_index; return ;;
    --_global_list)
      shift
      if [[ "${1:-}" == --q ]]; then shift; fi
      _global_list "$@"; return
      ;;
    --_preview) _preview "${2:-}"; return ;;
  esac
  command -v zoxide >/dev/null 2>&1 || { printf 'fzd: zoxide is required; install it with your distribution package manager\n' >&2; return 1; }
  case "${1:-}" in
    --help|-h)
      printf '%s\n' 'Usage: fzd [DIRECTORY] | --global [QUERY]' \
        'Use shell integration: lf explores, lf name remembers, lff name finds.'
      return 0 ;;
    --_help) ;;
    --global) (($# <= 2)) || { printf 'fzd: quote the global query\n' >&2; return 1; } ;;
    '') ;;
    *)
      if (($# == 1)) && [[ -d $1 ]]; then
        cd -- "$1" || return
        shift
      else
        printf 'fzd: expected a directory or --global [QUERY]; use lf for zoxide jumps\n' >&2
        return 1
      fi ;;
  esac
  FZF_BIN="$(type -P fzf 2>/dev/null || command -v fzf || true)"
  [[ -x "$FZF_BIN" ]] || { echo "fzd: ERROR: fzf not found" >&2; return 1; }
  if [[ ${1:-} == --_help ]]; then
    if _explorer_load ui; then _ui_help "${2:-local}"; fi
    return 0
  fi
  unset FZF_CTRL_T_COMMAND FZF_ALT_C_COMMAND FZF_DEFAULT_COMMAND 2>/dev/null || true
  HAS_POS=0
  if printf 'x\n' | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null "$FZF_BIN" --bind='start:pos(1)' --filter=x >/dev/null 2>&1; then HAS_POS=1; fi
  # Keep the previous frame during navigation; restore before editors and exit.
  # A usable terminfo restore capability is required, so tput stays optional.
  if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
    FZD_SCREEN_RESTORE=$(tput rmcup 2>/dev/null) || FZD_SCREEN_RESTORE=''
    [[ -z "$FZD_SCREEN_RESTORE" ]] || FZD_SCREEN_OPTS=(--no-clear)
  fi
  dbg "start:pos supported: $HAS_POS"
  main "$@"
}

# Sourcing exposes functions for unit tests without running initialization or UI.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  export LC_ALL=C
  _fzd_paths
  # Keep configuration at top level: `declare` must not become function-local.
  # Configuration remains trusted Bash code, as in the original application.
  # shellcheck source=/dev/null
  [[ -f "$FZD_CONF_FILE" ]] && source "$FZD_CONF_FILE"
  _fzd_entry "$@"
fi
