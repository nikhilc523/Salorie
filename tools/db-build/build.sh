#!/usr/bin/env bash
# Salorie food-catalog build pipeline.
# Download datasets (download.sh for USDA; OFF via curl), then run this.
# Produces out/salorie_foods.sqlite: per-100g nutrients + portions + FTS5 search.
#
# Sources (each optional — globs decide what's included):
#   USDA Foundation + SR Legacy  → generic lab foods (source_priority 0/1)
#   USDA Branded (US)            → US barcodes        (source_priority 2)
#   Open Food Facts (US)         → global barcodes    (source_priority 3)
#
# Cross-source barcode dedup: USDA Branded wins over OFF.
# Sanity clamps drop/na physically-impossible values (bad manufacturer data).
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")"

OUT="out/salorie_foods.sqlite"
mkdir -p out out/duck_tmp
rm -f "$OUT" "$OUT-wal" "$OUT-shm"

BRANDED_GLOB=$(ls data/*/*/branded_food.csv 2>/dev/null | head -1 || true)
OFF_GLOB=$(ls data/off/*.csv.gz 2>/dev/null | head -1 || true)

# ---- Branded block ---------------------------------------------------------
if [[ -n "$BRANDED_GLOB" ]]; then
  echo "▸ Branded present (barcodes)."
  BRANDED_SQL=$(cat <<'SQL'
CREATE TEMP VIEW branded_src AS
  SELECT * FROM read_csv_auto('data/*/*/branded_food.csv', header=true, sample_size=-1, ignore_errors=true);
CREATE TEMP TABLE foods_branded AS
WITH b0 AS (
  SELECT f.fdc_id, f.description AS name,
    COALESCE(NULLIF(TRIM(b.brand_name), ''), b.brand_owner) AS brand,
    CASE WHEN regexp_full_match(CAST(b.gtin_upc AS VARCHAR), '\d{8,14}')
         THEN lpad(CAST(b.gtin_upc AS VARCHAR), 14, '0') END AS barcode,
    b.serving_size, b.serving_size_unit, b.household_serving_fulltext,
    b.branded_food_category AS category, b.ingredients, b.modified_date
  FROM food f JOIN branded_src b ON b.fdc_id = f.fdc_id
  WHERE f.data_type = 'branded_food' AND b.market_country IN ('United States','US') AND f.description IS NOT NULL
),
b1 AS (SELECT *, row_number() OVER (PARTITION BY barcode ORDER BY modified_date DESC NULLS LAST) rn FROM b0 WHERE barcode IS NOT NULL)
SELECT
  'usda:' || b1.fdc_id AS id, 'USDA Branded' AS source, 2 AS source_priority,
  b1.name, b1.brand, b1.barcode,
  COALESCE(n.kcal_1008,n.kcal_2048,n.kcal_2047) AS kcal_100,
  n.carbs AS carbs_100, n.protein AS protein_100, n.fat AS fat_100, n.fibre AS fibre_100,
  COALESCE(n.sugars_2000,n.sugars_1063) AS sugars_100, n.satfat AS satfat_100, n.sodium AS sodium_100, n.chol AS chol_100,
  n.potassium AS potassium_100, n.calcium AS calcium_100, n.iron AS iron_100, n.magnesium AS magnesium_100, n.zinc AS zinc_100,
  n.vit_d AS vit_d_100, n.vit_c AS vit_c_100, n.vit_a AS vit_a_100, n.vit_b12 AS vit_b12_100, n.folate AS folate_100,
  n.caffeine AS caffeine_100, n.added_sugars AS added_sugars_100, n.trans_fat AS trans_fat_100, n.mono_fat AS mono_fat_100, n.poly_fat AS poly_fat_100,
  CAST(NULL AS VARCHAR) AS nutri_score, CAST(NULL AS INTEGER) AS nova_group,
  CASE WHEN TRY_CAST(b1.serving_size AS DOUBLE) > 0 THEN TRY_CAST(b1.serving_size AS DOUBLE) ELSE 100 END AS default_serving_g,
  COALESCE(NULLIF(TRIM(b1.household_serving_fulltext),''),
           CASE WHEN TRY_CAST(b1.serving_size AS DOUBLE) > 0
                THEN CAST(ROUND(TRY_CAST(b1.serving_size AS DOUBLE)) AS BIGINT)||' '||COALESCE(b1.serving_size_unit,'g') ELSE '100 g' END) AS serving_text,
  b1.category, b1.ingredients
FROM b1 JOIN nut n ON n.fdc_id = b1.fdc_id
WHERE b1.rn = 1 AND COALESCE(n.kcal_1008,n.kcal_2048,n.kcal_2047) IS NOT NULL;
SQL
)
  PRIOR_SQL="CREATE TEMP TABLE prior_barcodes AS SELECT barcode FROM foods_branded WHERE barcode IS NOT NULL;"
  UNION_SQL="SELECT * FROM foods_generic UNION ALL SELECT * FROM foods_branded"
