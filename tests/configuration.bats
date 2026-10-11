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

@test "root arrays preserve spaces and override the legacy root string" {
  local root="$BATS_TEST_TMPDIR/root with spaces"
  mkdir -p "$root"
  printf text > "$root/needle"
  printf 'FZD_GLOBAL_ROOTS=(%q)\n' "$root" > "$FZD_CONF_FILE"
  export FZD_GLOBAL_PATHS=/does/not/exist
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$root/needle"
}

@test "legacy root expansion never executes substitution text" {
  export FZD_GLOBAL_PATHS='$(printf hit > FZD_ROOT_MARKER)'
  run bash -c 'cd -- "$1"; exec bash "$2" --_global_list --q needle' _ "$FIXTURE_ROOT" "$FZD_SCRIPT"
  [ ! -e "$FIXTURE_ROOT/FZD_ROOT_MARKER" ]
  [ "$status" -ne 0 ]
  [[ "$output" == *'no accessible global search roots'* ]]
}

@test "invalid numeric settings fail with an actionable diagnostic" {
  export FZD_GLOBAL_MAXRESULTS=oops
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -ne 0 ]
  [[ "$output" == *'FZD_GLOBAL_MAXRESULTS must be a positive integer'* ]]
}

@test "unknown backend fails before launching a picker" {
  export FZD_GLOBAL_BACKEND=unknown
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -ne 0 ]
  [[ "$output" == *'unknown global backend'* ]]
}
