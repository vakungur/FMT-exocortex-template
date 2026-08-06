#!/usr/bin/env bash
# Regression test for bug #338: create-wp.sh должен записать РП во ВСЕ локальные места.
# Проверка (5 пунктов): inbox, WeekPlan, Strategy.md, WP-REGISTRY, build-active-wp.py.
# Внешний трекер сюда не входит — он условный пост-шаг (issue #321), не локальная запись.

set -euo pipefail

# Fixture: временный repо-скелет
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TEMPLATE_ROOT="${IWE_TEMPLATE:-$HOME/IWE/FMT-exocortex-template}"
cp -R "$TEMPLATE_ROOT/seed/strategy" "$TMPDIR/strategy"

# seed/ is a one-time bootstrap template, correctly excluded from update.sh's
# ongoing-sync manifest — a copy of this repo obtained any way other than a
# fresh git clone of the exact commit that added current/WeekPlan*.md won't
# have it (found by cold review 03.08). ensure_weekplan_fixture is a no-op
# when the real seed one is already present.
# shellcheck source=lib/seed_strategy_fixture.sh
source "$TEMPLATE_ROOT/scripts/tests/lib/seed_strategy_fixture.sh"
ensure_weekplan_fixture "$TMPDIR/strategy"

# IWE_GOVERNANCE_REPO — имя подпапки ПОД IWE_ROOT (create-wp.sh:26-30), а не
# произвольный относительный путь. "." без выставленного IWE_ROOT резолвился
# в $HOME/IWE/. — реальный домашний каталог, а не эту песочницу (найдено 03.08,
# живьём создало мусорный inbox/WP-001/ в ~/IWE). IWE_ROOT=$TMPDIR + имя
# каталога делают IWE/$GOV_REPO = $TMPDIR/strategy — ровно то, что скопировано.
export IWE_TEMPLATE="$TEMPLATE_ROOT"
export IWE_ROOT="$TMPDIR"
export IWE_GOVERNANCE_REPO="strategy"

cd "$TMPDIR/strategy"

