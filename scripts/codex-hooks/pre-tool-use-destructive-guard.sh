#!/usr/bin/env bash
# Codex PreToolUse:Bash guard for irreversible shell/git operations.
# Read-only: it only inspects tool_input.command and returns allow-by-silence or
# a Codex permissionDecision=deny.
set -uo pipefail

HOOK_DIR="$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$HOOK_DIR/_common.sh"

fail_closed() {
  printf 'BLOCKED: destructive guard could not validate Codex Bash input: %s\n' "$1" >&2
  exit 2
}

deny() {
  local reason="$1"

  if codex_hooks_emit_pretool_deny "$reason"; then
    exit 0
  fi
  exit 2
}

for dependency in jq perl sed grep; do
  command -v "$dependency" >/dev/null 2>&1 ||
    fail_closed "${dependency} is unavailable"
done

HOOK_INPUT="$(cat 2>/dev/null)" ||
  fail_closed "stdin could not be read"

printf '%s' "$HOOK_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1 ||
  fail_closed "stdin is not a JSON object"

TOOL_NAME="$(
  printf '%s' "$HOOK_INPUT" |
    jq -r 'if (.tool_name | type) == "string" then .tool_name else "" end'
)" || fail_closed "tool_name could not be parsed"

# A matcher should invoke this adapter only for Bash. If it is intentionally
# reused for another tool, leave that tool untouched.
[[ "$TOOL_NAME" == "Bash" ]] || {
  [[ -n "$TOOL_NAME" ]] || fail_closed "tool_name is missing"
  exit 0
}

CMD="$(
  printf '%s' "$HOOK_INPUT" |
    jq -er '
      if (.tool_input | type) == "object"
         and (.tool_input.command | type) == "string"
         and (.tool_input.command | length) > 0
      then .tool_input.command
      else error("missing Bash command")
      end
    '
)" || fail_closed "tool_input.command is missing or invalid"

git_segments() {
  local subcommand="$1"

  SUBCOMMAND="$subcommand" perl -0777 -ne '
    my $subcommand = quotemeta($ENV{"SUBCOMMAND"});
    my $git = qr{(?:/(?:usr/(?:local/)?|opt/homebrew/)?bin/)?git};
    my $value = qr{(?:"[^"]*"|\x27[^\x27]*\x27|\S+)};
    my $global = qr{
      (?:
        -C\s+$value
        |--git-dir(?:=$value|\s+$value)
        |--work-tree(?:=$value|\s+$value)
        |-c\s+$value
        |--no-pager
        |--paginate
      )
    }x;

    while (/(?:^|[;&|]\s*|\s+)($git(?:\s+$global)*\s+$subcommand\b[^;&|]*)/g) {
      print "$1\n";
    }
  ' <<< "$CMD"
}

rm_segments() {
  perl -0777 -ne '
    my $rm = qr{(?:/(?:usr/(?:local/)?|opt/homebrew/)?bin/)?rm};
    while (/(?:^|[;&|]\s*|\s+)($rm\b[^;&|]*)/g) {
      print "$1\n";
    }
  ' <<< "$CMD"
}

# IWE safe-delete policy: recursive forced removal must go through trash.
RM_SEGMENTS="$(rm_segments)" ||
  fail_closed "rm command inspection failed"
if [[ -n "$RM_SEGMENTS" ]]; then
  if printf '%s\n' "$RM_SEGMENTS" |
      grep -qE -- '(^|[[:space:]])(-[[:alpha:]]*[rR][[:alpha:]]*|--recursive)([[:space:]]|$)' &&
    printf '%s\n' "$RM_SEGMENTS" |
      grep -qE -- '(^|[[:space:]])(-[[:alpha:]]*f[[:alpha:]]*|--force)([[:space:]]|$)'; then
    deny "rm -rf запрещён политикой безопасного удаления IWE. Используй trash для конкретных файлов или запроси явное согласование."
  fi
fi

# git push --force / -f. --force-with-lease remains allowed.
PUSH_SEGMENTS="$(git_segments push)" ||
  fail_closed "git push inspection failed"
if [[ -n "$PUSH_SEGMENTS" ]]; then
  PUSH_FORCE_SCAN="$(
    printf '%s\n' "$PUSH_SEGMENTS" |
      sed -E 's/--force-with-lease(=[^[:space:]]*)?//g'
  )" || fail_closed "git push flags could not be normalized"
  if printf '%s\n' "$PUSH_FORCE_SCAN" |
      grep -qE -- '(^|[[:space:]])(--force([[:space:]]|=|$)|-[[:alpha:]]*f[[:alpha:]]*([[:space:]]|$))'; then
    deny "git push --force запрещён. Используй --force-with-lease или согласуй операцию с владельцем."
  fi
fi

# git reset --hard.
RESET_SEGMENTS="$(git_segments reset)" ||
  fail_closed "git reset inspection failed"
if [[ -n "$RESET_SEGMENTS" ]] &&
  printf '%s\n' "$RESET_SEGMENTS" |
    grep -qE -- '(^|[[:space:]])--hard([[:space:]]|$)'; then
  deny "git reset --hard запрещён: он может удалить незакоммиченные изменения. Используй git stash или согласуй операцию."
fi

# git clean with any delete-enabling flag. This intentionally stays
# conservative even when a dry-run flag is also present.
CLEAN_SEGMENTS="$(git_segments clean)" ||
  fail_closed "git clean inspection failed"
if [[ -n "$CLEAN_SEGMENTS" ]] &&
  {
    printf '%s\n' "$CLEAN_SEGMENTS" |
      grep -qE -- '(^|[[:space:]])-[[:alpha:]]*[dfx][[:alpha:]]*([[:space:]]|$)' ||
      printf '%s\n' "$CLEAN_SEGMENTS" |
        grep -qE -- '(^|[[:space:]])--(force|dirs|ignored)([=[:space:]]|$)'
  }; then
  deny "git clean с удаляющими флагами запрещён: он может удалить неотслеживаемые файлы. Согласуй операцию с владельцем."
fi

exit 0
