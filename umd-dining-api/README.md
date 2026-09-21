# UMD Dining API

A REST API that scrapes and serves University of Maryland dining hall menus and nutrition information.

## Features

- Scrapes menus from UMD dining halls (Yahentamitsi, 251 North, South Campus Diner)
- Fetches and caches nutrition info, allergens, and ingredients per item
- Search for food items by name

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/dining-halls` | List all dining halls |
| GET | `/api/menu?date=...&dining_hall_id=...` | Get menu items (filterable) |
| GET | `/api/nutrition?rec_num=...` | Get nutrition info for a food item |
| GET | `/api/search?q=...` | Search food items by name |
| POST | `/api/scrape?date=...` | Scrape menus for a given date |
| GET | `/api/ranked-menu?date=...` | Personalized home feed (see below) |

## Feed ranking

`ranker.py` builds the home feed: drop junk (toppings, condiments, drinks, plain bread), then score each dish by
appeal + rarity + the user's favorites/taste + student interest (distinct students who viewed the dish — a tiebreaker
while data is thin, able to outweigh the appeal prior once ~100 students have viewed the top dish). Per hall and meal it sends up to 3 dishes per
station and flags the best 20 as `featured`; the app leads with those (grouped by station) and puts the rest behind
See More, so a strong menu spreads across many stations and a thin one across few.

- **Quality labels** — `data/food_labels.json` holds an LLM judge's verdict (role + appeal 1-5) per food. Edit a row to
  overrule the judge. Foods not in the file are rated by a small local model (`food_quality.py`, numpy only).
- **No API calls** at ranking time; personalization reuses the embeddings already stored on each food.

### Evals

```bash
python evals/run_eval.py                     # scorecard: junk %, appeal, nDCG, personalization
python evals/run_eval.py --show 9/22/2026    # print the feed a guest would see that day
python evals/run_eval.py --baseline old.py   # compare against another ranker.py
```

The scorecard replays 14 days of real menus (`evals/fixture/`) and grades what the iOS home screen would show.
`pytest` runs the same gates, so a ranking change that regresses quality fails CI.

To label new foods, judge them with `evals/JUDGE_RUBRIC.md`, add rows to `data/food_labels.json`, then run
`python evals/train_quality_model.py` (needs `evals/requirements.txt`) to refresh the fallback model.