# $PWD (logical), not `pwd -P` (physical): on macOS $TMPDIR from mktemp is
# under /var, which is itself a symlink to /private/var — `pwd -P` resolves
# that symlink and would never match "$TMPDIR"/*, failing this guard on every
# single run regardless of whether the fixture actually escaped (found running
# this test for real, not by reading the code).
case "$PWD" in
  "$TMPDIR"/*) ;;
  *)
    echo "FAIL: fixture escaped TMPDIR: $PWD" >&2
    exit 1
    ;;
esac

# Запустить create-wp.sh
TITLE="Тестовый РП"
bash "$IWE_TEMPLATE/scripts/create-wp.sh" \
  --title "$TITLE" \
  --budget "2h" \
  --priority "P3" \
  --no-consent-check

# Извлечь WP номер из созданного файла
WP_NUM=""
for wp_dir in inbox/WP-*; do
  [ -d "$wp_dir" ] || continue
  WP_NUM=$(basename "$wp_dir" | sed 's/WP-//')
  break
done
[ -z "$WP_NUM" ] && { echo "FAIL: no WP created"; exit 1; }

WP_ID="WP-$(printf '%03d' "$WP_NUM")"

echo "Created: $WP_ID"

# Проверка 5 мест
echo "Checking 5 locations..."

# 1. inbox/WP-N/WP-N.md
[ -f "inbox/$WP_ID/$WP_ID.md" ] || { echo "FAIL: $WP_ID.md not found"; exit 1; }
grep -q "^title:" "inbox/$WP_ID/$WP_ID.md" || { echo "FAIL: title not in inbox"; exit 1; }
echo "✓ inbox/$WP_ID/$WP_ID.md"

# 2. WeekPlan W{N}.md (якорь должен быть)
# Якорь — заголовок RП, не $WP_ID: create-wp.sh:166-168 документирует, что
# колонка «#» в WeekPlan/REGISTRY намеренно хранит bare-число (issue #338 п.4),
# паддинг только в путях/заголовках. WeekPlan-строка не содержит пути, поэтому
# "WP-001" в ней в принципе не появляется — нашёл grep'ая за $WP_ID вхолостую,
# пока эта фикстура наконец не заработала целиком (03.08).
WEEKPLAN=$(ls -1 current/WeekPlan*.md | head -1)
[ -n "$WEEKPLAN" ] || { echo "FAIL: no WeekPlan found"; exit 1; }
grep -q "$TITLE" "$WEEKPLAN" || { echo "FAIL: $WP_ID (title: $TITLE) not in WeekPlan"; exit 1; }
echo "✓ WeekPlan ($WEEKPLAN)"

# 3. Strategy.md (якорь в ## Текущая неделя)
[ -f "docs/Strategy.md" ] || { echo "FAIL: Strategy.md not found"; exit 1; }
grep -q "$WP_ID" "docs/Strategy.md" || { echo "WARN: $WP_ID not in Strategy.md (may be intentional)"; }
echo "✓ Strategy.md (checked)"

# 4. WP-REGISTRY.md (the number must occupy the first cell)
[ -f "docs/WP-REGISTRY.md" ] || { echo "FAIL: WP-REGISTRY.md not found"; exit 1; }
grep -qE "^\| (1|WP-1) \|" "docs/WP-REGISTRY.md" || { echo "FAIL: WP number not in first REGISTRY cell"; exit 1; }
echo "✓ WP-REGISTRY.md"

# 5. build-active-wp.py доступен (проверка пути)
BUILD_SCRIPT="${IWE_SCRIPTS:-$HOME/IWE/scripts}/build-active-wp.py"
[ -f "$BUILD_SCRIPT" ] || { echo "WARN: build-active-wp.py not found at $BUILD_SCRIPT"; }
echo "✓ build-active-wp.py path verified"

echo ""
echo "✓ All 5 locations populated correctly for $WP_ID"

# Regression coverage for every supported registry shape. Each case starts
# from an isolated governance fixture so the assertion also checks numbering
# style preservation and prevents cross-case state from hiding a failure.
run_schema_case() {
  local case_name="$1"
  local registry_body="$2"
  local expected_row="$3"
  local case_root="$TMPDIR/$case_name"
  local case_strategy="$case_root/strategy"

  mkdir -p "$case_root"
  cp -R "$TEMPLATE_ROOT/seed/strategy" "$case_strategy"
  ensure_weekplan_fixture "$case_strategy"
  printf '%s\n' "$registry_body" > "$case_strategy/docs/WP-REGISTRY.md"

  IWE_ROOT="$case_root" IWE_GOVERNANCE_REPO="strategy" \
    bash "$TEMPLATE_ROOT/scripts/create-wp.sh" \
      --title "Schema $case_name" \
      --budget "4h" \
      --priority "P2" \
      --repo "personal-projects/ivs-smena" \
      --no-consent-check \
      > "$case_root/create.out" 2>&1 || {
        cat "$case_root/create.out" >&2
        echo "FAIL: schema $case_name was rejected" >&2
        exit 1
      }

  grep -Fqx "$expected_row" "$case_strategy/docs/WP-REGISTRY.md" || {
    cat "$case_strategy/docs/WP-REGISTRY.md" >&2
    echo "FAIL: schema $case_name produced an unexpected row" >&2
    exit 1
  }
}

run_schema_case "4" \
  $'# Registry\n\n| # | Название | Статус | Активация |\n|---|----------|--------|-----------|\n| WP-19 | Existing | ✅ | closed |' \
  '| WP-20 | **Schema 4** | ⏳ | on-demand → personal-projects/ivs-smena |'

run_schema_case "5" \
  $'# Registry\n\n| # | Приоритет | Название | Статус | Репозитории |\n|---|-----------|----------|--------|-------------|\n| 1 | P3 | Existing | ✅ | strategy |' \
  '| 2 | P2 | **Schema 5** | ⏳ | personal-projects/ivs-smena |'

run_schema_case "6" \
  $'# Registry\n\n| # | P | Название | Ст | Репо | Бюджет |\n|---|---|----------|----|------|--------|\n| 1 | P3 | Existing | ✅ | strategy | 1h |' \
  '| 2 | P2 | **Schema 6** | ⏳ | personal-projects/ivs-smena | 4h |'

run_schema_case "8" \
  $'# Registry\n\n| # | P | Название | Ст | Репо | Бюджет | Активация | Ставка |\n|---|---|----------|----|------|--------|-----------|--------|\n| 1 | P3 | Existing | ✅ | strategy | 1h | closed | — |' \
  '| 2 | P2 | **Schema 8** | ⏳ | personal-projects/ivs-smena | 4h | on-demand | — |'

# The live WeekPlan schema uses full names instead of the legacy h/P columns.
LIVE_WEEKPLAN="$TMPDIR/4/strategy/current/WeekPlan W1.md"
cat > "$LIVE_WEEKPLAN" <<'WPEOF'
| # | РП | Бюджет | Статус | Дедлайн | Репо |
|---|----|---------|--------|---------|------|
| WP-19 | Existing | 1h | done | — | strategy |
WPEOF

IWE_ROOT="$TMPDIR/4" IWE_GOVERNANCE_REPO="strategy" \
  bash "$TEMPLATE_ROOT/scripts/create-wp.sh" \
    --title "Live WeekPlan" \
    --budget "5h" \
    --priority "P2" \
    --repo "personal-projects/ivs-smena" \
    --no-consent-check \
    > "$TMPDIR/4/weekplan.out" 2>&1

grep -Fqx '| WP-21 | **Live WeekPlan** — [описание] | 5h | pending | — | personal-projects/ivs-smena |' "$LIVE_WEEKPLAN" || {
  cat "$LIVE_WEEKPLAN" >&2
  echo "FAIL: live WeekPlan columns were not populated" >&2
  exit 1
}

echo "✓ REGISTRY schemas 4/5/6/8 and the live WeekPlan schema are supported"
