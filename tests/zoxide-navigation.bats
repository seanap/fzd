#!/usr/bin/env bats
load helpers/common
setup() {
  setup_fixture
  export FZD_BIN="$TEST_BIN/fzd" FZD_ARGUMENTS="$BATS_TEST_TMPDIR/args"
  cat >"$FZD_BIN" <<'STUB'
#!/bin/bash
: >"$FZD_ARGUMENTS"
if (($#)); then printf '%s\0' "$@" >"$FZD_ARGUMENTS"; fi
exit 130
STUB
  chmod +x "$FZD_BIN"
  mkdir -p "$FIXTURE_ROOT/docker/immich" "$FIXTURE_ROOT/archive/immich-old" "$FIXTURE_ROOT/elsewhere"
}

shells() { printf '%s\n' bash "$FZD_REAL_ZSH"; }

@test "lf without arguments explores and lff always forwards one seeded global query" {
  local shell
  while IFS= read -r shell; do
    run "$shell" -ec 'source "$1/shell/integration.sh"; lf' _ "$FZD_REPO"
    [ "$status" -eq 0 ]
    [ ! -s "$FZD_ARGUMENTS" ]
    run "$shell" -ec 'source "$1/shell/integration.sh"; lff docker immich' _ "$FZD_REPO"
    [ "$status" -eq 0 ]
    run bash -c 'mapfile -d "" -t args <"$FZD_ARGUMENTS"; [[ ${#args[@]} == 2 && ${args[0]} == --global && ${args[1]} == "docker immich" ]]'
    [ "$status" -eq 0 ]
    run "$shell" -ec 'source "$1/shell/integration.sh"; lff' _ "$FZD_REPO"
    [ "$status" -eq 0 ]
    run bash -c 'mapfile -d "" -t args <"$FZD_ARGUMENTS"; [[ ${#args[@]} == 2 && ${args[1]} == "" ]]'
    [ "$status" -eq 0 ]
  done < <(shells)
}

@test "partial and multiple terms jump to upstream zoxide's highest-ranked directory" {
  zoxide add -- "$FIXTURE_ROOT/archive/immich-old" "$FIXTURE_ROOT/docker/immich" "$FIXTURE_ROOT/docker/immich"
  local shell query
  while IFS= read -r shell; do
    for query in imm 'docker imm'; do
      run "$shell" -ec 'source "$1/shell/integration.sh"; if [[ $3 == imm ]]; then lf imm; else lf docker imm; fi; [[ $PWD == "$2/docker/immich" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT" "$query"
      [ "$status" -eq 0 ]
      [ ! -e "$FZD_ARGUMENTS" ]
    done
  done < <(shells)
}

@test "unmatched and option-like keywords fall back to discovery without executing shell data" {
  local shell query='unseen $(touch FZD_BAD); --help'
  while IFS= read -r shell; do
    run "$shell" -ec 'source "$1/shell/integration.sh"; lf "$2"' _ "$FZD_REPO" "$query"
    [ "$status" -eq 0 ]
    run bash -c 'mapfile -d "" -t args <"$FZD_ARGUMENTS"; [[ ${args[0]} == --global && ${args[1]} == "$1" ]]' _ "$query"
    [ "$status" -eq 0 ]
    [ ! -e FZD_BAD ]
  done < <(shells)
}

@test "direct paths symlinks spaces trailing newlines and dash navigation preserve shell behavior" {
  local shell target="$FIXTURE_ROOT/"$'space quote\x27 λ\n\n'
  mkdir -p "$target"
  ln -s "$target" "$FIXTURE_ROOT/link"
  while IFS= read -r shell; do
    run "$shell" -ec 'source "$1/shell/integration.sh"; start=$PWD; lf -- "$2"; [[ $PWD == "$2" ]]; lf - >/dev/null; [[ $PWD == "$start" ]]; lf "$3/link"; [[ $PWD == "$3/link" ]]' _ "$FZD_REPO" "$target" "$FIXTURE_ROOT"
    [ "$status" -eq 0 ]
    [ ! -e "$FZD_ARGUMENTS" ]
  done < <(shells)
}

@test "upstream-excluded newline names fall back and ordinary direct jumps learn immediately" {
  local shell target="$FIXTURE_ROOT/"$'odd-immich\n\n'
  mkdir -p "$target"
  zoxide add -- "$target"
  while IFS= read -r shell; do
    run "$shell" -ec 'source "$1/shell/integration.sh"; lf odd-imm; lf "$2/elsewhere"; [[ $(zoxide query elsewhere) == "$2/elsewhere" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT"
    [ "$status" -eq 0 ]
    [ -s "$FZD_ARGUMENTS" ]
  done < <(shells)
}

@test "existing lff and fallback names are preserved together with their completion handlers" {
  local shell
  while IFS= read -r shell; do
    run "$shell" -ec 'lff() { printf existing; }; fzd_find() { printf alternate; }; source "$1/shell/integration.sh"; [[ $(lff) == existing && $(fzd_find) == alternate ]]' _ "$FZD_REPO"
    [ "$status" -eq 0 ]
  done < <(shells)
  run bash -ec 'lf() { :; }; complete -W custom lf; complete -W preserved lff; source "$1/shell/integration.sh"; [[ $(complete -p lf) == *custom* && $(complete -p lff) == *preserved* ]]' _ "$FZD_REPO"
  [ "$status" -eq 0 ]
  run "$FZD_REAL_ZSH" -efc 'autoload -Uz compinit; compinit -i -D; compdef _files lf; compdef _files lff; source "$1/shell/integration.sh"; [[ $_comps[lf] == _files && $_comps[lff] == _files ]]' _ "$FZD_REPO"
  [ "$status" -eq 0 ]
}

@test "missing zoxide stops shell navigation and runtime with actionable diagnostics" {
  rm "$UTILITY_BIN/zoxide"
  local shell
  while IFS= read -r shell; do
    run "$shell" -c 'source "$1/shell/integration.sh"; lf' _ "$FZD_REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *'zoxide is required'* ]]
    [ ! -e "$FZD_ARGUMENTS" ]
  done < <(shells)
  run bash "$FZD_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'zoxide is required'* ]]
}

@test "completion offers ranked leaf names multiple terms and quoted local directories" {
  zoxide add -- "$FIXTURE_ROOT/archive/immich-old" "$FIXTURE_ROOT/docker/immich" "$FIXTURE_ROOT/docker/immich"
  mkdir -p "$FIXTURE_ROOT/local space"
  run bash -ec 'source "$1/shell/integration.sh"; COMP_WORDS=(lf imm); COMP_CWORD=1; _fzd_complete; [[ ${COMPREPLY[0]} == immich && ${COMPREPLY[1]} == immich-old ]]; COMP_WORDS=(lf docker imm); COMP_CWORD=2; _fzd_complete; [[ ${COMPREPLY[*]} == immich ]]; cd "$2"; COMP_WORDS=(lff "local s"); COMP_CWORD=1; _fzd_complete; [[ ${COMPREPLY[0]} == "local space" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
}

@test "completion lists accessible learned directories only and never launches fzf" {
  zoxide add -- "$FIXTURE_ROOT/docker/immich" "$FIXTURE_ROOT/archive/immich-old"
  rm -r "$FIXTURE_ROOT/archive"
  run bash -ec 'source "$1/shell/integration.sh"; [[ $(_fzd_candidates imm) == immich ]]; [[ $(_fzd_candidates docker imm) == immich ]]' _ "$FZD_REPO"
  [ "$status" -eq 0 ]
  [ ! -e "$FZD_ARGUMENTS" ]
}

@test "Bash upstream initialization preserves scalar and array prompt commands and z/zi" {
  run bash --noprofile --norc -ec 'PROMPT_COMMAND=("printf original" "true"); z() { :; }; zi() { :; }; oldz=$(declare -f z); oldzi=$(declare -f zi); source "$1/shell/integration.sh"; PROMPT_COMMAND+=(_fzd_init_zoxide); _fzd_init_zoxide; [[ ${PROMPT_COMMAND[0]} == "printf original" && ${PROMPT_COMMAND[1]} == true && ${PROMPT_COMMAND[2]} == __zoxide_hook && ${#PROMPT_COMMAND[@]} == 3 ]]; [[ $(declare -f z) == "$oldz" && $(declare -f zi) == "$oldzi" ]]; set -o history; builtin cd "$2/docker/immich"; __zoxide_hook; [[ $(zoxide query imm) == "$PWD" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  run bash --noprofile --norc -ec 'PROMPT_COMMAND="printf original; "; source "$1/shell/integration.sh"; PROMPT_COMMAND="printf original;_fzd_init_zoxide"; _fzd_init_zoxide; [[ $PROMPT_COMMAND == "printf original;__zoxide_hook" ]]' _ "$FZD_REPO"
  [ "$status" -eq 0 ]
}

@test "existing upstream zoxide configuration wins when sourced before or after FZD" {
  local shell order
  while IFS= read -r shell; do
    for order in before after; do
      run "$shell" -ec 'if [[ $3 == before ]]; then eval "$(zoxide init "$4" --no-cmd --hook none)"; fi; source "$1/shell/integration.sh"; if [[ $3 == after ]]; then eval "$(zoxide init "$4" --no-cmd --hook none)"; fi; old=$(typeset -f __zoxide_z 2>/dev/null || true); _fzd_init_zoxide; [[ $(typeset -f __zoxide_z 2>/dev/null || true) == "$old" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT" "$order" "${shell##*/}"
      [ "$status" -eq 0 ]
    done
  done < <(shells)
}

@test "zsh upstream initialization retains chpwd hooks and key bindings and learns ordinary cd" {
  run "$FZD_REAL_ZSH" -efc 'typeset -a chpwd_functions=(custom_hook); custom_hook() { :; }; bindkey "^[[0n" self-insert; before=$(bindkey "^[[0n"); source "$1/shell/integration.sh"; precmd_functions+=(_fzd_init_zoxide); _fzd_init_zoxide; [[ ${#chpwd_functions} == 2 && $chpwd_functions[1] == custom_hook && $chpwd_functions[2] == __zoxide_hook ]]; [[ $(bindkey "^[[0n") == "$before" ]]; builtin cd "$2/docker/immich"; [[ $(zoxide query imm) == "$PWD" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
}

@test "FZD traversal and selected destinations are learned even when the explorer is cancelled" {
  export FZD_STUB_PLAN="$BATS_TEST_TMPDIR/plan"
  plan_action RIGHT "$FIXTURE_ROOT/docker"
  plan_action RIGHT "$FIXTURE_ROOT/docker/immich"
  run_planned_session
  [ "$status" -eq 130 ]
  run zoxide query imm
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT/docker/immich" ]
  export FZD_STUB_ACTION=G_ENTER FZD_STUB_SELECTION="$FIXTURE_ROOT/elsewhere"
  unset FZD_STUB_PLAN
  run bash "$FZD_SCRIPT" --global elsewhere
  [ "$status" -eq 0 ]
  [ "$output" = "$FIXTURE_ROOT/elsewhere" ]
  run zoxide query elsewhere
  [ "$output" = "$FIXTURE_ROOT/elsewhere" ]
}

@test "seeded discovery preserves literal queries without duplicate startup reloads" {
  export FZD_STUB_FZF_LOG="$BATS_TEST_TMPDIR/fzf-args"
  local backend
  for backend in live locate cache; do
    export FZD_GLOBAL_BACKEND=$backend
    : >"$FZD_STUB_FZF_LOG"
    run bash "$FZD_SCRIPT" --global 'imm $(touch BAD)'
    [ "$status" -eq 130 ]
    run cat "$FZD_STUB_FZF_LOG"
    [[ "$output" == *'--query=imm $(touch BAD)'* ]]
    [[ "$output" != *'start:reload:'* ]]
    [ ! -e BAD ]
  done
}

@test "zoxide honors user database exclusions and symlink preferences without a second database" {
  export _ZO_EXCLUDE_DIRS="$FIXTURE_ROOT/elsewhere"
  run bash -ec 'source "$1/shell/integration.sh"; lf "$2/elsewhere"; ! zoxide query elsewhere; lf "$2/docker/immich"; [[ $(zoxide query imm) == "$PWD" ]]' _ "$FZD_REPO" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  [ -f "$_ZO_DATA_DIR/db.zo" ]
}
