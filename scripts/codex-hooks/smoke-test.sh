#!/usr/bin/env bash
# Local, non-mutating smoke tests for the minimal Codex hook adapters.
set -euo pipefail

HOOK_DIR="$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(CDPATH= cd -P -- "$HOOK_DIR/../.." && pwd)"
FIXTURES_DIR="$HOOK_DIR/fixtures"

pass_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf 'ok %d - %s\n' "$pass_count" "$1"
}

fail() {
  printf 'not ok %d - %s\n' "$((pass_count + 1))" "$1" >&2
  exit 1
}

assert_deny() {
  local fixture="$1" expected_fragment="$2" label="$3" output

  output="$(
    WORKSPACE_DIR="$WORKSPACE_ROOT" \
      /bin/bash "$HOOK_DIR/pre-tool-use-destructive-guard.sh" \
      <"$FIXTURES_DIR/$fixture"
  )" || fail "$label (unexpected exit)"

  printf '%s' "$output" |
    jq -e \
      --arg expected "$expected_fragment" \
      '
        .hookSpecificOutput.hookEventName == "PreToolUse"
        and .hookSpecificOutput.permissionDecision == "deny"
        and (.hookSpecificOutput.permissionDecisionReason | contains($expected))
      ' >/dev/null || fail "$label (invalid deny payload)"

  pass "$label"
}

command -v jq >/dev/null 2>&1 || fail "jq is required for smoke tests"

for script in \
  "$HOOK_DIR/_common.sh" \
  "$HOOK_DIR/user-prompt-wp-reminder.sh" \
  "$HOOK_DIR/pre-tool-use-destructive-guard.sh" \
  "$HOOK_DIR/session-start-trash-check.sh" \
  "$HOOK_DIR/smoke-test.sh"; do
  /bin/bash -n "$script" || fail "bash -n: $(basename "$script")"
done
pass "all hook scripts pass bash -n"

fixtures_before="$(
  cksum \
  "$FIXTURES_DIR/user-prompt-generic.json" \
  "$FIXTURES_DIR/user-prompt-postmit.json" \
    "$FIXTURES_DIR/user-prompt-day-open.json" \
    "$FIXTURES_DIR/pre-tool-safe.json" \
    "$FIXTURES_DIR/pre-tool-force-push.json" \
    "$FIXTURES_DIR/pre-tool-force-push-short.json" \
    "$FIXTURES_DIR/pre-tool-reset-hard.json" \
    "$FIXTURES_DIR/pre-tool-clean.json" \
    "$FIXTURES_DIR/pre-tool-rm-rf.json" \
    "$FIXTURES_DIR/pre-tool-invalid.json" \
    "$FIXTURES_DIR/session-start.json"
)"

generic_output="$(
  WORKSPACE_DIR="$WORKSPACE_ROOT" \
    /bin/bash "$HOOK_DIR/user-prompt-wp-reminder.sh" \
    <"$FIXTURES_DIR/user-prompt-generic.json"
)"
printf '%s' "$generic_output" |
  jq -e \
    --arg workspace "$WORKSPACE_ROOT" \
    '
      .hookSpecificOutput.hookEventName == "UserPromptSubmit"
      and (.hookSpecificOutput.additionalContext | contains("WP GATE"))
      and (.hookSpecificOutput.additionalContext | contains($workspace + "/memory/protocol-open.md"))
    ' >/dev/null || fail "UserPromptSubmit generic WP context"
pass "UserPromptSubmit emits Codex WP additionalContext"

postmit_output="$(
  WORKSPACE_DIR="$WORKSPACE_ROOT" \
    /bin/bash "$HOOK_DIR/user-prompt-wp-reminder.sh" \
    <"$FIXTURES_DIR/user-prompt-postmit.json"
)"
printf '%s' "$postmit_output" |
  jq -e \
    --arg skill "$WORKSPACE_ROOT/.agents/skills/postmit/SKILL.md" \
    '
      .hookSpecificOutput.hookEventName == "UserPromptSubmit"
      and (.hookSpecificOutput.additionalContext | contains("IWE SKILL"))
      and (.hookSpecificOutput.additionalContext | contains("/postmit"))
      and (.hookSpecificOutput.additionalContext | contains($skill))
    ' >/dev/null || fail "UserPromptSubmit routes /postmit to its skill"
pass "UserPromptSubmit routes /postmit to its skill"

