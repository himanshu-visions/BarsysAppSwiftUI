//
//  AnalyticsConsentManager.swift
//  BarsysAppSwiftUI
//
//  1:1 port of UIKit
//  `BarsysApp/Helpers/TrackEventsClass/AnalyticsConsentManager.swift`.
//
//  Combines the project's GDPR analytics-consent flag with Apple's
//  AppTrackingTransparency status into a single decision surface used
//  by `BrazeService` and the backend event tracker. Every Braze call
//  in `BrazeService` is gated by `isConsentGranted`, matching UIKit
//  `TrackEventsClass.brazeLoginUser` /
//  `addBrazeCustomEventWithEventName` / `brazeUpdateProfile`.
//
//  Storage: identical UserDefaults keys to UIKit so a user who already
//  granted consent in the UIKit build keeps their choice when they
//  upgrade to the SwiftUI build:
//   • "analytics_consent_granted"        → Bool
//   • "analytics_consent_prompt_shown"   → Bool
//

import Foundation
import AppTrackingTransparency
import UIKit

enum AnalyticsConsentManager {

    // MARK: - Legacy snake_case keys (used by the SwiftUI scaffold
    //          before the UIKit-parity fix). Read once on the first
    //          access of either flag; the value is migrated to the
    //          UIKit-matching camelCase key in `UserDefaultsClass`
    //          and then this snake_case copy is deleted. After
    //          migration these are never read again.
    private static let legacyConsentGrantedKey = "analytics_consent_granted"
    private static let legacyPromptShownKey    = "analytics_consent_prompt_shown"

