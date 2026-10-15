# Optional shell engines are shared dependencies, not FZD-owned application files.
# Existing installations are reused; FZD never overwrites or uninstalls them.
_inline_find_engines() {
  local path
  BLESH_PATH=${FZD_BLESH_PATH:-}
  AUTOSUGGEST_PATH=${FZD_ZSH_AUTOSUGGESTIONS_PATH:-}
  if [[ ($SHELL_TARGET == both || $SHELL_TARGET == bash) && -n $BLESH_PATH && ! -r $BLESH_PATH ]]; then die 'FZD_BLESH_PATH must name a readable ble.sh'; fi
  if [[ ($SHELL_TARGET == both || $SHELL_TARGET == zsh) && -n $AUTOSUGGEST_PATH && ! -r $AUTOSUGGEST_PATH ]]; then die 'FZD_ZSH_AUTOSUGGESTIONS_PATH must name a readable plugin'; fi
  if [[ -z $BLESH_PATH ]]; then
    for path in "$PREFIX/share/blesh/ble.sh" "${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh" \
      /usr/share/blesh/ble.sh /usr/local/share/blesh/ble.sh; do
      [[ ! -r $path ]] || {
        BLESH_PATH=$path
        break
      }
    done
  fi
  if [[ -z $AUTOSUGGEST_PATH ]]; then
    for path in /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
      /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
      "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" \
      "${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"; do
      [[ ! -r $path ]] || {
        AUTOSUGGEST_PATH=$path
        break
      }
    done
  fi
}

_inline_collect_missing() {
  _inline_find_engines
  local tool
  if [[ $SHELL_TARGET == both || $SHELL_TARGET == bash ]]; then
    have ps || MISSING+=(ps)
    if [[ -z $BLESH_PATH ]]; then
      if [[ $DEPS == none ]]; then
        MISSING+=(ble.sh)
      else
        for tool in curl tar xz; do have "$tool" || MISSING+=("$tool"); done
        [[ -s ${CURL_CA_BUNDLE:-${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}} || -s /etc/pki/tls/certs/ca-bundle.crt ]] || MISSING+=(ca-certificates)
      fi
    fi
  fi
  if [[ $SHELL_TARGET == both || $SHELL_TARGET == zsh ]]; then
    have zsh || MISSING+=(zsh)
    [[ -n $AUTOSUGGEST_PATH ]] || MISSING+=(zsh-autosuggestions)
  fi
}

_inline_install_blesh() {
  [[ $SHELL_TARGET == both || $SHELL_TARGET == bash ]] || return 0
  [[ -z $BLESH_PATH ]] || return 0
  local archive=ble-0.4.0-devel3-2.tar.xz digest member
  local expected=bdcdcfff216495403adf82a701fe41675f64b64644dc77caabd3e015871ebd61
  [[ ! -e $PREFIX/share/blesh && ! -L $PREFIX/share/blesh ]] || die 'Existing blesh directory has no ble.sh; preserve it and set FZD_BLESH_PATH explicitly'
  log 'Downloading pinned upstream ble.sh v0.4.0-devel3-2 for Bash inline suggestions'
  curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 120 --retry 2 --output "$TX/$archive" \
    "https://github.com/akinomyoga/ble.sh/releases/download/v0.4.0-devel3/$archive" || die 'ble.sh download failed; FZD installation will be rolled back'
  digest=$(sha256sum <"$TX/$archive")
  [[ ${digest%% *} == "$expected" ]] || die 'ble.sh SHA256 mismatch; no downloaded code was installed or executed'
  tar -tJf "$TX/$archive" >"$TX/ble-members" || die 'Invalid ble.sh archive'
  while IFS= read -r member; do
    [[ $member == ble-0.4.0-devel3/* && /$member/ != */../* ]] || die 'Unexpected ble.sh archive path'
  done <"$TX/ble-members"
  mkdir "$TX/blesh"
  tar -xJf "$TX/$archive" --strip-components=1 --no-same-owner --no-same-permissions -C "$TX/blesh" || die 'ble.sh extraction failed'
  bash -n "$TX/blesh/ble.sh" || die 'Invalid ble.sh shell syntax'
  # GNU no-clobber publication; a destination appearing meanwhile is preserved.
  mv -Tn -- "$TX/blesh" "$PREFIX/share/blesh" || die 'Could not install ble.sh'
  [[ ! -e $TX/blesh ]] || die 'ble.sh destination appeared during installation; it was preserved'
  BLESH_PATH=$PREFIX/share/blesh/ble.sh
  log "Installed shared Bash dependency at $BLESH_PATH (preserved on FZD uninstall)"
}
