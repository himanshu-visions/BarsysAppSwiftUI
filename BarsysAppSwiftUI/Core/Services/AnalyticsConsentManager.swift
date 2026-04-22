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
}
