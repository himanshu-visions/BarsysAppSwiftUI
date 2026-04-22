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
            case .tutorial:
                TutorialView()
            case .main:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: router.rootScreen)
        .loadingOverlay(env.loading)
        .appAlert(env.alerts)
        .toastOverlay(env.toast)
        .task {
            await env.bootstrap()
            router.handleBootstrap(authenticated: env.auth.isAuthenticated,
                                    hasSeenTutorial: env.preferences.hasSeenTutorial)
        }
    }
}
