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
  --prefix DIR             User installation prefix (default: ~/.local)
  --deps none|required|recommended
                           Default none; recommended also installs fd and bat
  --noninteractive         Never request sudo input; missing prerequisites fail
  --shell both|bash|zsh|none  Default both; respects exported ZDOTDIR
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
  --no-updatedb            Accepted legacy option; updatedb is never run
  -h, --help

Update: git pull --ff-only, then repeat installation from the checkout.
After installation: open a new shell and run lf (or fzd_cd if lf already exists).
The installer never changes third-party themes, EDITOR, or LS_COLORS.
USAGE
}

script_parent=${BASH_SOURCE[0]%/*}
[[ $script_parent != "${BASH_SOURCE[0]}" ]] || script_parent=.
SCRIPT_DIR=$(cd -- "$script_parent" && printf '%s.' "$PWD")
SCRIPT_DIR=${SCRIPT_DIR%.}
PREFIX=${HOME:?HOME must be set}/.local
[[ $SCRIPT_DIR != */share/fzd ]] || PREFIX=${SCRIPT_DIR%/share/fzd}
PREFIX_SET=0 DEPS=none NONINTERACTIVE=0 SHELL_TARGET=both NO_CONFIG=0 ADOPT=0
MODE=install STAGE='' FZF_VERSION='' FZF_SHA256='' JOURNAL_COUNT=0
while (($#)); do
  case "$1" in
  --prefix | --deps | --shell | --stage | --fzf-version | --fzf-sha256)
    if (($# < 2)) || [[ -z $2 ]]; then die "$1 requires a value"; fi
    case "$1" in
    --prefix)
      PREFIX=$2
      PREFIX_SET=1
      ;;
    --deps) DEPS=$2 ;;
    --shell) SHELL_TARGET=$2 ;;
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
  --no-updatedb) shift ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "Unknown argument: $1 (try --help)" ;;
  esac
done
[[ $DEPS == none || $DEPS == required || $DEPS == recommended ]] || die 'Invalid --deps value'
[[ $SHELL_TARGET == both || $SHELL_TARGET == bash || $SHELL_TARGET == zsh || $SHELL_TARGET == none ]] || die 'Invalid --shell value'
for path in "$PREFIX" "${XDG_CONFIG_HOME:-$HOME/.config}" "${ZDOTDIR:-$HOME}" "${FZD_CONF_FILE:-/unused}"; do
  [[ $path == /* && $path != *'/../'* && $path != */.. ]] || die 'Installation, XDG, ZDOTDIR and configuration paths must be absolute without .. components'
done
PREFIX=${PREFIX%/}
[[ -n $PREFIX ]] || die 'The filesystem root cannot be an installation prefix'
[[ $PREFIX != *:* ]] || die 'The installation prefix cannot contain : because PATH uses it as a separator'
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
CFG=${FZD_CONF_FILE:-$XDG_CONFIG_HOME/fzd/fzd.conf}
DATA=$PREFIX/share/fzd
MANIFEST=$DATA/install.manifest
# Use a previously verified local fzf bootstrap during updates and verification.
export PATH="$PREFIX/bin:$PATH"
# shellcheck source=installer/dependencies.bash
source "$SCRIPT_DIR/installer/dependencies.bash"
# shellcheck source=installer/lifecycle.bash
source "$SCRIPT_DIR/installer/lifecycle.bash"

if [[ -n $STAGE ]]; then
  [[ $STAGE == /* && $STAGE != / && $STAGE != *'/../'* && $STAGE != */.. ]] || die '--stage requires an absolute disposable staging directory'
  [[ $PREFIX_SET == 1 && $MODE == install && $DEPS == none && -z $FZF_VERSION && -z $FZF_SHA256 ]] || die 'Package staging requires --prefix and forbids dependency downloads and lifecycle operations'
  [[ -f $SCRIPT_DIR/fzd.sh ]] || die 'Package staging requires the source checkout'
  install -Dm755 "$SCRIPT_DIR/fzd.sh" "$STAGE$PREFIX/bin/fzd"
  install -Dm644 "$SCRIPT_DIR/shell/integration.sh" "$STAGE$PREFIX/share/fzd/integration.sh"
  install -Dm644 "$SCRIPT_DIR/fzd.conf.example" "$STAGE$PREFIX/share/fzd/fzd.conf.example"
  install -Dm644 "$SCRIPT_DIR/LICENSE.txt" "$STAGE$PREFIX/share/licenses/fzd/LICENSE.txt"
  log "Staged package payload under $STAGE$PREFIX (no user files or dependencies changed)"
  exit 0
fi

command -v readlink >/dev/null 2>&1 || die 'GNU readlink is required to resolve the installation prefix; install coreutils first'
PREFIX=$(
  readlink -m -- "$PREFIX"
  printf '.'
)
PREFIX=${PREFIX%.}
PREFIX=${PREFIX%$'\n'}
[[ $PREFIX != / && $PREFIX != *:* ]] || die 'Resolved installation prefix cannot be / or contain the PATH separator :'
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
[[ -z $FZF_VERSION ]] || download_fzf
install_owned "$SCRIPT_DIR/fzd.sh" "$PREFIX/bin/fzd" 755
install_owned "$SCRIPT_DIR/shell/integration.sh" "$DATA/integration.sh" 644
install_owned "$SCRIPT_DIR/fzd.conf.example" "$DATA/fzd.conf.example" 644
install_owned "$SCRIPT_DIR/LICENSE.txt" "$DATA/LICENSE.txt" 644
install_owned "$SCRIPT_DIR/install.sh" "$DATA/install.sh" 755
install_owned "$SCRIPT_DIR/installer/dependencies.bash" "$DATA/installer/dependencies.bash" 644
install_owned "$SCRIPT_DIR/installer/lifecycle.bash" "$DATA/installer/lifecycle.bash" 644
if [[ -n $FZF_VERSION ]]; then
  install_owned "$TX/fzf" "$PREFIX/bin/fzf" 755
else
  for index in "${!FILE_PATHS[@]}"; do
    [[ ${FILE_PATHS[index]} != "$PREFIX/bin/fzf" ]] || record file "${FILE_PATHS[index]}" "${FILE_HASHES[index]}"
  done
fi

if ((NO_CONFIG == 0)) && [[ ! -e $CFG && ! -L $CFG ]]; then
  source_config=$SCRIPT_DIR/fzd.conf.example
  if [[ -f $HOME/.fzd/fzd.conf ]]; then
    source_config=$HOME/.fzd/fzd.conf
    bash -n "$source_config" || die 'Legacy FZD configuration contains invalid Bash syntax'
    log 'Copying legacy ~/.fzd/fzd.conf; the original is preserved'
  fi
  write_file "$source_config" "$CFG" 644
fi
for index in "${!RC_PATHS[@]}"; do record rc "${RC_PATHS[index]}" "${RC_NEWLINES[index]}"; done
case "$SHELL_TARGET" in both | bash) edit_rc "$HOME/.bashrc" add ;; esac
case "$SHELL_TARGET" in both | zsh) edit_rc "${ZDOTDIR:-$HOME}/.zshrc" add ;; esac
write_file "$TX/manifest" "$MANIFEST" 600
: >"$TX/committed"
COMMITTED=1
log "Installed $PREFIX/bin/fzd. Configuration preserved at $CFG."
log "Open a new shell: lf (if free), or fzd_cd. Verify/uninstall: bash $(printf %q "$DATA/install.sh") --verify / --uninstall"
log "Original files and transaction journal: $DATA/backups"
