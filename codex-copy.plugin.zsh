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
  codex-copy --reindex        Rebuild the session cache
  codex-copy --no-cache       Scan sessions without reading or writing cache

Message selection:
  --user                      Copy only user messages
  --assistant                 Copy only assistant messages
  --turn N                    Copy turn N
  --from N --to M             Copy inclusive turn range
  --with-tools                Include tool output blocks
  -o PATH, --output PATH      Write Markdown to PATH instead of copying

Other:
  --help                      Show this help

Environment:
  CODEX_HOME                  Defaults to ~/.codex
  CODEX_COPY_CACHE_FILE       Defaults to /tmp/codex-copy-index-$USER.tsv
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

_codex_copy_cache_file() {
  print -r -- "${CODEX_COPY_CACHE_FILE:-/tmp/codex-copy-index-${USER:-user}.tsv}"
}

_codex_copy_file_mtime() {
  if stat -f %m "$1" >/dev/null 2>&1; then
    stat -f %m "$1"
  else
    stat -c %Y "$1"
  fi
}

_codex_copy_now_epoch() {
  date +%s
}

_codex_copy_scan_index() {
  emulate -L zsh
  setopt nullglob
  local root="$(_codex_copy_sessions_root)"
  local -a files
  local file mtime id cwd
  [[ -d "$root" ]] || return 0
  files=("$root"/**/*.jsonl(.om))
  for file in "${files[@]}"; do
    mtime="$(_codex_copy_file_mtime "$file")"
    id="$(_codex_copy_session_id "$file")"
    cwd="$(_codex_copy_session_cwd "$file")"
    [[ -n "$id" ]] || id="<unknown>"
    printf "%s\t%s\t%s\t%s\n" "$mtime" "$id" "$cwd" "$file"
  done
}

_codex_copy_rebuild_cache() {
  local cache_file="$(_codex_copy_cache_file)"
  local cache_dir="${cache_file:h}"
  local tmp_file
  mkdir -p "$cache_dir" 2>/dev/null || return 1
  tmp_file="$(mktemp "${cache_file}.XXXXXX")" || return 1
  _codex_copy_scan_index > "$tmp_file"
  chmod 600 "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$cache_file"
}

_codex_copy_cache_is_fresh() {
  local cache_file="$(_codex_copy_cache_file)"
  local max_age="${CODEX_COPY_CACHE_TTL:-600}"
  local now cache_mtime
  [[ -s "$cache_file" ]] || return 1
  now="$(_codex_copy_now_epoch)"
  cache_mtime="$(_codex_copy_file_mtime "$cache_file")"
  (( now - cache_mtime <= max_age ))
}

_codex_copy_index_rows() {
  local use_cache="$1" force_reindex="$2"
  local cache_file="$(_codex_copy_cache_file)"

  if (( ! use_cache )); then
    _codex_copy_scan_index
    return
  fi

  if (( force_reindex )) || ! _codex_copy_cache_is_fresh; then
    _codex_copy_rebuild_cache || return $?
  fi

  [[ -f "$cache_file" ]] && cat "$cache_file"
}

