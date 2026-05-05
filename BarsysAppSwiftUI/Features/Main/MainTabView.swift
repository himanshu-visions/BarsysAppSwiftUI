//
//  MainTabView.swift
//  BarsysAppSwiftUI
//
//  Direct port of BarsysApp/Controllers/TabBar/TabBarViewController.swift.
//
//  Tab layout (matches Tab enum in UIKit):
//    0 = BarBot                       barBotIcon / barBotIconSelected
//    1 = Explore                      exploreTabIcon
//    2 = My Bar                       myBarTabIcon
//    3 = Home ↔ Control Center        homeIcon / newHomeSelectedTab
//                                      ↔ controlCentreIcon / newControlCenterSelectedTab
//
//  Behaviour ports (from TabBarViewController):
//    • `updateTabImageAccordingToConnection()` — 4th tab icon + title flips
//       based on BLE connection. On iOS 26+ the tab item is created as
//       `UITabBarItem(tabBarSystemItem: .search, ...)` then its image is
//       overridden. In SwiftUI on iOS 18+ we use the `Tab(role: .search)`
//       API which is the closest 1:1; on older iOS we fall back to the
//       classic `.tabItem` Label.
//    • `replaceTabsAfterConnections()` — swaps the root VC of the 4th
//       tab's nav stack. In SwiftUI we conditionally render HomeView /
//       ControlCenterView and clear `router.homePath` on the flip so the
//       stack is reset (same effect as replacing the root VC in UIKit).
//    • `makeTabBarTransparent()` — configured in `configureAppearance()`
//       via UITabBarAppearance.
//    • `selectedIndex = .homeOrControlCenter` as the initial tab is set in
//       AppRouter.selectedTab default value.
//

import SwiftUI

