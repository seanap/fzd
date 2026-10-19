# Enhanced convenience only. Fonts are shared user data, never FZD-owned files.
_font_is_wsl() {
  [[ -n ${WSL_DISTRO_NAME:-} || -n ${WSL_INTEROP:-} ]] ||
    [[ $(uname -r) == *[Mm]icrosoft* ]]
}

_font_guidance() {
  log 'Select a Nerd Font in your terminal font settings (for example JetBrainsMono Nerd Font Mono).'
  log 'The active terminal font cannot be identified reliably; check these glyphs:     '
  log 'If they appear as squares, select a compatible font or set FZD_ICONS=0 in your fzd.conf.'
}

_font_find_compatible() {
  have fc-list || return 1
  local families
  # Verify representative eza glyph coverage as well as known family names.
  # This also accepts a custom verified font/fallback with the required glyphs.
  families=$(fc-list ':charset=f115 f15b e5ff f024b' family 2>/dev/null) || return 1
  [[ -n $families ]] || return 1
  if have omarchy-font-current; then
    local selected
    selected=$(omarchy-font-current 2>/dev/null) || selected=''
    [[ -z $selected ]] || log "Omarchy fontconfig monospace: $selected (terminal selection may differ)"
  fi
  log "Compatible font coverage found: ${families%%$'\n'*}; no font installed"
}

_font_install() (
  # Keep all archive handling private; extract only the expected regular font.
  local work destination digest
  local version=3.4.0 member=JetBrainsMonoNerdFontMono-Regular.ttf
  local expected=ef552a3e638f25125c6ad4c51176a6adcdce295ab1d2ffacf0db060caf8c1582
  destination=$XDG_DATA_HOME/fonts/fzd-nerd-fonts-$version
  [[ ! -e $destination && ! -L $destination ]] || {
    warn "Existing font directory preserved: $destination; run fc-cache or inspect it manually"
    return 0
  }
  work=$(mktemp -d "$TX/font.XXXXXXXX") || return 1
  trap 'rm -rf -- "$work"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 120 --retry 2 --output "$work/font.tar.xz" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v$version/JetBrainsMono.tar.xz" || return 1
  digest=$(sha256sum <"$work/font.tar.xz") || return 1
  [[ ${digest%% *} == "$expected" ]] || {
    warn 'Nerd Font SHA256 mismatch; downloaded font discarded'
    return 1
  }
  mkdir -m 700 "$work/fonts" || return 1
  tar -xOJf "$work/font.tar.xz" "$member" >"$work/fonts/$member" || return 1
  [[ -s $work/fonts/$member ]] || return 1
  chmod 644 "$work/fonts/$member" || return 1
  # Validate before publication; fc-scan is supplied by fontconfig.
  fc-scan --format '%{family}\n' "$work/fonts/$member" >"$work/family" || return 1
  [[ -s $work/family ]] || return 1
  (
    umask 077
    mkdir -p -- "${destination%/*}"
  ) || return 1
  mv -Tn -- "$work/fonts" "$destination" || return 1
  [[ ! -d $work/fonts ]] || {
    warn 'Font destination appeared; existing fonts preserved'
    return 1
  }
  log "Installed shared user font at $destination (retained on uninstall)"
  fc-cache "$destination" || warn 'Font installed; refresh the font cache with fc-cache when available'
)

_font_setup() {
  if _font_is_wsl; then
    log 'WSL: install a Nerd Font on Windows, then select it in Windows Terminal → Settings → Profiles → Appearance → Font face.'
    log 'Official fonts: https://www.nerdfonts.com/font-downloads (extract and use Windows Install). Linux fonts do not configure the Windows host terminal.'
    _font_guidance
    return 0
  fi
  if [[ $(uname -s) != Linux ]]; then
    warn 'Automatic font installation supports native Linux; install a Nerd Font with your platform tools'
    _font_guidance
    return 0
  fi
  local tool
  local -a packages=()
  if ! _font_find_compatible; then
    for tool in fc-list fc-scan fc-cache curl tar xz; do
      have "$tool" || packages+=("$tool")
    done
    if ((${#packages[@]})); then
      if [[ $DEPS == none ]]; then
        warn 'Font tools unavailable with --deps none; install fontconfig, curl, tar and xz for automatic font setup'
        _font_guidance
        return 0
      fi
      detect_pm
      local -a mapped=()
      for tool in "${packages[@]}"; do
        package_for "$tool"
        mapped+=("$REPLY")
      done
      install_packages "${mapped[@]}" || return 1
    fi
    # Installing fontconfig may reveal an already installed compatible font.
    _font_find_compatible || _font_install || {
      _font_guidance
      return 1
    }
  fi
  _font_guidance
}
