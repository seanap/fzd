#!/usr/bin/env bats
load helpers/common
setup() {
  local host_path=$PATH
  setup_fixture
  FZD_NATIVE_PYTHON=$(PATH=$host_path command -v python3 || true)
  [[ -n $FZD_NATIVE_PYTHON ]] || skip 'optional formatter requires Python 3'
  export FZD_NATIVE_PYTHON FZD_PYTHON_MARKER="$BATS_TEST_TMPDIR/python-called"
}

@test "optional formatter preserves the Bash snapshot bytes for unusual names links exclusions and caps" {
  use_fd_stub
  local name path cap paths=()
  for name in plain "single'quote" '$(touch SHOULD_NOT_EXIST)' 'back\slash' 'é-雪' $'tab\tname' $'line\nlast\n' $'escape\033name' $'bad-byte-\200\377' $'control\001\177'; do
    path="$FIXTURE_ROOT/$name"
    printf text >"$path"
    paths+=("$path")
  done
  mkdir -p "$FIXTURE_ROOT/dir" "$FIXTURE_ROOT/.git" "$FIXTURE_ROOT/proc/sub"
  touch "$FIXTURE_ROOT/.git/excluded" "$FIXTURE_ROOT/proc/sub/excluded"
  ln -s "$FIXTURE_ROOT/plain" "$FIXTURE_ROOT/link"
  ln -s "$FIXTURE_ROOT/missing" "$FIXTURE_ROOT/dangling"
  paths+=("$FIXTURE_ROOT/dir/" "$FIXTURE_ROOT/link" "$FIXTURE_ROOT/dangling" "$FIXTURE_ROOT/missing" "$FIXTURE_ROOT/.git/excluded" "$FIXTURE_ROOT/proc/sub/excluded" "$FIXTURE_ROOT-sibling/outside")
  set_results "${paths[@]}"
  export FZD_COLOR_DIR='#123456' FZD_COLOR_FILE='#abcdef' FZD_GLOBAL_XEXCLUDES='proc/*'
  for cap in 1 10 100; do
    export FZD_GLOBAL_MAXRESULTS=$cap
    rm -f "$TEST_BIN/python3"
    bash "$FZD_SCRIPT" --_global_index >"$BATS_TEST_TMPDIR/bash.records"
    cat >"$TEST_BIN/python3" <<'SH'
#!/usr/bin/env bash
touch "$FZD_PYTHON_MARKER"
exec "$FZD_NATIVE_PYTHON" "$@"
SH
    chmod +x "$TEST_BIN/python3"
    bash "$FZD_SCRIPT" --_global_index >"$BATS_TEST_TMPDIR/python.records"
    [ -e "$FZD_PYTHON_MARKER" ]
    rm "$FZD_PYTHON_MARKER"
    run cmp "$BATS_TEST_TMPDIR/bash.records" "$BATS_TEST_TMPDIR/python.records"
    [ "$status" -eq 0 ]
  done
  [ ! -e SHOULD_NOT_EXIST ]
}

@test "complex user exclusion patterns retain the Bash formatter" {
  use_fd_stub
  touch "$FIXTURE_ROOT/keep"
  set_results "$FIXTURE_ROOT/keep"
  cat >"$TEST_BIN/python3" <<'SH'
#!/usr/bin/env bash
touch "$FZD_PYTHON_MARKER"
exit 2
SH
  chmod +x "$TEST_BIN/python3"
  local exclusions
  for exclusions in '@(skip|drop)' 'literal[1]' 'escaped\*' 'literal|pipe'; do
    export FZD_EXCLUDES=$exclusions
    run --separate-stderr bash "$FZD_SCRIPT" --_global_index
    [ "$status" -eq 0 ]
    assert_record_path "$FIXTURE_ROOT/keep"
    [ ! -e "$FZD_PYTHON_MARKER" ]
    [ -z "$stderr" ]
  done
}

@test "accelerated snapshot caps safely close real fd and find producers" {
  ln -s "$FZD_NATIVE_PYTHON" "$TEST_BIN/python3"
  export FZD_GLOBAL_MAXRESULTS=1
  local i producer
  for ((i = 0; i < 2000; i++)); do printf '' >"$FIXTURE_ROOT/entry-$i"; done
  for producer in find fd; do
    if [[ $producer == fd ]]; then
      [[ -n $FZD_REAL_FD ]] || continue
      ln -s "$FZD_REAL_FD" "$TEST_BIN/fdfind"
    fi
    run --separate-stderr bash -c 'trap "" PIPE; exec bash "$1" --_global_index' _ "$FZD_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ -z "$stderr" ]
  done
}

@test "accelerated snapshots report producer failures unless the result cap was satisfied" {
  ln -s "$FZD_NATIVE_PYTHON" "$TEST_BIN/python3"
  touch "$FIXTURE_ROOT/entry"
  cat >"$TEST_BIN/fd" <<'SH'
#!/usr/bin/env bash
printf '%s\0' "$FZD_GLOBAL_PATHS/entry"
exit 1
SH
  chmod +x "$TEST_BIN/fd"
  export FZD_GLOBAL_MAXRESULTS=2
  run --separate-stderr bash "$FZD_SCRIPT" --_global_index
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'filesystem snapshot failed'* ]]
  export FZD_GLOBAL_MAXRESULTS=1
  run --separate-stderr bash "$FZD_SCRIPT" --_global_index
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ -z "$stderr" ]
}

@test "optional formatter handles NUL records split across arbitrary input blocks" {
  run "$FZD_NATIVE_PYTHON" - "$FZD_REPO/lib/global_format.py" "$FIXTURE_ROOT" <<'PY'
import base64, os, subprocess, sys
formatter, root = sys.argv[1:]
paths = []
for n in range(800):
    path = os.fsencode(root)+b'/entry-'+str(n).encode()+b'-\t\n'
    open(path, 'wb').close()
    paths.append(path)
p = subprocess.Popen([sys.executable, formatter, '1000', '', '', '', '1', root],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE)
payload = b''.join(path+b'\0' for path in paths)
# Output is larger than a pipe: communicate drains concurrently and preserves
# the 65,536-byte formatter block boundary inside the NUL record stream.
records, _ = p.communicate(payload)
assert p.returncode == 0
decoded = [base64.b64decode(line.split(b'\t',1)[0]) for line in records.splitlines()]
assert decoded == paths
PY
  [ "$status" -eq 0 ]
}
