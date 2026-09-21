# Judge rubric — UMD dining hall feed

You are judging items for the home feed of a college dining-hall app. The feed answers:
"What's worth going to the dining hall for today?" Students scroll a ranked list of dishes.

For every row in your chunk file, output one line: `idx<TAB>role<TAB>appeal`

## role (exactly one)
- `main`      — a dish you'd build a meal around: entrees, pizzas, burgers, composed sandwiches/wraps,
                pasta dishes, stir-fries, bowls, hearty composed salads, breakfast mains (omelets,
                pancakes, french toast, breakfast sandwiches, scrambled eggs as a served dish).
- `side`      — a prepared accompaniment: fries, rice, roasted/steamed vegetables, mashed potatoes,
                soups, beans, breakfast meats (bacon/sausage as a breakfast side), hash browns, fruit salad.
- `dessert`   — cakes, cookies, pies, brownies, ice cream, pastries, doughnuts, muffins, sweet bakery.
- `bread`     — plain bread, rolls, bagels, tortillas, buns, toast, plain waffle/plain staples from a self-serve bar, cereal.
- `component` — a raw/plain build-your-own ingredient or topping: salad-bar vegetables, shredded or
                sliced cheese, deli meats sold by the slice, burger toppings (lettuce, tomato, bacon
                strip as a topping), stir-fry raw ingredients, plain tofu cubes, hard-boiled egg at a
                salad bar, whole fruit, yogurt toppings, seeds, croutons.
- `condiment` — sauces, dressings, spreads, butter, cream cheese, syrups, jams, mustard, ketchup, oils, salsas, gravies.
- `beverage`  — drinks.

Use the station as context: "Salad Bar", "Harvest Greens", "Deli", "Mongolian Grill", "Woks",
"Smash Burger" contain many components/condiments, but ALSO real dishes — judge the item itself.
Nutrition values are noisy; do not rely on calories.

## appeal (integer 1–5): how good a feed headline is this for a typical student?
- 5 — crowd-pleaser / destination dish (e.g. chicken tenders, orange chicken, mac & cheese, a special like Lomo Saltado, burgers, popular pizza)
- 4 — solid, appealing dish most people would be glad to see
- 3 — fine but unexciting (plain grilled chicken, basic pasta, standard sides like fries = 3–4)
- 2 — rarely anyone's reason to go (plain steamed veg, plain rice, plain bread, basic cereal)
- 1 — should never be a feed headline (condiments, raw toppings, shredded cheese, single raw ingredients)

Components and condiments are almost always 1. Judge by the dish, not by healthiness.

## Output
Write ONLY the TSV lines (no header, no commentary) to the output file you are given, one line
per input row, same idx values, every row covered exactly once.
