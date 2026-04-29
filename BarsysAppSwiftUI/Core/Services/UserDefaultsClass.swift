//
//  UserDefaultsClass.swift
//  BarsysAppSwiftUI
//
//  Direct 1:1 port of BarsysApp/Controllers/Login/UserDefaultsClass.swift
//  — same method names, same underlying keys, so when the real Keychain-
//  backed adapter is wired in (Phase 2) it's a drop-in replacement.
//
//  The UIKit version stores sensitive data (tokens, PII) in the iOS Keychain
//  via `KeychainHelper.shared` and non-sensitive data (flags, timestamps)
//  in `UserDefaults`. The SwiftUI port uses `UserDefaults` for EVERYTHING
//  during scaffolding; the keys are byte-identical to the UIKit ones so a
//  user who logs in on the UIKit app and then runs the SwiftUI target with
//  the same bundle id sees the same data.
//

import Foundation

enum UserDefaultsClass {

    // MARK: - Keys (byte-identical to BarsysApp/Controllers/Login/UserDefaultsClass.swift)

    private enum Keys {
        // "Keychain" keys — stored in UserDefaults in the SwiftUI port
        static let userId        = "userId"
        static let sessionId     = "sessionId"
        static let email         = "user_email"
        static let phone         = "user_phone"
        static let sessionToken  = "session_token"
        static let name          = "name"
        static let accessToken   = "accessToken"
        static let countryName   = "countryName"
        static let deviceId      = "deviceId"
        static let profileImage  = "user_Profile_image"
        static let dob           = "user_dob"

        // UserDefaults keys (non-sensitive)
        static let lastConnectedDevice              = "lastConnectedDevice"
        static let lastConnectedDeviceTimeInterval  = "lastConnectedDeviceTimeInterval"
        static let savePreferencesUnit              = "savePreferencesUnit"
        static let updatedDataTimeStampForMixlistData = "updatedDataTimeStampForMixlistData"
        static let coreDataMixlistCount             = "coreDataMixlistCount"
        static let coasterConnectedNotFirstTime     = "coasterConnectedNotFirstTime"
        static let shakerConnectedNotFirstTime      = "shakerConnectedNotFirstTime"
        static let barsys360ConnectedNotFirstTime   = "barsys360ConnectedNotFirstTime"
        static let isFirstTimeShownDevicePopUp      = "isFirstTimeShownDevicePopUp"
        static let updatedDataTimeStampForFavourites = "updatedDataTimeStampForFavourites"
        static let updatedDataTimeStampForCacheRecipeData = "updatedDataTimeStampForCacheRecipeData"
        static let lastRatingViewShownTimeInterval  = "lastRatingViewShownTimeInterval"
        static let analyticsConsentGranted          = "analyticsConsentGranted"
        static let analyticsConsentPromptShown      = "analyticsConsentPromptShown"
        static let isManuallyDisconnected           = "kBarsysIsManuallyDisconnected"
        static let hasLaunchedBefore                = "hasLaunchedBefore"
        static let hasSeenTutorial                  = "hasSeenTutorial"

        // Storage cache keys — JSON-encoded recipes / mixlists / favourites
        // written by `MockStorageService.persistCache()`. Mirrors UIKit's
        // SQLite tables (`cocktails_recipes`, `mixlists`,
        // `favourite_recipes`). Listed here so `clearAll()` wipes them on
        // logout / delete-account / session-expired — matches UIKit
        // dropping the SQLite rows in those flows.
        static let storageRecipesCache              = "barsys_storage_recipes"
        static let storageMixlistsCache             = "barsys_storage_mixlists"
        static let storageFavoritesCache            = "barsys_storage_favorites"
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Store (sensitive — Keychain-backed in UIKit, UserDefaults here)

    static func storeName(_ value: String?)         { defaults.set(value, forKey: Keys.name) }
    static func storeEmail(_ value: String?)        { defaults.set(value, forKey: Keys.email) }
    static func storePhone(_ value: String?)        { defaults.set(value, forKey: Keys.phone) }
    static func storeDoB(_ value: String?)          { defaults.set(value, forKey: Keys.dob) }
    static func storeSessionToken(_ value: String?) { defaults.set(value, forKey: Keys.sessionToken) }
    static func storeAccessToken(_ value: String?)  { defaults.set(value, forKey: Keys.accessToken) }
    static func storeSessionId(_ value: String?)    { defaults.set(value, forKey: Keys.sessionId) }
    static func storeUserId(_ value: String?)       { defaults.set(value, forKey: Keys.userId) }
    static func storeCountryName(_ value: String?)  { defaults.set(value, forKey: Keys.countryName) }
    static func storeDeviceId(_ value: String?)     { defaults.set(value, forKey: Keys.deviceId) }
    static func storeProfileImage(_ value: String?) { defaults.set(value, forKey: Keys.profileImage) }

    // MARK: - Get

