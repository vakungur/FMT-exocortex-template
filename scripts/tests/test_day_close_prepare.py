"""
Тесты day-close-prepare.sh (issue #234, token-discipline Day Close).

Скрипт запускается как subprocess в синтетическом workspace (tmp_path):
  1. Digest-режим печатает все 11 секций и выходит с 0.
  2. --verify без итогов дня — FAIL по 9a/9b, exit 1.
  3. --verify с заархивированным DayPlan (итоги есть) и WeekReport — exit 0,
     включая английский заголовок "Day summary" (языко-толерантность 1c62621).
"""

import datetime
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).parent.parent / "day-close-prepare.sh"

DIGEST_SECTIONS = [
    "1. COMMITS TODAY", "2. DIRTY REPOS", "3. OPEN SESSIONS LOG",
    "4. MEMORY DRIFT", "5. INDEX HEALTH", "6. LESSON / MEMORY STATS",
    "7. WAKATIME", "8. PEER SESSIONS TODAY", "9. DAYPLANS IN current/",
    "10. DONE WP CONTEXTS IN inbox/", "11. WEEKREPORT",
]


def _make_workspace(tmp_path: Path) -> Path:
    ws = tmp_path / "workspace"
    gov = ws / "DS-strategy"
    for sub in ["current", "inbox", "archive/day-plans", "sessions"]:
        (gov / sub).mkdir(parents=True)
    (ws / "memory").mkdir()
    (ws / "memory" / "MEMORY.md").write_text("# memory\n", encoding="utf-8")
    return ws


def _run(ws: Path, tmp_path: Path, *args: str) -> subprocess.CompletedProcess:
    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": str(tmp_path / "home"),
        "WORKSPACE_DIR": str(ws),
        "IWE_TEMPLATE": str(tmp_path / "no-template"),  # forces dirty_scan fallback
    }
    (tmp_path / "home").mkdir(exist_ok=True)
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True, text=True, env=env,
    )


def test_digest_emits_all_sections(tmp_path):
    ws = _make_workspace(tmp_path)
    result = _run(ws, tmp_path)
    assert result.returncode == 0, result.stderr
    for section in DIGEST_SECTIONS:
        assert section in result.stdout, f"missing digest section: {section}"
    assert "END DIGEST" in result.stdout


def test_verify_fails_when_day_not_closed(tmp_path):
    ws = _make_workspace(tmp_path)
    result = _run(ws, tmp_path, "--verify")
    assert result.returncode == 1
    assert "9a FAIL" in result.stdout
    assert "9b FAIL" in result.stdout


def test_verify_passes_with_closed_day_english_headings(tmp_path):
    ws = _make_workspace(tmp_path)
    gov = ws / "DS-strategy"
    today = datetime.date.today()
    (gov / "archive/day-plans" / f"DayPlan {today.isoformat()}.md").write_text(
        f"# DayPlan\n## Day summary ({today.isoformat()})\ndone\n", encoding="utf-8"
    )
    (gov / "current" / "WeekReport W29.md").write_text(
        f"<details><summary><b>Results — {today.day} July</b></summary>ok</details>\n",
        encoding="utf-8",
    )
    result = _run(ws, tmp_path, "--verify")
    assert result.returncode == 0, result.stdout
    assert "9a OK" in result.stdout
    assert "9b OK" in result.stdout
    assert "dirty OK" in result.stdout
