# Dependency operations are separate from user files and never run on uninstall.
have() { command -v "$1" >/dev/null 2>&1; }
version_ge() {
  local current=$1 minimum=$2 a b c x y z
  [[ $current =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))? ]] || return 1
  a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[4]:-0}
  IFS=. read -r x y z <<<"$minimum"
  ((10#$a > 10#$x || (10#$a == 10#$x && (10#$b > 10#$y || (10#$b == 10#$y && 10#$c >= 10#$z)))))
}

check_fzf() {
  local bin=$1 version
  version=$(FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null "$bin" --version 2>/dev/null) || return 1
  version_ge "$version" 0.44.0 || return 1
  # Clear inherited defaults for a deterministic, non-TTY capability probe.
  printf 'x\n' | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null "$bin" \
    --bind='start:pos(1),load:pos(1),change:reload(printf x)' \
    --no-clear --filter=x >/dev/null 2>&1
}

detect_pm() {
  # Use os-release, not whichever foreign package manager happens to be in PATH.
  local ID='' ID_LIKE=''
  # shellcheck source=/dev/null
  [[ -r /etc/os-release ]] && source /etc/os-release
  case " $ID $ID_LIKE " in
  *' debian '* | *' ubuntu '*)
    PM=apt
    have apt-get || die 'apt-get is unavailable'
    ;;
  *' arch '*)
    PM=pacman
    have pacman || die 'pacman is unavailable'
    ;;
  *' fedora '* | *' rhel '*)
    PM=dnf
    have dnf || die 'dnf is unavailable'
    ;;
  *) die 'No supported dependency manager. Install prerequisites manually and use --deps none.' ;;
  esac
}

package_for() {
  local executable=$1
  case "$executable" in
  fd) [[ $PM == pacman ]] && REPLY=fd || REPLY=fd-find ;;
  bat) REPLY=bat ;;
  eza) REPLY=eza ;;
  wl-copy) REPLY=wl-clipboard ;;
  fc-list | fc-cache) REPLY=fontconfig ;;
  xz) [[ $PM == apt ]] && REPLY=xz-utils || REPLY=xz ;;
  head | tr | cat | ls | dirname | basename | wc | tail | base64 | sort | mktemp | install | sha256sum | readlink | truncate | cp | mv | realpath | chmod | rm | mkdir | stat) REPLY=coreutils ;;
  awk) [[ $PM == apt ]] && REPLY=mawk || REPLY=gawk ;;
  flock) [[ $PM == dnf ]] && REPLY=util-linux-core || REPLY=util-linux ;;
  find) REPLY=findutils ;;
  ps) [[ $PM == apt ]] && REPLY=procps || REPLY=procps-ng ;;
  *) REPLY=$executable ;;
  esac
}

install_packages() {
  local package existing
  local -a packages=() privilege=()
  for package; do
    existing=0
    for REPLY in "${packages[@]}"; do [[ $REPLY == "$package" ]] && existing=1; done
    ((existing)) || packages+=("$package")
  done
  ((${#packages[@]})) || return 0
  log "Package transaction ($PM): ${packages[*]}"
  if ((EUID != 0)); then
    have sudo || die "sudo is unavailable. Install these packages as root: ${packages[*]}"
    if ((NONINTERACTIVE)); then
      sudo -n -v || die "sudo authentication is required. Run sudo -v first, or install packages manually: ${packages[*]}"
      privilege=(sudo -n)
    else
      sudo -v || die 'sudo authentication failed; no FZD files were changed'
      privilege=(sudo)
    fi
  fi
  case "$PM" in
  apt)
    "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update </dev/null || die 'apt metadata refresh failed'
    "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y "${packages[@]}" \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold </dev/null || die 'apt installation failed'
    ;;
  pacman) "${privilege[@]}" pacman -S --needed --noconfirm "${packages[@]}" </dev/null || die 'pacman installation failed (refresh/upgrade the system separately)' ;;
  dnf) "${privilege[@]}" dnf install -y "${packages[@]}" </dev/null || die 'dnf installation failed' ;;
  esac
}

