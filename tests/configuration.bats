#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "explicit configuration path is loaded" {
  printf 'FZD_GLOBAL_MINLEN=8\n' > "$FZD_CONF_FILE"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "XDG configuration path is loaded when no explicit file is set" {
  unset FZD_CONF_FILE
  mkdir -p "$XDG_CONFIG_HOME/fzd"
  printf 'FZD_GLOBAL_MINLEN=8\n' > "$XDG_CONFIG_HOME/fzd/fzd.conf"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "legacy root variables expand without evaluating shell commands" {
  printf text > "$FIXTURE_ROOT/needle"
  export FZD_GLOBAL_PATHS='${FIXTURE_ROOT}' FIXTURE_ROOT
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
}

@test "shipped configuration defines one backend and one root list" {
  run grep -c '^FZD_GLOBAL_BACKEND=' "$FZD_REPO/fzd.conf.example"
  [ "$output" = 1 ]
  run grep -c '^FZD_GLOBAL_PATHS=' "$FZD_REPO/fzd.conf.example"
  [ "$output" = 1 ]
}
