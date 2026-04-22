//
//  BrazeService.swift
//  BarsysAppSwiftUI
//
//  1:1 port of UIKit `TrackEventsClass` Braze surface
//  (BarsysApp/Helpers/TrackEventsClass/TrackEventsClass.swift L130-215)
//  + BarsysApp/AppDelegate.swift `configureBraze()` (L79-103).
//
//  SDK linkage:
//  -----------
//  This file uses `#if canImport(BrazeKit)` so the project compiles both
//  WITHOUT the Braze pods (every call no-ops gracefully) AND WITH them
//  installed (every call hits the real SDK). To enable Braze in the
//  SwiftUI app:
//
//    1. Uncomment `pod 'BrazeKit'` and `pod 'BrazeUI'` in /Podfile
//    2. `pod install`
//    3. Re-open the .xcworkspace
//
//  Once linked, every method below routes to `Braze.shared` exactly the
//  way `TrackEventsClass` did in UIKit — including the
//  `AnalyticsConsentManager.isConsentGranted` gate, the push-subscription
//  toggle on login/logout, the `firstName` / `lastName` / `email` /
//  `phoneNumber` profile sync, the `wipeData()` on account deletion, and
//  the `logCustomEvent(name:properties:)` event firing.
//
//  Public API — mirrors `TrackEventsClass` Braze methods 1:1:
//   • `BrazeService.configure(launchOptions:)`        ← AppDelegate parity
//   • `setPushToken(_:)`                              ← AppDelegate parity
//   • `inAppMessageDisplayChoice(isUserLoggedIn:)`    ← AppDelegate IAM delegate
//   • `loginUser(userId:)`                            ← brazeLoginUser()
//   • `updateProfile(firstName:lastName:email:phone:userId:)` ← brazeUpdateProfile()
//   • `logoutUser()`                                  ← brazeLogoutUser()
//   • `deleteUser(userId:)`                           ← brazeDeleteUser()
//   • `track(event:properties:)`                      ← addBrazeCustomEventWithEventName()
//

import Foundation
import UIKit

#if canImport(BrazeKit)
import BrazeKit
#endif
#if canImport(BrazeUI)
import BrazeUI
#endif

// MARK: - Configuration constants
//
// 1:1 with UIKit `GlobalConstants.brazeApiKey` /
// `GlobalConstants.brazeEndpoint`
// (BarsysApp/Helpers/Constants/EnvironmentConfig.generated.swift L15-16).
// In UIKit these come from a generated file driven by an environment
// variable (`BARSYS_BRAZE_API_KEY` / `BARSYS_BRAZE_ENDPOINT` —
// BarsysApp/Scripts/generate_env.sh L74-75). The SwiftUI port hard-codes
// the same production key here so the app works out of the box; swap
// for a generated config when the build script is ported.
enum BrazeConfig {
    static let apiKey: String = "d5beb9b6-9499-4213-b4dd-f36322e1d444"
    static let endpoint: String = "sdk.iad-07.braze.com"
}

// MARK: - BrazeService
//
// Single global service vended through `AppEnvironment.braze`. Holds the
// `Braze` instance (when the SDK is linked) and exposes the `TrackEventsClass`
// surface to the rest of the app.

final class BrazeService {

    /// Shared singleton — initialized on first access. The instance held
    /// in `AppEnvironment.braze` forwards to this one so call-site usage
    /// (`env.braze.track(...)`) works identically to a per-environment
    /// instance, but the underlying `Braze` SDK has only one configured
    /// instance — matching UIKit `AppDelegate.braze` (a static).
    static let shared = BrazeService()

    /// Strong reference to the live Braze SDK instance once configured.
    /// Mirrors UIKit `AppDelegate.braze: Braze?` (AppDelegate.swift L29).
    /// Held as `Any?` so the type only needs to resolve when BrazeKit is
    /// linked — keeps this file compilable without the pods.
    private var brazeInstance: Any?

    /// Latest APNs device token captured from
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Cached so we can replay it to the Braze SDK if `configure()` ran
    /// after the OS already delivered the token (race tolerated).
    private var pendingPushToken: Data?

    private init() {}

    // MARK: - Configuration (ports AppDelegate.configureBraze, L79-103)

