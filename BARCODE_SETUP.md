# Food logging and navigation

## Setup

1. FoodAPIConfiguration.contact is configured with the developer's monitored email for the Open Food Facts User-Agent. Keep it current. No API key is required.
2. For development API checks, set baseURL to https://world.openfoodfacts.net. The service supplies the documented staging credentials. Switch to https://world.openfoodfacts.org for real package lookups; staging coverage differs.
3. Review https://openfoodfacts.github.io/openfoodfacts-server/api/ and complete its API usage form before distributing Tally. In-app links credit contributors, ODbL database, Database Contents License, and CC BY-SA images.
4. Select the Tally scheme. For iPhone, select your team under Signing & Capabilities and a bundle identifier registered to that team. Enable Developer Mode on the iPhone if Xcode requests it. The camera usage description is already configured.
5. Run with Command-R. Do not delete an existing installation to test migration: install over it and verify historical entries and goals remain.

## Testing in Xcode

Select TallyTests and an iPhone Simulator, then choose Product > Test (Command-U). Its explicit dependency builds the app automatically, including on a clean checkout. Tests use URLProtocol mock responses and an in-memory SwiftData store; they do not call Open Food Facts. They also cover extreme progress values, goal validation and precision, DST day filtering, current and historical timestamps, cache expiration, offline fallback, and storage failures. The original tests cover v3.6 decoding, reported energy, kJ conversion, missing nutrients, invalid quantities, liquids, servings without gram weight, UPC normalization, one-shot scan gating, cache reuse, diary persistence, edit/delete, HTTP failures, rate limits, and timeout handling.

The Simulator supports manual barcode entry. VisionKit camera scanning requires a supported physical iPhone.

## Food name search

The bottom bar has five buttons: Today, Diary, +, Foods, and Goals. Today shows the calorie and macro dashboard; Diary focuses on dated entries; Foods contains saved food definitions; Goals edits daily targets. The central + opens a sheet with Search foods and Scan a barcode. Adding from Today or Diary keeps that screen's selected date. Adding from Foods or Goals uses today.

Choose + > Search foods, enter a food name or brand, and tap the arrow (or Search on the keyboard). Suggested foods run a search when tapped. Results show product photos, names, and brands in separate cards. Tap a result to load its nutrition, choose a portion, and add it to the diary. Search displays up to 25 matches; use a more specific name or brand to narrow results. Matching saved foods filter locally as you type and can be reused offline. The Foods tab searches all saved definitions.

Choose + > Scan a barcode to open the camera. Unsupported devices, including Simulator, offer manual barcode entry. Search and barcode entry can also be switched within the Add Food sheet. Manual nutrition entry remains available in both modes. Long-press a recently used food in search to refresh its nutrition.

Search runs only when submitted. It uses Open Food Facts' documented `/cgi/search.pl` keyword endpoint for product identity, because the v2/v3 product APIs do not support full-text queries. The selected result goes through the existing v3.6 lookup and cache, so search does not introduce a second nutrition decoder. The keyword endpoint is legacy; Open Food Facts recommends Search-a-licious for future integrations, and discovery can migrate separately from nutrition lookup when that service is adopted.

Search has a separate conservative limit of eight requests per minute and honors HTTP 429 Retry-After. Changing the query, clearing it, cancelling, or closing the sheet cancels pending searches and discards their responses. Loading, no matches, and failed requests have visible states; retry and manual entry remain available.

