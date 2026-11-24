import pytest


@pytest.fixture(autouse=True)
def _accounts_in_tmp(tmp_path, monkeypatch):
    """Every test app keeps its player accounts in a throwaway file, never server/var/accounts.db."""
    monkeypatch.setenv("HH_ACCOUNTS_DB", str(tmp_path / "accounts.db"))
