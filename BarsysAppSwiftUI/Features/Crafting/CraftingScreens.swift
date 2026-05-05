//
//  CraftingScreens.swift
//  BarsysAppSwiftUI
//
//  1:1 port of UIKit:
//   - BarsysApp/Controllers/Crafting/CraftingViewController.swift
//   - BarsysApp/Controllers/Crafting/CraftingViewController+BleResponse.swift
//   - BarsysApp/Controllers/Crafting/CraftingViewController+TableView.swift
//   - BarsysApp/Controllers/Crafting/CraftingViewModel.swift
//   - BarsysApp/Controllers/BarBot/BarBotCraft/CraftingState.swift
//   - BarsysApp/Helpers/BleCommandBuilder.swift
//
//  The crafting flow drives the physical Barsys machine via the BLE
//  peripheral:
//
//    1. User taps "Craft" on Recipe / BarBot / Mixlist detail.
//    2. SwiftUI pushes this `CraftingView`. `onAppear` → `viewModel.start`.
//    3. start() decides device path:
//       • `Barsys 360` → load stations from server, build command string
//         `"200,s1,q1,s2,q2,…,s6,q6"` (15 components, trailing zeros if
//         fewer ingredients present) via `BleCommandBuilder`, send as
//         `.craftRaw(command: …)`.
//       • `Coaster / Shaker` → build `"200,q1,q2,…,q14"` with 14 slots
//         (remaining slots zero-filled) and send the same way.
//    4. Device broadcasts BLE events — parsed into `BleResponse` enum
//       and forwarded to `viewModel.dispatch(_:ble:)` which advances the
//       9-state `CraftingState` machine:
//         idle → waitingForGlass → dispensing → awaitingGlassRemoval →
//         completed
//       Cancel path:
//         cancelling → cancelledWaitingForGlass → cancelAcknowledged
//    5. On `dataFlushed` + `awaitingGlassRemoval` → transition to
//       `.completed` + navigate to `DrinkComplete`.
//    6. Cancel: send `.cancel` → wait for `cancelAcknowledged` +
//       `dataFlushed` → pop the nav stack.
//

import SwiftUI

// MARK: - CraftingState (1:1 with UIKit enum CraftingState)

/// Finite set of valid states during a drink crafting session.
///
/// Ports `BarsysApp/Controllers/BarBot/BarBotCraft/CraftingState.swift`
/// verbatim so the exact transitions from UIKit's
/// `CraftingViewController+BleResponse.swift` apply byte-for-byte here.
enum CraftingState: Equatable {
    /// Initial state. BLE command sent to device, waiting for device to begin.
    case idle

    /// Device requested user to place a glass (before dispensing has started).
    case waitingForGlass

    /// Actively pouring ingredients. Progress via `currentIngredient` counter.
    case dispensing

    /// Glass was lifted/removed DURING active dispensing. User must replace it.
    case glassLifted

    /// All ingredients poured (221,405 received). Waiting for user to remove glass.
    case awaitingGlassRemoval

    /// User pressed cancel, "202" command sent. Device has NOT yet acknowledged.
    case cancelling

    /// User cancelled while glass was lifted/waiting. Device has NOT yet acknowledged.
    case cancelledWaitingForGlass

    /// Device confirmed cancellation (202,401 received). Awaiting dataFlushed or dismiss.
    case cancelAcknowledged

    /// Drink successfully completed (dataFlushed received after awaitingGlassRemoval).
    case completed

    /// Ports UIKit `isCancelRelated` — groups the three cancel states.
    var isCancelRelated: Bool {
        switch self {
        case .cancelling, .cancelledWaitingForGlass, .cancelAcknowledged:
            return true
        default:
            return false
        }
    }
}

// MARK: - StationCleaningFlow-lite (row data for the crafting table)

/// Minimal shape we need at crafting time — 1:1 with the subset of
/// `StationCleaningFlow` used by `CraftingViewModel` + `CraftingCell`.
///
/// `isPerishable` + `updatedAt` are carried alongside the pourable
/// fields so the post-craft `updateQuantitiesOnBasedPouringCompletion`
/// PATCH can reconstruct a FULL `StationSlot` without dropping the
/// server-side metadata. The previous port rebuilt each slot with
/// `isPerishable: false, category: nil, updatedAt: nil`, which wiped
/// those fields on the server and caused Ready-to-Pour's category-
/// match filter to return an empty list the next time the user hit
/// "Make it again" (exact bug report — "make it again all ready to
/// pour data got lost").
struct CraftingIngredientRow: Identifiable, Hashable {
    let id = UUID()
    var station: StationName
    var ingredientName: String
    var ingredientQuantity: Double
    var category: IngredientCategory?
    /// Mirror of `StationSlot.isPerishable` (raw server flag, NOT the
    /// expired-computation). Preserved so the post-craft PATCH re-sends
    /// the ORIGINAL perishable state — UIKit does the same via
    /// `StationCleaningFlow.perishable`.
    var isPerishable: Bool = false
    /// Mirror of `StationSlot.updatedAt` — the server-owned ISO-8601
    /// timestamp of the last station refill. Carried through so the
    /// 24-hour perishable timer doesn't reset when we PATCH reduced
    /// quantities after a pour.
    var updatedAt: String? = nil
}

// MARK: - CraftingViewModel

@MainActor
final class CraftingViewModel: ObservableObject {

    // MARK: - State

    @Published var state: CraftingState = .idle
    @Published var recipeIngredients: [CraftingIngredientRow] = []
    @Published var currentIngredient: Int = 0
    @Published var completed: Int = 0
    /// Status line under the recipe name (UIKit `lbLGlassStatus.text`).
    @Published var glassStatusText: String = Constants.placeGlassToBegin
    @Published var stationQuantityFeedback: String = ""
    /// Shown beneath the 1:1 ingredient table to indicate overall progress.
    @Published var overallProgress: Double = 0
    /// True once dispensing has begun AT LEAST ONCE in this session.
    /// Reset only via `resetForMakeAgain()`.
    @Published var hasStartedDispensing: Bool = false

    /// 1:1 port of UIKit `garnishIngredientsArr` — mandatory garnish
    /// (`category.primary == "garnish" && ingredientOptional == false`).
    /// Display-only: never poured. Rendered on DrinkCompleteView as
    /// "Don't forget to add" steps.
    @Published var garnishIngredients: [Ingredient] = []

    /// 1:1 port of UIKit `additionalIngredientsArr` — optional garnish
    /// (`category.primary == "garnish" && ingredientOptional == true`).
    /// Display-only: never poured.
    @Published var additionalIngredients: [Ingredient] = []

    /// Surfaced to the view as an alert when a craft-entry
    /// precondition fails. Mirrors UIKit's
    /// `showDefaultAlert(message: Constants.xxx, cancelTitle: okay)`
    /// calls in `RecipePageViewModel.checkBarsys360Craftability` +
    /// `RecipeCraftingClass.craftCoasterRecipeWithUpdatedQuantity` +
    /// `RecipeCraftingClass.craftRecipeFromRecipeListing` — all of
    /// which emit one of the five error messages on failure. The
    /// view pops back to the caller on dismiss to match the UIKit
    /// behaviour where the craft push is aborted.
    @Published var craftError: CraftabilityError?

    /// Surfaced to the view as the perishable prompt. Only emitted on
    /// the Barsys 360 path (UIKit guards with `!isSpeakEasyCase`).
    /// The view must call either `continueAfterPerishable(ble:)` on
    /// "Okay" or dismiss the crafting screen on "Clean" (the cleaning
    /// navigation is owned by the view so the ViewModel stays
    /// independent of the router).
    @Published var perishablePromptVisible: Bool = false

    private(set) var recipe: Recipe?
    /// Mirrors UIKit `arrStations` populated by `MixlistsUpdateClass.getStationsHere`
    /// on the Barsys 360 path.
    private(set) var arrStations: [CraftingIngredientRow] = []

    /// Pre-computed craft command — built by `load360AndSendCommand`
    /// and cached when the perishable prompt fires so we can replay
    /// it once the user taps "Okay" to continue crafting.
    private var pendingCraftCommand: String?

    /// 1:1 port of UIKit `CraftabilityError` + the five error
    /// branches used by UIKit's three craft-entry functions
    /// (`checkBarsys360Craftability`, `craftCoasterRecipeWithUpdatedQuantity`,
    /// `craftRecipeFromRecipeListing`). Each case maps to the exact
    /// UIKit `Constants.xxx` message via `message`.
    enum CraftabilityError: Equatable {
        /// `baseAndMixerIngredientsArrWithUpdatedQuantity.count == 0`
        /// → "Ingredient not available in recipe."
        case noIngredients
        /// Recipe ingredient quantity < `NumericConstants.minimumQtyDouble`
        /// (= 5.0 ml) → "Ingredient quantity low."
        case lowIngredientQuantity
        /// No station in `arrStations` whose
        /// `(category.primary, category.secondary)` matches a recipe
        /// ingredient → "Please check your station: one or more
        /// ingredients are missing."
        case ingredientNotInStation
        /// Station has an assigned ingredient but its
        /// `ingredientQuantity < recipe.ingredient.quantity` →
        /// "Please check your station(s): one or more ingredients
        /// have insufficient quantity."
        case insufficientStationQuantity

        var message: String {
            switch self {
            case .noIngredients: return Constants.ingredientsNotAvailableInRecipe
            case .lowIngredientQuantity: return Constants.lowIngredientQty
            case .ingredientNotInStation: return Constants.ingredientDoesNotExistInStation
            case .insufficientStationQuantity: return Constants.insufficientIngredientQuantityFor360
            }
        }
    }

    // MARK: - Device detection helpers

    private enum DeviceKind { case barsys360, coaster, shaker, none }
    private func deviceKind(_ ble: BLEService) -> DeviceKind {
        if ble.isBarsys360Connected() { return .barsys360 }
        if ble.isCoasterConnected() { return .coaster }
        if ble.isBarsysShakerConnected() { return .shaker }
        return .none
    }

    // MARK: - Computed UI copy

    var recipeName: String {
        if (recipe?.name ?? "").isEmpty { return "Custom Drink" }
        return recipe?.name ?? ""
    }
    var initialGlassStatusText: String {
        // UIKit: shaker has no place-glass prompt — label remains empty.
        // Other devices show `Constants.placeGlassToBegin`.
        Constants.placeGlassToBegin
    }

    /// Row status helper — mirrors UIKit `ingredientStatus(at:)`.
    enum IngredientPourStatus { case nowPouring, poured, inQueue, empty }

    func ingredientStatus(at index: Int) -> IngredientPourStatus {
        guard index >= 0, index < recipeIngredients.count else { return .empty }
        let row = recipeIngredients[index]
        if row.ingredientName.isEmpty { return .empty }
        if index == currentIngredient {
            return hasStartedDispensing ? .nowPouring : .inQueue
        }
        return index < currentIngredient ? .poured : .inQueue
    }

    // MARK: - Start

