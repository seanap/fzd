#!/usr/bin/env bats
load helpers/common
setup() {
  setup_fixture
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export FZD_TEST_LOG="$BATS_TEST_TMPDIR/args"
}

@test "editor parses arguments without eval and preserves unusual filenames" {
  local path="$FIXTURE_ROOT/a '\" \$(touch nope)"
  touch "$path"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/vim"
  chmod +x "$TEST_BIN/vim"
  run bash -euc 'source "$1/fzd.sh"; source "$1/lib/command.bash"; _terminal_run() { printf "%s\0" "$@" >"$FZD_TEST_LOG"; }; EDITOR="vim -f \"a b\""; _open_in_editor "$2"' _ "$FZD_REPO" "$path"
  [ "$status" -eq 0 ]
  run bash -euc 'mapfile -d "" -t args <"$FZD_TEST_LOG"; [[ ${args[0]} == vim && ${args[1]} == -f && ${args[2]} == "a b" && ${args[3]} == -- && ${args[4]} == "$1" ]]' _ "$path"
  [ "$status" -eq 0 ]
}

@test "unsafe editor expressions are rejected without execution and fallback respects precedence" {
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/micro"
  chmod +x "$TEST_BIN/micro"
  run bash -euc 'source "$1/lib/command.bash"; for value in "vim; touch $2/pwn" "vim \$(touch $2/pwn)" "vim | sh" "vim \"unfinished"; do ! _fzd_command_parse "$value" || exit 1; done; EDITOR=missing; VISUAL="micro -x"; _fzd_editor_command; [[ ${FZD_COMMAND[*]} == micro ]]; EDITOR=""; _fzd_editor_command; [[ ${FZD_COMMAND[*]} == "micro -x" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  [ ! -e "$FIXTURE_ROOT/pwn" ]
}

@test "current Omarchy wrapper uses live selected editor and adds exactly one separator" {
  mkdir -p "$HOME/.local/state/omarchy/defaults"
  cp "$FZD_REPO/tests/fixtures/omarchy/omarchy-launch-editor" "$TEST_BIN/omarchy-launch-editor"
  for tool in nvim vim; do printf '#!/bin/sh\nprintf "%%s\\0" "${0##*/}" "$@" >"$FZD_TEST_LOG"\n' >"$TEST_BIN/$tool"; done
  printf '#!/bin/sh\ncommand -v "$1" >/dev/null\n' >"$TEST_BIN/omarchy-cmd-present"
  chmod +x "$TEST_BIN/omarchy-launch-editor" "$TEST_BIN/nvim" "$TEST_BIN/vim" "$TEST_BIN/omarchy-cmd-present"
  touch "$FIXTURE_ROOT/a file"
  for tool in nvim vim; do
    printf '%s\n' "$tool" >"$HOME/.local/state/omarchy/defaults/editor"
    run bash -euc 'source "$1/fzd.sh"; _terminal_run() { "$@"; }; EDITOR="omarchy-launch-editor --inline"; _open_in_editor "$2"; mapfile -d "" -t a <"$FZD_TEST_LOG"; [[ ${#a[@]} == 3 && ${a[0]} == "$3" && ${a[1]} == -- && ${a[2]} == "$2" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT/a file" "$tool"
    [ "$status" -eq 0 ]
  done
}

theme_fixture() {
  mkdir -p "$XDG_STATE_HOME/omarchy/current/theme"
  cp "$FZD_REPO/tests/fixtures/omarchy/$1.toml" "$XDG_STATE_HOME/omarchy/current/theme/colors.toml"
  cp "$FZD_REPO/tests/fixtures/omarchy/omarchy-theme-color" "$TEST_BIN/omarchy-theme-color"
  chmod +x "$TEST_BIN/omarchy-theme-color"
}

@test "current light and dark Omarchy palettes apply once and explicit colors win" {
  for theme in tokyo-night catppuccin-latte; do
    theme_fixture "$theme"
    run bash -euc 'source "$1/fzd.sh"; source "$1/lib/theme.bash"; _fzd_theme_init; [[ ${#FZD_THEME_OPTS[@]} -gt 5 && $FZD_COLOR_DIR == "$2" ]]; before=$FZD_THEME_SNAPSHOT; omarchy-theme-color() { printf called >>"$FZD_TEST_LOG"; return 99; }; _fzd_theme_init --_preview; [[ $before == "$FZD_THEME_SNAPSHOT" ]]; FZD_COLOR_DIR=""; FZD_COLOR_BORDER="#010203"; _fzd_theme_init --_preview; [[ $FZD_COLOR_DIR == "" && ${FZD_THEME_OPTS[-1]} == --color=border:#010203 ]]; FZD_THEME_SNAPSHOT=""; _fzd_theme_init --_preview; [[ ! -e $FZD_TEST_LOG ]]' _ "$FZD_REPO" "$([[ $theme == tokyo-night ]] && echo '#7aa2f7' || echo '#1e66f5')"
    [ "$status" -eq 0 ]
  done
}

