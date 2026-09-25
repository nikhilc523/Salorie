#!/usr/bin/env bash
# End-to-end validation of out/salorie_foods.sqlite.
set -euo pipefail
cd "$(dirname "$0")"
DB=out/salorie_foods.sqlite
q() { sqlite3 -header -column "$DB" "$1"; }
line() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

line "SQLite integrity_check";           sqlite3 "$DB" "PRAGMA integrity_check;"
line "Row counts by source";             q "SELECT source, source_priority AS prio, COUNT(*) n FROM foods GROUP BY source, source_priority ORDER BY n DESC;"
line "Data-quality invariants (all 0)";  q "SELECT
     (SELECT COUNT(*) FROM foods WHERE kcal_100 IS NULL) AS null_kcal,
     (SELECT COUNT(*) FROM foods WHERE name IS NULL OR name='') AS null_name,
     (SELECT COUNT(*) FROM (SELECT id FROM foods GROUP BY id HAVING COUNT(*)>1)) AS dup_ids,
     (SELECT COUNT(*) FROM (SELECT barcode FROM foods WHERE barcode IS NOT NULL GROUP BY barcode HAVING COUNT(*)>1)) AS dup_barcodes;"
line "SANITY CLAMPS — impossible values (all 0)"; q "SELECT
     (SELECT COUNT(*) FROM foods WHERE kcal_100>902) AS kcal_gt_902,
     (SELECT COUNT(*) FROM foods WHERE caffeine_100>8000) AS caff_gt_8000,
     (SELECT COUNT(*) FROM foods WHERE carbs_100>100 OR protein_100>100 OR fat_100>100 OR fibre_100>100) AS macro_gt_100,
     (SELECT COUNT(*) FROM foods WHERE sodium_100>42000) AS sodium_huge;"
line "SOURCE-PRIORITY RANKING — 'avocado' (generic must come first)"
                                         q "SELECT f.name, f.source FROM foods_fts x JOIN foods f ON f.id=x.id WHERE foods_fts MATCH 'avocado' ORDER BY f.source_priority, rank LIMIT 6;"
line "Same query WITHOUT priority (shows why we need it)"
                                         q "SELECT f.name, f.source FROM foods_fts x JOIN foods f ON f.id=x.id WHERE foods_fts MATCH 'avocado' ORDER BY rank LIMIT 4;"
line "Nutrient sanity: banana raw (ref ~89 kcal, ~358mg K)"
                                         q "SELECT name, ROUND(kcal_100) kcal, ROUND(potassium_100) K_mg, ROUND(vit_c_100,1) vitC FROM foods WHERE name LIKE 'Bananas, raw%' LIMIT 1;"
line "Caffeine top 5 (max must be ≤8000 now)"; q "SELECT name, ROUND(caffeine_100) caff FROM foods WHERE caffeine_100>0 ORDER BY caffeine_100 DESC LIMIT 5;"
line "OPEN FOOD FACTS — sample with Nutri-Score / NOVA badges"
                                         q "SELECT substr(name,1,34) name, substr(brand,1,14) brand, nutri_score ns, nova_group nova, barcode FROM foods WHERE source='Open Food Facts' AND nutri_score IS NOT NULL AND nova_group IS NOT NULL LIMIT 6;"
line "OFF barcode resolves + is unique across sources"
                                         q "SELECT source, COUNT(*) n FROM foods WHERE barcode=(SELECT barcode FROM foods WHERE source='Open Food Facts' LIMIT 1) GROUP BY source;"
line "Nutri-Score / NOVA coverage (OFF rows)"; q "SELECT COUNT(*) off_rows, COUNT(nutri_score) with_nutriscore, COUNT(nova_group) with_nova FROM foods WHERE source='Open Food Facts';"
line "DB size";                          ls -lh "$DB" | awk '{print $5"  "$9}'