    /// 1:1 port of `CraftingViewController.makeDrinkInitiallyOrAgain()`.
    /// Branches on connected device type and drives the correct command.
    ///
    /// Ingredient-filter rules — ported verbatim from UIKit
    /// `RecipePageViewModel+DataLoading.swift` L37-40:
    ///
    ///   • `baseAndMixer` = primary != "garnish" && primary != "additional"
    ///     → THESE are the only ingredients the device pours. The 360
    ///       command builder iterates over them; the coaster/shaker
    ///       command builder iterates over them.
    ///   • `garnish`       = primary == "garnish" && ingredientOptional == false
    ///     → Display-only. Shown on DrinkCompleteView as "Don't forget
    ///       to add" steps. NEVER poured.
    ///   • `additional`    = primary == "garnish" && ingredientOptional == true
    ///     → Display-only (optional garnish). NEVER poured.
    ///
    /// Previously the SwiftUI port seeded `recipeIngredients` from the
    /// UNFILTERED `recipe.ingredients`, so garnish + additional rows
    /// were being sent to the device as pourable quantities. This
    /// resulted in the device trying to pour garnish (lemon wedge,
    /// mint leaf, etc.) which either fails at the firmware level or
    /// (worse) dispenses junk because the station doesn't match.
    ///
    /// Validation chain (1:1 with UIKit `checkBarsys360Craftability`
    /// + `craftCoasterRecipeWithUpdatedQuantity`):
    ///   1. `baseAndMixer.count == 0` → `.noIngredients`
    ///   2. any ingredient `quantity < minimumQtyDouble (= 5 ml)`
    ///      → `.lowIngredientQuantity`
    ///   3. Device-specific checks inside
    ///      `load360AndSendCommand` / `sendCoasterOrShakerCommand`.
    func start(recipe: Recipe, ble: BLEService) async {
        self.recipe = recipe
        self.glassStatusText = initialGlassStatusText
        self.state = .idle
        self.currentIngredient = 0
        self.completed = 0
        self.hasStartedDispensing = false
        self.overallProgress = 0
        self.craftError = nil
        self.perishablePromptVisible = false
        self.pendingCraftCommand = nil

        let allIngredients = recipe.ingredients ?? []

        // UIKit split (RecipePageViewModel+DataLoading.swift L37-40).
        let baseAndMixer = allIngredients.filter { ing in
            let p = (ing.category?.primary ?? "").lowercased()
            // Matches UIKit SQL exclusion: garnish, additionals, additional.
            return p != "garnish" && p != "additional" && p != "additionals"
        }
        // `.unique(by: name.lowercased())` dedup — UIKit applies this
        // to garnish / additional (L29-30, L39-40) so repeat entries
        // in the recipe don't double-render on DrinkComplete.
        let garnishArr = allIngredients
            .filter { ing in
                let p = (ing.category?.primary ?? "").lowercased()
                return p == "garnish" && (ing.ingredientOptional ?? false) == false
            }
            .uniqued(by: { $0.name.lowercased() })
        let additionalArr = allIngredients
            .filter { ing in
                let p = (ing.category?.primary ?? "").lowercased()
                return p == "garnish" && (ing.ingredientOptional ?? false) == true
            }
            .uniqued(by: { $0.name.lowercased() })

        self.garnishIngredients = garnishArr
        self.additionalIngredients = additionalArr

        // Seed the pourable-only rendered list. `station: .a` is a
        // placeholder; the 360 path re-resolves the real station in
        // `load360AndSendCommand` via category matching, and the
        // coaster/shaker path ignores `station` entirely (command
        // format is positional quantity-only).
        recipeIngredients = baseAndMixer.map { ing in
            CraftingIngredientRow(
                station: .a,
                ingredientName: ing.name,
                ingredientQuantity: ing.quantity ?? 0,
                category: ing.category
            )
        }

        // Validation 1 — noIngredients (UIKit L17-20 in
        // checkBarsys360Craftability; UIKit L293-297 in
        // craftCoasterRecipeWithUpdatedQuantity).
        if recipeIngredients.isEmpty {
            craftError = .noIngredients
            return
        }

        // Validation 2 — lowIngredientQuantity. UIKit's coaster path
        // (L311-316) checks `quantity < minimumQtyDouble` per
        // ingredient. UIKit `minimumQtyDouble` = 5.0 ml
        // (Constants.swift L73). The same semantics apply to the
        // 360 path — UIKit has a dead-code check (L32-35) against
        // an empty `finalArrayMapped` which never fires, but the
        // intent is clearly "block pours below 5 ml" so we apply it
        // uniformly on both device paths.
        let minQty = 5.0
        if recipeIngredients.contains(where: { $0.ingredientQuantity < minQty }) {
            craftError = .lowIngredientQuantity
            return
        }

        switch deviceKind(ble) {
        case .barsys360:
            await load360AndSendCommand(ble: ble)
        case .coaster, .shaker:
            await sendCoasterOrShakerCommand(ble: ble)
        case .none:
            // No device connected — surface a passive idle state.
            state = .idle
        }
    }

    /// Called by the view when the user taps "Okay" on the perishable
    /// prompt. 1:1 with UIKit `showCustomAlertMultipleButtons` "Okay"
    /// branch (RecipeCraftingClass.swift L81 — empty closure that
    /// implicitly proceeds; crafting continues because the command
    /// was already cached).
    func continueAfterPerishable(ble: BLEService) {
        perishablePromptVisible = false
        guard let command = pendingCraftCommand else { return }
        pendingCraftCommand = nil
        _ = ble.send(.craftRaw(command: command))
    }

    /// Called by the view when the user taps "Clean" on the perishable
    /// prompt. 1:1 with UIKit `showCustomAlertMultipleButtons` "Clean"
    /// branch (RecipeCraftingClass.swift L83-86 — pushes
    /// `StationCleaningFlowViewController` then pops the crafting
    /// stack). In SwiftUI the view handles the navigation; this
    /// method only resets internal state so the craft attempt is
    /// abandoned cleanly.
    func cancelForPerishableCleaning() {
        perishablePromptVisible = false
        pendingCraftCommand = nil
        state = .idle
    }

    /// Ports UIKit `CraftingViewController.getIngredientsFor360StartCraftingFlow()`
    /// + `RecipeCraftingClass.craftRecipeFromRecipeListing` (the 360
    /// branch L30-107) + `RecipePageViewModel.checkBarsys360Craftability`
    /// (L16-100). All three UIKit call sites run the SAME validation
    /// sequence before building + sending the craft command, so we
    /// consolidate them here.
    ///
    /// Sequence — EXACT order matters:
    ///   1. Load the 6 A–F stations from the server.
    ///   2. For every recipe ingredient (base+mixer only):
    ///      a. Find the station whose `(category.primary, category.secondary)`
    ///         matches the ingredient's, lowercased.
    ///         • No match → `.ingredientNotInStation`, abort.
    ///      b. If that station has an assigned ingredient AND its
    ///         `ingredientQuantity < recipe.ingredient.quantity`
    ///         → `.insufficientStationQuantity`, abort.
    ///   3. Build the "200,…" command string (already correct).
    ///   4. Compute the perishable-stations list — any station whose
    ///      `perishable == true` AND `updatedAt` is older than 24h.
    ///      `StationsAPIService.loadStations` already pre-computed
    ///      this as `StationSlot.isPerishable`.
    ///   5. If any perishable station AND NOT speakeasy → cache
    ///      the command in `pendingCraftCommand` and flag
    ///      `perishablePromptVisible`. The view shows the
    ///      `Constants.perishableDescriptionTitle` alert; "Okay" calls
    ///      `continueAfterPerishable` which sends the cached command,
    ///      "Clean" calls `cancelForPerishableCleaning` + navigates.
    ///   6. Else send the command immediately.
    private func load360AndSendCommand(ble: BLEService) async {
        let deviceName = ble.getConnectedDeviceName()
        let stations = await StationsAPIService.loadStations(deviceName: deviceName)
        // 1:1 port of UIKit `CraftingViewModel.processStationsForCrafting`
        // + `BleCommandBuilder.buildCommandString` — station category
        // (primary + secondary) is REQUIRED for the command builder to
        // match recipe ingredients to stations.
        arrStations = stations.map {
            // Preserve isPerishable + updatedAt alongside category so
            // `updateQuantitiesOnBasedPouringCompletion` can PATCH the
            // reduced quantities WITHOUT nuking those server-side
            // fields. The previous port dropped them here (only
            // carried station / name / quantity / category forward),
            // and the post-craft PATCH was what broke Make-It-Again
            // → Ready-to-Pour for Barsys 360.
            CraftingIngredientRow(
                station: $0.station,
                ingredientName: $0.ingredientName,
                ingredientQuantity: $0.ingredientQuantity,
                category: $0.category,
                isPerishable: $0.isPerishable,
                updatedAt: $0.updatedAt
            )
        }

        // Validation 3 — ingredientNotInStation + insufficientStationQuantity.
        // 1:1 port of the for-loop in UIKit
        // `checkBarsys360Craftability` L55-82 and
        // `craftRecipeFromRecipeListing` L47-76.
        for ingredient in recipeIngredients {
            let rp = (ingredient.category?.primary ?? "").lowercased()
            let rs = (ingredient.category?.secondary ?? "").lowercased()
            let matchingStation = stations.first { station in
                let sp = (station.category?.primary ?? "").lowercased()
                let ss = (station.category?.secondary ?? "").lowercased()
                return sp == rp && ss == rs
            }
            guard let station = matchingStation else {
                craftError = .ingredientNotInStation
                return
            }
            // UIKit check: `existingStationObject.ingredientName != nil
            //   && existingStationObject.ingredientQuantity <
            //      currentIngredientQuantity`
            // i.e. if the station has an assigned ingredient but not
            // enough of it to cover the recipe's ask, block the craft.
            if !station.ingredientName.isEmpty
                && station.ingredientQuantity < ingredient.ingredientQuantity {
                craftError = .insufficientStationQuantity
                return
            }
        }

        // 1:1 with UIKit `BleCommandBuilder.buildCommandString`
        // L136-143: after walking A→F and collecting the matched
        // recipe ingredients into `tempActualStationsArrayToPour`,
        // UIKit REPLACES `craftVc.recipeIngredientsArr` with that
        // station-A→F-ordered list. This reorder is the load-bearing
        // piece that makes the cell gradient track the device's
        // actual pour sequence on Barsys 360.
        //
        // Why: the 360 firmware pours stations in A→F order (skipping
        // empty slots) and reports progress via `"218,{idx},405"`
        // where `idx` is a 0-based POUR-SEQUENCE position (0 = first
        // active pour, 1 = second, …). The dispatch handler then
        // pattern-matches `where idx == currentIngredient` — which
        // only lines up when `recipeIngredients[0]` is the ingredient
        // assigned to the FIRST A→F station, `recipeIngredients[1]`
        // is the second, etc.
        //
        // The previous SwiftUI port kept `recipeIngredients` in the
        // recipe's original JSON order. If the recipe listed
        // ingredients in a different order than their stations
        // (e.g. recipe order [bourbon, vermouth, bitters] but stations
        // [vermouth=A, bourbon=C, bitters=E]), firmware would report
        // `dispensingStarted(0)` when station A (vermouth) started,
        // `idx=0` against `currentIngredient=0` matched, but the cell
        // at row 0 was bourbon — so the "now pouring" gradient
        // highlighted the WRONG ingredient and never advanced,
        // exactly matching the bug report.
        //
        // Coaster + Shaker do NOT need the reorder — their command is
        // positional (14 fixed slots of quantity-only, no station
        // mapping) and the firmware's `idx` for those devices equals
        // the recipe-order index by construction. Only the Barsys 360
        // path rewires recipe ↔ station mapping, so only this path
        // reorders the pourable list.
        let order: [StationName] = [.a, .b, .c, .d, .e, .f]
        var orderedIngredients: [CraftingIngredientRow] = []
        for st in order {
            guard let stationObj = arrStations.first(where: { $0.station == st }) else { continue }
            let sp = stationObj.category?.primary?.lowercased() ?? ""
            let ss = stationObj.category?.secondary?.lowercased() ?? ""
            guard stationObj.category?.primary != nil else { continue }
            guard let match = recipeIngredients.first(where: { r in
                let rp = r.category?.primary?.lowercased() ?? ""
                let rs = r.category?.secondary?.lowercased() ?? ""
                return rp == sp && rs == ss && !r.ingredientName.isEmpty
            }) else { continue }
            var row = match
            row.station = st
            orderedIngredients.append(row)
        }
        // Replace ONLY when at least one match survived — if all
        // station slots are empty (shouldn't happen post-validation),
        // leave the list untouched rather than blanking the UI.
        if !orderedIngredients.isEmpty {
            self.recipeIngredients = orderedIngredients
        }

        // Build the command using the A→F-ordered list — same
        // "200,s1,q1,...,s6,q6" format used by UIKit.
        let command = build360Command(stations: arrStations,
                                      recipeIngredients: recipeIngredients)

        // Validation 4 — perishable stations. 1:1 with UIKit
        // `showCustomAlertMultipleButtons(title: perishableDescriptionTitle,…)`
        // guard in `RecipeCraftingClass.craftRecipeFromRecipeListing`
        // L79-89 + `performBarsys360CraftCheck` L91-99. UIKit skips the
        // prompt when `isSpeakEasyCase` because the remote operator —
        // not the app user — decides cleaning.
        // Use `isPerishableExpired` = raw flag AND updated_at > 24h
        // ago. Matches UIKit `BleCommandBuilder.getPerishableArray(from:)`
        // used by `craft360RecipeForUpdatedQuantity` perishable guard.
        let perishableStations = stations.filter { $0.isPerishableExpired }
        let isSpeakEasy = AppStateManager.shared.isSpeakEasyCase
        if !perishableStations.isEmpty && !isSpeakEasy {
            pendingCraftCommand = command
            perishablePromptVisible = true
            return
        }

        _ = ble.send(.craftRaw(command: command))
    }

