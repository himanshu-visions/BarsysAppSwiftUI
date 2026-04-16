//
//  AppRouter.swift
//  BarsysAppSwiftUI
//
//  Replaces AppCoordinator + the 15 UIKit child coordinators.
//  Owns top-level screen state and per-tab navigation paths.
//
//  Tab layout matches UIKit TabBarViewController exactly:
//    0 = BarBot
//    1 = Explore
//    2 = My Bar
//    3 = Home ↔ Control Center (swaps on BLE connection)
//

import SwiftUI

// MARK: - Top-level screen

enum RootScreen: Equatable {
    case splash
    case auth
    case tutorial
    case main
}

// MARK: - Tabs

enum AppTab: Int, Hashable, CaseIterable, Identifiable {
    case barBot = 0
    case explore = 1
    case myBar = 2
    case homeOrControlCenter = 3

    var id: Self { self }

    var title: String {
        switch self {
        case .barBot:              return "BarBot"
        case .explore:             return "Explore"
        case .myBar:               return "My Bar"
        case .homeOrControlCenter: return "Home"
        }
    }

    /// Asset image names come from the real Assets.xcassets/BottomTabBar/ folder.
    var imageName: String {
        switch self {
        case .barBot:              return "barBotIcon"
        case .explore:             return "exploreTabIcon"
        case .myBar:               return "myBarTabIcon"
        case .homeOrControlCenter: return "homeIcon"
        }
    }
    var selectedImageName: String {
        switch self {
        case .barBot:              return "barBotIconSelected"
        case .explore:             return "exploreTabIcon"
        case .myBar:               return "myBarTabIcon"
        case .homeOrControlCenter: return "homeIconSelected"
        }
    }
}

// MARK: - Route enum

/// Every navigable destination in the app. Added to NavigationStack paths.
enum Route: Hashable {
    // Recipes
    case recipeDetail(RecipeID)
    case exploreRecipes
    case makeMyOwn
    case editRecipe(RecipeID?)

    // Mixlists / Favorites
    case mixlistList          // "Cocktail Kits" — ports MixlistViewController
    case mixlistDetail(MixlistID)
    case mixlistEdit(MixlistID?)
    case favorites

    // MyBar
    case scanIngredients

    // Profile / preferences
    case myProfile
    case preferences
    case countryPicker
    case selectQuantity(String)

    // Devices
    case pairDevice
    case deviceList
    case deviceConnected(DeviceID)
    case deviceRename(DeviceID)

    // Stations / Crafting
    case stationsMenu
    case stationCleaning
    case crafting(RecipeID)
    case drinkComplete(RecipeID)

    // BarBot
    case barBotCraft
    case barBotHistory
    case qrReader

    // Web
    case web(URL, String)
}

// MARK: - Setup-Stations-from-Mixlist context
//
// 1:1 port of UIKit `RecipeCraftingClass+StationSetup.setupStationsAction`
// forward-payload: when the user taps "Setup Stations" on
// `MixlistDetailViewController`, the coordinator pushes
// `StationsMenuViewController` with:
//   • `stationsOrigin = .setupStationsFlow`
//   • `mixlist = <the mixlist>`
//   • `ingredientsArrayForSetUpStationsMapped = <final mapped array>`
//   • `actualBaseAndMixerArrOfMixlist = baseAndMixerIngredientsArr`
//
// SwiftUI has no way to pass that much state through a `Route` enum
// cleanly, so we surface it as a transient context object stored on
// the router. The target screen (StationsMenuView / StationCleaningView)
// reads it on appear and clears it when the flow completes.
struct SetupStationsContext: Equatable {
    let mixlist: Mixlist
    /// Mixlist base + mixer ingredients (used to detect "missing" entries
    /// when the user edits a mapped station).
    let baseAndMixerIngredients: [Ingredient]
    /// Pre-mapped array — each station already has the mixlist ingredient
    /// assigned (UIKit `finalArrayMapped`).
    let mappedSlots: [StationSlot]
    /// True when the mapping discovered stations that previously had
    /// ingredients which need cleaning BEFORE the mixlist ones can be
    /// poured. Drives the "Ingredients may be spoiled…" alert.
    let requiresCleaning: Bool
    /// Stations that need cleaning before the new mixlist ingredients
    /// can be poured into them (UIKit `differentStationsToCleanArr`).
    let stationsToClean: [StationSlot]
}

/// Enumerates the screens UIKit treats as "crafting-adjacent" for the
/// purposes of the mid-craft disconnect alert
/// (BleManagerDelegate+Disconnect.swift L69-72).
enum CraftingScreenKind {
    case crafting
    case stationCleaning
    case barBotCrafting
}

// MARK: - AppRouter

final class AppRouter: ObservableObject {

    @Published var rootScreen: RootScreen = .splash
    @Published var selectedTab: AppTab = .homeOrControlCenter
    @Published var showSideMenu: Bool = false

    // One NavigationStack path per tab.
    @Published var barBotPath = NavigationPath()
    @Published var explorePath = NavigationPath()
    @Published var myBarPath = NavigationPath()
    @Published var homePath = NavigationPath()

    /// Transient — populated by `MixlistDetailView.setupStations()`
    /// (or any future Recipe-based setup flow) right before pushing
    /// `.stationsMenu` / `.stationCleaning`. Consumers read the context
    /// on appear and clear it when done.
    @Published var setupStationsContext: SetupStationsContext? = nil

