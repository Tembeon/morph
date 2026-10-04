import math

import numpy as np

from .analysis import origin, tracks
from .scenario import LabError


def spring(t, response, damping, delay, initial, target, velocity):
    t = np.asarray(t, dtype=float)
    elapsed = np.maximum(0, t - delay)
    omega = 2 * math.pi / response
    displacement = initial - target
    if damping < 1 - 1e-6:
        decay = damping * omega
        frequency = omega * math.sqrt(1 - damping * damping)
        value = np.exp(-decay * elapsed) * (displacement * np.cos(frequency * elapsed) + (velocity + decay * displacement) / frequency * np.sin(frequency * elapsed))
    elif damping > 1 + 1e-6:
        root = omega * math.sqrt(damping * damping - 1)
        a, b = -damping * omega + root, -damping * omega - root
        coefficient = (velocity - b * displacement) / (a - b)
        value = coefficient * np.exp(a * elapsed) + (displacement - coefficient) * np.exp(b * elapsed)
    else:
        value = np.exp(-omega * elapsed) * (displacement + (velocity + omega * displacement) * elapsed)
    return np.where(t < delay, initial, target + value)


def series(rows, track, property_name, start, end):
    offset = origin(rows)
    samples = tracks(rows).get(track, [])
    pairs = [(row["t"] - offset - start, row["values"][property_name]) for row in samples
             if start <= row["t"] - offset <= end and isinstance(row["values"].get(property_name), (int, float))]
    if len(pairs) < 20:
        raise LabError("spring fitting needs at least 20 observed samples in the selected interval")
    t, y = np.array(pairs).T
    if np.ptp(y) < 1e-6:
        raise LabError("constant geometry does not identify a spring")
    return t, y


def fit_spring(rows, track, property_name, start, end, holdout=None):
    try:
        from scipy.optimize import least_squares
    except ImportError as error:
        raise LabError("fit-spring requires scipy; install lab/requirements.txt") from error
    t, y = series(rows, track, property_name, start, end)
    span = float(np.ptp(y))
    low = [0.02, 0.05, 0, float(np.min(y) - span), float(np.min(y) - span), -span * 100]
    high = [5, 3, min(0.25, float(np.max(t)) / 3), float(np.max(y) + span), float(np.max(y) + span), span * 100]
    best = None
    for response in (0.2, 0.4, 0.8):
        initial = [response, 0.8, min(0.01, high[2] / 2), float(y[0]), float(np.median(y[-5:])), 0]
        fit = least_squares(lambda p: spring(t, *p) - y, initial, bounds=(low, high), x_scale="jac", max_nfev=1500)
        if best is None or np.sum(fit.fun ** 2) < np.sum(best.fun ** 2):
            best = fit
    names = ("response", "damping", "delay", "initial", "target", "velocity")
    parameters = dict(zip(names, (float(p) for p in best.x)))
    rank = int(np.linalg.matrix_rank(best.jac))
    residual_variance = float(np.sum(best.fun ** 2) / max(1, len(t) - len(names)))
    covariance = np.linalg.pinv(best.jac.T @ best.jac) * residual_variance
    result = {"model": "second-order step response; independent of widget implementation", "track": track, "property": property_name,
              "window": [start, end], "sampleCount": len(t), "parameters": parameters,
              "rms": float(np.sqrt(np.mean(best.fun ** 2))), "maxResidual": float(np.max(np.abs(best.fun))), "jacobianRank": rank,
              "localStandardErrors": dict(zip(names, np.sqrt(np.maximum(0, np.diag(covariance))).tolist())),
              "uncertaintyNote": "local linear estimate; correlated frames and multiple animation channels require independent recaptures",
              "boundaryParameters": [name for name, value, a, b in zip(names, best.x, low, high) if min(abs(value - a), abs(value - b)) < 1e-5],
              "samples": [{"t": float(time), "observed": float(value), "fitted": float(prediction)} for time, value, prediction in zip(t, y, spring(t, *best.x))]}
    if holdout is not None:
        ht, hy = series(holdout, track, property_name, start, end)
        result["holdout"] = {"count": len(ht), "rms": float(np.sqrt(np.mean((spring(ht, *best.x) - hy) ** 2)))}
    result["identifiableWithHoldout"] = holdout is not None and rank == len(names) and not result["boundaryParameters"]
    result["requiresReview"] = True
    return result
