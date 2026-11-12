# Barcode food logging

## Setup

1. FoodAPIConfiguration.contact is configured with the developer's monitored email for the Open Food Facts User-Agent. Keep it current. No API key is required.
2. For development API checks, set baseURL to https://world.openfoodfacts.net. The service supplies the documented staging credentials. Switch to https://world.openfoodfacts.org for real package lookups; staging coverage differs.
3. Review https://openfoodfacts.github.io/openfoodfacts-server/api/ and complete its API usage form before distributing Tally. In-app links credit contributors, ODbL database, Database Contents License, and CC BY-SA images.
4. Select the Tally scheme. For iPhone, select your team under Signing & Capabilities and a bundle identifier registered to that team. Enable Developer Mode on the iPhone if Xcode requests it. The camera usage description is already configured.
5. Run with Command-R. Do not delete an existing installation to test migration: install over it and verify historical entries and goals remain.

## Testing in Xcode

Select TallyTests and an iPhone Simulator, then choose Product > Test (Command-U). Its explicit dependency builds the app automatically, including on a clean checkout. Tests use URLProtocol mock responses and an in-memory SwiftData store; they do not call Open Food Facts. They also cover extreme progress values, goal validation and precision, DST day filtering, current and historical timestamps, cache expiration, offline fallback, and storage failures. The original tests cover v3.6 decoding, reported energy, kJ conversion, missing nutrients, invalid quantities, liquids, servings without gram weight, UPC normalization, one-shot scan gating, cache reuse, diary persistence, edit/delete, HTTP failures, rate limits, and timeout handling.

The Simulator supports manual barcode entry. VisionKit camera scanning requires a supported physical iPhone.

## Manual acceptance checks

- Choose a date, Add Entry > Scan Barcode, grant camera access, and scan a package. Hold it in view: only one lookup should occur.
- Compare product and nutrition with the package. Enter 150 grams. A product containing 20 g protein per 100 g should show 30 g.
- Add to Diary; confirm the selected day's ring, macro bars, and list update. Navigate away and back, then relaunch to verify persistence.
- Edit the diary entry. Label calories remain explicit; update them when changing macros, or clear the calories field to use the 4/4/9 estimate. Editing nutrition removes the original portion description.
- Delete the test entry; check goals and other history remain.
- Reopen Add Entry and reuse a Recent Food. Repeat in airplane mode; cached definitions work offline, although images may not.
- Try an unknown barcode, incomplete product, lost network, camera denial, cancellation, and background/foreground transitions. Each should offer a useful fallback.
- For an 8-digit code entered manually, select UPC-E only if the package uses that symbology. Camera recognition identifies UPC-E automatically.
- Use Refresh from Open Food Facts to replace a saved definition. Old diary entries must retain their original consumed values.

## How it works

BarcodeScannerView wraps VisionKit with UIViewControllerRepresentable. Its coordinator receives barcode callbacks, accepts one valid result, and stops the camera. Permission and availability checks occur before presenting it; teardown cancels startup and stops scanning.

FoodAPIService is an actor using URLSession and async/await. Codable response types read the v3.6 nutrition.aggregated_set and input_sets schema. Numeric strings are accepted; missing, invalid, bounded, or unsupported-unit nutrients remain unknown. As-sold nutrition is used. Grams and milliliters are separate; no density or serving weight is guessed. Energy comes from reported kcal or kJ, with a visibly labeled macro estimate only when all three macros exist.

Food is an immutable value definition. FoodPortion contains nutrition per gram, milliliter, or serving. FoodDetailView scales it by a validated positive quantity; all required nutrients must be present before logging.

SavedFood persists an encoded definition separately from MacroEntry. FoodStore reuses definitions for seven days, then automatically refreshes them. If a refresh fails because of connectivity or temporary server problems, normal lookup can use the saved definition with a visible warning; explicit refresh reports the error. Cache-write failures do not prevent logging a successfully fetched food. Cached definitions display their fetch date and remain available offline. It does not alter or merge external food datasets. Diary entries store consumed values, barcode, portion, source, and energy provenance.

MacroEntry adds only optional properties so older entries keep their existing 4/4/9 energy behavior. No persistent store is reset. Existing-store migration still needs an upgrade acceptance check on a copy of real data.

SwiftUI @State owns transient screen state. @Query observes persisted entries for dashboard updates. @Model makes records persistent. Optional Double values distinguish unknown nutrients from actual zero. Structured concurrency supports cancellation without blocking the UI.

## Limits

- No favorites, prepared-food selector, density guessing, or label editing in the shared food cache.
- The recent list shows the latest 30 saved foods; older definitions remain usable by barcode.
- Definitions expire after seven days. An offline fallback displays the saved date and asks the user to verify the package.
- The rate guard limits this process to 15 product requests/minute and honors HTTP 429 Retry-After. Other apps on the same IP may still consume the provider's shared allowance.
- The developer contact is configured. Automated tests verify the default User-Agent using mocked requests; live API and physical-camera behavior still need acceptance checks.
- Verification on 2026-11-12: the iOS app and test bundle compile, and the optimized Release build succeeds. All 16 model and regression tests pass in the iOS 26.5 Simulator and in a temporary macOS package using the same source and test files. Existing-store migration, dashboard interaction, and camera behavior remain manual acceptance checks.
- ENABLE_DEBUG_DYLIB is disabled for the app so the hosted test bundle can resolve app symbols with this project configuration. This may limit the newest preview execution mode; normal app builds remain supported.
