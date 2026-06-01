# AGENTS.md

## Commit Attribution

Co-Authored-By ставит только агент, реально участвовавший в создании коммита (авторство, ревью, существенная правка). Автономные коммиты других агентов / скриптов — без трейлера Kimi, если Kimi не участвовал.

Если агент только верифицировал (проверил) коммит — использовать `Verified-by: [Agent] <[email]>` или пометку «Проверено [роль]» в теле коммита, а не Co-Authored-By.

**Для коммитов с участием Kimi:**

**Method 1 (preferred — template):**
```bash
git commit -t ~/.git-commit-template-kimi -m "feat: description"
```

**Method 2 (manual — if template unavailable):**
```bash
git commit -m "feat: description" --trailer "Co-Authored-By: Kimi <noreply@moonshot.ai>"
```

**Never** commit without the trailer. If you forget — amend immediately:
```bash
git commit --amend --trailer "Co-Authored-By: Kimi <noreply@moonshot.ai>"
```

## Git Staging — CRITICAL

**NEVER use `git add -u`, `git add .`, or `git add -A`.**

These commands pick up staged/unstaged changes from OTHER agents (Claude Code works in the same repo simultaneously). Wrong attribution and accidental commits of other agents' work result.

**Always stage only specific files you edited:**
```bash
# Correct
git add DS-ecosystem-development/0.OPS/0.9.Inbox/WP-73-architect-agenda-next.md

# FORBIDDEN — captures other agents' work
git add -u
git add .
git add -A
```

## Coordination Protocol

Before starting any edit task:

1. **Declare intention** (no lock needed):
   ```
   Tool: update_peer_status
   params: { "status": "working", "current_task": "<brief description>", "files": ["relative/path/file.md"] }
   ```

2. **Acquire lock** before first Edit:
   ```
   Tool: acquire_file_lock
   param: canonical_file = relative path from IWE root (e.g. "DS-ecosystem-development/0.OPS/0.9.Inbox/WP-73-architect-agenda-next.md")
   ```

3. **Release lock** after commit:
   ```
   Tool: release_file_lock
   ```

4. On `lock_collision`: wait 30s and retry, or switch to another file.

## Artifact Naming

**Do not invent artifact names.** Names for sections, documents, RPs, and deliverables must come from the plan/task you received. If the task is silent on a name — report "need clarification on name" instead of making one up.

## Drift Reporting

If you discover a discrepancy (file doesn't match plan, stale content, inconsistency):
- **Report to pilot, do not silently fix.**
- Format: "Found drift: [what is inconsistent] in [file]. Should I fix it?"
- Only fix if explicitly instructed.

## Working Directory

`{{WORKSPACE_DIR}}/`

## WP Context Scope — Umbrella РП

Для зонтичных (umbrella) РП с `agent_scope: open-only` в frontmatter:
- Читать **только** фазы со статусом `pending` / `in_progress` / `blocked`
- Архивные (`done`, `closed`, `defer`) — **не читать** без явного запроса пользователя
- Исключение: если пользователь даёт задание с указанием конкретной архивной фазы

Применяется к: WP-5, WP-7.

## Calendar Events — CRITICAL

**All platform reminders and calendar events created by the agent must be scheduled BEFORE 09:00 AM.**

This includes:
- Task reminders
- Follow-up events
- Template migration tasks
- Any agent-generated calendar entries

**Never** schedule agent-created events at or after 09:00 without explicit pilot approval.

If an event is created after 09:00 by mistake:
1. Delete the incorrect event immediately
2. Recreate it before 09:00 on the same day, or on the next available pre-09:00 slot
3. Report the error to the pilot

## Language

Respond in Russian unless the user writes in English.

## Response Style — Pilot-Facing (peer-session 2026-06-01-27)

**Symmetric to Claude `CLAUDE.md §9` "Режим на пальцах (S-37)" and `memory/feedback_response_clarity_for_pilot.md`.**

The pilot reads agent responses as a human, not as a CI inspector. Twelve patterns of clutter and eleven rules — full text in `memory/feedback_response_clarity_for_pilot.md` (HOT). Kimi must apply these rules in chat replies, report syntheses, and post-action summaries.

**Channel detector (which style for which context):**
- **Peer-session transcripts** (`NN-writer.md` / `NN-peer.md`) — dense technical style. No restrictions.
- **`report.md` synthesis** (§1-§4 «Постановка», «Позиции», «Альтернативы», «Решение») — режим «на пальцах» / pilot-readable.
- **`report.md` quoted turns** — dense technical style as evidence, no rewrite.
- **Chat with pilot** — detector by pilot's own message:
  - Technical mode if pilot writes `grep`, `git`, file paths, command flags, SHA hashes, English code-terms.
  - Режим «на пальцах» otherwise (default for «объясни», «что произошло», «почему», or task framed without technical detail).
- **Commit messages, PR descriptions** — dense technical style.

**Eleven rules (A1-A11), short form:**

- **A1.** File path is never the subject of a sentence. Only in parentheses after a Russian verb. («Бот пишет ноль в счётчик при старте марафона (`handlers/marathon.py:65`)»). Three or more paths → move under spoiler / final section.
- **A2.** English term allowed only after Russian description, in parentheses. Open exceptions list — terms the pilot himself uses: бот, чек-ин, deploy, smoke, merge, push, commit, MCP, Pack.
- **A3.** First mention of a column / function / variable in a reply — must include a one-word meaning. («Колонка `total_checkins` (всего чек-инов в марафоне)»).
- **A4.** Pre-flight filter for every sentence: will the pilot make a decision based on this? No → move to technical details or remove.
- **A5.** WHAT before HOW. First — what happens to the pilot / bot / user. Then — how to fix, one phrase. HOW belongs in main text only if it changes the pilot's decision.
- **A6.** One implication-arrow per sentence. «А → Б» fine. «А → Б → В» → split into two sentences.
- **A7.** Report-after-action format: «Сделал то-то. Эффект для пилота / бота: такой-то. Технические детали — под спойлером ниже.» No bare commit hashes, paths, exit codes in main text.
- **A8.** Process journal («читаю файл…», «проверяю…», «let me check…») — by default NOT written. Under spoiler only if pilot explicitly asked for trace.
- **A9.** Channel detector — see above.
- **A10.** English status markers («exit 0», «PASS», «status: done», «SHA: abc») → Russian: «получилось», «прошло проверку», «закрыто», «залил правкой». SHA as navigation link → in parentheses after Russian.
- **A11.** Active voice on errors and findings. «Я нашёл», «я ошибся в гипотезе», «я понял после проверки». Passive «было обнаружено», «оказалось», «выяснилось» forbidden in main text.

**Twelve clutter patterns (П1-П12) — full text with «было/стало» examples in `memory/feedback_response_clarity_for_pilot.md`.**

**Self-check before sending a pilot reply** — 4 quick passes:
1. Path as subject in main text? (П1 / A1) → move into parentheses.
2. English term without Russian description? (П2 / A2) → add Russian description first.
3. «exit», «PASS», «SHA» as a fact? (П11 / A10) → replace with Russian word.
4. «Было обнаружено» / «оказалось»? (П12 / A11) → rewrite in first person active.