else
  echo "▸ Branded absent."
  BRANDED_SQL=""
  PRIOR_SQL="CREATE TEMP TABLE prior_barcodes(barcode VARCHAR);"
  UNION_SQL="SELECT * FROM foods_generic"
fi

# ---- Open Food Facts block -------------------------------------------------
if [[ -n "$OFF_GLOB" ]]; then
  echo "▸ Open Food Facts present (US filter)."
  OFF_SQL=$(cat <<'SQL'
CREATE TEMP TABLE foods_off AS
WITH o0 AS (
  SELECT
    code,
    NULLIF(TRIM(product_name),'') AS name,
    NULLIF(TRIM(split_part(brands, ',', 1)),'') AS brand,
    lpad(code, 14, '0') AS barcode,
    TRY_CAST("energy-kcal_100g" AS DOUBLE) AS kcal,
    TRY_CAST("carbohydrates_100g" AS DOUBLE) AS carbs,
    TRY_CAST("proteins_100g" AS DOUBLE) AS protein,
    TRY_CAST("fat_100g" AS DOUBLE) AS fat,
    TRY_CAST("fiber_100g" AS DOUBLE) AS fibre,
    TRY_CAST("sugars_100g" AS DOUBLE) AS sugars,
    TRY_CAST("saturated-fat_100g" AS DOUBLE) AS satfat,
    COALESCE(TRY_CAST("sodium_100g" AS DOUBLE)*1000, TRY_CAST("salt_100g" AS DOUBLE)/2.5*1000) AS sodium,
    TRY_CAST("cholesterol_100g" AS DOUBLE)*1000 AS chol,
    TRY_CAST("potassium_100g" AS DOUBLE)*1000 AS potassium,
    TRY_CAST("calcium_100g" AS DOUBLE)*1000 AS calcium,
    TRY_CAST("iron_100g" AS DOUBLE)*1000 AS iron,
    TRY_CAST("magnesium_100g" AS DOUBLE)*1000 AS magnesium,
    TRY_CAST("zinc_100g" AS DOUBLE)*1000 AS zinc,
    TRY_CAST("vitamin-c_100g" AS DOUBLE)*1000 AS vit_c,
    TRY_CAST("caffeine_100g" AS DOUBLE)*1000 AS caffeine,
    CASE WHEN lower(nutriscore_grade) IN ('a','b','c','d','e') THEN upper(nutriscore_grade) END AS nutri_score,
    CASE WHEN TRY_CAST(nova_group AS INTEGER) BETWEEN 1 AND 4 THEN TRY_CAST(nova_group AS INTEGER) END AS nova_group,
    TRY_CAST(completeness AS DOUBLE) AS completeness,
    NULLIF(TRIM(serving_size),'') AS serving_size,
    TRY_CAST(serving_quantity AS DOUBLE) AS serving_q
  FROM read_csv('data/off/*.csv.gz', delim='\t', header=true, quote='', all_varchar=true, ignore_errors=true)
  WHERE countries_tags LIKE '%united-states%'
    AND regexp_full_match(code, '\d{8,14}')
    AND TRY_CAST("energy-kcal_100g" AS DOUBLE) IS NOT NULL
    AND NULLIF(TRIM(product_name),'') IS NOT NULL
),
o1 AS (SELECT *, row_number() OVER (PARTITION BY barcode ORDER BY completeness DESC NULLS LAST) rn FROM o0)
SELECT
  'off:' || o1.code AS id, 'Open Food Facts' AS source, 3 AS source_priority,
  o1.name, o1.brand, o1.barcode,
  o1.kcal AS kcal_100, o1.carbs AS carbs_100, o1.protein AS protein_100, o1.fat AS fat_100, o1.fibre AS fibre_100,
  o1.sugars AS sugars_100, o1.satfat AS satfat_100, o1.sodium AS sodium_100, o1.chol AS chol_100,
  o1.potassium AS potassium_100, o1.calcium AS calcium_100, o1.iron AS iron_100, o1.magnesium AS magnesium_100, o1.zinc AS zinc_100,
  CAST(NULL AS DOUBLE) AS vit_d_100, o1.vit_c AS vit_c_100, CAST(NULL AS DOUBLE) AS vit_a_100, CAST(NULL AS DOUBLE) AS vit_b12_100, CAST(NULL AS DOUBLE) AS folate_100,
  o1.caffeine AS caffeine_100, CAST(NULL AS DOUBLE) AS added_sugars_100, CAST(NULL AS DOUBLE) AS trans_fat_100, CAST(NULL AS DOUBLE) AS mono_fat_100, CAST(NULL AS DOUBLE) AS poly_fat_100,
  o1.nutri_score, o1.nova_group,
  CASE WHEN o1.serving_q > 0 THEN o1.serving_q ELSE 100 END AS default_serving_g,
  COALESCE(o1.serving_size, CASE WHEN o1.serving_q > 0 THEN CAST(ROUND(o1.serving_q) AS BIGINT)||' g' ELSE '100 g' END) AS serving_text,
  CAST(NULL AS VARCHAR) AS category, CAST(NULL AS VARCHAR) AS ingredients
FROM o1
WHERE o1.rn = 1 AND o1.barcode NOT IN (SELECT barcode FROM prior_barcodes);
SQL
)
  UNION_SQL="$UNION_SQL UNION ALL SELECT * FROM foods_off"