    /// 1:1 port of `BleCommandBuilder.buildCommandString` for Barsys 360.
    ///
    /// **Format**: non-empty `(station, qty)` pairs appear FIRST in the
    /// command, followed by `,0,0` pairs for every empty station, then
    /// zero-padded to 15 components total. This matches UIKit
    /// `BleCommandBuilder.buildCommandString` L78-189 — two passes:
    ///   1. Walk A→F and append `,{num},{qty}` for each matched station
    ///      (skipping empty ones; empty station names collected into
    ///      `nilStationNamesArray`).
    ///   2. Walk the nil-station list and append `,0,0` for each.
    ///
    /// **Why the order matters**: the Barsys 360 firmware iterates the
    /// pairs left-to-right and reports pour progress via
    /// `"218,{idx},405"` / `"218,{idx},401"` where `idx` is the 0-based
    /// POSITION of the pair in the command. With the old "interleaved"
    /// format (empty stations emitted in their A→F slot), a recipe with
    /// only stations C + E matched produced
    ///   `"200,0,0,0,0,3,60,0,0,5,30,0,0"`
    /// and firmware reported `dispensingStarted(2)` for station C,
    /// `dispensingStarted(4)` for station E. The dispatch handler's
    /// `where idx == currentIngredient` guard therefore never fired
    /// (currentIngredient is 0, 1, 2, … after the reorder in
    /// `load360AndSendCommand`), so the "Now pouring" cell gradient
    /// never advanced and the drink never transitioned through to
    /// `.awaitingGlassRemoval` / `.completed` — exactly the bug report.
    ///
    /// Compact format for the same recipe:
    ///   `"200,3,60,5,30,0,0,0,0,0,0,0,0,0,0"`
    /// Firmware reports `dispensingStarted(0)` for C (pair index 0) and
    /// `dispensingStarted(1)` for E (pair index 1), which aligns with
    /// `currentIngredient = 0, 1` — cell gradient advances, completion
    /// fires on `allIngredientsPoured` + `dataFlushed` exactly as UIKit.
    ///
    /// Coaster + Shaker unaffected — their command is `sendCoasterOrShakerCommand`
    /// (positional 14 quantity-only slots, no station mapping).
    private func build360Command(stations: [CraftingIngredientRow],
                                 recipeIngredients: [CraftingIngredientRow]) -> String {
        let order: [(StationName, Int)] = [
            (.a, 1), (.b, 2), (.c, 3), (.d, 4), (.e, 5), (.f, 6)
        ]
        var matchedPairs: [String] = []
        var emptySlotCount = 0
        for (station, num) in order {
            let stationObj = stations.first { $0.station == station }
            let match = recipeIngredients.first { r in
                let rp = r.category?.primary?.lowercased() ?? ""
                let rs = r.category?.secondary?.lowercased() ?? ""
                let sp = stationObj?.category?.primary?.lowercased() ?? ""
                let ss = stationObj?.category?.secondary?.lowercased() ?? ""
                return stationObj?.category?.primary != nil
                    && rp == sp && rs == ss
                    && !r.ingredientName.isEmpty
            }
            if let m = match {
                matchedPairs.append("\(num),\(Int(m.ingredientQuantity))")
            } else {
                emptySlotCount += 1
            }
        }
        // Non-empty pairs first — matches UIKit pass 1.
        var cmd = "200"
        for pair in matchedPairs {
            cmd += ",\(pair)"
        }
        // Trailing `,0,0` per empty station — UIKit pass 2.
        for _ in 0..<emptySlotCount {
            cmd += ",0,0"
        }
        // Final pad to 15 components — UIKit post-pass padding loop.
        let components = cmd.components(separatedBy: ",")
        if components.count < 15 {
            let pad = Array(repeating: "0", count: 15 - components.count)
            cmd += "," + pad.joined(separator: ",")
        }
        return cmd
    }

    /// 1:1 port of `CraftingViewModel.buildCoasterCommand()`:
    /// `"200,q1,q2,…,q14"` — recipe quantities in order, remaining slots
    /// zero-filled to exactly 14 quantities.
    private func sendCoasterOrShakerCommand(ble: BLEService) async {
        var cmd = "200"
        for row in recipeIngredients {
            cmd += ",\(row.ingredientQuantity)"
        }
        let rest = max(0, 14 - recipeIngredients.count)
        for _ in 0..<rest { cmd += ",0" }
        _ = ble.send(.craftRaw(command: cmd))
    }

    // MARK: - Cancel

    /// Ports `CraftingViewController.didPressCancelButton` +
    /// `CraftingViewModel.handleCancelRequest`. Branches on current
    /// state so `cancelling` / `cancelledWaitingForGlass` are tracked
    /// correctly.
    func cancel(ble: BLEService) {
        guard !state.isCancelRelated else { return }
        if state == .waitingForGlass || state == .glassLifted {
            state = .cancelledWaitingForGlass
        } else {
            state = .cancelling
        }
        glassStatusText = Constants.removeGlassToCancelTheDrink
        _ = ble.send(.cancel)
    }

    // MARK: - Reset (ports resetForMakeAgain)
    func resetForMakeAgain() {
        state = .idle
        hasStartedDispensing = false
        currentIngredient = 0
        completed = 0
        stationQuantityFeedback = ""
        overallProgress = 0
        glassStatusText = initialGlassStatusText
        craftError = nil
        perishablePromptVisible = false
        pendingCraftCommand = nil
    }

    // MARK: - BLE response dispatch
    //
    // 1:1 port of `CraftingViewController+BleResponse.swift`. Each
    // device kind has its own switch-case tree since the firmware sends
    // slightly different sequences. The shared pattern:
    //
    //   glassLifted / glassWaiting → [dispensing, cancelling, waitingForGlass]
    //   glassPlaced               → [dispensing, cancelling, idle]
    //   cancelAcknowledged        → [pop back or cancelAcknowledged]
    //   allIngredientsPoured      → .awaitingGlassRemoval
    //   dispensingStarted(n)      → set `n = currentIngredient`, .dispensing
    //   dispensingComplete(n)     → increment `completed + currentIngredient`
    //   dataFlushed               → transition to .completed (or dismiss on cancel)

    /// Entry point the view calls from `.onReceive(ble.$lastResponse)`.
    func dispatch(_ response: BleResponse, ble: BLEService,
                  onCompleted: (() -> Void)? = nil,
                  onDismiss: (() -> Void)? = nil) {
        // Handle dataFlushed separately — it's cross-device and drives
        // the final completion or the final dismiss after cancel.
        if case .dataFlushed = response {
            handleDataFlushed(ble: ble, onCompleted: onCompleted, onDismiss: onDismiss)
            return
        }

        switch deviceKind(ble) {
        case .barsys360:
            dispatch360(response, onDismiss: onDismiss)
        case .coaster:
            dispatchCoaster(response, onDismiss: onDismiss)
        case .shaker:
            dispatchShaker(response, onDismiss: onDismiss)
        case .none:
            break
        }
    }

    private func handleDataFlushed(ble: BLEService,
                                   onCompleted: (() -> Void)?,
                                   onDismiss: (() -> Void)?) {
        // Completion path (UIKit L61-68): universal — any device where
        // `currentIngredient` has advanced past zero AND state is
        // awaitingGlassRemoval. Post-fix this is the normal happy path
        // on Barsys 360 now that the compact command format + A→F
        // reorder keep `currentIngredient` in sync with firmware
        // `dispensingComplete` indices.
        if currentIngredient > 0, state == .awaitingGlassRemoval {
            completeDrink(ble: ble, onCompleted: onCompleted)
            return
        }
        // Cancel-acknowledged dismissals per device (UIKit L69-76).
        if state.isCancelRelated {
            switch deviceKind(ble) {
            case .coaster, .shaker:
                // Coaster / Shaker need time to flush data after cancel —
                // UIKit uses a 2.0s delay.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.state = .idle
                    onDismiss?()
                }
            case .barsys360:
                onDismiss?()
            case .none:
                break
            }
            return
        }

