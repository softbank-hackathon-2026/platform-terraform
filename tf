#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ENV_ROOT="$SCRIPT_DIR/env"

usage() {
  cat <<'EOF'
사용법:
  ./tf <env> <command> [args...]
  ./tf
  ./tf completion <bash|zsh>
  ./tf --help

예시:
  ./tf dev plan
  ./tf stg apply -auto-approve
  ./tf prd format -check

자동완성:
  source <(./tf completion zsh)
  source <(./tf completion bash)
EOF
}

error() {
  printf '오류: %s\n' "$*" >&2
}

require_terraform() {
  if ! command -v terraform >/dev/null 2>&1; then
    error "terraform 명령을 찾을 수 없습니다."
    return 127
  fi
}

list_envs() {
  local path

  [[ -d "$ENV_ROOT" ]] || return 1

  for path in "$ENV_ROOT"/*; do
    [[ -d "$path" && ! -L "$path" ]] || continue
    printf '%s\n' "${path##*/}"
  done | LC_ALL=C sort
}

valid_env() {
  local env_name="$1"

  case "$env_name" in
    ''|.|..|*/*) return 1 ;;
  esac

  [[ -d "$ENV_ROOT/$env_name" && ! -L "$ENV_ROOT/$env_name" ]]
}

list_commands() {
  local help_output

  help_output="$(terraform -help 2>/dev/null)" || return 1

  printf '%s\n' "$help_output" | awk '
    /^Main commands:$/ || /^All other commands:$/ { commands = 1; next }
    /^Global options/ { exit }
    commands && /^  [[:alnum:]][[:alnum:]_-]*[[:space:]]/ {
      command = $1
      if (command == "fmt") command = "format"
      if (!seen[command]++) print command
    }
  '
}

load_envs() {
  local item

  ENVIRONMENTS=()
  while IFS= read -r item; do
    [[ -n "$item" ]] && ENVIRONMENTS+=("$item")
  done < <(list_envs)
}

load_commands() {
  local item

  COMMANDS=()
  while IFS= read -r item; do
    [[ -n "$item" ]] && COMMANDS+=("$item")
  done < <(list_commands)
}

choose() {
  local prompt="$1"
  shift
  local options=("$@" "취소")
  local choice
  local PS3="$prompt"

  select choice in "${options[@]}"; do
    if [[ -z "${choice:-}" ]]; then
      error "목록의 번호를 입력하세요."
      continue
    fi

    if [[ "$choice" == "취소" ]]; then
      return 130
    fi

    SELECTED="$choice"
    return 0
  done

  return 130
}

run_terraform() {
  local env_name="$1"
  local command_name="$2"
  shift 2

  if [[ "$command_name" == "format" ]]; then
    command_name="fmt"
  fi

  exec terraform "-chdir=$ENV_ROOT/$env_name" "$command_name" "$@"
}

run_tui() {
  local env_name command_name

  require_terraform || return $?

  load_envs
  if [[ ${#ENVIRONMENTS[@]} -eq 0 ]]; then
    error "env 아래에 실행할 환경이 없습니다."
    return 1
  fi

  printf '환경을 선택하세요.\n' >&2
  if ! choose '환경 번호: ' "${ENVIRONMENTS[@]}"; then
    printf '취소했습니다.\n' >&2
    return 130
  fi
  env_name="$SELECTED"

  load_commands
  if [[ ${#COMMANDS[@]} -eq 0 ]]; then
    error "Terraform 명령 목록을 가져올 수 없습니다."
    return 1
  fi

  printf 'Terraform 명령을 선택하세요.\n' >&2
  if ! choose '명령 번호: ' "${COMMANDS[@]}"; then
    printf '취소했습니다.\n' >&2
    return 130
  fi
  command_name="$SELECTED"

  printf '실행: ./tf %s %s\n' "$env_name" "$command_name" >&2
  run_terraform "$env_name" "$command_name"
}

print_bash_completion() {
  cat <<'EOF'
_tf_repo_completion() {
  local current candidate command_path

  current="${COMP_WORDS[COMP_CWORD]}"
  command_path="${COMP_WORDS[0]}"
  COMPREPLY=()

  case "$COMP_CWORD" in
    1)
      while IFS= read -r candidate; do
        [[ "$candidate" == "$current"* ]] && COMPREPLY+=("$candidate")
      done < <("$command_path" __complete envs)
      ;;
    2)
      while IFS= read -r candidate; do
        [[ "$candidate" == "$current"* ]] && COMPREPLY+=("$candidate")
      done < <("$command_path" __complete commands)
      ;;
  esac
}

complete -o default -F _tf_repo_completion ./tf
EOF
}

print_zsh_completion() {
  cat <<'EOF'
_tf_repo_completion() {
  local -a candidates

  case "$CURRENT" in
    2)
      candidates=("${(@f)$(command "${words[1]}" __complete envs)}")
      _describe 'environment' candidates
      ;;
    3)
      candidates=("${(@f)$(command "${words[1]}" __complete commands)}")
      _describe 'terraform command' candidates
      ;;
    *)
      _files
      ;;
  esac
}

if (( ! $+functions[compdef] )); then
  autoload -Uz compinit && compinit
fi
compdef _tf_repo_completion ./tf
EOF
}

complete_values() {
  case "${1:-}" in
    envs) list_envs ;;
    commands)
      command -v terraform >/dev/null 2>&1 || return 1
      list_commands
      ;;
    *) return 2 ;;
  esac
}

ENVIRONMENTS=()
COMMANDS=()
SELECTED=''

case "${1:-}" in
  '')
    run_tui
    ;;
  -h|--help|help)
    usage
    ;;
  completion)
    if [[ $# -ne 2 ]]; then
      error "completion 뒤에 bash 또는 zsh를 지정하세요."
      exit 2
    fi
    case "$2" in
      bash) print_bash_completion ;;
      zsh) print_zsh_completion ;;
      *)
        error "지원하지 않는 셸입니다: $2"
        exit 2
        ;;
    esac
    ;;
  __complete)
    complete_values "${2:-}"
    ;;
  *)
    if [[ $# -lt 2 ]]; then
      error "Terraform 명령이 필요합니다."
      usage >&2
      exit 2
    fi

    env_name="$1"
    command_name="$2"
    shift 2

    if ! valid_env "$env_name"; then
      error "알 수 없는 환경입니다: $env_name"
      printf '사용 가능한 환경:\n' >&2
      list_envs | sed 's/^/  /' >&2
      exit 2
    fi

    require_terraform || exit $?
    run_terraform "$env_name" "$command_name" "$@"
    ;;
esac
