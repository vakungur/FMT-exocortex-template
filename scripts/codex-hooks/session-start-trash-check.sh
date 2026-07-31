#!/usr/bin/env bash
# Codex SessionStart advisory for the IWE safe-delete dependency.
# Read-only and non-blocking: emits context only when the command is missing.
set -uo pipefail

HOOK_DIR="$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$HOOK_DIR/_common.sh"

IWE_WORKSPACE_ROOT="$(codex_hooks_workspace_root)"
TRASH_COMMAND="${IWE_TRASH_COMMAND:-trash}"

# Consume the event object even though this check does not need its fields.
cat >/dev/null 2>&1 || true

if command -v "$TRASH_COMMAND" >/dev/null 2>&1; then
  exit 0
fi

CONTEXT="⚠️ SAFE DELETE: команда '${TRASH_COMMAND}' не найдена. Для ${IWE_WORKSPACE_ROOT} не используй rm -rf; до установки trash-cli удаляй только после явного согласования. Установи trash/trash-cli через пакетный менеджер своей ОС."
codex_hooks_emit_context "SessionStart" "$CONTEXT"
