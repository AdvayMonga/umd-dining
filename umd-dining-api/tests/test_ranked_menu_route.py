"""/api/ranked-menu end to end: route glue -> rank_items -> response shape."""
import pytest

import routes
from conftest import FakeDB

DATE = "9/5/2026"
PIZZA_VEC, CURRY_VEC = [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]


def menu(rec_num, station, meal="Lunch", hall="19", icons=()):
    return {"rec_num": rec_num, "date": DATE, "dining_hall_id": hall, "meal_period": meal,
            "station": station, "dietary_icons": list(icons), "frequency": 3}


def food(rec_num, name, protein="10g", embedding=None):
    doc = {"rec_num": rec_num, "name": name, "nutrition": {"Protein": protein, "Serving Size": "1 each"}}
    if embedding:
        doc["embedding"] = embedding
    return doc


@pytest.fixture
def db(monkeypatch):
    fake = FakeDB(
        menus=[menu("PIZZA", "Pizza"), menu("PIZZA", "Pizza", meal="Dinner"), menu("CURRY", "Chef's Table"),
               menu("RANCH", "Salad Bar"), menu("TOFU", "Woks", icons=["vegan"])],
        foods=[food("PIZZA", "Pepperoni Pizza", embedding=PIZZA_VEC), food("CURRY", "Chicken Curry", "30g", CURRY_VEC),
               food("RANCH", "Ranch Dressing"), food("TOFU", "Kung Pao Tofu", embedding=CURRY_VEC),
               food("FAV", "Thai Green Curry Chicken", embedding=CURRY_VEC)],
        favorites=[{"user_id": "u1", "rec_num": "FAV"}],
        preferences=[{"user_id": "u1", "vegan": True, "cuisine_prefs": ["Italian"]}],
        cuisine_embeddings=[{"cuisine": "Italian", "embedding": PIZZA_VEC}],
    )
    monkeypatch.setattr(routes, "db", fake)
    for cache in (routes._trending_cache, routes._global_views_cache):
        monkeypatch.setitem(cache, "expires", 0)
    monkeypatch.setattr(routes, "_guest_menu_cache", {})
    return fake


async def ranked(user_id=None, **over):
    kwargs = dict(request=None, date=DATE, dining_hall_ids=["19"], user_id=user_id, vegetarian=False,
                  vegan=False, halal=False, high_protein=False, allergens=[])
    kwargs.update(over)
    # __wrapped__ skips the slowapi decorator, which needs a live Request
    return await routes.get_ranked_menu.__wrapped__(**kwargs)


async def test_guest_feed_gates_junk_and_keeps_the_response_shape(db):
    body = await ranked()
    names = [i["name"] for i in body["data"]]
    assert body["success"] and body["count"] == len(names)
    assert "Ranch Dressing" not in names
    assert names.count("Pepperoni Pizza") == 2  # once for lunch, once for dinner
    assert set(body["data"][0]) == {"name", "rec_num", "dining_hall_id", "date", "meal_period", "station",
                                    "dietary_icons", "tag", "tags", "featured"}


async def test_signed_in_feed_uses_favorites_cuisines_and_student_interest(db):
    db.item_views.aggregate_docs = [{"_id": "CURRY", "count": 40}]
    body = await ranked(user_id="u1")
    lunch = [i for i in body["data"] if i["meal_period"] == "Lunch"]
    assert lunch[0]["name"] == "Chicken Curry"  # matches the favorite, is viewed by students, high protein
    assert "Recommended" in lunch[0]["tags"] and "High Protein" in lunch[0]["tags"]


async def test_dietary_filter_runs_before_ranking(db):
    body = await ranked(vegan=True)
    assert [i["name"] for i in body["data"]] == ["Kung Pao Tofu"]
