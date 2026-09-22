"""Trending: recent favorites first, the past year when recent activity is thin."""
from datetime import datetime, timedelta, timezone

import pytest

import routes
from conftest import FakeDB


def window_days(pipeline):
    cutoff = datetime.fromisoformat(pipeline[0]["$match"]["added_at"]["$gte"])
    return round((datetime.now(timezone.utc) - cutoff) / timedelta(days=1))


@pytest.fixture
def db(monkeypatch):
    fake = FakeDB()
    monkeypatch.setattr(routes, "db", fake)
    monkeypatch.setitem(routes._trending_cache, "expires", 0)
    return fake


def dishes(n, prefix="D"):
    return [{"_id": f"{prefix}{i}", "count": 2} for i in range(n)]


async def test_busy_month_uses_recent_favorites_only(db):
    seen = []
    db.favorites.aggregate_docs = lambda p: seen.append(window_days(p)) or dishes(8)
    assert await routes._get_trending() == {f"D{i}" for i in range(8)}
    assert seen == [30]


async def test_quiet_month_falls_back_to_the_past_year(db):
    db.favorites.aggregate_docs = lambda p: dishes(1, "NEW") if window_days(p) == 30 else dishes(12, "OLD")
    assert await routes._get_trending() == {f"OLD{i}" for i in range(12)}


async def test_a_single_favorite_is_never_a_trend(db):
    pipelines = []
    db.favorites.aggregate_docs = lambda p: pipelines.append(p) or []
    assert await routes._get_trending() == set()
    assert len(pipelines) == 2  # tried the recent window, then the past year
    for pipeline in pipelines:
        assert {"$match": {"count": {"$gte": 2}}} in pipeline