    static func getName() -> String?          { defaults.string(forKey: Keys.name) }
    static func getEmail() -> String?         { defaults.string(forKey: Keys.email) }
    static func getPhone() -> String?         { defaults.string(forKey: Keys.phone) }
    static func getDoB() -> String?           { defaults.string(forKey: Keys.dob) }
    static func getSessionToken() -> String?  { defaults.string(forKey: Keys.sessionToken) }
    static func getAccessToken() -> String?   { defaults.string(forKey: Keys.accessToken) }
    static func getSessionId() -> String?     { defaults.string(forKey: Keys.sessionId) }
    static func getUserId() -> String?        { defaults.string(forKey: Keys.userId) }
    static func getCountryName() -> String?   { defaults.string(forKey: Keys.countryName) }
    static func getProfileImage() -> String?  { defaults.string(forKey: Keys.profileImage) }

    static func getDeviceID() -> String {
        if let existing = defaults.string(forKey: Keys.deviceId), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        storeDeviceId(new)
        return new
    }

    // MARK: - Last connected device (UserDefaults-backed in UIKit)

    static func saveLastConnectedDevice(_ value: String?) {
        defaults.set(value, forKey: Keys.lastConnectedDevice)
    }
    static func getLastConnectedDevice() -> String? {
        defaults.string(forKey: Keys.lastConnectedDevice)
    }
    static func removeLastConnectedDevice() {
        defaults.removeObject(forKey: Keys.lastConnectedDevice)
    }

    static func saveLastConnectedDeviceTime(_ value: String?) {
        defaults.set(value, forKey: Keys.lastConnectedDeviceTimeInterval)
    }
    static func getLastConnectedDeviceTime() -> String? {
        defaults.string(forKey: Keys.lastConnectedDeviceTimeInterval)
    }
    static func removeLastConnectedDeviceTime() {
        defaults.removeObject(forKey: Keys.lastConnectedDeviceTimeInterval)
    }

    /// Convenience wrapper so older call sites that used `storeLastConnectedDevice`
    /// (my earlier port) still compile.
    static func storeLastConnectedDevice(_ value: String?) {
        saveLastConnectedDevice(value)
    }

    // MARK: - Preferences / flags

    static func savePreferencesUnit(_ value: String?) {
        defaults.set(value, forKey: Keys.savePreferencesUnit)
    }
    static func getPreferencesUnit() -> QuantityType {
        let raw = defaults.string(forKey: Keys.savePreferencesUnit)?.lowercased()
        if raw == "oz" { return .oz }
        return .ml
    }

    static func storeIsManuallyDisconnected(_ flag: Bool) {
        defaults.set(flag, forKey: Keys.isManuallyDisconnected)
    }
    static func getIsManuallyDisconnected() -> Bool {
        defaults.bool(forKey: Keys.isManuallyDisconnected)
    }

    static func hasLaunchedBefore() -> Bool {
        defaults.bool(forKey: Keys.hasLaunchedBefore)
    }
    static func markHasLaunchedBefore() {
        defaults.set(true, forKey: Keys.hasLaunchedBefore)
    }
    static func hasSeenTutorial() -> Bool {
        defaults.bool(forKey: Keys.hasSeenTutorial)
    }
    static func markHasSeenTutorial(_ value: Bool) {
        defaults.set(value, forKey: Keys.hasSeenTutorial)
    }

    // MARK: - Per-device first-time tutorial flags
    //
    // 1:1 ports of UIKit
    // `UserDefaultsClass.{save,get}{Coaster,Shaker,Barsys360}ConnectedNotFirstTime`.
    // Drive `DevicePairedViewModel.shouldHideTutorial()` and
    // `tutorialVideoURLAndMarkShown()` so the Explore-screen tutorial
    // card only appears the FIRST time a user connects each device kind.
    // Once the tutorial is shown, the flag is set to `true` and the
    // card stays hidden on subsequent connections.

    static func saveCoasterConnectedNotFirstTime(_ value: Bool) {
        defaults.set(value, forKey: Keys.coasterConnectedNotFirstTime)
    }
    static func getCoasterConnectedNotFirstTime() -> Bool {
        defaults.bool(forKey: Keys.coasterConnectedNotFirstTime)
    }

    static func saveShakerConnectedNotFirstTime(_ value: Bool) {
        defaults.set(value, forKey: Keys.shakerConnectedNotFirstTime)
    }
    static func getShakerConnectedNotFirstTime() -> Bool {
        defaults.bool(forKey: Keys.shakerConnectedNotFirstTime)
    }

    static func saveBarsys360ConnectedNotFirstTime(_ value: Bool) {
        defaults.set(value, forKey: Keys.barsys360ConnectedNotFirstTime)
    }
    static func getBarsys360ConnectedNotFirstTime() -> Bool {
        defaults.bool(forKey: Keys.barsys360ConnectedNotFirstTime)
    }

    // MARK: - Clear (logout)