    /// Initialize the Braze SDK with the project API key + endpoint and
    /// wire the in-app-message presenter. Call from
    /// `AppDelegateAdaptor.application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// Mirrors the UIKit recipe exactly:
    ///   • `Braze.Configuration(apiKey:endpoint:)`
    ///   • `configuration.push.automation = true`
    ///   • `configuration.push.automation.requestAuthorizationAtLaunch =
    ///      AnalyticsConsentManager.isConsentGranted`
    ///   • `configuration.forwardUniversalLinks = true`
    ///   • `configuration.logger.level = .info`
    ///   • `configuration.api.sdkAuthentication = true`
    ///   • `BrazeInAppMessageUI()` → `braze.inAppMessagePresenter = ui`
    ///   • `UNUserNotificationCenter.current().setNotificationCategories(
    ///        Braze.Notifications.categories)`
    func configure() {
        #if canImport(BrazeKit)
        let configuration = Braze.Configuration(
            apiKey: BrazeConfig.apiKey,
            endpoint: BrazeConfig.endpoint
        )
        configuration.push.automation = true
        configuration.push.automation.requestAuthorizationAtLaunch =
            AnalyticsConsentManager.isConsentGranted
        configuration.forwardUniversalLinks = true
        configuration.logger.level = .info
        configuration.api.sdkAuthentication = true

        let braze = Braze(configuration: configuration)
        brazeInstance = braze

        #if canImport(BrazeUI)
        // 1:1 with UIKit AppDelegate.swift L94-96:
        //   let brazeUI = BrazeInAppMessageUI()
        //   brazeUI.delegate = self
        //   AppDelegate.braze?.inAppMessagePresenter = brazeUI
        //
        // The IAM delegate decision (discard vs show) is brokered by
        // `inAppMessageDisplayChoice(isUserLoggedIn:)` — wire it up at the
        // call site (e.g. an IAM delegate in `AppDelegateAdaptor`) once
        // BrazeUI is linked.
        let inAppMessageUI = BrazeInAppMessageUI()
        braze.inAppMessagePresenter = inAppMessageUI
        #endif

        // 1:1 with UIKit AppDelegate.swift L98-99:
        //   UNUserNotificationCenter.current().setNotificationCategories(
        //       Braze.Notifications.categories)
        UNUserNotificationCenter.current()
            .setNotificationCategories(Braze.Notifications.categories)

        // If APNs already delivered a token before the SDK finished
        // initialising, replay it now.
        if let token = pendingPushToken {
            braze.notifications.register(deviceToken: token)
            pendingPushToken = nil
        }
        #endif
    }

    // MARK: - Push token registration (ports AppDelegate.swift L253-255)

    /// Forward the APNs token to Braze. Call from
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Safe to call before `configure()` — the token is cached and
    /// replayed once the SDK is initialized.
    func setPushToken(_ deviceToken: Data) {
        pendingPushToken = deviceToken
        #if canImport(BrazeKit)
        if let braze = brazeInstance as? Braze {
            braze.notifications.register(deviceToken: deviceToken)
            pendingPushToken = nil
        }
        #endif
    }

