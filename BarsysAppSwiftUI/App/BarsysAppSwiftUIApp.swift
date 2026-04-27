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
