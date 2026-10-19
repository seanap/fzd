#!/usr/bin/env bash
# Source installs are per-user. Package builds use --stage, never user lifecycle.
set -euo pipefail
((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))) || {
  printf 'FZD requires Bash 4.4 or later\n' >&2
  exit 1
}
umask 022
die() {
  printf 'fzd install: %s\n' "$*" >&2
  exit 1
}
log() { printf 'fzd install: %s\n' "$*"; }
warn() { printf 'fzd install: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage: bash install.sh [options]
  bash install.sh             Simple: recommended tools and native Tab completion
  bash install.sh --enhanced  Enhanced: rich preview tools, suggestions and font setup

Advanced options (automation and compatibility):
  --enhanced               Add inline suggestions and optional Nerd Font setup
                           Default: Simple (recommended tools, native Tab)
  --omarchy-launcher float|tile  Optional Enhanced Omarchy terminal launcher
  --allow-package-indexing  Accepted compatibility option; no longer required
  --prefix DIR             User installation prefix (default: ~/.local)
  --deps none|required|recommended
                           Default recommended; includes eza, fd, bat, tree, file
  --noninteractive         Never request sudo input; missing prerequisites fail
  --inline-suggestions     Install/configure ble.sh (Bash) and/or
                           zsh-autosuggestions for the selected --shell target
                           Implies --deps recommended unless --deps is explicit
  --no-inline-suggestions  Disable FZD-managed inline setup; retain shared engines
  --shell both|bash|zsh|none  Default both; respects exported ZDOTDIR
  --bashrc FILE --zshrc FILE  Explicit shell startup paths (also FZD_BASH_RC/FZD_ZSH_RC)
  --no-config              Do not initialize user configuration
  --adopt                  Explicitly replace unmanaged/modified application
                           files, retaining originals in transaction backups
  --fzf-version VERSION --fzf-sha256 HASH
                           Opt-in verified official Linux amd64/arm64 download
  --verify                 Check this installation without changing files
  --uninstall              Remove unchanged owned files and shell blocks only
  --recover                Roll back an interrupted transaction (no live owner)
  --stage DIR              Package staging root: --prefix is required; no deps,
                           home edits, lifecycle metadata or bundled fzf
  --no-updatedb            Skip initialization of a missing default locate index
  -h, --help

Update: git pull --ff-only, then repeat installation from the checkout.
After installation: lf explores; lf name remembers; lff name finds.
Use fzd_cd/fzd_find when lf/lff already exist. Open a new shell first.
The installer never changes third-party themes, EDITOR, or LS_COLORS.
Missing system packages require root or cached sudo authorization (sudo -v).
USAGE
}

script_parent=${BASH_SOURCE[0]%/*}
[[ $script_parent != "${BASH_SOURCE[0]}" ]] || script_parent=.
SCRIPT_DIR=$(cd -- "$script_parent" && printf '%s.' "$PWD")
SCRIPT_DIR=${SCRIPT_DIR%.}
PREFIX=${HOME:?HOME must be set}/.local
[[ $SCRIPT_DIR != */share/fzd ]] || PREFIX=${SCRIPT_DIR%/share/fzd}
PREFIX_SET=0 DEPS=recommended DEPS_SET=0 NONINTERACTIVE=1 SHELL_TARGET=both NO_CONFIG=0 ADOPT=0
INLINE_SUGGESTIONS=keep BLESH_PATH='' AUTOSUGGEST_PATH='' ENHANCED=0 OMARCHY_LAUNCHER=none NO_UPDATEDB=0
APT_REFRESHED=0 GLOW_BOOTSTRAP=0
BASH_RC=${FZD_BASH_RC:-$HOME/.bashrc}
ZSH_RC=${FZD_ZSH_RC:-${ZDOTDIR:-$HOME}/.zshrc}
MODE=install STAGE='' FZF_VERSION='' FZF_SHA256='' JOURNAL_COUNT=0
while (($#)); do
  case "$1" in
  --prefix | --deps | --shell | --stage | --fzf-version | --fzf-sha256 | --bashrc | --zshrc | --omarchy-launcher)
    if (($# < 2)) || [[ -z $2 ]]; then die "$1 requires a value"; fi
    case "$1" in
    --omarchy-launcher) OMARCHY_LAUNCHER=$2 ;;
    --prefix)
      PREFIX=$2
      PREFIX_SET=1
      ;;
    --deps)
      DEPS=$2
      DEPS_SET=1
      ;;
    --shell) SHELL_TARGET=$2 ;;
    --bashrc) BASH_RC=$2 ;;
    --zshrc) ZSH_RC=$2 ;;
    --stage) STAGE=$2 ;;
    --fzf-version) FZF_VERSION=$2 ;;
    --fzf-sha256) FZF_SHA256=$2 ;;
    esac
    shift 2
    ;;
  --noninteractive)
    NONINTERACTIVE=1
    shift
    ;;
  --allow-package-indexing) shift ;;
  --enhanced)
    ENHANCED=1
    [[ $INLINE_SUGGESTIONS != keep ]] || INLINE_SUGGESTIONS=1
    shift
    ;;
  --inline-suggestions)
    INLINE_SUGGESTIONS=1
    shift
    ;;
  --no-inline-suggestions)
    INLINE_SUGGESTIONS=0
    shift
    ;;
  --no-config)
    NO_CONFIG=1
    shift
    ;;
  --adopt)
    ADOPT=1
    shift
    ;;
  --verify | --uninstall | --recover)
    [[ $MODE == install ]] || die 'Choose only one lifecycle operation'
    MODE=${1#--}
    shift
    ;;
  --no-updatedb)
    NO_UPDATEDB=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "Unknown argument: $1 (try --help)" ;;
  esac
