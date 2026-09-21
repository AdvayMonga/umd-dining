"""Feed ranking: junk gate, scoring signals, tags, per-slot dedup and caps."""
import pytest

import ranker
from ranker import get_protein, rank_items

# mid-window frequency: neither a rotating special nor a daily staple
NEUTRAL_FREQ = 7


def entry(rec_num, **over):
    base = {
        "rec_num": rec_num,
        "dining_hall_id": "19",
        "date": "9/5/2026",
        "meal_period": "Lunch",
        "station": f"Station {rec_num}",
        "dietary_icons": [],
        "frequency": NEUTRAL_FREQ,
    }
    base.update(over)
    return base


def food(rec_num, **over):
    base = {
        "rec_num": rec_num,
        "name": f"Food {rec_num}",
        "nutrition": {"Calories": "400", "Protein": "10g"},
    }
    base.update(over)
    return base


def rank(entries, foods=None, roles=None, appeals=None, **over):
    """rank_items with a fake judge: every food is a 3-appeal main unless overridden."""
    roles, appeals = roles or {}, appeals or {}
    kwargs = {
        "menu_entries": entries,
        "foods": foods if foods is not None else {e["rec_num"]: food(e["rec_num"]) for e in entries},
        "fav_rec_nums": set(),
        "fav_stations": set(),
        "user_prefs": {},
        "popular_rec_nums": set(),
        "date_seed": "9/5/2026",
        "quality": lambda rec_num, _food, _station="": (roles.get(rec_num, "main"), appeals.get(rec_num, 3.0)),
    }
    kwargs.update(over)
    return rank_items(**kwargs)


def ids(result):
    return [i["rec_num"] for i in result]


class TestNutritionParsing:
    @pytest.mark.parametrize("value,expected", [
        ("32g", 32.0), ("450", 450.0), ("12.5g", 12.5), ("", None), (None, None),
    ])
    def test_parse_number(self, value, expected):
        assert ranker._parse_number(value) == expected

    def test_protein_key_variants(self):
        assert get_protein({"Protein": "25g"}) == 25.0
        assert get_protein({"Total Protein": "18g"}) == 18.0
        assert get_protein({}) is None


class TestJunkGate:
    @pytest.mark.parametrize("role", ["component", "condiment", "beverage", "bread"])
    def test_junk_roles_never_reach_the_feed(self, role):
        assert ids(rank([entry("JUNK"), entry("MAIN")], roles={"JUNK": role})) == ["MAIN"]

    def test_an_appealing_bread_counts_as_a_dish(self):
        result = rank([entry("NAAN"), entry("BAGEL")], roles={"NAAN": "bread", "BAGEL": "bread"},
                      appeals={"NAAN": 4.0, "BAGEL": 3.0})
        assert ids(result) == ["NAAN"]

    def test_junk_survives_if_the_user_favorited_it(self):
        result = rank([entry("KETCHUP")], roles={"KETCHUP": "condiment"}, fav_rec_nums={"KETCHUP"})
        assert ids(result) == ["KETCHUP"]

    def test_high_protein_data_cannot_rescue_a_condiment(self):
        # real data: 1 oz of mustard is listed with 7.9g protein and 148 calories
        foods = {"MUSTARD": food("MUSTARD", nutrition={"Calories": "148", "Protein": "40g"})}
        assert rank([entry("MUSTARD")], foods=foods, roles={"MUSTARD": "condiment"}) == []


class TestScoring:
    def test_more_appealing_dish_ranks_first(self):
        assert ids(rank([entry("MEH"), entry("GREAT")], appeals={"MEH": 2.0, "GREAT": 5.0})) == ["GREAT", "MEH"]

    def test_main_outranks_side_of_equal_appeal(self):
        assert ids(rank([entry("SIDE"), entry("MAIN")], roles={"SIDE": "side"}))[0] == "MAIN"

    def test_dessert_ranks_below_side_of_equal_appeal(self):
        assert ids(rank([entry("CAKE"), entry("FRIES")], roles={"CAKE": "dessert", "FRIES": "side"}))[0] == "FRIES"

    def test_rotating_special_outranks_daily_staple(self):
        assert ids(rank([entry("STAPLE", frequency=14), entry("SPECIAL", frequency=1)]))[0] == "SPECIAL"

    def test_missing_frequency_is_not_treated_as_a_special(self):
        unknown = entry("UNKNOWN")
        del unknown["frequency"]
        assert ids(rank([unknown, entry("SPECIAL", frequency=1)]))[0] == "SPECIAL"

    def test_favorite_beats_a_far_more_appealing_dish(self):
        result = rank([entry("FAV"), entry("GREAT")], appeals={"FAV": 2.0, "GREAT": 5.0}, fav_rec_nums={"FAV"})
        assert result[0]["rec_num"] == "FAV"
        assert result[0]["tag"] == "Favorite"

    def test_favorite_station_breaks_a_tie(self):
        result = rank([entry("A", station="Grill"), entry("B", station="Wok")], fav_stations={"Wok"})
        assert result[0]["rec_num"] == "B"

    def test_dietary_preference_match_breaks_a_tie(self):
        entries = [entry("MEAT"), entry("VEG", dietary_icons=["vegan"])]
        assert ids(rank(entries, user_prefs={"vegan": True}))[0] == "VEG"

    def test_preferred_hall_outranks_other_hall(self):
        entries = [entry("A", dining_hall_id="19"), entry("B", dining_hall_id="51")]
        assert ids(rank(entries, preferred_halls=["51"]))[0] == "B"