else
  echo "▸ Open Food Facts absent."
  OFF_SQL=""
fi

echo "▸ Building with DuckDB…"
duckdb <<SQL
INSTALL sqlite; LOAD sqlite;
SET memory_limit='8GB';
SET temp_directory='out/duck_tmp';

CREATE TEMP VIEW food          AS SELECT * FROM read_csv_auto('data/*/*/food.csv', header=true, sample_size=-1, union_by_name=true);
CREATE TEMP VIEW food_nutrient AS
  SELECT CAST(fdc_id AS BIGINT) AS fdc_id, CAST(nutrient_id AS BIGINT) AS nutrient_id, TRY_CAST(amount AS DOUBLE) AS amount
  FROM read_csv_auto('data/*/*/food_nutrient.csv', header=true, union_by_name=true,
       types={'fdc_id':'BIGINT','nutrient_id':'BIGINT','amount':'DOUBLE'});
CREATE TEMP VIEW food_portion  AS SELECT * FROM read_csv_auto('data/*/*/food_portion.csv', header=true, sample_size=-1, union_by_name=true);
CREATE TEMP VIEW measure_unit  AS SELECT id, ANY_VALUE(name) AS name FROM read_csv_auto('data/*/*/measure_unit.csv', header=true, union_by_name=true) GROUP BY id;
CREATE TEMP VIEW food_category AS SELECT id, ANY_VALUE(description) AS description FROM read_csv_auto('data/*/*/food_category.csv', header=true, union_by_name=true) GROUP BY id;

CREATE TEMP TABLE nut AS
SELECT fdc_id,
  MAX(amount) FILTER (WHERE nutrient_id=1008) AS kcal_1008,
  MAX(amount) FILTER (WHERE nutrient_id=2048) AS kcal_2048,
  MAX(amount) FILTER (WHERE nutrient_id=2047) AS kcal_2047,
  MAX(amount) FILTER (WHERE nutrient_id=1005) AS carbs,
  MAX(amount) FILTER (WHERE nutrient_id=1003) AS protein,
  MAX(amount) FILTER (WHERE nutrient_id=1004) AS fat,
  MAX(amount) FILTER (WHERE nutrient_id=1079) AS fibre,
  MAX(amount) FILTER (WHERE nutrient_id=2000) AS sugars_2000,
  MAX(amount) FILTER (WHERE nutrient_id=1063) AS sugars_1063,
  MAX(amount) FILTER (WHERE nutrient_id=1258) AS satfat,
  MAX(amount) FILTER (WHERE nutrient_id=1093) AS sodium,
  MAX(amount) FILTER (WHERE nutrient_id=1253) AS chol,
  MAX(amount) FILTER (WHERE nutrient_id=1092) AS potassium,
  MAX(amount) FILTER (WHERE nutrient_id=1087) AS calcium,
  MAX(amount) FILTER (WHERE nutrient_id=1089) AS iron,
  MAX(amount) FILTER (WHERE nutrient_id=1090) AS magnesium,
  MAX(amount) FILTER (WHERE nutrient_id=1095) AS zinc,
  MAX(amount) FILTER (WHERE nutrient_id=1114) AS vit_d,
  MAX(amount) FILTER (WHERE nutrient_id=1162) AS vit_c,
  MAX(amount) FILTER (WHERE nutrient_id=1106) AS vit_a,
  MAX(amount) FILTER (WHERE nutrient_id=1178) AS vit_b12,
  MAX(amount) FILTER (WHERE nutrient_id=1177) AS folate,
  MAX(amount) FILTER (WHERE nutrient_id=1057) AS caffeine,
  MAX(amount) FILTER (WHERE nutrient_id=1235) AS added_sugars,
  MAX(amount) FILTER (WHERE nutrient_id=1257) AS trans_fat,
  MAX(amount) FILTER (WHERE nutrient_id=1292) AS mono_fat,
  MAX(amount) FILTER (WHERE nutrient_id=1293) AS poly_fat