    /// Identifies which crafting-adjacent screen is currently visible
    /// (if any). Set by views in `onAppear`, cleared in `onDisappear`.
    ///
    /// 1:1 port of UIKit's `BleManagerDelegate+Disconnect.showDisconnectAlert`
    /// which checks `self is CraftingViewController ||
    /// StationCleaningFlowViewController || BarBotCraftingViewController`
    /// to decide between the "during crafting" alert copy + error
    /// haptic vs the generic disconnect copy + warning haptic.
    /// Without a corresponding flag in SwiftUI, the disconnect handler
    /// can't tell which alert to show.
    @Published var activeCraftingScreen: CraftingScreenKind? = nil

    // MARK: - Cross-screen signals (NotificationCenter replacements)
    //
    // UIKit uses `NotificationCenter.default.post(name:)` to coordinate
    // between detached controllers. SwiftUI replaces these with
    // `@Published` tick counters on the router — every subscriber's
    // `.onChange(of: router.<tick>)` fires exactly once per post.

    /// Incremented by `SelectQuantityView` when the user confirms a
    /// refill quantity. UIKit posts `getStationsDataNotif` from the
    /// same place — `StationsMenuViewController` observes it and
    /// triggers `updateSingleStation` to PUT the new quantity.
    ///
    /// The accompanying payload is parked on `pendingStationUpdate`
    /// so the observer can read the name/quantity/category without
    /// having to touch NotificationCenter userInfo.
    @Published var getStationsRefillTick: Int = 0
    @Published var pendingStationUpdate: PendingStationUpdate? = nil

    /// Incremented whenever the cleaning flow pops back to the stations
    /// menu. 1:1 port of UIKit
    /// `StationCleaningFlowViewController.didPressBackButton`'s
    /// `DelayedAction.afterBleResponse(seconds: 1.0) { … refreshOnlyWhenComesFromStationsCleanScreen() }`
    /// which refetches stations so the menu reflects the post-cleaning
    /// empty quantity state. `StationsMenuView` observes this tick in
    /// `.onChange(of:)` and re-runs `loadStations`.
    @Published var stationsRefreshAfterCleaningTick: Int = 0

    /// Payload sent alongside `getStationsRefillTick`. Ports the
    /// `name / quantity / category / perishable / isAddingNewIngredient /
    /// stationName` userInfo dict that UIKit's `getStationsDataNotif`
    /// carries.
    struct PendingStationUpdate: Equatable {
        let ingredientName: String
        let quantityMl: Double
        let primaryCategory: String?
        let secondaryCategory: String?
        let isPerishable: Bool
        let isAddingNewIngredient: Bool
        let stationName: String?
    }

    /// Convenience: posts a refill update — called by
    /// `SelectQuantityView` after the user confirms the refill quantity.
    func postStationRefill(_ update: PendingStationUpdate) {
        pendingStationUpdate = update
        getStationsRefillTick &+= 1
    }

    /// Convenience: signals that the cleaning flow just popped so the
    /// stations menu should refetch.
    func signalStationsRefreshAfterCleaning() {
        stationsRefreshAfterCleaningTick &+= 1
    }

    // MARK: - Root transitions

    func handleBootstrap(authenticated: Bool, hasSeenTutorial: Bool) {
        if !authenticated {
            rootScreen = .auth
        } else if !hasSeenTutorial {
            rootScreen = .tutorial
        } else {
            rootScreen = .main
        }
    }

    func didLogin(hasSeenTutorial: Bool) {
        rootScreen = hasSeenTutorial ? .main : .tutorial
    }

    func didFinishTutorial() {
        rootScreen = .main
    }

    func logout() {
        rootScreen = .auth
        barBotPath.removeLast(barBotPath.count)
        explorePath.removeLast(explorePath.count)
        myBarPath.removeLast(myBarPath.count)
        homePath.removeLast(homePath.count)
        showSideMenu = false
        selectedTab = .homeOrControlCenter
    }

    // MARK: - Push / pop

    func push(_ route: Route, in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        switch target {
        case .barBot:              barBotPath.append(route)
        case .explore:             explorePath.append(route)
        case .myBar:               myBarPath.append(route)
        case .homeOrControlCenter: homePath.append(route)
        }
    }

    func popToRoot(in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        switch target {
        case .barBot:              barBotPath.removeLast(barBotPath.count)
        case .explore:             explorePath.removeLast(explorePath.count)
        case .myBar:               myBarPath.removeLast(myBarPath.count)
        case .homeOrControlCenter: homePath.removeLast(homePath.count)
        }
    }

    /// Pops a single route off the top of the active tab's navigation
    /// stack. 1:1 port of UIKit
    /// `self.navigationController?.popViewController(animated: true)`.
    /// Used by alerts that need to close the screen after the user
    /// dismisses them (e.g. "Perishable Ingredients Cleaned" → pop).
    func popTop(in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        switch target {
        case .barBot:
            if !barBotPath.isEmpty { barBotPath.removeLast() }
        case .explore:
            if !explorePath.isEmpty { explorePath.removeLast() }
        case .myBar:
            if !myBarPath.isEmpty { myBarPath.removeLast() }
        case .homeOrControlCenter:
            if !homePath.isEmpty { homePath.removeLast() }
        }
    }

    /// Replicates `selectTabAndPopToRoot` in UIKit TabBarViewController.
    func selectTabAndPopToRoot(_ tab: AppTab) {
        popToRoot(in: tab)
        selectedTab = tab
    }
}
