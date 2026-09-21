"""Food quality: judge-label lookup, model fallback, and the shipped artifacts."""
import pytest

from food_quality import QualityModel, featurize, is_junk

ROLES = {"main", "side", "dessert", "bread", "component", "condiment", "beverage"}


@pytest.fixture(scope="module")
def model():
    return QualityModel.load()


def test_shipped_labels_are_well_formed(model):
    assert len(model.labels) > 1500
    for label in model.labels.values():
        assert label["role"] in ROLES
        assert 1 <= label["appeal"] <= 5


def test_judge_label_wins_over_the_model(model):
    rec_num, label = next((r, v) for r, v in model.labels.items() if v["role"] == "condiment")
    # a name the model would call a main must not override the stored verdict
    assert model.get(rec_num, {"name": "Cheeseburger"}) == ("condiment", float(label["appeal"]))


@pytest.mark.parametrize("name,station,serving", [
    ("Chipotle Ranch Dressing", "Salad Bar", "1 oz"),
    ("Sriracha Mayo Sauce", "Grill", "1 oz"),
    ("Shredded Mozzarella Cheese", "Salad Bar", "1 oz"),
    ("Sliced Red Onions", "Deli", "1 oz"),
])
def test_unseen_junk_is_gated(model, name, station, serving):
    assert is_junk(*model.predict(name, station, serving))


@pytest.mark.parametrize("name,station,serving", [
    ("Buffalo Chicken Pizza", "Pizza", "1 slice"),
    ("Korean BBQ Beef Rice Bowl", "Chef's Table", "1 each"),
    ("Butternut Squash Ravioli", "Pasta", "6 oz"),
    ("Turkey Wrap w/ Chipotle Aioli", "Deli+", "1 each"),
])
def test_unseen_dishes_pass_the_gate(model, name, station, serving):
    role, appeal = model.predict(name, station, serving)
    assert not is_junk(role, appeal)
    assert appeal >= 2.5


@pytest.mark.parametrize("role,appeal,junk", [
    ("condiment", 5, True), ("component", 4, True),   # toppings never pass, however tasty
    ("bread", 2, True), ("beverage", 3, True),        # plain staples don't either
    ("bread", 4, False),                               # garlic bread, naan
    ("main", 1, False), ("side", 2, False),
])
def test_junk_rule(role, appeal, junk):
    assert is_junk(role, appeal) is junk


def test_missing_model_falls_back_to_a_neutral_main():
    assert QualityModel().predict("Anything") == ("main", 3.0)


def test_featurize_is_deterministic_and_normalized():
    idx, val = featurize("Orange Chicken", "Woks", "4 oz")
    idx2, _ = featurize("Orange Chicken", "Woks", "4 oz")
    assert list(idx) == list(idx2)
    assert abs(float((val ** 2).sum()) - 1.0) < 1e-5
