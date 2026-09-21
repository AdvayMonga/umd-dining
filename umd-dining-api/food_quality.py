"""
food_quality.py — What kind of food is this, and how appealing is it?

Every food gets a role (main, side, dessert, bread, component, condiment,
beverage) and an appeal score (1-5). Known foods are looked up in the
LLM-judged label file; unseen foods fall back to a small linear model over
hashed name/station/serving features. Pure numpy, no network, no DB.

Regenerate the model with evals/train_quality_model.py.
"""

import json
import logging
import os
import re
import zlib

import numpy as np

_DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
LABELS_PATH = os.path.join(_DATA_DIR, 'food_labels.json')
MODEL_PATH = os.path.join(_DATA_DIR, 'quality_model.npz')

N_FEATURES = 2 ** 15

# Toppings and condiments never enter the feed. Plain staples (bagels, cereal, milk) don't
# either, but a bread or drink the judge found appealing (garlic bread, naan) counts as a dish.
JUNK_ROLES = frozenset({'component', 'condiment'})
STAPLE_ROLES = frozenset({'bread', 'beverage'})
STAPLE_MIN_APPEAL = 4


def is_junk(role, appeal):
    return role in JUNK_ROLES or (role in STAPLE_ROLES and appeal < STAPLE_MIN_APPEAL)


def _tokens(name, station, serving):
    """Yield string features for one food."""
    words = re.findall(r'[a-z0-9]+', (name or '').lower())
    for w in words:
        yield 'w:' + w
        padded = f' {w} '
        for n in (3, 4, 5):
            for i in range(len(padded) - n + 1):
                yield 'c:' + padded[i:i + n]
    for a, b in zip(words, words[1:], strict=False):
        yield f'b:{a}_{b}'
    if words:
        yield 'first:' + words[0]
        yield 'last:' + words[-1]
    yield f'n:{min(len(words), 4)}'

    station_words = re.findall(r'[a-z]+', (station or '').lower())
    for w in station_words:
        yield 's:' + w
    yield 'S:' + ' '.join(station_words)

    m = re.match(r'\s*([\d.]+)\s*([a-z]+)', (serving or '').lower())
    if m:
        unit = m.group(2)
        yield 'u:' + unit
        if unit in ('oz', 'ounce', 'ounces'):
            try:
                amount = float(m.group(1))
            except ValueError:
                amount = 0.0
            yield 'oz:' + ('1' if amount <= 1 else '2' if amount <= 2 else '4' if amount <= 4 else 'big')


def featurize(name, station='', serving=''):
    """Hashed, L2-normalized feature vector as (indices, values)."""
    idx = sorted({zlib.crc32(t.encode()) % N_FEATURES for t in _tokens(name, station, serving)})
    indices = np.asarray(idx, dtype=np.int64)
    values = np.full(len(idx), 1.0 / np.sqrt(max(len(idx), 1)), dtype=np.float32)
    return indices, values


class QualityModel:
    """Judge labels first, linear model for anything unlabeled."""

    def __init__(self, labels=None, weights=None):
        self.labels = labels or {}
        self.weights = weights
        self._cache = {}

    @classmethod
    def load(cls, labels_path=LABELS_PATH, model_path=MODEL_PATH):
        labels = {}
        if os.path.exists(labels_path):
            with open(labels_path) as fh:
                labels = json.load(fh)
        weights = None
        if os.path.exists(model_path):
            with np.load(model_path) as z:
                weights = {k: z[k].astype(np.float32) if z[k].dtype.kind == 'f' else z[k] for k in z.files}
        if not labels or weights is None:
            # without these every food looks like a 3/5 main and the junk gate is off
            logging.getLogger(__name__).warning('food quality data missing: labels=%d, model=%s', len(labels), weights is not None)
        return cls(labels, weights)

    def predict(self, name, station='', serving=''):
        """Model-only prediction: (role, appeal)."""
        if self.weights is None:
            return 'main', 3.0
        idx, val = featurize(name, station, serving)
        w = self.weights
        role_scores = w['role_coef'][:, idx] @ val + w['role_intercept']
        role = str(w['roles'][int(np.argmax(role_scores))])
        appeal = float(w['appeal_coef'][idx] @ val + w['appeal_intercept'])
        return role, min(5.0, max(1.0, appeal))

    def get(self, rec_num, food, station=''):
        """(role, appeal) for a food doc, preferring the judge label."""
        label = self.labels.get(rec_num)
        if label:
            return label['role'], float(label['appeal'])
        key = (rec_num, station)
        if key not in self._cache:
            serving = (food.get('nutrition') or {}).get('Serving Size', '')
            self._cache[key] = self.predict(food.get('name', ''), station, serving)
        return self._cache[key]


_default = None


def get_quality(rec_num, food, station=''):
    """Module-level accessor backed by a lazily loaded default model."""
    global _default
    if _default is None:
        _default = QualityModel.load()
    return _default.get(rec_num, food, station)