    /// Forward an APNs payload to Braze for handling. Call from
    /// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
    /// and the foreground/background `UNUserNotificationCenterDelegate`
    /// hooks. Mirrors UIKit AppDelegate L274-280.
    @discardableResult
    func handleBackgroundNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        #if canImport(BrazeKit)
        if let braze = brazeInstance as? Braze {
            return braze.notifications.handleBackgroundNotification(
                userInfo: userInfo,
                fetchCompletionHandler: { _ in }
            )
        }
        #endif
        return false
    }

    /// Process a Braze notification tap from the foreground UNNC delegate
    /// (`userNotificationCenter(_:didReceive:withCompletionHandler:)`).
    /// Returns `true` if Braze claimed the notification (so the host can
    /// suppress its own handling).
    @discardableResult
    func handleUserNotification(_ response: UNNotificationResponse) -> Bool {
        #if canImport(BrazeKit)
        if let braze = brazeInstance as? Braze {
            return braze.notifications.handleUserNotification(
                response: response,
                withCompletionHandler: {}
            )
        }
        #endif
        return false
    }

    // MARK: - In-app message display gate (ports AppDelegate.swift L307-315)

    /// 1:1 port of UIKit `inAppMessage(_:displayChoiceForMessage:)`:
    ///   • `.discard` if the user is not authenticated (Braze should not
    ///     show IAMs to anonymous users — UIKit returns `.discard`).
    ///   • `.now` otherwise.
    /// Wire this from a `BrazeInAppMessageUIDelegate` once BrazeUI is
    /// linked and a delegate object exists in the SwiftUI app.
    enum InAppMessageDisplayChoice { case now, discard, reenqueue, later }
    func inAppMessageDisplayChoice(isUserLoggedIn: Bool) -> InAppMessageDisplayChoice {
        isUserLoggedIn ? .now : .discard
    }

    // MARK: - User identification (ports brazeLoginUser, L135-147)

    /// Attach the Braze user to the currently authenticated `userId`,
    /// flip push subscription to `.subscribed`, and re-enable Braze.
    /// Gated by `AnalyticsConsentManager.isConsentGranted` (the same
    /// guard UIKit applies at the top of `brazeLoginUser`).
    func loginUser(userId: String) {
        guard AnalyticsConsentManager.isConsentGranted else { return }
        guard !userId.isEmpty else { return }
        #if canImport(BrazeKit)
        guard let braze = brazeInstance as? Braze else { return }
        braze.user.set(pushNotificationSubscriptionState: .subscribed)
        braze.changeUser(userId: userId)
        braze.enabled = true
        #else
        _ = userId
        #endif
    }

    // MARK: - Profile sync (ports brazeUpdateProfile, L149-176)

    /// Sync the user's first name, email and phone number to Braze
    /// (PII minimisation: `lastName` is intentionally cleared to ""
    /// per UIKit L159). Phone is digit-stripped and re-prefixed with
    /// `"+"` for push targeting (UIKit L165-172).
    ///
    /// Order matches UIKit `brazeUpdateProfile()` exactly:
    ///   1. `set(firstName:)`        ← UIKit L158
    ///   2. `set(lastName: "")`      ← UIKit L159
    ///   3. `set(email:)`            ← UIKit L162  (always called, even if nil/empty)
    ///   4. `set(phoneNumber:)`      ← UIKit L170  (only if non-empty digits)
    ///   5. `changeUser(userId:)`    ← UIKit L174
    ///
    /// `firstName` and `email` are forwarded UNCONDITIONALLY (matching
    /// UIKit which calls `.set(email: getEmail())` even when the
    /// stored value is nil — Braze interprets nil as "clear that
    /// attribute", which is the intended behaviour after a user
    /// removes their email).
    func updateProfile(firstName: String?,
                       email: String?,
                       phone: String?,
                       userId: String) {
        guard AnalyticsConsentManager.isConsentGranted else { return }
        guard !userId.isEmpty else { return }
        #if canImport(BrazeKit)
        guard let braze = brazeInstance as? Braze else { return }
        braze.user.set(firstName: firstName)
        braze.user.set(lastName: "")
        braze.user.set(email: email)
        if let phone {
            let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if !digits.isEmpty {
                braze.user.set(phoneNumber: "+\(digits)")
            }
        }
        braze.changeUser(userId: userId)
        #else
        _ = (firstName, email, phone, userId)
        #endif
    }

    // MARK: - Logout (ports brazeLogoutUser, L178-186)

    /// Unsubscribe the device from push and disable the SDK. Note: UIKit
    /// does NOT call `changeUser()` here — push subscription is just
    /// toggled off and `braze.enabled = false`.
    func logoutUser() {
        #if canImport(BrazeKit)
        guard let braze = brazeInstance as? Braze else { return }
        braze.user.set(pushNotificationSubscriptionState: .unsubscribed)
        braze.enabled = false
        #endif
    }

    // MARK: - Delete user (ports brazeDeleteUser, L188-200)

    /// Clear PII attributes, swap to `userId` (so the wipe is scoped),
    /// `wipeData()`, and disable the SDK. Mirrors the UIKit cleanup on
    /// account deletion exactly.
    func deleteUser(userId: String) {
        #if canImport(BrazeKit)
        guard let braze = brazeInstance as? Braze else { return }
        braze.user.set(firstName: nil)
        braze.user.set(email: nil)
        braze.user.set(phoneNumber: nil)
        braze.changeUser(userId: userId)
        braze.wipeData()
        braze.enabled = false
        #else
        _ = userId
        #endif
    }

    // MARK: - Custom events (ports addBrazeCustomEventWithEventName, L203-212)

    /// Log a custom event to Braze. Properties dictionary is forwarded
    /// when non-nil/empty, matching UIKit's `logCustomEvent(name:)` vs
    /// `logCustomEvent(name:properties:)` branch.
    /// Gated by `AnalyticsConsentManager.isConsentGranted`.
    func track(event: String, properties: [String: Any] = [:]) {
        guard AnalyticsConsentManager.isConsentGranted else { return }
        guard !event.isEmpty else { return }
        #if canImport(BrazeKit)
        guard let braze = brazeInstance as? Braze else { return }
        if properties.isEmpty {
            braze.logCustomEvent(name: event)
        } else {
            braze.logCustomEvent(name: event, properties: properties)
        }
        #else
        _ = (event, properties)
        #endif
    }

    /// Convenience for the existing `BrazeService` API surface
    /// (`setUser(id:)`) used by the env stub before this rewrite — kept
    /// so downstream call-sites that already use `env.braze.setUser(id:)`
    /// keep working without churn.
    func setUser(id: String) { loginUser(userId: id) }
}
