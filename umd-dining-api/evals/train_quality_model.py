"""
Train the fallback quality model from data/food_labels.json.

Dev-only (needs scikit-learn + scipy, see evals/requirements.txt):
    python evals/train_quality_model.py

Prints 5-fold cross-validated agreement with the judge, writes out-of-fold
predictions to evals/oof_predictions.json (used by run_eval.py --cold-start),
then fits on everything and exports data/quality_model.npz.
"""

import json
import os
import sys

import numpy as np
from scipy.sparse import csr_matrix
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.model_selection import StratifiedKFold

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from food_quality import LABELS_PATH, MODEL_PATH, N_FEATURES, featurize, is_junk  # noqa: E402

OOF_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'oof_predictions.json')


def build_matrix(rows):
    indptr, indices, data = [0], [], []
    for r in rows:
        idx, val = featurize(r['name'], r['station'], r['serving'])
        indices.extend(idx)
        data.extend(val)
        indptr.append(len(indices))
    return csr_matrix((data, indices, indptr), shape=(len(rows), N_FEATURES), dtype=np.float32)


def fit(X, roles, appeal):
    clf = LogisticRegression(max_iter=5000, C=50, class_weight='balanced').fit(X, roles)
    reg = Ridge(alpha=0.3).fit(X, appeal)
    return clf, reg


def main():
    with open(LABELS_PATH) as fh:
        labels = json.load(fh)
    rec_nums = sorted(labels)
    rows = [labels[r] for r in rec_nums]
    X = build_matrix(rows)
    roles = np.array([r['role'] for r in rows])
    appeal = np.array([r['appeal'] for r in rows], dtype=float)

    pred_role = np.empty(len(rows), dtype=object)
    pred_appeal = np.zeros(len(rows))
    for train, test in StratifiedKFold(5, shuffle=True, random_state=0).split(X, roles):
        clf, reg = fit(X[train], roles[train], appeal[train])
        pred_role[test] = clf.predict(X[test])
        pred_appeal[test] = np.clip(reg.predict(X[test]), 1, 5)

    junk = np.array([is_junk(r, a) for r, a in zip(roles, appeal, strict=True)])
    pred_junk = np.array([is_junk(r, a) for r, a in zip(pred_role, pred_appeal, strict=True)])
    good = ~junk & (appeal >= 4)
    print(f'foods: {len(rows)}')
    print(f'role agreement with judge:        {(pred_role == roles).mean():.3f}')
    print(f'junk leaking into the feed:       {(junk & ~pred_junk).sum() / junk.sum():.3f}')
    print(f'good dishes wrongly called junk:  {(good & pred_junk).sum() / good.sum():.3f}')
    print(f'appeal correlation / MAE:         {np.corrcoef(pred_appeal, appeal)[0, 1]:.3f} / {np.abs(pred_appeal - appeal).mean():.2f}')

    with open(OOF_PATH, 'w') as fh:
        json.dump({r: {'role': pred_role[i], 'appeal': round(float(pred_appeal[i]), 2)}
                   for i, r in enumerate(rec_nums)}, fh, indent=0)

    clf, reg = fit(X, roles, appeal)
    np.savez_compressed(
        MODEL_PATH,
        roles=np.array(clf.classes_),
        role_coef=clf.coef_.astype(np.float16),
        role_intercept=clf.intercept_.astype(np.float32),
        appeal_coef=reg.coef_.astype(np.float16),
        appeal_intercept=np.float32(reg.intercept_),
    )
    print(f'wrote {MODEL_PATH} ({os.path.getsize(MODEL_PATH) / 1024:.0f} KB) and {OOF_PATH}')


if __name__ == '__main__':
    main()