collect_missing() {
  local tool
  MISSING=()
  for tool in zoxide plocate bash head grep sed awk tr cat ls dirname basename wc tail base64 sort mktemp install sha256sum readlink truncate find cp mv realpath chmod rm mkdir flock stat; do
    have "$tool" || MISSING+=("$tool")
  done
  have fzf || [[ -n $FZF_VERSION ]] || MISSING+=(fzf)
  # Use the same safe argument parsing as the runtime; never source user files.
  if ! declare -F _fzd_editor_command >/dev/null; then
    local command_lib=${BASH_SOURCE[0]%/installer/*}/lib/command.bash
    if [[ -f $command_lib ]]; then
      # shellcheck source=lib/command.bash
      source "$command_lib"
    fi
  fi
  if ! _fzd_editor_command; then MISSING+=(micro); fi
  if [[ ${INLINE_SUGGESTIONS:-keep} == 1 ]]; then _inline_collect_missing; fi
}

collect_recommended() {
  MISSING=()
  have eza || MISSING+=(eza)
  have file || MISSING+=(file)
  have tree || MISSING+=(tree)
  have fd || have fdfind || MISSING+=(fd)
  have bat || have batcat || MISSING+=(bat)
  if [[ ${ENHANCED:-0} == 1 ]]; then
    have chafa || MISSING+=(chafa)
    have glow || MISSING+=(glow)
    if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
      have wl-copy || MISSING+=(wl-copy)
    elif [[ -n ${DISPLAY:-} ]]; then
      have xclip || have xsel || MISSING+=(xclip)
    fi
  fi
}

ensure_recommended() {
  [[ $DEPS == recommended ]] || return 0
  collect_recommended
  ((${#MISSING[@]})) || return 0
  local tool
  local -a optional=("${MISSING[@]}") packages=()
  # Unsupported or unavailable optional packages must not break the core install.
  if ! (detect_pm); then
    warn "Recommended tools unavailable: ${optional[*]}; existing preview/search fallbacks remain usable"
    return 0
  fi
  detect_pm
  for tool in "${optional[@]}"; do
    package_for "$tool"
    packages+=("$REPLY")
  done
  if ! (install_packages "${packages[@]}"); then
    for tool in "${optional[@]}"; do
      package_for "$tool"
      (install_packages "$REPLY") || warn "Optional $tool unavailable; keeping the existing fallback"
    done
  fi
  collect_recommended
  ((${#MISSING[@]} == 0)) || warn "Recommended tools still missing: ${MISSING[*]} (FZD will use available fallbacks)"
  return 0
}

ensure_dependencies() {
  local tool
  local -a packages=()
  collect_missing
  if ((${#MISSING[@]})); then
    [[ $DEPS != none ]] || die "Missing prerequisites: ${MISSING[*]}. Install them or use --deps required."
    detect_pm
    for tool in "${MISSING[@]}"; do
      package_for "$tool"
      packages+=("$REPLY")
    done
    install_packages "${packages[@]}"
    collect_missing
    ((${#MISSING[@]} == 0)) || die "Still missing after package installation: ${MISSING[*]}"
  fi
  if [[ -z $FZF_VERSION ]]; then
    check_fzf "$(command -v fzf)" || die 'fzf must be >= 0.44.0 and support FZD bindings. Use a compatible distro package or --fzf-version VERSION --fzf-sha256 SHA256 (see README).'
  fi
  plocate --version >/dev/null 2>&1 || die 'plocate is installed but cannot execute'
  ensure_locate_index
  ensure_recommended
  local zoxide_version
  zoxide_version=$(zoxide --version) || die 'zoxide could not execute'
  version_ge "${zoxide_version#zoxide }" 0.9.0 || die 'zoxide >= 0.9.0 is required; upgrade your distribution package'
  if ! printf '' | base64 -w 0 >/dev/null 2>&1; then die 'GNU-compatible base64 with -w 0 is required; install coreutils'; fi
  if ! printf '\0' | sort -zf >/dev/null 2>&1; then die 'GNU-compatible sort with -zf is required; install coreutils'; fi
}

locate_index_ready() {
  local locate_probe
  local -a locate_command=(plocate) locate_args=(--count --limit 1)
  if have timeout; then locate_command=(timeout --kill-after=1 3 plocate); fi
  [[ -z ${FZD_LOCATE_DBS:-} ]] || locate_args+=(-d "$FZD_LOCATE_DBS")
  locate_probe=$("${locate_command[@]}" "${locate_args[@]}" -- / 2>/dev/null) && [[ $locate_probe =~ ^[1-9][0-9]*$ ]]
}

ensure_locate_index() {
  locate_index_ready && return 0
  # Use distro defaults only. Never rewrite exclusions, configure services or
  # initialize databases explicitly selected by the caller.
  if [[ ${DEPS:-none} != none && ${NO_UPDATEDB:-0} != 1 && -z ${FZD_LOCATE_DBS:-} ]]; then
    local updater=''
    local -a privilege=()
    if have updatedb; then updater=updatedb; elif have updatedb.plocate; then updater=updatedb.plocate; fi
    if [[ -n $updater ]]; then
      if ((EUID != 0)); then
        if have sudo && sudo -n -v; then
          privilege=(sudo -n)
        else
          warn 'Cannot initialize the plocate index without sudo authorization; run sudo updatedb when ready.'
          updater=''
        fi
      fi
      if [[ -n $updater ]]; then
        log 'Initializing the default plocate index with existing system exclusions; this may take a while.'
        if ! "${privilege[@]}" "$updater" </dev/null; then
          warn 'Index initialization failed; continuing with the filesystem search fallback.'
        fi
      fi
    else
      warn 'updatedb is unavailable; the plocate package normally provides it.'
    fi
  fi
  if ! locate_index_ready; then
    warn 'plocate index is missing, empty or unreadable; global search will retain its filesystem fallback.'
    warn 'Initialize it with sudo updatedb or wait for your distribution indexing schedule. FZD leaves indexing exclusions, services and timers unchanged.'
  fi
  return 0
}

download_fzf() {
  local arch asset url actual
  [[ $FZF_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $FZF_SHA256 =~ ^[a-fA-F0-9]{64}$ ]] || die 'fzf download requires an explicit release version and SHA256 digest'
  if ! have curl || ! have tar || ! have gzip; then die 'fzf download requires curl, tar and gzip; install them first'; fi
  arch=$(uname -m)
  case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; *) die "No fzf download mapping for $arch; install fzf manually" ;; esac
  asset="fzf-${FZF_VERSION}-linux_${arch}.tar.gz"
  url="https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/${asset}"
  log "Downloading explicit fzf release $FZF_VERSION for $arch"
  curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 120 --retry 2 --output "$TX/archive.tar.gz" "$url" || die "fzf download failed: $url"
  actual=$(sha256sum <"$TX/archive.tar.gz")
  actual=${actual%% *}
  [[ ${actual,,} == "${FZF_SHA256,,}" ]] || die 'fzf SHA256 mismatch; nothing was installed'
  # Extract only the expected member into a private file, never archive paths.
  tar -xOzf "$TX/archive.tar.gz" fzf >"$TX/fzf" || die 'fzf archive does not contain the expected executable'
  chmod 755 "$TX/fzf"
  check_fzf "$TX/fzf" || die 'Downloaded fzf is incompatible or could not execute'
}
