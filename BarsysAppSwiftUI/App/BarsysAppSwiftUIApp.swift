//
//  BarsysAppSwiftUIApp.swift
//  BarsysAppSwiftUI
//
//  Pure SwiftUI rewrite of BarsysApp.
//  App entry point — owns the root `AppEnvironment` and `AppRouter`
//  and decides whether to show the auth flow or the main app shell.
//

import SwiftUI

@main
struct BarsysAppSwiftUIApp: App {

    // Forward UIKit lifecycle callbacks (APNs / Braze / deep links) to a thin adaptor.
    // Remove or comment out if you do not have Firebase / Braze pods installed yet.
    @UIApplicationDelegateAdaptor(AppDelegateAdaptor.self) private var appDelegate

    @StateObject private var environment = AppEnvironment.live()
    @StateObject private var router = AppRouter()
    @StateObject private var userStore = UserProfileStore.shared

    /// QA-flagged fix: on iOS 26 the Liquid-Glass toolbar items (back-
    /// button circle + favourites/profile pill) sample their tint from
    /// the bar's `scrollEdgeAppearance` while content is at the top,
    /// then switch to `standardAppearance` once content scrolls beneath
    /// the bar. SwiftUI's `.toolbarBackground` only writes one of those
    /// slots reliably, so screens with dark imagery beneath the nav
    /// bar (Recipe Detail's hero image, Mixlist Detail's banner,
    /// BarBot, Crafting, etc.) tinted the capsules grey/dark as the
    /// user scrolled.
    ///
    /// Configuring `UINavigationBar.appearance()` with an opaque
    /// `primaryBackgroundColor` background across ALL FOUR appearance
    /// slots (standard, scrollEdge, compact, compactScrollEdge) BEFORE
    /// any view is created locks every navigation bar in the app to
    /// the same flat canvas — the toolbar items now compose against
    /// the opaque bar instead of the scroll content beneath, so the
    /// back-button circle + favourites/profile pill stay visually
    /// identical at all scroll positions on every screen.
    /// `isTranslucent = false` is the belt-and-braces switch that
    /// stops UIKit from blending its default blur into the bar.
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        if let bg = UIColor(named: "primaryBackgroundColor") {
            appearance.backgroundColor = bg
        }
        // Belt-and-braces shadow removal: pre-iOS 26 UINavigationBar
        // can render a 1pt hairline divider at the bottom of the bar
        // even when `shadowColor = .clear` is set — the system also
        // honours `shadowImage` (legacy property used by older iOS
        // versions to draw a 1×1 stretchable image as the shadow).
        // Setting BOTH a clear shadow colour AND an empty shadow image
        // guarantees no visible underline below the toolbar on every
        // iOS version + iPad / iPhone idiom. Without the empty shadow
        // image, iOS <26 was leaving a visible hairline directly under
        // the nav bar across every Explore / MyBar / Recipes /
        // Mixlists / Favorites / Profile / Preferences screen.
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()
        appearance.backgroundImage = UIImage()

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = appearance
        proxy.scrollEdgeAppearance = appearance
        proxy.compactAppearance = appearance
        proxy.compactScrollEdgeAppearance = appearance
        proxy.isTranslucent = false
        // Legacy iOS shadow-removal hooks — `shadowImage` /
        // `setBackgroundImage(_:for:)` on the UINavigationBar proxy
        // itself catch any UIKit code path that bypasses the modern
        // `UINavigationBarAppearance` configuration above (some
        // SwiftUI internals on iOS <26 still consult these properties
        // when computing the bottom hairline). Using the empty image
        // route here so iPhone + iPad pre-iOS 26 both render the bar
        // without a divider line beneath it.
        proxy.shadowImage = UIImage()
        proxy.setBackgroundImage(UIImage(), for: .default)

