"""
ranker.py — Feed ranking and recommendation logic.

All scoring is pure logic: no DB access. The caller (routes.py) fetches
all required data and passes it in.

Pipeline: gate out junk (toppings, condiments, plain staples) →
score = appeal prior + rarity + personal signals + student interest →
per dining hall and meal, up to 3 dishes per station, the best 20 flagged
'featured' for the home screen. Scores are in appeal points (1-5).
Quality of the whole thing is measured by evals/run_eval.py.
"""

import math
import re
import zlib

import numpy as np

from food_quality import get_quality, is_junk

# --- Score weights (appeal points) ---
W_MAIN = 0.5             # mains headline over sides
W_DESSERT = -0.5         # desserts show up, but below real dishes
W_RARITY = 0.8           # rotating special vs. daily staple
W_FAVORITE = 4.0
W_FAVORITE_EXTRA = 1.5   # favorites past the first MAX_FULL_FAVORITES in a slot
W_FAV_STATION = 0.6
W_TRENDING = 0.5
W_PREF_MATCH = 0.6
W_VIEWED = 0.2           # doubled at 3+ personal views
W_STUDENTS = 2.4         # ceiling for student interest; see STUDENT_EVIDENCE_K
W_AFFINITY = 1.6         # per point of taste affinity, capped
W_HIGH_PROTEIN = 0.2
W_PREFERRED_HALL = 10.0  # only affects cross-hall order
W_JITTER = 0.3           # date-seeded, rotates near-ties day to day

MAX_FULL_FAVORITES = 5
PER_SLOT = 30
PER_STATION = 3          # dishes per station card (one more for favorite stations)
FEATURED_BUDGET = 20     # dishes the home screen leads with, per hall and meal
FEATURED_MIN_APPEAL = 3  # weaker dishes wait behind See More unless favorited
FREQUENCY_WINDOW = 14    # days of menus the scraper counts frequency over
STUDENT_EVIDENCE_K = 20  # viewers of the top dish at which student interest reaches half strength
HIGH_PROTEIN_GRAMS = 15
AFFINITY_Z_CUT = 2.0     # similarity must beat the menu average by this many std-devs to count
AFFINITY_CAP = 2.5
RECOMMENDED_AFFINITY = 1.5
SIMILAR_FALLBACK = 0.65  # raw cosine that counts as similar when the menu is too small for z-scores


def _parse_number(value):
    """Extract the first number from a nutrition string like '32g' or '450'."""
    if not value:
        return None
    try:
        return float(''.join(c for c in str(value) if c.isdigit() or c == '.'))
    except Exception:
        return None


def get_protein(nutrition):
    for key in ('Protein', 'Total Protein', 'protein'):
        val = _parse_number(nutrition.get(key))
        if val is not None:
            return val
    return None


def _affinity(candidates, foods, anchors):
    """
    Map rec_num -> taste affinity. Similarity is z-scored per anchor against
    today's menu, and only the excess over AFFINITY_Z_CUT is summed, so an item
    close to several favorites (a shared theme) beats one that merely shares an
    ingredient with a single favorite. Dividing by sqrt(anchors) keeps the scale
    the same for a user with 2 favorites and a user with 50.
    """
    if not anchors:
        return {}
    dim = len(anchors[0])
    anchors = [a for a in anchors if len(a) == dim]
    rec_nums = [r for r in candidates if len(foods.get(r, {}).get('embedding') or ()) == dim]
    if not rec_nums:
        return {}
    items = np.nan_to_num(np.asarray([foods[r]['embedding'] for r in rec_nums], dtype=np.float32))
    anch = np.nan_to_num(np.asarray(anchors, dtype=np.float32))
    items /= np.linalg.norm(items, axis=1, keepdims=True) + 1e-10
    anch /= np.linalg.norm(anch, axis=1, keepdims=True) + 1e-10
    sims = items @ anch.T  # (n_items, n_anchors)

    std = sims.std(axis=0)
    if len(rec_nums) >= 10 and np.all(std > 1e-6):
        excess = np.clip((sims - sims.mean(axis=0)) / std - AFFINITY_Z_CUT, 0, None)
    else:
        excess = np.where(sims >= SIMILAR_FALLBACK, RECOMMENDED_AFFINITY * math.sqrt(len(anchors)), 0.0)
    return dict(zip(rec_nums, (excess.sum(axis=1) / math.sqrt(len(anchors))).tolist(), strict=True))


