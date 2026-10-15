#!/usr/bin/env bats
load helpers/common
load helpers/terminal
setup() {
  setup_terminal_fixture
  : >"$FZD_PTY_ERROR"
  export HOME="$BATS_TEST_TMPDIR/home"
  export FZD_COMPAT_ROOT="${FZD_COMPAT_ROOT:-$FZD_REPO/.test-work/compat}"
  export FZD_SHELL_BUFFER="$BATS_TEST_TMPDIR/buffer"
  export FZD_BIN="$FZD_SCRIPT"
  export ZDOTDIR="$HOME"
  mkdir -p "$HOME" "$FIXTURE_ROOT/docker/immich" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
  zoxide add -- "$FIXTURE_ROOT/docker/immich"
}
teardown() { stop_terminal; }

start_completion_shell() {
  local shell=$1 engine=${2:-none} command
  if [[ $engine == blesh ]]; then
    # Upstream treats an out/ tree as a development build and caches beside it.
    # Load a private copy so read-only mounted fixtures remain untouched.
    mkdir -p "$HOME/blesh"
    cp -R "$FZD_COMPAT_ROOT/blesh/out/." "$HOME/blesh/"
  fi
  if [[ $shell == bash ]]; then
    cat >"$HOME/rc" <<'RC'
PS1='FZD_PROMPT> '
source "$FZD_REPO/shell/integration.sh"
source "$FZD_REPO/shell/integration.sh"
[[ ${FZD_TEST_NO_HOOK:-0} != 1 ]] || eval "$(zoxide init bash --no-cmd --hook none)"
bind 'set show-all-if-ambiguous on'
if [[ $FZD_TEST_ENGINE == blesh ]]; then
  source "$HOME/blesh/ble.sh" --rcfile /dev/null
  bleopt complete_auto_delay=50
fi
bind -x '"\C-x\C-b": printf "%s" "$READLINE_LINE" >"$FZD_SHELL_BUFFER"'
RC
    printf -v command 'exec bash --noprofile --rcfile %q -i' "$HOME/rc"
  else
    cat >"$HOME/.zshrc" <<'RC'
PS1='FZD_PROMPT> '
source "$FZD_REPO/shell/integration.sh"
source "$FZD_REPO/shell/integration.sh"
[[ ${FZD_TEST_NO_HOOK:-0} != 1 ]] || eval "$(zoxide init zsh --no-cmd --hook none)"
if [[ $FZD_TEST_ENGINE == autosuggestions ]]; then
  ZSH_AUTOSUGGEST_STRATEGY=(completion)
  source "$FZD_COMPAT_ROOT/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
_fzd_test_buffer() { printf '%s' "$BUFFER" >"$FZD_SHELL_BUFFER"; }
zle -N _fzd_test_buffer
bindkey '^X^B' _fzd_test_buffer
RC
    printf -v command 'exec zsh -d -i'
  fi
  if [[ $engine == installed ]]; then
    if [[ $shell == bash ]]; then
      cat >"$HOME/rc" <<'RC'
PS1='FZD_PROMPT> '
source "$HOME/.bashrc"
bind -x '"\C-x\C-b": printf "%s" "$READLINE_LINE" >"$FZD_SHELL_BUFFER"'
RC
    else
      # The ordinary helper wrote its fixture zshrc. Replace it with the exact
      # installer output kept by prepare_installed_inline, plus test widgets.
      cp "$HOME/installed.zshrc" "$HOME/.zshrc"
      cat >>"$HOME/.zshrc" <<'RC'
PS1='FZD_PROMPT> '
_fzd_test_buffer() { printf '%s' "$BUFFER" >"$FZD_SHELL_BUFFER"; }
zle -N _fzd_test_buffer
bindkey '^X^B' _fzd_test_buffer
RC
    fi
  fi
  rm -f "$FZD_SHELL_BUFFER.ready"
  if [[ $shell == bash ]]; then
    printf '%s\n' 'printf ready >"$FZD_SHELL_BUFFER.ready"' >>"$HOME/rc"
  else
    printf '%s\n' 'printf ready >"$FZD_SHELL_BUFFER.ready"' >>"$HOME/.zshrc"
  fi
  export FZD_REPO FZD_TEST_ENGINE=$engine
  tmux -S "$SOCKET" -f /dev/null new-session -d -x 120 -y 32 -s fzd -c "$FIXTURE_ROOT" "$command"
  wait_file "$FZD_SHELL_BUFFER.ready"
  wait_screen FZD_PROMPT
}

