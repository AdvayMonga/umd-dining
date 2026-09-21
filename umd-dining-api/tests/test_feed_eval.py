"""Ranking-quality gates: replay 14 days of real menus and grade the visible feed.

Thresholds live in evals/run_eval.py. If a ranking change trips one, run
`python evals/run_eval.py` to see the full scorecard before touching the gate.
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "evals"))
import run_eval  # noqa: E402


@pytest.fixture(scope="module")
def fixture():
    return run_eval.Fixture()


@pytest.mark.parametrize("mode", ["labels", "cold-start"])
def test_feed_quality_gates(fixture, mode):
    assert run_eval.check(fixture, mode) == []


def test_recommendations_match_the_users_taste(fixture):
    cards = run_eval.persona_scorecard(fixture, run_eval.current_ranker)
    precision = [c["recommended_precision"] for c in cards.values()]
    assert sum(precision) / len(precision) >= 0.70
    assert all(c["favorite_leads"] >= 0.95 for c in cards.values())


def test_recommended_stays_scarce_however_many_favorites_a_user_has(fixture):
    by_count = run_eval.recommended_by_favorite_count(fixture, run_eval.current_ranker)
    assert max(by_count.values()) <= 8, by_count
