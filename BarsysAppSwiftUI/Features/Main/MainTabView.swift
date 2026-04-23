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

    var body: some View {
        ZStack(alignment: .leading) {
            TabView(selection: $router.selectedTab) {

                // 0 — BarBot
                NavigationStack(path: $router.barBotPath) {
                    BarBotCraftView()
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
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
            .onChange(of: ble.isAnyDeviceConnected) { _ in
                setFourthTabToSearchItem()
            }
            // Re-apply selectedImage of the 4th tab when user switches
            // tabs — SwiftUI's `.tabItem` rebuild can reset the
            // 4th-tab's search-item selectedImage. A small defer lets
            // SwiftUI's rebuild land first so we overwrite the final
            // state (not an intermediate one that gets rebuilt).
            //
            // The first 3 tabs do NOT need any runtime re-apply now —
            // their horizontal composite is baked directly into
            // SwiftUI's `.tabItem` via `Image(uiImage:)` (see
            // `tabLabel(_:connected:)`), so SwiftUI reproduces the
            // exact same content on every rebuild. No race, no flicker.
            .onChange(of: router.selectedTab) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    setFourthTabToSearchItem()
                }
            }
            // Re-apply on color-scheme flip so the 4th tab's selected
            // asset switches between light and dark variants live.
            .onChange(of: colorScheme) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    setFourthTabToSearchItem()
                }
            }
            // Re-apply on scene activation (background → foreground)
            // — catches theme flips that happened while app was
            // suspended.
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    setFourthTabToSearchItem()
                }
            }
            // Clear the home nav stack every time the connection state flips
            // so the new root view (Home or ControlCenter) is the top of the
            // stack — 1:1 match with replaceTabsAfterConnections which
            // replaces the navigation controller's root VC in UIKit.
            .onChange(of: ble.isAnyDeviceConnected) { _ in
                // Clear BOTH home and explore nav stacks when connection
                // state changes so the new root views appear cleanly.
                router.homePath.removeLast(router.homePath.count)
                router.explorePath.removeLast(router.explorePath.count)
                // Update the 4th tab's search item icon to match new state
                // (home icon ↔ control centre icon)
                setFourthTabToSearchItem()
            }

            SideMenuOverlay()
        }
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
        appearance.backgroundColor = UIColor.white.withAlphaComponent(0.01)
        appearance.backgroundEffect = nil

        // Dynamic UIColor providers — light variants are bit-identical
        // to the historical hard-coded `UIColor.black(...)` values, so
        // the tab bar renders the EXACT same pixels in light mode as
        // before. In dark mode the resolver returns the white-tinted
        // counterparts so icons / titles stay legible against the dark
        // `primaryBackgroundColor` canvas instead of disappearing into
        // a black-on-dark blur.
        let unselectedIconColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.55)
                : UIColor.black.withAlphaComponent(0.55) // EXACT historical value
        }
        let unselectedTitleColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.6)
                : UIColor.black.withAlphaComponent(0.6) // EXACT historical value
        }
        let selectedColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white
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
            // UIKit L133-139 pre-26 branch: lift the titles 12pt closer
            // to their icons (the stacked layout otherwise puts them too
            // far down with the asset icon + no title).
            item.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -12)
            item.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -12)
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
        // Strategy: modify the EXISTING UITabBarItem in-place rather than
        // creating a new one. SwiftUI's TabView manages its own tab items
        // and can overwrite a replacement item on re-render. By mutating
        // the existing item's properties, the changes survive re-renders.
        // We also create a .search system item as fallback if the existing
        // one isn't already a search type.
        let existingItem = vcs[tabIndex].tabBarItem
        let searchItem: UITabBarItem

        // Check if it's already a .search system item (tag == tabIndex)
        if existingItem?.tag == tabIndex {
            searchItem = existingItem!
        } else {
            searchItem = UITabBarItem(tabBarSystemItem: .search, tag: tabIndex)
        }

        if isConnected {
            // Pick the dark-mode variant of the Control Center
            // selected-state asset when the system is in dark mode,
            // otherwise keep the historical `newControlCenterSelectedTab`
            // asset for light (bit-identical light-mode behaviour).
            // Re-evaluated every time `setFourthTabToSearchItem` runs —
            // including on the `.onChange(of: colorScheme)` hook below —
            // so the icon swaps live when the user toggles appearance.
            let controlCenterSelectedAssetName = colorScheme == .dark
                ? "newControlCenterSelectedTabDark"
                : "newControlCenterSelectedTab"
            searchItem.selectedImage = UIImage(named: controlCenterSelectedAssetName)?.withRenderingMode(.alwaysOriginal)
            searchItem.image = UIImage(named: "controlCentreIcon")
            searchItem.title = "Control Center"
        } else {
            searchItem.image = UIImage(named: "homeIcon")
            // Pick the dark-mode variant of the Home selected-state
            // asset when the system is in dark mode, otherwise keep
            // the historical `newHomeSelectedTab` asset for light
            // (bit-identical light-mode behaviour). Re-evaluated
            // every time `setFourthTabToSearchItem` runs — including
            // on the `.onChange(of: colorScheme)` hook below — so
            // the icon swaps live when the user toggles appearance.
            let homeSelectedAssetName = colorScheme == .dark
                ? "newHomeSelectedTabDark"
                : "newHomeSelectedTab"
            searchItem.selectedImage = UIImage(named: homeSelectedAssetName)?.withRenderingMode(.alwaysOriginal)
            searchItem.title = "Home"
        }

        vcs[tabIndex].tabBarItem = searchItem

        // Force the tab bar to re-layout so it picks up the new selectedImage
        tabBarController.tabBar.setNeedsLayout()
        tabBarController.tabBar.layoutIfNeeded()
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
            Task {
                await env.catalog.preload()
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