    /// One-shot legacy → UIKit-key migration. Idempotent: once the
    /// snake_case copies are absent (every device after the first
    /// post-upgrade launch) this is a pure no-op.
    private static func migrateLegacyConsentKeysIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: legacyConsentGrantedKey) != nil {
            UserDefaultsClass.saveAnalyticsConsentGranted(
                defaults.bool(forKey: legacyConsentGrantedKey)
            )
            defaults.removeObject(forKey: legacyConsentGrantedKey)
        }
        if defaults.object(forKey: legacyPromptShownKey) != nil {
            UserDefaultsClass.saveAnalyticsConsentPromptShown(
                defaults.bool(forKey: legacyPromptShownKey)
            )
            defaults.removeObject(forKey: legacyPromptShownKey)
        }
    }

    // MARK: - Public API

    /// Whether the user has granted analytics consent. Returns `false`
    /// when the prompt was never shown OR the user denied — matching
    /// UIKit's two-step gate (you must have BOTH shown the prompt AND
    /// gotten an Allow tap to count as granted).
    ///
    /// 1:1 with UIKit `AnalyticsConsentManager.isConsentGranted`
    /// (BarsysApp/Helpers/TrackEventsClass/AnalyticsConsentManager.swift L19-24)
    /// — same `hasPromptBeenShown && consentGranted` shape, same
    /// underlying `UserDefaults` keys (`analyticsConsentPromptShown` /
    /// `analyticsConsentGranted` in camelCase) so cross-build
    /// compatibility is preserved.
    static var isConsentGranted: Bool {
        migrateLegacyConsentKeysIfNeeded()
        guard UserDefaultsClass.getAnalyticsConsentPromptShown() else {
            return false
        }
        return UserDefaultsClass.getAnalyticsConsentGranted()
    }

    /// Whether the consent prompt has been shown at least once.
    static var hasPromptBeenShown: Bool {
        migrateLegacyConsentKeysIfNeeded()
        return UserDefaultsClass.getAnalyticsConsentPromptShown()
    }

    /// Whether ATT (App Tracking Transparency) is authorized. Returns
    /// `false` on iOS < 14 (no framework) or when the user denied or
    /// restricted tracking. Mirrors UIKit `isTrackingAuthorized`.
    @available(iOS 14, *)
    static var isTrackingAuthorized: Bool {
        ATTrackingManager.trackingAuthorizationStatus == .authorized
    }

    /// Whether IP address collection is permitted — requires BOTH the
    /// analytics consent and the ATT authorization (GDPR + CCPA). Used
    /// by the internal backend event tracker when assembling the event
    /// envelope's `session.ip` field.
    static var isIPCollectionPermitted: Bool {
        guard isConsentGranted else { return false }
        if #available(iOS 14, *) {
            return isTrackingAuthorized
        }
        return true
    }

    /// Update consent (e.g., from a Settings toggle, a custom prompt,
    /// or after the user accepted/declined the system ATT alert).
    ///
    /// 1:1 with UIKit `AnalyticsConsentManager.setConsent(_:)`
    /// (BarsysApp/Helpers/TrackEventsClass/AnalyticsConsentManager.swift L63-66):
    /// always sets `promptShown = true` so the prompt is treated as
    /// "answered" regardless of the answer — denial decisions stick
    /// across launches and the user is not re-prompted.
    static func setConsent(_ granted: Bool) {
        // Migrate legacy keys before writing — guarantees the new
        // value lands in the UIKit-matching slot even if the user
        // happens to call this in the same launch they're upgrading.
        migrateLegacyConsentKeysIfNeeded()
        UserDefaultsClass.saveAnalyticsConsentGranted(granted)
        UserDefaultsClass.saveAnalyticsConsentPromptShown(true)
    }

    /// Reset both flags — call on logout / account deletion so the
    /// next user is prompted afresh. Matches UIKit `resetConsent()`
    /// (BarsysApp/Helpers/TrackEventsClass/AnalyticsConsentManager.swift L57-60).
    static func resetConsent() {
        UserDefaultsClass.removeAnalyticsConsentGranted()
        UserDefaultsClass.removeAnalyticsConsentPromptShown()
        // Belt-and-braces: also wipe any pre-migration snake_case
        // copies so a stale legacy bool can't survive the reset and
        // resurface on next launch via the migration helper.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyConsentGrantedKey)
        defaults.removeObject(forKey: legacyPromptShownKey)
    }

    /// Trigger the iOS 14+ ATT system prompt. Call after the user
    /// taps "Allow" in the in-app analytics prompt. Matches UIKit
    /// `requestATTPermission()` — denial/restricted flips the analytics
    /// consent flag back to `false` so the two stay in sync.
    @MainActor
    static func requestATTPermission() {
        guard #available(iOS 14, *) else { return }
        ATTrackingManager.requestTrackingAuthorization { status in
            if status == .denied || status == .restricted {
                DispatchQueue.main.async { setConsent(false) }
            }
        }
    }

    /// Surface the analytics + ATT consent prompt the first time the
    /// user lands on Home after a successful login.
    ///
    /// 1:1 port of UIKit
    /// `AnalyticsConsentManager.requestConsentIfNeeded(from: UIViewController)`
    /// (BarsysApp/Helpers/TrackEventsClass/AnalyticsConsentManager.swift L51-54)
    /// + the private `showConsentAlert(from:)` helper L71-88. The
    /// SwiftUI variant takes an `AlertQueue` instead of a presenting
    /// view-controller because the SwiftUI app routes every popup
    /// through the shared `env.alerts` queue (Services.swift `AlertQueue`).
    ///
    /// Critical: without this prompt being surfaced, `hasPromptBeenShown`
    /// stays `false` forever, `isConsentGranted` returns `false` from
    /// the guard at the top of every Braze entry-point in
    /// `BrazeService` (`loginUser`, `updateProfile`, `track`,
    /// `requestAuthorizationAtLaunch`), and **no Braze events ever
    /// fire**. This was the missing piece in the SwiftUI port — the
    /// service code was correct but it was permanently gated off.
    ///
    /// Copy is identical to UIKit so a user upgrading from the UIKit
    /// build sees the same wording (and the same UserDefaults keys
    /// keep the existing decision sticky — see `setConsent`).
    @MainActor
    static func requestConsentIfNeeded(alertQueue: AlertQueue) {
        guard !hasPromptBeenShown else { return }
        alertQueue.show(
            title: "Analytics & Tracking",
            message: "We collect device info, usage data, and IP address to improve your experience. Your name, email, and phone number may be shared with our analytics partners. This includes Apple's App Tracking Transparency. You can change this anytime in Settings.",
            primaryTitle: "Allow",
            secondaryTitle: "Don't Allow",
            onPrimary: {
                // Mirrors UIKit `showConsentAlert` "Allow" branch
                // (AnalyticsConsentManager.swift L78-81): record consent
                // first, then surface the system ATT prompt so the user
                // sees one decision at a time. ATT denial later flips
                // analytics consent back to false via the callback in
                // `requestATTPermission()`.
                setConsent(true)
                Task { @MainActor in requestATTPermission() }
            },
            onSecondary: {
                // UIKit "Don't Allow" branch (L83-85). Records the
                // declined decision so we still set
                // `hasPromptBeenShown = true` and never re-prompt.
                setConsent(false)
            },
            hideClose: true
        )
    }
}