done
[[ $OMARCHY_LAUNCHER == none || $OMARCHY_LAUNCHER == float || $OMARCHY_LAUNCHER == tile ]] || die 'Invalid --omarchy-launcher value'
[[ $OMARCHY_LAUNCHER == none || $ENHANCED == 1 ]] || die '--omarchy-launcher requires --enhanced'
[[ $DEPS == none || $DEPS == required || $DEPS == recommended ]] || die 'Invalid --deps value'
[[ $SHELL_TARGET == both || $SHELL_TARGET == bash || $SHELL_TARGET == zsh || $SHELL_TARGET == none ]] || die 'Invalid --shell value'
if [[ $INLINE_SUGGESTIONS == 1 ]]; then
  [[ $SHELL_TARGET != none ]] || die '--inline-suggestions needs --shell bash, zsh or both'
  ((DEPS_SET)) || DEPS=recommended
fi
# XDG relative values are ignored as specified by the Base Directory spec.
# Reject traversal rather than allowing installation writes through ambiguous paths.
for variable in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME; do
  value=${!variable:-}
  if [[ -n $value && $value != /* ]]; then
    warn "Ignoring relative $variable; using its default"
    unset "$variable"
  elif [[ /$value/ == */../* ]]; then
    die "$variable must not contain .. components"
  fi
done
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
for path in "$HOME" "$PREFIX" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "${ZDOTDIR:-$HOME}" "$BASH_RC" "$ZSH_RC" "${FZD_CONF_FILE:-/unused}"; do
  [[ $path == /* && /$path/ != */../* ]] || die 'Installation, XDG, ZDOTDIR and configuration paths must be absolute without .. components'
done
PREFIX=${PREFIX%/}
[[ -n $PREFIX ]] || die 'The filesystem root cannot be an installation prefix'
[[ $PREFIX != *:* ]] || die 'The installation prefix cannot contain : because PATH uses it as a separator'
CFG=${FZD_CONF_FILE:-$XDG_CONFIG_HOME/fzd/fzd.conf}
DATA=$PREFIX/share/fzd
MANIFEST=$DATA/install.manifest
# Use a previously verified local fzf bootstrap during updates and verification.
export PATH="$PREFIX/bin:$PATH"
# shellcheck source=installer/dependencies.bash
source "$SCRIPT_DIR/installer/dependencies.bash"
# shellcheck source=installer/lifecycle.bash
source "$SCRIPT_DIR/installer/lifecycle.bash"
# shellcheck source=installer/inline.bash
source "$SCRIPT_DIR/installer/inline.bash"
# shellcheck source=installer/fonts.bash
source "$SCRIPT_DIR/installer/fonts.bash"
# shellcheck source=installer/desktop.bash
source "$SCRIPT_DIR/installer/desktop.bash"

if [[ -n $STAGE ]]; then
  ((DEPS_SET)) || DEPS=none
  [[ $STAGE == /* && $STAGE != / && $STAGE != *'/../'* && $STAGE != */.. ]] || die '--stage requires an absolute disposable staging directory'
  if ! STAGE=$(readlink -m -- "$STAGE" && printf '.'); then die 'Could not resolve staging root; GNU readlink -m is required'; fi
  STAGE=${STAGE%.}
  STAGE=${STAGE%$'\n'}
  [[ -n $STAGE && $STAGE != / ]] || die 'Resolved staging root cannot be empty or /'
  [[ $PREFIX_SET == 1 && $MODE == install && $DEPS == none && -z $FZF_VERSION && -z $FZF_SHA256 && $INLINE_SUGGESTIONS == keep && $ENHANCED == 0 ]] || die 'Package staging requires --prefix and forbids dependency downloads, inline setup and lifecycle operations'
  [[ -f $SCRIPT_DIR/fzd.sh ]] || die 'Package staging requires the source checkout'
  install -Dm755 "$SCRIPT_DIR/fzd.sh" "$STAGE$PREFIX/bin/fzd"
  install -Dm644 "$SCRIPT_DIR/shell/integration.sh" "$STAGE$PREFIX/share/fzd/integration.sh"
  install -Dm644 "$SCRIPT_DIR/shell/integration.zsh" "$STAGE$PREFIX/share/fzd/integration.zsh"
  install -Dm644 "$SCRIPT_DIR/shell/inline.sh" "$STAGE$PREFIX/share/fzd/inline.sh"
  for module in "$SCRIPT_DIR/lib/"*.bash "$SCRIPT_DIR/lib/"*.py; do
    install -Dm644 "$module" "$STAGE$PREFIX/share/fzd/lib/${module##*/}"
  done
  install -Dm644 "$SCRIPT_DIR/fzd.conf.example" "$STAGE$PREFIX/share/fzd/fzd.conf.example"
  install -Dm644 "$SCRIPT_DIR/LICENSE.txt" "$STAGE$PREFIX/share/licenses/fzd/LICENSE.txt"
  log "Staged package payload under $STAGE$PREFIX (no user files or dependencies changed)"
  exit 0
