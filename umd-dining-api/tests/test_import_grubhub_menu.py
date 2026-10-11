"""Grubhub HAR → Market menu conversion.

Fixtures mirror the shape of Grubhub's restaurant and item-detail responses
(menu_category_list / menu_item_list / choice_category_list, prices in cents).
Recheck against a real capture if Grubhub changes its payloads.
"""
import base64
import json

from tools import import_grubhub_menu as imp


def restaurant_doc(price=589, available=True):
    return {"restaurant": {"menu_category_list": [
        {"name": "Entrées", "menu_item_list": [
            {"id": 11, "name": "Chick-fil-A Chicken Sandwich", "price": {"amount": price}, "available": available},
            {"id": 12, "name": "8ct Nuggets", "price": {"amount": 549}},
        ]},
        {"name": "Meals", "menu_item_list": [
            {"id": 21, "name": "8ct Nuggets Meal", "minimum_price_variation": {"amount": 1009}},
        ]},
    ]}}


def detail_doc():
    return {"id": 21, "name": "8ct Nuggets Meal", "choice_category_list": [
        {"id": 900, "name": "Choose a Side", "min_choice_options": 1, "max_choice_options": 1,
         "choice_option_list": [
             {"id": 1, "description": "Waffle Fries", "price": {"amount": 0}},
             {"id": 2, "description": "Mac & Cheese", "price": {"amount": 90}},
         ]},
    ]}


def har(*docs, encode_second=False):
    entries = []
    for i, doc in enumerate(docs):
        text = json.dumps(doc)
        content = {"text": text, "mimeType": "application/json"}
        if encode_second and i == 1:
            content = {"text": base64.b64encode(text.encode()).decode(), "encoding": "base64"}
        entries.append({"response": {"content": content}})
    entries.append({"response": {"content": {"text": "<html>not json</html>"}}})
    return {"log": {"entries": entries}}


class TestExtract:
    def test_reads_items_prices_and_categories(self):
        items = imp.extract_menu([restaurant_doc()])
        by_name = {i["name"]: i for i in items}
        assert by_name["Chick-fil-A Chicken Sandwich"]["price"] == 5.89
        assert by_name["8ct Nuggets Meal"]["category"] == "Meals"
        assert by_name["8ct Nuggets Meal"]["price"] == 10.09

    def test_item_detail_supplies_option_groups(self):
        items = imp.extract_menu([restaurant_doc(), detail_doc()])
        meal = next(i for i in items if i["name"] == "8ct Nuggets Meal")
        (side,) = meal["options"]
        assert side["title"] == "Choose a Side"
        assert (side["min"], side["max"]) == (1, 1)
        assert [c["name"] for c in side["choices"]] == ["Waffle Fries", "Mac & Cheese"]
        assert side["choices"][1]["price"] == 0.90

    def test_unavailable_items_are_skipped(self):
        items = imp.extract_menu([restaurant_doc(available=False)])
        assert "Chick-fil-A Chicken Sandwich" not in {i["name"] for i in items}

    def test_har_with_base64_and_non_json_bodies(self, tmp_path):
        path = tmp_path / "capture.har"
        path.write_text(json.dumps(har(restaurant_doc(), detail_doc(), encode_second=True)))
        items = imp.extract_menu(imp.load_json_documents(path))
        meal = next(i for i in items if i["name"] == "8ct Nuggets Meal")
        assert meal["options"], "base64 item detail should still be read"

    def test_empty_capture_explains_itself(self):
        import pytest
        with pytest.raises(SystemExit, match="No menu found"):
            imp.extract_menu([{"unrelated": True}])