        // 1:1 with UIKit `handleDataFlushed` L77-87: DEFENSIVE fallback
        // for Barsys 360. If the first branch didn't trigger because
        // `currentIngredient == 0` — which can happen on very short
        // recipes or if a firmware quirk drops a `dispensingComplete`
        // event — but `state` is still awaitingGlassRemoval AND Barsys
        // 360 is the connected device, force completion. UIKit adds
        // this specifically so the DrinkComplete screen still fires
        // when the primary counter check fails. Coaster / Shaker do
        // NOT get this branch (UIKit doesn't either) — their pours are
        // short enough that the counter always advances.
        if ble.isBarsys360Connected(), state == .awaitingGlassRemoval {
            completeDrink(ble: ble, onCompleted: onCompleted)
            return
        }
    }

    /// Shared completion path extracted from `handleDataFlushed`. Runs
    /// the success haptic, fires the server-side station quantity
    /// update (Barsys 360 only), and pushes DrinkComplete via the
    /// injected `onCompleted` closure.
    private func completeDrink(ble: BLEService, onCompleted: (() -> Void)?) {
        state = .completed
        // UIKit `CraftingViewController+BleResponse.swift` L63:
        // `HapticService.shared.success()` when the drink
        // completes. SwiftUI port adds the same success haptic
        // so the device confirms-completion cue feels identical.
        HapticService.success()
        // 1:1 port of UIKit `DrinkCompleteViewController.viewDidLoad`
        // L111-114: after the drink finishes AND Barsys 360 is
        // connected, call `updateQuantitiesOnBasedPouringCompletion`
        // to PATCH the new (reduced) station quantities back to the
        // server so perishable timers + remaining ml counts stay in
        // sync with what the hardware actually dispensed.
        if ble.isBarsys360Connected() {
            let deviceName = ble.getConnectedDeviceName()
            let feedback = stationQuantityFeedback
            let stationsSnapshot = arrStations
            Task {
                await CraftingViewModel.updateQuantitiesOnBasedPouringCompletion(
                    deviceName: deviceName,
                    feedback: feedback,
                    stations: stationsSnapshot
                )
            }
        }
        onCompleted?()
    }

    // MARK: - Barsys 360 (ports `handleBarsys360Response`)
    private func dispatch360(_ response: BleResponse, onDismiss: (() -> Void)?) {
        switch response {
        case .glassLifted, .glassWaiting:
            if state == .dispensing {
                glassStatusText = Constants.placeGlassToBegin
                state = .glassLifted
            } else if state == .cancelling {
                state = .cancelledWaitingForGlass
            } else if state != .glassLifted && state != .cancelledWaitingForGlass {
                state = .waitingForGlass
            }

        case .glassPlaced(let is219):
            if state == .glassLifted { state = .dispensing }
            else if state == .cancelledWaitingForGlass { state = .cancelling }
            else if state == .waitingForGlass { state = .idle }
            if is219 { glassStatusText = "" }

        case .cancelAcknowledged:
            if state == .cancelledWaitingForGlass {
                state = .cancelAcknowledged
                onDismiss?()
            } else {
                state = .cancelAcknowledged
            }

        case .allIngredientsPoured:
            if state.isCancelRelated {
                glassStatusText = Constants.removeGlassToCancelTheDrink
                return
            }
            // UIKit `CraftingViewController+BleResponse.swift` L147:
            // `HapticService.shared.medium()` on allIngredientsPoured.
            HapticService.medium()
            glassStatusText = Constants.removeGlassToCompleteTheDrink
            state = .awaitingGlassRemoval

        case .quantityFeedback(let raw):
            stationQuantityFeedback = raw
            if !state.isCancelRelated { state = .awaitingGlassRemoval }

        case .dispensingStarted(let index) where index == currentIngredient:
            state = .dispensing
            hasStartedDispensing = true

        case .dispensingComplete(let index) where index == currentIngredient:
            // UIKit L166: `HapticService.shared.light()` on each
            // ingredient finishing so the user feels a tick for every
            // ingredient poured.
            HapticService.light()
            completed += 1
            currentIngredient += 1
            recomputeOverallProgress()

        default:
            break
        }
    }

    // MARK: - Coaster (ports `handleCoasterResponse`)
    private func dispatchCoaster(_ response: BleResponse, onDismiss: (() -> Void)?) {
        switch response {
        case .glassLifted, .glassWaiting:
            if state == .dispensing {
                glassStatusText = Constants.placeGlassToBegin
                state = .glassLifted
            } else if state == .cancelling {
                state = .cancelledWaitingForGlass
            } else if state != .glassLifted && state != .cancelledWaitingForGlass {
                state = .waitingForGlass
            }

        case .glassPlaced:
            if state == .glassLifted { state = .dispensing }
            else if state == .cancelledWaitingForGlass { state = .cancelling }
            else if state == .waitingForGlass { state = .idle }
            glassStatusText = ""

        case .cancelAcknowledged:
            if state == .cancelledWaitingForGlass {
                state = .cancelAcknowledged
                // UIKit: 2.0s wait before popping so hardware settles.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.state = .idle
                    onDismiss?()
                }
            } else {
                state = .cancelAcknowledged
            }

        case .allIngredientsPoured:
            guard !state.isCancelRelated else { return }
            // UIKit parity — medium haptic on allIngredientsPoured
            // (same as Barsys 360 branch).
            HapticService.medium()
            glassStatusText = Constants.removeGlassToCompleteTheDrink
            state = .awaitingGlassRemoval

        case .dispensingStarted(let index) where index == currentIngredient:
            guard !state.isCancelRelated else { return }
            state = .dispensing
            hasStartedDispensing = true

        case .dispensingComplete(let index) where index == currentIngredient:
            guard !state.isCancelRelated else { return }
            // Light haptic per ingredient finished.
            HapticService.light()
            completed += 1
            currentIngredient += 1
            recomputeOverallProgress()

        default:
            break
        }
    }

    // MARK: - Shaker (ports `handleShakerResponse`)
    private func dispatchShaker(_ response: BleResponse, onDismiss: (() -> Void)?) {
        switch response {
        case .shakerNotFlat:
            // UIKit pops the ShakerFlatSurface alert — exposed via the view.
            break
        case .shakerFlat, .glassPlaced(is219: true):
            // Dismiss the flat-surface popup; no state change.
            break
        case .glassLifted:
            if state == .dispensing { state = .glassLifted }
            else if state == .cancelling { state = .cancelledWaitingForGlass }
            else if state != .glassLifted && state != .cancelledWaitingForGlass {
                state = .waitingForGlass
            }

        case .glassPlaced:
            if state == .glassLifted { state = .dispensing }
            else if state == .cancelledWaitingForGlass { state = .cancelling }
            else if state == .waitingForGlass { state = .idle }

        case .cancelAcknowledged:
            if state == .cancelledWaitingForGlass {
                state = .cancelAcknowledged
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.state = .idle
                    onDismiss?()
                }
            } else {
                state = .cancelAcknowledged
            }

        case .allIngredientsPoured:
            guard !state.isCancelRelated else { return }
            // Medium haptic — Shaker same as 360 / Coaster.
            HapticService.medium()
            state = .awaitingGlassRemoval

        case .dispensingStarted(let index) where index == currentIngredient:
            guard !state.isCancelRelated else { return }
            state = .dispensing
            hasStartedDispensing = true

        case .dispensingComplete(let index) where index == currentIngredient:
            guard !state.isCancelRelated else { return }
            // Light haptic per ingredient finished.
            HapticService.light()
            completed += 1
            currentIngredient += 1
            recomputeOverallProgress()

        default:
            break
        }
    }

    private func recomputeOverallProgress() {
        guard !recipeIngredients.isEmpty else {
            overallProgress = 0; return
        }
        overallProgress = Double(currentIngredient) / Double(recipeIngredients.count)
    }

    // MARK: - updateQuantitiesOnBasedPouringCompletion
    //
    // 1:1 port of UIKit `CraftingViewModel+StationUpdate.swift` —
    // after the Barsys 360 finishes pouring, the device sends a
    // quantity-feedback frame in one of these formats (see UIKit
    // `getDataDicOfQuantity`):
    //   • "222,209,{s1},{q1},{s2},{q2},…"
    //   • "222,224,{s1},{q1},{s2},{q2},…"
    //   • Optionally suffixed with ",d"
    // Each `(station, quantity)` pair tells us how many ml of each
    // station we actually dispensed. We subtract these from the
    // station quantities currently on the server and PATCH the full
    // `configuration.stations` dictionary so the next session starts
    // with correct remaining-ml counts.
    //
    // Called from `handleDataFlushed` when transitioning to
    // `.completed`, guarded by `ble.isBarsys360Connected()` to match
    // UIKit's `DrinkCompleteViewController.viewDidLoad` guard.
    nonisolated static func updateQuantitiesOnBasedPouringCompletion(
        deviceName: String,
        feedback: String,
        stations: [CraftingIngredientRow]
    ) async {
        guard !deviceName.isEmpty, !feedback.isEmpty else { return }
        let pouredByStation = parseStationQuantityFeedback(feedback)
        guard !pouredByStation.isEmpty else { return }

        // Reduce current station quantities by what was poured. Match
        // by station name (UIKit uses tag→StationName via
        // `StationHelper.getStationName(tag:)`, we already store the
        // station enum directly so the lookup is trivial).
        //
        // CRITICAL: preserve `category`, `isPerishable`, and
        // `updatedAt` from the original row. `patchAllStations` writes
        // `slot.category?.primary / secondary / flavourTags` and
        // `slot.isPerishable` straight into the PATCH body — if we
        // drop them here (the previous port emitted
        // `isPerishable: false, category: nil`), the server overwrites
        // its stored category fields with empty strings. The next
        // time the user taps "Make it again" the Ready-to-Pour screen
        // refetches stations, reads back empty categories, and the
        // category-match filter returns zero recipes. Keeping these
        // three fields pinned here is what restores Make-It-Again →
        // RTP parity with UIKit.
        var updated: [StationSlot] = stations.map { row in
            var remaining = row.ingredientQuantity
            if let poured = pouredByStation[row.station] {
                remaining -= poured
            }
            if remaining < 0 { remaining = 0 }
            return StationSlot(
                station: row.station,
                ingredientName: row.ingredientName,
                ingredientQuantity: remaining,
                isPerishable: row.isPerishable,
                category: row.category,
                updatedAt: row.updatedAt
            )
        }
        // UIKit sorts by stationName.rawValue before building the dict
        // so the payload order matches the server's expected A→F order.
        updated.sort { $0.station.rawValue < $1.station.rawValue }

        // `flow: .postCraft` is CRITICAL — matches UIKit
        // `updateQuantitiesOnBasedPouringCompletion` exactly:
        //   • sends ALL 6 stations (empty ones included) so the
        //     server's `stations` object stays complete and the last
        //     filled slot doesn't disappear after a drink completes
        //     (the exact regression the user reported);
        //   • writes the REDUCED quantity (what's left after the pour)
        //     instead of the setup-flow's 750ml reset;
        //   • hard-codes `is_perishable: false` per UIKit L91;
        //   • preserves each slot's server-stamped `updated_at` so
        //     the 24-hour perishable timer doesn't reset just because
        //     the user finished a drink.
        _ = await StationsAPIService.patchAllStations(
            deviceName: deviceName,
            stations: updated,
            flow: .postCraft
        )
    }

    /// 1:1 port of UIKit `CraftingViewModel.getDataDicOfQuantity()`:
    /// strips the "222,209,", "222,224,", and ",d" prefixes / suffixes
    /// from the feedback string, then walks the remaining CSV pairs as
    /// `(stationTag, quantityMl)` entries (up to 6 iterations — one per
    /// station) and returns them keyed by `StationName`.
    ///
    /// `nonisolated` because this is a pure parsing function with no
    /// actor-isolated state — and the calling `updateQuantitiesOnBasedPouringCompletion`
    /// is itself `nonisolated` (runs off the main actor to avoid
    /// blocking UI on the network round-trip). Without `nonisolated`
    /// the compiler emits:
    ///   "Main actor-isolated static method 'parseStationQuantityFeedback'
    ///    cannot be called from outside of the actor"
    /// because `CraftingViewModel` is `@MainActor`-isolated which
    /// propagates to its static members by default.
    nonisolated private static func parseStationQuantityFeedback(_ raw: String)
        -> [StationName: Double]
    {
        let cleaned = raw
            .replacingOccurrences(of: "222,209,", with: "")
            .replacingOccurrences(of: ",d", with: "")
            .replacingOccurrences(of: "222,224,", with: "")
        let components = cleaned.split(separator: ",")
        guard components.count >= 2 else { return [:] }

        var result: [StationName: Double] = [:]
        var i = 0
        // UIKit loops 6 times max — one per station, each iteration
        // consumes TWO components (stationTag, quantity).
        for _ in 0..<6 {
            guard i + 1 < components.count else { break }
            // UIKit guards with `split[index] != "0.00" || "\(Int(…))" != "0"`
            // — skips zero-station entries since they mean "no pour on
            // this slot". We mirror that guard here.
            let tagStr = String(components[i])
            let tagDouble = Double(tagStr) ?? 0
            let tagInt = Int(tagDouble)
            if tagInt == 0 {
                i += 2
                continue
            }
            if let station = StationName.forTag(tagInt) {
                let qty = Double(String(components[i + 1])) ?? 0
                // If the same station appears twice, accumulate (server
                // treats each 222,209 frame as cumulative for the slot).
                result[station, default: 0] += qty
            }
            i += 2
        }
        return result
    }
}

// MARK: - CraftingView

struct CraftingView: View {
    let recipeID: RecipeID
    /// 1:1 port of UIKit `CraftingViewController.skipPourConfirmation`
    /// (L101). Set to `true` when entering from "Make It Again" on
    /// DrinkComplete, or from a SpeakEasy-socket-driven craft flow.
    /// When `true`, we skip the "Ready to Pour?" alert and start
    /// crafting immediately.
    var skipPourConfirmation: Bool = false
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService
    @ObservedObject private var appState = AppStateManager.shared
    @Environment(\.dismiss) private var dismiss
    /// Reactive colour scheme — drives the Cancel button's dark-mode
    /// override so its visual matches the recipe-page "Add to
    /// Favorites" capsule (white-glass fill + etched gradient
    /// stroke). Light mode keeps the original `cancelCapsule`
    /// material-based recipe.
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = CraftingViewModel()
    @State private var showCancelConfirm = false
    /// Glass-card popup for "Cancel Drink" — replaces native .alert
    @State private var cancelDrinkPopup: BarsysPopup? = nil
    /// Drives the "Ready to Pour?" confirmation alert. Shown on first
    /// appear unless `skipPourConfirmation` / `isSpeakEasyCase`.
    /// 1:1 with UIKit `showPourConfirmation(onConfirm:)` (L128-143).
    @State private var showPourConfirm = false
    /// Glass-card popup for "Ready to Pour?" — replaces native .alert
    @State private var pourConfirmPopup: BarsysPopup? = nil
    /// True once we've either confirmed or bypassed the pour prompt —
    /// prevents the alert from re-appearing on view re-appearance
    /// (SwiftUI's `.task(id:)` runs again if the view re-enters).
    @State private var didResolvePourConfirm = false

