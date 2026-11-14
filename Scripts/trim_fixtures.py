#!/usr/bin/env python3
"""Trim and scrub raw ororo.tv API recordings into test fixtures.

Usage: python3 -I Scripts/trim_fixtures.py <in-dir> <out-dir>

In-dir names: shows.json, movies.json, mobland.json, ep.json, dune.json
Out names:    shows.json, movies.json, show.json, episode.json, movie.json
"""
import json
import os
import sys

PLACEHOLDER = "https://example.invalid/stream.m3u8?wmsAuthSign=PLACEHOLDER"
URL_KEYS = {"url", "download_url"}
KEEP = 200
TOP = 100
MIN_NULL_BACKDROP = 3


def is_subtitle_entry(d):
    return "lang" in d and str(d.get("url", "")).split("?")[0].endswith(".vtt")


def scrub(v):
    """Recursively replace playback URLs; subtitle .vtt URLs are kept."""
    if isinstance(v, dict):
        sub = is_subtitle_entry(v)
        out = {}
        for k, x in v.items():
            if k in URL_KEYS and isinstance(x, str) and not (sub and k == "url"):
                out[k] = PLACEHOLDER
            else:
                out[k] = scrub(x)
        return out
    if isinstance(v, list):
        return [scrub(x) for x in v]
    if isinstance(v, str) and "wmsAuthSign=" in v:
        return PLACEHOLDER
    return v


def select(items, key):
    """Top TOP by `key` (descending) plus evenly spaced items from the rest, KEEP total."""
    ranked = sorted(range(len(items)), key=lambda i: (-(items[i].get(key) or 0), i))
    top = set(ranked[:TOP])
    rest = [i for i in range(len(items)) if i not in top]
    n = KEEP - TOP
    step = len(rest) / n
    picked = {rest[int(j * step)] for j in range(n)}
    # Guarantee some null backdrops (placeholder-artwork coverage).
    have = sum(1 for i in top | picked if items[i].get("backdrop_url") is None)
    if have < MIN_NULL_BACKDROP:
        extra = [i for i in rest if i not in picked and items[i].get("backdrop_url") is None]
        drop = [i for i in sorted(picked) if items[i].get("backdrop_url") is not None]
        for add, rem in zip(extra[: MIN_NULL_BACKDROP - have], drop):
            picked.discard(rem)
            picked.add(add)
    return [items[i] for i in sorted(top | picked)]


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def dump(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main(src, dst):
    os.makedirs(dst, exist_ok=True)
    shows = load(os.path.join(src, "shows.json"))
    shows["shows"] = select(shows["shows"], "user_popularity")
    dump(os.path.join(dst, "shows.json"), scrub(shows))
    movies = load(os.path.join(src, "movies.json"))
    movies["movies"] = select(movies["movies"], "imdb_rating")
    dump(os.path.join(dst, "movies.json"), scrub(movies))
    for s, d in (("mobland.json", "show.json"), ("ep.json", "episode.json"), ("dune.json", "movie.json")):
        dump(os.path.join(dst, d), scrub(load(os.path.join(src, s))))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
