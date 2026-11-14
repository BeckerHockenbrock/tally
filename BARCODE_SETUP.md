# Tally: local nutrition tracking

Tally stores diary entries, goals, custom foods, and scanned products in SwiftData on the phone. Managed CloudKit sync is disabled. There is no account or backend. Product photos are not fetched, so opening saved foods does not make image requests.

## Common foods

`Tally/CommonFoods.json` bundles 52 everyday foods from USDA FoodData Central SR Legacy (2018). Each food has one familiar name and a small native emoji illustration: Pasta, White Rice, Brown Rice, Chicken Breast, and other staples. Search and the food library show these simple choices instead of USDA varieties, salt levels, or preparation duplicates. A short subtitle identifies the preparation to weigh (for example, cooked pasta and rice). Nutrition comes from that specific source record; variants are not averaged together.

All reported nutrient values are retained, including vitamins, minerals, amino acids, and fatty acids. Missing values remain unknown. The original USDA description and source ID are kept with the food for traceability. Search in Add Food and Your foods is entirely local. Saved products and custom foods appear alongside the bundled foods and get a matching emoji when recognizable, or a plate icon otherwise. Bundled foods never expire. Gram portions use USDA values per 100 g; where USDA provides a portion weight, a labeled serving is also available.

To regenerate the bundle, download the [USDA SR Legacy CSV ZIP](https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip), then run:

```
python3 scripts/import_usda.py /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
```

The importer contains the explicit source IDs, simple names, icons, preparation subtitles, and nutrient mappings. It requires only Python's standard library. USDA data is public domain / CC0. Source: U.S. Department of Agriculture, Agricultural Research Service, FoodData Central, SR Legacy (2018).

## Barcode lookup and retention

- Scanning first checks local storage; only an unknown/expired barcode calls Open Food Facts.
- The first scan saves the product. Each successful diary addition updates its last-use time, using the current logging time even if the diary date is historical.
- Viewing a food or refreshing a definition does not renew its retention period. The Barcode screen offers an explicit Refresh this barcode online action.
- Products expire three calendar months after first scan or last diary addition. Expired definitions are removed on launch, foregrounding, and barcode lookup; they are excluded from food lists immediately.
- An expired barcode needs an online lookup again. There is no periodic seven-day refresh.
- Custom foods stay until explicitly deleted. Manual barcode corrections saved as custom foods also stay until deleted.
- Deleting or expiring a reusable food never deletes diary entries. Each entry stores its own consumed nutrition snapshot.

`FoodAPIConfiguration.contact` supplies the monitored developer email in the Open Food Facts User-Agent. No API key is required. Keep this address current. The production base URL is `https://world.openfoodfacts.org`; staging is `https://world.openfoodfacts.net` (the service supplies staging authentication). Check the provider's API usage requirements before distribution.

The service uses v3.6 `nutrition.aggregated_set` / `input_sets`, preserves as-sold versus prepared distinctions, scales reported values, normalizes g/mg/µg, and retains vitamin IU separately from mass-based forms. Unsupported or bounded values such as `< 1 mg` remain unknown. API requests are limited to 15 per minute and honor Retry-After.

## Nutrient tracking

Today and Diary link to daily vitamins, minerals, and other nutrient totals. A partial total indicates how many diary entries reported that nutrient. A known zero is different from an unknown value. Vitamin A RAE, unqualified label vitamin A, IU, total folate, and folate DFE remain distinct; they are not summed as interchangeable forms.

Food Details shows portion-scaled macros and expandable nutrient details. Manual entry supports optional nutrient amounts and a Save to my foods switch; the entire entry becomes one reusable serving. Editing an entry preserves its reported micronutrients, including source metadata for unchanged values. Legacy entries remain readable but have unknown micronutrients because those values were never recorded.

## Build and tests

Open `Tally.xcodeproj`. Select the Tally scheme and an iPhone Simulator, then Run. For a physical iPhone, select your signing team and enable Developer Mode if requested. The camera permission description is configured. VisionKit camera scanning needs a supported physical device; Simulator supports typed barcodes.

Select TallyTests and run Product > Test. Tests use isolated SwiftData stores and mocked URLSession responses. They cover offline library loading, staple search, portion scaling, micro unit normalization, missing versus zero values, partial totals, calendar-month expiration, retention renewal only on logging, custom-food retention, history preservation, legacy payload decoding, save rollback, and the existing barcode, goal, and diary behavior.

Install over an existing app to check migration; do not uninstall an existing app containing valued history. New diary nutrient snapshots use an optional field to permit lightweight migration.

Manual checks:

1. Search rice offline and confirm only White Rice and Brown Rice appear. Search pasta and confirm one Pasta choice. Check the preparation subtitle, log 150 grams, and inspect daily nutrients.
2. Scan or type a new product barcode online; reopen it offline and log another serving.
3. Create a named custom food with micronutrients and Save to my foods enabled; reuse it offline.
4. Edit a diary entry, change a nutrient amount, and verify the daily total; blank a field and verify it becomes unknown.
5. Delete a saved food and confirm historical diary amounts remain.
6. Check a physical camera scan, camera denial, large Dynamic Type, and background/foreground behavior.

## References

- [USDA downloads](https://fdc.nal.usda.gov/download-datasets/)
- [USDA food and nutrient documentation](https://fdc.nal.usda.gov/Foundation_Foods_Documentation/)
- [USDA licensing](https://fdc.nal.usda.gov/api-guide/)
- [Open Food Facts API](https://openfoodfacts.github.io/openfoodfacts-server/api/)
- [Open Food Facts nutrient taxonomy](https://github.com/openfoodfacts/openfoodfacts-server/blob/main/taxonomies/nutrients.txt)
- [Open Food Facts local caching](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/creating-a-local-cache-of-open-food-facts-data/)
- [FDA nutrition label coverage](https://www.fda.gov/food/nutrition-facts-label/daily-value-nutrition-and-supplement-facts-labels)
- [Apple: disable managed CloudKit sync](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct/none)

## Verification before library simplification (2026-11-12)

The final app and test bundle built successfully for the iPhone 17 Pro Simulator (iOS 26.5). All 27 tests passed, including migration from an on-disk pre-nutrient schema with existing diary entries, goals, and saved foods. The bundle contains 165 foods and 142 distinct additional nutrient fields across those foods. Simulator UI checks confirmed local search, food detail navigation, 150 g portion scaling, and expanded nutrient rows distinguishing reported zero from unknown. No diary entries were added during UI checks. Physical-camera scanning and live barcode API responses were not exercised in this verification.

## Simplified library verification (2026-11-12)

The library now contains 52 uniquely named foods, with exactly one Pasta and two rice choices (White Rice and Brown Rice). Each has a local emoji illustration and preparation subtitle. The final Simulator build and all 27 tests pass, including assertions for these choices, nutrient scaling, legacy payload decoding, and database migration. Visual checks confirmed the simplified picker, names, preparation subtitles, and food icons. Existing diary snapshots are unaffected by changing the bundled catalog.