    /// Ports `UserDefaultsClass.clearAll()` — wipes every key this class
    /// writes to, exactly matching the UIKit version.
    static func clearAll() {
        let keys: [String] = [
            Keys.email, Keys.phone, Keys.sessionToken, Keys.name,
            Keys.accessToken, Keys.sessionId, Keys.userId, Keys.countryName,
            Keys.deviceId, Keys.profileImage, Keys.dob,
            Keys.isFirstTimeShownDevicePopUp,
            Keys.updatedDataTimeStampForFavourites,
            Keys.updatedDataTimeStampForMixlistData,
            Keys.coreDataMixlistCount,
            Keys.coasterConnectedNotFirstTime,
            Keys.barsys360ConnectedNotFirstTime,
            Keys.lastConnectedDevice,
            Keys.updatedDataTimeStampForCacheRecipeData,
            Keys.isManuallyDisconnected,
            Keys.hasSeenTutorial,
            // Storage disk-cache keys — wipe alongside the rest so the
            // next user / fresh login doesn't see the previous user's
            // recipes / mixlists / favourites. UIKit drops the SQLite
            // rows here (`DBManager.deleteAllData`); we drop the
            // JSON-encoded equivalents.
            //
            // Kept for backwards compatibility with builds that
            // persisted the catalog in UserDefaults — current builds
            // write to file storage (see below) but a stale
            // UserDefaults blob from a pre-migration build still gets
            // cleared here so it never lingers post-logout.
            Keys.storageRecipesCache,
            Keys.storageMixlistsCache,
            Keys.storageFavoritesCache
        ]
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.synchronize()

        // The catalog cache moved from UserDefaults to JSON files in
        // the Caches directory (UserDefaults can't hold the ~5 MB
        // recipes payload). Delete the file copies on logout so the
        // next user / fresh login starts with an empty cache, just
        // like UIKit's `DBManager.deleteAllData()`.
        clearStorageCacheFiles()
    }

    /// Removes the catalog cache files that `MockStorageService`
    /// writes (`barsys_storage_recipes.json` etc.) so a logout / delete-
    /// account flow drops the on-disk JSON copies in addition to the
    /// in-memory dictionaries the auth-flow tear-down already clears.
    /// Filenames are duplicated from `MockStorageService` because the
    /// Services-side constants are private to that type.
    private static func clearStorageCacheFiles() {
        guard let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first else { return }
        let filenames = [
            "barsys_storage_recipes.json",
            "barsys_storage_mixlists.json",
            "barsys_storage_favorites.json"
        ]
        for filename in filenames {
            let url = cacheDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - AppStateManager (lightweight port of AppStateManager.swift)

@MainActor
final class AppStateManager: ObservableObject {
    static let shared = AppStateManager()

    @Published var isSpeakEasyCase: Bool = false
    @Published var recipeCache: [Recipe] = []
    /// Set to `true` by `DrinkCompleteView`'s "Craft again" button so
    /// the next time `CraftingView` appears it bypasses the
    /// "Ready to Pour?" confirmation alert and starts crafting
    /// immediately — matching UIKit's
    /// `craftingVc?.skipPourConfirmation = true` on re-entry
    /// (`DrinkCompleteViewController.swift` L262-287).
    ///
    /// Consumed once on the next `CraftingView.onAppear` and reset
    /// to `false` so subsequent manual pushes of CraftingView still
    /// show the pour confirmation.
    @Published var makeItAgainPending: Bool = false

    private init() {}

    func setSpeakEasyCaseState(_ value: Bool) {
        isSpeakEasyCase = value
    }

    func updateRecipeCache(_ recipes: [Recipe]) {
        recipeCache = recipes
    }

    /// Read-and-clear helper — returns the current
    /// `makeItAgainPending` value and resets it to `false` atomically
    /// so only the first `CraftingView.onAppear` after DrinkComplete's
    /// "Craft again" tap picks it up.
    func consumeMakeItAgainPending() -> Bool {
        let value = makeItAgainPending
        makeItAgainPending = false
        return value
    }
}

// MARK: - HapticService (ports HapticService.shared from UIKit)

enum HapticService {
    /// Mirrors UIKit `HapticService.shared.light()` — light tap used on
    /// most button presses (navigation, tab switches, pencil edits).
    static func light() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred()
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.medium()` — used on confirm
    /// actions: "Start Pouring" in CraftingVC, "Make It Again" return
    /// to crafting, etc. UIKit triggers this via
    /// `.medium` `UIImpactFeedbackGenerator`.
    static func medium() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        gen.impactOccurred()
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.heavy()` — reserved for hard
    /// commit actions (e.g. deleting an account).
    static func heavy() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.prepare()
        gen.impactOccurred()
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.selection()` — segmented
    /// controls, tab swaps, country-picker selection.
    static func selection() {
        #if canImport(UIKit)
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        gen.selectionChanged()
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.error()` — validation failures.
    static func error() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.error)
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.success()` — profile save,
    /// drink complete, favorite added.
    static func success() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.warning()`.
    static func warning() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.warning)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
