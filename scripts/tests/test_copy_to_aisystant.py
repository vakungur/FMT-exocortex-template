"""Tests for scripts/copy-to-aisystant.py (WP-415 Pipeline 1: personal RU
template -> aisystant private RU repos, Variant A pull-only).

Network calls (`gh repo view`, real `github.com` pushes) are never exercised
here -- `target_exists` is monkeypatched, and remote URLs are redirected to
local bare git repos via `_remote_url`, so these tests prove the dry-run/
live/confirm/token gates and the commit-tree publish logic without touching
any real GitHub org.
"""

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

MODULE_PATH = Path(__file__).parent.parent / "copy-to-aisystant.py"
spec = importlib.util.spec_from_file_location("copy_to_aisystant", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
sys.modules["copy_to_aisystant"] = mod
spec.loader.exec_module(mod)


def _git(repo_dir: Path, *args: str) -> subprocess.CompletedProcess:
    result = subprocess.run(
        ["git", "-C", str(repo_dir), *args], capture_output=True, text=True, check=True
    )
    return result


@pytest.fixture
def source_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "source"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "test@example.com")
    _git(repo, "config", "user.name", "Test")
    (repo / "README.md").write_text("hello\n", encoding="utf-8")
    _git(repo, "add", "README.md")
    _git(repo, "commit", "-q", "-m", "initial")
    return repo


@pytest.fixture
def bare_target(tmp_path: Path) -> Path:
    target = tmp_path / "target.git"
    subprocess.run(["git", "init", "-q", "--bare", str(target)], check=True)
    return target


def _write_config(tmp_path: Path, repo: str, branch: str = "main") -> Path:
    config = tmp_path / "targets.yaml"
    config.write_text(
        yaml.safe_dump({"schema_version": 1, "targets": [{"repo": repo, "branch": branch}]}),
        encoding="utf-8",
    )
    return config


class TestLoadTargets:
    def test_missing_file_returns_empty(self, tmp_path):
        assert mod.load_targets(tmp_path / "does-not-exist.yaml") == []

    def test_empty_list_returns_empty(self, tmp_path):
        config = tmp_path / "targets.yaml"
        config.write_text(yaml.safe_dump({"targets": []}), encoding="utf-8")
        assert mod.load_targets(config) == []

    def test_parses_entries_with_branch_default(self, tmp_path):
        config = _write_config(tmp_path, "aisystant/docs-aisystant")
        targets = mod.load_targets(config)
        assert len(targets) == 1
        assert targets[0].repo == "aisystant/docs-aisystant"
        assert targets[0].branch == "main"


class TestMainNoTargets:
    def test_empty_config_is_a_quiet_success(self, tmp_path, source_repo, capsys):
        config = tmp_path / "targets.yaml"
        config.write_text(yaml.safe_dump({"targets": []}), encoding="utf-8")
        rc = mod.main(["--config", str(config), "--repo-dir", str(source_repo)])
        assert rc == 0
        assert "nothing to do" in capsys.readouterr().out


class TestMissingTargetRepo:
    def test_nonexistent_repo_is_skipped_not_created(self, tmp_path, source_repo, monkeypatch, capsys):
        monkeypatch.setattr(mod, "target_exists", lambda repo: False)
        config = _write_config(tmp_path, "aisystant/does-not-exist-yet")
        rc = mod.main(["--config", str(config), "--repo-dir", str(source_repo)])
        assert rc == 0
        out = capsys.readouterr().out
        assert "does not exist yet" in out
        assert "not creating it" in out


class TestDryRun:
    def test_default_run_does_not_push(self, tmp_path, source_repo, bare_target, monkeypatch, capsys):
        monkeypatch.setattr(mod, "target_exists", lambda repo: True)
        monkeypatch.setattr(mod, "_remote_url", lambda repo, token: f"file://{bare_target}")
        config = _write_config(tmp_path, "aisystant/docs-aisystant")

        rc = mod.main(["--config", str(config), "--repo-dir", str(source_repo)])
        assert rc == 0
        assert "dry-run" in capsys.readouterr().out
        # Bare target must still have zero refs -- nothing was pushed.
        refs = subprocess.run(
            ["git", "-C", str(bare_target), "for-each-ref"], capture_output=True, text=True, check=True
        )
        assert refs.stdout.strip() == ""


class TestLiveGates:
    def test_live_without_confirm_refuses(self, tmp_path, source_repo, bare_target, monkeypatch):
        monkeypatch.setattr(mod, "target_exists", lambda repo: True)
        monkeypatch.setattr(mod, "_remote_url", lambda repo, token: f"file://{bare_target}")
        monkeypatch.setenv("GH_TOKEN", "fake-token")
        config = _write_config(tmp_path, "aisystant/docs-aisystant")

        rc = mod.main(["--config", str(config), "--repo-dir", str(source_repo), "--live"])
        assert rc == 1

    def test_live_without_token_refuses(self, tmp_path, source_repo, bare_target, monkeypatch):
        monkeypatch.setattr(mod, "target_exists", lambda repo: True)
        monkeypatch.setattr(mod, "_remote_url", lambda repo, token: f"file://{bare_target}")
        monkeypatch.delenv("GH_TOKEN", raising=False)
        config = _write_config(tmp_path, "aisystant/docs-aisystant")

        rc = mod.main([
            "--config", str(config), "--repo-dir", str(source_repo),
            "--live", "--confirm=PUBLISH",
        ])
        assert rc == 1


class TestLivePublish:
    def test_confirmed_live_run_publishes_commit(self, tmp_path, source_repo, bare_target, monkeypatch):
        monkeypatch.setattr(mod, "target_exists", lambda repo: True)
        monkeypatch.setattr(mod, "_remote_url", lambda repo, token: f"file://{bare_target}")
        monkeypatch.setenv("GH_TOKEN", "fake-token")
        config = _write_config(tmp_path, "aisystant/docs-aisystant")

        rc = mod.main([
            "--config", str(config), "--repo-dir", str(source_repo),
            "--live", "--confirm=PUBLISH",
        ])
        assert rc == 0
        refs = subprocess.run(
            ["git", "-C", str(bare_target), "for-each-ref", "--format=%(refname)"],
            capture_output=True, text=True, check=True,
        )
        assert "refs/heads/main" in refs.stdout

    def test_second_run_is_up_to_date_and_skips(self, tmp_path, source_repo, bare_target, monkeypatch, capsys):
        monkeypatch.setattr(mod, "target_exists", lambda repo: True)
        monkeypatch.setattr(mod, "_remote_url", lambda repo, token: f"file://{bare_target}")
        monkeypatch.setenv("GH_TOKEN", "fake-token")
        config = _write_config(tmp_path, "aisystant/docs-aisystant")
        args = [
            "--config", str(config), "--repo-dir", str(source_repo),
            "--live", "--confirm=PUBLISH",
        ]
        assert mod.main(args) == 0
        capsys.readouterr()

        rc = mod.main(args)
        assert rc == 0
        assert "up to date" in capsys.readouterr().out
