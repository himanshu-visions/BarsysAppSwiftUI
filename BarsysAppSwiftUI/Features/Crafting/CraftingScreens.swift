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
struct CraftingIngredientRow: Identifiable, Hashable {
    let id = UUID()
    var station: StationName
    var ingredientName: String
    var ingredientQuantity: Double
    var category: IngredientCategory?
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

    private(set) var recipe: Recipe?
    /// Mirrors UIKit `arrStations` populated by `MixlistsUpdateClass.getStationsHere`
    /// on the Barsys 360 path.
    private(set) var arrStations: [CraftingIngredientRow] = []

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
    func start(recipe: Recipe, ble: BLEService) async {
        self.recipe = recipe
        self.glassStatusText = initialGlassStatusText
        self.state = .idle
        self.currentIngredient = 0
        self.completed = 0
        self.hasStartedDispensing = false
        self.overallProgress = 0

        // Seed the rendered ingredient list from the recipe so the table
        // shows rows before the device responds.
        recipeIngredients = (recipe.ingredients ?? []).map {
            CraftingIngredientRow(
                station: .a, // actual station is resolved after server fetch
                ingredientName: $0.name,
                ingredientQuantity: $0.quantity ?? 0,
                category: $0.category
            )
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

    /// Ports `CraftingViewController.getIngredientsFor360StartCraftingFlow()`:
    /// loads the 6 device stations from the server, sorts + filters the
    /// recipe ingredient list, then sends the composed `200,…` command.
    private func load360AndSendCommand(ble: BLEService) async {
        let deviceName = ble.getConnectedDeviceName()
        let stations = await StationsAPIService.loadStations(deviceName: deviceName)
        arrStations = stations.map {
            CraftingIngredientRow(
                station: $0.station,
                ingredientName: $0.ingredientName,
                ingredientQuantity: $0.ingredientQuantity,
                category: nil
            )
        }

        // UIKit only pours non-empty stations. Filter rows that have
        // either no name, "--", or "NA"/"N/A".
        recipeIngredients = recipeIngredients.filter { row in
            let trimmed = row.ingredientName.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty
                && trimmed != "--"
                && trimmed.lowercased() != "n/a"
                && trimmed.lowercased() != "na"
        }

        let command = build360Command(stations: arrStations,
                                      recipeIngredients: recipeIngredients)
        _ = ble.send(.craftRaw(command: command))
    }

    /// 1:1 port of `BleCommandBuilder.buildCommandString` for Barsys 360.
    ///
    /// Walks A→F, matching each station to a recipe ingredient by
    /// `category.primary + category.secondary` (lowercased). If matched,
    /// emits `",{stationNumber},{quantity}"`; otherwise emits `",0,0"`.
    /// Output is padded with `,0` pairs to exactly 15 components total.
    private func build360Command(stations: [CraftingIngredientRow],
                                 recipeIngredients: [CraftingIngredientRow]) -> String {
        let order: [(StationName, Int)] = [
            (.a, 1), (.b, 2), (.c, 3), (.d, 4), (.e, 5), (.f, 6)
        ]
        var cmd = "200"
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
                cmd += ",\(num),\(Int(m.ingredientQuantity))"
            } else {
                cmd += ",0,0"
            }
        }
        // Pad to 15 components.
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
        // Completion path (UIKit L61-68, L77-87).
        if currentIngredient > 0, state == .awaitingGlassRemoval {
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
        }
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
                isPerishable: false
            )
        }
        // UIKit sorts by stationName.rawValue before building the dict
        // so the payload order matches the server's expected A→F order.
        updated.sort { $0.station.rawValue < $1.station.rawValue }

        _ = await StationsAPIService.patchAllStations(
            deviceName: deviceName,
            stations: updated
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
    @StateObject private var viewModel = CraftingViewModel()
    @State private var showCancelConfirm = false
    /// Drives the "Ready to Pour?" confirmation alert. Shown on first
    /// appear unless `skipPourConfirmation` / `isSpeakEasyCase`.
    /// 1:1 with UIKit `showPourConfirmation(onConfirm:)` (L128-143).
    @State private var showPourConfirm = false
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
                            Text(viewModel.glassStatusText.isEmpty
                                 ? displayFallback(for: viewModel.state)
                                 : viewModel.glassStatusText)
                                .font(.system(size: 16))
                                .foregroundStyle(Color("darkGrayTextColor"))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.top, 47)

                            // Device image (IsT-iE-QYL) 120×120, center,
                            // 30pt below status. Uses in-queue variant
                            // when idle/waiting, pouring variant when
                            // actively dispensing — mirrors UIKit
                            // `deviceInQueueImage` / `devicePouringImage`.
                            Image(deviceImageName())
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .padding(.top, 30)

                            // Recipe name (vHh-PF-hYT): system 16pt
                            // charcoalGrayColor, centered, y=44 below
                            // the device image.
                            Text(recipe.displayName)
                                .font(.system(size: 16))
                                .foregroundStyle(Color("charcoalGrayColor"))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.top, 44)

                            // Ingredient glass pill list (tblCrafting).
                            // Auto-expanding height via a VStack of cells
                            // (UIKit observes `contentSize` KVO).
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
                                .padding(.top, 42) // matches jNS-Yd-QVB constraint
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
        .alert("Cancel Drink",
               isPresented: $showCancelConfirm,
               actions: {
            Button("Yes, Cancel", role: .destructive) {
                // Matches UIKit L312/L341: medium haptic on confirm.
                HapticService.medium()
                viewModel.cancel(ble: ble)
            }
            Button("No", role: .cancel) {}
        }, message: {
            Text("Are you sure you want to cancel the current drink?")
        })
        // 1:1 port of UIKit `showPourConfirmation(onConfirm:)`
        // (`CraftingViewController.swift` L128-143):
        //   title = "Ready to Pour?"
        //   subtitle = "Place your glass and confirm to start crafting."
        //   primary button: "Start Pouring" → HapticService.medium()
        //                   then start crafting
        //   secondary button: "Cancel" → pop nav (dismiss)
        //   close-button hidden + cancelButtonColor=.segmentSelectionColor
        //
        // SwiftUI alerts don't support tinted primary buttons or
        // custom close-button visibility — the semantic behaviour
        // (two-button destructive/default arrangement) is the part
        // that matters for parity.
        .alert(Constants.readyToPourTitle,
               isPresented: $showPourConfirm,
               actions: {
            Button("Start Pouring") {
                // UIKit L140: medium haptic on "Start Pouring" tap.
                HapticService.medium()
                didResolvePourConfirm = true
                guard let recipe = env.storage.recipe(by: recipeID) else { return }
                env.analytics.track(TrackEventName.craftBegin.rawValue)
                Task { await viewModel.start(recipe: recipe, ble: ble) }
            }
            Button(ConstantButtonsTitle.cancelButtonTitle, role: .cancel) {
                // UIKit L138: user declined → pop nav.
                didResolvePourConfirm = true
                dismiss()
            }
        }, message: {
            Text("Place your glass and confirm to start crafting.")
        })
        .barsysPopup($popup)
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
            showPourConfirm = true
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
                Button {
                    HapticService.light()
                    showCancelConfirm = true
                } label: {
                    Text(ConstantButtonsTitle.cancelButtonTitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.black)
                        .frame(width: 168, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color("silverColor"), lineWidth: 1)
                        )
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

    var body: some View {
        HStack(spacing: 6) {
            Text(displayName)
                .font(.system(size: 12))
                .foregroundStyle(textColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)

            // Quantity + status cluster (Nbg-tv-qKT). 60pt quantity,
            // 5pt gap, 90pt status, trailing 24pt.
            HStack(spacing: 5) {
                Text(quantityText)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(textColor)
                    .frame(width: 60, alignment: .trailing)
                Text(statusText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(textColor)
                    .frame(width: 90, alignment: .center)
            }
            .padding(.trailing, 24)
        }
        .frame(height: 52)
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
        let radius: CGFloat = 26 // fully rounded on a 52pt pill
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
                        .stroke(Color(red: 0.949, green: 0.949, blue: 0.949),
                                lineWidth: 1)
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
                .background(
                    Color.white.opacity(0.8),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color(red: 0.949, green: 0.949, blue: 0.949),
                                lineWidth: 1)
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
        let optimized = raw
            .replacingOccurrences(of: "https://storage.googleapis.com/barsys-images-production/",
                                  with: "https://api.barsys.com/api/optimizeImage?fileUrl=https://media.barsys.com/")
        return URL(string: optimized)
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
                            case .empty, .failure:
                                Image("myDrink")
                                    .resizable().aspectRatio(contentMode: .fill)
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
                            // iOS 26+ applyCancelCapsuleGradientBorderStyle,
                            // pre-26 makeBorder(1, craftButtonBorderColor)
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
                                        .cancelCapsule(height: 45, cornerRadius: 8)
                                }
                                .buttonStyle(BounceButtonStyle())
                                .accessibilityLabel("Make it again")
                                .accessibilityHint("Crafts the same drink again")
                            }

                            // "Customize" — navigate to recipe detail for editing
                            // UIKit: customizeButton, same style as Make it again
                            // Action: pops to RecipePage before CraftingVC, or pushes new one
                            Button {
                                HapticService.light()
                                env.analytics.track(TrackEventName.craftCustomise.rawValue)
                                // Pop back to recipe detail for customization
                                // UIKit navigates to the view controller before CraftingVC
                                // SwiftUI: pop to root and navigate to recipe detail
                                router.popToRoot()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    router.push(.recipeDetail(recipeID))
                                }
                            } label: {
                                Text("Customize")
                                    .cancelCapsule(height: 45, cornerRadius: 8)
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityLabel("Customize")
                            .accessibilityHint("Opens recipe customization")

                            // "Done" — PrimaryOrangeButton
                            // UIKit: doneButton, brandTanColor bg,
                            // iOS 26+ makeOrangeStyle (capsule gradient),
                            // pre-26 makeBorder(1, sideMenuSelectionColor), 8pt corners
                            // Action: haptic success → doneAction() (pops to source VC)
                            Button {
                                HapticService.success()
                                doneAction()
                            } label: {
                                Text("Done")
                                    .brandCapsule(height: 45, cornerRadius: 8)
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
                    secondaryTitle: ConstantButtonsTitle.noStayInAppButtonTitle
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
                Image("back")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 20)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Back")
            .accessibilityHint("Returns to the previous screen")
        }

        if ble.isAnyDeviceConnected || isSpeakEasyCase {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if !deviceIconName.isEmpty {
                        Image(deviceIconName)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                    }
                    Text(deviceKindName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color("appBlackColor"))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Connected device, \(deviceKindName)")
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
    private func doneAction() {
        router.popToRoot()
    }
}
