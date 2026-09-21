"""
Refresh evals/fixture from a snapshot directory (read-only data, no user ids).

    python evals/make_fixture.py <snapshot_dir>

<snapshot_dir> holds menus.json, foods.json, emb.npy, emb_ids.json and
engagement.json as dumped from MongoDB. Frequencies are filled in the way the
fixed scraper writes them (every meal-period row gets the count).
"""

import collections
import gzip
import json
import os
import sys

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fixture')
EMB_DIMS = 256  # text-embedding-3 vectors stay meaningful when truncated


def main(src):
    menus = json.load(open(f'{src}/menus.json'))
    foods = json.load(open(f'{src}/foods.json'))
    on_menu = {m['rec_num'] for m in menus}

    dates = collections.defaultdict(set)
    for m in menus:
        dates[(m['dining_hall_id'], m['rec_num'], m['station'])].add(m['date'])
    slim_menus = [{
        'date': m['date'], 'dining_hall_id': m['dining_hall_id'], 'meal_period': m['meal_period'],
        'rec_num': m['rec_num'], 'station': m['station'], 'dietary_icons': m.get('dietary_icons', []),
        'frequency': len(dates[(m['dining_hall_id'], m['rec_num'], m['station'])]),
    } for m in menus]

    keep = ('Serving Size', 'Calories', 'Protein')
    slim_foods = [{
        'rec_num': f['rec_num'], 'name': f.get('name', ''),
        'nutrition': {k: v for k, v in (f.get('nutrition') or {}).items() if k in keep},
    } for f in foods if f['rec_num'] in on_menu]

    ids = json.load(open(f'{src}/emb_ids.json'))
    emb = np.nan_to_num(np.load(f'{src}/emb.npy'))
    rows = [i for i, r in enumerate(ids) if r in on_menu]
    emb = emb[rows, :EMB_DIMS]
    emb /= np.linalg.norm(emb, axis=1, keepdims=True) + 1e-10

    eng = json.load(open(f'{src}/engagement.json'))
    engagement = {
        'favorites': {d['_id']: d['n'] for d in eng['favs'] if d['_id'] in on_menu},
        'views': {d['_id']: d['n'] for d in eng['views'] if d['_id'] in on_menu},
    }

    for name, obj in (('menus', slim_menus), ('foods', slim_foods), ('engagement', engagement)):
        with gzip.open(f'{OUT}/{name}.json.gz', 'wt') as fh:
            json.dump(obj, fh, separators=(',', ':'))
    np.savez_compressed(f'{OUT}/embeddings.npz', rec_nums=np.array([ids[i] for i in rows]), vectors=emb.astype(np.float16))
    print(f'{len(slim_menus)} menu rows, {len(slim_foods)} foods, {len(rows)} embeddings -> {OUT}')


if __name__ == '__main__':
    main(sys.argv[1])
