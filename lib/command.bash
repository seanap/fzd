# shellcheck shell=bash
# Split conventional editor arguments without evaluating expansions or shell code.
# EDITOR takes precedence over VISUAL, retaining FZD's established behavior.
_fzd_command_parse() {
  local input=$1 char next state=plain word='' started=0 index
  FZD_COMMAND=()
  if command -v -- "$input" >/dev/null 2>&1; then
    FZD_COMMAND=("$input")
    return 0
  fi
  for ((index = 0; index < ${#input}; index++)); do
    char=${input:index:1}
    case $state in
    single)
      if [[ $char == "'" ]]; then state=plain; else word+=$char; fi
      ;;
    double)
      case $char in
      '"') state=plain ;;
      '$' | '`') return 1 ;;
      \\)
        ((index += 1))
        next=${input:index:1}
        [[ -n $next ]] || return 1
        case $next in '"' | '$' | '`' | \\) word+=$next ;; *) word+="\\$next" ;; esac
        ;;
      *) word+=$char ;;
      esac
      ;;
    plain)
      case $char in
      "'")
        state=single
        started=1
        ;;
      '"')
        state=double
        started=1
        ;;
      \\)
        ((index += 1))
        next=${input:index:1}
        [[ -n $next ]] || return 1
        word+=$next
        started=1
        ;;
      ' ' | $'\t' | $'\n')
        if ((started)); then
          FZD_COMMAND+=("$word")
          word=''
          started=0
        fi
        ;;
      '$' | '`' | ';' | '|' | '&' | '<' | '>' | '(' | ')') return 1 ;;
      *)
        word+=$char
        started=1
        ;;
      esac
      ;;
    esac
  done
  [[ $state == plain ]] || return 1
  if ((started)); then FZD_COMMAND+=("$word"); fi
  ((${#FZD_COMMAND[@]})) && [[ -n ${FZD_COMMAND[0]} ]]
}

_fzd_editor_command() {
  if _fzd_command_parse "${EDITOR:-${VISUAL:-micro}}" && command -v -- "${FZD_COMMAND[0]}" >/dev/null 2>&1; then return 0; fi
  FZD_COMMAND=(micro)
  command -v micro >/dev/null 2>&1
}
