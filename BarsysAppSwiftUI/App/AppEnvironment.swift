//
//  AppEnvironment.swift
//  BarsysAppSwiftUI
//
//  Dependency-injection container. Produced once at `@main` and vended through
//  `@EnvironmentObject` so every view and view model can reach the services it needs.
//
//  The `.live()` factory wires up mock implementations by default. To connect the real
//  backend (the existing BarsysApp layer), replace each `Mock*` instance with the
//  corresponding class from the old project.
//

import SwiftUI
import Combine

final class AppEnvironment: ObservableObject {

    // MARK: - Services

    let api: APIClient
    let storage: StorageService
    let auth: AuthService
    let preferences: PreferencesService
    let ble: BLEService
    let socket: SocketService
    /// Real WebSocket client for the Barsys Speakeasy QR → device-pairing
    /// flow. 1:1 port of UIKit `SocketManager`. Created lazily per session
    /// so a reconnect always starts from a fresh state — matches UIKit
    /// `appDelegate?.socketManager = SocketManager()` per QR scan.
    let speakeasySocket = SpeakeasySocketManager()
    let braze: BrazeService
    let analytics: AnalyticsService
    let catalog: CatalogService

    // MARK: - Shared UI state

    @Published var loading = LoadingState()
    @Published var alerts = AlertQueue()
    let toast = ToastManager()

    init(api: APIClient,
         storage: StorageService,
         auth: AuthService,
         preferences: PreferencesService,
         ble: BLEService,
         socket: SocketService,
         braze: BrazeService,
         analytics: AnalyticsService,
         catalog: CatalogService) {
        self.api = api
        self.storage = storage
        self.auth = auth
        self.preferences = preferences
        self.ble = ble
        self.socket = socket
        self.braze = braze
        self.analytics = analytics
        self.catalog = catalog
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        await auth.restoreSession()
        // Always call preload if authenticated — MockStorageService is in-memory
        // so data is LOST on every app restart. Must re-fetch from API each time.
        // UIKit persists to SQLite so data survives restart; we don't have that
        // luxury with the mock, so we MUST fetch on every launch.
        //
        // **Silent bootstrap** (1:1 UIKit parity):
        // `SplashViewController.viewDidLoad` runs
        // `prefetchRecipesIfNeeded` silently — NO loader overlay —
        // while the splash GIF animates on top. The SwiftUI port
        // previously popped `loading.show("Loading…")` here, which
        // stacked a spinner on top of the splash GIF. Removed so the
        // splash renders cleanly.
        //
        // **Duration match** (1:1 UIKit parity):
        // UIKit `SplashViewController.viewDidAppear` calls
        // `DelayedAction.afterTransition(seconds: GlobalConstants.delayForSplash)`
        // where `delayForSplash = 2.5`. We hold the splash for the
        // same 2.5s by timing the data preload and sleeping only the
        // remainder. Fast networks don't skip the splash; slow
        // networks just extend naturally (user sees the GIF until
        // data is ready).
        let start = Date()
        if auth.isAuthenticated {
            await catalog.preload()
        }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, 2.5 - elapsed)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
    }

    /// Called after successful login/OTP verification.
    /// Ports the EXACT UIKit post-login data chain from LoginViewModel:
    ///   1. handleProfileFetchAndPostLogin → MyProfileApiService.getProfile()
    ///   2. getAllMixlistData → MixlistApiServices.getMixlist
    ///   3. getCacheRecipesData → MixlistApiServices.getCacheRecipes
    ///   4. getFavouritesData → FavoriteRecipeApiService.getFavouritesListApi
    ///   5. insertToDatabaseAndFetchCount → DBManager inserts
    ///   6. fetchAllRecipes → AppStateManager.updateRecipeCache
    ///   7. onPostLoginDataFetched → navigation fires
    /// Fire-and-forget version (for BLE callbacks etc.)
    func onLoginSuccess() {
        Task { await onLoginSuccessAsync() }
    }

    /// Awaitable version — waits for data to load before returning.
    /// Called from login/signup flows so data is ready before navigation.
    func onLoginSuccessAsync() async {
        // Wrap the entire post-login fetch chain in the
        // session-expired suppression scope. The Ory token persisted
        // by `verifyOtp` is fresh, but the downstream services
        // (`/my/profile`, `cache/recipes`, `cache/mixlists`, favourites)
        // can transiently respond with 401 / "expired session token"
        // immediately after sign-in — propagation lag in the Ory
        // session, server caches, etc. Without this guard the very
        // first stale 401 trips `SessionExpirationHandler` and shows
        // the "Your session has expired" alert moments after the user
        // just logged in. UIKit never hit this because its splash
        // controller silently absorbed early 401s while the splash
        // GIF held; we mirror that with an explicit scoped suppress.
        await SessionExpirationHandler.shared.suppressExpirationDuring {
            // Step 1: Fetch full profile (ports handleProfileFetchAndPostLogin → getProfile)
            if let oryAPI = api as? OryAPIClient {
                await oryAPI.fetchAndSyncProfile()
            }
            // Steps 2-6: Fetch mixlists + recipes + favourites + insert to storage
            await catalog.preload()
        }
    }

    // MARK: - Factory

    /// `@MainActor` because every caller — `@StateObject private var
    /// environment = AppEnvironment.live()` in the `@main` App struct
    /// — already runs on the main actor, and pinning the factory here
    /// lets it call any service initializer that the Swift concurrency
    /// checker may end up inferring as main-actor-isolated (e.g. when
    /// the type holds `@Published` properties or registers
    /// NotificationCenter observers).
    @MainActor
    static func live() -> AppEnvironment {
        let preferences = PreferencesService()
        let storage = MockStorageService()
        // Real Ory backend (https://iam.auth.barsys.com/self-service/) for
        // OTP-based phone login + signup. Same endpoints as the UIKit app.
        let api: APIClient = OryAPIClient()
        let catalog = CatalogService(storage: storage)
        catalog.setAPI(api) // Wire real API for recipe/mixlist fetching
        return AppEnvironment(
            api: api,
            storage: storage,
            auth: AuthService(api: api, preferences: preferences),
            preferences: preferences,
            ble: BLEService(),
            socket: SocketService(),
            braze: BrazeService.shared,
            analytics: AnalyticsService(),
            catalog: catalog
        )
    }
}
