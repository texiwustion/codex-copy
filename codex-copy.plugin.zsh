# codex-copy: copy readable Codex CLI conversations from local session JSONL.
# Copyright 2026 Rayn
# SPDX-License-Identifier: Apache-2.0

_codex_copy_usage() {
  cat <<'EOF'
Usage: codex-copy [SESSION_INDEX] [options]

Session selection:
  codex-copy                  Copy the latest session for current directory
  codex-copy --last           Copy the latest session for current directory
  codex-copy 2                Copy the second most recent session for current directory
  codex-copy --session ID     Copy session by full id or unambiguous prefix
  codex-copy --list           List recent sessions for current directory
  codex-copy --global         Search all sessions instead of current directory

Message selection:
  --user                      Copy only user messages
  --assistant                 Copy only assistant messages
  --turn N                    Copy turn N
  --from N --to M             Copy inclusive turn range

Other:
  --help                      Show this help

Environment:
  CODEX_HOME                  Defaults to ~/.codex
  CODEX_COPY_CLIPBOARD=stdout Print instead of copying, useful for tests
EOF
}

_codex_copy_sessions_root() {
  print -r -- "${CODEX_HOME:-$HOME/.codex}/sessions"
}

_codex_copy_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    print -u2 "codex-copy: jq is required"
    return 1
  fi
}

_codex_copy_session_id() {
  jq -r 'select(.type=="session_meta") | .payload.id // empty' "$1" 2>/dev/null | head -n 1
}

_codex_copy_session_cwd() {
  jq -r 'select(.type=="session_meta") | .payload.cwd // empty' "$1" 2>/dev/null | head -n 1
}

