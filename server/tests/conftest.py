import pytest


@pytest.fixture(autouse=True)
def _accounts_in_tmp(tmp_path, monkeypatch):
    """Every test app keeps its player accounts (and arcade scores) in throwaway files, never server/var."""
    monkeypatch.setenv("HH_ACCOUNTS_DB", str(tmp_path / "accounts.db"))
    monkeypatch.setenv("HH_ARCADE_DB", str(tmp_path / "arcade.db"))  # (and arcade scores)
