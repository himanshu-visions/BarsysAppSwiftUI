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
                .preferredColorScheme(.light)
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
