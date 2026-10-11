"""Turn a saved Grubhub page session into the Market menu file the app bundles.

Capture (manual, in your own browser; nothing here talks to Grubhub):
  1. Chrome → grubhub.com → the Stamp Chick-fil-A page, signed in.
  2. ⌥⌘I → Network tab → reload the page.
  3. Click into every item that has options (meals, nuggets, drinks…) so
     their option groups load too.
  4. Right-click any request → "Save all as HAR with content".

Then:
  python tools/import_grubhub_menu.py ~/Downloads/www.grubhub.com.har          # show diff only
  python tools/import_grubhub_menu.py ~/Downloads/www.grubhub.com.har --write  # accept it

A single saved JSON response works too, in place of the HAR.

Campus restaurants usually only show in the phone app. For those, follow
tools/MENU_CAPTURE.md to write the menu file by hand (or have Claude do it via
iPhone Mirroring), then validate and diff it the same way:
  python tools/import_grubhub_menu.py capture.json --check           # validate + diff
  python tools/import_grubhub_menu.py capture.json --check --write   # accept it
"""
from __future__ import annotations

import argparse
import base64
import json
import re
import sys
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO / "umd-dining-app" / "Resources" / "market-menu-cfa-stamp.json"

# First keyword hit wins; order matters ("meal" before the entrée words)
EMOJI = [
    ("spicy", "🌶️"), ("nugget", "🍗"), ("strip", "🍗"), ("sandwich", "🥪"),
    ("wrap", "🌯"), ("salad", "🥗"), ("fries", "🍟"), ("mac", "🧀"),
    ("fruit", "🍓"), ("lemonade", "🍋"), ("tea", "🧋"), ("shake", "🥤"),
    ("cookie", "🍪"), ("brownie", "🍫"), ("water", "💧"), ("coffee", "☕"),
    ("sauce", "🥫"), ("biscuit", "🥐"),
]


# MARK: - Reading the capture

def load_json_documents(path: Path) -> list:
    """Every JSON body in a HAR, or the single document in a .json file."""
    raw = json.loads(path.read_text())
    if not (isinstance(raw, dict) and "log" in raw and "entries" in raw["log"]):
        return [raw]
    docs = []
    for entry in raw["log"]["entries"]:
        content = entry.get("response", {}).get("content", {})
        text = content.get("text")
        if not text:
            continue
        if content.get("encoding") == "base64":
            try:
                text = base64.b64decode(text).decode("utf-8")
            except (ValueError, UnicodeDecodeError):
                continue
        try:
            docs.append(json.loads(text))
        except json.JSONDecodeError:
            continue
    return docs


def walk(node):
    """Yield every dict in a JSON tree."""
    if isinstance(node, dict):
        yield node
        for v in node.values():
            yield from walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v)


def cents(price) -> int | None:
    """Grubhub prices look like {"amount": 589, "currency": "USD"}."""
    if isinstance(price, dict):
        price = price.get("amount")
    if isinstance(price, (int, float)):
        return int(price)
    return None


def item_price(item: dict) -> int | None:
    for key in ("price", "minimum_price_variation", "delivery_price", "pickup_price"):
        c = cents(item.get(key))
        if c is not None:
            return c
    return None


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def emoji_for(name: str) -> str:
    lower = name.lower()
    return next((e for word, e in EMOJI if word in lower), "🍽️")


def parse_options(item: dict) -> list[dict]:
    groups = []
    for group in item.get("choice_category_list") or []:
        title = (group.get("name") or "").strip()
        choices = []
        for opt in group.get("choice_option_list") or []:
            name = (opt.get("description") or opt.get("name") or "").strip()
            if not name:
                continue
            choices.append({
                "id": str(opt.get("id") or slug(name)),
                "name": name,
                "price": round((cents(opt.get("price")) or 0) / 100, 2),
            })
        if not title or not choices:
            continue
        groups.append({
            "id": str(group.get("id") or slug(title)),
            "title": title,
            "min": int(group.get("min_choice_options") or 0),
            "max": int(group.get("max_choice_options") or 1),
            "choices": choices,
        })
    return groups


def extract_menu(docs: list) -> list[dict]:
    """Categories from the restaurant response, options from item detail responses."""
    items: dict[str, dict] = {}
    details: dict[str, list[dict]] = {}

    for doc in docs:
        for node in walk(doc):
            for category in node.get("menu_category_list") or []:
                cat_name = (category.get("name") or "Menu").strip()
                for item in category.get("menu_item_list") or []:
                    name = (item.get("name") or "").strip()
                    price = item_price(item)
                    if not name or price is None or item.get("available") is False:
                        continue
                    item_id = str(item.get("id") or slug(name))
                    items.setdefault(item_id, {
                        "id": item_id,
                        "name": name,
                        "category": cat_name,
                        "emoji": emoji_for(name),
                        "price": round(price / 100, 2),
                        "description": (item.get("description") or "").strip(),
                        "options": parse_options(item),
                    })
            # Item detail responses (opened by tapping an item) carry the choices
            if node.get("choice_category_list") and node.get("name"):
                item_id = str(node.get("id") or slug(node["name"]))
                details[item_id] = parse_options(node)

    for item_id, options in details.items():
        if item_id in items and options:
            items[item_id]["options"] = options

    if not items:
        keys = sorted({k for d in docs if isinstance(d, dict) for k in d})[:40]
        raise SystemExit(
            "No menu found in the capture. Make sure the restaurant page finished loading "
            f"before saving.\nTop-level keys seen: {keys}"
        )
    return list(items.values())


# MARK: - Validation