    /// 1:1 port of UIKit `ShakerFlatSurfacePopUpViewController` shown
    /// by `showShakerFlatSurfacePopUp()` in the Crafting +
    /// BarBotCrafting view controllers. Triggered when
    /// `BleResponse.shakerNotFlat` / `.glassWaiting` arrives from a
    /// connected Shaker peripheral, and automatically dismissed on
    /// `.shakerFlat` / `.glassPlaced(is219: true)`.
    @State private var popup: BarsysPopup?

    /// iPad-only sizing flag. The Crafting screen scales its hero
    /// elements (glass-status text, device image, recipe-name title,
    /// and the gap above the ingredient list) up on iPad so the
    /// wider canvas doesn't read as iPhone metrics blown up to fit.
    /// Every iPad value is gated through this — iPhone pixels stay
    /// bit-identical to the UIKit storyboard.
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        // 1:1 port of UIKit `Crafting.storyboard` scene `X0s-iW-KFx`:
        //
        //   60pt top bar (centered device icon + name)
        //   ScrollView containing:
        //     • `lbLGlassStatus` — system 16pt, darkGrayTextColor,
        //       center-aligned, y=47 (e.g. "Place glass on device to
        //       begin", "Remove glass to complete", etc.).
        //     • `imgViewDevice` — 120×120 device image centered, y=30
        //       below status. Swaps between `barsys_360` /
        //       `barsys_coaster` / `barsys_shaker` on appear and
        //       to the in-queue variant / pouring variant via state.
        //     • `lblRecipeName` — recipe name, system 16pt
        //       charcoalGrayColor, centered, y=44 below image.
        //     • tblCrafting — auto-height table with glass-pill cells.
        //   Bottom bar:
        //     • Cancel button 168×40 centered (single-button version —
        //       Done button exists but is always hidden in xib).
        ZStack {
            Color("primaryBackgroundColor").ignoresSafeArea()

            VStack(spacing: 0) {
                if let recipe = env.storage.recipe(by: recipeID) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Glass status label (storyboard gzR-vU-4zg) —
                            // system 16pt, darkGrayTextColor, center-aligned.
                            // iPad bumps to 22pt + 60pt top inset so the
                            // status reads at a comfortable scale on the
                            // wider canvas. iPhone unchanged.
                            Text(viewModel.glassStatusText.isEmpty
                                 ? displayFallback(for: viewModel.state)
                                 : viewModel.glassStatusText)
                                .font(.system(size: isIPad ? 22 : 16))
                                .foregroundStyle(Color("darkGrayTextColor"))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.top, isIPad ? 60 : 47)

                            // Device image (IsT-iE-QYL) 120×120, center,
                            // 30pt below status. Uses in-queue variant
                            // when idle/waiting, pouring variant when
                            // actively dispensing — mirrors UIKit
                            // `deviceInQueueImage` / `devicePouringImage`.
                            //
                            // Light mode: original PNG (bit-identical to
                            // UIKit-parity render). Dark mode: template-
                            // tinted with `softWhiteText` so the dark
                            // device illustration reads as a clear white
                            // glyph against the dark crafting canvas.
                            // iPad bumps to 200×200 with a wider top gap
                            // so the device illustration anchors the
                            // wider canvas the way 120×120 anchors iPhone.
                            Group {
                                if colorScheme == .dark {
                                    Image(deviceImageName())
                                        .renderingMode(.template)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(Theme.Color.softWhiteText)
                                } else {
                                    Image(deviceImageName())
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                }
                            }
                            .frame(width: isIPad ? 200 : 120,
                                   height: isIPad ? 200 : 120)
                            .padding(.top, isIPad ? 40 : 30)

                            // Recipe name (vHh-PF-hYT): system 16pt
                            // charcoalGrayColor, centered, y=44 below
                            // the device image. iPad bumps to 26pt + 50pt
                            // top inset so the recipe title reads as the
                            // primary label, not a caption, on the wider
                            // canvas. iPhone unchanged.
                            Text(recipe.displayName)
                                .font(.system(size: isIPad ? 26 : 16))
                                .foregroundStyle(Color("charcoalGrayColor"))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.top, isIPad ? 50 : 44)

