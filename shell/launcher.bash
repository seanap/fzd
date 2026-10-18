# shellcheck shell=bash
# Used as bash --rcfile; a terminal remains interactive after directory selection.
_fzd_launcher_data=${BASH_SOURCE[0]%/*}
# shellcheck source=/dev/null
source "$_fzd_launcher_data/launcher.conf"
if [[ -r $FZD_LAUNCH_RC ]]; then
  # Normal interactive startup, never evaluated by the installer.
  # shellcheck source=/dev/null
  source "$FZD_LAUNCH_RC"
fi
# shellcheck source=/dev/null
source "$_fzd_launcher_data/integration.sh"
FZD_BIN=$FZD_LAUNCH_BIN FZD_CONF_FILE=$FZD_LAUNCH_CONFIG _fzd_run_and_cd || true
unset _fzd_launcher_data FZD_LAUNCH_RC FZD_LAUNCH_BIN FZD_LAUNCH_CONFIG
