#!/usr/bin/env bash
# Codex UserPromptSubmit adapter for the IWE WP Gate reminder.
# Read-only: consumes hook JSON and returns developer additionalContext.
set -uo pipefail

HOOK_DIR="$(CDPATH= cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$HOOK_DIR/_common.sh"

IWE_WORKSPACE_ROOT="$(codex_hooks_workspace_root)"
HOOK_INPUT="$(cat 2>/dev/null || printf '{}')"
PROMPT=""

if command -v jq >/dev/null 2>&1; then
  PROMPT="$(
    printf '%s' "$HOOK_INPUT" |
      jq -r 'if type == "object" and (.prompt | type == "string") then .prompt else "" end' \
        2>/dev/null || true
  )"
fi

WP_CONTEXT="⛔ WP GATE: Перед обработкой сообщения проверь ${IWE_WORKSPACE_ROOT}/memory/protocol-open.md. Если это новая нетривиальная задача или новый РП — пройди WP Gate; не регистрируй новый РП без явного согласия пользователя. Если это продолжение того же РП — продолжай. Если вопрос перерастает в работу — повторно оцени WP Gate."

# IWE keeps skills in .claude/skills, while Codex discovers project skills in
# .agents/skills. Preserve the established /skill syntax without pretending it
# is a built-in Codex slash command. Restrict names to the on-disk convention
# before resolving the path to prevent traversal through user input.
if [[ "$PROMPT" =~ ^/([a-z0-9][a-z0-9-]*)([[:space:]]|$) ]]; then
  SKILL_NAME="${BASH_REMATCH[1]}"
  SKILL_FILE="${IWE_WORKSPACE_ROOT}/.agents/skills/${SKILL_NAME}/SKILL.md"

  if [[ -f "$SKILL_FILE" ]]; then
    WP_CONTEXT+=" IWE SKILL: пилот вызвал /${SKILL_NAME}. Используй \$${SKILL_NAME}; если навык не показан в сокращённом списке Codex, прочитай ${SKILL_FILE} и выполни его только доступными средствами."
  else
    WP_CONTEXT+=" IWE SKILL: пилот вызвал /${SKILL_NAME}, но ${SKILL_FILE} не найден. Не имитируй запуск; сообщи ограничение и следующий шаг."
  fi
fi

# Preserve the useful Day Open specialization from the IWE hook, but resolve
# every workspace-owned extension from WORKSPACE_DIR.
if printf '%s' "$PROMPT" | grep -qiE '(открывай[[:space:]]+день|открой[[:space:]]+день|открывай[[:space:]]*$)'; then
  REAL_DATE="$(date '+%Y-%m-%d %A %H:%M %Z')"
  DAY_CONTEXT="⛔ DAY OPEN: Реальная дата и время: ${REAL_DATE}. Используй эту дату для дня недели, strategy_day и временных фильтров."

  BEFORE_EXTENSION="${IWE_WORKSPACE_ROOT}/extensions/day-open.before.md"
  AFTER_EXTENSION="${IWE_WORKSPACE_ROOT}/extensions/day-open.after.md"
  CHECKS_EXTENSION="${IWE_WORKSPACE_ROOT}/extensions/day-open.checks.md"

  [[ -f "$BEFORE_EXTENSION" ]] &&
    DAY_CONTEXT+=" Перед шагом 1 прочитай ${BEFORE_EXTENSION}."
  [[ -f "$AFTER_EXTENSION" ]] &&
    DAY_CONTEXT+=" После шага 6b прочитай ${AFTER_EXTENSION}."
  [[ -f "$CHECKS_EXTENSION" ]] &&
    DAY_CONTEXT+=" Перед git commit прочитай ${CHECKS_EXTENSION}."

  WP_CONTEXT="${DAY_CONTEXT} ${WP_CONTEXT}"
fi

codex_hooks_emit_context "UserPromptSubmit" "$WP_CONTEXT"
