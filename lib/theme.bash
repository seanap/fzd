# shellcheck shell=bash
# A single validated palette snapshot travels to preview subprocesses.
_fzd_theme_init() {
  local mode=${FZD_OMARCHY_THEME:-auto} path=${FZD_OMARCHY_THEME_FILE:-} palette='' key value role inherited=${FZF_DEFAULT_OPTS:-} variable
  local -A colors=()
  FZD_THEME_OPTS=()
  if [[ $mode != 0 ]]; then
    if [[ ${1:-} == --_preview && -n ${FZD_THEME_SNAPSHOT:-} ]]; then
      palette=$FZD_THEME_SNAPSHOT
    else
      if [[ -z $path ]]; then
        for path in "$XDG_STATE_HOME/omarchy/current/theme/colors.toml" "$HOME/.local/state/omarchy/current/theme/colors.toml" "$XDG_CONFIG_HOME/omarchy/current/theme/colors.toml"; do
          [[ ! -f $path ]] || break
        done
      fi
      # Presence of both the palette and current utility distinguishes ordinary Arch.
      if [[ $path == /* && /$path/ != */../* && -f $path ]] && _have omarchy-theme-color; then
        palette=$(_timeout_wrap 2 omarchy-theme-color --file "$path" --all 2>/dev/null) || palette=''
      fi
    fi
  fi
  FZD_THEME_SNAPSHOT=''
  while IFS=$'\t' read -r key value; do
    case $key in accent | foreground | background | blue | yellow | muted | selection | selection_foreground | bright_foreground | green) ;; *) continue ;; esac
    [[ $value =~ ^#[a-fA-F0-9]{6}$ ]] || continue
    colors[$key]=$value
    FZD_THEME_SNAPSHOT+="$key"$'\t'"$value"$'\n'
  done <<<"$palette"
  export FZD_THEME_SNAPSHOT
  # Explicit empty overrides intentionally suppress automatic entry colors.
  [[ ${FZD_COLOR_DIR+x} || ! ${colors[blue]+x} ]] || FZD_COLOR_DIR=${colors[blue]}
  [[ ${FZD_COLOR_FILE+x} || ! ${colors[foreground]+x} ]] || FZD_COLOR_FILE=${colors[foreground]}
  # Honor fzf palettes in either inherited options surface. Never evaluate them.
  if [[ -f ${FZF_DEFAULT_OPTS_FILE:-/nonexistent} && -r ${FZF_DEFAULT_OPTS_FILE:-/nonexistent} ]]; then
    inherited+=$(<"$FZF_DEFAULT_OPTS_FILE")
  fi
  if [[ $inherited != *--color* && $inherited != *--no-color* ]]; then
    for role in fg:foreground bg:background hl:accent hl+:accent fg+:bright_foreground bg+:selection border:muted prompt:accent pointer:accent marker:green info:yellow; do
      key=${role#*:}
      [[ ! ${colors[$key]+x} ]] || FZD_THEME_OPTS+=("--color=${role%%:*}:${colors[$key]}")
    done
  fi
  for role in BORDER:border HIGHLIGHT:hl FG:fg BG:bg; do
    variable=FZD_COLOR_${role%%:*}
    value=${!variable:-}
    [[ ! $value =~ ^#[a-fA-F0-9]{6}$ ]] || FZD_THEME_OPTS+=("--color=${role#*:}:$value")
  done
}
