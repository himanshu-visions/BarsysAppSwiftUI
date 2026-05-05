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

    // MARK: - UserDefaults keys (must match UIKit `UserDefaultsClass`)

    private static let consentGrantedKey = "analytics_consent_granted"
    private static let promptShownKey = "analytics_consent_prompt_shown"

    // MARK: - Public API

    /// Whether the user has granted analytics consent. Returns `false`
    /// when the prompt was never shown OR the user denied — matching
    /// UIKit's two-step gate (you must have BOTH shown the prompt AND
    /// gotten an Allow tap to count as granted).
    static var isConsentGranted: Bool {
        guard hasPromptBeenShown else { return false }
        return UserDefaults.standard.bool(forKey: consentGrantedKey)
    }

    /// Whether the consent prompt has been shown at least once.
    static var hasPromptBeenShown: Bool {
        UserDefaults.standard.bool(forKey: promptShownKey)
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
    static func setConsent(_ granted: Bool) {
        UserDefaults.standard.set(granted, forKey: consentGrantedKey)
        UserDefaults.standard.set(true, forKey: promptShownKey)
    }

    /// Reset both flags — call on logout / account deletion so the
    /// next user is prompted afresh. Matches UIKit `resetConsent()`.
    static func resetConsent() {
        UserDefaults.standard.removeObject(forKey: consentGrantedKey)
        UserDefaults.standard.removeObject(forKey: promptShownKey)
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