def validate_menu(items: list[dict]) -> list[str]:
    """Problems that would make a seller's Grubhub order differ from the buyer's."""
    errors = []
    names = [i.get("name", "") for i in items]
    for dup in sorted({n for n in names if names.count(n) > 1}):
        errors.append(f"duplicate item name: {dup}")
    ids = [i.get("id") for i in items]
    for dup in sorted({str(x) for x in ids if ids.count(x) > 1}):
        errors.append(f"duplicate item id: {dup}")

    for item in items:
        where = item.get("name") or item.get("id") or "<unnamed item>"
        for key in ("id", "name", "category", "emoji"):
            if not str(item.get(key, "")).strip():
                errors.append(f"{where}: missing {key}")
        price = item.get("price")
        if not isinstance(price, (int, float)) or not 0 < price < 100:
            errors.append(f"{where}: price {price!r} looks wrong")

        titles = [g.get("title", "") for g in item.get("options", [])]
        for dup in sorted({t for t in titles if titles.count(t) > 1}):
            errors.append(f"{where}: option group '{dup}' appears twice")
        for group in item.get("options", []):
            g = f"{where} / {group.get('title') or '<untitled group>'}"
            choices = group.get("choices", [])
            lo, hi = group.get("min"), group.get("max")
            if not choices:
                errors.append(f"{g}: no choices")
            if not isinstance(lo, int) or not isinstance(hi, int) or lo < 0 or hi < 1 or lo > hi:
                errors.append(f"{g}: min/max {lo}/{hi} invalid")
            elif lo > len(choices):
                errors.append(f"{g}: requires {lo} picks but has {len(choices)} choices")
            choice_names = [c.get("name", "") for c in choices]
            for dup in sorted({n for n in choice_names if choice_names.count(n) > 1}):
                errors.append(f"{g}: choice '{dup}' appears twice")
            for c in choices:
                cp = c.get("price")
                if not c.get("name") or not c.get("id"):
                    errors.append(f"{g}: choice missing name or id")
                if not isinstance(cp, (int, float)) or not 0 <= cp < 50:
                    errors.append(f"{g} / {c.get('name')}: price {cp!r} looks wrong")
    return errors


# MARK: - Diffing

def diff_menus(old: list[dict], new: list[dict]) -> list[str]:
    old_by = {i["name"]: i for i in old}
    new_by = {i["name"]: i for i in new}
    lines = []
    for name in sorted(new_by.keys() - old_by.keys()):
        lines.append(f"+ added    {name}  ${new_by[name]['price']:.2f}")
    for name in sorted(old_by.keys() - new_by.keys()):
        lines.append(f"- removed  {name}")
    for name in sorted(old_by.keys() & new_by.keys()):
        o, n = old_by[name], new_by[name]
        if o["price"] != n["price"]:
            lines.append(f"~ price    {name}  ${o['price']:.2f} → ${n['price']:.2f}")
        o_opts = {g["title"]: {c["name"]: c["price"] for c in g["choices"]} for g in o.get("options", [])}
        n_opts = {g["title"]: {c["name"]: c["price"] for c in g["choices"]} for g in n.get("options", [])}
        if o_opts != n_opts:
            lines.append(f"~ options  {name}")
            for title in sorted(o_opts.keys() | n_opts.keys()):
                before, after = o_opts.get(title, {}), n_opts.get(title, {})
                for choice in sorted(after.keys() - before.keys()):
                    lines.append(f"    + {title}: {choice}")
                for choice in sorted(before.keys() - after.keys()):
                    lines.append(f"    - {title}: {choice}")
                for choice in sorted(before.keys() & after.keys()):
                    if before[choice] != after[choice]:
                        lines.append(f"    ~ {title}: {choice} +${before[choice]:.2f} → +${after[choice]:.2f}")

    # Sellers follow Grubhub's screen order, so a reshuffle matters too
    def order(menu):
        cats: dict[str, list[str]] = {}
        for i in menu:
            cats.setdefault(i.get("category", ""), []).append(i["name"])
        return cats
    old_order, new_order = order(old), order(new)
    for cat in new_order:
        shared = [n for n in new_order[cat] if n in old_order.get(cat, [])]
        if shared != [n for n in old_order.get(cat, []) if n in shared]:
            lines.append(f"~ order    {cat}")
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("capture", type=Path,
                        help="HAR file, saved JSON response, or (with --check) a menu file captured by hand")
    parser.add_argument("--check", action="store_true",
                        help="capture is already in menu format (from the phone capture procedure)")
    parser.add_argument("--location", default="cfa-stamp")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--write", action="store_true", help="save the new menu (otherwise only show the diff)")
    args = parser.parse_args(argv)

    if args.check:
        items = json.loads(args.capture.read_text())["items"]
    else:
        items = extract_menu(load_json_documents(args.capture))
    old_items = json.loads(args.out.read_text())["items"] if args.out.exists() else []

    errors = validate_menu(items)
    if errors:
        print(f"{len(errors)} problem(s); nothing written:")
        print("\n".join(f"  ✗ {e}" for e in errors))
        return 1

    changes = diff_menus(old_items, items)
    with_options = sum(1 for i in items if i["options"])
    print(f"{len(items)} items, {with_options} with options")
    print("\n".join(changes) if changes else "No changes from the current menu.")
    missing = [i["name"] for i in items if not i["options"] and re.search(r"meal|nugget|drink|lemonade|tea", i["name"], re.I)]
    if missing:
        print(f"\nNo options captured for: {', '.join(missing)}\n"
              "Click into those items on Grubhub before saving the HAR if they should have choices.")

    if args.write:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps({
            "location_id": args.location,
            "source": "grubhub",
            "captured_on": date.today().isoformat(),
            "items": items,
        }, indent=2, ensure_ascii=False) + "\n")
        print(f"\nWrote {args.out.relative_to(REPO)}")
    elif changes:
        print("\nRun again with --write to accept.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