fileprivate extension View {
    /// Lifts the tab bar off the bottom edge on iOS < 26 by adding a
    /// 27pt `safeAreaInset(edge: .bottom)`. The inset is applied
    /// during SwiftUI's LAYOUT pass — BEFORE the first paint — so the
    /// tab bar is born in its lifted position rather than starting
    /// at the bottom and snapping up after `.onAppear` runs (which
    /// is what produced the user-reported "items move up after first
    /// selection" flicker with the previous transform-based
    /// approach). 27pt matches UIKit pre-26's
    /// `TabBarViewController.viewDidLayoutSubviews()` hardcoded
    /// `bottomInset = 27`. iOS 26+ is intentionally a no-op — its
    /// native glass tab bar positions itself correctly without any
    /// additional inset.
    @ViewBuilder
    func applyIOSLessThan26TabBarLift() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 27)
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService

    /// Persists the user's last-selected tab across background ↔
    /// foreground transitions. SwiftUI's TabView occasionally
    /// "restores" to index 0 (BarBot) when the app comes back from
    /// background even when the user was on My Bar / Home / Explore —
    /// the user reported this exact symptom. `@AppStorage` survives
    /// process suspensions independently of SwiftUI's own state
    /// restoration, so we can detect the desync on `.scenePhase ==
    /// .active` and force `router.selectedTab` back to the value the
    /// user actually left it on. Default `3` = `homeOrControlCenter`,
    /// matching `AppRouter`'s in-memory default.
    @AppStorage("barsys_lastSelectedTab") private var persistedSelectedTabRaw: Int = 3

    /// SHARED BarBot view model — owned here at `MainTabView` so both
    /// `BarBotCraftView` (via `@EnvironmentObject`) and the
    /// `BarBotHistorySideMenuOverlay` mounted at this level read the
    /// SAME instance. This is essential because tapping a session row
    /// in the history drawer calls `vm.loadSession(session)` which
    /// mutates `messages` — those updates must reach the chat view
    /// that the user returns to after the drawer dismisses. Similarly
    /// "new chat" on the drawer resets via the same VM. A previous
    /// iteration mounted a SEPARATE VM here, which left session
    /// selection and new-chat silently no-op against the chat screen
    /// the user could see.
    @StateObject private var barBotSharedVM = BarBotViewModel()

    /// True when the user is on the ROOT screen of the currently
    /// selected tab — i.e. the tab's NavigationStack has no pushed
    /// destinations on top of the root view. Drives the iOS-< 26
    /// selection pill's visibility (visible only when at root, fades
    /// out when the user pushes to Favorites / Profile / RecipeDetail
    /// / etc., per the user's instruction matching UIKit's
    /// `hidesBottomBarWhenPushed` behaviour).
    private var isCurrentTabAtRoot: Bool {
        switch router.selectedTab {
        case .barBot:              return router.barBotPath.isEmpty
        case .explore:             return router.explorePath.isEmpty
        case .myBar:               return router.myBarPath.isEmpty
        case .homeOrControlCenter: return router.homePath.isEmpty
        }
    }

    /// SwiftUI color-scheme env — read so the 4th tab's selected-state
    /// image can swap between `newHomeSelectedTab` (light) and
    /// `newHomeSelectedTabDark` (dark) at runtime. We re-call
    /// `setFourthTabToSearchItem` on every change so the UITabBarItem
    /// picks up the right asset whenever the user toggles appearance.
    @Environment(\.colorScheme) private var colorScheme

    /// Scene-phase observer — catches the edge case where the user
    /// backgrounds the app, flips the system theme in Settings /
    /// Control Center, and then returns to the app. SwiftUI
    /// coalesces `colorScheme` changes that happen while the app is
    /// inactive into a single update on activation, which can fire
    /// BEFORE the underlying `UITabBarItem` has finished rebuilding.
    /// Re-running `setFourthTabToSearchItem` on every `.active`
    /// transition guarantees the 4th tab's selected asset
    /// (`newHomeSelectedTab` / `newHomeSelectedTabDark` /
    /// `newControlCenterSelectedTab` / `newControlCenterSelectedTabDark`)
    /// always matches the resolved system appearance after the app
    /// comes back to foreground.
    @Environment(\.scenePhase) private var scenePhase

    /// Intercepts tab-bar taps so EVERY user tap on the tab bar pops
    /// the target tab's NavigationStack back to its root — matching
    /// the requested behaviour: "tap Explore from any other tab and
    /// land on Device Paired (the root of Explore), not on whatever
    /// push the user left mid-visit."
    ///
    /// Scope of the reset:
    ///   • ONLY the tab the user is tapping is popped to root. The
    ///     other three tabs keep their stacks intact, so switching
    ///     back to THEM later still lands on their root too (each tab
    ///     is reset only when the user taps it via the tab bar).
    ///   • Side menu / BarBot history panels close if open, mirroring
    ///     UIKit's native behaviour where a tab tap collapses any
    ///     presented overlay.
    ///
    /// Programmatic writes to `router.selectedTab` (e.g. the post-
    /// connect `.explore` switch in `wireBLECallbacks`, the logout
    /// reset, etc.) go STRAIGHT to the `@Published` property and do
    /// NOT run through this binding's setter — those call sites
    /// retain their pre-existing behaviour exactly. The pop-to-root
    /// only engages when the user physically taps a tab bar item.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { newTab in
                // Intentionally diverges from UIKit parity (which used
                // `HapticService.shared.selection()` in
                // BarsysApp/Controllers/TabBar/TabBarViewController.swift:255):
                // per user feedback the SwiftUI tab bar tap should feel
                // a little firmer, so we use a medium impact instead of
                // the subtler selectionChanged() vibration.
                HapticService.medium()
                // UIKit-parity guard — if a RecipeDetailView currently on
                // screen reports unsaved quantity edits, surface the
                // same "Keep Editing / Discard" confirmation UIKit's
                // `RecipePageViewController.showUnsavedChangesAlertForBack`
                // used to show. The navigation is deferred until the
                // user taps Discard; Keep Editing leaves them on the
                // recipe page with the edits intact. Matches constants:
                //   • `unsavedChangesForRecipe`
                //   • `keepEditingButtonTitle` / `discardButtonTitle`
                if router.hasUnsavedRecipeChanges {
                    router.pendingUnsavedDiscardAction = {
                        // Running inside Discard: safe to commit the
                        // full tab reset now.
                        router.hasUnsavedRecipeChanges = false
                        router.popToRoot(in: newTab)
                        if router.showSideMenu { router.showSideMenu = false }
                        if router.showBarBotHistory { router.showBarBotHistory = false }
                        router.selectedTab = newTab
                    }
                    router.unsavedChangesConfirmPopup = .confirm(
                        title: Constants.unsavedChangesForRecipe,
                        message: nil,
                        primaryTitle: ConstantButtonsTitle.keepEditingButtonTitle,
                        secondaryTitle: ConstantButtonsTitle.discardButtonTitle,
                        isDestructive: false,
                        isCloseHidden: true
                    )
                    return
                }
                // Always pop the tab the user is tapping back to root.
                // `AppRouter.popToRoot(in:)` resigns the keyboard and
                // clears the specific tab's NavigationPath; it's a no-op
                // if the stack was already empty.
                router.popToRoot(in: newTab)
                // Collapse any presented overlay so re-entry is clean.
                if router.showSideMenu { router.showSideMenu = false }
                if router.showBarBotHistory { router.showBarBotHistory = false }
                // Finally commit the tab switch (a no-op when the user
                // taps the already-selected tab; just a reset in place).
                router.selectedTab = newTab
            }
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            TabView(selection: tabSelection) {

                // 0 — BarBot
                //
                // `barBotSharedVM` is injected via `.environmentObject`
                // so both `BarBotCraftView` (which uses it via
                // `@EnvironmentObject`) AND the
                // `BarBotHistorySideMenuOverlay` mounted below on
                // MainTabView's ZStack reference the SAME VM instance.
                // Tapping a session in the drawer therefore updates
                // the chat view the user returns to, and "new chat"
                // resets the chat the user sees.
                NavigationStack(path: $router.barBotPath) {
                    BarBotCraftView()
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .environmentObject(barBotSharedVM)
                .tabItem { tabLabel(.barBot) }
                .tag(AppTab.barBot)

                // 1 — Explore (DevicePairedView is ALWAYS the root)
                //
                // UIKit: DevicePairedViewController IS the Explore tab root
                // for BOTH connected and disconnected states. The screen
                // adapts: top bar shows/hides device icon, first grid tile
                // changes by device type. Same controller, different data.
                NavigationStack(path: $router.explorePath) {
                    DevicePairedView()
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .tabItem { tabLabel(.explore) }
                .tag(AppTab.explore)

                // 2 — My Bar
                NavigationStack(path: $router.myBarPath) {
                    MyBarView()
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .tabItem { tabLabel(.myBar) }
                .tag(AppTab.myBar)

                // 3 — Home ↔ Control Center (swaps on BLE connection)
                //
                // Mirrors UIKit replaceTabsAfterConnections + updateTabImageAccordingToConnection:
                //    - Connected → ControlCenterView, icon "controlCentreIcon", title "Control Center"
                //    - Disconnected → HomeView (ChooseOptionsDashboard), icon "homeIcon", title "Home"
                //
                // On iOS 26+ the UIKit code creates the tab item with
                // `UITabBarItem(tabBarSystemItem: .search, tag:)`. SwiftUI's
                // equivalent is `Tab(value:role:)` with `.search` role,
                // available from iOS 18+. We use the classic .tabItem here
                // because iOS 18's search role visually morphs the tab into
                // a pill-shaped search button which does NOT match the UIKit
                // design (it uses the system .search tag purely as a layout
                // hint, not for search UI). The icon + title swap below is
                // the functionally correct match for all iOS versions.
                NavigationStack(path: $router.homePath) {
                    Group {
                        if ble.isAnyDeviceConnected {
                            ControlCenterView()
                        } else {
                            HomeView()
                        }
                    }
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .tabItem { tabLabel(.homeOrControlCenter, connected: ble.isAnyDeviceConnected) }
                .tag(AppTab.homeOrControlCenter)
                // Re-apply selectedImage every time this tab's content appears.
                // SwiftUI's .tabItem re-creates UITabBarItem on body re-evaluation,
                // wiping our selectedImage. This onAppear fires when the tab becomes
                // visible, re-applying the correct selected image asset.
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        setFourthTabToSearchItem()
                    }
                }
            }
            .applyIOSLessThan26TabBarLift()
            .tint(Theme.Color.brand)
            .onAppear {
                configureAppearance()
                wireBLECallbacks()
                // 1:1 port of UIKit `TabBarViewController.viewDidAppear`
                // which calls `setupSelectionView()` on iOS < 26.
                // Run setup at end of CURRENT runloop (no delay) plus
                // multiple staggered attempts so the per-item
                // imageInsets fallback lands AT THE EARLIEST possible
                // moment — without this the user sees the icons in
                // their default positions on first render, then snap
                // up to match the title's -12pt lift after the first
                // delayed setup runs (the visible "image up / text
                // down" misalignment the user reported on initial
                // mount). The function is idempotent — only mutates
                // state when a value actually differs — so duplicate
                // runs are no-ops. iOS 26+ early-returns inside.
                DispatchQueue.main.async {
                    setupCustomSelectionViewIfNeeded()
                    Self.setPillVisible(isCurrentTabAtRoot, animated: false)
                }
                for delay: Double in [0.05, 0.15, 0.3, 0.6, 1.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        setupCustomSelectionViewIfNeeded()
                        // After each setup attempt land the initial
                        // visibility — the pill should ONLY be visible
                        // when the currently selected tab is at its
                        // root NavigationStack. Saved here without
                        // animation so the pill doesn't fade in if
                        // the user is already away from the root on
                        // first mount (e.g. deep-link launch).
                        Self.setPillVisible(isCurrentTabAtRoot, animated: false)
                    }
                }
            }
            // 1:1 port of UIKit `selectTab(_:)` →
            // `moveSelectionView(to:animated:true)` (line 232 in
            // TabBarViewController.swift). Animates the white pill to
            // the new tab on every selection change.
            //
            // KEPT MINIMAL — selection changes only animate the pill,
            // update visibility, and persist the new value. They do
            // NOT re-run `setupCustomSelectionViewIfNeeded()` or
            // reassign tab-bar appearance, because each of those
            // triggers a UIKit layout pass on the live tab bar —
            // which the user reported as "tab item positions flicker
            // on first selection". iOS 26+ no-op except for the
            // persistence write (which has to fire there too so
            // background → foreground restoration works on iOS 26+
            // as well, even though iOS 26+ doesn't usually need it).
            .onChange(of: router.selectedTab) { newTab in
                // Persist EVERY selection change to UserDefaults
                // via @AppStorage so the foreground restoration
                // logic in `.onChange(of: scenePhase)` can recover
                // the user's last tab when SwiftUI's TabView
                // momentarily resets to BarBot during the
                // background → foreground transition. Fires for
                // BOTH iOS 26+ and iOS < 26 — the persistence
                // itself is harmless on either path.
                persistedSelectedTabRaw = newTab.rawValue

                if #available(iOS 26.0, *) { return }
                // Update visibility based on whether the new tab is
                // at root. Tapping a tab via the tab bar always pops
                // to root (see `tabSelection` binding above), but
                // programmatic `router.selectedTab` writes from
                // BLE callbacks etc. don't go through that pop, so
                // a tab might be selected with non-empty path —
                // hide the pill in that case.
                Self.setPillVisible(isCurrentTabAtRoot)
                if Self.observedTabBar != nil {
                    Self.repositionPillAtIndex(newTab.rawValue, animated: true)
                } else {
                    // Initial setup hasn't run yet — defer the pill
                    // update behind a one-shot setup. This path only
                    // hits before `.onAppear` has had a chance to
                    // mount the pill on the live tab bar.
                    DispatchQueue.main.async {
                        setupCustomSelectionViewIfNeeded()
                    }
                }
            }
            // Path-change observers — fade the pill in/out as the user
            // pushes / pops within EACH tab's NavigationStack. Each
            // path is observed independently, but only the currently
            // selected tab's path actually drives the pill's
            // visibility (the computed `isCurrentTabAtRoot` reads the
            // right path based on `router.selectedTab`). Observing
            // ALL paths keeps the pill correct even after a programmatic
            // path mutation on a non-foreground tab — when the user
            // later switches to that tab the pill state is already
            // computed from the latest path.
            .onChange(of: router.barBotPath) { _ in
                Self.setPillVisible(isCurrentTabAtRoot)
            }
            .onChange(of: router.explorePath) { _ in
                Self.setPillVisible(isCurrentTabAtRoot)
            }
            .onChange(of: router.myBarPath) { _ in
                Self.setPillVisible(isCurrentTabAtRoot)
            }
            .onChange(of: router.homePath) { _ in
                Self.setPillVisible(isCurrentTabAtRoot)
            }
            // 1:1 port of UIKit
            // `TabBarViewController.updateTabImageAccordingToConnection()`:
            //
            //   guard #available(iOS 26.0, *) else { return }
            //   let tabItem = UITabBarItem(tabBarSystemItem: .search, tag: tabIndex)
            //   if isConnected {
            //       tabItem.selectedImage = UIImage.newControlCenterSelectedTab
            //           .withRenderingMode(.alwaysOriginal)
            //       tabItem.image = UIImage.controlCentreIcon
            //   } else {
            //       tabItem.image = UIImage.homeIcon
            //       tabItem.selectedImage = UIImage.newHomeSelectedTab
            //           .withRenderingMode(.alwaysOriginal)
            //   }
            //
            // UIKit calls this method EVERY TIME a device connects or
            // disconnects (via `TabBarViewController.replaceTabsAfterConnections`
            // which is wired into the BLE delegate). The previous SwiftUI
            // port only called `setFourthTabToSearchItem` once inside
            // `configureAppearance()`, so the `newHomeSelectedTab` →
            // `newControlCenterSelectedTab` swap (the selection-state
            // circle asset) never happened at runtime — the tab kept
            // the boot-time selection image. Now we re-run on EVERY
            // connection change so the circle asset matches the
            // connected-device state on selection, exactly like UIKit.
            // The tab-bar runtime override fires ONLY when the 4th
            // tab's desired visual state actually changes:
            //   • BLE connection flip → icon + title + selectedImage
            //   • Color scheme flip → selectedImage asset variant
            //   • Scene activation → catches theme flips made while
            //     the app was backgrounded
            //
            // We deliberately removed the per-tab-selection re-apply
            // that used to run here — it was firing on every tap and
            // walking the UIKit hierarchy even when nothing about the
            // 4th tab had changed, producing the fluctuation the user
            // reported. `setFourthTabToSearchItem` is now fully
            // idempotent (only reassigns properties that actually
            // changed, never calls setNeedsLayout), and the first 3
            // tabs don't need runtime overrides at all because their
            // horizontal composite is baked directly into SwiftUI's
            // `.tabItem` via `Image(uiImage:)` (see
            // `tabLabel(_:connected:)`).
            .onChange(of: ble.isAnyDeviceConnected) { _ in
                setFourthTabToSearchItem()
                // Re-apply the tab bar's bottom-lift transform — BLE
                // connect/disconnect rebuilds the 4th tab item, which
                // can trigger a UIKit relayout that resets `tabBar.transform`.
                Self.reapplyTabBarOffset()
                // 4th tab item rebuild also changes its content
                // bounds (homeIcon vs controlCentreIcon are different
                // sizes), so the pill needs to re-fit if it currently
                // sits on tab 3. Defer one tick so UIKit has finished
                // installing the new image before we measure.
                let idx = router.selectedTab.rawValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Self.repositionPillAtIndex(idx)
                }
            }
            .onChange(of: colorScheme) { _ in
                setFourthTabToSearchItem()
                Self.reapplyTabBarOffset()
                let idx = router.selectedTab.rawValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Self.repositionPillAtIndex(idx)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else { return }
                // CRITICAL — restore the user's last-selected tab
                // from `@AppStorage` if SwiftUI's TabView "restored"
                // the selection to a different tab during the
                // background → foreground transition. The user
                // reported being on My Bar / Home before backgrounding
                // and returning to find BarBot selected — that's
                // SwiftUI's TabView state restoration writing index 0
                // back through the binding when its internal state
                // got cleared during suspension. `@AppStorage` lives
                // in UserDefaults and survives suspensions cleanly,
                // so it's a reliable record of the last user-set tab.
                if let restored = AppTab(rawValue: persistedSelectedTabRaw),
                   router.selectedTab != restored {
                    router.selectedTab = restored
                }
                let idx = router.selectedTab.rawValue
                // SEED the cached pill index IMMEDIATELY (no defer)
                // so a tap-during-foreground-transition bounds KVO
                // that fires before our 0.1s asyncAfter still reads
                // the correct index. Fixes the user-reported "tap a
                // tab right after foregrounding and pill lands on
                // the wrong tab" race.
                Self.lastKnownSelectedIndex = idx
                // 0.1s defer — UIKit's trait-collection propagation
                // on foreground activation can land AFTER SwiftUI's
                // colorScheme update; waiting a tick guarantees we
                // resolve the final asset variant, not a stale one.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    setFourthTabToSearchItem()
                    Self.repositionPillAtIndex(idx)
                }
                // ALSO re-apply at a later delay — some iOS versions
                // restore the TabView's selection state asynchronously
                // and the immediate 0.1s pass might land before
                // SwiftUI has finished syncing the underlying
                // `UITabBarController.selectedIndex` to the router
                // value. The 0.6s second pass guarantees the pill
                // ends up at the correct tab even on slow restorations.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // Re-read the persisted value here too — if
                    // SwiftUI re-clobbered selection between 0.1s
                    // and 0.6s, restore it again.
                    if let restored = AppTab(rawValue: persistedSelectedTabRaw),
                       router.selectedTab != restored {
                        router.selectedTab = restored
                    }
                    Self.repositionPillAtIndex(router.selectedTab.rawValue)
                }
            }
            // Clear the home nav stack every time the connection state flips
            // so the new root view (Home or ControlCenter) is the top of the
            // stack — 1:1 match with replaceTabsAfterConnections which
            // replaces the navigation controller's root VC in UIKit.
            //
            // The 4th-tab search-item refresh is NOT duplicated here —
            // it's already handled by the `.onChange(of:
            // ble.isAnyDeviceConnected)` above. Calling it twice per
            // state change caused the tab bar to re-run the override
            // back-to-back, contributing to the fluctuation the user
            // reported on connect / disconnect.
            .onChange(of: ble.isAnyDeviceConnected) { isConnected in
                // Disconnect path: clear BOTH home and explore nav stacks
                // so the new root views (Home replaces ControlCenter, etc.)
                // are the top of each tab's stack.
                //
                // Connect path: do NOTHING here. The `onDeviceConnected`
                // callback wired below is the single source of truth for
                // post-connect navigation — it branches on
                // `pendingConnectionSource`:
                //   • `.recipeCrafting` → only pop the pair screen,
                //     keep the craft source (RecipePage / RTP / Mixlist /
                //     Edit / BarBot) visible (1:1 UIKit
                //     `BleManagerDelegate+Connect.swift:146-165`).
                //   • `.none` → switch to Explore + clear all paths
                //     (1:1 UIKit L177-182).
                //
                // The previous version cleared paths here on EVERY state
                // change. Because `onDeviceConnected` resets
                // `pendingConnectionSource = .none` before the SwiftUI
                // change-observer fires, the resets ran AFTER the source
                // was already gone — wiping `.recipeDetail(id)` off the
                // stack and bouncing the user back to Explore root. By
                // gating on `!isConnected` we keep the disconnect-side
                // cleanup intact while letting the connect callback own
                // the post-connect navigation decision exclusively.
                guard !isConnected else { return }
                router.homePath.removeLast(router.homePath.count)
                router.explorePath.removeLast(router.explorePath.count)
            }

            SideMenuOverlay()

            // BarBot history drawer — mounted HERE at the MainTabView
            // ZStack level (sibling of `SideMenuOverlay`) so it renders
            // ABOVE the tab-bar z-layer, exactly like the right-side
            // menu. Previously this lived inside `BarBotCraftView` and
            // sat BELOW the tab bar, which is why the tab bar appeared
            // on top of the drawer. Drag progress is hoisted to the
            // router (`historyOpenDragProgress` / `historyCloseDragProgress`)
            // so the edge-pan gesture inside `BarBotCraftView` still
            // drives the open animation while the overlay itself lives
            // at the higher z-layer here.
            if router.showBarBotHistory || router.historyOpenDragProgress > 0 {
                BarBotHistorySideMenuOverlay(
                    isPresented: $router.showBarBotHistory,
                    vm: barBotSharedVM,
                    closeDragProgress: $router.historyCloseDragProgress,
                    openDragProgress: router.historyOpenDragProgress,
                    isFullyPresented: router.showBarBotHistory
                )
                .zIndex(10)
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .move(edge: .leading)
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85),
                   value: router.showBarBotHistory)
        // Rating popup — shown on the full screen AFTER side menu dismisses.
        // 1:1 port of UIKit: dismissSideMenu(isAnimated: false) → then
        // showCustomAlertMultipleButtons on topViewController.
        .barsysPopup($router.pendingRatingPopup, onPrimary: {
            // "Yes please!" → open App Store review URL
            if let url = URL(string: WebViewURLs.appStoreReviewUrl) {
                UIApplication.shared.open(url)
            }
        }, onSecondary: {
            // "No, stay in the app" → dismiss
        })
        // Global pair-device confirmation popup — 1:1 port of UIKit
        // `openPairYourDeviceWhenNotConnected()`. Any screen can trigger
        // via `router.promptPairDevice(in: .<tab>, isConnected: ble.isAny…)`;
        // the popup renders at the top level here so it survives tab
        // switches and sits above all tab content.
        .barsysPopup($router.pairDevicePrompt, onPrimary: {
            // UIKit cancelButton (RIGHT, "Continue" with brand fill)
            // → navigate to Pair Device.
            router.confirmPairDevice()
        }, onSecondary: {
            // UIKit continueButton (LEFT, "No") → dismiss silently.
        })
        // Unsaved-changes confirmation shown when a tab-bar tap is
        // blocked by `router.hasUnsavedRecipeChanges`. Primary "Keep
        // Editing" leaves the user on the recipe page; Secondary
        // "Discard" runs the captured tab-switch action and resets
        // the unsaved flag. 1:1 port of UIKit
        // `RecipePageViewController.showUnsavedChangesAlertForBack`.
        .barsysPopup($router.unsavedChangesConfirmPopup, onPrimary: {
            // "Keep Editing" — drop the pending discard closure; user
            // stays on the recipe page with edits intact.
            router.pendingUnsavedDiscardAction = nil
        }, onSecondary: {
            // "Discard" — run the captured tab-switch closure which
            // clears the flag, pops the target tab's stack, and
            // commits the tab change.
            router.pendingUnsavedDiscardAction?()
            router.pendingUnsavedDiscardAction = nil
        })
    }

    // MARK: - Tab labels
    //
    // Mirrors UIKit updateTabImageAccordingToConnection — picks the
    // unselected image for each tab and lets UITabBarAppearance handle the
    // selected tint. The 4th tab swaps its base image based on `connected`.

    @ViewBuilder
    private func tabLabel(_ tab: AppTab, connected: Bool = false) -> some View {
        let imageName: String = {
            switch tab {
            case .barBot:              return "barBotIcon"
            case .explore:             return "exploreTabIcon"
            case .myBar:               return "myBarTabIcon"
            case .homeOrControlCenter: return connected ? "controlCentreIcon" : "homeIcon"
            }
        }()
        let title: String = {
            if tab == .homeOrControlCenter && connected {
                return "Control Center"
            }
            return tab.title
        }()

        // Use horizontal composite (icon + title baked into ONE image,
        // side-by-side, vertically centered with each other) on EVERY
        // tab where it's safe to do so:
        //
        //   • iOS 26+:    first 3 tabs only — the 4th tab is converted
        //                 to a search system item (separate floating
        //                 circle) by `setFourthTabToSearchItem()`,
        //                 which would conflict with a composite image.
        //                 (This branch is BIT-IDENTICAL to the prior
        //                 iOS-26+ behaviour — no functional change.)
        //
        //   • iOS < 26:   ALL 4 tabs — explicitly fixes the user-
        //                 reported "icon at top, title at bottom, not
        //                 centered with each other" stacked-layout
        //                 problem. The default UIKit pre-26 stacked
        //                 layout places the icon above the title with
        //                 visible separation; the user wants them on
        //                 the SAME LINE, horizontally centered with
        //                 each other. Pre-rendering both as a single
        //                 composite image and using it as the tab
        //                 item's image (with no separate title) gives
        //                 exactly that — every tab shows icon + title
        //                 side-by-side, vertically aligned with each
        //                 other, identical from the FIRST render
        //                 through every tab tap. Nothing async to
        //                 race against, nothing to fluctuate.
        //
        // The composite cache (`horizontalTabImageCache`) keys by
        // (iconName, title) so the 4th tab's BLE-driven swap between
        // home/Home and controlCentreIcon/Control Center generates
        // distinct composites and re-renders correctly when
        // `connected` changes.
        let useComposite: Bool = {
            if #available(iOS 26.0, *) {
                return tab != .homeOrControlCenter
            } else {
                return true  // every tab uses the composite on iOS < 26
            }
        }()

        if useComposite,
           let composite = Self.horizontalTabImage(iconName: imageName, title: title) {
            Image(uiImage: composite)
                .renderingMode(.template)
        } else {
            Label {
                Text(title)
            } icon: {
                Image(imageName)
                    .renderingMode(.template)
            }
        }
    }

    // MARK: - Appearance
    //
    // Mirrors TabBarViewController.makeTabBarTransparent — opaque white
    // background, black selected colour, 55% black for unselected items.

    private func configureAppearance() {
        // ============================================================
        // iOS < 26 EARLY RETURN — handled in App.init.
        //
        // Why: re-applying `UITabBar.appearance().standardAppearance`
        // here on `.onAppear` would replace the appearance object
        // already installed by `BarsysAppSwiftUIApp.init()` with a new
        // (identical-valued but different-reference) UITabBarAppearance
        // instance. UIKit detects the assignment and triggers a
        // tab-bar relayout, which the user perceives as a brief
        // FLUCTUATION of the icons + titles between the proxy's
        // already-laid-out positions and the new identical layout.
        //
        // Pinning iOS < 26 entirely to App.init means the proxy is
        // configured ONCE at app boot — every subsequent tab-bar
        // mount (across MainTabView re-mounts, root-view swaps,
        // re-launch from background) reads the same proxy values
        // without any re-assignment. No relayout, no flicker, no
        // fluctuation. The pre-26 visual stays bit-identical to what
        // App.init produces (matches the values this function used
        // to set itself).
        //
        // iOS 26+ continues through this method below — its
        // appearance is per-instance (depends on instance state) and
        // can't be simply baked into App.init.
        // ============================================================
        guard #available(iOS 26.0, *) else {
            // Still trigger the iOS-26+-only `setFourthTabToSearchItem`
            // hook here for symmetry — it early-returns inside on
            // iOS < 26, so this is a no-op on the pre-26 path.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                setFourthTabToSearchItem()
            }
            return
        }

        // 1:1 port of UIKit
        // `TabBarViewController.makeTabBarTransparent()`:
        //
        //   appearance.configureWithOpaqueBackground()
        //   appearance.backgroundColor = UIColor.white.withAlphaComponent(0.01)
        //   if #available(iOS 26.0, *) {
        //       appearance.shadowColor = UIColor.black.withAlphaComponent(0.4)
        //   } else {
        //       ...title position adjustment -12...
        //   }
        //   appearance.backgroundEffect = nil   // ← disables system blur/glass
        //
        // The previous SwiftUI port used `configureWithOpaqueBackground()`
        // + `backgroundColor = UIColor.white` which produced a flat white
        // rectangle — UIKit instead uses a 1%-opacity "nearly-transparent"
        // white AND explicitly clears `backgroundEffect` so iOS 26 renders
        // the native glass material underneath (the user requested this
        // glass effect). On iOS < 26 the translucent white lets the
        // parent `primaryBackgroundColor` show through.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        // Background colour — diverges by OS version:
        //
        //   • iOS 26+        → nearly-transparent white (alpha 0.01).
        //                      Combined with `backgroundEffect = nil`
        //                      below this lets the native iOS 26 glass
        //                      tab bar render the `UIGlassEffect` over
        //                      the app's `primaryBackgroundColor` —
        //                      bit-identical to the previous behaviour
        //                      that the user said is working fine.
        //
        //   • Pre-iOS 26     → solid `primaryBackgroundColor`. The
        //                      tab bar on pre-26 is a flat opaque
        //                      rectangle, and previously the 0.01
        //                      white let scrollable content bleed
        //                      through from behind — the user
        //                      observed this as "table overlapping
        //                      with tab bar" on Explore Recipes,
        //                      Cocktail Kits, Device Paired, etc.
        //                      Making the tab bar opaque in the
        //                      SAME colour as the page background
        //                      hides the bleed-through entirely
        //                      without needing per-screen bottom
        //                      insets — the visual effect is the
        //                      scrollable list is cleanly clipped
        //                      at the tab bar's top edge.
        if #available(iOS 26.0, *) {
            appearance.backgroundColor = UIColor.white.withAlphaComponent(0.01)
        } else {
            appearance.backgroundColor = UIColor(named: "primaryBackgroundColor")
                ?? UIColor.systemBackground
        }
        appearance.backgroundEffect = nil

        // Dynamic UIColor providers — light variants are bit-identical
        // to the historical hard-coded `UIColor.black(...)` values, so
        // the tab bar renders the EXACT same pixels in light mode as
        // before. In dark mode the resolver returns the white-tinted
        // counterparts so icons / titles stay legible against the dark
        // `primaryBackgroundColor` canvas instead of disappearing into
        // a black-on-dark blur.
        // Dark-mode "white" is routed through `softWhiteTextColor` so the
        // tab-bar icons / titles read as a softened off-white (#EBEBEB)
        // instead of harsh full-luminance #FFFFFF on OLED. Light mode is
        // bit-identical to the historical hard-coded `UIColor.black(...)`.
        let softWhiteUIColor = UIColor(named: "softWhiteTextColor") ?? .white
        let unselectedIconColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? softWhiteUIColor.withAlphaComponent(0.55)
                : UIColor.black.withAlphaComponent(0.55) // EXACT historical value
        }
        let unselectedTitleColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? softWhiteUIColor.withAlphaComponent(0.6)
                : UIColor.black.withAlphaComponent(0.6) // EXACT historical value
        }
        let selectedColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? softWhiteUIColor
                : UIColor.black // EXACT historical value
        }

        let item = UITabBarItemAppearance()
        item.normal.iconColor = unselectedIconColor
        item.normal.titleTextAttributes = [
            .foregroundColor: unselectedTitleColor
        ]
        item.selected.iconColor = selectedColor
        item.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        if #available(iOS 26.0, *) {
            // UIKit L130: `shadowColor = UIColor.black.withAlphaComponent(0.4)`.
            // Top hairline under the glass so the tab bar reads against
            // `primaryBackgroundColor` even on iOS 26 glass.
            // Dynamic so the hairline is visible in both modes — light
            // value is bit-identical to the historical hard-coded
            // `UIColor.black.withAlphaComponent(0.4)`.
            appearance.shadowColor = UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor.white.withAlphaComponent(0.4)
                    : UIColor.black.withAlphaComponent(0.4) // EXACT historical value
            }
        } else {
            // iOS < 26: HIDE the 1pt grey hairline that UIKit draws at
            // the TOP of the tab bar by default. Without explicit
            // overrides `configureWithOpaqueBackground()` keeps the
            // system's default shadowColor on the appearance object —
            // that's the line the user reported seeing on every iOS
            // <26 screen above the tab bar (separate from the nav-bar
            // bottom hairline handled in HomeView).
            //
            // Setting BOTH `shadowColor = .clear` AND `shadowImage =
            // UIImage()` covers every iOS pre-26 path: modern paths
            // honour `shadowColor`, legacy paths still consult
            // `shadowImage` (an empty 1×1 image renders nothing).
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()

            if UIDevice.current.userInterfaceIdiom != .pad {
                // UIKit L133-139 pre-26 branch: lift the titles 12pt closer
                // to their icons (the stacked layout otherwise puts them too
                // far down with the asset icon + no title).
                //
                // IMPORTANT — scoped to iPhone ONLY. On iPad pre-iOS 26 the
                // tab bar uses the *inline* layout (icon and title side-by-
                // side), so a vertical `-12pt` adjustment shoves the title
                // up out of alignment with the icon, producing the broken
                // tab-bar look on iPad. iPhone's stacked layout is
                // unchanged — it still gets the lift exactly as before.
                // iPhone iOS 26+ also stays untouched (different branch).
                item.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -12)
                item.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -12)

                // Pair the title's -12pt lift with a MATCHING icon
                // shift via `UITabBarItem.appearance().imageInsets`.
                // Setting it via the UIAppearance proxy (rather than
                // per-item later) bakes the shift into every tab
                // item from FIRST RENDER — without this the user sees
                // the icons in their default positions briefly on
                // initial mount, then snap up to match the title once
                // `setupCustomSelectionViewIfNeeded` runs after its
                // 0.1s defer. Per-item assignment in setup remains as
                // a belt-and-braces fallback for iOS versions where
                // `imageInsets` isn't appearance-compliant.
                UITabBarItem.appearance().imageInsets = UIEdgeInsets(
                    top: -12, left: 0, bottom: 12, right: 0
                )
            }
        }

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        // Convert the 4th tab to .search system item type.
        // UIKit storyboard: `<tabBarItem systemItem="search" tag="3"/>`.
        // On iOS 26+ this makes the 4th tab appear as a separate floating
        // circle on the right side of the tab bar (outside the 3-item pill).
        // SwiftUI's TabView/.tabItem doesn't support system items, so we
        // walk the UIKit hierarchy to find the UITabBarController and
        // replace the 4th item. The 0.1s defer lets SwiftUI finish
        // mounting the UITabBarController first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            setFourthTabToSearchItem()
        }
    }

    /// Walk the UIKit view hierarchy to find the UITabBarController
    /// hosted by SwiftUI's TabView, then replace the 4th tab's item
    /// with `UITabBarItem(tabBarSystemItem: .search, tag: 3)`.
    /// The icon is immediately overridden with the correct image
    /// (homeIcon or controlCentreIcon depending on connection state).
    private func setFourthTabToSearchItem() {
        // UIKit parity — `UITabBarItem(tabBarSystemItem: .search, …)`
        // is an iOS-26-ONLY hook (UIKit
        // `TabBarViewController.updateTabImageAccordingToConnection`
        // wraps the call in `if #available(iOS 26.0, *)` precisely
        // because the floating-search treatment only exists on iOS 26+).
        //
        // On pre-iOS-26 (and on iPad where this override was visibly
        // breaking the 4th-tab icon — it briefly showed the system
        // magnifying-glass default before our `.image =` landed, and
        // on iPad that mid-state was what the user observed), we let
        // SwiftUI's `.tabItem { Label { … } icon: { Image("homeIcon") } }`
        // drive the 4th tab natively. That path reactively swaps
        // between `homeIcon` and `controlCentreIcon` on BLE
        // connection state changes with NO UIKit override needed.
        guard #available(iOS 26.0, *) else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else { return }

        // Find the UITabBarController in the hierarchy
        func findTabBarController(in vc: UIViewController?) -> UITabBarController? {
            if let tbc = vc as? UITabBarController { return tbc }
            for child in vc?.children ?? [] {
                if let found = findTabBarController(in: child) { return found }
            }
            return nil
        }

        guard let tabBarController = findTabBarController(in: window.rootViewController) else { return }

        let tabIndex = 3
        guard let vcs = tabBarController.viewControllers,
              vcs.count > tabIndex else { return }

        // iOS 26+ horizontal layout for the first 3 tabs is now
        // driven DIRECTLY by SwiftUI's `.tabItem` via `Image(uiImage:)`
        // (see `tabLabel(_:connected:)`), so this function no longer
        // touches those items. Runtime overrides were the source of
        // the selection-time fluctuation the user reported — every
        // tab-select triggered a re-apply pass that flashed the
        // standard stacked layout before restoring the composite.
        //
        // With the composite baked into SwiftUI's view tree there is
        // no race: SwiftUI's rebuild reproduces the same composite
        // image verbatim, so the tab bar never flickers between
        // representations.
        //
        // The 4th tab still requires a runtime hook (below) because
        // SwiftUI's TabView doesn't expose the `.search` system item
        // type or the `selectedImage` asset-swap we need for the
        // Home ↔ Control Center state.

        let isConnected = ble.isAnyDeviceConnected

        // 1:1 port of UIKit TabBarViewController.updateTabImageAccordingToConnection().
        //
        // Modify the EXISTING UITabBarItem in-place rather than
        // creating a new one on every call. SwiftUI's TabView manages
        // its own tab items; replacing them wholesale forces a layout
        // pass on every call — that's the main source of the tab-bar
        // fluctuation the user reported.
        //
        // We cache the search UITabBarItem in a static store (keyed
        // by the tab bar controller's ObjectIdentifier) and ONLY
        // create it once — the first time this function runs after
        // the tab bar is mounted. Subsequent calls reuse the same
        // item and only touch properties that have actually changed
        // (image / selectedImage / title). If nothing changed we do
        // no work at all — no property writes, no setNeedsLayout, no
        // layoutIfNeeded. This is what makes selection smooth and
        // match default UITabBar behavior.

        // Resolve the desired final state up-front.
        let desiredImageName: String = isConnected ? "controlCentreIcon" : "homeIcon"
        let desiredTitle: String = isConnected ? "Control Center" : "Home"
        let selectedAssetName: String = {
            if isConnected {
                return colorScheme == .dark
                    ? "newControlCenterSelectedTabDark"
                    : "newControlCenterSelectedTab"
            } else {
                return colorScheme == .dark
                    ? "newHomeSelectedTabDark"
                    : "newHomeSelectedTab"
            }
        }()

        // Ensure the 4th slot is a search system item. If SwiftUI's
        // rebuild has replaced it with a Label-derived item (tag != 3),
        // we reinstall the cached / new search item. Otherwise reuse.
        let existingItem = vcs[tabIndex].tabBarItem
        let searchItem: UITabBarItem
        if let existing = existingItem, existing.tag == tabIndex {
            searchItem = existing
        } else {
            searchItem = UITabBarItem(tabBarSystemItem: .search, tag: tabIndex)
            vcs[tabIndex].tabBarItem = searchItem
        }

        // Idempotent property updates — only touch each property when
        // the current value differs from the target. No write → no
        // layout invalidation → no visible flicker.
        let desiredImage = UIImage(named: desiredImageName)
        if searchItem.image !== desiredImage {
            searchItem.image = desiredImage
        }
        if searchItem.title != desiredTitle {
            searchItem.title = desiredTitle
        }
        let desiredSelected = UIImage(named: selectedAssetName)?
            .withRenderingMode(.alwaysOriginal)
        if searchItem.selectedImage !== desiredSelected {
            searchItem.selectedImage = desiredSelected
        }
        // NO setNeedsLayout / layoutIfNeeded here — UITabBar observes
        // item property changes itself and relays out only when
        // needed. Manual layout calls forced a pass on every trigger
        // (tab switch, scene activation) that produced the "fluctuation
        // on selection" the user reported.
    }

    // MARK: - Custom selection pill + bottom inset (iOS < 26 only)
    //
    // 1:1 port of UIKit
    // `BarsysApp/Controllers/TabBar/TabBarViewController.swift`:
    //
    //   • `selectionView` (line 23-29): a UIView with white background
    //     (alpha 0.2 declared, then forced to opaque white inside
    //     `setupSelectionView()`), `roundCorners = BarsysCornerRadius.xlarge`
    //     (= 20), and `clipsToBounds = true`.
    //
    //   • `setupSelectionView()` (line 33-42): inserted as the FIRST
    //     subview of `tabBar` (index 0, behind the tab items) on
    //     iOS < 26 only, then positioned at the current selected index
    //     via `moveSelectionView(animated: false)`. Called from
    //     `viewDidAppear` (line 218-224).
    //
    //   • `moveSelectionView(to:animated:)` (line 44-72): repositions
    //     the pill using:
    //         itemWidth = tabBar.bounds.width / itemCount
    //         x = index * itemWidth + 10
    //         y = 8
    //         w = itemWidth - 20
    //         h = tabBar.bounds.height - 17
    //     — with a special case for the 4th tab (homeOrControlCenter)
    //     where x is shifted -5 and width grows +10 to accommodate the
    //     wider Control Center label. Animated with a spring
    //     (damping 0.8, velocity 0.5, duration 0.25, curveEaseInOut).
    //     Called from `selectTab(_:)` with animated: true on every
    //     user tab tap (line 232 in TabBarViewController.swift).
    //
    //   • `viewDidLayoutSubviews` (line 111-119): on iOS < 26 only,
    //     lifts the tab bar 27pt off the bottom edge by overriding
    //     `tabBar.frame.origin.y`. Re-applied on every layout pass so
    //     the offset survives rotation, safe-area changes, etc.
    //
    // Conditions analysed from UIKit (when the pill / offset apply):
    //   ✓ Always present on iOS < 26 once the controller appears —
    //     never hidden, never removed at runtime. The pill is created
    //     once and only its frame animates between tabs.
    //   ✗ Never created or attached on iOS 26.0+ — both the
    //     `setupSelectionView`, `moveSelectionView`, AND the
    //     `viewDidLayoutSubviews` bottom-inset block are gated behind
    //     `if #available(iOS 26.0, *) {} else { ... }`.
    //   ✓ Repositioned on every tab tap (animated) and on initial
    //     mount (non-animated).
    //   ✓ Width adapts to tab bar bounds, so the same code works for
    //     both iPhone and iPad pre-26 (the only difference is iPad
    //     uses inline layout for the items, but the pill divides the
    //     bar's bounds.width by item count regardless).
    //
    // SwiftUI port — implementation notes:
    //   The pill view is held in a `static let` so it persists across
    //   `MainTabView` re-evaluations (the struct is rebuilt by SwiftUI
    //   on every body update). We walk the UIKit hierarchy to locate
    //   the `UITabBarController` SwiftUI hosts under its TabView, then
    //   insert the pill as a subview of the tab bar.
    //
    //   Tab-bar 27pt lift uses `tabBar.transform` instead of a frame
    //   override because SwiftUI's TabView re-runs its own layout on
    //   every body re-evaluation — manually mutating `tabBar.frame`
    //   would be clobbered immediately. A transform survives those
    //   passes and produces the identical visual + hit-test offset
    //   (UIView.hitTest accounts for transforms).
    //
    //   KVO on `tabBar.bounds` re-positions the pill on rotation /
    //   split-view resize / safe-area change — UIKit got this for
    //   free via `viewDidLayoutSubviews`.

    private static let tabBarSelectionView: UIView = {
        let view = UIView()
        // Dynamic background — adapts to system appearance. The
        // dynamic `UIColor(provider:)` closure is re-resolved by
        // UIKit on every trait collection change so the pill auto-
        // updates when the user toggles light / dark mode without
        // any manual reapply on our side.
        //   • Light mode: opaque white (UIKit pre-26 parity, exactly
        //     matches the `selectionView.backgroundColor = UIColor.white`
        //     from `TabBarViewController.setupSelectionView()`).
        //   • Dark mode: TRANSLUCENT MEDIUM GREY. Previous translucent
        //     black darkened the slot but read as "muddy" on the dark
        //     tab bar. A medium grey (~50% white, 55% alpha) lifts the
        //     pill slightly above the bar surface so the selected tab
        //     reads as a soft greyish highlight — visible without the
        //     harsh contrast of pure white.
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.5, alpha: 0.55)
                : UIColor.white
        }
        // Initial corner radius — replaced dynamically inside
        // `positionSelectionView(in:atIndex:animated:)` to be exactly
        // half the pill's height so the pill always renders as a true
        // capsule / "perfectly round" shape regardless of how the
        // height adapts per device. `cornerCurve = .continuous` makes
        // the corner blend smoother — Apple's continuous corner curve
        // continues into the straight edges instead of hitting them
        // with a hard tangent, which reads as a softer pill shape.
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        // `masksToBounds = false` so we can render a subtle drop
        // shadow below the pill. The pill has no subviews (it's a
        // solid white rectangle), so disabling clipping doesn't
        // affect any child rendering — the layer's `cornerRadius`
        // still rounds the drawn background. Shadow color / opacity
        // are reapplied dynamically in `applyDynamicShadowAppearance`
        // so dark mode gets a softer glow instead of a hard black
        // drop-shadow.
        view.layer.masksToBounds = false
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 4
        view.isUserInteractionEnabled = false  // never swallow taps
        return view
    }()

    /// Re-applies the pill's shadow color + opacity based on the
    /// current trait collection. Layer shadow properties don't auto-
    /// resolve dynamic UIColors, so we resolve them ourselves on each
    /// reposition / color-scheme flip:
    ///   • Light mode → soft black drop shadow (10% opacity).
    ///   • Dark mode  → very subtle white inner glow (8% opacity)
    ///     since black shadow is invisible on a dark backdrop.
    private static func applyDynamicShadowAppearance() {
        let trait = tabBarSelectionView.traitCollection
        let isDark = trait.userInterfaceStyle == .dark
        tabBarSelectionView.layer.shadowColor = isDark
            ? UIColor.white.cgColor
            : UIColor.black.cgColor
        tabBarSelectionView.layer.shadowOpacity = isDark ? 0.08 : 0.10
    }

    private static weak var observedTabBar: UITabBar?
    private static var tabBarBoundsObserver: NSKeyValueObservation?

    /// Source-of-truth pill index — updated EVERY TIME we explicitly
    /// reposition the pill, and consulted by anything that needs to
    /// know "which tab should the pill currently sit on?". Why this
    /// exists:
    ///
    ///   • `UITabBarController.selectedIndex` can drift out of sync
    ///     with `router.selectedTab` during layout transitions. The
    ///     bounds-KVO observer fires on rotation / safe-area changes
    ///     and used to read `tabBarController.selectedIndex` to
    ///     decide where to put the pill — when that read landed
    ///     before SwiftUI propagated the tab tap, the pill ended up
    ///     on the OLD tab even though the new tab's screen was
    ///     already showing.
    ///   • Caching the last-router-reported index here means every
    ///     reposition (KVO-triggered or onChange-triggered) targets
    ///     the index the user / app actually intends, decoupled
    ///     from the underlying controller's transient state.
    ///
    /// Default value matches `AppRouter.selectedTab` default
    /// (homeOrControlCenter / index 3).
    private static var lastKnownSelectedIndex: Int = 3

    /// Resolves the y-translation offset used to lift the tab bar off
    /// the bottom edge on iOS < 26.
    ///
    /// User's intent (paraphrased): the tab bar's BOTTOM EDGE should
    /// sit ON the safe-area top boundary — i.e. the tab bar lives
    /// entirely ABOVE the home-indicator strip without overlapping it
    /// at all, and the home indicator gets clean visible space below
    /// the bar with NO tab-bar pixels intruding. The previous lift
    /// (`max(47, safeAreaBottom + 30)`) over-shot that — it pushed the
    /// bar 30pt above the safe area which made the bar feel detached
    /// and meant the user could see scrollable content bleed up between
    /// the bar and the home indicator.
    ///
    /// New formula:
    ///   • iPhone with home indicator (`safeAreaBottom > 0`):
    ///       lift = safeAreaBottom + extraGap
    ///     puts the bar bottom EXACTLY `extraGap` above the safe-area
    ///     top boundary. `extraGap = 10` keeps a small visual breathing
    ///     room without feeling disconnected.
    ///   • Devices without a home indicator (`safeAreaBottom == 0`):
    ///       lift = max(extraGap, 27)
    ///     falls back to UIKit's hardcoded 27pt so iPad / notch-less
    ///     iPhone visuals stay bit-identical to UIKit pre-26.
    private static let extraBottomBreathingRoom: CGFloat = 10
    private static func tabBarLiftOffset(for tabBar: UITabBar) -> CGFloat {
        let safeAreaBottom = tabBar.window?.safeAreaInsets.bottom ?? 0
        if safeAreaBottom > 0 {
            // iPhone with home indicator → bar bottom sits 10pt above
            // the safe area top, never inside the home-indicator strip.
            return safeAreaBottom + extraBottomBreathingRoom
        } else {
            // No home indicator → UIKit's hardcoded 27pt.
            return 27
        }
    }

    /// Tab-bar lift is now SwiftUI-managed via
    /// `applyIOSLessThan26TabBarLift()` (a `safeAreaInset` on the
    /// TabView), so this used to install a `CGAffineTransform` on
    /// the live UITabBar — now a no-op kept for source compatibility
    /// with existing call sites. The function defensively resets the
    /// transform to identity so a stale transform from an upgrade
    /// can't double-lift on top of the SwiftUI inset.
    private static func reapplyTabBarOffset() {
        if #available(iOS 26.0, *) { return }
        guard let tabBar = observedTabBar else { return }
        if tabBar.transform != .identity {
            tabBar.transform = .identity
        }
    }

    /// Re-positions the pill at the currently-selected tab without
    /// animating. Called from every SwiftUI lifecycle event that can
    /// indirectly invalidate the pill's geometry — BLE connection
    /// flip (4th tab item rebuild changes its content bounds), color
    /// scheme flip (asset swap), scene phase activation (system may
    /// have laid the bar out differently while backgrounded). Reads
    /// the current selection from the tab bar controller so it stays
    /// correct regardless of which selection mechanism triggered the
    /// invalidation. iOS 26+ no-op.
    private static func reapplyPillPosition() {
        if #available(iOS 26.0, *) { return }
        guard let tabBar = observedTabBar else { return }
        let parentTBC = tabBar.next as? UITabBarController
        let currentIdx = parentTBC?.selectedIndex ?? 0
        positionSelectionView(in: tabBar, atIndex: currentIdx, animated: false)
    }

    /// Re-positions the pill at an EXPLICIT tab index — used when the
    /// caller already has authoritative knowledge of which tab should
    /// be selected (e.g. from `router.selectedTab.rawValue`). On
    /// background → foreground transitions the underlying
    /// `UITabBarController.selectedIndex` can momentarily flicker to
    /// 0 while SwiftUI restores its TabView state, so reading from
    /// the controller's index would land the pill on BarBot even
    /// when the user was actually on Home. Routing the index in
    /// from the caller's `router.selectedTab.rawValue` pins the pill
    /// to the correct tab regardless of transient controller state.
    ///
    /// ALSO updates `lastKnownSelectedIndex` so subsequent
    /// KVO-triggered repositions (rotation, safe-area changes) hit
    /// the SAME index — fixes the "tap a tab right after foregrounding
    /// the app and the pill lands on the wrong tab" race the user
    /// reported. iOS 26+ no-op.
    private static func repositionPillAtIndex(_ index: Int, animated: Bool = false) {
        if #available(iOS 26.0, *) { return }
        // Cache the index FIRST — even before bailing on a missing
        // observedTabBar — so any later setup pass picks it up too.
        lastKnownSelectedIndex = index
        guard let tabBar = observedTabBar else { return }
        positionSelectionView(in: tabBar, atIndex: index, animated: animated)
    }

    /// Animates the pill's opacity in or out — used to hide the pill
    /// when the user navigates AWAY from a tab's root (per UIKit's
    /// behaviour where the tab bar disappears once the user pushes
    /// past the root via `hidesBottomBarWhenPushed`; SwiftUI keeps
    /// the bar mounted but we mirror the visual hide-behaviour by
    /// fading the selection pill to 0 alpha on non-root screens).
    /// iOS 26+ no-op — its glass tab bar handles the appearance
    /// natively.
    private static func setPillVisible(_ visible: Bool, animated: Bool = true) {
        if #available(iOS 26.0, *) { return }
        let target: CGFloat = visible ? 1.0 : 0.0
        if abs(tabBarSelectionView.alpha - target) < 0.001 { return }
        if animated {
            UIView.animate(withDuration: 0.18,
                           delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState]) {
                tabBarSelectionView.alpha = target
            }
        } else {
            tabBarSelectionView.alpha = target
        }
    }

    /// 1:1 port of UIKit `setupSelectionView()` + the bottom-inset
    /// block in `viewDidLayoutSubviews()`. Idempotent — safe to call
    /// repeatedly. iOS 26+ early-returns and never touches the tab bar.
    private func setupCustomSelectionViewIfNeeded() {
        if #available(iOS 26.0, *) { return }

        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else { return }

        func findTBC(in vc: UIViewController?) -> UITabBarController? {
            if let tbc = vc as? UITabBarController { return tbc }
            for child in vc?.children ?? [] {
                if let found = findTBC(in: child) { return found }
            }
            return nil
        }
        guard let tabBarController = findTBC(in: window.rootViewController) else { return }
        let tabBar = tabBarController.tabBar

        // 1:1 with UIKit:
        //   if selectionView.superview == nil {
        //       tabBar.insertSubview(selectionView, at: 0)
        //   }
        //   selectionView.backgroundColor = UIColor.white
        if Self.tabBarSelectionView.superview !== tabBar {
            Self.tabBarSelectionView.removeFromSuperview()
            tabBar.insertSubview(Self.tabBarSelectionView, at: 0)
        }
        // NOTE — we intentionally do NOT re-assign `backgroundColor`
        // here. The pill's static initializer already wires a DYNAMIC
        // `UIColor` provider (light → opaque white / dark → soft
        // off-white at 22% alpha). UIKit's
        // `setupSelectionView()` does `selectionView.backgroundColor =
        // UIColor.white` — but that's a STATIC color which overrode
        // our dynamic resolver every time setup ran, leaving the pill
        // bright white in dark mode (the user reported this on iPad
        // dark mode). Letting the dynamic provider stand means the
        // pill auto-adapts to system appearance every time the trait
        // collection changes — light mode stays bit-identical to UIKit.

        // PER-ITEM `imageInsets` ASSIGNMENT WAS DELIBERATELY REMOVED.
        //
        // The previous implementation paired UIKit's
        // `titlePositionAdjustment = -12` with a per-item
        // `imageInsets = (top: -12, bottom: 12)` to shift the icon up
        // alongside the title. That had two problems:
        //   1. `imageInsets` is NOT appearance-compliant, so it
        //      couldn't be applied via the proxy in `App.init` —
        //      it had to run per-item AFTER SwiftUI mounted the
        //      UITabBarController, which produced the user-reported
        //      "icon and title not aligned until first tab tap" race.
        //   2. SwiftUI rebuilt UITabBarItems on body re-evaluations
        //      and we had to re-apply on every onChange handler,
        //      which the user perceived as runtime fluctuation.
        //
        // The new approach (see `tabLabel(_:connected:)`) bakes the
        // icon and title into a single composite image and uses it
        // directly as the tab item's image — no separate title to
        // reposition, no per-item insets needed, identical visual
        // from the first render through every tab tap. iPhone iOS <
        // 26 now also uses this path, so the title-position pairing
        // is OBSOLETE here.

        // ONE-SHOT live-instance appearance hardening — runs ONLY the
        // FIRST time we see this tab bar reference (gated by the
        // `observedTabBar !== tabBar` block below, which sets
        // `Self.observedTabBar = tabBar` after this function's
        // sibling work completes). Why one-shot:
        //
        //   • `App.init()` already configures `UITabBar.appearance()`
        //     with `shadowColor = .clear` for iOS < 26, so newly-
        //     mounted tab bars are born without a hairline.
        //   • Re-assigning `tabBar.standardAppearance` on every setup
        //     pass forces UIKit to relayout the bar — which the user
        //     reported as "tab item positions flicker on first
        //     selection" and even "sometimes goes to BarBot
        //     wrongly" (transient layout state during the relayout
        //     can confuse SwiftUI's TabView selection binding).
        //
        // We KEEP the assignment for the very first encounter as a
        // belt-and-braces in case the proxy didn't propagate (rare
        // edge case on older iOS versions), but every subsequent
        // setup pass leaves the live tab bar's appearance untouched.
        if Self.observedTabBar !== tabBar {
            if tabBar.standardAppearance.shadowColor != .clear,
               let standardCopy = tabBar.standardAppearance.copy() as? UITabBarAppearance {
                standardCopy.shadowColor = .clear
                standardCopy.shadowImage = UIImage()
                tabBar.standardAppearance = standardCopy
            }
            if let scrollEdge = tabBar.scrollEdgeAppearance,
               scrollEdge.shadowColor != .clear,
               let scrollCopy = scrollEdge.copy() as? UITabBarAppearance {
                scrollCopy.shadowColor = .clear
                scrollCopy.shadowImage = UIImage()
                tabBar.scrollEdgeAppearance = scrollCopy
            }
            // Legacy hairline stripper — pre-iOS-13 paths still
            // consult `shadowImage` directly on the UITabBar before
            // falling back to the appearance object. Setting an
            // empty image once kills the legacy line. (Reassigning
            // an empty image on subsequent passes was a layout-
            // triggering no-op — skip it via the one-shot guard.)
            if tabBar.shadowImage == nil {
                tabBar.shadowImage = UIImage()
            }
        }

        // TAB-BAR LIFT IS NOW APPLIED VIA SwiftUI's
        // `applyIOSLessThan26TabBarLift()` modifier on the TabView,
        // which uses `safeAreaInset(edge: .bottom)` to reserve 27pt
        // of clear space at the bottom of the TabView. The inset is
        // applied during SwiftUI's layout pass BEFORE the first
        // paint — so the tab bar is born in its lifted position,
        // identical from the very first render through every tab tap.
        //
        // The previous transform-based approach
        // (`tabBar.transform = CGAffineTransform(...)`) was applied
        // post-paint inside `setupCustomSelectionViewIfNeeded`, which
        // is what produced the user-reported "items move up after
        // first selection" snap. Defensively reset any stale
        // transform here in case a previous build wrote one — this
        // is a no-op on a clean install but prevents double-lift on
        // upgrade paths.
        if tabBar.transform != .identity {
            tabBar.transform = .identity
        }

        // Bounds KVO — re-positions the pill on rotation, split-view
        // resize, and safe-area changes. UIKit got this for free
        // via `viewDidLayoutSubviews`. We tear down + re-attach if the
        // tab bar reference has changed (e.g. SwiftUI rebuilt the
        // TabView host on splash → main transition).
        if Self.observedTabBar !== tabBar {
            Self.tabBarBoundsObserver?.invalidate()
            Self.tabBarBoundsObserver = tabBar.observe(\.bounds, options: [.new]) { obs, _ in
                DispatchQueue.main.async { [weak obs] in
                    guard let obs else { return }
                    // Use the CACHED last-known-selected index instead
                    // of `tabBarController.selectedIndex`. The
                    // controller's index can drift out of sync with
                    // the user's intent during layout transitions
                    // (especially when the user taps a tab right after
                    // foregrounding — UIKit's selectedIndex hasn't
                    // yet caught up to SwiftUI's binding write, and a
                    // bounds change in that window would land the
                    // pill on the OLD tab). Reading the cached index
                    // pins the pill to wherever `repositionPillAtIndex`
                    // last said it should be.
                    Self.positionSelectionView(in: obs,
                                               atIndex: Self.lastKnownSelectedIndex,
                                               animated: false)
                    // Tab bar lift is now SwiftUI-managed via
                    // `applyIOSLessThan26TabBarLift()` — no transform
                    // to re-apply here on bounds changes. Defensively
                    // reset any stale transform that might have been
                    // installed by a previous build.
                    if obs.transform != .identity {
                        obs.transform = .identity
                    }
                }
            }
            Self.observedTabBar = tabBar
        }

        // Seed the cached index from `router.selectedTab` BEFORE
        // positioning, so any subsequent KVO-triggered reposition
        // (e.g. a rotation that fires before the user has tapped a
        // tab) reads the SAME source-of-truth value the initial
        // setup uses. Without this seed, the cached index would
        // remain at its default (3 = homeOrControlCenter) until the
        // user taps a tab — leaving rotations on a non-default-tab
        // launch (like deep-link to Explore) positioning the pill
        // back at homeOrControlCenter.
        Self.lastKnownSelectedIndex = router.selectedTab.rawValue
        // Initial position — UIKit calls `moveSelectionView(animated: false)`
        // from `setupSelectionView()` so the pill snaps to the current
        // tab without animating from (0,0).
        Self.positionSelectionView(in: tabBar,
                                   atIndex: router.selectedTab.rawValue,
                                   animated: false)
    }

    /// 1:1 port of UIKit `moveSelectionView(to:animated:)`, with one
    /// deliberate refinement on iPad: UIKit's math divides the bar's
    /// `bounds.width` evenly across `items.count` and lays the pill
    /// inside that slot. That's correct on iPhone (stacked layout —
    /// each item button spans its full slot, so an inside-inset pill
    /// sits centered behind the icon+title group). On iPad pre-26 the
    /// tab bar uses INLINE layout and each item button is sized to its
    /// CONTENT (icon + title side-by-side), not to the slot — the
    /// content is roughly centered inside the slot but only fills a
    /// fraction of the slot's width. The slot-based pill therefore
    /// extends well beyond the actual icon+title and looks
    /// off-centered (the user reported the BarBot pill stretching all
    /// the way past the icon on iPad).
    ///
    /// The fix locates the actual tab-bar button frames (any
    /// `UIControl` subview of the tab bar — UITabBarButton is private
    /// but always a UIControl) and on iPad outsets them by 10pt on
    /// each side. iPhone uses the original UIKit slot-inset math —
    /// bit-identical to TabBarViewController.swift:48-58 — so the
    /// iPhone visuals are byte-for-byte the same as UIKit pre-26.
    /// iOS 26+ early-returns and never touches the tab bar.
    /// Returns the bounding box of the visible icon + title content
    /// inside a tab bar button, in the BUTTON's coordinate space.
    ///
    /// IMPORTANT — only `UIImageView` (the icon — UITabBarSwappableImageView
    /// is a UIImageView subclass) and `UILabel` (the title — typically
    /// `_UITabBarButtonLabel` / `_UITabBarItemTitleView`, both UILabel
    /// subclasses) are unioned. Background views, separators, and any
    /// other "decoration" subviews are skipped — including them would
    /// inflate the bounds to the full button frame and the pill would
    /// stop being centered around the actual visible content (which
    /// the user reported as "top space less, bottom space more").
    ///
    /// Recurses one level into container subviews so wrapper views
    /// like `_UITabBarItemTitleView` (which wraps an inner UILabel)
    /// still contribute the inner label's frame.
    private static func tabItemContentBounds(in button: UIView) -> CGRect? {
        func isContent(_ v: UIView) -> Bool {
            return v is UIImageView || v is UILabel
        }

        func collect(in view: UIView, depth: Int) -> [CGRect] {
            if depth > 3 { return [] }
            var out: [CGRect] = []
            for sub in view.subviews {
                if sub.isHidden || sub.alpha < 0.05 { continue }
                if sub.frame.width <= 0 || sub.frame.height <= 0 { continue }
                if isContent(sub) {
                    // Convert into the button's coordinate space so
                    // every collected rect is comparable.
                    out.append(button.convert(sub.bounds, from: sub))
                } else if !sub.subviews.isEmpty {
                    out.append(contentsOf: collect(in: sub, depth: depth + 1))
                }
            }
            return out
        }

        let rects = collect(in: button, depth: 0)
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    private static func positionSelectionView(in tabBar: UITabBar,
                                              atIndex index: Int,
                                              animated: Bool) {
        if #available(iOS 26.0, *) { return }
        guard let items = tabBar.items, !items.isEmpty else { return }

        // Locate the actual tab-bar item buttons. We walk the tab bar's
        // direct subviews (one level deep is enough for every iOS
        // version we ship to) collecting any `UIControl` whose class
        // name carries the "TabBar" / "Tab" hint — UITabBarButton on
        // iOS pre-18, and iOS 18+ replacement classes. Sorted by minX
        // so the array index lines up with the matching tab item.
        var buttons: [UIView] = tabBar.subviews
            .filter { subview in
                if !(subview is UIControl) { return false }
                let className = NSStringFromClass(type(of: subview))
                return className.contains("TabBar") || className.contains("Tab")
            }
            .sorted { $0.frame.minX < $1.frame.minX }
        if buttons.count < items.count {
            // Fallback: every UIControl direct child of the tab bar.
            buttons = tabBar.subviews
                .filter { $0 is UIControl }
                .sorted { $0.frame.minX < $1.frame.minX }
        }

        // Padding around the visible icon+title content. EQUAL on
        // top/bottom and EQUAL on left/right → user's "top space and
        // bottom space should be equal" + "15 from left and 15 from
        // right" instructions.
        //   • paddingX = 15 — extra breathing room on each side of the
        //     icon+title group (per the latest "increase its left and
        //     right space to 15 from left and 15 from right").
        //   • paddingY = 8  — equal top + bottom margin around the
        //     content. The user asked for ~2pt then "increase little
        //     height also"; 8pt gives a comfortable rounded-pill look
        //     without overflowing the button area on iPhone with the
        //     -12pt title adjustment.
        let paddingX: CGFloat = 15
        let paddingY: CGFloat = 8

        let frame: CGRect
        if buttons.count >= items.count,
           index < buttons.count,
           let contentInButton = tabItemContentBounds(in: buttons[index]) {
            // Pre-compute the WIDEST content across every tab and
            // size the pill to hug that maximum, regardless of which
            // tab is currently selected. The user explicitly asked
            // for "Width of selection view should be almost equal for
            // all tab items" — this enforces it: BarBot's pill is the
            // same width as Control Center's, even though "Control
            // Center" is a much longer title than "BarBot". The pill
            // is then HORIZONTALLY centered on the selected tab's
            // actual content midpoint so it remains visually anchored
            // to the icon+title for every tab. Cap at slot-width
            // minus a small safety margin so pills never bleed into
            // adjacent tab slots regardless of how long the longest
            // title turns out to be.
            let allContentWidths: [CGFloat] = buttons.compactMap {
                tabItemContentBounds(in: $0)?.width
            }
            let maxContentWidth = allContentWidths.max() ?? contentInButton.width
            let slotWidth = tabBar.bounds.width / CGFloat(items.count)
            let safetyCap = max(slotWidth - 6, 0)
            // iPad-only: widen the selection pill by 50pt so it reads
            // as a deliberate emphasis on the larger canvas. iPhone
            // unchanged. Still capped by `safetyCap` so it can never
            // bleed into adjacent tab slots.
            let iPadWidthBump: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 40 : 0
            let uniformWidth = min(maxContentWidth + paddingX * 2 + iPadWidthBump, safetyCap)

            // Vertical metrics still hug the SELECTED tab's content
            // bounds — top / bottom space is `paddingY` regardless of
            // which tab is active. (Vertical content height is the
            // same across all tabs in a given idiom, so this is
            // already uniform in practice.)
            let contentInTabBar = tabBar.convert(contentInButton, from: buttons[index])
            let x = contentInTabBar.midX - uniformWidth / 2
            let w = uniformWidth
            let y = contentInTabBar.minY - paddingY
            let h = contentInTabBar.height + paddingY * 2
            // 4th tab's `+5pt each side` UIKit special case is
            // INTENTIONALLY dropped here — including it would re-
            // introduce a width difference between the 4th tab and
            // the first three, which is exactly what the user asked
            // us to eliminate. Uniform width covers Control Center
            // / Home naturally because `maxContentWidth` already
            // resolves to the widest tab's content width.
            frame = CGRect(x: x, y: y, width: w, height: h)
        } else {
            // Fallback: button frames not found (rare — defensive).
            // Use UIKit's slot-divided math, vertically centered within
            // the BUTTON AREA only (i.e. excluding the safe-area
            // portion of the tab bar). That keeps the pill out of the
            // home-indicator strip even on devices where the visible
            // content's bounding box couldn't be resolved. Padding
            // matches the content-bounds path (15 horizontal / 8
            // vertical) by inflating the slot inward and capping the
            // pill height instead of using UIKit's hardcoded 17pt
            // gap, so the fallback gives a similar visual to the
            // primary path.
            let safeAreaBottom = tabBar.window?.safeAreaInsets.bottom ?? 0
            let buttonAreaHeight = max(tabBar.bounds.height - safeAreaBottom, 0)
            let height = max(buttonAreaHeight - paddingY * 2, 0)
            let yPosition: CGFloat = (buttonAreaHeight - height) / 2
            let tabBarWidth = tabBar.bounds.width
            let itemWidth = tabBarWidth / CGFloat(items.count)
            // Hug a centered ~70%-of-slot-width content area with
            // paddingX margins on each side (the assumed visible
            // icon+title is centered in the slot).
            let assumedContentWidth = itemWidth * 0.70
            // iPad-only: same +50pt bump as the primary path so the
            // fallback stays consistent if it's ever hit.
            let iPadWidthBump: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 50 : 0
            let unboundedWidth = assumedContentWidth + paddingX * 2 + iPadWidthBump
            // Cap at slot width minus a small safety margin so the pill
            // never bleeds into adjacent slots regardless of bump.
            let width = min(unboundedWidth, max(itemWidth - 6, 0))
            let xPosition = CGFloat(index) * itemWidth
                + (itemWidth - width) / 2
            var f = CGRect(x: xPosition, y: yPosition, width: width, height: height)
            if index == AppTab.homeOrControlCenter.rawValue {
                f = CGRect(x: xPosition - 5,
                           y: yPosition,
                           width: width + 10,
                           height: height)
            }
            frame = f
        }

        // Dynamic corner radius — half the resolved pill height makes
        // the pill render as a TRUE CAPSULE (perfectly round end caps)
        // rather than the static 20pt that left visible flat segments
        // along the longer edges. Recomputed on every reposition so a
        // taller / shorter pill (per device idiom or rotation) keeps
        // the round shape. iOS 26+ never enters this code path.
        tabBarSelectionView.layer.cornerRadius = frame.height / 2
        // Re-resolve dynamic shadow color + opacity for the current
        // appearance — CALayer shadow properties don't auto-adapt to
        // trait collection changes, so we read the active style here
        // and reset them. Cheap (just two property writes); idempotent
        // because the values match the trait every time.
        applyDynamicShadowAppearance()
        // Pre-compute the shadow path so the soft drop-shadow animates
        // alongside the frame change instead of triggering an expensive
        // off-screen alpha render every frame. Without an explicit
        // path UIKit re-rasterises the shadow each tick, which on
        // older iPads / iPhones produces noticeable jank — matches
        // the user's "I need smooth UI" instruction.
        let pillBounds = CGRect(origin: .zero, size: frame.size)
        tabBarSelectionView.layer.shadowPath = UIBezierPath(
            roundedRect: pillBounds,
            cornerRadius: frame.height / 2
        ).cgPath

        if animated {
            // Smoother, less bouncy animation than UIKit's pre-26
            // spring (damping 0.8 / velocity 0.5 / 0.25s). Higher
            // damping (0.95) keeps a hint of overshoot for life
            // without the visible bounce; the longer 0.32s duration
            // makes the slide read as a deliberate motion rather
            // than a snap. The `.allowUserInteraction` option lets
            // the user tap a different tab mid-animation without
            // having to wait for the previous slide to finish.
            UIView.animate(withDuration: 0.32,
                           delay: 0,
                           usingSpringWithDamping: 0.95,
                           initialSpringVelocity: 0.2,
                           options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
                tabBarSelectionView.frame = frame
            }
        } else {
            tabBarSelectionView.frame = frame
        }
    }

    // MARK: - Horizontal tab item content (iOS 26+ glass tab bar)
    //
    // Pre-renders [icon][spacing][title] as a single UIImage so the
    // first 3 tab items can display horizontal content WITHOUT
    // altering the tab bar's or item's own dimensions. The composite
    // is returned as a template image so the tab bar's `tintColor`
    // drives both the icon AND the title color uniformly (selected
    // vs unselected colors configured in `configureAppearance()`).
    //
    // Cache by (iconName, title) so the composite is rendered once
    // and reused across re-runs of `setFourthTabToSearchItem`.
    private static var horizontalTabImageCache: [String: UIImage] = [:]

    private static func horizontalTabImage(iconName: String,
                                           title: String) -> UIImage? {
        let key = "\(iconName)|\(title)"
        if let cached = horizontalTabImageCache[key] { return cached }

        guard let icon = UIImage(named: iconName) else { return nil }

        // Tab-bar icons in the Assets.xcassets are designed to render
        // at ~25x25 pt — match UITabBarItem's native stacked-layout
        // icon size so the composite reads at the same visual scale
        // as the current (vertical) layout.
        let iconSize = CGSize(width: 25, height: 25)
        let font = UIFont.systemFont(ofSize: 10, weight: .regular)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black // recolored by .alwaysTemplate
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        let spacing: CGFloat = 4

        let totalWidth = iconSize.width + spacing + ceil(titleSize.width)
        let totalHeight = max(iconSize.height, ceil(titleSize.height))

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: totalWidth, height: totalHeight)
        )
        let composite = renderer.image { _ in
            let iconY = (totalHeight - iconSize.height) / 2
            icon.draw(in: CGRect(x: 0,
                                 y: iconY,
                                 width: iconSize.width,
                                 height: iconSize.height))

            // Cap-height centered title placement — aligns the
            // VISUAL middle of the letters (the midpoint between cap
            // top and baseline) with the icon's vertical center,
            // instead of centring the text's full bounding-box
            // (which includes descender space below the baseline and
            // makes the text read as sitting LOWER than the icon).
            //
            // Math:
            //   • Icon center y      = totalHeight / 2
            //   • Want cap-middle y  = totalHeight / 2 too
            //   • Baseline y         = textTop + ascender
            //   • Cap-middle y       = baseline - capHeight / 2
            //                        = textTop + ascender - capHeight / 2
            //   ⇒ textTop = totalHeight/2 - ascender + capHeight/2
            //
            // The result is a tiny shift (typically 0.5–1pt up vs the
            // bounding-box centre at this font size) but it lines up
            // the visual centre of the text with the icon's centre,
            // which is what the user perceives as "centered with each
            // other".
            let titleY = (totalHeight / 2) - font.ascender + (font.capHeight / 2)
            (title as NSString).draw(
                at: CGPoint(x: iconSize.width + spacing, y: titleY),
                withAttributes: titleAttrs
            )
        }
        let templated = composite.withRenderingMode(.alwaysTemplate)
        horizontalTabImageCache[key] = templated
        return templated
    }

    // MARK: - BLE connection/disconnection callbacks
    //
    // Ports the UIKit post-connection flow:
    //   1. Toast "{name} is Connected." — 6s, segmentSelectionColor (gold)
    //   2. Switch to Explore tab (index 1)
    //   3. Tab 4 icon/content changes reactively via isAnyDeviceConnected
    //
    // And the disconnection flow:
    //   1. Toast "{name} is Disconnected." — 5s, errorLabelColor (red)
    //   2. Tab 4 reverts reactively

    private func wireBLECallbacks() {
        ble.onDeviceConnected = { [weak router, weak env] deviceName in
            guard let router, let env else { return }

            // If the "device disconnected" alert is still on screen from a
            // prior power-off, auto-dismiss it now that the device is back.
            // Mirrors UIKit's `dismiss(animated:)` on the presented alert
            // when a reconnect event fires.
            if env.alerts.current?.title == Constants.deviceDisconnectedTitle {
                env.alerts.dismiss()
            }

            // 1:1 with UIKit `BleManagerDelegate+Connect.swift` L155-185 —
            // branches based on `AppNavigationState.pendingConnectionSource`:
            //
            //   • `.recipeCrafting` → POP the pair screen (user returns
            //       to the craft source), update tabs, clear flag. NO
            //       tab switch.
            //   • `.none` → default: switch to Explore tab, pop all
            //       stacks, show toast.
            //
            // The SwiftUI equivalent lives on `AppRouter.pendingConnectionSource`,
            // set when `promptPairDevice(source: .recipeCrafting)` is
            // invoked from a craft-gated screen (Ready to Pour, Recipe
            // page, Mixlist detail, Edit recipe, Edit mixlist, Explore
            // row tap, BarBot card).

            let source = router.pendingConnectionSource
            let originTab = router.pendingPairDeviceTab ?? router.selectedTab
            router.pendingConnectionSource = .none
            router.pendingPairDeviceTab = nil

            switch source {
            case .recipeCrafting:
                // UIKit L161-165 — pop pair screen on the origin tab so
                // the user lands back on the craft source. No tab switch,
                // no stack reset.
                router.popTop(in: originTab)

                // Toast + haptic still fire (UIKit does these before the
                // pop/branch above).
                env.toast.show("\(deviceName) is Connected.",
                               color: Color("segmentSelectionColor"),
                               duration: 6)
                HapticService.success()

            case .none:
                // UIKit L177-182 — default post-connect path: switch to
                // Explore, pop all stacks, refresh. Order matters — select
                // Explore FIRST so the reactive Home → ControlCenter swap
                // happens on an off-screen tab.
                router.selectedTab = .explore

                env.toast.show("\(deviceName) is Connected.",
                               color: Color("segmentSelectionColor"),
                               duration: 6)
                HapticService.success()

                router.homePath.removeLast(router.homePath.count)
                router.explorePath.removeLast(router.explorePath.count)
            }

            // Post-connection data refresh — ports BleManagerDelegate+Connect.swift:
            //   MixlistsUpdateClass().updateMixlists(trigger: .connection)
            //   → API: getMixlist + getCacheRecipes + getFavouritesData
            //   → DB: insertToDatabase
            // This ensures recipes and mixlists are fresh after device connects.
            //
            // Wrapped in `suppressExpirationDuring` for the same reason
            // `onLoginSuccessAsync` is wrapped: a transient 401 /
            // "expired session token" on `/cache/recipes`,
            // `/cache/mixlists`, or favourites — which can happen if
            // the BLE connect fires concurrently with another
            // in-flight authenticated request — must NOT log the user
            // out. UIKit's `MixlistsUpdateClass.updateMixlists(trigger:
            // .connection)` ran on a background queue and silently
            // dropped 401s during the connection burst; mirroring that
            // behaviour here matches UIKit byte-for-byte.
            Task {
                await SessionExpirationHandler.shared.suppressExpirationDuring {
                    await env.catalog.preload()
                }
            }
        }

        ble.onDeviceDisconnected = { [weak env, weak router] deviceName in
            guard let env, let router else { return }
            // Toast: "{name} is Disconnected." (UIKit: 5s, errorLabelColor)
            env.toast.show("\(deviceName) is Disconnected.", color: Color("errorLabelColor"), duration: 5)

            // 1:1 port of UIKit
            // `BleManagerDelegate+Disconnect.showDisconnectAlert`
            // (BleManagerDelegate+Disconnect.swift L66-105):
            //
            //   isCraftingScreen = self is CraftingViewController
            //                   || self is StationCleaningFlowViewController
            //                   || self is BarBotCraftingViewController
            //
            //   if isCraftingScreen {
            //       HapticService.shared.error()
            //       alert(title: deviceDisconnectedTitle,
            //             message: deviceDisconnectedDuringCraftingMessage,
            //             primary: OK → AppCoordinator.handleDisconnect)
            //   } else {
            //       HapticService.shared.warning()
            //       alert(title: deviceDisconnectedTitle,
            //             message: deviceDisconnectedMessage,
            //             primary: OK → AppCoordinator.handleDisconnect)
            //   }
            //
            // SwiftUI: `router.activeCraftingScreen` is set by
            // CraftingView / StationCleaningView / BarBotCraftView in
            // their `onAppear` and cleared in `onDisappear`. The
            // handler below maps that flag to the same alert + haptic
            // branches as UIKit, then runs `handleDisconnect()` on OK.
            let isCrafting = router.activeCraftingScreen != nil
            let message = isCrafting
                ? Constants.deviceDisconnectedDuringCraftingMessage
                : Constants.deviceDisconnectedMessage
            if isCrafting {
                HapticService.error()
            } else {
                HapticService.warning()
            }
            env.alerts.show(
                title: Constants.deviceDisconnectedTitle,
                message: message,
                primary: Constants.okButtonTitle,
                action: {
                    handleDisconnect(router: router)
                }
            )
        }
    }
}

