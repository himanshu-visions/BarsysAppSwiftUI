//
//  SessionExpirationHandler.swift
//  BarsysAppSwiftUI
//
//  1:1 port of the UIKit session-expired pipeline:
//    • `NetworkingUtility.validateResponse` / `handleSessionExpiration`
//      (BarsysApp/Helpers/NetworkingUtility.swift L320-442)
//    • `NetworkingUtility.triggerSessionExpirationLogout` → shows the
//      standard alert "Your session has expired. Please log in again to
//      continue." with a single "Ok" button. On tap, it runs
//      `UIViewController.logoutActionWithMessage(reason: .sessionExpired)`
//      which clears UserDefaults, tears down BLE, tracks the Braze
//      logout event, and navigates back to the Login screen.
//
//  Architecture notes
//  ──────────────────
//  The UIKit version reaches into `UIApplication.shared.topViewController()`
//  to present the alert and derives the `AppCoordinator` from the
//  presenting VC. SwiftUI has neither a VC hierarchy nor a presenter
//  concept, so we use a singleton that is *configured* once from the
//  root view with two closures — one that shows the alert via the
//  live `AlertQueue`, one that performs the full logout (drive the
//  `AuthService`, `AppRouter`, UserDefaults, BLE, analytics). This
//  keeps `OryAPIClient` pure (it can call `handleExpiration()` without
//  knowing about environment objects) and lets the closures capture
//  the env for us.
//
//  Concurrency
//  ───────────
//  A single `isHandlingExpiration` flag guards against duplicate alerts
//  when multiple in-flight requests all receive 401 (e.g. recipes +
//  mixlists + profile fetched in parallel on app resume). Matches the
//  UIKit `@MainActor static var isHandlingExpiration` on
//  `NetworkingUtility`.
//

import Foundation

@MainActor
final class SessionExpirationHandler {

    static let shared = SessionExpirationHandler()

    /// UIKit `NetworkingUtility.isHandlingExpiration` — blocks concurrent
    /// 401s from stacking multiple alerts. Reset by `reset()` after the
    /// logout flow finishes, OR when the user returns to Login manually.
    private var isHandlingExpiration = false

    /// Suppression scope counter — when > 0, `handleExpiration()` is a
    /// no-op. Used to wrap the post-login data chain
    /// (`onLoginSuccessAsync`: profile fetch + recipes + mixlists +
    /// favourites) so a transient 401 from any of those endpoints
    /// can't fire the "session expired" alert moments after the user
    /// just authenticated. UIKit didn't see this race because it
    /// triggered the post-login fetches from inside
    /// `SplashViewController` AFTER its own delay, and dropped 401s
    /// during the splash hold; mirroring that here with an explicit
    /// scoped suppression is the simplest 1:1.
    private var suppressionDepth = 0

    /// Show-alert hook. Installed once from `RootView.task`. The closure
    /// receives a completion callback which must be invoked on "OK" tap
    /// so the handler can then run the logout flow.
    private var showAlert: ((@escaping () -> Void) -> Void)?

    /// Logout hook. Installed once from `RootView.task`. Runs the shared
    /// logout flow: loader → clear UserDefaults → auth.logout →
    /// router.logout (navigate back to auth).
    private var performLogout: (() -> Void)?

    private init() {}

    /// Install the alert + logout closures. Called once from `RootView.task`
    /// so the singleton doesn't need to hold references to the env / router.
    /// Closures capture the live objects by weak reference on the call
    /// site so memory still releases correctly across scene rebuilds.
    func configure(showAlert: @escaping (@escaping () -> Void) -> Void,
                   performLogout: @escaping () -> Void) {
        self.showAlert = showAlert
        self.performLogout = performLogout
    }

    /// Called from network code the moment a 401 / expired-body response
    /// is observed. De-dups concurrent calls and fires the alert. The
    /// logout runs only after the user taps OK.
    func handleExpiration() {
        // Inside a `suppressExpirationDuring` scope (e.g. the post-login
        // data fetch) — drop the 401 silently. Without this guard a
        // stale recipes/mixlists/profile 401 fired moments after a
        // successful OTP verify would log the user back out.
        guard suppressionDepth == 0 else { return }
        guard !isHandlingExpiration else { return }
        isHandlingExpiration = true

        guard let showAlert else {
            // Handler was invoked before configuration (unit test, or a
            // 401 on cold launch before RootView.task fires). Reset so
            // the next 401 after configuration can present.
            isHandlingExpiration = false
            return
        }

        showAlert { [weak self] in
            self?.performLogout?()
            // Reset after logout completes — the next session can raise
            // a fresh alert. Matches UIKit `NetworkingUtility.resetExpirationFlag()`
            // which is called from the logout completion path.
            self?.isHandlingExpiration = false
        }
    }

    /// UIKit `NetworkingUtility.resetExpirationFlag()` — called when the
    /// user is back on the Login screen so a subsequent session can fire
    /// a new alert without needing a full app restart.
    func reset() {
        isHandlingExpiration = false
    }

    /// Run `block` with the session-expired alert suppressed. Designed
    /// for the post-login data chain so a stale-token 401 on
    /// `/my/profile`, `/cache/recipes`, `/cache/mixlists`, etc. can't
    /// log the user back out moments after a successful OTP verify.
    /// Reentrant via `suppressionDepth` so nested wrappers stay safe.
    func suppressExpirationDuring<T>(_ block: () async -> T) async -> T {
        suppressionDepth += 1
        defer { suppressionDepth -= 1 }
        return await block()
    }
}

// MARK: - Inspection helper

/// Mirrors UIKit `NetworkingUtility.validateResponse` + `isSessionExpiredInBody`:
/// a 401 status code, OR a 200 response whose body contains the raw
/// `"expired session token"` marker, both mean "session has expired —
/// drop everything and log the user out".
///
/// Call sites use this as `guard !SessionExpirationCheck.isSessionExpired(...)`
/// right after `URLSession.shared.data(for:)`. When `true`, the call site
/// must also notify the handler and stop further processing of the body
/// (no decode, no storage write, no navigation).
enum SessionExpirationCheck {

    /// Pure predicate — no side effects, so safe to call from any thread.
    static func isSessionExpired(response: URLResponse?, data: Data?) -> Bool {
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            return true
        }
        if let data, let body = String(data: data, encoding: .utf8),
           body.contains(Constants.expiredSessionTokenBodyMarker) {
            return true
        }
        return false
    }

    /// Convenience: predicate + side effect. Returns `true` when the
    /// response indicates an expired session AND has notified the handler.
    /// Call sites that simply want to short-circuit on expired sessions
    /// can write:
    ///
    ///     if await SessionExpirationCheck.inspectAndHandle(response: r, data: d) {
    ///         return []  // or throw
    ///     }
    @discardableResult
    static func inspectAndHandle(response: URLResponse?, data: Data?) async -> Bool {
        guard isSessionExpired(response: response, data: data) else { return false }
        await MainActor.run {
            SessionExpirationHandler.shared.handleExpiration()
        }
        return true
    }
}