FROM food_nutrient GROUP BY fdc_id;

CREATE TEMP TABLE portions AS
SELECT fp.fdc_id, fp.seq_num,
  NULLIF(TRIM(CONCAT_WS(' ',
    CASE WHEN fp.amount IS NULL THEN NULL WHEN fp.amount = FLOOR(fp.amount) THEN CAST(CAST(fp.amount AS BIGINT) AS VARCHAR) ELSE CAST(ROUND(fp.amount,2) AS VARCHAR) END,
    CASE WHEN mu.name IS NULL OR mu.name='undetermined' THEN NULL ELSE mu.name END,
    COALESCE(NULLIF(TRIM(fp.portion_description),''), NULLIF(TRIM(fp.modifier),'')))), '') AS label,
  fp.gram_weight
FROM food_portion fp LEFT JOIN measure_unit mu ON mu.id = fp.measure_unit_id
WHERE fp.gram_weight IS NOT NULL AND fp.gram_weight > 0;

CREATE TEMP TABLE default_portion AS
SELECT fdc_id, gram_weight AS default_g, label FROM (
  SELECT *, row_number() OVER (PARTITION BY fdc_id ORDER BY seq_num NULLS LAST) rn FROM portions
) WHERE rn = 1;

CREATE TEMP TABLE foods_generic AS
SELECT
  'usda:' || f.fdc_id AS id,
  CASE f.data_type WHEN 'foundation_food' THEN 'USDA Foundation' WHEN 'sr_legacy_food' THEN 'SR Legacy' END AS source,
  CASE f.data_type WHEN 'foundation_food' THEN 0 WHEN 'sr_legacy_food' THEN 1 END AS source_priority,
  f.description AS name, CAST(NULL AS VARCHAR) AS brand, CAST(NULL AS VARCHAR) AS barcode,
  COALESCE(n.kcal_1008,n.kcal_2048,n.kcal_2047) AS kcal_100,
  n.carbs AS carbs_100, n.protein AS protein_100, n.fat AS fat_100, n.fibre AS fibre_100,
  COALESCE(n.sugars_2000,n.sugars_1063) AS sugars_100, n.satfat AS satfat_100, n.sodium AS sodium_100, n.chol AS chol_100,
  n.potassium AS potassium_100, n.calcium AS calcium_100, n.iron AS iron_100, n.magnesium AS magnesium_100, n.zinc AS zinc_100,
  n.vit_d AS vit_d_100, n.vit_c AS vit_c_100, n.vit_a AS vit_a_100, n.vit_b12 AS vit_b12_100, n.folate AS folate_100,
  n.caffeine AS caffeine_100, n.added_sugars AS added_sugars_100, n.trans_fat AS trans_fat_100, n.mono_fat AS mono_fat_100, n.poly_fat AS poly_fat_100,
  CAST(NULL AS VARCHAR) AS nutri_score, CAST(NULL AS INTEGER) AS nova_group,
  COALESCE(dp.default_g, 100) AS default_serving_g,
  CASE WHEN dp.default_g IS NOT NULL THEN COALESCE(dp.label,'serving')||' ('||CAST(ROUND(dp.default_g) AS BIGINT)||' g)' ELSE '100 g' END AS serving_text,
  fc.description AS category, CAST(NULL AS VARCHAR) AS ingredients
FROM food f
JOIN nut n ON n.fdc_id = f.fdc_id
LEFT JOIN default_portion dp ON dp.fdc_id = f.fdc_id
LEFT JOIN food_category fc ON fc.id = f.food_category_id
WHERE f.data_type IN ('foundation_food','sr_legacy_food')
  AND COALESCE(n.kcal_1008,n.kcal_2048,n.kcal_2047) IS NOT NULL AND f.description IS NOT NULL;