class TestStudentInterest:
    """global_views = distinct students who viewed each dish (routes.py dedupes repeat taps)."""

    def test_thin_evidence_is_only_a_tiebreaker(self):
        result = rank([entry("MEH"), entry("GREAT")], appeals={"MEH": 3.0, "GREAT": 4.0}, global_views={"MEH": 3})
        assert ids(result)[0] == "GREAT"

    def test_many_students_outweigh_the_appeal_prior(self):
        result = rank([entry("MEH"), entry("GREAT")], appeals={"MEH": 3.0, "GREAT": 4.0},
                      global_views={"MEH": 120, "OTHER": 2})
        assert ids(result)[0] == "MEH"

    def test_interest_is_relative_to_the_most_viewed_dish(self):
        result = rank([entry("NICHE"), entry("HIT")], global_views={"NICHE": 5, "HIT": 120})
        assert ids(result)[0] == "HIT"

    def test_views_cannot_get_junk_past_the_gate(self):
        assert rank([entry("KETCHUP")], roles={"KETCHUP": "condiment"}, global_views={"KETCHUP": 500}) == []

    def test_unviewed_dishes_are_not_penalized(self):
        entries = [entry("A"), entry("B")]
        assert ids(rank(entries)) == ids(rank(entries, global_views={"ELSEWHERE": 80}))


class TestTags:
    def test_trending_tag(self):
        assert "Trending" in rank([entry("A")], popular_rec_nums={"A"})[0]["tags"]

    def test_high_protein_tag(self):
        foods = {"A": food("A", nutrition={"Protein": "30g"})}
        assert "High Protein" in rank([entry("A")], foods=foods)[0]["tags"]

    def test_high_protein_tag_is_for_dishes_not_desserts(self):
        foods = {"A": food("A", nutrition={"Protein": "30g"})}
        assert "High Protein" not in rank([entry("A")], foods=foods, roles={"A": "dessert"})[0]["tags"]

    def test_similar_to_favorites_earns_recommended_tag(self):
        vec = [1.0, 0.0, 0.0]
        result = rank([entry("A")], foods={"A": food("A", embedding=vec)}, fav_embeddings=[vec])
        assert "Recommended" in result[0]["tags"]

    def test_dissimilar_item_is_not_recommended(self):
        result = rank([entry("A")], foods={"A": food("A", embedding=[0.0, 1.0, 0.0])}, fav_embeddings=[[1.0, 0.0, 0.0]])
        assert "Recommended" not in result[0]["tags"]

    def test_favorite_suppresses_recommended_tag(self):
        vec = [1.0, 0.0, 0.0]
        result = rank([entry("A")], foods={"A": food("A", embedding=vec)}, fav_embeddings=[vec], fav_rec_nums={"A"})
        assert "Recommended" not in result[0]["tags"]


class TestAffinity:
    def test_shared_theme_beats_a_single_ingredient_overlap(self):
        # 20 unrelated foods set the menu baseline; THEME is near both favorites,
        # LOOKALIKE is very near only one of them.
        foods = {f"N{i}": {"embedding": [0.0, 0.0, 1.0, 0.05 * i]} for i in range(20)}
        foods["THEME"] = {"embedding": [0.7, 0.7, 0.0, 0.0]}
        foods["LOOKALIKE"] = {"embedding": [0.95, 0.0, 0.3, 0.0]}
        scores = ranker._affinity(set(foods), foods, [[1.0, 0.1, 0.0, 0.0], [0.1, 1.0, 0.0, 0.0]])
        assert scores["THEME"] > scores["LOOKALIKE"] > scores["N0"] == 0.0

    def test_scale_does_not_grow_with_the_number_of_favorites(self):
        foods = {f"N{i}": {"embedding": [0.0, 0.0, 1.0, 0.05 * i]} for i in range(20)}
        foods["MATCH"] = {"embedding": [1.0, 0.0, 0.0, 0.0]}
        one = ranker._affinity(set(foods), foods, [[1.0, 0.0, 0.0, 0.0]])["MATCH"]
        many = ranker._affinity(set(foods), foods, [[1.0, 0.0, 0.0, 0.0]] * 25)["MATCH"]
        assert many <= one * 5.01  # 25x the anchors, at most sqrt(25)x the score

    def test_embeddings_of_the_wrong_size_are_ignored(self):
        foods = {"OK": {"embedding": [1.0, 0.0]}, "RAGGED": {"embedding": [1.0, 0.0, 0.0]}}
        assert set(ranker._affinity(set(foods), foods, [[1.0, 0.0]])) == {"OK"}

    def test_no_anchors_means_no_affinity(self):
        assert ranker._affinity({"A"}, {"A": {"embedding": [1.0, 0.0]}}, []) == {}


