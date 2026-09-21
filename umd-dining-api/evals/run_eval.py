"""
Feed-ranking scorecard. Replays 14 days of real menus through rank_items,
applies the same station grouping the iOS home feed does, and grades what a
student would actually see against the LLM-judge labels.

    python evals/run_eval.py                          # current ranker
    python evals/run_eval.py --baseline old_ranker.py # side-by-side with another ranker
    python evals/run_eval.py --show 9/22/2026         # print one day's visible feed

Modes: "labels" is production (judge labels + model fallback); "cold-start"
pretends every food is brand new, so only the fallback model is used
(out-of-fold predictions, i.e. the model never saw the food it is rating).
"""

import argparse
import collections
import gzip
import importlib.util
import inspect
import json
import os
import random
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import ranker as current_ranker  # noqa: E402
from food_quality import LABELS_PATH, is_junk  # noqa: E402

# Mirrors HomeViewModel.displayRows
SIDE_STATION_KEYWORDS = ['sauce', 'condiment', 'dressing', 'topping', 'side dish', 'sides', 'beverage', 'drink']
LEGACY_ITEM_KEYWORDS = ['dressing', 'ranch', 'vinaigrette', 'sauce', 'salsa', 'mayo', 'ketchup', 'mustard',
                        'hot sauce', 'butter', 'creamer', 'syrup', 'gravy', 'aioli', 'marinade', 'relish',
                        'hummus', 'spread']
STATIONS_SHOWN, ITEMS_PER_STATION = 5, 3

# Taste personas: favorites are the first few matching foods; everything else
# matching the keywords is what a good recommender should surface.
PERSONAS = {
    'pizza': ['pizza'],
    'fried chicken': ['tender', 'fried chicken', 'nugget', 'wings', 'tempura chicken', 'chicken strips'],
    'pasta': ['pasta', 'penne', 'ziti', 'alfredo', 'lasagna', 'macaroni', 'spaghetti'],
    'tofu': ['tofu'],
    'burger': ['burger', 'cheeseburger'],
    'curry': ['curry', 'masala', 'tikka', 'palak', 'vindaloo', 'korma'],
}
# Real users like several kinds of food at once
MIXED_PERSONAS = [('pizza', 'curry'), ('fried chicken', 'tofu'), ('pasta', 'burger', 'curry')]
PERSONA_FAVORITES = 4  # per kind

# Regression gates (see tests/test_feed_eval.py). In 'labels' mode the ranker reads the same labels it is
# graded on, so those gates catch broken ranking logic, not bad labels; 'cold-start' is the honest number.
THRESHOLDS = {
    'labels': {'junk_visible': 0.01, 'junk_top3': 0.01, 'mean_appeal': 3.9, 'ndcg': 0.80, 'great_visible': 0.78},
    'cold-start': {'junk_visible': 0.06, 'junk_top3': 0.10, 'mean_appeal': 3.6, 'ndcg': 0.68, 'great_visible': 0.62},
}


class Fixture:
    def __init__(self, path=os.path.join(HERE, 'fixture')):
        def load(name):
            with gzip.open(os.path.join(path, f'{name}.json.gz'), 'rt') as fh:
                return json.load(fh)
        self.menus = load('menus')
        self.foods = {f['rec_num']: f for f in load('foods')}
        self.engagement = load('engagement')
        with np.load(os.path.join(path, 'embeddings.npz')) as z:
            # plain lists, the way MongoDB hands embeddings to the ranker
            self.embeddings = dict(zip(z['rec_nums'].tolist(), z['vectors'].astype(np.float32).tolist(), strict=True))
        with open(LABELS_PATH) as fh:
            self.gold = json.load(fh)
        with open(os.path.join(HERE, 'oof_predictions.json')) as fh:
            self.oof = json.load(fh)
        self.dates = sorted({m['date'] for m in self.menus}, key=lambda d: tuple(int(p) for p in d.split('/'))[::-1])
        self.by_date = collections.defaultdict(list)
        for m in self.menus:
            self.by_date[m['date']].append(m)
        favs = self.engagement['favorites']
        self.trending = {r for r, n in favs.items() if n >= 2}
        self.global_views = dict(sorted(self.engagement['views'].items(), key=lambda kv: -kv[1])[:100])

    def is_junk(self, rec_num):
        return is_junk(self.gold[rec_num]['role'], self.gold[rec_num]['appeal'])

    def quality(self, mode):
        table = self.gold if mode == 'labels' else self.oof
        return lambda rec_num, food, station='': (table[rec_num]['role'], float(table[rec_num]['appeal']))


