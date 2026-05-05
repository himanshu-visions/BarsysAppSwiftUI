//
//  AppDelegateAdaptor.swift
//  BarsysAppSwiftUI
//
//  Thin UIKit lifecycle bridge. Only needed because Firebase Messaging, Braze,
//  and APNs require a UIApplicationDelegate. All other app logic lives in
//  `BarsysAppSwiftUIApp` and `AppEnvironment`.
//
//  Braze SDK integration (1:1 with UIKit AppDelegate.swift):
//   • `application(_:didFinishLaunchingWithOptions:)` →
//      `BrazeService.shared.configure()` (UIKit AppDelegate L79-103)
//   • `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` →
//      `BrazeService.shared.setPushToken(_:)` (UIKit L253-255)
//   • `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` →
//      `BrazeService.shared.handleBackgroundNotification(_:)` (UIKit L274-280)
//   • `userNotificationCenter(_:didReceive:withCompletionHandler:)` →
//      `BrazeService.shared.handleUserNotification(_:)` (UIKit L274-280)
//
//  All Braze SDK calls go through `BrazeService` which uses
//  `#if canImport(BrazeKit)` so this code compiles whether or not the
//  BrazeKit / BrazeUI pods are installed.
//

import UIKit
import UserNotifications

final class AppDelegateAdaptor: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        configureFirebase()
        configureBraze()
        configureKeyboardManager()
        configureNotifications(application)
        return true
    }

    // MARK: - Configuration

    private func configureFirebase() {
        // TODO: plug in existing Firebase init
        // FirebaseApp.configure()
    }

    /// 1:1 port of UIKit `AppDelegate.configureBraze()` (L79-103). The
    /// real SDK calls live in `BrazeService.configure()` which uses
    /// `#if canImport(BrazeKit)` so this compiles WITH or WITHOUT the
    /// Braze pods installed. To activate Braze:
    ///   1. Uncomment `pod 'BrazeKit'` + `pod 'BrazeUI'` in /Podfile
    ///   2. `pod install`
    ///   3. Re-open the .xcworkspace
    private func configureBraze() {
        BrazeService.shared.configure()
    }

    private func configureKeyboardManager() {
        // TODO: plug in IQKeyboardManagerSwift
        // IQKeyboardManager.shared.enable = true
        // IQKeyboardManager.shared.enableAutoToolbar = false
        // IQKeyboardManager.shared.resignOnTouchOutside = true
    }

    private func configureNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        DispatchQueue.main.async { application.registerForRemoteNotifications() }
    }

    // MARK: - Push token registration (1:1 with UIKit AppDelegate L253-259)

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Forward to Braze. UIKit additionally hands the same token to
        // Firebase Messaging via `Messaging.messaging().apnsToken =
        // deviceToken` (AppDelegate.swift L254) — wire that here too
        // once Firebase is added to the SwiftUI Podfile.
        BrazeService.shared.setPushToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // UIKit just logs and continues — no special handling required.
        // Failure here doesn't break the app, the user just won't
        // receive push notifications until APNs registration succeeds
        // on a future launch.
    }

    // MARK: - Background notifications (1:1 with UIKit AppDelegate L274-280)

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler:
                        @escaping (UIBackgroundFetchResult) -> Void) {
        // Hand the silent / data push to Braze first — it owns content
        // refresh and silent push handling. If Braze didn't claim the
        // notification we just signal `.noData` so APNs marks the
        // delivery complete.
        let handled = BrazeService.shared.handleBackgroundNotification(userInfo)
        completionHandler(handled ? .newData : .noData)
    }

    // MARK: - Foreground presentation (UNUserNotificationCenterDelegate)

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 1:1 with UIKit AppDelegate.swift L266-272: `[.banner, .list,
        // .sound]`. UIKit deliberately does NOT include `.badge` in
        // the foreground presentation options — the badge count is
        // owned by the server-side Braze payload + app-icon counter,
        // not the per-notification banner. Including `.badge` here
        // would cause double-counting (system increments + Braze
        // payload), so we match UIKit's three-option set exactly.
        completionHandler([.banner, .list, .sound])
    }

    /// 1:1 port of UIKit AppDelegate.swift L274-280 — forwards the
    /// notification tap to Braze so deep links / IAM triggers fire.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        BrazeService.shared.handleUserNotification(response)
        completionHandler()
    }
}