References checked for this implementation: [Open Food Facts API usage and rate limits](https://openfoodfacts.github.io/openfoodfacts-server/api/), [keyword search availability](https://openfoodfacts.github.io/openfoodfacts-server/api/ref-cheatsheet/), [Apple search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields), [tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), and [sheet sizing](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)). The center + is a separate action in the custom bottom bar; it presents a sheet rather than selecting an empty tab.

Verification on 2026-11-12: the redesigned app and test bundle compile, and all 19 tests pass in the iOS 26.5 Simulator, including search decoding/deduplication, safe thumbnail URLs, encoded queries, selected-result nutrition lookup, request limits, HTTP failures, and cancellation. Live staging search returned 25 results for “oats” and loaded gram/serving nutrition. Visual and interaction checks in the installed Simulator app confirmed the five-button bar, the + chooser, the search landing screen, photo result cards for a live production “Rice” search, navigation to Rice Krispies nutrition, saved-food display, a historical diary date in the chooser, scanner launch, and the manual barcode fallback. A separate live query returned HTTP 503 and displayed the retry state correctly. No diary entries were added during these checks. Physical-camera scanning, large Dynamic Type, and goal-save interaction still need manual acceptance checks.

## Manual acceptance checks

- Choose + > Search foods, search a food name, select a result, and add a portion. Verify the chosen day's totals and recent foods update. Try a brand, no matches, retry after failure, clearing the field, editing during a search, and closing while loading.
- Choose a date in Diary, then + > Scan a barcode, grant camera access, and scan a package. Hold it in view: only one lookup should occur.
- Compare product and nutrition with the package. Enter 150 grams. A product containing 20 g protein per 100 g should show 30 g.
- Add to Diary; confirm the selected day's ring, macro bars, and list update. Navigate away and back, then relaunch to verify persistence.
- Edit the diary entry. Label calories remain explicit; update them when changing macros, or clear the calories field to use the 4/4/9 estimate. Editing nutrition removes the original portion description.
- Delete the test entry; check goals and other history remain.
- Open Foods or Recently used in search and reuse a food. Repeat in airplane mode; cached definitions work offline, although images may not.
- Try an unknown barcode, incomplete product, lost network, camera denial, cancellation, and background/foreground transitions. Each should offer a useful fallback.
- For an 8-digit code entered manually, select UPC-E only if the package uses that symbology. Camera recognition identifies UPC-E automatically.
- Long-press a recently used food in search and choose Refresh nutrition to replace its saved definition. Old diary entries must retain their original consumed values.

## How it works

BarcodeScannerView wraps VisionKit with UIViewControllerRepresentable. Its coordinator receives barcode callbacks, accepts one valid result, and stops the camera. Permission and availability checks occur before presenting it; teardown cancels startup and stops scanning.

FoodAPIService is an actor using URLSession and async/await. Codable response types read the v3.6 nutrition.aggregated_set and input_sets schema. Numeric strings are accepted; missing, invalid, bounded, or unsupported-unit nutrients remain unknown. As-sold nutrition is used. Grams and milliliters are separate; no density or serving weight is guessed. Energy comes from reported kcal or kJ, with a visibly labeled macro estimate only when all three macros exist.

Food is an immutable value definition. FoodPortion contains nutrition per gram, milliliter, or serving. FoodDetailView scales it by a validated positive quantity; all required nutrients must be present before logging.

SavedFood persists an encoded definition separately from MacroEntry. FoodStore reuses definitions for seven days, then automatically refreshes them. If a refresh fails because of connectivity or temporary server problems, normal lookup can use the saved definition with a visible warning; explicit refresh reports the error. Cache-write failures do not prevent logging a successfully fetched food. Cached definitions display their fetch date and remain available offline. It does not alter or merge external food datasets. Diary entries store consumed values, barcode, portion, source, and energy provenance.

MacroEntry adds only optional properties so older entries keep their existing 4/4/9 energy behavior. No persistent store is reset. Existing-store migration still needs an upgrade acceptance check on a copy of real data.

SwiftUI @State owns transient screen state. @Query observes persisted entries for dashboard updates. @Model makes records persistent. Optional Double values distinguish unknown nutrients from actual zero. Structured concurrency supports cancellation without blocking the UI.

## Limits

- No favorites, prepared-food selector, density guessing, or label editing in the shared food cache.
- Recently used shows the latest five saved foods; name/brand filtering and the Foods tab search all saved definitions. Older definitions also remain usable by barcode.
- Definitions expire after seven days. An offline fallback displays the saved date and asks the user to verify the package.
- The rate guard limits this process to 15 product requests/minute and honors HTTP 429 Retry-After. Other apps on the same IP may still consume the provider's shared allowance.
- The developer contact is configured. Automated tests verify the default User-Agent using mocked requests; physical-camera behavior still needs acceptance checks.
- Existing-store migration, physical-camera scanning, goal-save interaction, and large Dynamic Type remain manual acceptance checks. Current build, test, and interaction results are recorded above.
- ENABLE_DEBUG_DYLIB is disabled for the app so the hosted test bundle can resolve app symbols with this project configuration. This may limit the newest preview execution mode; normal app builds remain supported.