capture_buffer() {
  rm -f "$FZD_SHELL_BUFFER"
  tmux -S "$SOCKET" send-keys C-x C-b
  wait_file "$FZD_SHELL_BUFFER"
}

@test "native Bash and zsh Tab complete learned names and preserve escaped local paths" {
  local shell
  mkdir -p "$FIXTURE_ROOT/local space"
  for shell in bash zsh; do
    start_completion_shell "$shell"
    tmux -S "$SOCKET" send-keys -l 'lf imm'
    tmux -S "$SOCKET" send-keys Tab
    wait_screen 'lf immich'
    capture_buffer
    [[ $(cat "$FZD_SHELL_BUFFER") == 'lf immich'* ]]
    tmux -S "$SOCKET" send-keys C-u
    tmux -S "$SOCKET" send-keys -l 'lf local'
    tmux -S "$SOCKET" send-keys Tab
    wait_screen 'local\ space'
    capture_buffer
    [[ $(cat "$FZD_SHELL_BUFFER") == *'local\ space'* ]]
    stop_terminal
  done
}

check_inline_suggestion() {
  local shell=$1 engine=$2
  start_completion_shell "$shell" "$engine"
  tmux -S "$SOCKET" send-keys -l 'lf imm'
  wait_screen 'lf immich'
  # The suffix must be displayed while still absent from the editable buffer.
  capture_buffer
  [ "$(cat "$FZD_SHELL_BUFFER")" = 'lf imm' ]
  # Inspecting the buffer can cancel an engine's current suggestion. Retype
  # its final character to request a fresh suggestion before accepting it.
  tmux -S "$SOCKET" send-keys BSpace
  tmux -S "$SOCKET" send-keys -l m
  wait_screen 'lf immich'
  tmux -S "$SOCKET" send-keys Right
  capture_buffer
  [[ $(cat "$FZD_SHELL_BUFFER") == 'lf immich'* ]]
  tmux -S "$SOCKET" capture-pane -e -p -t fzd:0.0 >"$BATS_TEST_TMPDIR/accepted-screen.txt"
}

@test "ble.sh displays a learned directory as ghost text and Right accepts it" {
  [[ -f $FZD_COMPAT_ROOT/blesh/out/ble.sh ]] || skip 'run bash dev/prepare-shell-compat.sh'
  check_inline_suggestion bash blesh
}

@test "zsh-autosuggestions completion strategy displays ghost text and Right accepts it" {
  [[ -f $FZD_COMPAT_ROOT/zsh-autosuggestions/zsh-autosuggestions.zsh ]] || skip 'run bash dev/prepare-shell-compat.sh'
  check_inline_suggestion zsh autosuggestions
}

@test "Enter on an uncompleted partial query jumps in both real interactive shells" {
  local shell
  for shell in bash zsh; do
    start_completion_shell "$shell"
    tmux -S "$SOCKET" send-keys -l 'lf imm'
    tmux -S "$SOCKET" send-keys Enter
    tmux -S "$SOCKET" send-keys -l 'printf "%s" "$PWD" >"$FZD_SHELL_BUFFER"'
    tmux -S "$SOCKET" send-keys Enter
    wait_file "$FZD_SHELL_BUFFER"
    [ "$(cat "$FZD_SHELL_BUFFER")" = "$FIXTURE_ROOT/docker/immich" ]
    stop_terminal
    rm -f "$FZD_SHELL_BUFFER"
  done
}

@test "ordinary interactive cd is learned with only one upstream hook after repeated sourcing" {
  local shell
  for shell in bash zsh; do
    start_completion_shell "$shell"
    tmux -S "$SOCKET" send-keys -l 'mkdir -p elsewhere; cd elsewhere'
    tmux -S "$SOCKET" send-keys Enter
    tmux -S "$SOCKET" send-keys -l 'zoxide query elsewhere >"$FZD_SHELL_BUFFER"'
    tmux -S "$SOCKET" send-keys Enter
    wait_file "$FZD_SHELL_BUFFER"
    [ "$(cat "$FZD_SHELL_BUFFER")" = "$FIXTURE_ROOT/elsewhere" ]
    if [[ $shell == bash ]]; then
      tmux -S "$SOCKET" send-keys -l 'printf "%s\n" "${PROMPT_COMMAND[@]}" >"$FZD_SHELL_BUFFER.hooks"'
    else
      tmux -S "$SOCKET" send-keys -l 'printf "%s\n" "${precmd_functions[@]}" "${chpwd_functions[@]}" >"$FZD_SHELL_BUFFER.hooks"'
    fi
    tmux -S "$SOCKET" send-keys Enter
    wait_file "$FZD_SHELL_BUFFER.hooks"
    [ "$(grep -o __zoxide_hook "$FZD_SHELL_BUFFER.hooks" | wc -l)" -eq 1 ]
    ! grep -q _fzd_init_zoxide "$FZD_SHELL_BUFFER.hooks"
    stop_terminal
    rm -f "$FZD_SHELL_BUFFER"
  done
}

