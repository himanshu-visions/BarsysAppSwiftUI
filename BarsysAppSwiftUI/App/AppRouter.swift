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

// MARK: - Edit-cover navigation path

/// Environment value that carries the `NavigationPath` binding of the
/// fullScreenCover hosting `EditRecipeView`. When non-nil, any push
/// originating inside the Edit cover (Craft, etc.) should append to
/// THIS path instead of the tab's stack — that keeps the pushed screen
/// layered on top of Edit inside the same cover hierarchy.
///
/// Mirrors UIKit `EditViewController.navigationController` which was
/// always the same nav host that Edit itself was pushed into — so
/// `pushViewController` from Edit layered on top of Edit.
private struct EditCoverPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath>? = nil
}

extension EnvironmentValues {
    var editCoverPath: Binding<NavigationPath>? {
        get { self[EditCoverPathKey.self] }
        set { self[EditCoverPathKey.self] = newValue }
    }
}

/// Direct-close callback plumbed from the `.fullScreenCover(isPresented:)`
/// (or `.fullScreenCover(item:)`) call site down into `EditRecipeView`.
/// Invoking it sets the presenting binding to `false` / `nil`, which
/// dismisses the cover on every platform.
///
/// Needed because `@Environment(\.dismiss)` inside the root of a
/// `NavigationStack(path:)` that itself sits inside a fullScreenCover
/// does not reliably propagate up to the cover on iPad — the cross
/// button in EditRecipeView silently did nothing there. Routing
/// close actions through an explicit closure sidesteps that quirk.
private struct EditCoverCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var editCoverClose: (() -> Void)? {
        get { self[EditCoverCloseKey.self] }
        set { self[EditCoverCloseKey.self] = newValue }
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
    case readyToPour
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

    /// Resigns first responder globally so any open keyboard is dismissed
    /// before the next screen appears. Mirrors UIKit's
    /// `self.view.endEditing(true)` that was invoked inside every
    /// navigation trigger (tab switches, pushes, side-menu opens). Placed
    /// here so every router transition funnels through a single point —
    /// callers don't need to remember to dismiss on each button.
    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    @Published var rootScreen: RootScreen = .splash
    @Published var selectedTab: AppTab = .homeOrControlCenter {
        didSet {
            if selectedTab != oldValue { Self.dismissKeyboard() }
        }
    }

    /// Right-side menu (profile / settings panel). UIKit
    /// `rightMenuNavigationController`. The `didSet` enforces a STRICT
    /// "history-first" gate that mirrors UIKit's user-reported
    /// SideMenuManager behaviour: while BarBot history is open, ANY
    /// attempt to open the right side menu is REJECTED — instead the
    /// history is dismissed. The user has to retry the open gesture
    /// after the history slides off, exactly as UIKit handled it.
    @Published var showSideMenu: Bool = false {
        didSet {
            if showSideMenu && showBarBotHistory {
                // Reject the open: dismiss the history first, leave the
                // side menu CLOSED so the user has to deliberately
                // reopen it after the history slide-off completes.
                showSideMenu = false
                showBarBotHistory = false
            }
            if showSideMenu && !oldValue { Self.dismissKeyboard() }
        }
    }

    /// Mirrors UIKit SideMenuManager's "only one menu visible at a time"
    /// invariant. UIKit registers BOTH `leftMenuNavigationController`
    /// (BarBot history) and `rightMenuNavigationController` (profile/
    /// side menu) on the SAME SideMenuManager, which internally enforces
    /// mutual exclusion — opening one dismisses the other.
    ///
    /// In SwiftUI the two panels live in different parent views
    /// (BarBotCraftView for history, MainTabView for the side menu) so
    /// we hoist the BarBot history visibility to the router. The `didSet`
    /// dismisses the right side menu when the history is opened so the
    /// two panels never overlap.
    @Published var showBarBotHistory: Bool = false {
        didSet {
            if showBarBotHistory && showSideMenu {
                showSideMenu = false
            }
            if showBarBotHistory && !oldValue { Self.dismissKeyboard() }
        }
    }