/// 1:1 port of UIKit `AppCoordinator.handleDisconnect()`
/// (`Coordinators/AppCoordinator.swift` L162-165):
///   • Sets the "device connection state" to disconnected (handled
///     reactively by `ble.isAnyDeviceConnected` in our SwiftUI port).
///   • Rebuilds the tab bar with the home tab pointing at the
///     ChooseOptions/HomeView (we already do this reactively via
///     `tab(.homeOrControlCenter, connected: ble.isAnyDeviceConnected)`).
///
/// Additionally we POP every tab's nav stack so the user lands on a
/// clean tab root after disconnect — UIKit's `showTabBar(...)` rebuilds
/// every nav controller from scratch, which has the same effect. We
/// ALSO close the side menu AND the BarBot chat-history overlay
/// because UIKit's full-tab-bar rebuild implicitly tears down any
/// presented modal (side menu / history), which the user perceives
/// as a clean "return to home" after disconnect. Without this close,
/// the SwiftUI port leaves the side menu mounted on top of the home
/// tab and the user sees no visible change when OK is tapped on the
/// disconnect alert — which is the exact symptom the user reported
/// when tapping Disconnect from the DeviceConnectedPopup.
@MainActor
private func handleDisconnect(router: AppRouter) {
    router.barBotPath.removeLast(router.barBotPath.count)
    router.explorePath.removeLast(router.explorePath.count)
    router.myBarPath.removeLast(router.myBarPath.count)
    router.homePath.removeLast(router.homePath.count)
    router.activeCraftingScreen = nil
    router.setupStationsContext = nil
    router.selectedTab = .homeOrControlCenter
    router.showSideMenu = false
    router.showBarBotHistory = false
}

