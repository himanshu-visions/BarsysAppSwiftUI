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

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService

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
            .tint(Theme.Color.brand)
            .onAppear {
                configureAppearance()
                wireBLECallbacks()
                // 1:1 port of UIKit `TabBarViewController.viewDidAppear`
                // which calls `setupSelectionView()` on iOS < 26.
                // Multiple staggered attempts so the setup lands AFTER
                // SwiftUI has fully mounted the underlying UITabBarController.
                // The function is idempotent — only mutates state when a
                // value actually differs — so duplicate runs are no-ops.
                // iOS 26+ early-returns inside the function.
                for delay: Double in [0.1, 0.3, 0.6, 1.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        setupCustomSelectionViewIfNeeded()
                    }
                }
            }
            // 1:1 port of UIKit `selectTab(_:)` →
            // `moveSelectionView(to:animated:true)` (line 232 in
            // TabBarViewController.swift). Animates the white pill to
            // the new tab on every selection change. iOS 26+ no-op.
            .onChange(of: router.selectedTab) { newTab in
                if #available(iOS 26.0, *) { return }
                // Re-apply the bottom-lift transform first — SwiftUI
                // sometimes resets it on tab-selection-driven body
                // updates, and we want the lift visible BEFORE the
                // pill animation starts.
                Self.reapplyTabBarOffset()
                guard let tabBar = Self.observedTabBar else {
                    // Tab bar not yet observed — defer until next runloop
                    // so SwiftUI mounts it, then re-attempt.
                    DispatchQueue.main.async {
                        setupCustomSelectionViewIfNeeded()
                    }
                    return
                }
                Self.positionSelectionView(in: tabBar,
                                           atIndex: newTab.rawValue,
                                           animated: true)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Self.reapplyPillPosition()
                }
            }
            .onChange(of: colorScheme) { _ in
                setFourthTabToSearchItem()
                Self.reapplyTabBarOffset()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Self.reapplyPillPosition()
                }
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else { return }
                // 0.1s defer — UIKit's trait-collection propagation
                // on foreground activation can land AFTER SwiftUI's
                // colorScheme update; waiting a tick guarantees we
                // resolve the final asset variant, not a stale one.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    setFourthTabToSearchItem()
                    // Foreground activation can also reset the tab
                    // bar's transform if the system stashed the bar's
                    // state during background — re-apply it.
                    Self.reapplyTabBarOffset()
                    Self.reapplyPillPosition()
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

        // iOS 26+ glass tab bar: for the first 3 tabs, render a
        // pre-composed HORIZONTAL (icon + title side-by-side) image
        // DIRECTLY inside SwiftUI's `.tabItem` via `Image(uiImage:)`.
        //
        // This is the ROOT fix for the "fluctuation on tab select"
        // issue:
        //
        //   Previously we let SwiftUI build a stacked `Label { Text }
        //   icon: { Image }` and then OVERWROTE the resulting
        //   `UITabBarItem.image` from Swift code after the fact.
        //   SwiftUI re-evaluates `.tabItem` on every body re-render
        //   (tab select, BLE flip, colorScheme flip) and rebuilds the
        //   `UITabBarItem` from the Label — wiping our composite
        //   until the next async re-apply landed. The user observed
        //   that race as flicker / inconsistent content.
        //
        //   With this approach the `.tabItem` content IS the composite
        //   from the start — SwiftUI's rebuild reproduces the exact
        //   same `Image(uiImage:)` every time, so there's nothing to
        //   race against and nothing to fluctuate. No async reapply
        //   needed for the first 3 tabs.
        //
        // The 4th tab (search system item) still needs runtime
        // UIKit hooks (handled in `setFourthTabToSearchItem`), and
        // pre-iOS 26 keeps the classic stacked Label — both paths
        // stay bit-identical to their previous behavior.
        if #available(iOS 26.0, *),
           tab != .homeOrControlCenter,
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
        view.backgroundColor = UIColor.white
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
        // still rounds the drawn background. The shadow gives the
        // capsule a soft "lifted" feel against the tab bar background
        // and reads as a much smoother UI than a flat fill.
        view.layer.masksToBounds = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.10
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 4
        view.isUserInteractionEnabled = false  // never swallow taps
        return view
    }()

    private static weak var observedTabBar: UITabBar?
    private static var tabBarBoundsObserver: NSKeyValueObservation?

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

    /// Re-applies the tab bar's lift transform — idempotent, safe to
    /// call on every relevant SwiftUI lifecycle event so the offset
    /// survives any internal SwiftUI relayout that might reset the
    /// tab bar's transform. iOS 26+ early-returns and never touches
    /// the tab bar.
    private static func reapplyTabBarOffset() {
        if #available(iOS 26.0, *) { return }
        guard let tabBar = observedTabBar else { return }
        let offset = tabBarLiftOffset(for: tabBar)
        if tabBar.transform.ty != -offset {
            tabBar.transform = CGAffineTransform(translationX: 0, y: -offset)
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
        Self.tabBarSelectionView.backgroundColor = UIColor.white

        // Belt-and-braces: hide the 1pt grey hairline at the top edge
        // of the tab bar on the LIVE instance. We already clear it via
        // `UITabBar.appearance()` in `configureAppearance()`, but
        // defensive instance-level overrides catch any internal
        // UIKit code path that re-derives the shadow from a default
        // appearance after our proxy values were set.
        if let standardCopy = tabBar.standardAppearance.copy() as? UITabBarAppearance {
            standardCopy.shadowColor = .clear
            standardCopy.shadowImage = UIImage()
            tabBar.standardAppearance = standardCopy
        }
        if let scrollEdge = tabBar.scrollEdgeAppearance,
           let scrollCopy = scrollEdge.copy() as? UITabBarAppearance {
            scrollCopy.shadowColor = .clear
            scrollCopy.shadowImage = UIImage()
            tabBar.scrollEdgeAppearance = scrollCopy
        }
        // Legacy hairline stripper — pre-iOS-13 paths still consult
        // `shadowImage` directly on the UITabBar before falling back
        // to the appearance object. An empty image kills the legacy
        // line in those paths too. Note: we deliberately do NOT
        // assign `backgroundImage` here — that would clear the tab
        // bar's opaque `primaryBackgroundColor` fill set in
        // `configureAppearance()`.
        tabBar.shadowImage = UIImage()

        // 1:1 with UIKit's `viewDidLayoutSubviews`:
        //   frame.origin.y = view.frame.height - frame.height - 27
        // We use a translation transform instead of a frame mutation
        // because SwiftUI re-lays-out the tab bar on every body update
        // and would clobber a manual frame change. Transform survives.
        // (Compare ty directly — CGAffineTransform isn't Equatable in
        // older Swift toolchains, and using `==` triggers compiler
        // ambiguity issues on certain SDKs.)
        // The offset is resolved dynamically via `tabBarLiftOffset(for:)`
        // — at minimum UIKit's hardcoded 27pt, but expanded to
        // `safeAreaInsets.bottom + 10pt` on devices with a home-indicator
        // safe area so the bar's bottom edge clears that strip.
        let liftOffset = Self.tabBarLiftOffset(for: tabBar)
        if tabBar.transform.ty != -liftOffset {
            tabBar.transform = CGAffineTransform(translationX: 0, y: -liftOffset)
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
                    let parentTBC = obs.next as? UITabBarController
                    let idx = parentTBC?.selectedIndex ?? 0
                    Self.positionSelectionView(in: obs,
                                               atIndex: idx,
                                               animated: false)
                    // Defensive: a bounds change on rotation can
                    // sometimes drop the transform. Re-apply if needed.
                    // Uses the same dynamic resolver as the initial
                    // setup so iPhone / iPad / notch-less devices each
                    // get the right lift amount (≥ 27, ≥ safeArea+10).
                    let liftOffset = Self.tabBarLiftOffset(for: obs)
                    if obs.transform.ty != -liftOffset {
                        obs.transform = CGAffineTransform(translationX: 0, y: -liftOffset)
                    }
                }
            }
            Self.observedTabBar = tabBar
        }

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
            // Center the pill around the ACTUAL icon+title bounding
            // box of the selected tab. Converting from the button's
            // coordinate space to the tab bar's keeps the math correct
            // regardless of how UIKit positioned the button inside its
            // slot (iPhone stacked and iPad inline both work — the
            // button's internal subview frames already encode the
            // chosen layout). The result is a pill whose top margin
            // == bottom margin == `paddingY`, and left margin ==
            // right margin == `paddingX`, around the visible content.
            let contentInTabBar = tabBar.convert(contentInButton, from: buttons[index])
            var x = contentInTabBar.minX - paddingX
            var w = contentInTabBar.width + paddingX * 2
            let y = contentInTabBar.minY - paddingY
            let h = contentInTabBar.height + paddingY * 2
            if index == AppTab.homeOrControlCenter.rawValue {
                // UIKit pre-26: 4th tab gets +5pt on each side
                // (TabBarViewController.swift:56-58). Preserved here
                // because the Control Center / Home label is wider than
                // its peers and a tighter hug would clip on the right.
                x -= 5
                w += 10
            }
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
            let xPosition = CGFloat(index) * itemWidth
                + (itemWidth - assumedContentWidth) / 2
                - paddingX
            let width = assumedContentWidth + paddingX * 2
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

            let titleY = (totalHeight - titleSize.height) / 2
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