                            // Ingredient glass pill list (tblCrafting).
                            // Auto-expanding height via a VStack of cells
                            // (UIKit observes `contentSize` KVO). iPad
                            // bumps the gap above the list 42 → 56 so the
                            // larger recipe title doesn't crowd row 1.
                            if !viewModel.recipeIngredients.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(Array(viewModel.recipeIngredients.enumerated()),
                                            id: \.element.id) { idx, ingredient in
                                        CraftingIngredientRowView(
                                            name: ingredient.ingredientName,
                                            quantity: ingredient.ingredientQuantity,
                                            unit: env.preferences.measurementUnit,
                                            status: viewModel.ingredientStatus(at: idx)
                                        )
                                    }
                                }
                                .padding(.top, isIPad ? 56 : 42) // jNS-Yd-QVB constraint
                                .padding(.bottom, 24)
                            }

                            Spacer(minLength: 20)
                        }
                    }

                    // Bottom Cancel button (wBo / V73 stack). Always visible
                    // while crafting is in flight; hidden in
                    // `awaitingGlassRemoval` + `completed` to match UIKit
                    // `cancelButton.isHidden = true` calls.
                    bottomActions(for: recipe)
                } else {
                    EmptyStateView(systemImage: "questionmark.circle",
                                   title: Constants.recipeLoadError,
                                   subtitle: Constants.unableToConnectToServer)
                }
            }
        }
        .navigationTitle("Crafting")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Custom 15×15 `back` chevron — same styling as
            // MyProfile / Preferences / PairYourDevice / Cocktail Kits.
            // Tapping it opens the same "Cancel Drink" confirmation
            // popup the Cancel capsule uses; the popup's "Yes, Cancel"
            // handler sends the BLE `.cancel` (202) command and waits
            // for `dataFlushed` before `dismiss()` pops the screen.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    HapticService.light()
                    cancelDrinkPopup = .confirm(
                        title: "Cancel Drink",
                        message: "Are you sure you want to cancel the current drink?",
                        primaryTitle: "Yes, Cancel",
                        secondaryTitle: "No",
                        primaryFillColor: "segmentSelectionColor"
                    )
                } label: {
                    Image("back")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 22 : 15, height: UIDevice.current.userInterfaceIdiom == .pad ? 22 : 15)
                        .foregroundStyle(Color("appBlackColor"))
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel("Back")
            }
        }
        // Hide the tab bar on the Crafting screen — the user is in a
        // focused craft flow with the only escape hatches being the
        // Cancel capsule at the bottom and the nav-bar back button
        // (both route through the same cancel-drink popup above).
        // The tab bar returns automatically when Crafting pops.
        .toolbar(.hidden, for: .tabBar)
        // Swipe-back is DISABLED so an accidental gesture mid-pour
        // can't pop the screen while the device is still dispensing.
        .interactiveDismissDisabled()
        // Publish "we're on the crafting screen" so the disconnect
        // handler shows the during-crafting alert copy + error haptic.
        // 1:1 port of UIKit
        // `BleManagerDelegate+Disconnect.swift` L69-72 — the alert
        // branch is selected by the type of `self` at disconnect time.
        .onAppear {
            router.activeCraftingScreen = .crafting
            // Re-entry reset: if the user went Craft → DrinkComplete
            // → back, this same CraftingView instance is already
            // retained in the nav stack. Its state machine has
            // finished (`.completed`) / been cancelled
            // (`.cancelAcknowledged`), and `didResolvePourConfirm`
            // is still `true`. Without a reset, the pour-confirmation
            // alert never fires a second time — matching the user-
            // reported "second craft does nothing" bug.
            //
            // 1:1 parity with UIKit `CraftingViewController` where
            // "Make It Again" (DrinkCompleteViewController.swift
            // L262-287) calls `craftingVc?.resetCraftingState()` +
            // `makeDrinkInitiallyOrAgain()` on the pre-existing VC
            // before re-entering the flow. We mirror that here by
            // clearing `didResolvePourConfirm` + calling
            // `viewModel.resetForMakeAgain()` whenever we re-appear
            // in a terminal state, then re-running the entry flow.
            if viewModel.state == .completed
                || viewModel.state == .cancelAcknowledged {
                viewModel.resetForMakeAgain()
                didResolvePourConfirm = false
                showPourConfirm = false
            }
            runCraftEntryFlow()
        }
        .onDisappear {
            if router.activeCraftingScreen == .crafting {
                router.activeCraftingScreen = nil
            }
        }
        // Kept as a fallback for the very-first push of the view —
        // `.onAppear` above handles both first-push and re-appear
        // cases, but `.task(id:)` ensures cancellation of any
        // in-flight `viewModel.start(...)` if the recipeID changes
        // (currently the route is immutable, but future tab-routing
        // tweaks may push the same CraftingView with a different id).
        .task(id: recipeID) {
            runCraftEntryFlow()
        }
        // 1:1 with UIKit `CraftingViewController` acting as BleManagerDelegate:
        // forward every parsed BleResponse into the state machine.
        //
        // Shaker popup wiring (ports UIKit `showShakerFlatSurfacePopUp`
        // / `dismissShakerFlatSurfacePopUp` in the Shaker branch of
        // `+BleResponse.swift`): when the device reports it isn't on a
        // flat surface (or needs the user to place the shaker), present
        // a blocking popup; on `shakerFlat` / `glassPlaced(is219:true)`
        // dismiss it automatically.
        .onReceive(ble.$lastResponse.compactMap { $0 }) { response in
            // Shaker-specific popup orchestration BEFORE the dispatch so
            // the state machine doesn't race with popup presentation.
            if ble.isBarsysShakerConnected() {
                switch response {
                case .shakerNotFlat, .glassWaiting:
                    if popup == nil {
                        popup = .shakerFlatSurface(
                            message: "Please place the shaker on a flat surface."
                        )
                    }
                case .shakerFlat, .glassPlaced(is219: true), .cancelAcknowledged:
                    popup = nil
                default:
                    break
                }
            }

            viewModel.dispatch(
                response, ble: ble,
                onCompleted: {
                    router.push(.drinkComplete(recipeID))
                },
                onDismiss: {
                    // Ports `navigationController?.popViewController(animated:)`
                    // from UIKit's BleResponse extension — pops exactly
                    // one level off the stack. `@Environment(\.dismiss)`
                    // drives the NavigationStack to pop the CraftingView.
                    dismiss()
                }
            )
        }
        .barsysPopup($popup)
        // Cancel Drink popup — 1:1 port of UIKit showCustomAlertMultipleButtons
        // glass-card popup (replaces native .alert which lacks glass styling).
        .barsysPopup($cancelDrinkPopup, onPrimary: {
            HapticService.medium()
            viewModel.cancel(ble: ble)
        }, onSecondary: {
            // "No" — dismiss popup, continue crafting
        })
        // Ready to Pour popup — 1:1 port of UIKit showPourConfirmation
        // with glass card styling, cancelButtonColor=.segmentSelectionColor.
        .barsysPopup($pourConfirmPopup, onPrimary: {
            HapticService.medium()
            didResolvePourConfirm = true
            guard let recipe = env.storage.recipe(by: recipeID) else { return }
            env.analytics.track(TrackEventName.craftBegin.rawValue)
            Task { await viewModel.start(recipe: recipe, ble: ble) }
        }, onSecondary: {
            didResolvePourConfirm = true
            dismiss()
        })
        // Craftability-error popup — 1:1 port of UIKit
        // `showDefaultAlert(message: <error>, cancelTitle: OK)` calls in
        // `RecipePageViewController+Actions.performBarsys360CraftCheck`
        // L85-89 + `RecipeCraftingClass.craftCoasterRecipeWithUpdatedQuantity`
        // L294-296 + `RecipeCraftingClass.craftRecipeFromRecipeListing`
        // L61, L71 (also L192, L202 for the customized-recipe path). All
        // five UIKit branches emit the same single-OK alert and then
        // abort the craft push — in SwiftUI the CraftingView is already
        // on-screen (we build+validate inside `start`), so OK dismisses
        // us back to the previous screen.
        .barsysPopup(craftErrorBinding, onPrimary: {
            viewModel.craftError = nil
            dismiss()
        })
        // Perishable-cleaning popup — 1:1 port of UIKit
        // `showCustomAlertMultipleButtons(title: perishableDescriptionTitle,
        //   cancelButtonTitle: cleanAlertTitle,
        //   continueButtonTitle: okayButtonTitle,
        //   cancelButtonColor: .segmentSelectionColor,
        //   isCloseButtonHidden: true)` in
        // `performBarsys360CraftCheck` L91-99 + `RecipeCraftingClass.craftRecipeFromRecipeListing`
        // L81-88 + `craftCustomizedRecipeFromMakeMyOwn` L218-230.
        //
        // Button mapping:
        //   • Primary (RIGHT, `cancelButtonTitle` = "Clean",
        //     segmentSelectionColor fill) → pop back to stations
        //     cleaning — we dismiss here; the caller re-routes.
        //   • Secondary (LEFT, `continueButtonTitle` = "Okay") →
        //     proceed with the craft (run the cached command).
        //
        // Note on swap: UIKit's `cancelButtonTitle` is the orange
        // primary-action button (because UIKit's "cancel" semantics
        // here = "cancel the craft and clean"), which maps to our
        // `primaryTitle` slot. "Okay" is the dismiss-and-continue,
        // matching our `secondaryTitle`.
        .barsysPopup(perishablePromptBinding, onPrimary: {
            HapticService.medium()
            viewModel.cancelForPerishableCleaning()
            // Pop back — the station cleaning flow is a separate
            // screen the user can reach from Control Center. We
            // avoid hard-coding navigation here to stay router-
            // agnostic (the UIKit navigation is also conditional
            // on a `navigationController` being present).
            dismiss()
        }, onSecondary: {
            viewModel.continueAfterPerishable(ble: ble)
        })
    }

    /// Bridge `viewModel.craftError` → `BarsysPopup?` so we can reuse
    /// the shared `.barsysPopup(...)` modifier. UIKit uses a single
    /// `showDefaultAlert(message:, cancelTitle: OK)` for every error
    /// case — we mirror that by always rendering `.alert` with the
    /// localized message as the title (matches UIKit which puts the
    /// copy in the alert title, not message body).
    private var craftErrorBinding: Binding<BarsysPopup?> {
        Binding(
            get: {
                guard let err = viewModel.craftError else { return nil }
                return .alert(
                    title: err.message,
                    message: nil,
                    primaryTitle: ConstantButtonsTitle.okButtonTitle
                )
            },
            set: { newValue in
                if newValue == nil { viewModel.craftError = nil }
            }
        )
    }

    /// Bridge `viewModel.perishablePromptVisible` → `BarsysPopup?`.
    /// Mirrors UIKit `showCustomAlertMultipleButtons(title:
    /// perishableDescriptionTitle, cancelButtonTitle: cleanAlertTitle,
    /// continueButtonTitle: okayButtonTitle, …)` 1:1.
    private var perishablePromptBinding: Binding<BarsysPopup?> {
        Binding(
            get: {
                guard viewModel.perishablePromptVisible else { return nil }
                return .confirm(
                    title: Constants.perishableDescriptionTitle,
                    message: nil,
                    primaryTitle: Constants.cleanAlertTitle,
                    secondaryTitle: Constants.okayButtonTitle,
                    primaryFillColor: "segmentSelectionColor",
                    isCloseHidden: true
                )
            },
            set: { newValue in
                if newValue == nil { viewModel.perishablePromptVisible = false }
            }
        )
    }

    /// Single source of truth for "should we show the pour confirmation
    /// now, or bypass and start crafting directly?". Called from both
    /// `.onAppear` (the primary entry point that fires on every push
    /// AND every re-appearance) and `.task(id: recipeID)` (a safety
    /// net in case the recipe id changes while the view is alive).
    ///
    /// 1:1 port of UIKit `CraftingViewController.viewDidLoad` L114-122:
    /// ```
    /// if skipPourConfirmation || AppStateManager.shared.isSpeakEasyCase {
    ///     updateDeviceNameImage()
    ///     makeDrinkInitiallyOrAgain()
    /// } else {
    ///     showPourConfirmation { [weak self] in
    ///         self?.makeDrinkInitiallyOrAgain()
    ///     }
    ///     updateDeviceNameImage()
    /// }
    /// ```
    ///
    /// Guards:
    ///   • `viewModel.state == .idle` — don't restart a craft that's
    ///     already mid-flight (user could swipe-back during dispensing
    ///     and swipe-forward; that's not a "Make It Again").
    ///   • `!didResolvePourConfirm` — don't re-show the alert if the
    ///     user already confirmed this round.
    private func runCraftEntryFlow() {
        guard let recipe = env.storage.recipe(by: recipeID),
              viewModel.state == .idle,
              !didResolvePourConfirm else { return }

        // Consume the "Craft again" signal from DrinkCompleteView —
        // when the user tapped "Craft again" on DrinkComplete, UIKit
        // sets `craftingVc.skipPourConfirmation = true` before
        // re-entering the flow so the confirmation alert is bypassed
        // on the second craft. `consumeMakeItAgainPending()` reads +
        // clears the flag atomically so the bypass only applies once.
        let bypassViaMakeItAgain = appState.consumeMakeItAgainPending()

        if skipPourConfirmation
            || appState.isSpeakEasyCase
            || bypassViaMakeItAgain {
            didResolvePourConfirm = true
            env.analytics.track(TrackEventName.craftBegin.rawValue)
            // Medium haptic on the implicit "Start Pouring" —
            // matches the haptic the user would have felt if they'd
            // manually confirmed (UIKit fires `HapticService.medium()`
            // on the confirm button tap; we mirror it here so the
            // Make-It-Again path feels continuous with the first-
            // craft confirmation path).
            if bypassViaMakeItAgain {
                HapticService.medium()
            }
            Task { await viewModel.start(recipe: recipe, ble: ble) }
        } else {
            // UIKit CraftingViewController L128-143:
            //   showCustomAlertMultipleButtons(
            //     cancelButtonTitle: "Start Pouring",
            //     continueButtonTitle: "Cancel",
            //     cancelButtonColor: .segmentSelectionColor ← makes it orange/brand gradient
            //   )
            pourConfirmPopup = .confirm(
                title: Constants.readyToPourTitle,
                message: "Place your glass and confirm to start crafting.",
                primaryTitle: "Start Pouring",
                secondaryTitle: ConstantButtonsTitle.cancelButtonTitle,
                primaryFillColor: "segmentSelectionColor"
            )
        }
    }

    /// Fallback display when `glassStatusText` is empty — keeps the UI
    /// copy meaningful in edge states (idle, dispensing, completed).
    private func displayFallback(for state: CraftingState) -> String {
        switch state {
        case .idle: return Constants.placeGlassToBegin
        case .waitingForGlass, .glassLifted: return Constants.placeGlassToBegin
        case .dispensing: return ""
        case .awaitingGlassRemoval: return Constants.removeGlassToCompleteTheDrink
        case .cancelling, .cancelledWaitingForGlass: return Constants.removeGlassToCancelTheDrink
        case .cancelAcknowledged: return ""
        case .completed: return Constants.drinkCompletedStr
        }
    }

    /// 1:1 port of UIKit `viewModel.deviceInQueueImage` /
    /// `devicePouringImage` — chooses the correct device artwork based
    /// on the current BLE device kind AND whether dispensing has begun.
    private func deviceImageName() -> String {
        let isPouring = viewModel.state == .dispensing
        if ble.isBarsys360Connected() {
            return isPouring ? "barsys_360" : "barsys_360_inqueue"
        }
        if ble.isCoasterConnected() {
            return isPouring ? "barsys_coaster" : "barsys_coaster_inqueue"
        }
        if ble.isBarsysShakerConnected() {
            return "barsys_shaker"
        }
        // Fallback when no device is connected — still show the hero
        // image so the layout doesn't collapse.
        return "barsys_360_inqueue"
    }

    // Bottom button row — 1:1 port of storyboard `03v-cy-EVc`
    // (fillEqually stackView, 2 buttons 168.33×40, 8pt spacing).
    // UIKit hides the `Done` button permanently and shows only the
    // `Cancel` button, which is itself hidden during
    // `awaitingGlassRemoval` and `completed` states.
    //
    // Button style:
    //   • 168×40
    //   • roundCorners 8 (userDefinedRuntimeAttribute on the button)
    //   • No background fill, black title color, 1pt silverColor
    //     border added at runtime via `cancelButton.makeBorder`.
    //   • iOS 26+ applies `applyCancelCapsuleGradientBorderStyle()`.
    @ViewBuilder
    private func bottomActions(for recipe: Recipe) -> some View {
        HStack {
            switch viewModel.state {
            case .completed:
                // UIKit pushes DrinkComplete on dataFlushed, so this
                // fallback is only ever reached if the user navigates
                // back without completing. Match UIKit "Done" dormant
                // look.
                Spacer()
            case .awaitingGlassRemoval:
                // UIKit hides the cancel button here — keep an empty
                // spacer so layout doesn't shift.
                Spacer().frame(height: 40)
            default:
                // UIKit: applyCancelCapsuleGradientBorderStyle() on iOS 26+,
                // makeBorder(1pt, silverColor) on pre-26. 168×40pt centered.
                Button {
                    HapticService.light()
                    // UIKit L302-314: cancelButtonColor: .segmentSelectionColor
                    // "Yes, Cancel" gets orange/brand fill, NOT destructive red
                    cancelDrinkPopup = .confirm(
                        title: "Cancel Drink",
                        message: "Are you sure you want to cancel the current drink?",
                        primaryTitle: "Yes, Cancel",
                        secondaryTitle: "No",
                        primaryFillColor: "segmentSelectionColor"
                    )
                } label: {
                    if colorScheme == .dark {
                        // Dark-mode only — mirror the recipe page's
                        // "Add to Favorites" capsule EXACTLY so both
                        // cancel-style buttons in the app share the
                        // same visual family in dark mode:
                        //   • Capsule fill = Color.white.opacity(0.85)
                        //     (same as `cancelCapsuleBackground` on
                        //     RecipesScreens.swift).
                        //   • 3-stop white→light-grey gradient stroke
                        //     at 1.5pt (same as `cancelCapsuleBorder`).
                        // Light mode is UNCHANGED — it still routes
                        // through the shared `cancelCapsule` helper
                        // with `showsBorder: false`, so every other
                        // caller of that helper stays bit-identical.
                        Text(ConstantButtonsTitle.cancelButtonTitle)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.85))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.95),
                                                Color(white: 0.85).opacity(0.9),
                                                Color.white.opacity(0.95)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .clipShape(Capsule(style: .continuous))
                            .frame(width: 168)
                    } else {
                        Text(ConstantButtonsTitle.cancelButtonTitle)
                            .cancelCapsule(height: 40, cornerRadius: 20,
                                           textColor: .black,
                                           showsBorder: false)
                            .font(.system(size: 14))
                            .frame(width: 168)
                    }
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel("Cancel drink")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}