class TestSlots:
    def test_menu_row_without_a_food_doc_is_skipped(self):
        assert ids(rank([entry("GHOST"), entry("REAL")], foods={"REAL": food("REAL")})) == ["REAL"]

    def test_favoriting_a_station_covers_its_sides(self):
        entries = [entry(f"S{i}", station="Grill Sides") for i in range(6)]
        assert len(rank(entries, fav_stations={"Grill"})) == 4

    def test_side_station_is_merged_into_its_parent(self):
        assert rank([entry("A", station="Grill Sides")])[0]["station"] == "Grill"

    def test_duplicate_rec_num_appears_once_per_slot(self):
        assert len(rank([entry("A", station="Grill"), entry("A", station="Deli")])) == 1

    def test_same_dish_is_kept_for_every_meal_and_hall_it_is_served_at(self):
        entries = [entry("A", meal_period="Lunch"), entry("A", meal_period="Dinner"),
                   entry("A", dining_hall_id="51")]
        assert len(rank(entries)) == 3

    def test_caps_at_30_per_hall_and_meal_period(self):
        assert len(rank([entry(f"R{i}") for i in range(35)])) == 30

    def test_cap_is_per_hall_meal_combination(self):
        entries = ([entry(f"A{i}", dining_hall_id="19") for i in range(35)]
                   + [entry(f"B{i}", dining_hall_id="51") for i in range(35)])
        assert len(rank(entries)) == 60

    def test_station_card_holds_three_dishes(self):
        entries = ([entry(f"P{i}", station="Pizza") for i in range(30)]
                   + [entry(f"G{i}", station="Grill") for i in range(2)])
        result = rank(entries, appeals={f"P{i}": 5.0 for i in range(30)})
        assert sum(i["station"] == "Pizza" for i in result) == 3
        assert {"G0", "G1"} <= set(ids(result))

    def test_favorite_station_card_holds_four(self):
        result = rank([entry(f"P{i}", station="Pizza") for i in range(10)], fav_stations={"Pizza"})
        assert len(result) == 4

    def test_sixth_favorite_is_softened_below_a_top_dish(self):
        favs = {f"F{i}" for i in range(6)}
        entries = [entry(f"F{i}") for i in range(6)] + [entry("GREAT")]
        result = rank(entries, fav_rec_nums=favs, appeals={"GREAT": 5.0})
        assert ids(result).index("GREAT") == 5


class TestFeatured:
    def test_small_menu_is_all_featured(self):
        assert all(i["featured"] for i in rank([entry(f"R{i}") for i in range(10)]))

    def test_only_the_best_twenty_are_featured(self):
        appeals = {f"R{i}": 5.0 if i < 20 else 4.0 for i in range(28)}
        result = rank([entry(f"R{i}") for i in range(28)], appeals=appeals)
        assert {i["rec_num"] for i in result if i["featured"]} == {f"R{i}" for i in range(20)}

    def test_budget_follows_the_good_dishes_not_a_fixed_grid(self):
        def featured(appeals):
            entries = [entry(f"S{s}D{d}", station=f"Station {s}") for s in range(12) for d in range(3)]
            return [i for i in rank(entries, appeals=appeals) if i["featured"]]
        # one great dish at every station -> all twelve stations lead
        spread = featured({f"S{s}D{d}": 5.0 if d == 0 else 2.0 for s in range(12) for d in range(3)})
        assert {i["station"] for i in spread} == {f"Station {s}" for s in range(12)}
        # three stations carry the menu -> their full cards lead
        focused = featured({f"S{s}D{d}": 5.0 if s < 3 else 2.0 for s in range(12) for d in range(3)})
        assert {f"S{s}D{d}" for s in range(3) for d in range(3)} <= {i["rec_num"] for i in focused}

    def test_filler_is_not_featured_just_to_fill_the_screen(self):
        result = rank([entry("GOOD"), entry("FILLER")], appeals={"FILLER": 2.0})
        assert {i["rec_num"]: i["featured"] for i in result} == {"GOOD": True, "FILLER": False}

    def test_a_favorite_is_featured_whatever_its_appeal(self):
        assert rank([entry("FAV")], appeals={"FAV": 1.0}, fav_rec_nums={"FAV"})[0]["featured"]

    def test_budget_is_per_hall_and_meal(self):
        entries = ([entry(f"L{i}", meal_period="Lunch") for i in range(25)]
                   + [entry(f"D{i}", meal_period="Dinner") for i in range(25)])
        assert sum(i["featured"] for i in rank(entries)) == 40


class TestDeterminism:
    def test_same_seed_gives_same_order(self):
        entries = [entry(f"R{i}") for i in range(10)]
        assert ids(rank(entries)) == ids(rank(entries))

    def test_ties_rotate_with_the_date(self):
        entries = [entry(f"R{i}") for i in range(10)]
        assert ids(rank(entries, date_seed="9/5/2026")) != ids(rank(entries, date_seed="9/6/2026"))


class TestEmptyInput:
    def test_no_entries_returns_empty(self):
        assert rank([]) == []