@test "inherited fzf colors and opt out preserve user palettes without parsing shell code" {
  theme_fixture tokyo-night
  export FZF_DEFAULT_OPTS='--color=bg:#123456'
  run bash -euc 'source "$1/fzd.sh"; source "$1/lib/theme.bash"; _fzd_theme_init; [[ ${#FZD_THEME_OPTS[@]} == 0 ]]; unset FZF_DEFAULT_OPTS; printf "%s" "--color=light" >"$2"; FZF_DEFAULT_OPTS_FILE=$2; _fzd_theme_init; [[ ${#FZD_THEME_OPTS[@]} == 0 ]]; unset FZD_COLOR_DIR FZD_COLOR_FILE; FZD_OMARCHY_THEME=0; _fzd_theme_init; [[ ! ${FZD_COLOR_DIR+x} && -z $FZD_THEME_SNAPSHOT ]]' _ "$FZD_REPO" "$BATS_TEST_TMPDIR/fzfopts"
  [ "$status" -eq 0 ]
}

@test "Wayland and X11 copy exact absolute bytes while headless and provider failures remain usable" {
  for tool in wl-copy xclip xsel; do
    printf '#!/bin/sh\ncat >"$FZD_TEST_LOG"\nexit "${CLIP_STATUS:-0}"\n' >"$TEST_BIN/$tool"
    chmod +x "$TEST_BIN/$tool"
  done
  local path="$FIXTURE_ROOT/strange ' \""$'\n'
  touch "$path"
  for display in wayland xclip xsel; do
    run bash -euc 'source "$1/fzd.sh"; source "$1/lib/integrations.bash"; unset DISPLAY WAYLAND_DISPLAY; if [[ $3 == wayland ]]; then WAYLAND_DISPLAY=wayland-1; else DISPLAY=:0; fi; _copy_absolute_path "$2"; [[ $FZD_STATUS == "Path copied" ]]; printf "%s" "$2" | cmp - "$FZD_TEST_LOG"; CLIP_STATUS=1; export CLIP_STATUS; _copy_absolute_path "$2"; [[ $FZD_STATUS == "Clipboard copy failed" ]]; unset WAYLAND_DISPLAY DISPLAY; _copy_absolute_path "$2"; [[ $FZD_STATUS == "No clipboard provider for this display" ]]' _ "$FZD_REPO" "$path" "$display"
    [ "$status" -eq 0 ]
    if [[ $display == xclip ]]; then rm "$TEST_BIN/xclip"; fi
  done
}

@test "Lazygit checks repositories on action and restores interactive terminal through common runner" {
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$FZD_TEST_LOG"\necho "${GIT_INSIDE:-true}"\n' >"$TEST_BIN/git"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/lazygit"
  chmod +x "$TEST_BIN/git" "$TEST_BIN/lazygit"
  touch "$FIXTURE_ROOT/file"
  run bash -euc 'source "$1/fzd.sh"; source "$1/lib/integrations.bash"; original=$PWD; expected_directory=$2; _terminal_run() { [[ $1 == lazygit && $PWD == "$expected_directory" ]]; }; _launch_lazygit "$2/file"; [[ $PWD == "$original" && $FZD_STATUS == "Returned from Lazygit" ]]; GIT_INSIDE=false; export GIT_INSIDE; _launch_lazygit "$2"; [[ $FZD_STATUS == "Selection is outside a Git working tree" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FZD_TEST_LOG")" -eq 2 ]
}

@test "Chafa uses bounded symbols rendering and discards partial failures" {
  printf '#!/bin/sh\necho image/png\n' >"$TEST_BIN/file"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"$FZD_TEST_LOG"\necho rendered\nexit "${RENDER_STATUS:-0}"\n' >"$TEST_BIN/chafa"
  chmod +x "$TEST_BIN/file" "$TEST_BIN/chafa"
  touch "$FIXTURE_ROOT/image.png"
  export FZF_PREVIEW_COLUMNS=110 FZF_PREVIEW_LINES=30
  run bash -euc 'source "$1/fzd.sh"; FZD_PREVIEW_TIMEOUT=1; _preview_file "$2"' _ "$FZD_REPO" "$FIXTURE_ROOT/image.png"
  [ "$status" -eq 0 ]
  [ "$output" = rendered ]
  grep -q -- '--size=110x30' "$FZD_TEST_LOG"
  grep -q -- '--format=symbols' "$FZD_TEST_LOG"
  export RENDER_STATUS=1
  run bash -euc 'source "$1/fzd.sh"; FZD_PREVIEW_TIMEOUT=1; _preview_file "$2"' _ "$FZD_REPO" "$FIXTURE_ROOT/image.png"
  [ "$status" -eq 0 ]
  [[ "$output" != *rendered* ]]
}