// MARK: - Route resolver

/// Wrapper used by the two EditRecipeView fullScreenCover call sites
/// (`RecipeDetailView` + `FavoritesView`). Owns a local
/// `NavigationPath` so Craft / other pushes from inside Edit layer on
/// top of Edit inside the cover, instead of into the parent tab's
/// NavigationStack (which sits below the cover and would render the
/// pushed screen invisibly).
///
/// Publishes the path as `\.editCoverPath` so `EditRecipeView.craft()`
/// can append to it without plumbing the binding through every
/// intermediate view.
struct EditRecipeCoverContent<Content: View>: View {
    @State private var path = NavigationPath()
    // Defensive re-injection of the app-level environment objects.
    // `.fullScreenCover` is supposed to inherit environment objects
    // from the presenting view on iOS 16+, but under certain conditions
    // (particularly when a Route is pushed from inside the cover onto
    // our local NavigationPath and `RouteView` constructs a destination
    // that uses `@EnvironmentObject`) the chain breaks — the destination
    // crashes with "No ObservableObject of type AppEnvironment found"
    // (stack trace lands on `RecipeDetailView.recipe.getter` /
    // `env.storage.recipe(by:)`). Capturing the objects from the
    // PRESENTING view here and re-injecting them on the cover's
    // NavigationStack guarantees every pushed destination inside the
    // cover sees the same environment as the rest of the app.
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService
    private let onClose: () -> Void
    private let content: () -> Content