        // -------------------------------------------------------------
        // Pre-mount UITabBar appearance — iOS < 26 only.
        //
        // Why HERE and not in MainTabView.configureAppearance(): we
        // need the appearance proxy values populated BEFORE any
        // SwiftUI view (including TabView) is constructed. Moving the
        // setup to `MainTabView.onAppear` runs it AFTER UITabBar has
        // already been mounted with default UIKit values — which is
        // the user-reported "icon at top, title at bottom, not
        // centered together until first selection" race. Setting the
        // proxy in App.init guarantees the values are ready by the
        // time SwiftUI's TabView creates its hosting
        // UITabBarController, so the very first frame already has
        // our `titlePositionAdjustment = -12` + matching
        // `imageInsets` baked in. iOS 26+ keeps its native glass tab
        // bar — we early-return out of this block and let UIKit's
        // pre-26 fallback never apply.
        if #available(iOS 26.0, *) {
            // iOS 26+ tab bar configuration is handled per-instance
            // inside `MainTabView.configureAppearance()` (the iOS 26+
            // branch needs `shadowColor` set to a translucent grey
            // for the glass canvas — different value than pre-26).
        } else {
            let tabAppearance = UITabBarAppearance()
            tabAppearance.configureWithOpaqueBackground()
            tabAppearance.backgroundColor = UIColor(named: "primaryBackgroundColor")
                ?? UIColor.systemBackground
            tabAppearance.backgroundEffect = nil
            // Hide the 1pt grey hairline at the top of the tab bar.
            tabAppearance.shadowColor = .clear
            tabAppearance.shadowImage = UIImage()

            // Item appearance — colors are dynamic UIColor providers
            // so they auto-adapt to light/dark on the trait flip,
            // matching `MainTabView.configureAppearance()`'s palette
            // bit-for-bit.
            let softWhiteUIColor = UIColor(named: "softWhiteTextColor") ?? .white
            let unselectedIconColor = UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? softWhiteUIColor.withAlphaComponent(0.55)
                    : UIColor.black.withAlphaComponent(0.55)
            }
            let unselectedTitleColor = UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? softWhiteUIColor.withAlphaComponent(0.6)
                    : UIColor.black.withAlphaComponent(0.6)
            }
            let selectedColor = UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? softWhiteUIColor
                    : UIColor.black
            }

            let tabItemAppearance = UITabBarItemAppearance()
            tabItemAppearance.normal.iconColor = unselectedIconColor
            tabItemAppearance.normal.titleTextAttributes = [
                .foregroundColor: unselectedTitleColor
            ]
            tabItemAppearance.selected.iconColor = selectedColor
            tabItemAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor
            ]

            // ZERO position adjustments — let UIKit's default stacked
            // layout center the icon directly above the title. Why
            // we removed the previous -12pt title adjustment + paired
            // imageInsets:
            //
            //   • `titlePositionAdjustment` IS appearance-compliant —
            //     it propagates through `UITabBar.appearance()` and
            //     applies on the FIRST render, immediately moving
            //     titles up by -12pt.
            //   • `imageInsets` is NOT appearance-compliant on the
            //     `UITabBarItem.appearance()` proxy. SwiftUI-created
            //     UITabBarItem instances do NOT pick the value up,
            //     so the icon stays at its default position.
            //
            // The combination produced exactly the user-reported
            // "icon and title not center-aligned each other on first
            // run" symptom: title moved up via the proxy, icon stayed
            // put, group looked misaligned. After the user tapped a
            // tab, our per-item `imageInsets` write inside
            // `setupCustomSelectionViewIfNeeded` finally landed and
            // shifted the icon up too — that's the "fixes itself
            // after selection" behaviour they reported.
            //
            // Removing both adjustments means there's NOTHING async
            // to race against — every UITabBarItem is born with
            // UIKit's stock stacked layout, icon and title naturally
            // centered together, identical from the very first frame
            // through every tab tap. The visual is slightly more
            // spaced than UIKit pre-26's storyboard had, but it is
            // CONSISTENT — no fluctuation, no flicker, no snap.
            tabAppearance.stackedLayoutAppearance = tabItemAppearance
            tabAppearance.inlineLayoutAppearance = tabItemAppearance
            tabAppearance.compactInlineLayoutAppearance = tabItemAppearance

            UITabBar.appearance().standardAppearance = tabAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.auth)
                .environmentObject(environment.preferences)
                .environmentObject(environment.catalog)
                .environmentObject(environment.ble)
                .environmentObject(environment.loading)
                .environmentObject(environment.alerts)
                .environmentObject(router)
                .environmentObject(userStore)
                .tint(Theme.Color.brand)
                // Respect system appearance.
                //
                // Light mode is byte-identical to the historical
                // build: every existing colorset's light variant was
                // left untouched (only NEW dark variants were added),
                // and the only Swift token affected — `Theme.Color.surface`
                // — points at `surfaceColor` whose light entry is
                // pure white sRGB(1, 1, 1), the same pixel value the
                // hard-coded `Color.white` resolved to.
                //
                // Dark mode activates automatically when the device's
                // system appearance is dark: the new asset dark
                // variants kick in, and the system materials we use
                // (`.regularMaterial`, `.ultraThinMaterial`,
                // `UIGlassEffect/.systemMaterial` inside
                // `BarsysGlassPanelBackground`) adapt natively — the
                // side menu glass, edit-recipe glass, popup cards,
                // and every blur surface in the app pick up their
                // dark-mode counterparts without any per-screen code
                // changes.
        }
    }
}

