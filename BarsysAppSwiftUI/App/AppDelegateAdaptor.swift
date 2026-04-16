//
//  AppDelegateAdaptor.swift
//  BarsysAppSwiftUI
//
//  Thin UIKit lifecycle bridge. Only needed because Firebase Messaging, Braze,
//  and APNs require a UIApplicationDelegate. All other app logic lives in
//  `BarsysAppSwiftUIApp` and `AppEnvironment`.
//
//  INTEGRATION POINTS (uncomment and plug in your existing implementations):
//  - FirebaseApp.configure()
//  - Braze.init(...) + BrazeInAppMessageUI()
//  - IQKeyboardManager.shared.enable = true
//  - Push notification registration
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

    private func configureBraze() {
        // TODO: plug in existing Braze init. See BarsysApp/AppDelegate.swift configureBraze()
        // let configuration = Braze.Configuration(apiKey: "...", endpoint: "...")
        // let braze = Braze(configuration: configuration)
        // AppState.shared.braze = braze
        // let inAppMessageUI = BrazeInAppMessageUI()
        // braze.inAppMessagePresenter = inAppMessageUI
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

    // MARK: - Push

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Forward to Braze / Firebase Messaging as needed
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    // MARK: - Foreground presentation

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}