    init(onClose: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        // Re-inject the environment objects — see comment above.
        .environmentObject(env)
        .environmentObject(router)
        .environmentObject(ble)
        .environment(\.editCoverPath, $path)
        // Direct close action — `EditRecipeView` reads this via
        // `@Environment(\.editCoverClose)` and invokes it for the
        // cross button + save-success flow. Works reliably on iPad
        // where `@Environment(\.dismiss)` inside this nav-stack root
        // did not propagate to the enclosing fullScreenCover.
        .environment(\.editCoverClose, onClose)
        // 1:1 with UIKit `EditViewController` glass-loader stack —
        // `UIApplication.shared.topViewController()?.showGlassLoader(...)`
        // (EditViewController.swift L262, L393) presents the loader
        // on the TOPMOST view controller, which on iOS == the
        // EditRecipeView when the user is selecting a Photos /
        // Camera image for the AI ingredient detection flow.
        //
        // The SwiftUI port mounts a single `loadingOverlay` at the
        // RootView (`BarsysAppSwiftUIApp.body`), but
        // `.fullScreenCover` presents this `EditRecipeCoverContent`
        // ABOVE that root, so the root-level loader is hidden behind
        // the cover and the user never sees the "Adding ingredients"
        // glass loader after picking a photo on the iPad ingredient
        // image picker (or the iPhone equivalent — same root cause).
        //
        // Mounting `.loadingOverlay(env.loading)` here on the cover
        // itself makes the loader render ON TOP of the EditRecipe
        // surface — exactly the UIKit `topViewController` semantics —
        // so `env.loading.show("Adding ingredients...")` from
        // `uploadAndProcessIngredient(image:)` and
        // `env.loading.show("Saving Recipe")` from the save-recipe
        // path now both surface the loader regardless of which
        // hosting context EditRecipe was opened from
        // (RecipeDetail's full-screen cover, FavoriteList's row tap,
        // BarBot history detail, etc.).
        //
        // Behaviour parity:
        //   • iPhone — was previously failing too; now works,
        //     visually identical to iPad except for typical
        //     idiom-driven container sizing already present in
        //     `LoadingOverlayModifier`.
        //   • iPad — fixed.
        //
        // Re-using `env.loading` (the same `LoadingState` injected
        // at the app root) means a `show` call from any view inside
        // the cover OR from the cover's parent both drive the same
        // observable; this loader simply renders the same state on
        // a different layer in the iOS view hierarchy. No risk of
        // showing two loaders simultaneously — `LoadingState` has a
        // single source of truth.
        .loadingOverlay(env.loading)
    }
}