// MARK: - Root

/// Decides what to present at the top of the window based on auth + splash state.
struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            switch router.rootScreen {
            case .splash:
                SplashView()
            case .auth:
                AuthFlowView()
            case .main:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: router.rootScreen)
        .loadingOverlay(env.loading)
        .appAlert(env.alerts)
        .toastOverlay(env.toast)
        .task {
            // Wire SessionExpirationHandler before bootstrap fires any network
            // calls — otherwise an early 401 (e.g. recipe/mixlist preload
            // after a long app suspension with a rolled Ory session) would
            // reach the singleton before its alert + logout closures are
            // installed and be silently dropped. 1:1 with UIKit hooking
            // `NetworkingUtility` at AppDelegate bootstrap.
            configureSessionExpirationHandler()

            await env.bootstrap()
            router.handleBootstrap(authenticated: env.auth.isAuthenticated)
        }
    }

    /// Installs the two hooks `SessionExpirationHandler` needs:
    ///   1. how to surface the alert (via `env.alerts.showSessionExpired`)
    ///   2. how to perform the logout once the user taps OK
    ///
    /// Uses the same clear-UserDefaults + auth.logout + router.logout
    /// sequence that `SideMenuView.performLogout()` runs for the manual
    /// logout path, so both code paths converge on identical state after
    /// returning to the auth screen.
    private func configureSessionExpirationHandler() {
        SessionExpirationHandler.shared.configure(
            showAlert: { [env] onConfirm in
                env.alerts.showSessionExpired(onConfirm: onConfirm)
            },
            performLogout: { [env, router] in
                // 1:1 with UIKit `logoutActionWithMessage(reason: .sessionExpired)`:
                //   show "Logging Out" loader → track logout event →
                //   disconnect BLE → remove last-connected-device data →
                //   clearAll UserDefaults → clear cache timestamps →
                //   AFTER 1.5s loader: auth.logout() + router.logout().
                env.loading.show(Constants.loaderLoggingOut)
                env.analytics.track(TrackEventName.logoutEvent.rawValue)
                // Silent disconnect — see `BLEService.disconnectAllSilently()`
                // for the rationale (suppresses the red "{device} is
                // Disconnected" toast + alert on session-expired / logout
                // so the user lands on Login without an error noise-trail).
                env.ble.disconnectAllSilently()
                UserDefaultsClass.removeLastConnectedDevice()
                UserDefaultsClass.removeLastConnectedDeviceTime()
                UserDefaultsClass.clearAll()
                // Reset the in-memory `@Published` tutorial flag so it
                // tracks the just-cleared UserDefaults key. Kept for
                // parity, no longer affects post-login routing — see
                // SideMenuView.performLogout.
                env.preferences.hasSeenTutorial = false
                UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForCacheRecipeData")
                UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForMixlistData")
                UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForFavourites")
                UserDefaults.standard.removeObject(forKey: "coreDataMixlistCount")

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    env.loading.hide()
                    env.auth.logout()
                    router.logout()
                }
            }
        )
    }
}