def rank_items(
    menu_entries,
    foods,
    fav_rec_nums,
    fav_stations,
    user_prefs,
    popular_rec_nums,
    date_seed,
    fav_embeddings=None,
    user_views=None,
    global_views=None,
    preferred_halls=None,
    quality=get_quality,
):
    """
    Score, tag, and sort menu items for the feed.

    Args:
        menu_entries:      list of dicts from db.menus
        foods:             dict mapping rec_num -> food doc from db.foods
        fav_rec_nums:      set of rec_nums the user has favorited
        fav_stations:      set of station names the user has favorited
        user_prefs:        dict with keys 'vegetarian' (bool), 'vegan' (bool)
        popular_rec_nums:  set of rec_nums trending across all users (by favorites)
        date_seed:         string seeding the daily tie-break jitter
        fav_embeddings:    taste anchors: embeddings of favorites and cuisine centroids
        user_views:        dict mapping rec_num -> view count for this user
        global_views:      dict mapping rec_num -> distinct students who viewed it
        preferred_halls:   dining_hall_ids the user prefers
        quality:           callable (rec_num, food, station) -> (role, appeal)

    Returns:
        list of item dicts with 'tag'/'tags'/'featured', best first within each
        dining hall and meal period, each rec_num once per hall and meal.
    """
    is_vegetarian = user_prefs.get('vegetarian', False)
    is_vegan = user_prefs.get('vegan', False)
    user_views = user_views or {}
    global_views = global_views or {}
    preferred_halls = preferred_halls or []
    # Student interest counts for more as the app gathers evidence: a tiebreaker while the
    # most-viewed dish has a handful of viewers, able to outweigh the appeal prior at ~100.
    top_viewers = max(global_views.values(), default=0)
    student_weight = W_STUDENTS * top_viewers / (top_viewers + STUDENT_EVIDENCE_K)

    # --- Gate: junk never enters the feed unless the user favorited it ---
    candidates = []
    for entry in menu_entries:
        rec_num = entry['rec_num']
        food = foods.get(rec_num, {})
        if not food.get('name'):
            continue  # menu row whose food doc hasn't been scraped yet
        role, appeal = quality(rec_num, food, entry.get('station', ''))
        if is_junk(role, appeal) and rec_num not in fav_rec_nums:
            continue
        candidates.append((entry, food, role, appeal))

    affinity = _affinity({e['rec_num'] for e, _, _, _ in candidates}, foods, fav_embeddings)

    scored = []
    for entry, food, role, appeal in candidates:
        rec_num = entry['rec_num']
        # Merge sides with parent station (e.g. "Grill Sides" → "Grill"), the name the app shows and favorites
        station = re.sub(r'\s+Sides?\s*$', '', entry.get('station', ''), flags=re.IGNORECASE)
        dietary_icons = entry.get('dietary_icons', [])
        is_fav = rec_num in fav_rec_nums
        tags = []

        score = appeal
        if role == 'main':
            score += W_MAIN
        elif role == 'dessert':
            score += W_DESSERT

        # Rarity: a missing frequency is neutral, never a "special"
        frequency = entry.get('frequency')
        rarity = 0.5 if frequency is None else 1 - min(frequency, FREQUENCY_WINDOW) / FREQUENCY_WINDOW
        score += W_RARITY * rarity

        if is_fav:
            score += W_FAVORITE
            tags.append('Favorite')
        if station in fav_stations:
            score += W_FAV_STATION
        if rec_num in popular_rec_nums:
            score += W_TRENDING
            tags.append('Trending')
        if (is_vegan and 'vegan' in dietary_icons) or (is_vegetarian and 'vegetarian' in dietary_icons):
            score += W_PREF_MATCH

        personal_views = user_views.get(rec_num, 0)
        if personal_views:
            score += W_VIEWED * (2 if personal_views >= 3 else 1)
        if top_viewers:
            score += student_weight * math.log1p(global_views.get(rec_num, 0)) / math.log1p(top_viewers)

        taste = affinity.get(rec_num, 0.0)
        score += W_AFFINITY * min(taste, AFFINITY_CAP)
        if taste >= RECOMMENDED_AFFINITY and not is_fav:
            tags.append('Recommended')

        protein = get_protein(food.get('nutrition') or {})
        if protein is not None and protein >= HIGH_PROTEIN_GRAMS and role in ('main', 'side'):
            score += W_HIGH_PROTEIN
            tags.append('High Protein')

        if entry.get('dining_hall_id') in preferred_halls:
            score += W_PREFERRED_HALL
        # crc32, not hash(): hash() is randomized per process
        score += W_JITTER * zlib.crc32(f'{date_seed}:{rec_num}'.encode()) / 2 ** 32

        scored.append((score, appeal >= FEATURED_MIN_APPEAL or is_fav, {
            'name': food.get('name', ''),
            'rec_num': rec_num,
            'dining_hall_id': entry['dining_hall_id'],
            'date': entry['date'],
            'meal_period': entry.get('meal_period', 'Unknown'),
            'station': station or 'Unknown',
            'dietary_icons': dietary_icons,
            'tag': tags[0] if tags else None,
            'tags': tags,
        }))

    # --- Per slot (hall + meal): dedupe, soften surplus favorites, cap ---
    slots = {}
    for score, worthy, item in sorted(scored, key=lambda x: -x[0]):
        slots.setdefault((item['dining_hall_id'], item['meal_period']), []).append((score, worthy, item))

    result = []
    for rows in slots.values():
        seen, fav_count, unique = set(), 0, []
        for score, worthy, item in rows:
            if item['rec_num'] in seen:
                continue
            seen.add(item['rec_num'])
            if 'Favorite' in item['tags']:
                fav_count += 1
                if fav_count > MAX_FULL_FAVORITES:
                    score -= W_FAVORITE - W_FAVORITE_EXTRA
            unique.append((score, worthy, item))
        unique.sort(key=lambda x: -x[0])

        # Cap each station card, then flag the dishes the home screen leads with
        per_station, picked, featured = {}, [], 0
        for score, worthy, item in unique:
            station = item['station']
            cap = PER_STATION + 1 if station in fav_stations else PER_STATION
            if per_station.get(station, 0) < cap and len(picked) < PER_SLOT:
                per_station[station] = per_station.get(station, 0) + 1
                item['featured'] = worthy and featured < FEATURED_BUDGET
                featured += item['featured']
                picked.append((score, item))
        result.extend(picked)

    # Best first overall; within a hall and meal the order above is already by score
    result.sort(key=lambda x: -x[0])
    return [item for _, item in result]