def load_ranker(path):
    spec = importlib.util.spec_from_file_location('baseline_ranker', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_feed(fx, ranker, date, mode='labels', favorites=()):
    """Server feed for one date. Favorites double as taste anchors."""
    favorites = set(favorites)
    anchors = [fx.embeddings[r] for r in sorted(favorites) if r in fx.embeddings]
    foods = fx.foods
    if anchors:
        foods = {r: dict(f, embedding=fx.embeddings[r]) if r in fx.embeddings else f for r, f in fx.foods.items()}
    kwargs = dict(menu_entries=fx.by_date[date], foods=foods, fav_rec_nums=favorites, fav_stations=set(),
                  user_prefs={}, popular_rec_nums=fx.trending, date_seed=date, fav_embeddings=anchors,
                  user_views={}, global_views=fx.global_views)
    if 'quality' in inspect.signature(ranker.rank_items).parameters:
        kwargs['quality'] = fx.quality(mode)
    return ranker.rank_items(**kwargs)


def visible(feed, hall, meal, legacy_client=False):
    """What the home screen shows for one hall + meal, before tapping See More.

    Current app: the server-flagged featured dishes, grouped by station.
    Legacy app (or a ranker that doesn't flag): first 5 stations x 3 items, minus keyword-filtered names.
    """
    pool = [i for i in feed if i['dining_hall_id'] == hall and i['meal_period'] == meal
            and not any(k in i['station'].lower() for k in SIDE_STATION_KEYWORDS)]
    if not legacy_client and any(i.get('featured') for i in pool):
        pool = [i for i in pool if i.get('featured')]
        stations = list(dict.fromkeys(i['station'] for i in pool))
        return [i for st in stations for i in pool if i['station'] == st]
    if legacy_client:
        pool = [i for i in pool if not any(k in i['name'].lower() for k in LEGACY_ITEM_KEYWORDS)]
    stations = list(dict.fromkeys(i['station'] for i in pool))[:STATIONS_SHOWN]
    return [i for st in stations for i in [x for x in pool if x['station'] == st][:ITEMS_PER_STATION]]


def slots_of(feed):
    return sorted({(i['dining_hall_id'], i['meal_period']) for i in feed})


def _display_station(name):
    return re.sub(r'\s+Sides?\s*$', '', name, flags=re.IGNORECASE)


def feed_scorecard(fx, ranker, mode='labels', legacy_client=False):
    junk = shown = junk_top3 = n_slots = stations = great = great_seen = great_st = great_st_seen = 0
    appeals, ndcgs = [], []
    for date in fx.dates:
        feed = run_feed(fx, ranker, date, mode)
        for hall, meal in slots_of(feed):
            vis = visible(feed, hall, meal, legacy_client)
            judged = [(fx.gold[v['rec_num']]['role'], fx.gold[v['rec_num']]['appeal']) for v in vis]
            if not judged:
                continue
            n_slots += 1
            shown += len(judged)
            junk += sum(is_junk(role, a) for role, a in judged)
            junk_top3 += any(is_junk(role, a) for role, a in judged[:3])
            appeals += [a for _, a in judged]
            stations += len({v['station'] for v in vis})
            menu = [m for m in fx.by_date[date] if m['dining_hall_id'] == hall and m['meal_period'] == meal]

            # Coverage: how many of the slot's great mains (judge >= 4), and their stations, made the screen
            great_mains = {m['rec_num']: _display_station(m['station']) for m in menu
                           if fx.gold[m['rec_num']]['role'] == 'main' and fx.gold[m['rec_num']]['appeal'] >= 4}
            great += len(great_mains)
            great_seen += len(set(great_mains) & {v['rec_num'] for v in vis})
            great_st += len(set(great_mains.values()))
            great_st_seen += len(set(great_mains.values()) & {v['station'] for v in vis})

            # nDCG vs. the best possible list from everything on that slot's menu
            k = len(judged)
            discount = 1 / np.log2(np.arange(2, k + 2))
            ideal = np.array(sorted((2 ** fx.gold[m['rec_num']]['appeal'] - 1 for m in menu), reverse=True)[:k])
            ndcgs.append(float((np.array([2 ** a - 1 for _, a in judged]) * discount).sum()
                               / (ideal * discount[:len(ideal)]).sum()))
    return {
        'junk_visible': junk / shown, 'junk_top3': junk_top3 / n_slots, 'mean_appeal': float(np.mean(appeals)),
        'ndcg': float(np.mean(ndcgs)), 'great_visible': great_seen / great, 'great_stations_visible': great_st_seen / great_st,
        'dishes': shown / n_slots, 'stations_visible': stations / n_slots, 'slots': n_slots,
    }


def persona_scorecard(fx, ranker, mode='labels', legacy_client=False):
    """Held-out category retrieval: favorite a few foods of a kind, expect the rest of that kind."""
    out = {}
    personas = [(kind,) for kind in PERSONAS] + MIXED_PERSONAS
    for kinds in personas:
        persona = ' + '.join(kinds)
        keywords = [k for kind in kinds for k in PERSONAS[kind]]

        def matches(rec_num, keywords=keywords):
            return any(k in fx.foods[rec_num]['name'].lower() for k in keywords)
        favorites = set()
        for kind in kinds:
            pool = sorted(r for r in fx.embeddings if not fx.is_junk(r)
                          and any(k in fx.foods[r]['name'].lower() for k in PERSONAS[kind]))
            favorites.update(pool[:PERSONA_FAVORITES])
        recommended = rec_hits = relevant = rel_visible = fav_slots = fav_leads = 0
        appeals = []
        for date in fx.dates:
            feed = run_feed(fx, ranker, date, mode, favorites)
            for item in feed:
                if 'Recommended' in item['tags']:
                    recommended += 1
                    rec_hits += matches(item['rec_num'])
            for hall, meal in slots_of(feed):
                vis = visible(feed, hall, meal, legacy_client)
                vis_ids = [v['rec_num'] for v in vis]
                appeals += [fx.gold[r]['appeal'] for r in vis_ids]
                on_menu = {m['rec_num'] for m in fx.by_date[date]
                           if m['dining_hall_id'] == hall and m['meal_period'] == meal}
                targets = {r for r in on_menu if matches(r) and r not in favorites
                           and not fx.is_junk(r)}
                relevant += len(targets)
                rel_visible += len(targets & set(vis_ids))
                if favorites & on_menu:
                    # the screen is grouped by station, so "leads" = within the first two station cards
                    lead_stations = list(dict.fromkeys(v['station'] for v in vis))[:2]
                    fav_slots += 1
                    fav_leads += any(v['rec_num'] in favorites for v in vis if v['station'] in lead_stations)
        out[persona] = {
            'recommended_precision': rec_hits / recommended if recommended else float('nan'),
            'recommended_per_day': recommended / len(fx.dates),
            'relevant_visible': rel_visible / relevant if relevant else float('nan'),
            'favorite_leads': fav_leads / fav_slots if fav_slots else float('nan'),
            'mean_appeal': float(np.mean(appeals)),
        }
    return out


def recommended_by_favorite_count(fx, ranker, counts=(1, 4, 10, 25, 50), dates=('9/15/2026', '9/22/2026')):
    """Recommended tags per day for users with N random favorites: should stay small at every N."""
    mains = sorted(r for r in fx.embeddings if fx.gold[r]['role'] == 'main')
    out = {}
    for n in counts:
        favorites = random.Random(n).sample(mains, n)
        feeds = [run_feed(fx, ranker, d, 'labels', favorites) for d in dates]
        out[n] = sum('Recommended' in i['tags'] for feed in feeds for i in feed) / len(dates)
    return out


def check(fx, mode):
    """Threshold failures for the current ranker (empty list = pass)."""
    card = feed_scorecard(fx, current_ranker, mode)
    gates = THRESHOLDS[mode]
    failures = [f'{mode}: {k} = {card[k]:.3f} exceeds {gates[k]}' for k in ('junk_visible', 'junk_top3')
                if card[k] > gates[k]]
    failures += [f'{mode}: {k} = {card[k]:.3f} below {gates[k]}' for k in ('mean_appeal', 'ndcg', 'great_visible')
                 if card[k] < gates[k]]
    return failures


def _print_feed_row(label, c):
    print(f'{label:26} junk {c["junk_visible"]:5.1%} | junk in top-3 {c["junk_top3"]:5.1%} | appeal {c["mean_appeal"]:.2f} | '
          f'nDCG {c["ndcg"]:.3f} | great mains on screen {c["great_visible"]:5.1%} | their stations {c["great_stations_visible"]:5.1%} | '
          f'{c["dishes"]:.1f} dishes / {c["stations_visible"]:.1f} stations')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--baseline', help='path to another ranker.py to compare against')
    ap.add_argument('--show', metavar='DATE', help='print the visible guest feed for one date, e.g. 9/22/2026')
    args = ap.parse_args()
    fx = Fixture()

    if args.show:
        feed = run_feed(fx, current_ranker, args.show)
        for hall, meal in slots_of(feed):
            print(f'\n== hall {hall} · {meal}')
            for v in visible(feed, hall, meal):
                g = fx.gold[v['rec_num']]
                print(f'   {v["station"][:24]:24} {g["role"][:4]}/{g["appeal"]}  {str(v["tags"]):26} {v["name"]}')
        return

    rankers = [('current', current_ranker, False)]
    if args.baseline:
        rankers.insert(0, ('baseline', load_ranker(args.baseline), True))

    print(f'FEED QUALITY — guest, {len(fx.dates)} days, graded on what the home screen shows')
    for name, module, legacy in rankers:
        if name == 'baseline':
            _print_feed_row('baseline', feed_scorecard(fx, module, 'labels', legacy))
            continue
        _print_feed_row('current', feed_scorecard(fx, module, 'labels'))
        _print_feed_row('current, brand-new foods', feed_scorecard(fx, module, 'cold-start'))
        _print_feed_row('current, on the old app', feed_scorecard(fx, module, 'labels', legacy_client=True))

    print('\nPERSONALIZATION — favorite 4 foods of a kind, measure the rest of that kind')
    print(f'{"":34} {"Recommended":>12} {"tags/day":>9} {"relevant":>9} {"favorite":>9}')
    print(f'{"":34} {"precision":>12} {"":>9} {"visible":>9} {"leads":>9}')
    for name, module, legacy in rankers:
        cards = persona_scorecard(fx, module, 'labels', legacy)
        for persona, c in cards.items():
            print(f'{name + " · " + persona:34} {c["recommended_precision"]:12.1%} {c["recommended_per_day"]:9.1f} '
                  f'{c["relevant_visible"]:9.1%} {c["favorite_leads"]:9.1%}')
        mean = {k: float(np.nanmean([c[k] for c in cards.values()])) for k in next(iter(cards.values()))}
        print(f'{name + " · MEAN":34} {mean["recommended_precision"]:12.1%} {mean["recommended_per_day"]:9.1f} '
              f'{mean["relevant_visible"]:9.1%} {mean["favorite_leads"]:9.1%}\n')

    by_count = recommended_by_favorite_count(fx, current_ranker)
    print('Recommended tags/day by number of (random) favorites: ' + ', '.join(f'{n} favs → {v:.1f}' for n, v in by_count.items()) + '\n')

    failures = [f for mode in THRESHOLDS for f in check(fx, mode)]
    print('GATES: ' + ('all passed' if not failures else 'FAILED\n  ' + '\n  '.join(failures)))
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
