#!/usr/bin/env bash
# Re-record API fixtures from ororo.tv and scrub them.
# Requires ORORO_EMAIL and ORORO_PASSWORD in the environment. Never commit raw recordings.
set -euo pipefail

: "${ORORO_EMAIL:?set ORORO_EMAIL}"
: "${ORORO_PASSWORD:?set ORORO_PASSWORD}"

BASE="https://ororo.tv/api/v2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Packages/OroroKit/Tests/OroroTestSupport/Fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() { curl -fsS -u "$ORORO_EMAIL:$ORORO_PASSWORD" "$BASE/$1" -o "$TMP/$2"; }

fetch shows shows.json
fetch movies movies.json

# MobLand show detail, one of its episodes, and Dune; ids are resolved from the lists by name.
SHOW_ID="$(python3 -I -c 'import json,sys;print(next(s["id"] for s in json.load(open(sys.argv[1]))["shows"] if s["name"]=="MobLand"))' "$TMP/shows.json")"
MOVIE_ID="$(python3 -I -c 'import json,sys;print(next(m["id"] for m in json.load(open(sys.argv[1]))["movies"] if m["name"].startswith("Dune")))' "$TMP/movies.json")"
fetch "shows/$SHOW_ID" mobland.json
EP_ID="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["episodes"][0]["id"])' "$TMP/mobland.json")"
fetch "episodes/$EP_ID" ep.json
fetch "movies/$MOVIE_ID" dune.json

python3 -I "$ROOT/Scripts/trim_fixtures.py" "$TMP" "$OUT"
echo "Fixtures written to $OUT"
