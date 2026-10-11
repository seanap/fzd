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
  version=$("$bin" --version 2>/dev/null) || return 1
  version_ge "$version" 0.44.0 || return 1
  # Clear inherited defaults for a deterministic, non-TTY capability probe.
  printf 'x\n' | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null "$bin" \
    --bind='start:pos(1),load:pos(1),change:reload(printf x)' \
    --no-clear --select-1 --exit-0 >/dev/null 2>&1
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
  base64 | sort | mktemp | install | sha256sum | readlink | truncate) REPLY=coreutils ;;
  find) REPLY=findutils ;;
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
  log "Required package transaction ($PM): ${packages[*]}"
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
    "${privilege[@]}" apt-get update || die 'apt metadata refresh failed'
    "${privilege[@]}" apt-get install --no-install-recommends -y "${packages[@]}" || die 'apt installation failed'
    ;;
  pacman) "${privilege[@]}" pacman -S --needed --noconfirm "${packages[@]}" || die 'pacman installation failed (refresh/upgrade the system separately)' ;;
  dnf) "${privilege[@]}" dnf install -y "${packages[@]}" || die 'dnf installation failed' ;;
  esac
}

collect_missing() {
  local tool
  MISSING=()
  for tool in base64 sort mktemp install sha256sum readlink truncate find; do
    have "$tool" || MISSING+=("$tool")
  done
  have fzf || [[ -n $FZF_VERSION ]] || MISSING+=(fzf)
  # The runtime accepts a single editor executable. Preserve EDITOR/VISUAL.
  if ! have "${EDITOR:-${VISUAL:-micro}}" && ! have micro; then MISSING+=(micro); fi
  if [[ $DEPS == recommended ]]; then
    have file || MISSING+=(file)
    have tree || MISSING+=(tree)
    have fd || have fdfind || MISSING+=(fd)
    have bat || have batcat || MISSING+=(bat)
  fi
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
  if ! printf '' | base64 -w 0 >/dev/null 2>&1; then die 'GNU-compatible base64 with -w 0 is required; install coreutils'; fi
  if ! printf '\0' | sort -zf >/dev/null 2>&1; then die 'GNU-compatible sort with -zf is required; install coreutils'; fi
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