// MARK: - CraftingIngredientRowView (1:1 port of `CraftingTableViewCell`)
//
// UIKit `CraftingTableViewCell.xib` structure (row 67pt):
//   • `utI-wh-Loo` "viewGlass": 16pt leading/trailing, 5pt top/bottom
//     → 343×52 pill. Fully rounded via `BarsysCornerRadius.pill`
//     (= height/2). Background swaps per state:
//       – iOS 26+ → `addGlassEffect(cornerRadius: .xlarge, alpha: 1.0)`
//       – iOS <26 → black/white 7% gradient + 1pt `#F2F2F2` border
//       – nowPouring → `sideMenuSelectionColor` fill (overrides glass)
//   • `ingredientNameLabel` (aZA): leading=24, centerY, max 2 lines,
//     system 12pt, `unSelectedColor` xib-default → runtime overridden
//     to `craftingTitleColor` (most states) or `veryDarkGrayColor`
//     (nowPouring).
//   • Quantity + status stack (`Nbg`): 161×24, trailing=24, centerY:
//       – `quantityLabel` (rK6): 60pt wide, right-aligned, system
//         12pt LIGHT, `craftingTitleColor`.
//       – `currentIngredientStatusLabel` (skL): 90pt wide, center-
//         aligned, system 12pt (BOLD in nowPouring per runtime).
//
// State → status text (UIKit `+TableView.swift` L45-L80):
//   • nowPouring → "Pour now" (Coaster/Shaker) OR "Now pouring" (360)
//   • poured     → "Poured"
//   • inQueue    → "In queue"
//   • empty      → "--"
private struct CraftingIngredientRowView: View {
    let name: String
    let quantity: Double
    let unit: MeasurementUnit
    let status: CraftingViewModel.IngredientPourStatus

    /// iPad scales every metric on the crafting ingredient row up so
    /// the 52pt iPhone-spec pill doesn't read as a thumbnail strip on
    /// the wider iPad canvas. Mirrors the same iPad-bump pattern
    /// `RecipeIngredientRow` uses for its INGREDIENTS table on
    /// recipe-detail (RecipesScreens.swift L2948-2951).
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var nameFontSize: CGFloat { isIPad ? 16 : 12 }
    private var qtyFontSize: CGFloat { isIPad ? 16 : 12 }
    private var statusFontSize: CGFloat { isIPad ? 16 : 12 }
    private var qtyFieldWidth: CGFloat { isIPad ? 90 : 60 }
    private var statusFieldWidth: CGFloat { isIPad ? 130 : 90 }
    private var pillHeight: CGFloat { isIPad ? 64 : 52 }
    private var sideInset: CGFloat { isIPad ? 28 : 24 }

    var body: some View {
        HStack(spacing: isIPad ? 10 : 6) {
            Text(displayName)
                .font(.system(size: nameFontSize))
                .foregroundStyle(textColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, sideInset)

            // Quantity + status cluster (Nbg-tv-qKT). 60pt quantity,
            // 5pt gap, 90pt status, trailing 24pt. iPad bumps the
            // widths + gap so the larger fonts don't collide.
            HStack(spacing: isIPad ? 8 : 5) {
                Text(quantityText)
                    .font(.system(size: qtyFontSize, weight: .light))
                    .foregroundStyle(textColor)
                    .frame(width: qtyFieldWidth, alignment: .trailing)
                Text(statusText)
                    .font(.system(size: statusFontSize, weight: .bold))
                    .foregroundStyle(textColor)
                    .frame(width: statusFieldWidth, alignment: .center)
            }
            .padding(.trailing, sideInset)
        }
        .frame(height: pillHeight)
        .background(pillBackground)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    // MARK: - Derived

    private var displayName: String {
        status == .empty ? "-NA-" : name
    }

    private var quantityText: String {
        switch unit {
        case .ml: return "\(Int(quantity)) ml"
        case .oz:
            let oz = quantity / 29.5735
            return String(format: "%.2f oz", oz)
        }
    }

    /// Ports UIKit +TableView.swift L45-L80 — different strings per
    /// device kind for `nowPouring`. In SwiftUI we don't have the BLE
    /// service here, so the ViewModel resolves the label before setting
    /// the status. We just use the text the status maps to.
    private var statusText: String {
        switch status {
        case .nowPouring: return Constants.nowPouringTitle
        case .poured:     return Constants.pouredTitle
        case .inQueue:    return Constants.inQueueStr
        case .empty:      return Constants.emptyDoubleDash
        }
    }

    private var textColor: Color {
        status == .nowPouring
            ? Color("veryDarkGrayColor")
            : Color("craftingTitleColor")
    }

    @ViewBuilder
    private var pillBackground: some View {
        // Always half the pill height so the row stays a true capsule
        // on both iPhone (52pt → 26) and iPad (64pt → 32).
        let radius: CGFloat = pillHeight / 2
        switch status {
        case .nowPouring:
            // UIKit L66-75: drops the glass effect and uses the brand
            // side-menu selection colour. On iOS 26+ the real app
            // adds a glossy multi-gradient; we approximate via a soft
            // vertical gradient so the "actively pouring" row reads
            // clearly even without UIGlassEffect.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color("sideMenuSelectionColor"),
                                 Color("sideMenuSelectionColor").opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        default:
            // Glass pill (inQueue / poured / empty). iOS 26+ uses
            // `.ultraThinMaterial`; older iOS mirrors the UIKit
            // fallback (7% black→white gradient + 1pt #F2F2F2 stroke).
            glassPill(radius: radius)
        }
    }

    @ViewBuilder
    private func glassPill(radius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        // Trait-resolved border so the rim is visible
                        // against both the light and the dark crafting
                        // canvases. Light mode keeps the historical
                        // #F2F2F2 hairline; dark mode uses a soft
                        // white@0.18 line so the pill edge reads on
                        // the dark surface instead of vanishing.
                        .stroke(Color(UIColor { trait in
                            trait.userInterfaceStyle == .dark
                                ? UIColor(white: 1.0, alpha: 0.18)
                                : UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1.0)
                        }), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.07),
                                 Color.white.opacity(0.07)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Pre-iOS 26 fallback: trait-resolved closure so the
                // pill fill flips automatically when the user toggles
                // light / dark at runtime. Light mode preserves the
                // EXACT historical white@0.8 fill (bit-identical
                // pixels). Dark mode returns a near-clear white@0.10
                // — same recipe used by `pillGlassBackground` in
                // `RecipeIngredientRow` (RecipesScreens.swift:3160) —
                // so the crafting and recipe ingredient pills look
                // identical on the dark canvas instead of the
                // crafting variant rendering as a stark white slab.
                .background(
                    Color(UIColor { trait in
                        trait.userInterfaceStyle == .dark
                            ? UIColor(white: 1.0, alpha: 0.10)
                            : UIColor(white: 1.0, alpha: 0.8) // EXACT historical
                    }),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        // Trait-resolved border — see iOS 26+ branch
                        // for the same rationale (rim must be visible
                        // on both canvases).
                        .stroke(Color(UIColor { trait in
                            trait.userInterfaceStyle == .dark
                                ? UIColor(white: 1.0, alpha: 0.18)
                                : UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1.0)
                        }), lineWidth: 1)
                )
        }
    }
}

// MARK: - DrinkCompleteView (1:1 port of DrinkCompleteViewController)
//
// UIKit storyboard hierarchy (Crafting.storyboard, scene F7y-N5-Rnz):
//
//   Main View (393×852)
//   ├── Header View (393×60) — back button, device info, side menu
//   └── ScrollView (393×555, y=60)
//       └── Content View (393×639.33)
//           ├── Recipe Name Label — top: 47
//           ├── Drink Image — 211×211 circular, top: 50 below name
//           ├── "Drink is ready!" Label — 16pt, centered, top: 40 below image
//           ├── Garnish Label — bold "Garnish:" + names, top: 10
//           ├── Additional Label — bold "Additional Ingredients:" + names
//           └── Buttons Stack (vertical, spacing: 8, 345×151)
//               ├── "Make it again" — 345×45, primaryBackgroundColor,
//               │   8pt corners, 15pt medium, 1pt craftButtonBorderColor
//               │   (iOS 26+ cancelCapsuleGradientBorderStyle)
//               ├── "Customize" — same style
//               └── "Done" — PrimaryOrangeButton, brandTanColor/orange,
//                   8pt corners (iOS 26+ capsule with orange gradient)
//
// Fonts: SFProDisplay (body=16pt, buttons=15pt medium)
// Colors: brandTanColor (Done), primaryBackgroundColor (secondary buttons),
//         craftButtonBorderColor (borders), charcoalGrayColor (text)

struct DrinkCompleteView: View {
    let recipeID: RecipeID
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService
    @Environment(\.dismiss) private var dismiss
    /// Used to pin the Done button's peach-tan gradient in dark mode
    /// (matches the Recipe Page Craft button treatment — see
    /// `drinkCompleteDoneBackground`). Light mode is untouched.
    @Environment(\.colorScheme) private var colorScheme

    /// Rating popup state — 1:1 port of UIKit DrinkCompleteViewController
    /// viewDidLoad L126-134 which checks shouldShowRatingPrompt interval.
    @State private var ratingPopup: BarsysPopup? = nil

    /// Hides "Make it again" when SpeakEasy case is active (UIKit L106-108).
    private var isSpeakEasyCase: Bool {
        AppStateManager.shared.isSpeakEasyCase
    }

    // Toolbar device helpers (matches UIKit header device info stack).
    private var deviceIconName: String {
        if ble.isBarsys360Connected() || isSpeakEasyCase { return "icon_barsys_360" }
        if ble.isCoasterConnected() { return "icon_barsys_coaster" }
        if ble.isBarsysShakerConnected() { return "icon_barsys_shaker" }
        return ""
    }
    private var deviceKindName: String {
        if ble.isBarsys360Connected() || isSpeakEasyCase { return Constants.barsys360NameTitle }
        if ble.isCoasterConnected() { return Constants.barsysCoasterTitle }
        if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
        return ""
    }

    /// Garnish ingredients — recipe ingredients with category primary == "garnish"
    private func garnishIngredients(for recipe: Recipe) -> [Ingredient] {
        recipe.ingredients?.filter {
            $0.category?.primary?.lowercased() == "garnish"
        } ?? []
    }

    /// Additional ingredients — optional ingredients or category primary == "additional"
    private func additionalIngredients(for recipe: Recipe) -> [Ingredient] {
        let allNonBase = (recipe.ingredients ?? []).filter {
            $0.ingredientOptional == true
                || $0.category?.primary?.lowercased() == "additional"
        }
        return allNonBase
    }

    private func optimizedImageURL(for recipe: Recipe) -> URL? {
        guard let raw = recipe.image?.url, !raw.isEmpty else { return nil }
        return raw.getImageUrl()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let recipe = env.storage.recipe(by: recipeID) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Recipe Name — top: 47pt from content top
                        // UIKit: lblRecipeName, bold body (16pt)
                        Text(recipe.displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color("charcoalGrayColor"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 47)

                        // Drink Image — 211×211 circular
                        // UIKit: drinkCompleteImage, roundCorners = height/2,
                        // SDWebImage with placeholder myDrink
                        AsyncImage(url: optimizedImageURL(for: recipe)) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            case .empty:
                                Color("lightBorderGrayColor")
                            case .failure:
                                // Light mode keeps the placeholder PNG;
                                // dark mode template-tints with
                                // `softWhiteText` so the dark glyph
                                // doesn't blend into the dark fallback
                                // background.
                                if colorScheme == .dark {
                                    Image("myDrink")
                                        .renderingMode(.template)
                                        .resizable().aspectRatio(contentMode: .fit)
                                        .foregroundStyle(Theme.Color.softWhiteText)
                                        .padding(30)
                                } else {
                                    Image("myDrink")
                                        .resizable().aspectRatio(contentMode: .fit)
                                        .padding(30)
                                }
                            @unknown default:
                                Color("lightBorderGrayColor")
                            }
                        }
                        .frame(width: 211, height: 211)
                        .background(Color("lightBorderGrayColor"))
                        .clipShape(Circle())
                        .padding(.top, 50)

                        // "Drink is ready!" — 16pt, centered
                        // UIKit: zYW-Hh-bze label, charcoalGrayColor
                        Text("Drink is ready!")
                            .font(.system(size: 16))
                            .foregroundStyle(Color("charcoalGrayColor"))
                            .padding(.top, 40)

                        // Garnish & Additional labels
                        // UIKit: attributed strings with bold prefix
                        let garnish = garnishIngredients(for: recipe)
                        let additional = additionalIngredients(for: recipe)

