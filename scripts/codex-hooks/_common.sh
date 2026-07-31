#!/usr/bin/env bash
# Shared helpers for the minimal IWE -> Codex hook adapters.
# Codex hook contract: https://learn.chatgpt.com/docs/hooks

# Resolve workspace-owned paths from WORKSPACE_DIR when the caller supplies it.
# A missing/stale value falls back to the repository root relative to this file,
# so hooks remain usable when Codex starts in a nested working directory.
codex_hooks_workspace_root() {
  local helper_dir candidate

  helper_dir="$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  candidate="${WORKSPACE_DIR:-}"

  if [[ -n "$candidate" && -d "$candidate" ]]; then
    CDPATH= cd -P -- "$candidate" && pwd
    return
  fi

  CDPATH= cd -P -- "$helper_dir/../.." && pwd
}

# UserPromptSubmit and SessionStart both accept this Codex-specific JSON shape.
# Plain stdout is also valid for those two events, so it is a safe fallback if
# jq is unavailable.
codex_hooks_emit_context() {
  local event_name="$1" context="$2"

  if command -v jq >/dev/null 2>&1 &&
    jq -cn \
      --arg event_name "$event_name" \
      --arg context "$context" \
      '{
        hookSpecificOutput: {
          hookEventName: $event_name,
          additionalContext: $context
        }
      }'; then
    return 0
  fi

  printf '%s\n' "$context"
}

# PreToolUse accepts permissionDecision=deny. If JSON emission is unavailable,
# exit 2 + stderr is the documented fail-closed fallback.
codex_hooks_emit_pretool_deny() {
  local reason="$1"

  if command -v jq >/dev/null 2>&1 &&
    jq -cn \
      --arg reason "$reason" \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $reason
        }
      }'; then
    return 0
  fi

  printf 'BLOCKED: %s\n' "$reason" >&2
  return 2
}
