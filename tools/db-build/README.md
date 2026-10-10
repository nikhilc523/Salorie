# Salorie food-catalog build pipeline

Offline pipeline that turns free public data into the read-only SQLite catalog the
app searches and scans (`FoodCatalog` in the app; GRDB in P2).

## Prereqs
- `duckdb` (`brew install duckdb`), `sqlite3` (system), `curl`, `unzip`.
- ~8 GB free disk (Branded unzips to ~2.9 GB; OFF is streamed from its 1.2 GB gzip — never unzipped).

## Run
```bash
./download.sh     # USDA Foundation + SR Legacy + Branded (CC0) + Open Food Facts US (ODbL)
                  #   WITH_OFF=0 ./download.sh   to skip OFF
./build.sh        # → out/salorie_foods.sqlite
./validate.sh     # integrity, ranking, clamps, search, barcode, nutrient sanity
```
Re-runnable. `build.sh` auto-detects Branded (`data/*/*/branded_food.csv`) and OFF
(`data/off/*.csv.gz`); with neither it builds generic-only.

## Sources & priority (lower = ranked higher in search)
| Source | License | `source_priority` | Role |
|---|---|---|---|
| USDA Foundation | CC0 | 0 | generic, lab-analyzed (richest micros) |
| USDA SR Legacy | CC0 | 1 | generic fallback |
| USDA Branded (US) | CC0 | 2 | US barcodes |
| Open Food Facts (US) | ODbL | 3 | extra barcodes + Nutri-Score/NOVA |

## Output: `out/salorie_foods.sqlite`
- `foods` — one row per food, nutrients **per 100 g**. `id` = `usda:<fdc_id>` / `off:<code>`.
  `barcode` = GTIN-14 (nullable). Core macros + extended (potassium, caffeine, vitamins…);
  `nutri_score` (A–E) + `nova_group` (1–4, OFF only); `source_priority`; missing values are
  `NULL` so the app hides those rows.
- `food_portion` — household measures (`label`, `grams`) for the serving picker.
- `foods_fts` — FTS5 (porter) over `name`+`brand`; join back on `id`.
- Indexes: unique `id`, partial `barcode`, `food_portion(food_id)`.

### Canonical search query (P2 uses this)
```sql
SELECT f.* FROM foods_fts x JOIN foods f ON f.id = x.id
WHERE foods_fts MATCH ?              -- e.g. 'avoca*'
ORDER BY f.source_priority, rank     -- generic > branded > OFF, then relevance
LIMIT 50;
```

## Data integrity
- **Cross-source barcode dedup:** one row per GTIN-14; USDA Branded wins over OFF;
  within a source the latest (Branded: `modified_date`) / most complete (OFF: `completeness`) wins.
- **Sanity clamps** remove impossible manufacturer data: drop rows with kcal/100g > 902
  (pure fat ≈ 900); NULL any macro > 100 g, sodium > 42 000 mg, caffeine > 8 000 mg, etc.
  (dropped ~19.6 k bad Branded rows in the current build).

## Current build (USDA 2026-04-30 + OFF 2026-05-26)
| Source | Foods |
|---|---|
| USDA Branded (US) | 396,245 |
| Open Food Facts (US) | 62,033 |
| SR Legacy | 7,756 |
| USDA Foundation | 377 |
| **Total** | **466,411** |

DB size **≈298 MB**. Validated: integrity ok; 0 dup ids/barcodes; 0 clamp violations;
generic ranks above branded; banana = 89 kcal / 358 mg K; barcode lookup ~1 ms.

## Licenses / attribution
- USDA FoodData Central — public domain (CC0). *U.S. Department of Agriculture, ARS. FoodData Central.*
- Open Food Facts — database under **ODbL**, contents under DbCL. Attribute:
  *"Contains data from Open Food Facts, available under the Open Database License."*
  If the app lets users add/correct products, contribute changes back via the OFF API.

`data/` and `out/` are git-ignored.