fi

command -v readlink >/dev/null 2>&1 || die 'GNU readlink is required to resolve the installation prefix; install coreutils first'
if ! PREFIX=$(readlink -m -- "$PREFIX" && printf '.'); then
  die 'Could not resolve installation prefix; GNU readlink -m is required'
fi
PREFIX=${PREFIX%.}
PREFIX=${PREFIX%$'\n'}
[[ -n $PREFIX && $PREFIX != / && $PREFIX != *:* ]] || die 'Resolved installation prefix cannot be empty, /, or contain the PATH separator :'
DATA=$PREFIX/share/fzd
MANIFEST=$DATA/install.manifest
export PATH="$PREFIX/bin:$PATH"

case "$MODE" in
recover)
  recover_transaction
  exit
  ;;
uninstall)
  uninstall_files
  exit
  ;;
verify)
  DEPS=none
  FZF_VERSION=''
  ensure_dependencies
  verify_installation
  exit
  ;;
esac
[[ -f $SCRIPT_DIR/fzd.sh && -f $SCRIPT_DIR/shell/integration.sh ]] || die 'Install/update from the source checkout, not the installed lifecycle script'
[[ -z $FZF_SHA256 || -n $FZF_VERSION ]] || die '--fzf-sha256 requires --fzf-version'
if [[ -n $FZF_VERSION ]]; then
  [[ $FZF_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $FZF_SHA256 =~ ^[a-fA-F0-9]{64}$ ]] || die 'Provide an explicit fzf version and SHA256 before downloading'
fi
bash -n "$SCRIPT_DIR/fzd.sh"
if [[ -e $CFG ]]; then
  [[ -f $CFG ]] || die "Configuration is not a regular file: $CFG"
  bash -n "$CFG" || die "Existing configuration has invalid Bash syntax (unchanged): $CFG"
