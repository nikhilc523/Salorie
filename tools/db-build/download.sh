#!/usr/bin/env bash
# Download the USDA FoodData Central CSV datasets Salorie builds from (all CC0).
# Idempotent: skips a dataset whose CSVs are already unzipped.
#
# Release pinned to 2026-04-30 (latest as of build). To bump: check
# https://fdc.nal.usda.gov/download-datasets and update RELEASE / SR_LEGACY.
#
# Open Food Facts US (~1.2 GB gzip, ~8.7 GB uncompressed but DuckDB STREAMS the
# .gz — it is never unzipped to disk). Set WITH_OFF=0 to skip it.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

BASE="https://fdc.nal.usda.gov/fdc-datasets"
RELEASE="2026-04-30"
SR_LEGACY="2018-04"

fetch() { # name url
  local name="$1" url="$2"
  if ls "data/$name"/*/food.csv >/dev/null 2>&1; then
    echo "▸ $name already unzipped — skipping."
    return
  fi
  echo "▸ Downloading $name…"
  curl -fL --retry 3 --max-time 1800 -o "data/$name.zip" "$url"
  echo "  unzipping…"
  rm -rf "data/$name" && mkdir -p "data/$name"
  unzip -oq "data/$name.zip" -d "data/$name"
}

fetch foundation "$BASE/FoodData_Central_foundation_food_csv_$RELEASE.zip"
fetch sr_legacy  "$BASE/FoodData_Central_sr_legacy_food_csv_$SR_LEGACY.zip"
fetch branded    "$BASE/FoodData_Central_branded_food_csv_$RELEASE.zip"

# Open Food Facts (ODbL) — a single gzip DuckDB streams; not unzipped.
if [[ "${WITH_OFF:-1}" == "1" ]]; then
  if [[ -f data/off/products.csv.gz ]]; then
    echo "▸ OFF already downloaded — skipping."
  else
    echo "▸ Downloading Open Food Facts (~1.2 GB)…"
    mkdir -p data/off
    curl -fL --retry 3 --max-time 3600 -o data/off/products.csv.gz \
      "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
  fi
fi

echo "▸ Done. Now run ./build.sh"