                        if !garnish.isEmpty {
                            drinkCompleteAttributedLabel(
                                boldPrefix: "Garnish: ",
                                text: garnish.map { $0.name }.joined(separator: ", ")
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                        }

                        if !additional.isEmpty {
                            drinkCompleteAttributedLabel(
                                boldPrefix: "Additional Ingredients: ",
                                text: additional.map { $0.name }.joined(separator: ", ")
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 6)
                        }

                        // Action Buttons Stack
                        // UIKit: phe-0t-jY4 vertical stack, spacing: 8, 345×151
                        // Leading/trailing: 24pt each → 345pt width on 393pt screen
                        VStack(spacing: 8) {
                            // "Make it again" — hidden if SpeakEasy case
                            // UIKit: makeItAgainButton, 345×45, addBounceEffect,
                            //   font: .body/.medium (16pt medium)
                            //   iOS 26+: applyCancelCapsuleGradientBorderStyle
                            //   pre-26:  makeBorder(1, craftButtonBorderColor), no fill
                            if !isSpeakEasyCase {
                                Button {
                                    HapticService.light()
                                    env.analytics.track(TrackEventName.craftMakeAgain.rawValue)
                                    AppStateManager.shared.makeItAgainPending = true
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                                        dismiss()
                                    }
                                } label: {
                                    Text("Make it again")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color("appBlackColor"))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 45)
                                        .background(drinkCompleteCancelBackground)
                                        .overlay(drinkCompleteCancelBorder)
                                }
                                .buttonStyle(BounceButtonStyle())
                                .accessibilityLabel("Make it again")
                                .accessibilityHint("Crafts the same drink again")
                            }

                            // "Customize" — same style as Make it again
                            // UIKit: customizeButton, identical styling
                            Button {
                                HapticService.light()
                                env.analytics.track(TrackEventName.craftCustomise.rawValue)
                                router.popToRoot()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    router.push(.recipeDetail(recipeID))
                                }
                            } label: {
                                Text("Customize")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color("appBlackColor"))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 45)
                                    .background(drinkCompleteCancelBackground)
                                    .overlay(drinkCompleteCancelBorder)
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityLabel("Customize")
                            .accessibilityHint("Opens recipe customization")

                            // "Done" — PrimaryOrangeButton
                            // UIKit: doneButton, font: .body/.medium (16pt medium)
                            //   iOS 26+: makeOrangeStyle (capsule gradient)
                            //   pre-26:  makeBorder(1, sideMenuSelectionColor), 8pt corners
                            Button {
                                HapticService.success()
                                doneAction()
                            } label: {
                                Text("Done")
                                    .font(.system(size: 16, weight: .medium))
                                    // Title colour is pinned to BLACK in
                                    // both appearance modes now that the
                                    // Done button renders a peach-tan
                                    // gradient on both light AND dark
                                    // (dark mode override — see
                                    // `drinkCompleteDoneBackground`).
                                    // Black contrasts best against the
                                    // peach fill and matches every other
                                    // brand primary CTA in the app
                                    // (Craft, Clean, Continue, Stop).
                                    // Light-mode pixels stay identical
                                    // because the previous code also
                                    // resolved to black in light mode.
                                    .foregroundStyle(Color.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 45)
                                    .background(drinkCompleteDoneBackground)
                                    .overlay(drinkCompleteDoneBorder)
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityLabel("Done")
                            .accessibilityHint("Returns to the previous screen")
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 30)
                        .padding(.bottom, 75)
                    }
                }
            } else {
                EmptyStateView(systemImage: "checkmark.seal",
                               title: Constants.drinkCompletedStr,
                               subtitle: "")
            }
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { drinkCompleteToolbar }
        .chooseOptionsStyleNavBar()
        .onAppear {
            env.analytics.track(TrackEventName.craftCompleted.rawValue)

            // 1:1 port of UIKit DrinkCompleteViewController viewDidLoad L126-134:
            // Rating prompt shown on a 24-hour interval (perishableInterval = 86400s).
            // UIKit: if shouldShowRatingPrompt → markRatingShown → showCustomAlertMultipleButtons
            //   title: wouldYouLikeRatingTextAfterDrinkCompleted
            //   cancelButton: "Yes please!" (opens App Store)
            //   continueButton: "No, stay in the app"
            //   cancelButtonColor: segmentSelectionColor
            //   closeButton: hidden
            if shouldShowRatingPrompt() {
                markRatingShown()
                ratingPopup = .confirm(
                    title: Constants.wouldYouLikeRatingTextAfterDrinkCompleted,
                    message: nil,
                    primaryTitle: ConstantButtonsTitle.yesPleaseButtonTitle,
                    secondaryTitle: ConstantButtonsTitle.noStayInAppButtonTitle,
                    primaryFillColor: "segmentSelectionColor",
                    isCloseHidden: true
                )
            }
        }
        // Rating popup overlay — uses BarsysPopup glass card matching UIKit
        // AlertPopUpHorizontalStackController styling.
        .barsysPopup($ratingPopup, onPrimary: {
            // "Yes please!" → open App Store review URL
            if let url = URL(string: WebViewURLs.appStoreReviewUrl) {
                UIApplication.shared.open(url)
            }
        }, onSecondary: {
            // "No, stay in the app" → just dismiss
        })
    }

    // MARK: - Rating prompt interval logic
    // 1:1 port of DrinkCompleteViewModel.shouldShowRatingPrompt / markRatingShown.
    // Shows rating prompt after 24 hours (perishableInterval = 86400 seconds)
    // since the last time it was shown. First craft always shows it.

    private func shouldShowRatingPrompt() -> Bool {
        // Key matches UIKit UserDefaultsClass "lastRatingViewShownTimeInterval"
        let key = "lastRatingViewShownTimeInterval"
        let savedTimestamp = UserDefaults.standard.double(forKey: key)
        if savedTimestamp == 0 { return true } // Never shown before
        let elapsed = Date().timeIntervalSince1970 - savedTimestamp
        // UIKit: differenceTimeStamp > NumericConstants.perishableInterval (86400s = 24 hours)
        return elapsed > NumericConstants.perishableInterval
    }

    private func markRatingShown() {
        let key = "lastRatingViewShownTimeInterval"
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }

    // MARK: - Attributed label helper
    // UIKit: makeAttributedString(fullText:boldPart:normalFont:boldFont:)
    // Renders "Garnish: Lime, Mint" with "Garnish:" in bold 16pt.
    private func drinkCompleteAttributedLabel(boldPrefix: String, text: String) -> some View {
        (Text(boldPrefix).font(.system(size: 16, weight: .bold))
            + Text(text).font(.system(size: 16)))
            .foregroundStyle(Color("charcoalGrayColor"))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Toolbar (matches UIKit header: back, device info, side menu)
    @ToolbarContentBuilder
    private var drinkCompleteToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                HapticService.light()
                doneAction()
            } label: {
                // Light mode keeps the original PNG so pixels stay
                // bit-identical to the existing UIKit-parity render.
                // Dark mode template-tints with `softWhiteText` so the
                // dark chevron doesn't sink into the dark canvas.
                if colorScheme == .dark {
                    Image("back")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(Theme.Color.softWhiteText)
                        .frame(width: 9, height: 17)
                        .frame(width: 30, height: 30)
                } else {
                    Image("back")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 9, height: 17)
                        .frame(width: 30, height: 30)
                }
            }
            .accessibilityLabel("Back")
            .accessibilityHint("Returns to the previous screen")
        }

        // UIKit parity — icon only, 25×25, name label hidden
        // (CraftingViewController.swift:148 and :175 both set
        // `lblDeviceName.isHidden = true` and never reverse it).
        if (ble.isAnyDeviceConnected || isSpeakEasyCase), !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                DevicePrincipalIcon(assetName: deviceIconName,
                                    accessibilityLabel: "Connected device, \(deviceKindName)")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationRightGlassButtons(
                showsLeading: false,
                onFavorites: {},
                onProfile: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        router.showSideMenu = true
                    }
                }
            )
        }
    }

    // MARK: - Done action
    // UIKit: doneAction() pops to the first DrinkCompletionDestination
    // in the nav stack (FavouritesRecipesAndDrinks, MakeMyOwn,
    // RecipePage, ReadyToPour, MixlistDetail, or BarBot).
    // SwiftUI: pop to root — the router handles tab-scoped nav stacks.
    // MARK: - DrinkComplete button styles (1:1 UIKit DrinkCompleteViewController L91-158)

    /// "Make it again" / "Customize" — applyCancelCapsuleGradientBorderStyle on iOS 26+,
    /// makeBorder(1, craftButtonBorderColor) with NO fill on pre-26.
    @ViewBuilder
    private var drinkCompleteCancelBackground: some View {
        if #available(iOS 26.0, *) {
            // applyCancelCapsuleGradientBorderStyle → glass capsule
            Capsule(style: .continuous).fill(.regularMaterial)
        } else {
            // No fill — just transparent with border
            Capsule(style: .continuous).fill(Color.clear)
        }
    }

    @ViewBuilder
    private var drinkCompleteCancelBorder: some View {
        if #available(iOS 26.0, *) {
            // applyCancelCapsuleGradientBorderStyle → 1.5pt gradient border
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color(white: 0.85).opacity(0.9),
                            Color.white.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        } else {
            // makeBorder(width: 1, color: .craftButtonBorderColor)
            Capsule(style: .continuous)
                .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
        }
    }

    /// "Done" — makeOrangeStyle on iOS 26+ (brand gradient capsule),
    /// makeBorder(1, sideMenuSelectionColor) on pre-26.
    /// NOTE: pre-26 uses sideMenuSelectionColor border, NOT craftButtonBorderColor.
    ///
    /// Dark-mode override: both code paths swap the brand gradient /
    /// clear fill for the same hard-coded peach-tan LinearGradient the
    /// Recipe Page Craft button uses
    /// (`ReadyToPourView.craftButtonBackground` L970-982 and
    /// `RecipesScreens.primaryOrangeButtonBackground`). The reasons:
    ///
    /// • The `brandGradientTop` / `brandGradientBottom` assets have
    ///   dark-appearance variants that resolve to a near-black brown;
    ///   leaving the iOS 26+ path untouched would render the Done
    ///   capsule as a dark muddy pill in dark mode, not the orange
    ///   CTA the user expects.
    /// • The pre-26 clear-fill + `sideMenuSelectionColor` border style
    ///   barely reads on the dark `primaryBackgroundColor` (0.11 luma)
    ///   background — the button visually disappears. Filling with the
    ///   peach gradient in dark mode brings it in line with every other
    ///   brand primary CTA (Craft, Clean, Continue, Stop).
    ///
    /// Light-mode pixels are unchanged on BOTH iOS 26+ AND pre-26 —
    /// the `else` branches of the `colorScheme == .dark` checks below
    /// preserve the exact prior rendering.
    @ViewBuilder
    private var drinkCompleteDoneBackground: some View {
        if #available(iOS 26.0, *) {
            if colorScheme == .dark {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.980, green: 0.878, blue: 0.800),
                                Color(red: 0.949, green: 0.761, blue: 0.631)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                // Light mode — original asset-driven brand gradient.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color("brandGradientTop"), Color("brandGradientBottom")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        } else {
            if colorScheme == .dark {
                // Dark-mode pre-26 uses the same peach fill as iOS 26+
                // so the Done button reads as a solid CTA on the dark
                // background — matches Recipe Page Craft button dark.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.980, green: 0.878, blue: 0.800),
                                Color(red: 0.949, green: 0.761, blue: 0.631)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                // Light-mode pre-26 — EXACT original (clear + border).
                Capsule(style: .continuous).fill(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var drinkCompleteDoneBorder: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            if colorScheme == .dark {
                // Dark mode already has the peach fill from above —
                // the sideMenuSelectionColor border would clash, so
                // drop it entirely (matches Recipe Craft button
                // pre-26 dark: no border over the orange capsule).
                EmptyView()
            } else {
                // Light-mode pre-26 — EXACT original border.
                Capsule(style: .continuous)
                    .stroke(Color("sideMenuSelectionColor"), lineWidth: 1)
            }
        }
    }

    private func doneAction() {
        router.popToRoot()
    }
}