@test "upstream hook none stays disabled while explicit interactive FZD jumps still learn" {
  export FZD_TEST_NO_HOOK=1
  local shell
  mkdir -p "$FIXTURE_ROOT/explicit-jump" "$FIXTURE_ROOT/ordinary-cd"
  for shell in bash zsh; do
    start_completion_shell "$shell"
    tmux -S "$SOCKET" send-keys -l 'cd ordinary-cd; lf ../explicit-jump; zoxide query explicit-jump >"$FZD_SHELL_BUFFER"'
    tmux -S "$SOCKET" send-keys Enter
    wait_file "$FZD_SHELL_BUFFER"
    [ "$(cat "$FZD_SHELL_BUFFER")" = "$FIXTURE_ROOT/explicit-jump" ]
    run zoxide query ordinary-cd
    [ "$status" -ne 0 ]
    stop_terminal
    rm -f "$FZD_SHELL_BUFFER"
  done
}

prepare_installed_inline() {
  local archive="$FZD_COMPAT_ROOT/ble-0.4.0-devel3-2.tar.xz"
  [[ -f $archive ]] || skip 'run bash dev/prepare-shell-compat.sh'
  mkdir -p "$HOME/dependencies"
  tar -xJf "$archive" -C "$HOME/dependencies"
  export FZD_BLESH_PATH="$HOME/dependencies/ble-0.4.0-devel3/ble.sh"
  export FZD_ZSH_AUTOSUGGESTIONS_PATH="$FZD_COMPAT_ROOT/zsh-autosuggestions/zsh-autosuggestions.zsh"
  local native_plugin
  for native_plugin in /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
    /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh; do
    [[ ! -r $native_plugin ]] || {
      export FZD_ZSH_AUTOSUGGESTIONS_PATH=$native_plugin
      break
    }
  done
  unset FZD_BIN
  run bash "$FZD_REPO/install.sh" --inline-suggestions --deps none --noninteractive
  [ "$status" -eq 0 ]
  cp "$HOME/.zshrc" "$HOME/installed.zshrc"
}

@test "installer-enabled Bash inline suggestions display gray ghost text with Right acceptance" {
  prepare_installed_inline
  check_inline_suggestion bash installed
}

@test "installer-enabled zsh inline suggestions work on the first prompt without manual compinit or plugin setup" {
  prepare_installed_inline
  check_inline_suggestion zsh installed
}

@test "fresh zsh initializes compinit once and preserves a framework initialized later in startup" {
  cat >"$HOME/.zshrc" <<'RC'
PS1='FZD_PROMPT> '
source "$FZD_REPO/shell/integration.sh"
autoload -Uz compinit
compinit -i -D
functions[_fzd_test_original_compinit]=$functions[compinit]
compinit() { printf duplicate >"$FZD_SHELL_BUFFER"; _fzd_test_original_compinit "$@"; }
source "$FZD_REPO/shell/integration.sh"
RC
  export FZD_REPO
  tmux -S "$SOCKET" -f /dev/null new-session -d -x 120 -y 32 -s fzd -c "$FIXTURE_ROOT" 'exec zsh -d -i'
  wait_screen FZD_PROMPT
  tmux -S "$SOCKET" send-keys -l 'lf imm'
  tmux -S "$SOCKET" send-keys Tab
  wait_screen 'lf immich'
  [ ! -e "$FZD_SHELL_BUFFER" ]
}

@test "explicit completion opt-out preserves a zsh setup without compinit" {
  run zsh -efc 'FZD_AUTO_COMPLETION=0; source "$1/shell/integration.sh"; _fzd_init_completion; ! whence compdef' _ "$FZD_REPO"
  [ "$status" -eq 0 ]
}
