#!/usr/bin/env bash
# Warm Bash command-dispatch measurements; private upstream zoxide database.
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
output=${1:?fresh result directory required}
[[ ! -e $output ]] || exit 2
mkdir -p "$output"
python3 - "$repo" "$output" <<'PY'
import json, os, pathlib, statistics, subprocess, sys, tempfile, time
repo, output = map(pathlib.Path, sys.argv[1:])
with tempfile.TemporaryDirectory(prefix='fzd-navigation-', dir=repo / '.test-work') as private:
    private = pathlib.Path(private)
    target = private / 'docker' / 'immich'
    target.mkdir(parents=True)
    env = dict(os.environ, HOME=str(private), _ZO_DATA_DIR=str(private / 'zoxide'),
               FZD_BENCH_INTEGRATION=str(repo / 'shell/integration.sh'),
               FZD_BENCH_TARGET=str(target), BASH_ENV='/dev/null')
    for name in ('_ZO_EXCLUDE_DIRS', '_ZO_RESOLVE_SYMLINKS', '_ZO_MAXAGE'):
        env.pop(name, None)
    subprocess.run(['zoxide', 'add', '--', str(target)], env=env, check=True)
    commands = {
        'upstream_query_cd_add': 'builtin cd -- "$(zoxide query -- docker imm)"; zoxide add -- "$PWD"',
        'lf_partial_jump': 'lf docker imm',
    }
    results = {}
    # Alternate order across groups; amortize one-time shell/source startup.
    count = 150
    for group in range(7):
        for name in list(commands)[::1 if group % 2 == 0 else -1]:
            script = ('set -e; source "$FZD_BENCH_INTEGRATION"; '
                      'for ((i=0;i<150;i++)); do ' + commands[name] +
                      '; [[ $PWD == "$FZD_BENCH_TARGET" ]]; done')
            start = time.perf_counter_ns()
            subprocess.run(['bash', '--noprofile', '--norc', '-c', script],
                           env=env, check=True, stdout=subprocess.DEVNULL)
            elapsed = (time.perf_counter_ns() - start) / count / 1e6
            results.setdefault(name, []).append(elapsed)
    record = {'clock': 'Python perf_counter_ns (monotonic)', 'iterations_per_group': count,
              'groups': 7, 'includes': 'query, cd, learning; shell/source startup amortized',
              'zoxide': subprocess.check_output(['zoxide', '--version'], text=True).strip(),
              'results': {name: {'median_ms': statistics.median(times), 'groups_ms': times}
                          for name, times in results.items()}}
    (output / 'direct-jumps.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2))
PY