    /// Pre-selected tab for the next FavoritesView appearance.
    /// 1:1 port of UIKit `BarBotCoordinator.showFavourites(tabSelected:)`
    /// which forwards a `tabSelected` parameter through to
    /// `FavouritesRecipesAndDrinksViewController.tabSelectedFromOutside`,
    /// pre-selecting the Barsys Recipes (0) or My Drinks (1) tab.
    ///
    /// Used by the EditRecipe save-success flow: after the popup OK is
    /// tapped, we navigate to favorites and set this to `1` (My Drinks)
    /// so the new/updated drink is visible immediately.
    @Published var pendingFavoritesTabIndex: Int? = nil

    /// Increment-on-change signal that tells any currently-presented
    /// `FavoritesView` to re-fetch its My Drinks list. Used after the
    /// EditRecipe save-success flow when the user was ALREADY on
    /// Favorites — we don't want to push a new Favorites route (which
    /// would stack a second copy) so we just ping this tick. Mirrors
    /// the UIKit parity where `FavouritesVC.viewWillAppear` re-runs
    /// `getFavouritesRecipeData()` on every re-appearance.
    @Published var myDrinksRefreshTick: Int = 0

    /// True while `FavoritesView` is on-screen. Set in its `.onAppear` /
    /// `.onDisappear`. Used by the side menu to suppress a duplicate push
    /// when the user taps "Favourites" while the screen is already open
    /// (previously it would stack a second copy on top of the first).
    @Published var isShowingFavorites: Bool = false

    /// Same pattern for `PreferencesView`.
    @Published var isShowingPreferences: Bool = false

    /// Same pattern for `PairDeviceView` (Pair Your Device screen).
    @Published var isShowingPairDevice: Bool = false

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

    /// Rating popup state — shown on the full screen AFTER the side menu
    /// dismisses. 1:1 port of UIKit SideMenuViewController which calls
    /// `dismissSideMenu(isAnimated: false)` FIRST, then presents the
    /// alert on `UIApplication.shared.topViewController()`.
    @Published var pendingRatingPopup: BarsysPopup? = nil

    /// Global pair-device confirmation popup — 1:1 port of UIKit
    /// `openPairYourDeviceWhenNotConnected()`
    /// (UIViewController+Alerts.swift L143-163). UIKit routes every
    /// "requires a connected device" action through this ONE helper so
    /// the same confirmation alert shows up consistently. The SwiftUI
    /// port centralises the popup state on the router so any screen can
    /// trigger it via `router.promptPairDevice(in:)` and `MainTabView`
    /// renders it once at the top level.
    ///
    /// Matches UIKit `showCustomAlertMultipleButtons`:
    ///   • title              : Constants.goToPairyourDeviceStr
    ///   • primaryTitle       : ConstantButtonsTitle.continueButtonTitle = "Continue"
    ///                          (RIGHT, brand-gradient filled → navigates)
    ///   • secondaryTitle     : ConstantButtonsTitle.noButtonTitle       = "No"
    ///                          (LEFT, border only → dismisses silently)
    ///   • primaryFillColor   : segmentSelectionColor
    ///   • isCloseHidden      : true
    @Published var pairDevicePrompt: BarsysPopup? = nil

    /// Which tab's navigation stack should receive the pair-device push
    /// when the user taps "Continue". Set by `promptPairDevice(in:)`,
    /// consumed by the router's `onPrimary` closure when the alert is
    /// confirmed.
    @Published var pendingPairDeviceTab: AppTab? = nil