class TestDiff:
    def test_reports_price_change_addition_and_removal(self):
        old = imp.extract_menu([restaurant_doc(price=589)])
        new = imp.extract_menu([restaurant_doc(price=619)])
        new = [i for i in new if i["name"] != "8ct Nuggets"] + [
            {"name": "Mac & Cheese", "price": 3.89, "options": []}]
        lines = imp.diff_menus(old, new)
        assert "~ price    Chick-fil-A Chicken Sandwich  $5.89 → $6.19" in lines
        assert "- removed  8ct Nuggets" in lines
        assert "+ added    Mac & Cheese  $3.89" in lines

    def test_reports_option_changes(self):
        old = imp.extract_menu([restaurant_doc(), detail_doc()])
        changed = detail_doc()
        changed["choice_category_list"][0]["choice_option_list"][1]["price"]["amount"] = 120
        new = imp.extract_menu([restaurant_doc(), changed])
        lines = imp.diff_menus(old, new)
        assert "~ options  8ct Nuggets Meal" in lines
        assert "    ~ Choose a Side: Mac & Cheese +$0.90 → +$1.20" in lines

    def test_identical_menus_have_no_diff(self):
        menu = imp.extract_menu([restaurant_doc(), detail_doc()])
        assert imp.diff_menus(menu, menu) == []


def good_menu():
    return [{
        "id": "meal", "name": "8ct Nuggets Meal", "category": "Meals", "emoji": "🍗", "price": 10.09,
        "description": "", "options": [{
            "id": "side", "title": "Choose a Side", "min": 1, "max": 1,
            "choices": [{"id": "fries", "name": "Waffle Fries", "price": 0},
                        {"id": "mac", "name": "Mac & Cheese", "price": 0.9}],
        }],
    }]


class TestValidate:
    def test_good_menu_passes(self):
        assert imp.validate_menu(good_menu()) == []

    def test_catches_bad_rules_prices_and_duplicates(self):
        menu = good_menu()
        menu[0]["options"][0].update(min=3, max=3)  # more required picks than choices
        menu[0]["options"][0]["choices"][1]["name"] = "Waffle Fries"
        menu.append(dict(menu[0], id="meal2", price=0))
        errors = imp.validate_menu(menu)
        assert any("requires 3 picks but has 2 choices" in e for e in errors)
        assert any("choice 'Waffle Fries' appears twice" in e for e in errors)
        assert any("duplicate item name: 8ct Nuggets Meal" in e for e in errors)
        assert any("price 0 looks wrong" in e for e in errors)

    def test_min_above_max_is_invalid(self):
        menu = good_menu()
        menu[0]["options"][0].update(min=2, max=1)
        assert any("min/max 2/1 invalid" in e for e in imp.validate_menu(menu))


class TestOrderDiff:
    def test_reordered_items_are_reported(self):
        a = {"name": "A", "category": "Meals", "price": 1.0, "options": []}
        b = {"name": "B", "category": "Meals", "price": 1.0, "options": []}
        assert "~ order    Meals" in imp.diff_menus([a, b], [b, a])
        assert imp.diff_menus([a, b], [a, b]) == []


class TestCheckMode:
    def test_valid_hand_capture_is_written(self, tmp_path, monkeypatch):
        capture = tmp_path / "capture.json"
        capture.write_text(json.dumps({"items": good_menu()}))
        out = tmp_path / "menu.json"
        monkeypatch.setattr(imp, "REPO", tmp_path)
        assert imp.main([str(capture), "--check", "--out", str(out), "--write"]) == 0
        assert json.loads(out.read_text())["items"][0]["name"] == "8ct Nuggets Meal"

    def test_invalid_hand_capture_is_rejected(self, tmp_path):
        menu = good_menu()
        menu[0]["options"][0]["choices"] = []
        capture = tmp_path / "capture.json"
        capture.write_text(json.dumps({"items": menu}))
        out = tmp_path / "menu.json"
        assert imp.main([str(capture), "--check", "--out", str(out), "--write"]) == 1
        assert not out.exists()


class TestWrite:
    def test_write_creates_menu_file(self, tmp_path, monkeypatch):
        capture = tmp_path / "c.json"
        capture.write_text(json.dumps(restaurant_doc()))
        out = tmp_path / "menu.json"
        monkeypatch.setattr(imp, "REPO", tmp_path)  # keep the "Wrote …" path relative
        assert imp.main([str(capture), "--out", str(out), "--write"]) == 0
        saved = json.loads(out.read_text())
        assert saved["location_id"] == "cfa-stamp"
        assert saved["source"] == "grubhub"
        assert len(saved["items"]) == 3