struct RouteView: View {
    let route: Route
    /// `RouteView` needs the router so it can forward the transient
    /// `pendingStationUpdate` context into `SelectQuantityView`.
    /// 1:1 parity with UIKit `ControlCenterCoordinator.showSelectQuantity(flowToAdd:)`
    /// where the coordinator threads the full `StationCleaningFlow`
    /// payload through the push site.
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        switch route {
        case .recipeDetail(let id): RecipeDetailView(recipeID: id)
        case .exploreRecipes: ExploreRecipesView()
        case .makeMyOwn: MakeMyOwnView()
        case .editRecipe(let id): EditRecipeView(recipeID: id)
        case .mixlistList: MixlistListView()
        case .mixlistDetail(let id): MixlistDetailView(mixlistID: id)
        case .mixlistEdit(let id): EditMixlistView(mixlistID: id)
        case .favorites: FavoritesView()
        case .scanIngredients: ScanIngredientsView()
        case .myProfile: MyProfileView()
        case .preferences: PreferencesView()
        case .countryPicker: EmbeddedCountryPicker()
        case .selectQuantity(let ingredient):
            // Thread the originating station / perishable / category
            // context through from `router.pendingStationUpdate` (set
            // by the Refill button on `StationsMenuView`) into the
            // SelectQuantity screen so the refill posts back to the
            // SAME station with the SAME perishable flag — mirroring
            // UIKit `ControlCenterCoordinator.showSelectQuantity(flowToAdd:)`
            // where `flowToAdd` carries the full station context.
            SelectQuantityView(
                ingredientName: ingredient,
                stationName: router.pendingStationUpdate?.stationName,
                isPerishable: router.pendingStationUpdate?.isPerishable ?? false,
                primaryCategory: router.pendingStationUpdate?.primaryCategory,
                secondaryCategory: router.pendingStationUpdate?.secondaryCategory
            )
        case .pairDevice: PairDeviceView()
        case .deviceList: DeviceListView()
        case .deviceConnected(let id): DeviceConnectedView(deviceID: id)
        case .deviceRename(let id): DeviceRenameView(deviceID: id)
        case .stationsMenu: StationsMenuView()
        case .readyToPour: ReadyToPourView()
        case .stationCleaning: StationCleaningView()
        case .crafting(let id): CraftingView(recipeID: id)
        case .drinkComplete(let id): DrinkCompleteView(recipeID: id)
        case .barBotCraft: BarBotCraftView()
        case .barBotHistory: BarBotHistoryView()
        case .qrReader: QRReaderView()
        // 1:1 port of UIKit `WebViewController` — custom 50pt black
        // header with white back button + bold 16pt white title, system
        // nav bar hidden, tab bar hidden, pre-flight
        // "Please check your internet connection." alert.
        case .web(let url, let title): BarsysWebView(url: url, title: title)
        }
    }
}