    /// 1:1 port of UIKit `AppNavigationState.ConnectionSource`
    /// (`AppNavigationState.swift` L10-13). Records WHY the user is on
    /// the Pair Device screen — so the BLE connect callback can route
    /// back to the right place:
    ///
    ///   • `.recipeCrafting` — set when the user taps Craft from a
    ///     recipe/mixlist/edit/ready-to-pour screen. On connect, the
    ///     app should POP the pair screen (return user to the craft
    ///     source) instead of the default "switch to Explore" flow.
    ///   • `.none` — default: on connect, switch to Explore tab and
    ///     refresh all tabs (the UIKit post-pairing happy path).
    enum ConnectionSource { case none, recipeCrafting }
    @Published var pendingConnectionSource: ConnectionSource = .none

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
        Self.dismissKeyboard()
        let target = tab ?? selectedTab
        switch target {
        case .barBot:              barBotPath.append(route)
        case .explore:             explorePath.append(route)
        case .myBar:               myBarPath.append(route)
        case .homeOrControlCenter: homePath.append(route)
        }
    }

    /// Shared "do you want to connect a device?" prompt — 1:1 with
    /// UIKit `openPairYourDeviceWhenNotConnected()`
    /// (UIViewController+Alerts.swift L143-163).
    ///
    /// Replaces raw `router.push(.pairDevice)` calls in screens that
    /// need to gate pair-device navigation behind a confirmation
    /// alert. Every UIKit screen uses the SAME helper (ReadyToPour,
    /// MixlistDetail, EditMixlist, MakeMyOwn, Explore, BarBot cards,
    /// Edit, Crafting). SwiftUI now mirrors that by centralising the
    /// popup state here.
    ///
    /// Behaviour:
    ///   • If ANY Barsys device is connected → does nothing (UIKit
    ///     wraps `show…` in the same guard — no popup, no push).
    ///   • If a popup is already up → does nothing.
    ///   • Otherwise → sets `pairDevicePrompt` + records the target
    ///     tab so the `onPrimary` closure knows which stack to push.
    ///
    /// - Parameters:
    ///   - tab: which tab's navigation stack should receive the
    ///     `.pairDevice` push on Continue. Defaults to `selectedTab`.
    ///   - isConnected: callers pass `ble.isAnyDeviceConnected` so
    ///     the router stays BLE-agnostic.
    ///   - source: records WHY the user is about to pair. When set
    ///     to `.recipeCrafting`, the post-connect handler will POP
    ///     the pair screen (returning the user to the craft source)
    ///     instead of switching to Explore. UIKit parity:
    ///     `AppNavigationState.shared.pendingConnectionSource =
    ///      .recipeCrafting` set by every craft-gated screen.
    func promptPairDevice(in tab: AppTab? = nil,
                          isConnected: Bool = false,
                          source: ConnectionSource = .none) {
        // Parity with UIKit guard:
        //   `if !isBarsys360Connected && !isCoaster && !isShaker { ... }`
        guard !isConnected else { return }
        guard pairDevicePrompt == nil else { return }
        pendingPairDeviceTab = tab ?? selectedTab
        pendingConnectionSource = source
        pairDevicePrompt = .confirm(
            title: Constants.goToPairyourDeviceStr,
            message: nil,
            primaryTitle: ConstantButtonsTitle.continueButtonTitle,
            secondaryTitle: ConstantButtonsTitle.noButtonTitle,
            primaryFillColor: "segmentSelectionColor",
            isCloseHidden: true
        )
    }

    /// Fires when the user taps the RIGHT/CONTINUE button on the
    /// pair-device prompt. Pushes `.pairDevice` on the tab captured
    /// at prompt time. `pendingConnectionSource` stays set so the
    /// BLE connect callback can route back correctly.
    func confirmPairDevice() {
        let tab = pendingPairDeviceTab ?? selectedTab
        pendingPairDeviceTab = nil
        push(.pairDevice, in: tab)
    }

    func popToRoot(in tab: AppTab? = nil) {
        Self.dismissKeyboard()
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
        Self.dismissKeyboard()
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