_codex_copy_find_sessions() {
  local scope_cwd="$1" use_cache="$2" force_reindex="$3"
  local -a files filtered
  local row mtime id session_cwd file

  if [[ -n "$scope_cwd" ]]; then
    while IFS=$'\t' read -r mtime id session_cwd file; do
      [[ "$session_cwd" == "$scope_cwd" ]] && filtered+=("$file")
    done < <(_codex_copy_index_rows "$use_cache" "$force_reindex")
    files=("${filtered[@]}")
  else
    while IFS=$'\t' read -r mtime id session_cwd file; do
      [[ -n "$file" ]] && files+=("$file")
    done < <(_codex_copy_index_rows "$use_cache" "$force_reindex")
  fi

  (( ${#files[@]} == 0 )) || print -rl -- "${files[@]}"
}

_codex_copy_list_sessions() {
  local scope_cwd="$1" use_cache="$2" force_reindex="$3"
  local i=1 row mtime id cwd file
  _codex_copy_index_rows "$use_cache" "$force_reindex" | while IFS=$'\t' read -r mtime id cwd file; do
    [[ -n "$scope_cwd" && "$cwd" != "$scope_cwd" ]] && continue
    [[ -n "$id" ]] || id="<unknown>"
    printf "%d\t%s\t%s\t%s\n" "$i" "$id" "$cwd" "$file"
    i=$((i + 1))
  done
}

_codex_copy_resolve_session_by_index() {
  local index="$1" scope_cwd="$2" use_cache="$3" force_reindex="$4" file
  if ! [[ "$index" == <-> ]] || (( index < 1 )); then
    print -u2 "codex-copy: recent session index must be >= 1"
    return 2
  fi

  file="$(_codex_copy_find_sessions "$scope_cwd" "$use_cache" "$force_reindex" | sed -n "${index}p")"
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
  local query="$1" scope_cwd="$2" use_cache="$3" force_reindex="$4" file id
  local -a matches

  while IFS= read -r file; do
    id="$(_codex_copy_session_id "$file")"
    if [[ "$id" == "$query" || "$id" == "$query"* ]]; then
      matches+=("$file")
    fi
  done < <(_codex_copy_find_sessions "$scope_cwd" "$use_cache" "$force_reindex")

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
  local file="$1" role_filter="$2" from_turn="$3" to_turn="$4" include_tools="$5"

  jq -r -s \
    --arg role_filter "$role_filter" \
    --argjson from_turn "$from_turn" \
    --argjson to_turn "$to_turn" \
    --argjson include_tools "$include_tools" '
      def resolved_turn($turn; $max_turn):
        if $turn < 0 then
          ($max_turn + $turn + 1)
        else
          $turn
        end;

      def command_text($payload):
        if ($payload.command | type) == "array" then
          $payload.command | join(" ")
        elif $payload.command == null then
          ""
        else
          $payload.command | tostring
        end;

      def output_text($payload):
        if ($payload.aggregated_output // "") != "" then
          $payload.aggregated_output
        elif ($payload.formatted_output // "") != "" then
          $payload.formatted_output
        elif ($payload.stdout // "") != "" or ($payload.stderr // "") != "" then
          (($payload.stdout // "") + (if ($payload.stderr // "") != "" then "\n" + $payload.stderr else "" end))
        else
          ""
        end;

      def tool_item($row; $turn):
        ($row.payload) as $payload
        | (command_text($payload)) as $command
        | (output_text($payload)) as $output
        | {
            turn: $turn,
            role: "tool",
            text: (
              "## Tool: " + ($payload.type // "tool") + "\n\n" +
              (if $command != "" then "Command:\n```text\n" + $command + "\n```\n\n" else "" end) +
              (if ($payload.exit_code // null) != null then "Exit code: " + ($payload.exit_code | tostring) + "\n\n" else "" end) +
              (if $output != "" then "Output:\n```text\n" + $output + "\n```\n" else "" end)
            )
          };

      reduce .[] as $row (
        {turn: 0, out: []};
        if ($row.type == "event_msg" and $row.payload.type == "user_message") then
          .turn += 1
          | .out += [{turn: .turn, role: "user", text: ($row.payload.message // "")}]
        elif ($row.type == "event_msg" and $row.payload.type == "agent_message") then
          .out += [{turn: .turn, role: "assistant", text: ($row.payload.message // "")}]
        elif (
          $include_tools == 1
          and $row.type == "event_msg"
          and .turn > 0
          and ($row.payload.type | test("tool|exec|command|function"; "i"))
          and ($row.payload.type != "token_count")
        ) then
          .out += [tool_item($row; .turn)]
        else
          .
        end
      )
      | . as $state
      | (resolved_turn($from_turn; $state.turn)) as $resolved_from
      | (resolved_turn($to_turn; $state.turn)) as $resolved_to
      | $state.out[]
      | select(
          $role_filter == "both"
          or .role == $role_filter
          or (.role == "tool" and $role_filter == "assistant")
        )
      | select(.turn >= $resolved_from and .turn <= $resolved_to)
      | if .role == "user" then
          "## User\n\n" + .text + "\n"
        elif .role == "assistant" then
          "## Codex\n\n" + .text + "\n"
        else
          .text + "\n"
        end
    ' "$file"
}

_codex_copy_deliver() {
  local content="$1" output_file="$2"

  if [[ -n "$output_file" ]]; then
    if [[ "$output_file" == "-" ]]; then
      print -r -- "$content"
      return 0
    fi
    local output_dir="${output_file:h}"
    mkdir -p "$output_dir" 2>/dev/null || return 1
    print -rn -- "$content" > "$output_file"
    return $?
  fi

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
  local use_cache=1
  local force_reindex=0
  local include_tools=0
  local output_file=""
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
      --reindex)
        force_reindex=1
        shift
        ;;
      --no-cache)
        use_cache=0
        shift
        ;;
      --with-tools)
        include_tools=1
        shift
        ;;
      -o|--output)
        if (( $# < 2 )); then
          print -u2 "codex-copy: $arg requires a path"
          return 2
        fi
        output_file="$2"
        shift 2
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
    _codex_copy_list_sessions "$scope_cwd" "$use_cache" "$force_reindex"
    return 0
  fi

  if (( from_turn > to_turn )); then
    print -u2 "codex-copy: --from must be <= --to"
    return 2
  fi

  local file id content
  if [[ "$selector" == "id" ]]; then
    file="$(_codex_copy_resolve_session_by_id "$selector_value" "$scope_cwd" "$use_cache" "$force_reindex")" || return $?
  else
    file="$(_codex_copy_resolve_session_by_index "$selector_value" "$scope_cwd" "$use_cache" "$force_reindex")" || return $?
  fi

  content="$(_codex_copy_render_session "$file" "$role_filter" "$from_turn" "$to_turn" "$include_tools")"
  if [[ -z "$content" ]]; then
    print -u2 "codex-copy: no matching messages found"
    return 1
  fi

  _codex_copy_deliver "$content" "$output_file"
}
