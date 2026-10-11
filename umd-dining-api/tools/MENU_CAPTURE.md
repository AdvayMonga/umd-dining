# Capturing a campus menu from the Grubhub app

Campus restaurants (Stamp Chick-fil-A and others) only appear in the Grubhub
phone app, not on grubhub.com, so the menu is captured from the app by
following these steps. A person can do it on their phone, or Claude can do it
through iPhone Mirroring in the Claude desktop app with Computer use on. Done
either way, the result should be identical.

The goal: a seller reading our checklist can rebuild the buyer's order in the
Grubhub app tap for tap, and Grubhub's bag total matches ours to the cent.

## Rules

1. **Copy text exactly as Grubhub shows it.** Keep ® and ™, capitalization,
   "&" vs "and", sizes in parentheses. Don't shorten or fix typos.
2. **Keep Grubhub's order everywhere**: categories top to bottom, items within
   each category, option groups top to bottom on an item's screen, choices
   within each group. List order in the file *is* the display order.
3. **Prices are the numbers Grubhub shows**, before tax: the item price, and
   each choice's "+$0.90"-style add-on price (0 when none is shown).
4. **Group rules come from the group's label**:
   - "Required" / "Choose 1" → `min: 1, max: 1`
   - "Choose up to 3" / "Optional, up to 3" → `min: 0, max: 3`
   - "Choose 2" (required, exactly) → `min: 2, max: 2`
   - "Optional" with single-select circles → `min: 0, max: 1`
5. **Open every item**, even ones that look simple. Hidden option groups (sauces,
   "make it a meal") only show inside the item screen.
6. **Never tap Checkout or Place Order.** Adding to the bag for the test below
   is fine; empty the bag afterwards.

## Steps

1. Grubhub app → Campus → Stamp Chick-fil-A. Note the hours shown on the
   restaurant page.
2. For each category, top to bottom, for each item, top to bottom:
   - record name, price, description (empty string if none)
   - open the item; record each option group and its choices as above
   - back out without adding
3. Write the file below and save it as `capture.json`.
4. **Bag test**: build these carts in the Grubhub bag one at a time and write
   down the bag subtotal for each. Then empty the bag.
   - the most expensive meal with a paid side and a paid add-on
   - the largest nuggets item with the maximum number of sauces
   - one drink in its largest size
   - two different items together, quantity 2 on one of them
5. Validate and compare with the current menu:
   ```
   cd umd-dining-api
   python tools/import_grubhub_menu.py capture.json --check
   ```
   Fix anything it reports as a problem, then check each bag-test subtotal
   against what the app computes for the same cart. All must match.
6. Accept it: same command with `--write`, rebuild the app.

## File format

```json
{
  "items": [
    {
      "id": "nuggets-8ct-meal",
      "name": "Chick-fil-A® Nuggets Meal",
      "category": "Meals",
      "emoji": "🍗",
      "price": 10.09,
      "description": "8 count nuggets, side and drink",
      "options": [
        {
          "id": "side",
          "title": "Choose a Side",
          "min": 1,
          "max": 1,
          "choices": [
            { "id": "waffle-fries", "name": "Waffle Potato Fries®", "price": 0 },
            { "id": "mac-cheese", "name": "Mac & Cheese", "price": 0.90 }
          ]
        }
      ]
    }
  ]
}
```

- `id`s: lowercase words joined by hyphens, made from the name. Keep the
  same id for the same thing across captures so diffs line up.
- `emoji`: any fitting emoji (the app shows it in place of a photo).
- `category`: the Grubhub section heading, exactly.

## After capture

Real orders keep checking the menu: sellers compare the Grubhub bag total with
ours before paying, and the confirmation screenshot's subtotal is compared
afterwards. Mismatches are flagged; when one appears, re-capture the affected
items with these steps.