day_open_output="$(
  WORKSPACE_DIR="$WORKSPACE_ROOT" \
    /bin/bash "$HOOK_DIR/user-prompt-wp-reminder.sh" \
    <"$FIXTURES_DIR/user-prompt-day-open.json"
)"
printf '%s' "$day_open_output" |
  jq -e \
    '
      .hookSpecificOutput.hookEventName == "UserPromptSubmit"
      and (.hookSpecificOutput.additionalContext | contains("DAY OPEN"))
      and (.hookSpecificOutput.additionalContext | contains("WP GATE"))
    ' >/dev/null || fail "UserPromptSubmit Day Open context"
pass "UserPromptSubmit preserves Day Open date reminder"

safe_output="$(
  WORKSPACE_DIR="$WORKSPACE_ROOT" \
    /bin/bash "$HOOK_DIR/pre-tool-use-destructive-guard.sh" \
    <"$FIXTURES_DIR/pre-tool-safe.json"
)"
[[ -z "$safe_output" ]] || fail "safe --force-with-lease must pass silently"
pass "PreToolUse allows --force-with-lease and ignores neighbouring -f"

assert_deny "pre-tool-force-push.json" "push --force" "PreToolUse denies git push --force"
assert_deny "pre-tool-force-push-short.json" "push --force" "PreToolUse denies git push -f"
assert_deny "pre-tool-reset-hard.json" "reset --hard" "PreToolUse denies git reset --hard"
assert_deny "pre-tool-clean.json" "git clean" "PreToolUse denies destructive git clean"
assert_deny "pre-tool-rm-rf.json" "rm -rf" "PreToolUse denies recursive forced rm"

set +e
invalid_stderr="$(
  WORKSPACE_DIR="$WORKSPACE_ROOT" \
    /bin/bash "$HOOK_DIR/pre-tool-use-destructive-guard.sh" \
    <"$FIXTURES_DIR/pre-tool-invalid.json" 2>&1 >/dev/null
)"
invalid_status=$?
set -e
[[ "$invalid_status" -eq 2 ]] ||
  fail "malformed PreToolUse input must fail closed with exit 2"
[[ "$invalid_stderr" == *"could not validate"* ]] ||
  fail "malformed PreToolUse input must explain fail-closed decision"
pass "PreToolUse fails closed on malformed input"

present_output="$(
  WORKSPACE_DIR="$WORKSPACE_ROOT" \
    IWE_TRASH_COMMAND="sh" \
    /bin/bash "$HOOK_DIR/session-start-trash-check.sh" \
    <"$FIXTURES_DIR/session-start.json"
)"
[[ -z "$present_output" ]] || fail "SessionStart must stay silent when trash command exists"
pass "SessionStart stays silent when safe-delete command exists"

missing_output="$(
  WORKSPACE_DIR="$WORKSPACE_ROOT" \
    IWE_TRASH_COMMAND="iwe-trash-command-that-does-not-exist" \
    /bin/bash "$HOOK_DIR/session-start-trash-check.sh" \
    <"$FIXTURES_DIR/session-start.json"
)"
printf '%s' "$missing_output" |
  jq -e \
    --arg workspace "$WORKSPACE_ROOT" \
    '
      .hookSpecificOutput.hookEventName == "SessionStart"
      and (.hookSpecificOutput.additionalContext | contains("SAFE DELETE"))
      and (.hookSpecificOutput.additionalContext | contains($workspace))
    ' >/dev/null || fail "SessionStart missing-trash advisory"
pass "SessionStart emits Codex additionalContext when trash is missing"

fixtures_after="$(
  cksum \
  "$FIXTURES_DIR/user-prompt-generic.json" \
  "$FIXTURES_DIR/user-prompt-postmit.json" \
    "$FIXTURES_DIR/user-prompt-day-open.json" \
    "$FIXTURES_DIR/pre-tool-safe.json" \
    "$FIXTURES_DIR/pre-tool-force-push.json" \
    "$FIXTURES_DIR/pre-tool-force-push-short.json" \
    "$FIXTURES_DIR/pre-tool-reset-hard.json" \
    "$FIXTURES_DIR/pre-tool-clean.json" \
    "$FIXTURES_DIR/pre-tool-rm-rf.json" \
    "$FIXTURES_DIR/pre-tool-invalid.json" \
    "$FIXTURES_DIR/session-start.json"
)"
[[ "$fixtures_before" == "$fixtures_after" ]] ||
  fail "smoke tests must not mutate fixtures"
pass "smoke tests are non-mutating"

printf '1..%d\n' "$pass_count"