$BRANDED_SQL
$PRIOR_SQL
$OFF_SQL

CREATE TEMP TABLE foods_all AS $UNION_SQL;

-- Sanity clamps: drop physically-impossible energy; NULL impossible per-100g values.
CREATE TEMP TABLE foods_clean AS
SELECT
  id, source, source_priority, name, brand, barcode, kcal_100,
  CASE WHEN carbs_100    > 100   THEN NULL ELSE carbs_100    END AS carbs_100,
  CASE WHEN protein_100  > 100   THEN NULL ELSE protein_100  END AS protein_100,
  CASE WHEN fat_100      > 100   THEN NULL ELSE fat_100      END AS fat_100,
  CASE WHEN fibre_100    > 100   THEN NULL ELSE fibre_100    END AS fibre_100,
  CASE WHEN sugars_100   > 100   THEN NULL ELSE sugars_100   END AS sugars_100,
  CASE WHEN satfat_100   > 100   THEN NULL ELSE satfat_100   END AS satfat_100,
  CASE WHEN sodium_100   > 42000 THEN NULL ELSE sodium_100   END AS sodium_100,
  CASE WHEN chol_100     > 5000  THEN NULL ELSE chol_100     END AS chol_100,
  CASE WHEN potassium_100> 20000 THEN NULL ELSE potassium_100 END AS potassium_100,
  CASE WHEN calcium_100  > 10000 THEN NULL ELSE calcium_100  END AS calcium_100,
  CASE WHEN iron_100     > 1000  THEN NULL ELSE iron_100     END AS iron_100,
  CASE WHEN magnesium_100> 5000  THEN NULL ELSE magnesium_100 END AS magnesium_100,
  CASE WHEN zinc_100     > 500   THEN NULL ELSE zinc_100     END AS zinc_100,
  vit_d_100,
  CASE WHEN vit_c_100    > 5000  THEN NULL ELSE vit_c_100    END AS vit_c_100,
  vit_a_100, vit_b12_100, folate_100,
  CASE WHEN caffeine_100 > 8000  THEN NULL ELSE caffeine_100 END AS caffeine_100,
  CASE WHEN added_sugars_100 > 100 THEN NULL ELSE added_sugars_100 END AS added_sugars_100,
  CASE WHEN trans_fat_100 > 100  THEN NULL ELSE trans_fat_100 END AS trans_fat_100,
  CASE WHEN mono_fat_100  > 100  THEN NULL ELSE mono_fat_100  END AS mono_fat_100,
  CASE WHEN poly_fat_100  > 100  THEN NULL ELSE poly_fat_100  END AS poly_fat_100,
  nutri_score, nova_group, default_serving_g, serving_text, category, ingredients
FROM foods_all
WHERE kcal_100 IS NOT NULL AND kcal_100 > 0 AND kcal_100 <= 902;

ATTACH '$OUT' AS db (TYPE SQLITE);
CREATE TABLE db.foods AS SELECT * FROM foods_clean;
CREATE TABLE db.food_portion AS
  SELECT 'usda:' || fdc_id AS food_id, seq_num AS seq, label, gram_weight AS grams
  FROM portions WHERE ('usda:' || fdc_id) IN (SELECT id FROM foods_clean);
DETACH db;

.mode box
SELECT source, COUNT(*) AS foods FROM foods_clean GROUP BY source ORDER BY foods DESC;
SELECT COUNT(*) AS total_foods FROM foods_clean;
SQL

echo "▸ Adding FTS5 + indexes via sqlite3…"
sqlite3 "$OUT" <<'SQL'
CREATE UNIQUE INDEX idx_foods_id ON foods(id);
CREATE INDEX idx_foods_barcode ON foods(barcode) WHERE barcode IS NOT NULL;
CREATE INDEX idx_portion_food ON food_portion(food_id);
CREATE VIRTUAL TABLE foods_fts USING fts5(id UNINDEXED, name, brand, tokenize='porter unicode61');
INSERT INTO foods_fts(id, name, brand) SELECT id, name, COALESCE(brand,'') FROM foods;
ANALYZE;
SQL

rm -rf out/duck_tmp
echo "▸ Done. Size: $(ls -lh "$OUT" | awk '{print $5}')  →  $OUT"