_codex_copy_find_sessions() {
  emulate -L zsh
  setopt nullglob
  local scope_cwd="$1"
  local root="$(_codex_copy_sessions_root)"
  local -a files filtered
  local file session_cwd
  [[ -d "$root" ]] || return 0
  files=("$root"/**/*.jsonl(.om))

  if [[ -n "$scope_cwd" ]]; then
    for file in "${files[@]}"; do
      session_cwd="$(_codex_copy_session_cwd "$file")"
      [[ "$session_cwd" == "$scope_cwd" ]] && filtered+=("$file")
    done
    files=("${filtered[@]}")
  fi

  (( ${#files[@]} == 0 )) || print -rl -- "${files[@]}"
}

_codex_copy_list_sessions() {
  local scope_cwd="$1"
  local i=1 file id cwd
  _codex_copy_find_sessions "$scope_cwd" | while IFS= read -r file; do
    id="$(_codex_copy_session_id "$file")"
    cwd="$(_codex_copy_session_cwd "$file")"
    [[ -n "$id" ]] || id="<unknown>"
    printf "%d\t%s\t%s\t%s\n" "$i" "$id" "$cwd" "$file"
    i=$((i + 1))
  done
}

_codex_copy_resolve_session_by_index() {
  local index="$1" scope_cwd="$2" file
  if ! [[ "$index" == <-> ]] || (( index < 1 )); then
    print -u2 "codex-copy: recent session index must be >= 1"
    return 2
  fi

  file="$(_codex_copy_find_sessions "$scope_cwd" | sed -n "${index}p")"
  if [[ -z "$file" ]]; then
    if [[ -n "$scope_cwd" ]]; then
      print -u2 "codex-copy: no Codex session found for current directory index $index"
      print -u2 "codex-copy: use --global to search all sessions"
    else
      print -u2 "codex-copy: no Codex session found for index $index"
    fi
    return 1
  fi

  print -r -- "$file"
}

_codex_copy_resolve_session_by_id() {
  local query="$1" scope_cwd="$2" file id
  local -a matches

  while IFS= read -r file; do
    id="$(_codex_copy_session_id "$file")"
    if [[ "$id" == "$query" || "$id" == "$query"* ]]; then
      matches+=("$file")
    fi
  done < <(_codex_copy_find_sessions "$scope_cwd")

  if (( ${#matches[@]} == 0 )); then
    if [[ -n "$scope_cwd" ]]; then
      print -u2 "codex-copy: no current-directory session matched id prefix: $query"
      print -u2 "codex-copy: use --global --session $query to search all sessions"
    else
      print -u2 "codex-copy: no session matched id prefix: $query"
    fi
    return 1
  fi

  if (( ${#matches[@]} > 1 )); then
    print -u2 "codex-copy: Multiple sessions matched id prefix: $query"
    for file in "${matches[@]}"; do
      id="$(_codex_copy_session_id "$file")"
      print -u2 "  $id  $file"
    done
    return 1
  fi

  print -r -- "${matches[1]}"
}

_codex_copy_render_session() {
  local file="$1" role_filter="$2" from_turn="$3" to_turn="$4"

  jq -r -s \
    --arg role_filter "$role_filter" \
    --argjson from_turn "$from_turn" \
    --argjson to_turn "$to_turn" '
      def resolved_turn($turn; $max_turn):
        if $turn < 0 then
          ($max_turn + $turn + 1)
        else
          $turn
        end;

      reduce .[] as $row (
        {turn: 0, out: []};
        if ($row.type == "event_msg" and $row.payload.type == "user_message") then
          .turn += 1
          | .out += [{turn: .turn, role: "user", text: ($row.payload.message // "")}]
        elif ($row.type == "event_msg" and $row.payload.type == "agent_message") then
          .out += [{turn: .turn, role: "assistant", text: ($row.payload.message // "")}]
        else
          .
        end
      )
      | . as $state
      | (resolved_turn($from_turn; $state.turn)) as $resolved_from
      | (resolved_turn($to_turn; $state.turn)) as $resolved_to
      | $state.out[]
      | select($role_filter == "both" or .role == $role_filter)
      | select(.turn >= $resolved_from and .turn <= $resolved_to)
      | if .role == "user" then
          "## User\n\n" + .text + "\n"
        else
          "## Codex\n\n" + .text + "\n"
        end
    ' "$file"
}

_codex_copy_deliver() {
  local content="$1"

  if [[ "${CODEX_COPY_CLIPBOARD:-}" == "stdout" ]]; then
    print -r -- "$content"
    return 0
  fi

  if command -v pbcopy >/dev/null 2>&1; then
    print -rn -- "$content" | pbcopy
    return 0
  fi

  if command -v wl-copy >/dev/null 2>&1; then
    print -rn -- "$content" | wl-copy
    return 0
  fi

  if command -v xclip >/dev/null 2>&1; then
    print -rn -- "$content" | xclip -selection clipboard
    return 0
  fi

  if command -v xsel >/dev/null 2>&1; then
    print -rn -- "$content" | xsel --clipboard --input
    return 0
  fi

  print -u2 "codex-copy: no clipboard command found; printed to stdout"
  print -r -- "$content"
}

codex-copy() {
  emulate -L zsh
  local selector="index" selector_value="1"
  local role_filter="both"
  local from_turn="1" to_turn="999999"
  local list_sessions=0
  local global_scope=0
  local arg

  while (( $# > 0 )); do
    arg="$1"
    case "$arg" in
      --help|-h)
        _codex_copy_usage
        return 0
        ;;
      --list)
        list_sessions=1
        shift
        ;;
      --global)
        global_scope=1
        shift
        ;;
      --last)
        selector="index"
        selector_value="1"
        shift
        ;;
      --session)
        if (( $# < 2 )); then
          print -u2 "codex-copy: --session requires an id"
          return 2
        fi
        selector="id"
        selector_value="$2"
        shift 2
        ;;
      --user)
        if [[ "$role_filter" == "assistant" ]]; then
          print -u2 "codex-copy: --user and --assistant are mutually exclusive"
          return 2
        fi
        role_filter="user"
        shift
        ;;
      --assistant)
        if [[ "$role_filter" == "user" ]]; then
          print -u2 "codex-copy: --user and --assistant are mutually exclusive"
          return 2
        fi
        role_filter="assistant"
        shift
        ;;
      --turn)
        if (( $# < 2 )) || ! [[ "$2" =~ '^-?[0-9]+$' ]] || (( $2 == 0 )); then
          print -u2 "codex-copy: --turn requires a nonzero integer"
          return 2
        fi
        from_turn="$2"
        to_turn="$2"
        shift 2
        ;;
      --from)
        if (( $# < 2 )) || ! [[ "$2" == <-> ]] || (( $2 < 1 )); then
          print -u2 "codex-copy: --from requires a positive number"
          return 2
        fi
        from_turn="$2"
        shift 2
        ;;
      --to)
        if (( $# < 2 )) || ! [[ "$2" == <-> ]] || (( $2 < 1 )); then
          print -u2 "codex-copy: --to requires a positive number"
          return 2
        fi
        to_turn="$2"
        shift 2
        ;;
      <->)
        selector="index"
        selector_value="$arg"
        shift
        ;;
      *)
        print -u2 "codex-copy: unknown argument: $arg"
        _codex_copy_usage >&2
        return 2
        ;;
    esac
  done

  _codex_copy_require_jq || return $?

  local scope_cwd="$PWD"
  (( global_scope )) && scope_cwd=""

  if (( list_sessions )); then
    _codex_copy_list_sessions "$scope_cwd"
    return 0
  fi

  if (( from_turn > to_turn )); then
    print -u2 "codex-copy: --from must be <= --to"
    return 2
  fi

  local file id content
  if [[ "$selector" == "id" ]]; then
    file="$(_codex_copy_resolve_session_by_id "$selector_value" "$scope_cwd")" || return $?
  else
    file="$(_codex_copy_resolve_session_by_index "$selector_value" "$scope_cwd")" || return $?
  fi

  content="$(_codex_copy_render_session "$file" "$role_filter" "$from_turn" "$to_turn")"
  if [[ -z "$content" ]]; then
    print -u2 "codex-copy: no matching messages found"
    return 1
  fi

  _codex_copy_deliver "$content"
}