fi
ensure_dependencies
load_manifest
begin_transaction
install_glow
[[ -z $FZF_VERSION ]] || download_fzf
[[ $INLINE_SUGGESTIONS != 1 ]] || _inline_install_blesh
install_owned "$SCRIPT_DIR/fzd.sh" "$PREFIX/bin/fzd" 755
install_owned "$SCRIPT_DIR/shell/integration.sh" "$DATA/integration.sh" 644
install_owned "$SCRIPT_DIR/shell/integration.zsh" "$DATA/integration.zsh" 644
install_owned "$SCRIPT_DIR/shell/inline.sh" "$DATA/inline.sh" 644
for module in "$SCRIPT_DIR/lib/"*.bash "$SCRIPT_DIR/lib/"*.py; do
  [[ $module != *.bash ]] || bash -n "$module"
  install_owned "$module" "$DATA/lib/${module##*/}" 644
done
install_owned "$SCRIPT_DIR/fzd.conf.example" "$DATA/fzd.conf.example" 644
install_owned "$SCRIPT_DIR/LICENSE.txt" "$DATA/LICENSE.txt" 644
install_owned "$SCRIPT_DIR/install.sh" "$DATA/install.sh" 755
install_owned "$SCRIPT_DIR/installer/dependencies.bash" "$DATA/installer/dependencies.bash" 644
install_owned "$SCRIPT_DIR/installer/lifecycle.bash" "$DATA/installer/lifecycle.bash" 644
install_owned "$SCRIPT_DIR/installer/inline.bash" "$DATA/installer/inline.bash" 644
install_owned "$SCRIPT_DIR/installer/fonts.bash" "$DATA/installer/fonts.bash" 644
install_owned "$SCRIPT_DIR/installer/desktop.bash" "$DATA/installer/desktop.bash" 644
install_owned "$SCRIPT_DIR/shell/launcher.bash" "$DATA/launcher.bash" 644
{
  printf 'FZD_LAUNCH_RC=%q\n' "$BASH_RC"
  printf 'FZD_LAUNCH_BIN=%q\n' "$PREFIX/bin/fzd"
  printf 'FZD_LAUNCH_CONFIG=%q\n' "$CFG"
} >"$TX/launcher.conf"
install_owned "$TX/launcher.conf" "$DATA/launcher.conf" 644
if [[ -n $FZF_VERSION ]]; then
  install_owned "$TX/fzf" "$PREFIX/bin/fzf" 755
else
  for index in "${!FILE_PATHS[@]}"; do
    [[ ${FILE_PATHS[index]} != "$PREFIX/bin/fzf" ]] || record file "${FILE_PATHS[index]}" "${FILE_HASHES[index]}"
  done
fi
for index in "${!FILE_PATHS[@]}"; do
  [[ ${FILE_PATHS[index]} != "$PREFIX/bin/glow" ]] || record file "${FILE_PATHS[index]}" "${FILE_HASHES[index]}"
done

if ((NO_CONFIG == 0)) && [[ ! -e $CFG && ! -L $CFG ]]; then
  source_config=$SCRIPT_DIR/fzd.conf.example
  if [[ -f $HOME/.fzd/fzd.conf ]]; then
    source_config=$HOME/.fzd/fzd.conf
    bash -n "$source_config" || die 'Legacy FZD configuration contains invalid Bash syntax'
    log 'Copying legacy ~/.fzd/fzd.conf; the original is preserved'
  fi
  (
    umask 077
    mkdir -p -- "${CFG%/*}"
  )
  write_file "$source_config" "$CFG" 644
fi
for index in "${!RC_PATHS[@]}"; do record rc "${RC_PATHS[index]}" "${RC_NEWLINES[index]}"; done
case "$SHELL_TARGET" in both | bash) edit_rc "$BASH_RC" add bash ;; esac
case "$SHELL_TARGET" in both | zsh) edit_rc "$ZSH_RC" add zsh ;; esac
for index in "${!SHELL_PATHS[@]}"; do record shell "${SHELL_PATHS[index]}" "${SHELL_HASHES[index]}"; done
_desktop_prepare
write_file "$TX/manifest" "$MANIFEST" 600
: >"$TX/committed"
COMMITTED=1
log "Installed $PREFIX/bin/fzd. Configuration preserved at $CFG."
log "Open a new shell: lf / lf name / lff name (or fzd_cd/fzd_find). Verify/uninstall: bash $(printf %q "$DATA/install.sh") --verify / --uninstall"
log "Original files and transaction journal: $DATA/backups"
if ((ENHANCED)); then
  (_font_setup) || warn 'Optional font setup did not complete; FZD is installed. See docs/TECHNICAL.md.'
fi
