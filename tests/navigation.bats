#!/usr/bin/env bats
load helpers/common
setup() {
  setup_fixture
  export FZD_STUB_PLAN="$BATS_TEST_TMPDIR/plan"
  export FZD_STUB_FZF_LOG="$BATS_TEST_TMPDIR/fzf-arguments"
  : >"$FZD_STUB_PLAN"
}

@test "global Right on a file is a no-op and leaves FZD running" {
  export FZD_GLOBAL_BACKEND=cache
  printf text >"$FIXTURE_ROOT/needle-file"
  plan_action ctrl-f ''
  plan_action G_RIGHT "$FIXTURE_ROOT/needle-file"
  plan_action ENTER "$BATS_TEST_TMPDIR"
  run_planned_session
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT" ]
}

@test "global Right on a disappeared result is a no-op" {
  export FZD_GLOBAL_BACKEND=cache
  plan_action ctrl-f ''
  plan_action G_RIGHT "$FIXTURE_ROOT/missing"
  plan_action ENTER "$BATS_TEST_TMPDIR"
  run_planned_session
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT" ]
}

@test "live overlay Right enters a directory with the existing controls" {
  mkdir -p "$FIXTURE_ROOT/needle-dir"
  plan_action ctrl-f ''
  plan_action G_RIGHT "$FIXTURE_ROOT/needle-dir"
  plan_action ENTER "$FIXTURE_ROOT"
  run_planned_session
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT/needle-dir" ]
}

@test "global Left retains its existing overlay-cancel behavior" {
  export FZD_GLOBAL_BACKEND=cache
  mkdir -p "$FIXTURE_ROOT/needle-dir"
  plan_action ctrl-f ''
  plan_action G_LEFT "$FIXTURE_ROOT/needle-dir"
  plan_action ENTER "$BATS_TEST_TMPDIR"
  run_planned_session
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT" ]
}

@test "local Right on a file does not terminate FZD" {
  printf text >"$FIXTURE_ROOT/needle-file"
  plan_action RIGHT "$FIXTURE_ROOT/needle-file"
  plan_action ENTER "$BATS_TEST_TMPDIR"
  run_planned_session
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT" ]
}

@test "Left restores the child directory selection" {
  mkdir -p "$FIXTURE_ROOT/aaa" "$FIXTURE_ROOT/zzz"
  plan_action RIGHT "$FIXTURE_ROOT/zzz"
  plan_action LEFT "$FIXTURE_ROOT"
  plan_action ENTER "$BATS_TEST_TMPDIR"
  run_planned_session
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT" ]
  run grep -F 'start:pos(3),load:pos(3)' "$FZD_STUB_FZF_LOG"
  [ "$status" -eq 0 ]
}

@test "Enter on the parent row preserves the current-directory shortcut" {
  plan_action ENTER "$BATS_TEST_TMPDIR"
  run_planned_session
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT" ]
}

@test "Esc exits with 130 and no directory output" {
  run_planned_session
  [ "$status" -eq 130 ]
  [ -z "$output" ]
}