@test "Glow preserves style and falls back on failure or timeout" {
  printf '# Heading\n\n| A | B |\n|---|---|\n| x | y |\n```sh\necho hi\n```\n' >"$FIXTURE_ROOT/README.md"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"$FZD_TEST_LOG"\necho markdown\nif [ "${RENDER_SLEEP:-0}" = 1 ]; then sleep 3; fi\nexit "${RENDER_STATUS:-0}"\n' >"$TEST_BIN/glow"
  chmod +x "$TEST_BIN/glow"
  export FZF_PREVIEW_COLUMNS=90
  run bash -euc 'source "$1/fzd.sh"; FZD_PREVIEW_TIMEOUT=1; FZD_PREVIEW_MAX_LINES=200; _preview_file "$2"' _ "$FZD_REPO" "$FIXTURE_ROOT/README.md"
  [ "$status" -eq 0 ]
  [ "$output" = markdown ]
  ! grep -q style "$FZD_TEST_LOG"
  grep -q -- '--pager=false' "$FZD_TEST_LOG"
  for variable in RENDER_STATUS RENDER_SLEEP; do
    export "$variable=1"
    run bash -euc 'source "$1/fzd.sh"; FZD_PREVIEW_TIMEOUT=1; FZD_PREVIEW_MAX_LINES=200; _preview_file "$2"' _ "$FZD_REPO" "$FIXTURE_ROOT/README.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *'# Heading'* ]]
    [[ "$output" != *markdown* ]]
    unset "$variable"
  done
}

@test "optional action bindings preserve existing controls and local navigation" {
  export FZD_STUB_PLAN="$BATS_TEST_TMPDIR/plan"
  : >"$FZD_STUB_PLAN"
  touch "$FIXTURE_ROOT/selected"
  plan_action COPY_PATH "$FIXTURE_ROOT/selected"
  plan_action LAZYGIT "$FIXTURE_ROOT"
  plan_action ENTER "$FIXTURE_ROOT"
  run_planned_session
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT" ]
}

@test "current upstream Omarchy Bash startup keeps aliases zoxide hooks and completion preferences" {
  mkdir -p "$HOME/omarchy/default/bash"
  local item
  for item in rc aliases init inputrc; do cp "$FZD_REPO/tests/fixtures/omarchy/bash-$item" "$HOME/omarchy/default/bash/$item"; done
  for item in envs shell functions completions; do printf ':\n' >"$HOME/omarchy/default/bash/$item"; done
  run bash --noprofile --norc -ic 'export OMARCHY_PATH="$HOME/omarchy"; source "$OMARCHY_PATH/default/bash/rc"; before=$(alias cd ls ff); hook=$PROMPT_COMMAND; complete -W custom lf; source "$1/shell/integration.sh"; source "$1/shell/integration.sh"; [[ $(alias cd ls ff) == "$before" ]]; [[ $PROMPT_COMMAND == *"$hook"* ]]; [[ $(complete -p lf) == *custom* ]]; [[ $(declare -f z) == *zoxide* ]]' _ "$FZD_REPO"
  [ "$status" -eq 0 ]
}

@test "native Chafa renders a real PNG through captured FZD preview" {
  [[ -x $FZD_REAL_CHAFA ]] || skip 'Chafa unavailable for native preview validation'
  ln -s "$FZD_REAL_CHAFA" "$TEST_BIN/chafa"
  # A 1x1 PNG, no external image libraries needed by the fixture.
  printf '%s' iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ZkAAAAASUVORK5CYII= | base64 -d >"$FIXTURE_ROOT/tiny.png"
  run bash -euc 'source "$1/fzd.sh"; FZD_PREVIEW_TIMEOUT=2; _preview_file "$2"' _ "$FZD_REPO" "$FIXTURE_ROOT/tiny.png"
  [ "$status" -eq 0 ]
  [[ "$output" != *'PNG image data'* ]]
  [ -n "$output" ]
}

@test "ordinary startup and preview helpers avoid missing Omarchy utility PATH scans" {
  run bash -euc 'source "$1/fzd.sh"; _fzd_paths; probed=0; _have() { if [[ $1 == omarchy-theme-color ]]; then probed=1; return 1; fi; command -v "$1" >/dev/null; }; _fzd_init --_preview; [[ $probed == 0 && ${#FZD_THEME_OPTS[@]} == 0 ]]' _ "$FZD_REPO"
  [ "$status" -eq 0 ]
}
